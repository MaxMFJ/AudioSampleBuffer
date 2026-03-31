//
//  HolographicControlPanel.h
//  AudioSampleBuffer
//
//  全息效果专用控制面板
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HolographicControlDelegate <NSObject>
- (void)holographicControlDidUpdateSettings:(NSDictionary *)settings;
@end

/**
 * 全息效果控制面板
 * 提供转动、扩散、音乐响应等效果的控制
 */
@interface HolographicControlPanel : UIView

@property (nonatomic, weak) id<HolographicControlDelegate> delegate;

/**
 * 显示控制面板
 */
- (void)showAnimated:(BOOL)animated;

/**
 * 隐藏控制面板
 */
- (void)hideAnimated:(BOOL)animated;

/**
 * 设置当前参数值
 */
- (void)setCurrentSettings:(NSDictionary *)settings;

@end

NS_ASSUME_NONNULL_END

