//
//  VinylRecordView.h
//  AudioSampleBuffer
//
//  黑胶唱片动画视图 - 用于替代没有封面的歌曲
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 黑胶唱片动画视图
 * 
 * 特性：
 * - 逼真的黑胶唱片外观，带有纹路效果
 * - 随机生成的中心标签颜色和图案
 * - 光泽反射效果
 * - 旋转动画，可根据播放状态控制
 */
@interface VinylRecordView : UIView

#pragma mark - 属性

/// 是否正在旋转（播放中）
@property (nonatomic, assign, readonly) BOOL isSpinning;

/// 旋转速度（每秒转数，默认 0.5，即 2 秒一圈）
@property (nonatomic, assign) CGFloat rotationsPerSecond;

/// 中心标签的主色调（nil 则随机生成）
@property (nonatomic, strong, nullable) UIColor *labelColor;

/// 唱片边缘的光泽强度（0-1，默认 0.3）
@property (nonatomic, assign) CGFloat glossIntensity;

#pragma mark - 初始化

/// 使用指定大小和种子创建（相同种子生成相同的随机外观）
- (instancetype)initWithFrame:(CGRect)frame seed:(NSUInteger)seed;

/// 使用歌曲名称作为种子（相同歌曲保持一致的外观）
- (instancetype)initWithFrame:(CGRect)frame songName:(NSString *)songName;

#pragma mark - 动画控制

/// 开始旋转动画
- (void)startSpinning;

/// 停止旋转动画（带缓出效果）
- (void)stopSpinning;

/// 暂停旋转动画（保持当前角度）
- (void)pauseSpinning;

/// 恢复旋转动画（从当前角度继续）
- (void)resumeSpinning;

#pragma mark - 外观更新

/// 重新生成随机外观（使用新的随机种子）
- (void)regenerateAppearance;

/// 使用指定种子重新生成外观
- (void)regenerateAppearanceWithSeed:(NSUInteger)seed;

/// 使用歌曲名称重新生成外观
- (void)regenerateAppearanceWithSongName:(NSString *)songName;

@end

NS_ASSUME_NONNULL_END

