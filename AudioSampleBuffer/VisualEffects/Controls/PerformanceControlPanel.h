//
//  PerformanceControlPanel.h
//  AudioSampleBuffer
//
//  性能配置控制面板
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PerformanceControlDelegate;

@interface PerformanceControlPanel : UIView

@property (nonatomic, weak) id<PerformanceControlDelegate> delegate;
@property (nonatomic, assign) BOOL automaticVideoEnabled;
@property (nonatomic, strong) NSMutableDictionary *currentSettings;  // 公开属性

- (void)showAnimated:(BOOL)animated;
- (void)hideAnimated:(BOOL)animated;
- (void)setCurrentSettings:(NSDictionary *)settings;

@end

@protocol PerformanceControlDelegate <NSObject>

- (void)performanceControlDidUpdateSettings:(NSDictionary *)settings;
@optional
- (void)performanceControlDidChangeAutomaticVideoEnabled:(BOOL)enabled;
- (void)performanceControlShowVideoTimelineEvidence;
- (void)performanceControlChooseBilibiliVideo;

@end

NS_ASSUME_NONNULL_END

