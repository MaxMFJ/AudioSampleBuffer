

#import "AudioSpectrumPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import "RealtimeAnalyzer.h"
#import "LyricsManager.h"
#import "LRCParser.h"
#import "MusicAIAnalyzer.h"

NSString *const kAudioPlayerDidLoadLyricsNotification = @"AudioPlayerDidLoadLyricsNotification";
NSString *const kAudioPlayerDidUpdateTimeNotification = @"AudioPlayerDidUpdateTimeNotification";
NSString *const kAudioPlayerDidStartPlaybackNotification = @"AudioPlayerDidStartPlaybackNotification";

@interface AudioSpectrumPlayer ()
{
    AVAudioFramePosition lastStartFramePosition;
    dispatch_source_t _sometimer;
    dispatch_queue_t _queue;
    BOOL _isSeeking;  // 是否正在跳转中，防止触发 didFinishPlay
    BOOL _isPaused;   // 🔧 是否处于暂停状态
    BOOL _enginePaused; // 🔧 引擎是否被暂停（后台时）
}
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitTimePitch *timePitchNode;  // 🎵 音高/速率调整节点
@property (nonatomic, strong) RealtimeAnalyzer *analyzer;
@property (nonatomic, assign) int bufferSize;
@property (nonatomic, strong) AVAudioFile *file;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) BOOL timeBegining;
@property (nonatomic, strong) NSString *currentFilePath;  // 当前播放文件路径
@property (nonatomic, strong, readwrite) LRCParser *lyricsParser;  // 歌词解析器
@property (nonatomic, assign) NSTimeInterval pausedTime; // 🔧 暂停时的播放时间

@end

@implementation AudioSpectrumPlayer

@synthesize duration = _duration;

- (BOOL)isPlaying {
    return self.player.isPlaying;
}

- (instancetype)init {
    if (self = [super init]) {
        [self configInit];
        [self setupPlayer];
    }
    return self;
}

- (void)configInit {
    self.bufferSize = 2048;
    self.analyzer = [[RealtimeAnalyzer alloc] initWithFFTSize:self.bufferSize];
    self.enableLyrics = YES;  // 默认启用歌词
    
    // 🎵 初始化音高/速率参数
    _pitchShift = 0.0f;      // 默认原调
    _playbackRate = 1.0f;    // 默认原速
    
    // 🔊 默认不允许与其他应用混音
    _allowMixWithOthers = NO;
}

- (void)setupPlayer {
    // 🔧 关键修复：配置音频会话
    [self configureAudioSession];
    
    NSLog(@"✅ 音频会话已配置");
    
    [self.engine attachNode:self.player];
    [self.engine attachNode:self.timePitchNode];
    
    AVAudioMixerNode *mixerNode = self.engine.mainMixerNode;
    
    // ⚠️ 关键修复：不要在连接前获取格式，连接时使用 nil 让系统自动协商格式
    // 🎵 音频链路：player → timePitch → mixer
    [self.engine connect:self.player to:self.timePitchNode format:nil];
    [self.engine connect:self.timePitchNode to:mixerNode format:nil];
    
    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) {
        NSLog(@"❌ AudioEngine 启动失败: %@", error);
        return;
    }
    
    // 在引擎启动后获取实际格式
    AVAudioFormat *format = [mixerNode outputFormatForBus:0];
    
    //在添加tap之前先移除上一个  不然有可能报"Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio',"之类的错误
    [mixerNode removeTapOnBus:0];
    [mixerNode installTapOnBus:0 bufferSize:self.bufferSize format:format block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        if (!self.player.isPlaying) return ;
        buffer.frameLength = self.bufferSize;
        NSArray *spectrums = [self.analyzer analyse:buffer withAmplitudeLevel:5];
        if ([self.delegate respondsToSelector:@selector(playerDidGenerateSpectrum:)]) {
            [self.delegate playerDidGenerateSpectrum:spectrums];
        }
    }];

    NSLog(@"✅ AudioSpectrumPlayer 音频链路已建立: player → timePitch → mixer");
    NSLog(@"   格式: %.0f Hz, %u 声道", format.sampleRate, (unsigned int)format.channelCount);
}
- (NSTimeInterval)audioDurationFromURL:(NSString *)url {
    AVURLAsset *audioAsset = nil;
    NSDictionary *dic = @{AVURLAssetPreferPreciseDurationAndTimingKey:@(YES)};
    if ([url hasPrefix:@"http://"]) {
        audioAsset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:url] options:dic];
    }else {
        audioAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:url] options:dic];
    }
    CMTime audioDuration = audioAsset.duration;
    float audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    return audioDurationSeconds;
}
//- (void)setCurrentTime:(NSTimeInterval)currentTime {
//    _currentTime = currentTime;
//    BOOL isPlaying = self.isPlaying;
//    [self.player stop]; // 先停下来
//    __weak typeof(self) weself = self;
//    AVAudioFramePosition startingFrame = currentTime * self.file.processingFormat.sampleRate;
//    // 要根据总时长和当前进度，找出起始的frame位置和剩余的frame数量
//    AVAudioFrameCount frameCount = (AVAudioFrameCount)(self.file.length - startingFrame);
//    if (frameCount > 1000) { // 当剩余数量小于0时会crash，随便设个数
//        lastStartFramePosition = startingFrame;
//        [self.player scheduleSegment:self.file startingFrame:startingFrame frameCount:frameCount atTime:nil completionHandler:^{
//            [weself didFinishPlay];
//        }]; // 这里只有这个scheduleSegement的方法播放快进后的“片段”
//    }
//    if (isPlaying) {
//        [self.player play]; // 恢复播放
//    }
//}
// 🎨 新方法：支持 AI 分析的播放
- (void)playWithFileName:(NSString *)fileName songName:(NSString *)songName artist:(NSString *)artist {
    // 调用核心播放逻辑
    [self _playWithFileName:fileName];
    
    // 🎨 触发 AI 颜色分析（如果提供了歌曲名）
    if (songName.length > 0) {
        [[MusicAIAnalyzer sharedAnalyzer] analyzeSong:songName
                                               artist:artist
                                           completion:^(AIColorConfiguration * _Nullable config, NSError * _Nullable error) {
            if (error) {
                NSLog(@"⚠️ AI 颜色分析失败: %@", error.localizedDescription);
            } else if (config) {
                NSLog(@"🎨 AI 颜色分析已应用: %@ - %@", config.songName, config.artist ?: @"");
            }
        }];
        
        // 🤖 发送通知触发AI特效决策Agent
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AudioSpectrumPlayerDidStartSongNotification"
                                                            object:self
                                                          userInfo:@{
            @"songName": songName,
            @"artist": artist ?: @""
        }];
    }
}

// 兼容旧版本的方法
- (void)playWithFileName:(NSString *)fileName {
    [self _playWithFileName:fileName];
}

// 核心播放逻辑（内部方法）
- (void)_playWithFileName:(NSString *)fileName {
    // 🔊 关键修复：每次播放前重新配置音频会话，确保设置生效
    [self configureAudioSession];
    
    // 立即清空旧歌词，避免短暂显示上一首歌的歌词
    self.lyricsParser = nil;
    if ([self.delegate respondsToSelector:@selector(playerDidLoadLyrics:)]) {
        [self.delegate playerDidLoadLyrics:nil];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioPlayerDidLoadLyricsNotification
                                                        object:self
                                                      userInfo:@{ @"parser": [NSNull null],
                                                                  @"filePath": self.currentFilePath ?: @"" }];
    
    // 🔧 修复：支持完整路径和文件名两种方式
    NSURL *fileUrl = nil;
    
    if ([fileName hasPrefix:@"/"]) {
        // 如果是完整路径（以 / 开头），直接使用
        fileUrl = [NSURL fileURLWithPath:fileName];
        NSLog(@"🎵 使用完整路径播放: %@", fileName);
    } else {
        // 如果是文件名，从 Bundle 中查找
        fileUrl = [[NSBundle mainBundle] URLForResource:fileName withExtension:nil];
        NSLog(@"🎵 从 Bundle 加载: %@", fileName);
    }
    
    if (!fileUrl) {
        NSLog(@"❌ 找不到音频文件: %@", fileName);
        return;
    }
    
    NSError *error = nil;
    self.file = [[AVAudioFile alloc] initForReading:fileUrl error:&error];
    if (error) {
        NSLog(@"❌ 创建 AVAudioFile 失败: %@", error);
        NSLog(@"   文件路径: %@", fileUrl.path);
        NSLog(@"   文件是否存在: %@", [[NSFileManager defaultManager] fileExistsAtPath:fileUrl.path] ? @"是" : @"否");
        return;
    }
    
    // 保存当前文件路径
    self.currentFilePath = fileUrl.path;
    
    [self.player stop];
    [self.player scheduleFile:self.file atTime:nil completionHandler:nil];
    
    // 启动音频引擎并播放
    if (self.engine.isRunning == YES)
    {
        [self.player play];
        NSLog(@"🎵 音频引擎已运行，直接播放");
    }else{
        NSError *engineError = nil;
        BOOL started = [self.engine startAndReturnError:&engineError];
        if (!started || engineError) {
            NSLog(@"❌ 音频引擎启动失败: %@", engineError);
            return;
        }
        [self.player play];
        NSLog(@"🎵 音频引擎已启动并开始播放");
    }
    
    // 🔊 在开始播放后，再次确认音频会话状态
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSLog(@"🔍 [播放后验证] 音频会话状态:");
        NSLog(@"   类别: %@", session.category);
        NSLog(@"   选项: %lu", (unsigned long)session.categoryOptions);
        NSLog(@"   混音: %@", (session.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) ? @"✅" : @"❌");
    });
    
    // 🎵 通知代理播放已开始（延迟一点确保真正开始播放）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(playerDidStartPlaying)]) {
            [self.delegate playerDidStartPlaying];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:kAudioPlayerDidStartPlaybackNotification
                                                            object:self
                                                          userInfo:@{ @"filePath": self.currentFilePath ?: @"" }];
    });
  
    
//    AVAudioTime *playerTime = [self.player playerTimeForNodeTime:self.player.lastRenderTime];
//    NSLog(@"%llu" ,playerTime.audioTimeStamp);
//    NSLog(@"%llu",playerTime.hostTime);
    
    AVAudioFrameCount frameCount = (AVAudioFrameCount)self.file.length;
    double sampleRate = self.file.processingFormat.sampleRate;
    self.duration = frameCount / sampleRate;
    
    
    
    
    AVAudioTime *playerTime = [self.player playerTimeForNodeTime:self.player.lastRenderTime];
    _currentTime = (lastStartFramePosition + playerTime.sampleTime) / playerTime.sampleRate;
    // 倒计时结束，关闭
    if (_sometimer != nil)
    {
        dispatch_source_cancel(self->_sometimer);
        self->_queue = nil;
        self->_sometimer = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            
            self->_timeBegining = NO;
        });
    }
 
    [self countDownBegin:(NSInteger)self.duration];
    
    // 加载歌词
    if (self.enableLyrics) {
        [self loadLyricsForCurrentTrack];
    }
}

//开始倒计时
- (void)countDownBegin:(NSInteger)sender{
    _timeBegining = YES;
    if (_queue ==nil)
    {
        _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0);
        _sometimer= dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0, _queue);
        
    }
    __block NSTimeInterval totalDuration = (NSTimeInterval)sender;
    __block NSTimeInterval elapsedTime = 0;
    
    // 🔧 关键修复：改为每0.1秒更新一次，提高歌词同步精度（10倍于原来）
    dispatch_source_set_timer(_sometimer, dispatch_walltime(NULL,0), 0.1*NSEC_PER_SEC, 0);
    
    dispatch_source_set_event_handler(_sometimer, ^{
        if(elapsedTime < totalDuration) {// 继续播放
            dispatch_async(dispatch_get_main_queue(), ^{
                // 更新当前播放时间（更精确，0.1秒级别）
                self->_currentTime = elapsedTime;
                
                // 通知代理时间更新（用于歌词同步）
                if ([self.delegate respondsToSelector:@selector(playerDidUpdateTime:)]) {
                    [self.delegate playerDidUpdateTime:elapsedTime];
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:kAudioPlayerDidUpdateTimeNotification
                                                                    object:self
                                                                  userInfo:@{ @"currentTime": @(elapsedTime) }];
            });
            
            // 以0.1秒为单位递增
            elapsedTime += 0.1;
        }else{
            // 倒计时结束，关闭
            dispatch_source_cancel(self->_sometimer);
            self->_queue = nil;
            self->_sometimer = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_timeBegining = NO;
                [self.delegate didFinishPlay];
            });
        }
    });
    
    dispatch_resume(_sometimer);
    
}
- (void)stop {
    [self.player stop];
    _isPaused = NO;
    self.pausedTime = 0;
    
    // 停止计时器
    [self cancelTimer];
    
    // 停止时清除歌词
    self.lyricsParser = nil;
}

#pragma mark - 🎵 暂停/恢复控制

- (BOOL)isPaused {
    return _isPaused;
}

/// 暂停播放（保持播放位置，暂停计时器）
- (void)pause {
    if (self.player.isPlaying) {
        // 1. 记录当前时间
        self.pausedTime = self.currentTime;
        _isPaused = YES;
        
        // 2. 暂停 playerNode
        [self.player pause];
        
        // 3. 暂停计时器
        [self cancelTimer];
        
        NSLog(@"⏸️ AudioPlayer 已暂停（位置: %.2fs / %.2fs）", self.pausedTime, self.duration);
    }
}

/// 恢复播放（从暂停位置重新调度）
- (void)resume {
    if (_isPaused && self.file) {
        NSTimeInterval resumeTime = self.pausedTime;
        NSLog(@"▶️ AudioPlayer 恢复播放（位置: %.2fs）", resumeTime);
        _isPaused = NO;
        
        // 🔧 如果引擎被暂停过（后台），需要先恢复引擎
        if (_enginePaused) {
            [self resumeEngine];
        }
        
        // 🔧 关键：手动重新调度播放（不通过 seekToTime，因为 seekToTime 检查 isPlaying 来决定是否 play）
        _isSeeking = YES;
        
        // 停止当前 playerNode（清除旧 buffer）
        [self.player stop];
        
        // 取消旧计时器
        [self cancelTimer];
        
        // 计算目标帧位置
        double sampleRate = self.file.processingFormat.sampleRate;
        AVAudioFramePosition startingFrame = (AVAudioFramePosition)(resumeTime * sampleRate);
        startingFrame = MAX(0, MIN(startingFrame, self.file.length - 1));
        AVAudioFrameCount frameCount = (AVAudioFrameCount)(self.file.length - startingFrame);
        
        if (frameCount <= 1000) {
            startingFrame = MAX(0, self.file.length - 1000);
            frameCount = (AVAudioFrameCount)(self.file.length - startingFrame);
        }
        
        lastStartFramePosition = startingFrame;
        _currentTime = resumeTime;
        
        // 调度播放
        __weak typeof(self) weakSelf = self;
        [self.player scheduleSegment:self.file
                       startingFrame:startingFrame
                          frameCount:frameCount
                              atTime:nil
                   completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
                   completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && !strongSelf->_isSeeking) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!strongSelf->_isSeeking && strongSelf.player.isPlaying == NO) {
                        [strongSelf.delegate didFinishPlay];
                    }
                });
            }
        }];
        
        _isSeeking = NO;
        
        // 🔧 关键：无论什么状态都要开始播放和启动计时器
        [self.player play];
        [self countDownBeginFromTime:resumeTime duration:self.duration];
        
        NSLog(@"✅ AudioPlayer 已恢复播放（%.2fs / %.2fs）", resumeTime, self.duration);
        
        // 通知代理
        if ([self.delegate respondsToSelector:@selector(playerDidStartPlaying)]) {
            [self.delegate playerDidStartPlaying];
        }
    }
}

/// 暂停音频引擎（进入后台时调用）
- (void)pauseEngine {
    if (!_enginePaused && self.engine.isRunning) {
        [self.engine pause];
        _enginePaused = YES;
        NSLog(@"🔧 AudioEngine 已暂停（后台节省资源）");
    }
}

/// 恢复音频引擎
- (void)resumeEngine {
    if (_enginePaused) {
        NSError *error = nil;
        if (![self.engine startAndReturnError:&error]) {
            NSLog(@"❌ AudioEngine 恢复失败: %@", error);
        } else {
            NSLog(@"✅ AudioEngine 已恢复");
        }
        _enginePaused = NO;
    }
}

/// 取消计时器
- (void)cancelTimer {
    if (_sometimer != nil) {
        dispatch_source_cancel(_sometimer);
        _queue = nil;
        _sometimer = nil;
        _timeBegining = NO;
    }
}

#pragma mark - 进度跳转

- (void)seekToTime:(NSTimeInterval)time {
    if (!self.file) {
        NSLog(@"❌ seekToTime: 没有音频文件");
        return;
    }
    
    // 限制时间范围
    time = fmax(0, fmin(time, self.duration - 0.5));  // 留出0.5秒余量，避免跳到末尾
    
    // 标记正在跳转，防止 completionHandler 触发 didFinishPlay
    _isSeeking = YES;
    
    BOOL wasPlaying = self.player.isPlaying;
    
    // 停止当前播放
    [self.player stop];
    
    // 停止计时器
    if (_sometimer != nil) {
        dispatch_source_cancel(_sometimer);
        _queue = nil;
        _sometimer = nil;
    }
    
    // 计算目标帧位置
    double sampleRate = self.file.processingFormat.sampleRate;
    AVAudioFramePosition startingFrame = (AVAudioFramePosition)(time * sampleRate);
    
    // 确保帧位置有效
    startingFrame = MAX(0, MIN(startingFrame, self.file.length - 1));
    
    // 计算剩余帧数
    AVAudioFrameCount frameCount = (AVAudioFrameCount)(self.file.length - startingFrame);
    
    if (frameCount <= 1000) {  // 留出一些缓冲
        NSLog(@"⚠️ seekToTime: 接近文件末尾，调整位置");
        startingFrame = MAX(0, self.file.length - 1000);
        frameCount = (AVAudioFrameCount)(self.file.length - startingFrame);
    }
    
    // 更新起始帧位置（用于时间计算）
    lastStartFramePosition = startingFrame;
    
    // 更新当前时间
    _currentTime = time;
    
    // 调度从指定位置开始播放的片段
    __weak typeof(self) weakSelf = self;
    [self.player scheduleSegment:self.file
                   startingFrame:startingFrame
                      frameCount:frameCount
                          atTime:nil
               completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
               completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && !strongSelf->_isSeeking) {
            // 只有在非跳转状态下才触发播放完成
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!strongSelf->_isSeeking && strongSelf.player.isPlaying == NO) {
                    [strongSelf.delegate didFinishPlay];
                }
            });
        }
    }];
    
    // 恢复标记
    _isSeeking = NO;
    
    // 如果之前在播放，恢复播放并重启计时器
    if (wasPlaying) {
        [self.player play];
        
        // 从新的时间位置开始计时
        [self countDownBeginFromTime:time duration:self.duration];
    }
    
    NSLog(@"⏩ 跳转到 %.2f 秒 (帧: %lld, 剩余帧: %u)", time, (long long)startingFrame, (unsigned int)frameCount);
}

/// 从指定时间开始倒计时
- (void)countDownBeginFromTime:(NSTimeInterval)startTime duration:(NSTimeInterval)totalDuration {
    // 先停止之前的计时器
    if (_sometimer != nil) {
        dispatch_source_cancel(_sometimer);
        _queue = nil;
        _sometimer = nil;
    }
    
    _timeBegining = YES;
    _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _sometimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    
    __block NSTimeInterval elapsedTime = startTime;
    __weak typeof(self) weakSelf = self;
    
    // 每0.1秒更新一次
    dispatch_source_set_timer(_sometimer, dispatch_walltime(NULL, 0), 0.1 * NSEC_PER_SEC, 0);
    
    dispatch_source_set_event_handler(_sometimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // 检查是否正在跳转
        if (strongSelf->_isSeeking) return;
        
        if (elapsedTime < totalDuration && strongSelf.player.isPlaying) {
            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf->_currentTime = elapsedTime;
                
                if ([strongSelf.delegate respondsToSelector:@selector(playerDidUpdateTime:)]) {
                    [strongSelf.delegate playerDidUpdateTime:elapsedTime];
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:kAudioPlayerDidUpdateTimeNotification
                                                                    object:strongSelf
                                                                  userInfo:@{ @"currentTime": @(elapsedTime) }];
            });
            
            elapsedTime += 0.1;
        } else if (elapsedTime >= totalDuration) {
            dispatch_source_cancel(strongSelf->_sometimer);
            strongSelf->_queue = nil;
            strongSelf->_sometimer = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf->_timeBegining = NO;
                if (!strongSelf->_isSeeking) {
                    [strongSelf.delegate didFinishPlay];
                }
            });
        }
    });
    
    dispatch_resume(_sometimer);
}

#pragma mark - Lyrics

- (void)loadLyricsForCurrentTrack {
    if (!self.currentFilePath) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [[LyricsManager sharedManager] fetchLyricsForAudioFile:self.currentFilePath
                                                completion:^(LRCParser *parser, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // ⚠️ 关键修复：确保代理回调在主线程执行
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"加载歌词失败: %@", error);
                strongSelf.lyricsParser = nil;
                
                // 通知代理歌词加载失败（传入nil），以便界面显示"暂无lrc文件歌词"
                if ([strongSelf.delegate respondsToSelector:@selector(playerDidLoadLyrics:)]) {
                    [strongSelf.delegate playerDidLoadLyrics:nil];
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:kAudioPlayerDidLoadLyricsNotification
                                                                    object:strongSelf
                                                                  userInfo:@{ @"parser": [NSNull null],
                                                                              @"filePath": strongSelf.currentFilePath ?: @"" }];
            } else {
                strongSelf.lyricsParser = parser;
                NSLog(@"歌词加载成功，共 %lu 行", (unsigned long)parser.lyrics.count);
                
                // 通知代理歌词加载完成
                if ([strongSelf.delegate respondsToSelector:@selector(playerDidLoadLyrics:)]) {
                    [strongSelf.delegate playerDidLoadLyrics:parser];
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:kAudioPlayerDidLoadLyricsNotification
                                                                    object:strongSelf
                                                                  userInfo:@{ @"parser": parser,
                                                                              @"filePath": strongSelf.currentFilePath ?: @"" }];
            }
        });
    }];
}

- (AVAudioEngine *)engine {
    if (!_engine) {
        _engine = [[AVAudioEngine alloc] init];
    }
    return _engine;
}

- (AVAudioPlayerNode *)player {
    if (!_player) {
        _player = [[AVAudioPlayerNode alloc] init];
    }
    return _player;
}

- (AVAudioUnitTimePitch *)timePitchNode {
    if (!_timePitchNode) {
        _timePitchNode = [[AVAudioUnitTimePitch alloc] init];
        _timePitchNode.pitch = 0.0f;  // 默认原调（单位：cent，100 cent = 1 半音）
        _timePitchNode.rate = 1.0f;   // 默认原速
    }
    return _timePitchNode;
}

#pragma mark - 🎵 音高/速率控制

- (void)setPitchShift:(float)pitchShift {
    // 限制范围：-12 到 +12 半音
    _pitchShift = fmaxf(-12.0f, fminf(12.0f, pitchShift));
    
    // AVAudioUnitTimePitch 使用 cent 作为单位（1 半音 = 100 cents）
    self.timePitchNode.pitch = _pitchShift * 100.0f;
    
    NSLog(@"🎵 [背景音乐] 音高调整: %.1f 半音 (%.0f cents)", _pitchShift, _pitchShift * 100.0f);
}

- (void)setPlaybackRate:(float)playbackRate {
    // 限制范围：0.5 到 2.0
    _playbackRate = fmaxf(0.5f, fminf(2.0f, playbackRate));
    
    self.timePitchNode.rate = _playbackRate;
    
    NSLog(@"🎵 [背景音乐] 速率调整: %.2fx", _playbackRate);
}

#pragma mark - 🔊 音频会话控制

- (void)setAllowMixWithOthers:(BOOL)allowMixWithOthers {
    if (_allowMixWithOthers != allowMixWithOthers) {
        _allowMixWithOthers = allowMixWithOthers;
        [self configureAudioSession];
        NSLog(@"🔊 混音设置已更新: %@", _allowMixWithOthers ? @"允许与其他应用同时播放" : @"独占播放");
    }
}

- (void)configureAudioSession {
    NSError *sessionError = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    NSLog(@"🔊 [音频会话] 开始配置...");
    NSLog(@"   混音开关状态: %@", self.allowMixWithOthers ? @"✅ 允许混音" : @"❌ 独占播放");
    
    // 根据 allowMixWithOthers 设置音频会话选项
    AVAudioSessionCategoryOptions options = self.allowMixWithOthers ? AVAudioSessionCategoryOptionMixWithOthers : 0;
    
    // 设置音频会话类别和选项
    BOOL categorySuccess = [audioSession setCategory:AVAudioSessionCategoryPlayback 
                                          withOptions:options 
                                                error:&sessionError];
    if (!categorySuccess || sessionError) {
        NSLog(@"❌ 音频会话类别配置失败: %@", sessionError);
        sessionError = nil;
    } else {
        NSLog(@"✅ 音频会话类别已设置: %@", audioSession.category);
        NSLog(@"   选项值: %lu (0=独占, 1=混音)", (unsigned long)audioSession.categoryOptions);
    }
    
    // 激活音频会话（使用 WITH_OPTIONS 激活选项）
    BOOL activateSuccess = [audioSession setActive:YES 
                                       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation 
                                             error:&sessionError];
    if (!activateSuccess || sessionError) {
        NSLog(@"❌ 音频会话激活失败: %@", sessionError);
        
        // 如果失败，尝试不带选项激活
        sessionError = nil;
        activateSuccess = [audioSession setActive:YES error:&sessionError];
        if (!activateSuccess || sessionError) {
            NSLog(@"❌ 音频会话二次激活也失败: %@", sessionError);
            sessionError = nil;
        } else {
            NSLog(@"✅ 音频会话已激活（二次尝试成功）");
        }
    } else {
        NSLog(@"✅ 音频会话已激活");
    }
    
    // 验证最终状态
    NSLog(@"📋 [音频会话] 最终状态:");
    NSLog(@"   类别: %@", audioSession.category);
    NSLog(@"   模式: %@", audioSession.mode);
    NSLog(@"   选项: %lu", (unsigned long)audioSession.categoryOptions);
    NSLog(@"   采样率: %.0f Hz", audioSession.sampleRate);
    NSLog(@"   混音状态: %@", (audioSession.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) ? @"✅ 允许" : @"❌ 禁止");
}

@end
