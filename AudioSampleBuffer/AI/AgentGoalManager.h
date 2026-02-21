//
//  AgentGoalManager.h
//  AudioSampleBuffer
//
//  目标管理器 - 管理 Agent 目标权重与评估
//  Planning + Reflection Agent 架构核心组件
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Agent 指标

/// Agent 运行指标
@interface AgentMetrics : NSObject <NSCopying>

@property (nonatomic, assign) float userSatisfaction;    // 用户满意度 [0-1]
@property (nonatomic, assign) float llmCallRate;         // LLM 调用比例 [0-1]
@property (nonatomic, assign) float styleDiversity;      // 风格多样性 [0-1]
@property (nonatomic, assign) float overrideRate;        // 用户覆盖率 [0-1]
@property (nonatomic, assign) float decisionLatency;     // 决策延迟 (秒)
@property (nonatomic, assign) float cacheHitRate;        // 缓存命中率 [0-1]
@property (nonatomic, assign) NSInteger totalDecisions;  // 总决策数

+ (instancetype)metricsWithDefaults;

@end

#pragma mark - 目标权重

/// 目标权重配置
@interface GoalWeights : NSObject <NSSecureCoding, NSCopying>

@property (nonatomic, assign) float satisfaction;   // 满意度权重
@property (nonatomic, assign) float cost;           // 成本权重 (LLM 调用)
@property (nonatomic, assign) float diversity;      // 多样性权重
@property (nonatomic, assign) float stability;      // 稳定性权重
@property (nonatomic, assign) float latency;        // 延迟权重

+ (instancetype)defaultWeights;

/// 使用软归一化，保留调整效果
- (void)softNormalize;

/// 获取权重总和
- (float)totalWeight;

@end

#pragma mark - 阈值配置

/// 可配置的阈值参数
@interface GoalThresholds : NSObject <NSSecureCoding>

// 触发调整的阈值
@property (nonatomic, assign) float overrideRateHigh;       // 覆盖率高阈值 (默认 0.4)
@property (nonatomic, assign) float llmCallRateHigh;        // LLM 调用率高阈值 (默认 0.6)
@property (nonatomic, assign) float satisfactionLow;        // 满意度低阈值 (默认 0.5)
@property (nonatomic, assign) float diversityLow;           // 多样性低阈值 (默认 0.3)
@property (nonatomic, assign) float latencyHigh;            // 延迟高阈值 (默认 3.0 秒)

// 权重调整步长
@property (nonatomic, assign) float majorAdjustStep;        // 主要调整步长 (默认 0.05)
@property (nonatomic, assign) float minorAdjustStep;        // 次要调整步长 (默认 0.03)

// 权重边界
@property (nonatomic, assign) float minWeight;              // 最小权重 (默认 0.05)
@property (nonatomic, assign) float maxWeight;              // 最大权重 (默认 0.60)

// 策略建议阈值
@property (nonatomic, assign) float cacheHitRateLow;        // 缓存命中率低阈值 (默认 0.3)
@property (nonatomic, assign) float costWeightHigh;         // 成本权重高阈值 (默认 0.3)

+ (instancetype)defaultThresholds;

@end

#pragma mark - 评分结果

/// 评分结果（包含正向得分和解释）
@interface GoalEvaluationResult : NSObject

@property (nonatomic, assign) float totalScore;             // 总分 [0-100]
@property (nonatomic, assign) float satisfactionScore;      // 满意度分数 [0-100]
@property (nonatomic, assign) float efficiencyScore;        // 效率分数（成本相关）[0-100]
@property (nonatomic, assign) float diversityScore;         // 多样性分数 [0-100]
@property (nonatomic, assign) float stabilityScore;         // 稳定性分数 [0-100]
@property (nonatomic, assign) float responsivenessScore;    // 响应速度分数 [0-100]
@property (nonatomic, copy) NSString *interpretation;       // 总分解释

@end

#pragma mark - 目标管理器

/// 目标管理器 - 管理 Agent 决策目标与权重动态调整
@interface AgentGoalManager : NSObject

/// 单例
+ (instancetype)sharedManager;

/// 当前目标权重
@property (nonatomic, strong, readonly) GoalWeights *currentWeights;

/// 阈值配置
@property (nonatomic, strong) GoalThresholds *thresholds;

/// 历史指标记录
@property (nonatomic, strong, readonly) NSArray<AgentMetrics *> *metricsHistory;

/// 是否启用自动保存（默认 YES）
@property (nonatomic, assign) BOOL autoSaveEnabled;

/// 自动保存间隔（秒，默认 60）
@property (nonatomic, assign) NSTimeInterval autoSaveInterval;

#pragma mark - 评估

/// 计算综合目标得分（新版：全正向 0-100 分）
/// @param metrics 当前指标
/// @return 评估结果（包含分数和解释）
- (GoalEvaluationResult *)evaluateMetricsWithResult:(AgentMetrics *)metrics;

/// 计算综合目标得分（简化版）
/// @param metrics 当前指标
/// @return 目标得分 [0-100]
- (float)evaluateMetrics:(AgentMetrics *)metrics;

/// 获取各子目标得分明细
/// @param metrics 当前指标
/// @return 子目标得分字典（全正向 0-100）
- (NSDictionary<NSString *, NSNumber *> *)evaluateMetricsDetailed:(AgentMetrics *)metrics;

#pragma mark - 权重调整

/// 根据指标自动调整权重（优化版：避免稀释）
/// @param metrics 当前指标
- (void)adjustWeightsWithMetrics:(AgentMetrics *)metrics;

/// 手动设置权重
/// @param weights 新权重
- (void)setWeights:(GoalWeights *)weights;

/// 重置为默认权重
- (void)resetWeights;

#pragma mark - 策略建议

/// 获取当前策略建议
/// @param metrics 当前指标
/// @return 策略建议数组
- (NSArray<NSString *> *)getStrategyRecommendations:(AgentMetrics *)metrics;

/// 是否应该优先使用本地规则
- (BOOL)shouldPreferLocalRules:(AgentMetrics *)metrics;

/// 是否应该增加 LLM 调用
- (BOOL)shouldIncreaseLLMUsage:(AgentMetrics *)metrics;

#pragma mark - 持久化

/// 保存权重到磁盘
- (void)saveWeights;

/// 加载权重
- (void)loadWeights;

/// 记录指标历史（优化版：延迟批量保存）
- (void)recordMetrics:(AgentMetrics *)metrics;

/// 强制立即保存所有数据
- (void)flushToDisk;

@end

NS_ASSUME_NONNULL_END
