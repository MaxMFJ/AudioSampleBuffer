#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ADSpectraStyle) {
    ADSpectraStyleRect = 0, //直角
    ADSpectraStyleRound //圆角
};

// 频谱颜色模式
typedef NS_ENUM(NSInteger, ADSpectrumColorMode) {
    ADSpectrumColorModeRainbow = 0,      // 彩虹渐变（默认）- 经典绚丽效果
    ADSpectrumColorModeSingleGradient,   // 单色渐变 - 使用主色的深浅变化
    ADSpectrumColorModeDualGradient,     // 双色渐变 - 主色到副色的平滑过渡
    ADSpectrumColorModeCustomTheme       // 自定义主题 - 主副色动态交替
};

@interface SpectrumView : UIView

@property (nonatomic, assign) CGFloat barWidth;
@property (nonatomic, assign) CGFloat space;
@property (nonatomic, assign) CGFloat bottomSpace;
@property (nonatomic, assign) CGFloat topSpace;

#pragma mark - 颜色配置（AI Agent 可调度参数）

// 颜色模式
@property (nonatomic, assign) ADSpectrumColorMode colorMode;

// 主色（用于单色渐变、双色渐变起始色、自定义主题）
@property (nonatomic, strong) UIColor *primaryColor;

// 副色（用于双色渐变结束色、自定义主题交替色）
@property (nonatomic, strong) UIColor *secondaryColor;

// 颜色饱和度 (0.0 - 1.0, 默认 1.0)，影响彩虹模式的鲜艳度
@property (nonatomic, assign) CGFloat colorSaturation;

// 颜色亮度倍数 (0.5 - 2.0, 默认 1.0)，控制整体明亮程度
@property (nonatomic, assign) CGFloat colorBrightness;

// 色相偏移 (0.0 - 1.0)，用于彩虹模式的初始色相位置
@property (nonatomic, assign) CGFloat hueShift;

// 便捷方法：应用预设主题
- (void)applyTheme:(NSDictionary *)themeConfig;

// 便捷方法：设置单色模式
- (void)setSingleColor:(UIColor *)color brightness:(CGFloat)brightness;

// 便捷方法：设置双色渐变模式
- (void)setGradientFromColor:(UIColor *)fromColor toColor:(UIColor *)toColor;

- (void)updateSpectra:(NSArray *)spectra withStype:(ADSpectraStyle)style;

// 控制频谱视图的暂停和恢复
- (void)pauseRendering;
- (void)resumeRendering;

@end

NS_ASSUME_NONNULL_END
