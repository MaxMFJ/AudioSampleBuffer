#import "ViewController.h"

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
#import "SpectrumView.h"
#import "VinylRecordView.h"
#import "VisualEffectManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface ViewController ()

@property (nonatomic, assign) BOOL isInBackground;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) CAShapeLayer *backgroundRingLayer;
@property (nonatomic, strong) UIImageView *coverImageView;

@property (nonatomic, strong) UITableView *tableView;
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
- (void)setupNavigationBar;
- (void)setupEffectControls;
- (void)setupBackgroundLayers;
- (void)setupImageView;
- (void)configInit;
- (void)createMusic;
- (void)setupAgentStatusPanel;

@end

@interface ViewController (Library) <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIDocumentPickerDelegate>

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
