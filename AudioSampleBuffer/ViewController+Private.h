#import "ViewController.h"

#import <PhotosUI/PhotosUI.h>
#import <QuartzCore/CADisplayLink.h>

#import "AnimationCoordinator.h"
#import "AudioSpectrumPlayer.h"
#import "CyberpunkControlPanel.h"
#import "GalaxyControlPanel.h"
#import "LyricsEffectControlPanel.h"
#import "LyricsView.h"
#import "LyricsEditorViewController.h"
#import "LRCParser.h"
#import "MusicLibraryManager.h"
#import "PerformanceControlPanel.h"
#import "RhythmColorMaskEffect.h"
#import "SpectrumView.h"
#import "VinylRecordView.h"
#import "VisualEffectManager.h"

#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BackgroundMediaKind) {
    BackgroundMediaKindVideo = 0,
    BackgroundMediaKindLivePhoto = 1,
};

@interface BackgroundMediaItem : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) BackgroundMediaKind kind;
@property (nonatomic, strong) NSDate *addedDate;

+ (instancetype)itemWithFilePath:(NSString *)filePath kind:(BackgroundMediaKind)kind displayName:(NSString *)displayName;
- (NSString *)kindDisplayName;

@end

@interface ViewController ()

@property (nonatomic, assign) BOOL isInBackground;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) CAShapeLayer *backgroundRingLayer;
@property (nonatomic, strong) UIImageView *coverImageView;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITableView *backgroundMediaTableView;
@property (nonatomic, strong) UIView *backgroundMediaPanelView;
@property (nonatomic, strong) UILabel *backgroundMediaEmptyLabel;
@property (nonatomic, strong) UIButton *backgroundMediaButton;
@property (nonatomic, strong) UIButton *backgroundMediaEnableButton;
@property (nonatomic, strong) UIButton *backgroundMediaRhythmButton;
@property (nonatomic, strong) UIButton *importBackgroundMediaButton;
@property (nonatomic, strong) UIView *backgroundMediaRhythmControlsView;
@property (nonatomic, strong) UISlider *backgroundMediaRhythmRateSlider;
@property (nonatomic, strong) UISlider *backgroundMediaRhythmShakeSlider;
@property (nonatomic, strong) UISlider *backgroundMediaRhythmFlashSlider;
@property (nonatomic, strong) UISlider *backgroundMediaRhythmBoostSlider;     // 加速强度
@property (nonatomic, strong) UISlider *backgroundMediaRhythmBlurSlider;      // 运动模糊强度
@property (nonatomic, strong) NSMutableArray<BackgroundMediaItem *> *backgroundMediaItems;
@property (nonatomic, strong, nullable) BackgroundMediaItem *selectedBackgroundMediaItem;
@property (nonatomic, copy, nullable) NSString *playingBackgroundMediaIdentifier;
@property (nonatomic, assign) BOOL isBackgroundMediaPanelVisible;
@property (nonatomic, strong) AVQueuePlayer *backgroundVideoPlayer;
@property (nonatomic, strong) AVPlayerLooper *backgroundVideoLooper;
@property (nonatomic, strong) AVPlayerLayer *backgroundVideoLayer;
@property (nonatomic, strong) UIImageView *livePhotoPosterView;
@property (nonatomic, assign) BOOL isBackgroundMediaEffectActive;

@property (nonatomic, assign) BOOL isBackgroundRhythmEnabled;
@property (nonatomic, strong, nullable) CADisplayLink *backgroundRhythmDisplayLink;
@property (nonatomic, assign) CGFloat backgroundRhythmBaseRate;
@property (nonatomic, assign) CGFloat backgroundRhythmMaxRate;
@property (nonatomic, assign) CGFloat backgroundRhythmShakeIntensity;
@property (nonatomic, assign) CFTimeInterval backgroundRhythmLastBeatTime;
@property (nonatomic, assign) float backgroundRhythmSmoothedBass;
@property (nonatomic, assign) float backgroundRhythmPulse;
@property (nonatomic, assign) CGPoint backgroundRhythmShakeVelocity;
@property (nonatomic, assign) CGPoint backgroundRhythmShakeOffset;

// Beat-detection state (spectral flux + adaptive threshold)
@property (nonatomic, strong, nullable) NSMutableArray<NSNumber *> *backgroundRhythmLastSpectrum;
@property (nonatomic, strong, nullable) NSMutableArray<NSNumber *> *backgroundRhythmFluxHistory;
@property (nonatomic, assign) NSUInteger backgroundRhythmFluxHistoryIndex;
@property (nonatomic, assign) CFTimeInterval backgroundRhythmBeatPeriod;
// 高潮密集 beat 检测：只有当近 2s 内 beat 数 ≥ 阈值时才注入 motion blur，降 CPU 开销
@property (nonatomic, strong, nullable) NSMutableArray<NSNumber *> *backgroundRhythmRecentBeatTimes;
@property (nonatomic, assign) CFTimeInterval backgroundRhythmHighEnergyEndsAt;
@property (nonatomic, assign) NSInteger backgroundRhythmBeatCounter;
@property (nonatomic, assign) Float64 backgroundRhythmLoopAnchorSeconds;

// Visual-punch state
@property (nonatomic, assign) CGFloat backgroundRhythmScalePulse;       // zoom 脉冲（0..1）
@property (nonatomic, assign) CGFloat backgroundRhythmRotationPulse;    // 旋转脉冲（带方向，-1..1）
@property (nonatomic, assign) CGFloat backgroundRhythmRotationDir;      // 方向交替：+1 / -1
@property (nonatomic, assign) CGFloat backgroundRhythmFlashIntensity;   // 白闪强度（0..1，beat 触发，按帧衰减）
@property (nonatomic, assign) CGFloat backgroundRhythmFlashMaxAlpha;    // 闪屏 alpha 上限（由"闪屏" slider 控制，默认 0）
@property (nonatomic, strong, nullable) UIView *backgroundRhythmFlashView;

// 色散特效模块（"色散" slider 控制）：封装 alpha/位移衰减、beat 切色等内部状态。
// ViewController 只持有 view 引用、把它加进层级、转发 trigger / tick / reset。
@property (nonatomic, strong, nullable) RhythmColorMaskEffect *backgroundRhythmColorMaskView;

// Motionleap-style filter state (driven by display link, read by CIFilter compositor on bg queue)
@property (atomic, assign) float backgroundRhythmFilterIntensity;       // 0..1，beat 上为 1，每帧指数衰减
@property (atomic, assign) float backgroundRhythmFilterShiftMax;        // 当前 RGB-split 最大像素位移（px）
@property (atomic, assign) float backgroundRhythmFilterStrongMix;       // 0..1：当前节拍是否强拍（影响色相/暗化幅度）

// Beat boost (短暂快进 rate burst) 调度时刻；用于互踩判断
@property (nonatomic, assign) CFTimeInterval backgroundRhythmLastBoostEndsAt;

// 震颤方向轴：0=水平，1=垂直；每个 beat 切换一次（单轴抖更舒服，避免十字乱抖）
@property (nonatomic, assign) NSInteger backgroundRhythmShakeAxis;
// boost 期间的运动模糊强度（0..1）；与 rate burst 同步注入，driving CIFilter
@property (atomic, assign) float backgroundRhythmFilterMotionBlur;

@property (nonatomic, strong) NSMutableArray *audioArray;
@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) SpectrumView *spectrumView;

@property (nonatomic, strong) MusicLibraryManager *musicLibrary;
@property (nonatomic, strong) NSArray<MusicItem *> *displayedMusicItems;
@property (nonatomic, assign) MusicCategory currentCategory;
@property (nonatomic, strong) NSMutableArray<UIButton *> *categoryButtons;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UIButton *reloadButton;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *clearAICacheButton;
@property (nonatomic, strong) UIButton *aiSettingsButton;
@property (nonatomic, assign) MusicSortType currentSortType;
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, strong) UIScrollView *leftFunctionScrollView;

@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIView *playControlBarView;
@property (nonatomic, strong) UIButton *loopButton;
@property (nonatomic, assign) BOOL isSingleLoopMode;

@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger iu;
@property (nonatomic, strong) UIBezierPath *circlePath;
@property (nonatomic, strong) CALayer *xlayer;
@property (nonatomic, strong) CAEmitterLayer *leafEmitter;

@property (nonatomic, strong) AnimationCoordinator *animationCoordinator;

@property (nonatomic, strong) VisualEffectManager *visualEffectManager;
@property (nonatomic, strong) UIButton *effectSelectorButton;
@property (nonatomic, strong) UIButton *spectrumStyleButton;
@property (nonatomic, strong) GalaxyControlPanel *galaxyControlPanel;
@property (nonatomic, strong) UIButton *galaxyControlButton;
@property (nonatomic, strong) CyberpunkControlPanel *cyberpunkControlPanel;
@property (nonatomic, strong) UIButton *cyberpunkControlButton;
@property (nonatomic, strong) PerformanceControlPanel *performanceControlPanel;
@property (nonatomic, strong) UIButton *performanceControlButton;

@property (nonatomic, strong) UIButton *aiModeButton;

@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong, nullable) CADisplayLink *fpsDisplayLink;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;

@property (nonatomic, strong) LyricsView *lyricsView;
@property (nonatomic, strong) UIView *lyricsContainer;
@property (nonatomic, strong) NSArray<NSNumber *> *latestSpectrumData;
@property (nonatomic, strong) UIView *visualLyricsOverlayView;
@property (nonatomic, strong) NSArray<UILabel *> *visualLyricsOverlayLabels;
@property (nonatomic, strong) NSArray<NSValue *> *visualLyricsOverlayBaseCenters;
@property (nonatomic, assign) NSInteger visualLyricsHighlightSlot;
@property (nonatomic, copy) NSString *visualLyricsLastHighlightedText;

@property (nonatomic, strong) UIButton *karaokeButton;

@property (nonatomic, strong) LyricsEffectControlPanel *lyricsEffectPanel;
@property (nonatomic, strong) UIButton *lyricsEffectButton;
@property (nonatomic, strong) UIButton *importLyricsButton;
@property (nonatomic, strong) UIButton *lyricsTimingButton;

@property (nonatomic, strong) UIButton *toggleUIButton;
@property (nonatomic, assign) BOOL isUIHidden;
@property (nonatomic, strong) NSMutableArray<UIView *> *controlButtons;
@property (nonatomic, strong) UIButton *cloudButton;

@property (nonatomic, strong) UIView *mixAudioControlView;
@property (nonatomic, strong) UISwitch *mixAudioSwitch;

@property (nonatomic, strong) UIView *spectrumStylePanelView;
@property (nonatomic, strong) UIView *spectrumStyleCardView;
@property (nonatomic, strong) UISegmentedControl *spectrumLayoutSegmentedControl;
@property (nonatomic, strong) UISegmentedControl *spectrumColorModeSegmentedControl;
@property (nonatomic, strong) UISwitch *spectrumAutoColorSwitch;
@property (nonatomic, strong) UIScrollView *spectrumStyleScrollView;
@property (nonatomic, strong) UISlider *spectrumHueSlider;
@property (nonatomic, strong) UISlider *spectrumBrightnessSlider;
@property (nonatomic, strong) UISlider *spectrumOpacitySlider;
@property (nonatomic, strong) UISlider *spectrumPositionXSlider;
@property (nonatomic, strong) UISlider *spectrumPositionYSlider;
@property (nonatomic, strong) UISlider *spectrumScaleSlider;
@property (nonatomic, strong) UILabel *spectrumPositionHintLabel;

// 频谱位置长按拖拽（3s 长按 → 拖动）
@property (nonatomic, assign) CGPoint spectrumDragStartTouchPoint;
@property (nonatomic, assign) CGPoint spectrumDragStartLayoutOffset;
@property (nonatomic, strong, nullable) UILabel *spectrumDragHintLabel;

@property (nonatomic, strong, nullable) UIColor *backgroundMediaPreviewColor;

@property (nonatomic, assign) NSTimeInterval lastNowPlayingUpdateTime;

@property (nonatomic, strong) VinylRecordView *vinylRecordView;
@property (nonatomic, assign) BOOL isShowingVinylRecord;

@property (nonatomic, assign) BOOL wasPlayingBeforeInterruption;
@property (nonatomic, assign) BOOL wasPlayingBeforeBackground;
@property (nonatomic, assign) BOOL shouldPreventAutoResume;

@property (nonatomic, strong) UIButton *agentStatusButton;
@property (nonatomic, strong) UIView *agentStatusPanel;
@property (nonatomic, strong) UILabel *agentMetricsLabel;
@property (nonatomic, strong) UILabel *agentRecommendationsLabel;
@property (nonatomic, strong) UILabel *agentCostLabel;
@property (nonatomic, strong, nullable) NSTimer *agentStatusTimer;

@end

@interface ViewController (Visuals) <CAAnimationDelegate, VisualEffectManagerDelegate, GalaxyControlDelegate, CyberpunkControlDelegate, PerformanceControlDelegate>

- (void)setupVisualEffectSystem;
- (void)setupBackgroundMediaPanel;
- (void)setupNavigationBar;
- (void)setupEffectControls;
- (void)setupBackgroundLayers;
- (void)setupImageView;
- (void)bringControlButtonsToFront;
- (void)configInit;
- (void)createMusic;
- (void)setupAgentStatusPanel;
- (void)refreshSpectrumStyleButtonState;
- (void)refreshSpectrumAdaptiveThemeIfNeeded;
- (void)updateSpectrumLiveEditingAvailability;
- (nullable UIColor *)dominantColorForBackgroundMediaItem:(nullable BackgroundMediaItem *)item;

@end

@interface ViewController (Library) <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIDocumentPickerDelegate, PHPickerViewControllerDelegate>

- (void)ncmDecryptionCompleted:(NSNotification *)notification;
- (void)setupMusicLibrary;
- (void)refreshMusicList;
- (void)updateAudioSelection;
- (UIImage *)musicImageWithMusicURL:(NSURL *)url;
- (UIImage *)loadExternalCoverForMusicFile:(NSString *)musicFilePath;
- (void)showAlert:(NSString *)title message:(NSString *)message;

- (void)categoryButtonTapped:(UIButton *)sender;
- (void)sortButtonTapped:(UIButton *)sender;
- (void)reloadMusicLibraryButtonTapped:(UIButton *)sender;
- (void)importMusicButtonTapped:(UIButton *)sender;
- (void)backgroundMediaButtonTapped:(UIButton *)sender;
- (void)backgroundMediaEnableButtonTapped:(UIButton *)sender;
- (void)backgroundMediaCloseButtonTapped:(UIButton *)sender;
- (void)importBackgroundMediaButtonTapped:(UIButton *)sender;
- (void)backgroundMediaRhythmButtonTapped:(UIButton *)sender;
- (void)backgroundMediaRhythmRateSliderChanged:(UISlider *)sender;
- (void)backgroundMediaRhythmShakeSliderChanged:(UISlider *)sender;
- (void)backgroundMediaRhythmFlashSliderChanged:(UISlider *)sender;
- (void)backgroundMediaRhythmBoostSliderChanged:(UISlider *)sender;
- (void)backgroundMediaRhythmBlurSliderChanged:(UISlider *)sender;
- (void)toggleBackgroundMediaPanel:(BOOL)visible animated:(BOOL)animated;
- (void)reloadBackgroundMediaLibrary;
- (BOOL)isBackgroundMediaEnabled;
- (void)setBackgroundMediaEnabled:(BOOL)enabled;
- (void)refreshBackgroundMediaButtonState;
- (void)playSelectedBackgroundMediaIfNeeded;
- (void)stopBackgroundMediaPlayback;
- (void)updateBackgroundMediaEffectStateForEffect:(VisualEffectType)effectType;
- (void)clearAICacheButtonTapped:(UIButton *)sender;
- (void)aiSettingsButtonTapped:(UIButton *)sender;
- (void)dismissKeyboard;

@end

@interface ViewController (Lyrics) <LyricsEffectControlDelegate, LyricsEditorViewControllerDelegate>

- (void)setupLyricsView;
- (void)setupVisualLyricsOverlay;
- (void)updateVisualLyricsOverlayForCurrentIndex:(NSInteger)currentIndex;
- (void)animateVisualLyricsOverlayWithBass:(CGFloat)bass mid:(CGFloat)mid treble:(CGFloat)treble;
- (void)refreshVisualLyricsOverlayVisibility;
- (void)karaokeButtonTapped:(UIButton *)sender;
- (void)lyricsEffectButtonTapped:(UIButton *)sender;
- (void)importLyricsButtonTapped:(UIButton *)sender;
- (void)lyricsTimingButtonTapped:(UIButton *)sender;
- (void)openLRCFilePicker;
- (void)openBatchLRCFilePicker;
- (void)handleSingleLRCImport:(NSURL *)lrcURL;
- (void)handleBatchLRCImport:(NSArray<NSURL *> *)lrcURLs;

@end

@interface ViewController (Playback) <AudioSpectrumPlayerDelegate>

- (void)hadEnterBackGround;
- (void)hadEnterForeGround;
- (void)karaokeModeDidStart;
- (void)karaokeModeDidEnd;
- (void)setupRemoteCommandCenter;
- (void)updateNowPlayingInfoImmediate;
- (void)updateNowPlayingInfo;
- (void)pausePlayback;
- (void)resumePlayback;
- (void)deactivateAudioSessionForPause;
- (void)playCurrentTrack;
- (void)previousButtonTapped:(UIButton *)sender;
- (void)nextButtonTapped:(UIButton *)sender;
- (void)playPauseButtonTapped:(UIButton *)sender;
- (void)loopButtonTapped:(UIButton *)sender;
- (void)handleAudioSessionInterruption:(NSNotification *)notification;
- (void)handleAudioSessionRouteChange:(NSNotification *)notification;

@end

@interface ViewController (CloudDownloadPrivate)

- (void)cloudDownloadButtonTapped:(UIButton *)sender;

@end

NS_ASSUME_NONNULL_END
