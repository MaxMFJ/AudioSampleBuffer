//
//  ViewController.m
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import "ViewController+Private.h"
#import "ViewController+CloudDownload.h"
#import "ViewController+PlaybackProgress.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface ViewController ()
{
    BOOL enterBackground;
    NSInteger index;
    CAShapeLayer *backLayers;
    UIImageView *imageView;
}
@end

@implementation ViewController

@synthesize isInBackground = enterBackground;
@synthesize currentIndex = index;
@synthesize backgroundRingLayer = backLayers;
@synthesize coverImageView = imageView;

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];

    self.shouldPreventAutoResume = NO;
    NSLog(@"📱 主界面出现，允许正常的音频操作");
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupNavigationBar];
    [self setupMusicLibrary];

    self.animationCoordinator = [[AnimationCoordinator alloc] initWithContainerView:self.view];
    [self setupVisualEffectSystem];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hadEnterBackGround) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hadEnterForeGround) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(karaokeModeDidStart) name:@"KaraokeModeDidStart" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(karaokeModeDidEnd) name:@"KaraokeModeDidEnd" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ncmDecryptionCompleted:) name:@"NCMDecryptionCompleted" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(platformMusicPlaybackReady:) name:@"PlatformMusicDidResolvePlayback" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(platformMusicQueueDidChange:) name:@"PlatformMusicQueueDidChange" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(platformMusicDidSelectLocalQueue:) name:@"PlatformMusicDidSelectLocalQueue" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(platformMusicLibraryDidUpdate:) name:@"PlatformMusicLibraryDidUpdate" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bilibiliMVUserDidSelectVideo:) name:@"BilibiliMVUserDidSelectVideo" object:nil];

    Class platformBridgeClass = NSClassFromString(@"PlatformMusicLibraryBridge");
    if (platformBridgeClass) {
        self.platformMusicBridge = [[platformBridgeClass alloc] init];
    } else {
        NSLog(@"❌ 平台歌单桥接器未加载，平台分类无法读取歌单");
        self.platformMusicStatusLabel.text = @"平台歌单模块未加载，请重新启动应用。";
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAudioSessionRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:[AVAudioSession sharedInstance]];

    NSLog(@"✅ 已注册音频会话中断和路由变化监听");

    self.view.backgroundColor = [UIColor blackColor];

    [self setupBackgroundLayers];
    [self setupImageView];
    [self configInit];
    [self createMusic];

    [self.animationCoordinator startAllAnimations];

    [self setupEffectControls];
    [self setupPlatformMusicAccountEntry];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.automaticVideoEnabled = [defaults objectForKey:@"AutomaticVideoMatchingEnabled"] ? [defaults boolForKey:@"AutomaticVideoMatchingEnabled"] : YES;
    self.signatureMVClip = [[SignatureMVClipPlayer alloc] initWithHostView:self.view];
    UILabel *mvMomentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    mvMomentLabel.hidden = YES;
    self.mvMomentStatusLabel = mvMomentLabel;
    [self setupLyricsView];

    // [self setupCloudDownloadFeature];

    [self player];
    [self setupRemoteCommandCenter];
    [self setupProgressView];
    [self setupAgentStatusPanel];
}

- (NSMutableArray *)audioArray {
    if (!_audioArray) {
        _audioArray = [NSMutableArray new];
    }
    return _audioArray;
}

- (AudioSpectrumPlayer *)player {
    if (!_player) {
        _player = [[AudioSpectrumPlayer alloc] init];
        _player.delegate = self;
    }
    return _player;
}

- (void)stopPlayback {
    NSLog(@"⏹️ 停止播放");
    [self resetMVMomentAnalysisForCurrentTrack];
    [self.signatureMVClip stop];
    [self.player stop];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView stopSpinning];
    }
}

- (void)setupPlatformMusicAccountEntry {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *icon = nil;
    if (@available(iOS 13.0, *)) {
        icon = [UIImage systemImageNamed:@"person.crop.circle.badge.music.note"] ?: [UIImage systemImageNamed:@"person.crop.circle"];
    }
    [button setImage:icon forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [UIColor colorWithRed:0.12 green:0.27 blue:0.40 alpha:0.9];
    button.layer.cornerRadius = 22;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    button.accessibilityLabel = @"音乐平台账号与歌单";
    button.tag = 47631;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;
    CGFloat topOffset = MAX(safeTop, 44.0) + 8;
    CGFloat btnSize = 44;
    CGFloat btnSpacing = 10;
    CGFloat rightX = self.view.bounds.size.width - btnSize - 12;
    CGFloat utilityRow = 6; // 排在现有六个右侧工具之后，保持在屏幕可见区域
    button.frame = CGRectMake(rightX,
                              topOffset + (btnSize + btnSpacing) * utilityRow,
                              44, 44);
    button.alpha = self.areUtilityControlsCollapsed ? 0.0 : 1.0;
    button.userInteractionEnabled = !self.areUtilityControlsCollapsed;
    [button addTarget:self action:@selector(openPlatformMusicAccounts) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    [self.controlButtons addObject:button];
    [self bringControlButtonsToFront];
}

- (void)openPlatformMusicAccounts {
    Class controllerClass = NSClassFromString(@"PlatformMusicAccountViewController");
    if (!controllerClass) return;
    UIViewController *controller = [[controllerClass alloc] init];
    controller.title = @"音乐平台";
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)platformMusicPlaybackReady:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self platformMusicPlaybackReady:notification]; });
        return;
    }
    NSDictionary *info = notification.userInfo;
    NSString *path = [info[@"filePath"] isKindOfClass:NSString.class] ? info[@"filePath"] : nil;
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *title = [info[@"title"] isKindOfClass:NSString.class] ? info[@"title"] : @"在线音乐";
    NSString *artist = [info[@"artist"] isKindOfClass:NSString.class] ? info[@"artist"] : @"";
    NSString *album = [info[@"album"] isKindOfClass:NSString.class] ? info[@"album"] : @"";
    NSString *artworkPath = [info[@"artworkFilePath"] isKindOfClass:NSString.class] ? info[@"artworkFilePath"] : nil;
    self.currentPlatformTrackInfo = [info copy];
    self.currentlyPlayingPlatformTrackID = [info[@"trackID"] isKindOfClass:NSString.class] ? info[@"trackID"] : nil;
    if (self.musicSourceControl.selectedSegmentIndex > 0 && self.currentlyPlayingPlatformTrackID.length > 0) {
        [self.tableView reloadData];
    }
    UIImage *artwork = artworkPath.length > 0 ? [UIImage imageWithContentsOfFile:artworkPath] : nil;
    [self displayAlbumArtwork:artwork songName:title];
    self.nowPlayingArtistLabel.text = artist;
    [self prepareAndPlayAudioPath:path title:title artist:artist];

    NSMutableDictionary *nowPlaying = [NSMutableDictionary dictionary];
    nowPlaying[MPMediaItemPropertyTitle] = title;
    nowPlaying[MPMediaItemPropertyArtist] = artist;
    if (album.length > 0) nowPlaying[MPMediaItemPropertyAlbumTitle] = album;
    NSNumber *duration = [info[@"duration"] isKindOfClass:NSNumber.class] ? info[@"duration"] : nil;
    if (duration.doubleValue > 0) nowPlaying[MPMediaItemPropertyPlaybackDuration] = duration;
    nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @0;
    nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] = @1;
    if (artwork) {
        MPMediaItemArtwork *itemArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artwork;
        }];
        nowPlaying[MPMediaItemPropertyArtwork] = itemArtwork;
    }
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlaying;
}

- (void)platformMusicLibraryDidUpdate:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self platformMusicLibraryDidUpdate:notification]; });
        return;
    }
    NSDictionary *info = notification.userInfo ?: @{};
    self.platformMusicRows = [info[@"rows"] isKindOfClass:NSArray.class] ? info[@"rows"] : @[];
    self.platformMusicRowsAreTracks = [info[@"mode"] isEqual:@"tracks"];
    self.platformMusicHasMoreRows = [info[@"hasMore"] boolValue];
    self.platformMusicStatusLabel.text = [info[@"message"] isKindOfClass:NSString.class] ? info[@"message"] : @"";
    [self.tableView reloadData];
}

- (void)platformMusicQueueDidChange:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self platformMusicQueueDidChange:notification]; });
        return;
    }
    self.isPlatformQueueActive = [notification.userInfo[@"active"] boolValue];
    if (!self.isPlatformQueueActive) {
        self.currentPlatformTrackInfo = nil;
        self.currentlyPlayingPlatformTrackID = nil;
    }
    NSString *error = [notification.userInfo[@"error"] isKindOfClass:NSString.class] ? notification.userInfo[@"error"] : nil;
    if (error.length > 0 && self.musicSourceControl.selectedSegmentIndex > 0) {
        self.platformMusicStatusLabel.text = error;
    }
}

- (void)platformMusicDidSelectLocalQueue:(NSNotification *)notification {
    NSArray<MusicItem *> *items = [notification.userInfo[@"items"] isKindOfClass:NSArray.class] ? notification.userInfo[@"items"] : nil;
    NSInteger index = [notification.userInfo[@"selectedIndex"] integerValue];
    if (items.count == 0 || index < 0 || index >= (NSInteger)items.count) return;
    self.displayedMusicItems = items;
    self.currentCategory = MusicCategoryAll;
    self.currentIndex = index;
    self.visibleMusicRowCount = MIN((NSInteger)items.count, MAX(20, index + 1));
    [self.tableView reloadData];
}

- (void)playNext {
    NSLog(@"⏭️ 外部控制: 播放下一首");

    if (self.isPlatformQueueActive) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PlatformMusicSkipNext" object:nil];
        return;
    }

    if (self.displayedMusicItems.count == 0) {
        NSLog(@"⚠️ 播放列表为空");
        return;
    }

    self.currentIndex += 1;
    if (self.currentIndex >= self.displayedMusicItems.count) {
        self.currentIndex = 0;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    [self.musicLibrary recordPlayForMusic:musicItem];

    [self updateAudioSelection];
    [self playCurrentTrack];
}

- (void)playPrevious {
    NSLog(@"⏮️ 外部控制: 播放上一首");

    if (self.isPlatformQueueActive) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PlatformMusicSkipPrevious" object:nil];
        return;
    }

    if (self.displayedMusicItems.count == 0) {
        NSLog(@"⚠️ 播放列表为空");
        return;
    }

    self.currentIndex -= 1;
    if (self.currentIndex < 0) {
        self.currentIndex = self.displayedMusicItems.count - 1;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    [self.musicLibrary recordPlayForMusic:musicItem];

    [self updateAudioSelection];
    [self playCurrentTrack];
}

- (void)dealloc {
    [self.fpsDisplayLink invalidate];
    self.fpsDisplayLink = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
