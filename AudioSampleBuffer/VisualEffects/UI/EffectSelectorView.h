//
//  EffectSelectorView.h
//  AudioSampleBuffer
//
//  特效选择界面
//

#import <UIKit/UIKit.h>
#import "../Core/VisualEffectType.h"

NS_ASSUME_NONNULL_BEGIN

@protocol EffectSelectorDelegate <NSObject>
@optional
- (void)effectSelector:(id)selector didSelectEffect:(VisualEffectType)effectType;
- (void)effectSelector:(id)selector didChangeSettings:(NSDictionary *)settings;
- (void)effectSelectorDidRequestPreview:(id)selector effect:(VisualEffectType)effectType;
@end

/**
 * 特效卡片视图
 */
@interface EffectCardView : UIView

@property (nonatomic, assign) VisualEffectType effectType;
@property (nonatomic, strong) VisualEffectInfo *effectInfo;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) BOOL isSupported;

- (instancetype)initWithEffectInfo:(VisualEffectInfo *)effectInfo;
- (void)updateSelectionState:(BOOL)selected animated:(BOOL)animated;

@end

/**
 * 分类按钮
 */
@interface CategoryButton : UIButton

@property (nonatomic, assign) EffectCategory category;
@property (nonatomic, assign) BOOL isSelected;

- (instancetype)initWithCategory:(EffectCategory)category;
- (void)updateSelectionState:(BOOL)selected animated:(BOOL)animated;

@end

/**
 * 特效选择器主视图
 */
@interface EffectSelectorView : UIView

@property (nonatomic, weak) id<EffectSelectorDelegate> delegate;
@property (nonatomic, assign) VisualEffectType currentEffectType;
@property (nonatomic, assign) BOOL isVisible;

/**
 * 显示/隐藏选择器
 */
- (void)showWithAnimation:(BOOL)animated;
- (void)hideWithAnimation:(BOOL)animated;

/**
 * 更新当前选中的特效
 */
- (void)setCurrentEffectType:(VisualEffectType)effectType animated:(BOOL)animated;

/**
 * 刷新设备支持状态
 */
- (void)refreshDeviceSupport;

@end

/**
 * 设置面板
 */
@interface EffectSettingsPanel : UIView

@property (nonatomic, weak) id<EffectSelectorDelegate> delegate;
@property (nonatomic, assign) VisualEffectType currentEffectType;

- (void)updateForEffectType:(VisualEffectType)effectType;
- (void)showWithAnimation:(BOOL)animated;
- (void)hideWithAnimation:(BOOL)animated;

@end

/**
 * 预览窗口
 */
@interface EffectPreviewWindow : UIView

@property (nonatomic, assign) VisualEffectType previewEffectType;

- (void)showPreviewForEffect:(VisualEffectType)effectType;
- (void)hidePreview;

@end

NS_ASSUME_NONNULL_END
