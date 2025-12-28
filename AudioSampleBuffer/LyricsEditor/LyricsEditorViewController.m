//
//  LyricsEditorViewController.m
//  AudioSampleBuffer
//
//  歌词打轴编辑器主控制器 - 手动为歌词添加时间戳并生成 LRC 文件
//

#import "LyricsEditorViewController.h"
#import "LRCGenerator.h"
#import "LyricsLineCell.h"
#import "LyricsTimingControlView.h"
#import "LyricsTextInputView.h"
#import "LocalLyricsListViewController.h"
#import <AVFoundation/AVFoundation.h>

/// 编辑器状态
typedef NS_ENUM(NSInteger, LyricsEditorState) {
    LyricsEditorStateInput,     // 歌词输入阶段
    LyricsEditorStateTiming,    // 打轴阶段
    LyricsEditorStateComplete   // 完成阶段
};

static NSString * const kLyricsLineCellID = @"LyricsLineCell";

@interface LyricsEditorViewController () <
    UITableViewDelegate,
    UITableViewDataSource,
    LyricsLineCellDelegate,
    LyricsTimingControlViewDelegate,
    LyricsTextInputViewDelegate
>

/// 当前状态
@property (nonatomic, assign) LyricsEditorState currentState;

/// LRC 生成器
@property (nonatomic, strong) LRCGenerator *lrcGenerator;

/// 音频播放器
@property (nonatomic, strong) AVPlayer *player;

/// 播放时间观察器
@property (nonatomic, strong) id timeObserver;

/// 歌词列表
@property (nonatomic, strong) UITableView *tableView;

/// 打轴控制面板
@property (nonatomic, strong) LyricsTimingControlView *controlView;

/// 歌词输入视图
@property (nonatomic, strong) LyricsTextInputView *inputView;

/// 导航栏标题
@property (nonatomic, strong) UILabel *navTitleLabel;

/// 完成按钮
@property (nonatomic, strong) UIBarButtonItem *doneButton;

/// 返回按钮
@property (nonatomic, strong) UIBarButtonItem *backButton;

/// 元信息编辑按钮
@property (nonatomic, strong) UIBarButtonItem *metadataButton;

/// 音频总时长
@property (nonatomic, assign) NSTimeInterval audioDuration;

/// 当前播放时间
@property (nonatomic, assign) NSTimeInterval currentPlayTime;

/// 是否正在播放
@property (nonatomic, assign) BOOL isPlaying;

/// 控制面板底部约束（用于键盘适配）
@property (nonatomic, strong) NSLayoutConstraint *controlViewBottomConstraint;

@end

@implementation LyricsEditorViewController

#pragma mark - Initialization

- (instancetype)initWithAudioFilePath:(NSString *)audioPath {
    if (self = [super init]) {
        _audioFilePath = audioPath;
        _audioFileURL = [NSURL fileURLWithPath:audioPath];
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithAudioFileURL:(NSURL *)audioURL {
    if (self = [super init]) {
        _audioFileURL = audioURL;
        _audioFilePath = audioURL.path;
        [self commonInit];
    }
    return self;
}

- (instancetype)init {
    if (self = [super init]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _lrcGenerator = [[LRCGenerator alloc] init];
    _currentState = LyricsEditorStateInput;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    [self setupNavigation];
    [self setupInputView];
    [self setupTableView];
    [self setupControlView];
    [self setupPlayer];
    [self setupKeyboardObservers];
    
    // 初始状态显示输入视图
    [self showInputView:YES animated:NO];
    
    // 如果有预设歌词，设置到输入框
    if (self.initialLyricsText.length > 0) {
        self.inputView.initialText = self.initialLyricsText;
    }
    
    // 如果有已有 LRC 内容，直接导入
    if (self.existingLRCContent.length > 0) {
        [self.lrcGenerator importFromLRC:self.existingLRCContent];
        [self transitionToTimingState];
    }
    
    // 设置元信息
    if (self.songTitle.length > 0) {
        self.lrcGenerator.metadata.title = self.songTitle;
    }
    if (self.artistName.length > 0) {
        self.lrcGenerator.metadata.artist = self.artistName;
    }
    if (self.albumName.length > 0) {
        self.lrcGenerator.metadata.album = self.albumName;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 🔧 显示导航栏（主界面隐藏了导航栏，push 过来需要重新显示）
    // 注意：使用 animated:NO 确保导航栏立即显示，避免 safe area 更新延迟
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    
    // 🔧 当 safe area 变化时（如导航栏显示/隐藏），强制更新布局
    [self.view setNeedsLayout];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self pausePlayback];
}

- (void)dealloc {
    [self removeTimeObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Setup

- (void)setupNavigation {
    // 标题
    _navTitleLabel = [[UILabel alloc] init];
    _navTitleLabel.text = @"歌词打轴";
    _navTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.navigationItem.titleView = _navTitleLabel;
    
    // 返回按钮
    _backButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                                                   style:UIBarButtonItemStylePlain
                                                  target:self
                                                  action:@selector(backButtonTapped)];
    self.navigationItem.leftBarButtonItem = _backButton;
    
    // 🔧 本地歌词列表按钮（替换原来的完成按钮）
    _doneButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"list.bullet"]
                                                   style:UIBarButtonItemStylePlain
                                                  target:self
                                                  action:@selector(localLyricsListButtonTapped)];
    
    // 元信息按钮
    _metadataButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(metadataButtonTapped)];
    
    self.navigationItem.rightBarButtonItems = @[_doneButton, _metadataButton];
}

- (void)setupInputView {
    _inputView = [[LyricsTextInputView alloc] init];
    _inputView.translatesAutoresizingMaskIntoConstraints = NO;
    _inputView.delegate = self;
    [self.view addSubview:_inputView];
    
    // 🔧 使用固定偏移量，确保内容在导航栏下方（导航栏高度约 44-56pt）
    CGFloat navBarOffset = 0;  // safeAreaLayoutGuide 应该已经处理了，但如果还有问题可以调整
    
    [NSLayoutConstraint activateConstraints:@[
        [_inputView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:navBarOffset],
        [_inputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_inputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_inputView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor systemBackgroundColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 56;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_tableView registerClass:[LyricsLineCell class] forCellReuseIdentifier:kLyricsLineCellID];
    [self.view addSubview:_tableView];
    
    // 🔧 使用 view.topAnchor + 导航栏高度偏移，确保内容在导航栏下方
    // 导航栏高度(44) + 状态栏高度(约47-59) ≈ 100pt（保守值）
    CGFloat topOffset = 100;
    
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:topOffset],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    
    _tableView.hidden = YES;
}

- (void)setupControlView {
    _controlView = [[LyricsTimingControlView alloc] init];
    _controlView.translatesAutoresizingMaskIntoConstraints = NO;
    _controlView.delegate = self;
    [self.view addSubview:_controlView];
    
    _controlViewBottomConstraint = [_controlView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.bottomAnchor constraintEqualToAnchor:_controlView.topAnchor],
        [_controlView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_controlView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _controlViewBottomConstraint,
        [_controlView.heightAnchor constraintEqualToConstant:280],
    ]];
    
    _controlView.hidden = YES;
}

- (void)setupPlayer {
    if (!self.audioFileURL) {
        return;
    }
    
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:self.audioFileURL];
    _player = [AVPlayer playerWithPlayerItem:playerItem];
    
    // 获取音频时长
    __weak typeof(self) weakSelf = self;
    [playerItem.asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            CMTime duration = playerItem.asset.duration;
            if (CMTIME_IS_VALID(duration)) {
                strongSelf.audioDuration = CMTimeGetSeconds(duration);
                [strongSelf.controlView updateTimeDisplay:0 duration:strongSelf.audioDuration];
            }
        });
    }];
    
    // 添加时间观察器
    [self addTimeObserver];
    
    // 监听播放结束
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerDidFinishPlaying:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];
}

- (void)addTimeObserver {
    if (self.timeObserver) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    CMTime interval = CMTimeMakeWithSeconds(0.05, NSEC_PER_SEC); // 50ms 更新一次
    
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:interval
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.currentPlayTime = CMTimeGetSeconds(time);
        [strongSelf.controlView updateTimeDisplay:strongSelf.currentPlayTime 
                                         duration:strongSelf.audioDuration];
    }];
}

- (void)removeTimeObserver {
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
}

- (void)setupKeyboardObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

#pragma mark - State Transitions

- (void)showInputView:(BOOL)show animated:(BOOL)animated {
    // 🔧 隐藏输入视图时，确保先关闭键盘
    if (!show) {
        [self.view endEditing:YES];
    }
    
    // 先设置最终状态（不使用动画 block 中的值，防止动画未完成时状态不一致）
    if (!show) {
        // 显示播放控制界面
        self.tableView.hidden = NO;
        self.controlView.hidden = NO;
        self.tableView.alpha = 1.0;
        self.controlView.alpha = 1.0;
        
        // 确保 tableView 和 controlView 在 inputView 上面
        [self.view bringSubviewToFront:self.tableView];
        [self.view bringSubviewToFront:self.controlView];
    } else {
        // 显示输入界面
        self.inputView.hidden = NO;
        self.inputView.alpha = 1.0;
        [self.view bringSubviewToFront:self.inputView];
    }
    
    void (^updateUI)(void) = ^{
        if (!show) {
            self.inputView.alpha = 0.0;
        } else {
            self.tableView.alpha = 0.0;
            self.controlView.alpha = 0.0;
        }
    };
    
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (!show) {
            self.inputView.hidden = YES;
        } else {
            self.tableView.hidden = YES;
            self.controlView.hidden = YES;
        }
        
        // 强制布局更新
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:updateUI completion:completion];
    } else {
        updateUI();
        completion(YES);
    }
}

- (void)transitionToTimingState {
    self.currentState = LyricsEditorStateTiming;
    
    // 🔧 确保键盘关闭，避免键盘背景残留
    [self.view endEditing:YES];
    
    [self showInputView:NO animated:YES];
    [self.tableView reloadData];
    
    // 更新控制面板
    [self updateControlViewForCurrentLine];
    [self updateStampProgress];
    
    // 加载波形显示
    if (self.audioFilePath) {
        [self.controlView loadWaveformFromFile:self.audioFilePath];
    } else if (self.audioFileURL) {
        [self.controlView loadWaveformFromFile:self.audioFileURL.path];
    }
    
    // 滚动到当前行
    [self scrollToCurrentLine];
    
    // 更新导航标题
    self.navTitleLabel.text = @"打轴中...";
}

- (void)transitionToCompleteState {
    self.currentState = LyricsEditorStateComplete;
    
    // 暂停播放
    [self pausePlayback];
    
    // 更新 UI
    self.navTitleLabel.text = @"打轴完成";
    
    // 成功反馈
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    
    // 🔧 只有在所有歌词打轴完成后才显示完成弹窗
    [self showCompletionAlert];
}

#pragma mark - Playback Control

- (void)startTimingProcess {
    if (self.lrcGenerator.lines.count == 0) {
        return;
    }
    
    [self resumePlayback];
}

- (void)pausePlayback {
    [self.player pause];
    self.isPlaying = NO;
    self.controlView.isPlaying = NO;
}

- (void)resumePlayback {
    [self.player play];
    self.isPlaying = YES;
    self.controlView.isPlaying = YES;
}

- (void)togglePlayback {
    if (self.isPlaying) {
        [self pausePlayback];
    } else {
        [self resumePlayback];
    }
}

- (void)seekToTime:(NSTimeInterval)time {
    CMTime targetTime = CMTimeMakeWithSeconds(time, NSEC_PER_SEC);
    [self.player seekToTime:targetTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)seekByDelta:(NSTimeInterval)delta {
    NSTimeInterval newTime = MAX(0, MIN(self.audioDuration, self.currentPlayTime + delta));
    [self seekToTime:newTime];
}

#pragma mark - Timing Operations

- (void)stampCurrentLine {
    if (self.currentState != LyricsEditorStateTiming) {
        return;
    }
    
    NSInteger currentIndex = self.lrcGenerator.currentIndex;
    
    if (currentIndex >= self.lrcGenerator.lines.count) {
        return;
    }
    
    // 记录当前时间
    BOOL success = [self.lrcGenerator stampCurrentLineWithTime:self.currentPlayTime];
    
    if (success) {
        // 触觉反馈
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
        
        // 动画
        [self.controlView playStampSuccessAnimation];
        
        // 刷新表格
        NSIndexPath *oldIndexPath = [NSIndexPath indexPathForRow:currentIndex inSection:0];
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:self.lrcGenerator.currentIndex inSection:0];
        
        [self.tableView reloadRowsAtIndexPaths:@[oldIndexPath] withRowAnimation:UITableViewRowAnimationNone];
        
        if (newIndexPath.row < self.lrcGenerator.lines.count) {
            [self.tableView reloadRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationNone];
        }
        
        // 更新控制面板
        [self updateControlViewForCurrentLine];
        [self updateStampProgress];
        
        // 滚动到当前行
        [self scrollToCurrentLine];
        
        // 检查是否完成
        if (self.lrcGenerator.isComplete) {
            [self transitionToCompleteState];
        }
    }
}

- (void)goBackToPreviousLine {
    NSInteger oldIndex = self.lrcGenerator.currentIndex;
    
    if ([self.lrcGenerator goBackToPreviousLine]) {
        // 刷新表格
        NSIndexPath *oldIndexPath = [NSIndexPath indexPathForRow:oldIndex inSection:0];
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:self.lrcGenerator.currentIndex inSection:0];
        
        [self.tableView reloadRowsAtIndexPaths:@[oldIndexPath, newIndexPath] withRowAnimation:UITableViewRowAnimationNone];
        
        // 更新控制面板
        [self updateControlViewForCurrentLine];
        [self updateStampProgress];
        
        // 滚动到当前行
        [self scrollToCurrentLine];
        
        // 触觉反馈
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
}

- (void)skipCurrentLine {
    NSInteger oldIndex = self.lrcGenerator.currentIndex;
    
    if ([self.lrcGenerator goToNextLine]) {
        // 刷新表格
        NSIndexPath *oldIndexPath = [NSIndexPath indexPathForRow:oldIndex inSection:0];
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:self.lrcGenerator.currentIndex inSection:0];
        
        [self.tableView reloadRowsAtIndexPaths:@[oldIndexPath, newIndexPath] withRowAnimation:UITableViewRowAnimationNone];
        
        // 更新控制面板
        [self updateControlViewForCurrentLine];
        
        // 滚动到当前行
        [self scrollToCurrentLine];
    }
}

#pragma mark - UI Updates

- (void)updateControlViewForCurrentLine {
    NSInteger currentIndex = self.lrcGenerator.currentIndex;
    
    if (currentIndex < self.lrcGenerator.lines.count) {
        LRCEditableLine *line = self.lrcGenerator.lines[currentIndex];
        [self.controlView setCurrentLyricPreview:line.text];
        [self.controlView setStampButtonEnabled:YES];
    } else {
        [self.controlView setCurrentLyricPreview:@"已完成所有歌词打轴"];
        [self.controlView setStampButtonEnabled:NO];
    }
}

- (void)updateStampProgress {
    [self.controlView updateStampProgress:self.lrcGenerator.timestampedCount 
                                    total:self.lrcGenerator.lines.count];
    
    // 更新波形上的时间标记
    NSMutableArray<NSNumber *> *timestamps = [NSMutableArray array];
    for (LRCEditableLine *line in self.lrcGenerator.lines) {
        if (line.isTimestamped) {
            [timestamps addObject:@(line.timestamp)];
        }
    }
    [self.controlView updateWaveformMarkers:timestamps];
}

- (void)scrollToCurrentLine {
    NSInteger currentIndex = self.lrcGenerator.currentIndex;
    
    if (currentIndex < self.lrcGenerator.lines.count) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:currentIndex inSection:0];
        [self.tableView scrollToRowAtIndexPath:indexPath 
                              atScrollPosition:UITableViewScrollPositionMiddle 
                                      animated:YES];
    }
}

#pragma mark - Actions

- (void)backButtonTapped {
    if (self.currentState == LyricsEditorStateTiming && self.lrcGenerator.timestampedCount > 0) {
        // 有未保存的进度，确认退出
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确定退出？"
                                                                       message:@"当前打轴进度将不会保存"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self dismissOrPop];
        }]];
        
        [self presentViewController:alert animated:YES completion:nil];
    } else if (self.currentState == LyricsEditorStateTiming) {
        // 回到输入状态
        self.currentState = LyricsEditorStateInput;
        [self.lrcGenerator.lines removeAllObjects];
        [self showInputView:YES animated:YES];
        self.navTitleLabel.text = @"歌词打轴";
    } else {
        [self dismissOrPop];
    }
}

- (void)dismissOrPop {
    [self pausePlayback];
    
    // 判断是否是导航控制器的根视图控制器（模态展示的情况）
    BOOL isRootOfNavigationController = (self.navigationController && 
                                          self.navigationController.viewControllers.firstObject == self);
    
    // 判断是否是模态展示
    BOOL isPresentedModally = (self.presentingViewController != nil || 
                               self.navigationController.presentingViewController != nil);
    
    if (isRootOfNavigationController && isPresentedModally) {
        // 模态展示的导航控制器根视图 - dismiss 整个导航控制器
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        // 在导航栈中且不是根视图 - pop
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        // 直接模态展示 - dismiss 自己
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        // 兜底处理
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
    if ([self.delegate respondsToSelector:@selector(lyricsEditorDidCancel:)]) {
        [self.delegate lyricsEditorDidCancel:self];
    }
}

- (void)localLyricsListButtonTapped {
    // 打开本地歌词列表管理页面
    LocalLyricsListViewController *listVC = [[LocalLyricsListViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)metadataButtonTapped {
    [self showMetadataEditor];
}

#pragma mark - Alerts & Sheets

- (void)showCompletionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎉 打轴完成！"
                                                                   message:[NSString stringWithFormat:@"已为 %ld 句歌词添加时间戳", (long)self.lrcGenerator.lines.count]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"导出 LRC" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showExportOptions];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"继续调整" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showExportOptions {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"导出 LRC"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"保存到本地" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self saveLRCToLocal];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制到剪贴板" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self copyLRCToClipboard];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self shareLRC];
    }]];
    
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad 适配
    sheet.popoverPresentationController.barButtonItem = self.doneButton;
    
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showMetadataEditor {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"歌曲信息"
                                                                   message:@"设置 LRC 文件的元信息"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"歌曲标题";
        textField.text = self.lrcGenerator.metadata.title;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"艺术家";
        textField.text = self.lrcGenerator.metadata.artist;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"专辑";
        textField.text = self.lrcGenerator.metadata.album;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"制作者";
        textField.text = self.lrcGenerator.metadata.by;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.lrcGenerator.metadata.title = alert.textFields[0].text;
        self.lrcGenerator.metadata.artist = alert.textFields[1].text;
        self.lrcGenerator.metadata.album = alert.textFields[2].text;
        self.lrcGenerator.metadata.by = alert.textFields[3].text;
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Export

- (void)saveLRCToLocal {
    // 生成文件名
    NSString *fileName = self.lrcGenerator.metadata.title ?: @"lyrics";
    if (self.lrcGenerator.metadata.artist.length > 0) {
        fileName = [NSString stringWithFormat:@"%@ - %@", self.lrcGenerator.metadata.artist, fileName];
    }
    
    NSError *error = nil;
    NSString *savedPath = [self.lrcGenerator saveLRCWithFileName:fileName error:&error];
    
    if (savedPath) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存成功"
                                                                       message:[NSString stringWithFormat:@"已保存到：\n%@", savedPath]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        
        if ([self.delegate respondsToSelector:@selector(lyricsEditor:didSaveLRCToPath:)]) {
            [self.delegate lyricsEditor:self didSaveLRCToPath:savedPath];
        }
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)copyLRCToClipboard {
    NSString *content = [self.lrcGenerator generateLRCContent];
    [UIPasteboard generalPasteboard].string = content;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                   message:@"LRC 内容已复制到剪贴板"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    
    if ([self.delegate respondsToSelector:@selector(lyricsEditor:didFinishWithLRCContent:)]) {
        [self.delegate lyricsEditor:self didFinishWithLRCContent:content];
    }
}

- (void)shareLRC {
    NSString *content = [self.lrcGenerator generateLRCContent];
    
    // 创建临时文件
    NSString *fileName = self.lrcGenerator.metadata.title ?: @"lyrics";
    if (self.lrcGenerator.metadata.artist.length > 0) {
        fileName = [NSString stringWithFormat:@"%@ - %@", self.lrcGenerator.metadata.artist, fileName];
    }
    fileName = [fileName stringByAppendingPathExtension:@"lrc"];
    
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
    
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                             applicationActivities:nil];
    
    activityVC.popoverPresentationController.barButtonItem = self.doneButton;
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (NSString *)currentLRCContent {
    return [self.lrcGenerator generateLRCContent];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.lrcGenerator.lines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LyricsLineCell *cell = [tableView dequeueReusableCellWithIdentifier:kLyricsLineCellID forIndexPath:indexPath];
    
    LRCEditableLine *line = self.lrcGenerator.lines[indexPath.row];
    BOOL isCurrent = (indexPath.row == self.lrcGenerator.currentIndex);
    
    [cell configureWithLine:line isCurrent:isCurrent index:indexPath.row];
    cell.delegate = self;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 点击跳转到指定行
    NSInteger oldIndex = self.lrcGenerator.currentIndex;
    [self.lrcGenerator goToLineAtIndex:indexPath.row];
    
    // 刷新表格
    NSMutableArray *indexPaths = [NSMutableArray arrayWithObject:indexPath];
    if (oldIndex != indexPath.row && oldIndex < self.lrcGenerator.lines.count) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:oldIndex inSection:0]];
    }
    [tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
    
    // 更新控制面板
    [self updateControlViewForCurrentLine];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView 
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    // 清除时间戳操作
    UIContextualAction *clearAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                              title:@"清除"
                                                                            handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self.lrcGenerator clearTimestampAtIndex:indexPath.row];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self updateStampProgress];
        completionHandler(YES);
    }];
    clearAction.backgroundColor = [UIColor systemOrangeColor];
    
    // 删除操作
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"删除"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self.lrcGenerator removeLineAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateStampProgress];
        [self updateControlViewForCurrentLine];
        completionHandler(YES);
    }];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, clearAction]];
}

#pragma mark - LyricsLineCellDelegate

- (void)lyricsLineCell:(LyricsLineCell *)cell didAdjustTimestamp:(NSTimeInterval)delta {
    [self.lrcGenerator adjustTimestamp:delta forLineAtIndex:cell.lineIndex];
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:cell.lineIndex inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    
    // 触觉反馈
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

#pragma mark - LyricsTimingControlViewDelegate

- (void)timingControlViewDidTapPlayPause:(LyricsTimingControlView *)view {
    [self togglePlayback];
}

- (void)timingControlViewDidTapStamp:(LyricsTimingControlView *)view {
    [self stampCurrentLine];
}

- (void)timingControlViewDidTapGoBack:(LyricsTimingControlView *)view {
    [self goBackToPreviousLine];
}

- (void)timingControlViewDidTapSkip:(LyricsTimingControlView *)view {
    [self skipCurrentLine];
}

- (void)timingControlView:(LyricsTimingControlView *)view didSeekToProgress:(float)progress {
    NSTimeInterval targetTime = self.audioDuration * progress;
    [self seekToTime:targetTime];
}

- (void)timingControlView:(LyricsTimingControlView *)view didSeekBySeconds:(NSTimeInterval)seconds {
    [self seekByDelta:seconds];
}

- (void)timingControlView:(LyricsTimingControlView *)view didSeekToTime:(NSTimeInterval)time {
    [self seekToTime:time];
}

#pragma mark - LyricsTextInputViewDelegate

- (void)lyricsTextInputView:(LyricsTextInputView *)view didConfirmWithText:(NSString *)text {
    // 导入歌词
    [self.lrcGenerator importFromText:text];
    
    if (self.lrcGenerator.lines.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无有效歌词"
                                                                       message:@"请检查输入的歌词文本"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // 切换到打轴状态
    [self transitionToTimingState];
}

- (void)lyricsTextInputViewDidCancel:(LyricsTextInputView *)view {
    [self dismissOrPop];
}

#pragma mark - Player Notifications

- (void)playerDidFinishPlaying:(NSNotification *)notification {
    self.isPlaying = NO;
    self.controlView.isPlaying = NO;
    
    // 可以选择自动从头开始或暂停
    [self seekToTime:0];
}

#pragma mark - Keyboard Handling

- (void)keyboardWillShow:(NSNotification *)notification {
    // 输入视图状态下不需要调整控制面板
    if (self.currentState == LyricsEditorStateInput) {
        return;
    }
    
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    self.controlViewBottomConstraint.constant = -keyboardFrame.size.height;
    
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    if (self.currentState == LyricsEditorStateInput) {
        return;
    }
    
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    self.controlViewBottomConstraint.constant = 0;
    
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Key Commands (外接键盘支持)

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands {
    if (self.currentState != LyricsEditorStateTiming) {
        return nil;
    }
    
    return @[
        // 空格键打轴
        [UIKeyCommand keyCommandWithInput:@" " 
                            modifierFlags:0 
                                   action:@selector(spaceKeyPressed)],
        
        // 回车键打轴
        [UIKeyCommand keyCommandWithInput:@"\r" 
                            modifierFlags:0 
                                   action:@selector(stampCurrentLine)],
        
        // 左方向键回退
        [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow 
                            modifierFlags:0 
                                   action:@selector(leftArrowPressed)],
        
        // 右方向键快进
        [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow 
                            modifierFlags:0 
                                   action:@selector(rightArrowPressed)],
        
        // 上方向键回退一行
        [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow 
                            modifierFlags:0 
                                   action:@selector(goBackToPreviousLine)],
        
        // P 键播放/暂停
        [UIKeyCommand keyCommandWithInput:@"p" 
                            modifierFlags:0 
                                   action:@selector(togglePlayback)],
    ];
}

- (void)spaceKeyPressed {
    [self stampCurrentLine];
}

- (void)leftArrowPressed {
    [self seekByDelta:-2.0];
}

- (void)rightArrowPressed {
    [self seekByDelta:2.0];
}

@end

