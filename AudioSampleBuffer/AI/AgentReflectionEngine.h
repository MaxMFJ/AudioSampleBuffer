//
//  AgentReflectionEngine.h
//  AudioSampleBuffer
//
//  反思引擎 - 决策复盘与策略优化
//  Planning + Reflection Agent 架构核心组件
//

#import <Foundation/Foundation.h>
#import "EffectDecisionAgent.h"
#import "MusicStyleClassifier.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 决策记录

/// 决策记录（用于反思分析）
@interface ReflectionDecisionRecord : NSObject <NSSecureCoding>

@property (nonatomic, assign) DecisionSource source;        // 决策来源
@property (nonatomic, assign) BOOL wasCorrect;              // 是否正确（未被覆盖）
@property (nonatomic, assign) MusicStyle style;             // 音乐风格
@property (nonatomic, assign) VisualEffectType effect;      // 选择的特效
@property (nonatomic, assign) float confidence;             // 置信度
@property (nonatomic, assign) NSTimeInterval decisionTime;  // 决策耗时
@property (nonatomic, strong) NSDate *timestamp;            // 时间戳
@property (nonatomic, copy, nullable) NSString *songName;   // 歌曲名
@property (nonatomic, assign) BOOL userOverrode;            // 用户是否覆盖

+ (instancetype)recordWithSource:(DecisionSource)source
                       wasCorrect:(BOOL)correct
                           style:(MusicStyle)style
                          effect:(VisualEffectType)effect;

@end

#pragma mark - 决策来源统计

/// 各决策来源的准确率统计
@interface SourceAccuracyStats : NSObject

@property (nonatomic, assign) NSInteger totalCount;         // 总数
@property (nonatomic, assign) NSInteger correctCount;       // 正确数
@property (nonatomic, assign) float accuracy;               // 准确率
@property (nonatomic, assign) float averageConfidence;      // 平均置信度
@property (nonatomic, assign) float averageDecisionTime;    // 平均决策时间

- (void)updateWithCorrect:(BOOL)correct confidence:(float)confidence time:(NSTimeInterval)time;

@end

#pragma mark - 反思分析结果

/// 反思分析结果
@interface ReflectionAnalysisResult : NSObject

@property (nonatomic, strong) NSDictionary<NSNumber *, SourceAccuracyStats *> *sourceStats;  // 各来源统计
@property (nonatomic, assign) float overallAccuracy;        // 整体准确率
@property (nonatomic, assign) float overrideRate;           // 覆盖率
@property (nonatomic, assign) float llmAccuracy;            // LLM 准确率
@property (nonatomic, assign) float ruleAccuracy;           // 规则准确率
@property (nonatomic, assign) float cacheAccuracy;          // 缓存准确率
@property (nonatomic, assign) float learningAccuracy;       // 自学习准确率
@property (nonatomic, assign) float userPrefAccuracy;       // 用户偏好准确率
@property (nonatomic, strong) NSArray<NSString *> *insights;  // 洞察建议
@property (nonatomic, strong) NSDictionary<NSNumber *, NSNumber *> *styleProblemRates;  // 各风格问题率
@property (nonatomic, assign) NSInteger totalRecords;       // 总记录数

@end

#pragma mark - 策略调整建议

typedef NS_ENUM(NSUInteger, StrategyAdjustmentType) {
    StrategyAdjustmentReduceLLMPriority,       // 降低 LLM 优先级
    StrategyAdjustmentIncreaseLLMPriority,     // 提高 LLM 优先级
    StrategyAdjustmentIncreaseRulePriority,    // 提高规则优先级
    StrategyAdjustmentReduceRulePriority,      // 降低规则优先级
    StrategyAdjustmentExpandCache,             // 扩大缓存
    StrategyAdjustmentEnhanceLearning,         // 增强学习
    StrategyAdjustmentStyleSpecificRule,       // 风格特定规则
    StrategyAdjustmentEmergencyMode,           // 紧急模式
    StrategyAdjustmentIncreaseUserPreference,  // 增加用户偏好权重
};

/// 反思阈值配置（可动态调整）
@interface ReflectionThresholds : NSObject <NSSecureCoding>

@property (nonatomic, assign) float emergencyAccuracyThreshold;    // 紧急模式触发阈值 (默认 0.5)
@property (nonatomic, assign) float highOverrideRateThreshold;     // 高覆盖率阈值 (默认 0.7)
@property (nonatomic, assign) float lowSourceAccuracyThreshold;    // 低来源准确率阈值 (默认 0.4)
@property (nonatomic, assign) float highSourceAccuracyThreshold;   // 高来源准确率阈值 (默认 0.8)
@property (nonatomic, assign) float styleProblemsThreshold;        // 风格问题率阈值 (默认 0.4)
@property (nonatomic, assign) float adjustmentStep;                // 每次调整步长 (默认 0.1)
@property (nonatomic, assign) NSInteger minRecordsForAdjustment;   // 最少记录数 (默认 10)

+ (instancetype)defaultThresholds;

@end

@interface StrategyAdjustment : NSObject

@property (nonatomic, assign) StrategyAdjustmentType type;
@property (nonatomic, assign) float priority;               // 优先级 [0-1]
@property (nonatomic, copy) NSString *reason;               // 调整原因
@property (nonatomic, strong, nullable) NSDictionary *parameters;  // 调整参数

+ (instancetype)adjustmentWithType:(StrategyAdjustmentType)type
                          priority:(float)priority
                            reason:(NSString *)reason;

@end

#pragma mark - 策略管理器协议

@protocol StrategyManagerProtocol <NSObject>

- (void)reduceLLMPriority:(float)amount;
- (void)increaseLLMPriority:(float)amount;
- (void)increaseRulePriority:(float)amount;
- (void)reduceRulePriority:(float)amount;
- (void)setLocalRulesConfidenceThreshold:(float)threshold;
- (void)setLLMCallEnabled:(BOOL)enabled;
- (void)increaseUserPreferenceWeight:(float)amount;
- (void)enterEmergencyMode;
- (void)exitEmergencyMode;
- (float)currentLLMPriority;
- (float)currentRulePriority;
- (void)saveStrategyState;

@end

#pragma mark - 反思引擎

/// 反思引擎 - 分析决策历史，优化策略
@interface AgentReflectionEngine : NSObject

/// 单例
+ (instancetype)sharedEngine;

/// 决策记录
@property (nonatomic, strong, readonly) NSArray<ReflectionDecisionRecord *> *decisionRecords;

/// 最近一次分析结果
@property (nonatomic, strong, readonly, nullable) ReflectionAnalysisResult *lastAnalysisResult;

/// 策略管理器
@property (nonatomic, weak, nullable) id<StrategyManagerProtocol> strategyManager;

/// 反思阈值配置（可动态调整）
@property (nonatomic, strong) ReflectionThresholds *thresholds;

/// 是否处于紧急模式
@property (nonatomic, assign, readonly) BOOL isEmergencyMode;

#pragma mark - 记录决策

/// 记录一次决策
- (void)recordDecision:(ReflectionDecisionRecord *)record;

/// 记录决策结果（用户是否覆盖）
- (void)recordDecisionOutcome:(NSString *)songName
                  userOverrode:(BOOL)overrode
                    newEffect:(VisualEffectType)newEffect;

/// 批量记录
- (void)recordDecisions:(NSArray<ReflectionDecisionRecord *> *)records;

#pragma mark - 分析

/// 分析所有决策记录
- (ReflectionAnalysisResult *)analyzeAllRecords;

/// 分析指定时间范围的记录
- (ReflectionAnalysisResult *)analyzeRecordsFromDate:(NSDate *)fromDate toDate:(NSDate *)toDate;

/// 分析特定风格的决策
- (ReflectionAnalysisResult *)analyzeRecordsForStyle:(MusicStyle)style;

/// 分析特定来源的决策
- (SourceAccuracyStats *)analyzeSource:(DecisionSource)source;

#pragma mark - 策略更新

/// 根据分析结果生成策略调整建议
- (NSArray<StrategyAdjustment *> *)generateAdjustments:(ReflectionAnalysisResult *)result;

/// 应用策略调整
- (void)applyAdjustments:(NSArray<StrategyAdjustment *> *)adjustments;

/// 自动反思并更新策略
- (void)reflectAndUpdatePolicy;

#pragma mark - ReAct Loop

/// 执行一次 ReAct 循环（Thought -> Action -> Observation）
/// @param currentState 当前状态
/// @param completion 完成回调，返回新状态和动作
- (void)runReActLoopWithState:(NSDictionary *)currentState
                   completion:(void(^)(NSDictionary *newState, NSString *action, NSString *observation))completion;

#pragma mark - 持久化

/// 保存记录
- (void)saveRecords;

/// 加载记录
- (void)loadRecords;

/// 清除记录
- (void)clearRecords;

/// 导出分析报告
- (NSString *)exportAnalysisReport;

@end

NS_ASSUME_NONNULL_END
