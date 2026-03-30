#import "ViewController+Private.h"

#import "AudioFileFormats.h"
#import "ViewController+PlaybackProgress.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@implementation ViewController (Playback)

#pragma mark - App Lifecycle

- (void)hadEnterBackGround {
    NSLog(@"🔄 进入后台，停止所有GPU渲染...");
    self.isInBackground = YES;
    [self.animationCoordinator applicationDidEnterBackground];

    [self.visualEffectManager pauseRendering];

    if (self.visualEffectManager.metalView) {
        self.visualEffectManager.metalView.paused = YES;
        self.visualEffectManager.metalView.delegate = nil;
        NSLog(@"✅ Metal视图已暂停并移除delegate");
    }

    if (self.fpsDisplayLink) {
        self.fpsDisplayLink.paused = YES;
        NSLog(@"✅ FPS监控已暂停");
    }

    if (self.spectrumView) {
        [self.spectrumView pauseRendering];
        NSLog(@"✅ 频谱视图已暂停");
    }

    NSLog(@"🎵 检查播放状态: isPlaying=%@, isPaused=%@",
          self.player.isPlaying ? @"YES" : @"NO",
          self.player.isPaused ? @"YES" : @"NO");

    self.wasPlayingBeforeBackground = self.player.isPlaying;
    NSLog(@"🔖 记录后台前播放状态: %@", self.wasPlayingBeforeBackground ? @"播放中" : @"已暂停/停止");

    if (self.player && self.player.isPlaying) {
        NSLog(@"🎵 后台音乐播放: 保持音频会话激活");
        [self updateNowPlayingInfo];

        NSDictionary *nowPlaying = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
        NSLog(@"✅ 后台播放信息已更新:");
        NSLog(@"   - 标题: %@", nowPlaying[MPMediaItemPropertyTitle]);
        NSLog(@"   - 播放速率: %@", nowPlaying[MPNowPlayingInfoPropertyPlaybackRate]);
    } else if (self.player.isPaused) {
        NSLog(@"🎵 播放已暂停，进入后台（engine和session已在暂停时处理）");
    } else {
        NSLog(@"⚠️ 进入后台时没有音乐在播放");
    }

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView pauseSpinning];
        NSLog(@"✅ 黑胶唱片动画已暂停");
    }

    NSLog(@"✅ 后台处理完成，GPU渲染已完全停止");
}

- (void)hadEnterForeGround {
    NSLog(@"🔄 回到前台，恢复GPU渲染...");
    self.isInBackground = NO;
    [self.animationCoordinator applicationDidBecomeActive];

    if (self.visualEffectManager.metalView) {
        self.visualEffectManager.metalView.paused = NO;
        NSLog(@"✅ Metal视图已准备恢复");
    }

    [self.visualEffectManager resumeRendering];

    if (self.fpsDisplayLink) {
        self.fpsDisplayLink.paused = NO;
        NSLog(@"✅ FPS监控已恢复");
    }

    if (self.spectrumView) {
        [self.spectrumView resumeRendering];
        NSLog(@"✅ 频谱视图已恢复");
    }

    if (self.isShowingVinylRecord && self.player.isPlaying) {
        [self.vinylRecordView resumeSpinning];
        NSLog(@"✅ 黑胶唱片动画已恢复");
    }

    if (self.player.isPaused) {
        NSLog(@"🎵 播放器处于暂停状态，等待用户手动恢复");
    }

    self.wasPlayingBeforeBackground = NO;

    NSLog(@"✅ 前台恢复完成，GPU渲染已重新启动");
}

- (void)karaokeModeDidStart {
    NSLog(@"🎤 收到卡拉OK模式开始通知，停止主界面音频播放");
    [self.player stop];
    [self.visualEffectManager pauseRendering];
}

- (void)karaokeModeDidEnd {
    NSLog(@"🎤 收到卡拉OK模式结束通知");
    [self.visualEffectManager resumeRendering];
    self.shouldPreventAutoResume = NO;
    NSLog(@"🎤 卡拉OK模式结束，等待用户手动播放");
}

#pragma mark - AudioSpectrumPlayerDelegate

- (void)playerDidGenerateSpectrum:(nonnull NSArray *)spectrums {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateBackground) {
            return;
        }

        [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];

        if (self.animationCoordinator.spectrumManager) {
            [self.animationCoordinator updateSpectrumAnimations:spectrums];
        }

        if (spectrums.count > 0) {
            NSArray *firstChannelData = spectrums.firstObject;
            [self.visualEffectManager updateSpectrumData:firstChannelData];
        }
    });
}

- (void)didFinishPlay {
    if (self.shouldPreventAutoResume) {
        NSLog(@"⏹️ 播放结束，但用户在其他页面，不自动播放下一首");
        return;
    }

    if (self.isSingleLoopMode) {
        NSLog(@"🔂 单曲循环：重新播放当前歌曲");
        [self playCurrentTrack];
        return;
    }

    self.currentIndex += 1;
    if (self.currentIndex >= self.displayedMusicItems.count) {
        self.currentIndex = 0;
    }

    if (self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
        [self.musicLibrary recordPlayForMusic:musicItem];
    }

    [self updateAudioSelection];
    [self playCurrentTrack];
}

- (void)playerDidLoadLyrics:(LRCParser *)parser {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (parser) {
            NSLog(@"✅ 歌词加载成功: %@ - %@", parser.artist ?: @"未知", parser.title ?: @"未知");
            NSLog(@"   歌词行数: %lu", (unsigned long)parser.lyrics.count);
            self.lyricsContainer.hidden = NO;
            self.lyricsView.parser = parser;
        } else {
            NSLog(@"⚠️ 未找到歌词");
            self.lyricsContainer.hidden = NO;
            self.lyricsView.parser = nil;
        }
    });
}

- (void)playerDidStartPlaying {
    NSLog(@"🎵 播放器已开始播放，更新系统媒体信息");

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.playPauseButton setTitle:@"⏸️" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.2 alpha:0.85];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateNowPlayingInfo];
        NSLog(@"✅ 播放开始后已更新完整媒体信息");
        [self updateProgressWithDuration:self.player.duration];
    });
}

- (void)playerDidUpdateTime:(NSTimeInterval)currentTime {
    [self.lyricsView updateWithTime:currentTime];
    [self updateProgressWithCurrentTime:currentTime];

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastNowPlayingUpdateTime >= 5.0) {
        self.lastNowPlayingUpdateTime = now;

        NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
        if (nowPlayingInfo) {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(currentTime);
            if (self.player.isPlaying) {
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
            }
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
        }
    }
}

#pragma mark - Playback Controls

- (void)previousButtonTapped:(UIButton *)sender {
    NSLog(@"⏮️ 点击上一首按钮");
    [self playPrevious];
}

- (void)nextButtonTapped:(UIButton *)sender {
    NSLog(@"⏭️ 点击下一首按钮");
    [self playNext];
}

- (void)playPauseButtonTapped:(UIButton *)sender {
    if (self.player.isPlaying) {
        NSLog(@"⏸️ 暂停播放");
        [self pausePlayback];
    } else if (self.player.isPaused) {
        NSLog(@"▶️ 恢复播放（从暂停位置 %.2fs）", self.player.currentTime);
        [self resumePlayback];
    } else {
        NSLog(@"▶️ 开始播放新曲目");
        if (self.displayedMusicItems.count > 0) {
            [self playCurrentTrack];
            [self.playPauseButton setTitle:@"⏸️" forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.2 alpha:0.85];
        } else {
            NSLog(@"⚠️ 播放列表为空");
        }
    }
}

- (void)loopButtonTapped:(UIButton *)sender {
    self.isSingleLoopMode = !self.isSingleLoopMode;

    if (self.isSingleLoopMode) {
        NSLog(@"🔂 切换为单曲循环模式");
        [self.loopButton setTitle:@"🔂" forState:UIControlStateNormal];
        self.loopButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.5 alpha:0.85];
        self.loopButton.layer.borderColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.6 alpha:0.8].CGColor;
    } else {
        NSLog(@"🔁 切换为列表循环模式");
        [self.loopButton setTitle:@"🔁" forState:UIControlStateNormal];
        self.loopButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.7 alpha:0.85];
        self.loopButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.8 alpha:0.8].CGColor;
    }
}

#pragma mark - Remote Commands

- (void)setupRemoteCommandCenter {
    NSLog(@"🎵 开始配置系统媒体控制（iOS 16+ 优化）...");

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSLog(@"✅ Step 1: 音频会话由 AudioSpectrumPlayer 管理");
    NSLog(@"   当前类别: %@", audioSession.category);
    NSLog(@"   混音模式: %@", self.player.allowMixWithOthers ? @"开启" : @"关闭");

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    NSLog(@"✅ Step 2: 已启用远程控制事件接收");

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:nil];
    [commandCenter.pauseCommand removeTarget:nil];
    [commandCenter.nextTrackCommand removeTarget:nil];
    [commandCenter.previousTrackCommand removeTarget:nil];
    [commandCenter.togglePlayPauseCommand removeTarget:nil];

    commandCenter.togglePlayPauseCommand.enabled = NO;

    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 播放");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.shouldPreventAutoResume) {
                NSLog(@"   ⚠️ 已禁止播放（用户在其他页面）");
                return;
            }
            if (self.player.isPaused) {
                NSLog(@"   从暂停位置恢复播放（%.2fs）", self.player.currentTime);
                [self resumePlayback];
            } else if (!self.player.isPlaying) {
                NSLog(@"   开始播放当前曲目");
                [self playCurrentTrack];
            }
            self.wasPlayingBeforeBackground = NO;
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 暂停");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.player.isPlaying) {
                [self pausePlayback];
            }
            self.wasPlayingBeforeBackground = NO;
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 下一首");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playNext];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 上一首");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playPrevious];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;

    NSLog(@"✅ Step 3: 远程命令已注册并启用");
    NSLog(@"📋 最终配置状态:");
    NSLog(@"   • 音频会话类别: %@", audioSession.category);
    NSLog(@"   • 音频会话模式: %@", audioSession.mode);
    NSLog(@"   • 混音模式: %@", self.player.allowMixWithOthers ? @"✅ 允许混音" : @"❌ 独占播放");
    NSLog(@"   • 播放命令: %@", commandCenter.playCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 暂停命令: %@", commandCenter.pauseCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 下一首命令: %@", commandCenter.nextTrackCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 上一首命令: %@", commandCenter.previousTrackCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 切换播放命令: %@ (应该禁用)", commandCenter.togglePlayPauseCommand.isEnabled ? @"❌ 启用了" : @"✅ 已禁用");
    NSLog(@"✅ 系统媒体控制配置完成（iOS 16+ 优化）");
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)forceUpdateNowPlayingInfo {
    NSLog(@"🔍 强制设置播放信息测试...");

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = @"测试歌曲";
    info[MPMediaItemPropertyArtist] = @"测试艺术家";
    info[MPMediaItemPropertyPlaybackDuration] = @(180.0);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(0.0);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);

    UIImage *testArtwork = [self createDefaultArtworkImage];
    if (testArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:testArtwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return testArtwork;
        }];
        info[MPMediaItemPropertyArtwork] = artwork;
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;

    NSLog(@"✅ 强制设置完成");
    NSLog(@"   当前播放信息: %@", [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo);

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   音频会话类别: %@", session.category);
    NSLog(@"   音频会话选项: %lu", (unsigned long)session.categoryOptions);
    NSLog(@"   其他音频播放中: %@", @([session isOtherAudioPlaying]));
    NSLog(@"   音频会话激活: ✅ (已设置)");

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    NSLog(@"   播放命令启用: %@", @(commandCenter.playCommand.isEnabled));
    NSLog(@"   暂停命令启用: %@", @(commandCenter.pauseCommand.isEnabled));
}

- (void)updateNowPlayingInfoImmediate {
    if (self.currentIndex >= self.displayedMusicItems.count) {
        NSLog(@"⚠️ 无法更新播放信息: 索引超出范围");
        return;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];

    NSString *title = @"正在播放";
    if (musicItem.displayName) {
        title = musicItem.displayName;
    } else if (musicItem.fileName) {
        title = [musicItem.fileName stringByDeletingPathExtension];
    }
    nowPlayingInfo[MPMediaItemPropertyTitle] = title;
    nowPlayingInfo[MPMediaItemPropertyArtist] = @"AudioSampleBuffer";
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = @"本地音乐";

    UIImage *defaultArtwork = [self createDefaultArtworkImage];
    if (defaultArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:defaultArtwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return defaultArtwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
        NSLog(@"   - 封面图片: ✅ 已设置 (%.0fx%.0f)", defaultArtwork.size.width, defaultArtwork.size.height);
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(0.0);

    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = nowPlayingInfo;

    NSLog(@"✅ 立即设置播放信息成功:");
    NSLog(@"   - 标题: %@", title);
    NSLog(@"   - 艺术家: %@", nowPlayingInfo[MPMediaItemPropertyArtist]);
    NSLog(@"   - 播放速率: %@", nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate]);

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   - 音频会话类别: %@", session.category);
    NSLog(@"   - 音频会话选项: %lu (0=独占, 1=混音)", (unsigned long)session.categoryOptions);
    NSLog(@"   - 其他音频播放中: %@", @(session.isOtherAudioPlaying));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        center.nowPlayingInfo = nowPlayingInfo;
        NSLog(@"🔄 二次确认播放信息已设置");
    });
}

- (UIImage *)createDefaultArtworkImage {
    if (self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];

        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        }

        if (fileUrl) {
            UIImage *musicCover = [self musicImageWithMusicURL:fileUrl];
            if (musicCover) {
                NSLog(@"✅ 使用音乐真实封面 (%.0fx%.0f): %@", musicCover.size.width, musicCover.size.height, musicItem.fileName);
                return musicCover;
            }
        }
    }

    UIImage *appIcon = [UIImage imageNamed:@"none_image"];
    if (appIcon) {
        NSLog(@"✅ 使用 App Icon 作为默认封面 (%.0fx%.0f)", appIcon.size.width, appIcon.size.height);
        return appIcon;
    }

    UIImage *noneImage = [UIImage imageNamed:@"none_image"];
    if (noneImage) {
        NSLog(@"✅ 使用默认封面图片: none_image (%.0fx%.0f)", noneImage.size.width, noneImage.size.height);
        return noneImage;
    }

    NSLog(@"⚠️ none_image 图片未找到，使用程序生成的默认封面");

    CGSize size = CGSizeMake(512, 512);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:1.0].CGColor
    ];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(size.width, size.height), 0);

    UIBezierPath *musicNote = [UIBezierPath bezierPath];
    CGFloat centerX = size.width / 2;
    CGFloat centerY = size.height / 2;
    [musicNote moveToPoint:CGPointMake(centerX - 30, centerY + 40)];
    [musicNote addLineToPoint:CGPointMake(centerX - 30, centerY - 40)];
    [musicNote addLineToPoint:CGPointMake(centerX + 30, centerY - 50)];
    [musicNote addLineToPoint:CGPointMake(centerX + 30, centerY + 30)];
    [[UIColor whiteColor] setStroke];
    musicNote.lineWidth = 8;
    [musicNote stroke];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    return image;
}

- (void)updateNowPlayingInfo {
    if (self.currentIndex >= self.displayedMusicItems.count) {
        return;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];

    if (musicItem.displayName) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = musicItem.displayName;
    } else if (musicItem.fileName) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = [musicItem.fileName stringByDeletingPathExtension];
    }

    if (self.player.lyricsParser && self.player.lyricsParser.artist) {
        nowPlayingInfo[MPMediaItemPropertyArtist] = self.player.lyricsParser.artist;
    } else {
        nowPlayingInfo[MPMediaItemPropertyArtist] = @"未知艺术家";
    }

    if (self.player.lyricsParser && self.player.lyricsParser.album) {
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = self.player.lyricsParser.album;
    }

    UIImage *artwork = [self createDefaultArtworkImage];
    if (artwork) {
        MPMediaItemArtwork *artworkItem = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkItem;
    }

    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(self.player.duration);
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
    if (self.player.isPlaying) {
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    NSLog(@"🎵 已更新系统播放信息: %@", nowPlayingInfo[MPMediaItemPropertyTitle]);
}

#pragma mark - Public Playback API

- (void)pausePlayback {
    NSLog(@"⏸️ 暂停播放");
    [self.player pause];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView pauseSpinning];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.playPauseButton setTitle:@"▶️" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.85];
    });

    [self.player pauseEngine];
    [self deactivateAudioSessionForPause];

    NSLog(@"✅ 已暂停播放（engine已暂停，session已deactivate，控制中心将显示播放按钮）");
}

- (void)deactivateAudioSessionForPause {
    NSError *error = nil;
    BOOL success = [[AVAudioSession sharedInstance] setActive:NO
                                                  withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                                        error:&error];
    if (success) {
        NSLog(@"✅ AudioSession 已 deactivate（系统将更新播放按钮）");
    } else {
        NSLog(@"⚠️ AudioSession deactivate 返回: %@ (按钮仍会更新)", error.localizedDescription);
    }
}

- (void)resumePlayback {
    NSLog(@"▶️ 恢复播放");

    [self.player configureAudioSession];
    [self.player resume];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView resumeSpinning];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.playPauseButton setTitle:@"⏸️" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.2 alpha:0.85];
    });

    NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
    if (nowPlayingInfo) {
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    }

    NSLog(@"✅ 已恢复播放（从 %.2fs 继续）", self.player.currentTime);
}

- (void)playCurrentTrack {
    NSLog(@"🎵 [playCurrentTrack] 开始...");
    NSLog(@"   当前索引: %ld", (long)self.currentIndex);
    NSLog(@"   列表总数: %lu", (unsigned long)self.displayedMusicItems.count);

    if (self.currentIndex >= self.displayedMusicItems.count) {
        NSLog(@"⚠️ 索引超出范围: %ld / %lu", (long)self.currentIndex, (unsigned long)self.displayedMusicItems.count);
        return;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    NSLog(@"   歌曲: %@", musicItem.fileName);
    NSLog(@"   路径: %@", musicItem.filePath);

    NSString *playPath = nil;
    if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
        playPath = musicItem.decryptedPath;
        NSLog(@"🎵 播放已解密文件: %@", playPath);
    } else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
        NSLog(@"🔓 解密NCM文件: %@", musicItem.fileName);
        NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
        playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];

        if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
            NSLog(@"✅ 解密成功: %@", playPath);
        }
    } else if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
        playPath = musicItem.filePath;
        NSLog(@"🎵 播放云下载文件（完整路径）: %@", playPath);
    } else {
        playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
        NSLog(@"🎵 播放Bundle文件: %@", playPath);
    }

    if (playPath.length == 0) {
        NSLog(@"❌ [playCurrentTrack] playPath 为空！");
        return;
    }

    NSLog(@"🎵 [playCurrentTrack] 最终播放路径: %@", playPath);
    [self updateNowPlayingInfoImmediate];

    NSString *songName = musicItem.displayName ?: [musicItem.fileName stringByDeletingPathExtension];
    NSString *artist = musicItem.artist ?: @"";
    if (artist.length == 0 && songName.length > 0 && [songName containsString:@" - "]) {
        NSArray *parts = [songName componentsSeparatedByString:@" - "];
        if (parts.count >= 2) {
            artist = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            songName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }

    [self.player playWithFileName:playPath songName:songName artist:artist];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView startSpinning];
    }
}

#pragma mark - Audio Session

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        NSLog(@"🎧 音频会话中断开始");
        self.wasPlayingBeforeInterruption = self.player.isPlaying;
        NSLog(@"   中断前播放状态: %@", self.wasPlayingBeforeInterruption ? @"播放中" : @"已暂停");

        if (self.player.isPlaying) {
            [self pausePlayback];
        }
    } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        NSLog(@"🎧 音频会话中断结束");

        if (self.shouldPreventAutoResume) {
            NSLog(@"   ⚠️ 已禁止自动恢复播放（用户可能在其他页面）");
            return;
        }

        if (!self.wasPlayingBeforeInterruption) {
            NSLog(@"   ⚠️ 中断前未播放，不恢复播放");
            return;
        }

        AVAudioSessionInterruptionOptions options = [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        BOOL shouldResume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;

        NSLog(@"   是否应该恢复播放: %@", shouldResume ? @"是" : @"否");

        if (shouldResume) {
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (error) {
                NSLog(@"❌ 重新激活音频会话失败: %@", error);
            } else {
                NSLog(@"✅ 音频会话已重新激活");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self playCurrentTrack];
                    NSLog(@"✅ 已恢复播放");
                    self.wasPlayingBeforeInterruption = NO;
                });
            }
        }
    }
}

- (void)handleAudioSessionRouteChange:(NSNotification *)notification {
    AVAudioSessionRouteChangeReason reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];

    NSLog(@"🎧 音频路由变化，原因: %lu", (unsigned long)reason);

    switch (reason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
            NSLog(@"🎧 新音频设备连接");

            AVAudioSession *session = [AVAudioSession sharedInstance];
            AVAudioSessionRouteDescription *currentRoute = session.currentRoute;

            for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
                NSLog(@"   输出设备: %@ (%@)", output.portName, output.portType);

                if ([output.portType isEqualToString:AVAudioSessionPortHeadphones] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
                    NSLog(@"✅ 检测到耳机/蓝牙设备连接");
                }
            }
            break;
        }

        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
            NSLog(@"🎧 音频设备断开");

            AVAudioSessionRouteDescription *previousRoute = notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
            for (AVAudioSessionPortDescription *output in previousRoute.outputs) {
                NSLog(@"   断开的设备: %@ (%@)", output.portName, output.portType);

                if ([output.portType isEqualToString:AVAudioSessionPortHeadphones] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
                    NSLog(@"⚠️ 耳机/蓝牙设备已断开，暂停播放");
                    if (self.player.isPlaying) {
                        [self pausePlayback];
                        NSLog(@"✅ 已自动暂停播放");
                    }
                }
            }
            break;
        }

        case AVAudioSessionRouteChangeReasonCategoryChange: {
            NSLog(@"🎧 音频类别变化");

            AVAudioSession *session = [AVAudioSession sharedInstance];
            NSLog(@"   新类别: %@", session.category);
            NSLog(@"   新模式: %@", session.mode);

            if (self.player.isPlaying) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self.player configureAudioSession];
                    NSLog(@"✅ 已重新配置音频会话");
                });
            }
            break;
        }

        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"🎧 音频路由被覆盖");
            break;

        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"🎧 从睡眠中唤醒");
            break;

        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"⚠️ 当前类别没有合适的音频路由");
            break;

        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            NSLog(@"🎧 音频路由配置变化");
            break;

        default:
            NSLog(@"🎧 其他路由变化原因: %lu", (unsigned long)reason);
            break;
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *currentRoute = session.currentRoute;
    NSLog(@"📋 当前音频路由:");
    for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
        NSLog(@"   输出: %@ (%@)", output.portName, output.portType);
    }
    for (AVAudioSessionPortDescription *input in currentRoute.inputs) {
        NSLog(@"   输入: %@ (%@)", input.portName, input.portType);
    }
}

@end
