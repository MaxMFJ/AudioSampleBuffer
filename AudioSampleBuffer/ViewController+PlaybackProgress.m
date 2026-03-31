//
//  ViewController+PlaybackProgress.m
//  AudioSampleBuffer
//
//  播放进度条扩展 - 为 ViewController 添加进度条功能
//

#import "ViewController+PlaybackProgress.h"
#import "ViewController+Private.h"
#import <objc/runtime.h>

// 关联对象的 key
static const void *kProgressViewKey = &kProgressViewKey;

@implementation ViewController (PlaybackProgress)

#pragma mark - 属性访问

- (AudioProgressView *)progressView {
    return objc_getAssociatedObject(self, kProgressViewKey);
}

- (void)setProgressView:(AudioProgressView *)progressView {
    objc_setAssociatedObject(self, kProgressViewKey, progressView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 私有属性访问

/// 获取播放器
- (AudioSpectrumPlayer *)playbackPlayer {
    return self.player;
}

#pragma mark - 设置

- (void)setupProgressView {
    CGFloat screenWidth  = self.view.bounds.size.width;
    CGFloat screenHeight = self.view.bounds.size.height;

    CGFloat safeAreaBottom = 0;
    if (@available(iOS 11.0, *)) {
        safeAreaBottom = self.view.safeAreaInsets.bottom;
    }

    // 进度条放在底部播放栏（高100pt）的顶部区域，避免与播放按钮重叠
    // 底部播放栏起始 Y = screenHeight - safeAreaBottom - 100
    // 进度条高度 36pt，放在播放栏起始 Y 的上方贴合
    CGFloat progressHeight = 36;
    CGFloat playBarTop     = screenHeight - safeAreaBottom - 100;
    CGFloat progressY      = playBarTop - progressHeight;

    UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, progressY, screenWidth, progressHeight)];
    containerView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    containerView.tag = 9999;

    // 进度条视图
    AudioProgressView *progressView = [[AudioProgressView alloc] initWithFrame:CGRectMake(0, 0, screenWidth, progressHeight)];
    progressView.delegate = self;
    progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    progressView.progressColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.5 alpha:1.0];
    progressView.trackColor    = [UIColor colorWithWhite:0.2 alpha:0.8];
    progressView.thumbColor    = [UIColor whiteColor];
    progressView.timeTextColor = [UIColor whiteColor];
    progressView.backgroundColor = [UIColor clearColor];

    [containerView addSubview:progressView];
    [self.view addSubview:containerView];
    self.progressView = progressView;

    NSLog(@"✅ 进度条已创建（播放栏上方），容器位置: (%.0f, %.0f)",
          containerView.frame.origin.x, containerView.frame.origin.y);
}

#pragma mark - 进度更新

- (void)updateProgressWithCurrentTime:(NSTimeInterval)currentTime {
    [self.progressView updateCurrentTime:currentTime];
}

- (void)updateProgressWithDuration:(NSTimeInterval)duration {
    [self.progressView updateDuration:duration];
}

- (void)resetProgress {
    [self.progressView reset];
}

- (void)setProgressViewHidden:(BOOL)hidden animated:(BOOL)animated {
    if (!self.progressView) return;
    
    // 获取容器视图
    UIView *containerView = [self.view viewWithTag:9999];
    UIView *targetView = containerView ?: self.progressView;
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            targetView.alpha = hidden ? 0.0 : 1.0;
        }];
    } else {
        targetView.alpha = hidden ? 0.0 : 1.0;
    }
    
    targetView.userInteractionEnabled = !hidden;
}

#pragma mark - AudioProgressViewDelegate

- (void)audioProgressView:(AudioProgressView *)progressView didSeekToTime:(NSTimeInterval)time {
    AudioSpectrumPlayer *player = [self playbackPlayer];
    if (player) {
        [player seekToTime:time];
        NSLog(@"🎵 进度条跳转到: %.2f 秒", time);
    }
}

- (void)audioProgressViewDidBeginSeeking:(AudioProgressView *)progressView {
    NSLog(@"👆 开始拖拽进度条");
}

- (void)audioProgressViewDidEndSeeking:(AudioProgressView *)progressView {
    NSLog(@"👆 结束拖拽进度条");
}

@end
