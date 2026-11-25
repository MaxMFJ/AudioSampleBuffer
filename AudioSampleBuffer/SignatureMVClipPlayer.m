#import "SignatureMVClipPlayer.h"
#import "AudioSampleBuffer-Swift.h"

#import <AVFoundation/AVFoundation.h>
#import <math.h>


@interface SignatureMVClipPlayer ()
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, copy) NSString *songTitle;
@property (nonatomic, copy) NSString *loggedTitle;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, assign) NSTimeInterval clipDuration;
@property (nonatomic, assign) BOOL prepared;
@property (nonatomic, assign) BOOL showing;
@property (nonatomic, assign) BOOL seeking;
@property (nonatomic, assign) NSTimeInterval lastSeekAt;
@property (nonatomic, assign) BOOL remoteMode;
@property (nonatomic, assign) NSTimeInterval preloadedStart;
@property (nonatomic, assign) NSInteger remoteRequestToken;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *remoteMoments;
@property (nonatomic, strong) AVPlayerItem *remoteItem;
@property (nonatomic, strong) BiliPlaybackSession *playbackSession;
@property (nonatomic, assign) NSUInteger operationGeneration;
@property (nonatomic, assign) NSTimeInterval latestSongTime;
@property (nonatomic, assign) BOOL latestPlaying;
@end

@implementation SignatureMVClipPlayer

- (BOOL)isShowingVideo {
    return self.showing;
}

- (instancetype)initWithHostView:(UIView *)hostView {
    self = [super init];
    if (self) {
        _hostView = hostView;
        _clipDuration = 33.7;
    }
    return self;
}

- (void)noteSongTitle:(NSString *)title {
    self.songTitle = title;
}

- (void)prepareResolvedVideoURL:(NSURL *)url song:(NSString *)song {
    [self stop];
    self.songTitle = song;
    self.remoteMode = YES;
    self.latestSongTime = 0;
    self.lastSeekAt = 0;
    self.preloadedStart = -1;
    __weak typeof(self) weakSelf = self;
    NSInteger token = self.remoteRequestToken;
    self.playbackSession = [[BiliPlaybackSession alloc] initWithURL:url automaticallyResume:NO itemChanged:^(AVPlayerItem *item) {
        typeof(self) owner = weakSelf;
        if (!owner || owner.remoteRequestToken != token) return;
        owner.operationGeneration += 1;
        owner.seeking = NO;
        owner.preloadedStart = -1;
        owner.lastSeekAt = 0;
        owner.remoteItem = item;
        [owner hide];
    } status:^(NSString *state) {
        typeof(self) owner = weakSelf;
        if (!owner || owner.remoteRequestToken != token) return;
        if ([state isEqualToString:@"ready"]) {
            double duration = CMTimeGetSeconds(owner.remoteItem.duration);
            if (isfinite(duration)) owner.clipDuration = duration;
        } else {
            [owner hide];
        }
    }];
    self.player = self.playbackSession.player;
    self.player.volume = 0;
    self.player.automaticallyWaitsToMinimizeStalling = YES;
    self.playerLayer.player = self.player;
    self.prepared = YES;
}

- (void)updateWithTitle:(NSString *)title time:(NSTimeInterval)time playing:(BOOL)playing {
    [self updateWithTitle:title time:time playing:playing mvMoments:self.remoteMoments ?: @[]];
}

- (void)updateWithTitle:(NSString *)title time:(NSTimeInterval)time playing:(BOOL)playing
              mvMoments:(NSArray<NSDictionary<NSString *, id> *> *)moments {
    BOOL timelineJump = fabs(time - self.latestSongTime) > 1.0;
    if (timelineJump) {
        self.lastSeekAt = 0;
        self.operationGeneration += 1;
        [self.player cancelPendingPrerolls];
        [self.player.currentItem cancelPendingSeeks];
        self.seeking = NO;
        self.preloadedStart = -1;
    }
    self.latestSongTime = time;
    self.latestPlaying = playing;
    if (self.remoteMode) {
        self.remoteMoments = moments ?: @[];
        NSDictionary *activeMoment = nil;
        NSDictionary *upcomingMoment = nil;
        for (NSDictionary *moment in self.remoteMoments) {
            NSTimeInterval start = [(NSNumber *)moment[@"start"] doubleValue];
            NSTimeInterval end = [(NSNumber *)moment[@"end"] doubleValue];
            if (time >= start && time < end) { activeMoment = moment; break; }
            if (!upcomingMoment && start >= time && start - time <= 5.0) upcomingMoment = moment;
        }
        AVPlayerItem *item = self.remoteItem;
        if ((!activeMoment && !upcomingMoment) || !item || self.player.currentItem != item) {
            if (self.seeking) {
                self.operationGeneration += 1;
                [self.player cancelPendingPrerolls];
                [item cancelPendingSeeks];
                self.seeking = NO;
            }
            self.preloadedStart = -1;
            [self hide];
            return;
        }
        if (item.status != AVPlayerItemStatusReadyToPlay) {
            [self hide];
            return;
        }
        NSDictionary *selected = activeMoment ?: upcomingMoment;
        NSTimeInterval songStart = [selected[@"start"] doubleValue];
        NSTimeInterval videoStart = [selected[@"videoStart"] doubleValue];
        NSTimeInterval target = MAX(0, videoStart + (activeMoment ? time - songStart : 0));
        if (self.clipDuration > 0 && target >= self.clipDuration - 0.1) {
            [self hide];
            return;
        }
        if (!playing) {
            // Keep the current frame visible while the master audio is paused.
            if (!activeMoment) [self hide];
            [self.player pause];
            return;
        }
        if (!activeMoment) {
            [self hide];
            if (self.seeking || self.preloadedStart == target) return;
            self.seeking = YES;
            self.preloadedStart = target;
            NSUInteger generation = ++self.operationGeneration;
            __weak typeof(self) weakSelf = self;
            NSLog(@"[BiliMV] 提前准备候选片段 %.1f 秒", target);
            [self.player seekToTime:CMTimeMakeWithSeconds(target, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    typeof(self) owner = weakSelf;
                    if (!owner || generation != owner.operationGeneration || owner.remoteItem != item) return;
                    if (!finished) { owner.seeking = NO; owner.preloadedStart = -1; return; }
                    [owner.player prerollAtRate:1 completionHandler:^(BOOL ready) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            typeof(self) owner = weakSelf;
                            if (!owner || generation != owner.operationGeneration || owner.remoteItem != item) return;
                            [owner.player pause];
                            owner.seeking = NO;
                            if (!ready) owner.preloadedStart = -1;
                        });
                    }];
                });
            }];
            return;
        }
        if (self.seeking) return;
        NSTimeInterval actual = CMTimeGetSeconds(self.player.currentTime);
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        BOOL drifted = !isfinite(actual) || fabs(actual - target) > (self.showing ? 1.0 : 0.35);
        BOOL waitingForBuffer = self.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
        // A visible interval stays on screen during buffering and synchronization.
        // Give each seek time to settle instead of repeatedly pausing and hiding.
        if ((timelineJump || (drifted && !waitingForBuffer)) && now - self.lastSeekAt >= 2.0) {
            self.seeking = YES;
            self.lastSeekAt = now;
            NSUInteger generation = ++self.operationGeneration;
            NSTimeInterval intervalStart = [activeMoment[@"start"] doubleValue];
            NSTimeInterval intervalEnd = [activeMoment[@"end"] doubleValue];
            __weak typeof(self) weakSelf = self;
            [self.player seekToTime:CMTimeMakeWithSeconds(target, 600)
                    toleranceBefore:CMTimeMakeWithSeconds(0.1, 600)
                     toleranceAfter:CMTimeMakeWithSeconds(0.1, 600)
                  completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    typeof(self) owner = weakSelf;
                    if (!owner || owner.operationGeneration != generation || owner.remoteItem != item) return;
                    owner.seeking = NO;
                    if (finished && owner.latestPlaying && owner.latestSongTime >= intervalStart && owner.latestSongTime < intervalEnd) {
                        // Start immediately; waiting for another clock tick can
                        // otherwise turn startup latency into another seek.
                        [owner.player play];
                    }
                });
            }];
            return;
        }
        BOOL buffered = item.isPlaybackLikelyToKeepUp;
        for (NSValue *value in item.loadedTimeRanges) {
            CMTimeRange range = value.CMTimeRangeValue;
            double begin = CMTimeGetSeconds(range.start), end = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
            if (target >= begin && end >= target + 0.25) buffered = YES;
        }
        // Readiness gates the first appearance only. A buffer dip preserves
        // the visible layer and AVPlayer's own recovery of the same item.
        if (!self.showing) {
            if (!buffered) return;
            NSLog(@"[BiliMV] 来源时间表触发，歌曲 %.1f 秒", time);
            [self show];
            self.showing = YES;
        }
        if (self.player.rate == 0 && !waitingForBuffer) [self.player play];
        return;
    }

    // No verified schedule means no video; never fall back to hardcoded times.
    [self hide];
}

- (void)stop {
    self.operationGeneration += 1;
    self.preloadedStart = -1;
    self.remoteRequestToken += 1;
    self.seeking = NO;
    [self.playbackSession stop];
    self.playbackSession = nil;
    self.remoteItem = nil;
    self.remoteMode = NO;
    self.songTitle = nil;
    self.remoteMoments = @[];
    [self.player pause];
    self.playerLayer.player = nil;
    self.player = nil;
    self.prepared = NO;
    self.clipDuration = 0;
    [self hide];
}

- (UIWindowScene *)activeScene {
    UIWindowScene *scene = self.hostView.window.windowScene;
    if (scene) return scene;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (candidate.activationState == UISceneActivationStateForegroundActive && [candidate isKindOfClass:UIWindowScene.class]) {
            return (UIWindowScene *)candidate;
        }
    }
    return nil;
}

- (void)show {
    UIWindowScene *scene = [self activeScene];
    if (!scene) return;
    if (!self.overlayWindow) {
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        window.windowLevel = UIWindowLevelAlert;
        window.backgroundColor = UIColor.clearColor;
        window.userInteractionEnabled = NO;
        UIViewController *root = [[UIViewController alloc] init];
        root.view.backgroundColor = UIColor.clearColor;
        root.view.userInteractionEnabled = NO;
        window.rootViewController = root;
        self.overlayWindow = window;
    }
    UIView *host = self.overlayWindow.rootViewController.view;
    if (!self.container) {
        UIView *container = [[UIView alloc] init];
        container.backgroundColor = UIColor.blackColor;
        container.layer.cornerRadius = 16;
        container.layer.masksToBounds = YES;
        container.layer.borderWidth = 2;
        container.layer.borderColor = UIColor.whiteColor.CGColor;
        container.userInteractionEnabled = NO;
        AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        layer.videoGravity = AVLayerVideoGravityResizeAspect;
        [container.layer addSublayer:layer];
        UILabel *caption = [[UILabel alloc] init];
        caption.text = @"MV";
        caption.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        caption.textColor = UIColor.whiteColor;
        caption.frame = CGRectMake(14, 10, 80, 18);
        [container addSubview:caption];
        self.container = container;
        self.playerLayer = layer;
        [host addSubview:container];
    }
    self.overlayWindow.hidden = NO;
    CGFloat width = MIN(CGRectGetWidth(host.bounds) - 24.0, 640.0);
    CGFloat height = width * 720.0 / 1556.0;
    self.container.frame = CGRectMake((CGRectGetWidth(host.bounds) - width) / 2.0,
                                      (CGRectGetHeight(host.bounds) - height) / 2.0,
                                      width, height);
    self.playerLayer.frame = self.container.bounds;
    self.container.hidden = NO;
}

- (void)hide {
    if (!self.showing && self.overlayWindow.hidden) return;
    self.showing = NO;
    [self.player pause];
    self.container.hidden = YES;
    self.overlayWindow.hidden = YES;
}

@end
