//
//  ViewController+PlaybackProgress.m
//  AudioSampleBuffer
//
//  播放进度条扩展 - 为 ViewController 添加进度条功能
//

#import "ViewController+PlaybackProgress.h"
#import "AudioSpectrumPlayer.h"
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

/// 获取播放器（通过 KVC）
- (AudioSpectrumPlayer *)playbackPlayer {
    return [self valueForKey:@"player"];
}

#pragma mark - 设置

- (void)setupProgressView {
    // 计算进度条位置 - 放在屏幕最底部
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat screenHeight = self.view.bounds.size.height;
    
    CGFloat progressHeight = 50;  // 增加高度以容纳时间标签
    CGFloat sidePadding = 0;  // 无边距，全宽
    
    // 检查是否有底部安全区域
    CGFloat safeAreaBottom = 0;
    if (@available(iOS 11.0, *)) {
        safeAreaBottom = self.view.safeAreaInsets.bottom;
    }
    
    // 放在屏幕最底部，考虑安全区域
    CGFloat progressY = screenHeight - progressHeight - safeAreaBottom;
    CGFloat progressWidth = screenWidth;
    
    // 创建容器视图（带毛玻璃效果）
    UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, progressY, screenWidth, progressHeight + safeAreaBottom)];
    containerView.backgroundColor = [UIColor clearColor];
    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    containerView.tag = 9999;  // 用于后续查找
    
    // 添加毛玻璃效果背景
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = containerView.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [containerView addSubview:blurView];
    
    // 添加顶部分割线
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenWidth, 0.5)];
    topLine.backgroundColor = [UIColor colorWithWhite:0.4 alpha:0.5];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [containerView addSubview:topLine];
    
    // 添加顶部渐变边缘
    CAGradientLayer *topGradient = [CAGradientLayer layer];
    topGradient.frame = CGRectMake(0, 0, screenWidth, 3);
    topGradient.colors = @[
        (id)[UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.6].CGColor,
        (id)[UIColor clearColor].CGColor
    ];
    [containerView.layer addSublayer:topGradient];
    
    // 创建进度条视图
    AudioProgressView *progressView = [[AudioProgressView alloc] initWithFrame:CGRectMake(sidePadding, 0, progressWidth, progressHeight)];
    progressView.delegate = self;
    progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // 霓虹风格颜色
    progressView.progressColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    progressView.trackColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    progressView.thumbColor = [UIColor whiteColor];
    progressView.timeTextColor = [UIColor whiteColor];
    progressView.backgroundColor = [UIColor clearColor];
    
    [containerView addSubview:progressView];
    [self.view addSubview:containerView];
    self.progressView = progressView;
    
    NSLog(@"✅ 进度条已创建（底部全宽样式），容器位置: (%.0f, %.0f)", 
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

