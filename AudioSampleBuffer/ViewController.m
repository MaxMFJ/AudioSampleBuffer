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
    [self.player stop];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView stopSpinning];
    }
}

- (void)playNext {
    NSLog(@"⏭️ 外部控制: 播放下一首");

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
