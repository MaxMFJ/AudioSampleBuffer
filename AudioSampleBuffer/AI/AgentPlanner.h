//
//  AgentPlanner.h
//  AudioSampleBuffer
//
//  规划器 - 多步规划生成与执行追踪
//  Planning + Reflection Agent 架构核心组件
//

#import <Foundation/Foundation.h>
#import "AudioFeatureExtractor.h"
#import "MusicStyleClassifier.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 计划步骤状态

typedef NS_ENUM(NSUInteger, PlanStepStatus) {
    PlanStepStatusPending = 0,      // 待执行
    PlanStepStatusInProgress,       // 执行中
    PlanStepStatusDone,             // 完成
    PlanStepStatusFailed,           // 失败
    PlanStepStatusSkipped,          // 跳过
};

#pragma mark - 计划步骤类型

typedef NS_ENUM(NSUInteger, PlanStepType) {
    PlanStepTypeAnalyzeTrack = 0,       // 分析完整曲目
    PlanStepTypeClassifyStyle,          // 分类音乐风格
    PlanStepTypeGenerateEmotionMap,     // 生成情感映射
    PlanStepTypeAssignEffects,          // 分配特效
    PlanStepTypeValidateTransitions,    // 验证过渡
    PlanStepTypeOptimizeParameters,     // 优化参数
    PlanStepTypeApplyUserPreferences,   // 应用用户偏好
    PlanStepTypeCacheLookup,            // 缓存查找
    PlanStepTypeLLMQuery,               // LLM 查询
    PlanStepTypeFallbackDecision,       // 降级决策
};

#pragma mark - 计划步骤

@interface PlanStep : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *stepId;           // 步骤 ID
@property (nonatomic, assign) PlanStepType type;        // 步骤类型
@property (nonatomic, copy) NSString *stepDescription;  // 步骤描述
@property (nonatomic, assign) PlanStepStatus status;    // 当前状态
@property (nonatomic, assign) NSInteger priority;       // 优先级 (0 最高)
@property (nonatomic, assign) float confidence;         // 完成置信度
@property (nonatomic, strong, nullable) NSDictionary *input;   // 输入数据
@property (nonatomic, strong, nullable) NSDictionary *output;  // 输出数据
@property (nonatomic, strong, nullable) NSError *error;        // 错误信息
@property (nonatomic, strong) NSDate *startTime;        // 开始时间
@property (nonatomic, strong, nullable) NSDate *endTime;       // 结束时间
@property (nonatomic, assign) BOOL isOptional;          // 是否可选
@property (nonatomic, strong, nullable) NSArray<NSString *> *dependencies;  // 依赖的步骤 ID

+ (instancetype)stepWithId:(NSString *)stepId
                      type:(PlanStepType)type
               description:(NSString *)description;

- (NSTimeInterval)duration;

@end

#pragma mark - 执行计划

@interface ExecutionPlan : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *planId;           // 计划 ID
@property (nonatomic, copy) NSString *songName;         // 歌曲名
@property (nonatomic, copy, nullable) NSString *artist; // 艺术家
@property (nonatomic, strong) NSMutableArray<PlanStep *> *steps;  // 步骤列表
@property (nonatomic, assign) float overallProgress;    // 整体进度 [0-1]
@property (nonatomic, strong) NSDate *createdAt;        // 创建时间
@property (nonatomic, strong, nullable) NSDate *completedAt;    // 完成时间
@property (nonatomic, assign) BOOL isRevised;           // 是否被修订过

+ (instancetype)planWithId:(NSString *)planId
                  songName:(NSString *)songName
                    artist:(nullable NSString *)artist;

- (PlanStep * _Nullable)stepWithId:(NSString *)stepId;
- (PlanStep * _Nullable)nextPendingStep;
- (NSArray<PlanStep *> *)completedSteps;
- (NSArray<PlanStep *> *)failedSteps;
- (BOOL)isComplete;
- (BOOL)hasFailures;
- (void)updateProgress;

@end

#pragma mark - 计划上下文

@interface PlanContext : NSObject

@property (nonatomic, copy) NSString *songName;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, strong, nullable) AudioFeatures *audioFeatures;
@property (nonatomic, strong, nullable) MusicStyleResult *styleResult;
@property (nonatomic, assign) BOOL hasCachedDecision;
@property (nonatomic, assign) BOOL hasUserPreference;
@property (nonatomic, assign) BOOL requiresLLM;
@property (nonatomic, assign) float urgency;            // 紧急程度 [0-1]
@property (nonatomic, strong, nullable) NSDictionary *additionalInfo;

+ (instancetype)contextWithSongName:(NSString *)songName artist:(nullable NSString *)artist;

@end

#pragma mark - 计划反馈

@interface PlanFeedback : NSObject

@property (nonatomic, assign) BOOL transitionProblem;       // 过渡问题
@property (nonatomic, assign) BOOL styleMatchProblem;       // 风格匹配问题
@property (nonatomic, assign) BOOL performanceProblem;      // 性能问题
@property (nonatomic, assign) BOOL userOverride;            // 用户覆盖
@property (nonatomic, copy, nullable) NSString *failedStepId;  // 失败步骤
@property (nonatomic, copy, nullable) NSString *feedbackMessage;

+ (instancetype)feedbackWithTransitionProblem:(BOOL)transition;

@end

#pragma mark - 规划器

/// 规划器 - 生成和管理执行计划
@interface AgentPlanner : NSObject

/// 单例
+ (instancetype)sharedPlanner;

/// 当前活跃计划
@property (nonatomic, strong, readonly, nullable) ExecutionPlan *currentPlan;

/// 历史计划
@property (nonatomic, strong, readonly) NSArray<ExecutionPlan *> *planHistory;

#pragma mark - 计划生成

/// 根据上下文生成执行计划
/// @param context 计划上下文
/// @return 执行计划
- (ExecutionPlan *)generatePlanWithContext:(PlanContext *)context;

/// 生成快速计划（仅基本步骤）
- (ExecutionPlan *)generateQuickPlanForSong:(NSString *)songName artist:(nullable NSString *)artist;

/// 生成完整分析计划
- (ExecutionPlan *)generateFullAnalysisPlanForSong:(NSString *)songName artist:(nullable NSString *)artist;

#pragma mark - 计划执行

/// 标记步骤开始
- (void)markStepInProgress:(NSString *)stepId inPlan:(ExecutionPlan *)plan;

/// 标记步骤完成
- (void)markStepDone:(NSString *)stepId
              inPlan:(ExecutionPlan *)plan
          withOutput:(nullable NSDictionary *)output;

/// 标记步骤失败
- (void)markStepFailed:(NSString *)stepId
                inPlan:(ExecutionPlan *)plan
             withError:(NSError *)error;

/// 跳过步骤
- (void)skipStep:(NSString *)stepId inPlan:(ExecutionPlan *)plan reason:(NSString *)reason;

#pragma mark - 计划修订

/// 根据反馈修订计划
/// @param plan 原计划
/// @param feedback 反馈信息
/// @return 修订后的计划
- (ExecutionPlan *)revisePlan:(ExecutionPlan *)plan withFeedback:(PlanFeedback *)feedback;

/// 添加步骤到计划
- (void)addStep:(PlanStep *)step toPlan:(ExecutionPlan *)plan afterStep:(nullable NSString *)afterStepId;

/// 移除步骤
- (void)removeStep:(NSString *)stepId fromPlan:(ExecutionPlan *)plan;

#pragma mark - 计划评估

/// 评估计划执行效果
/// @param plan 已执行的计划
/// @return 评估结果字典
- (NSDictionary *)evaluatePlan:(ExecutionPlan *)plan;

/// 获取计划执行统计
- (NSDictionary *)getPlanStatistics;

#pragma mark - 持久化

/// 保存计划历史
- (void)savePlanHistory;

/// 加载计划历史
- (void)loadPlanHistory;

/// 清除历史
- (void)clearHistory;

@end

NS_ASSUME_NONNULL_END
