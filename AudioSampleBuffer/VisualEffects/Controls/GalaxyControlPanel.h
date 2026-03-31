//
//  GalaxyControlPanel.h
//  AudioSampleBuffer
//
//  星系效果专用控制面板
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GalaxyControlDelegate <NSObject>
- (void)galaxyControlDidUpdateSettings:(NSDictionary *)settings;
@end

/**
 * 星系效果控制面板
 * 提供丰富的参数调节功能
 */
@interface GalaxyControlPanel : UIView

@property (nonatomic, weak) id<GalaxyControlDelegate> delegate;

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

/**
 * 重新加载颜色主题选择器
 */
- (void)reloadColorThemes;

@end

/**
 * 自定义滑块控件
 */
@interface GalaxySlider : UIView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) float value;
@property (nonatomic, assign) float minimumValue;
@property (nonatomic, assign) float maximumValue;
@property (nonatomic, copy) void(^valueChangedBlock)(float value);

- (instancetype)initWithTitle:(NSString *)title
                 minimumValue:(float)min
                 maximumValue:(float)max
                 currentValue:(float)current;

@end

NS_ASSUME_NONNULL_END
