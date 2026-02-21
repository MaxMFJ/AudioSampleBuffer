//
//  UserContext.h
//  AudioSampleBuffer
//
//  用户情境模型 - 记录当前使用环境和状态
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 使用场景枚举

typedef NS_ENUM(NSUInteger, UsageScene) {
    UsageSceneUnknown = 0,
    UsageSceneMorning,        // 早晨 (6:00-9:00)
    UsageSceneDaytime,        // 白天 (9:00-18:00)
    UsageSceneEvening,        // 傍晚 (18:00-21:00)
    UsageSceneNight,          // 夜晚 (21:00-24:00)
    UsageSceneLateNight,      // 深夜 (0:00-6:00)
};

#pragma mark - 用户情境

@interface UserContext : NSObject <NSCoding, NSSecureCoding>

/// 当前时间（0-23小时）
@property (nonatomic, assign) NSInteger hourOfDay;

/// 是否是周末
@property (nonatomic, assign) BOOL isWeekend;

/// 使用场景
@property (nonatomic, assign) UsageScene usageScene;

/// 近期听歌的平均能量水平 [0-1]
@property (nonatomic, assign) float recentListeningEnergy;

/// 上次手动选择的特效
@property (nonatomic, copy, nullable) NSString *lastManualEffectChoice;

/// 连续播放时长（秒）
@property (nonatomic, assign) NSTimeInterval sessionDuration;

/// 今日播放次数
@property (nonatomic, assign) NSInteger todayPlayCount;

/// 创建当前上下文
+ (instancetype)currentContext;

/// 根据时间获取使用场景
+ (UsageScene)usageSceneForHour:(NSInteger)hour;

/// 获取场景名称
+ (NSString *)nameForScene:(UsageScene)scene;

@end

NS_ASSUME_NONNULL_END
