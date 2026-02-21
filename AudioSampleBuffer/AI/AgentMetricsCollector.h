//
//  AgentMetricsCollector.h
//  AudioSampleBuffer
//
//  指标采集器 - 采集 Agent 运行指标，支持闭环优化
//  Planning + Reflection Agent 架构核心组件
//

#import <Foundation/Foundation.h>
#import "AgentGoalManager.h"
#import "EffectDecisionAgent.h"
#import "MusicStyleClassifier.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 决策事件

/// 决策事件类型
typedef NS_ENUM(NSUInteger, DecisionEventType) {
    DecisionEventTypeStarted,           // 决策开始
    DecisionEventTypeCompleted,         // 决策完成
    DecisionEventTypeUserOverride,      // 用户覆盖
    DecisionEventTypeLLMCalled,         // 调用 LLM
    DecisionEventTypeLLMSuccess,        // LLM 成功
    DecisionEventTypeLLMFailed,         // LLM 失败
    DecisionEventTypeCacheHit,          // 缓存命中
    DecisionEventTypeRuleUsed,          // 使用规则
    DecisionEventTypeLearningUsed,      // 使用学习
    DecisionEventTypeFallback,          // 降级
};

/// 决策事件
@interface DecisionEvent : NSObject

@property (nonatomic, assign) DecisionEventType type;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, copy, nullable) NSString *songName;
@property (nonatomic, assign) MusicStyle style;
@property (nonatomic, assign) VisualEffectType effect;
@property (nonatomic, assign) DecisionSource source;
@property (nonatomic, assign) float confidence;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, strong, nullable) NSDictionary *metadata;

+ (instancetype)eventWithType:(DecisionEventType)type;

@end

#pragma mark - 时间窗口统计

/// 统计时间窗口
typedef NS_ENUM(NSUInteger, MetricsTimeWindow) {
    MetricsTimeWindowHour,      // 最近 1 小时
    MetricsTimeWindowDay,       // 最近 24 小时
    MetricsTimeWindowWeek,      // 最近 7 天
    MetricsTimeWindowMonth,     // 最近 30 天
    MetricsTimeWindowAll,       // 全部
};

#pragma mark - 指标快照

/// 指标快照
@interface MetricsSnapshot : NSObject

@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) AgentMetrics *metrics;
@property (nonatomic, assign) MetricsTimeWindow timeWindow;

@end

#pragma mark - 成本控制

/// 成本控制配置
@interface CostControlConfig : NSObject <NSSecureCoding>

@property (nonatomic, assign) NSInteger dailyLLMBudget;         // 每日 LLM 调用预算
@property (nonatomic, assign) NSInteger currentLLMCalls;        // 当前 LLM 调用次数
@property (nonatomic, strong) NSDate *budgetResetDate;          // 预算重置日期
@property (nonatomic, assign) BOOL forceLocalOnBudgetExceeded;  // 超预算时强制本地

+ (instancetype)defaultConfig;

- (BOOL)isBudgetExceeded;
- (void)incrementLLMCalls;
- (void)resetIfNeeded;

@end

#pragma mark - 指标采集器

/// 指标采集器 - 收集和计算 Agent 运行指标
@interface AgentMetricsCollector : NSObject

/// 单例
+ (instancetype)sharedCollector;

/// 成本控制配置
@property (nonatomic, strong) CostControlConfig *costControl;

/// 是否启用自动采集
@property (nonatomic, assign) BOOL autoCollectionEnabled;

/// 采集间隔（秒）
@property (nonatomic, assign) NSTimeInterval collectionInterval;

#pragma mark - 事件记录

/// 记录决策事件
- (void)recordEvent:(DecisionEvent *)event;

/// 记录决策开始
- (void)recordDecisionStartedForSong:(NSString *)songName;

/// 记录决策完成
- (void)recordDecisionCompletedWithSource:(DecisionSource)source
                                   effect:(VisualEffectType)effect
                               confidence:(float)confidence
                                 duration:(NSTimeInterval)duration;

/// 记录用户覆盖
- (void)recordUserOverrideFromEffect:(VisualEffectType)oldEffect
                            toEffect:(VisualEffectType)newEffect;

/// 记录 LLM 调用
- (void)recordLLMCall:(BOOL)success duration:(NSTimeInterval)duration;

/// 记录缓存命中
- (void)recordCacheHit;

#pragma mark - 指标计算

/// 获取当前指标
- (AgentMetrics *)collectCurrentMetrics;

/// 获取指定时间窗口的指标
- (AgentMetrics *)collectMetricsForTimeWindow:(MetricsTimeWindow)window;

/// 获取特定风格的指标
- (AgentMetrics *)collectMetricsForStyle:(MusicStyle)style;

#pragma mark - 满意度计算

/// 计算用户满意度
/// 基于：1) 覆盖率 2) 跳过率 3) 完整收听率
- (float)calculateUserSatisfaction;

/// 计算风格多样性
/// 基于最近 N 次决策使用的特效种类数
- (float)calculateStyleDiversity;

/// 计算 LLM 调用率
- (float)calculateLLMCallRate;

/// 计算覆盖率
- (float)calculateOverrideRate;

/// 计算缓存命中率
- (float)calculateCacheHitRate;

/// 计算平均决策延迟
- (NSTimeInterval)calculateAverageDecisionLatency;

#pragma mark - 趋势分析

/// 获取指标趋势（比较两个时间窗口）
- (NSDictionary<NSString *, NSNumber *> *)getMetricsTrend:(MetricsTimeWindow)current
                                               compareTo:(MetricsTimeWindow)previous;

/// 获取指标历史快照
- (NSArray<MetricsSnapshot *> *)getMetricsHistory:(NSInteger)count;

#pragma mark - 成本控制

/// 检查是否应该强制使用本地策略
- (BOOL)shouldForceLocalStrategy;

/// 获取今日剩余 LLM 预算
- (NSInteger)remainingLLMBudgetToday;

/// 重置每日预算
- (void)resetDailyBudget;

#pragma mark - 报告

/// 生成指标摘要报告
- (NSString *)generateSummaryReport;

/// 获取实时统计数据（用于 UI 显示）
- (NSDictionary *)getRealTimeStats;

#pragma mark - 持久化

/// 保存指标数据
- (void)saveMetrics;

/// 加载指标数据
- (void)loadMetrics;

/// 清除历史数据
- (void)clearHistory;

@end

NS_ASSUME_NONNULL_END
