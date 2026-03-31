//
//  CyberpunkControlPanel.h
//  AudioSampleBuffer
//
//  赛博朋克效果专用控制面板
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CyberpunkControlDelegate <NSObject>
- (void)cyberpunkControlDidUpdateSettings:(NSDictionary *)settings;
@end

/**
 * 赛博朋克效果控制面板
 * 提供频段和高能效果的开关控制
 */
@interface CyberpunkControlPanel : UIView

@property (nonatomic, weak) id<CyberpunkControlDelegate> delegate;

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

