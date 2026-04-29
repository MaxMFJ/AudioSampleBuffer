//
//  RhythmColorMaskEffect.h
//  律动彩色蒙版特效模块。可独立扩展更多 style；ViewController 只负责创建 view、
//  添加到层级、转发 trigger / tick / reset，不再持有色散内部状态。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RhythmColorMaskStyle) {
    RhythmColorMaskStyleHueCycle = 0,   // 红/蓝/橙/青绿/紫/黄 6 色循环
    RhythmColorMaskStyleWarmCool = 1,   // 暖红 ↔ 冷蓝交替
    RhythmColorMaskStyleNeon     = 2,   // 霓虹粉/青/紫
};

/// 律动色彩蒙版：每个 beat 触发后切色 + 单轴 x/y 微位移，按帧自衰减。
/// alpha=0 / shiftMax=0 时 view 输出完全 identity，可放心保留在层级中。
@interface RhythmColorMaskEffect : UIView

@property (nonatomic, assign) RhythmColorMaskStyle style;

/// 蒙版 alpha 上限（外部按色散 slider 计算，例如 0.5 × sliderValue）
@property (nonatomic, assign) CGFloat maxAlpha;

/// 蒙版位移上限（像素，例如 8 × sliderValue）
@property (nonatomic, assign) CGFloat shiftMax;

/// beat 触发时调用：切下一种颜色 + 设置位移目标。
/// @param strongMix 0..1，当前节拍的强弱混合（影响 intensity 与位移幅度）
/// @param axis 0=x 轴位移，1=y 轴位移
- (void)triggerOnBeatWithStrongMix:(float)strongMix axis:(NSInteger)axis;

/// 每帧调用：按 dt 衰减 alpha 与位移并应用到 self。
- (void)tickWithDelta:(CFTimeInterval)dt;

/// 律动关闭时复位：alpha=0、transform=identity、内部状态清零。
- (void)reset;

@end

NS_ASSUME_NONNULL_END
