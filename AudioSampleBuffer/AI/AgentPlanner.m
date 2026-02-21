//
//  AgentPlanner.m
//  AudioSampleBuffer
//
//  规划器实现
//

#import "AgentPlanner.h"

static NSString *const kPlanHistoryFile = @"PlanHistory.plist";
static const NSInteger kMaxPlanHistory = 50;

#pragma mark - PlanStep

@implementation PlanStep

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)stepWithId:(NSString *)stepId
                      type:(PlanStepType)type
               description:(NSString *)description {
    PlanStep *step = [[PlanStep alloc] init];
    step.stepId = stepId;
    step.type = type;
    step.stepDescription = description;
    step.status = PlanStepStatusPending;
    step.priority = 0;
    step.confidence = 0.0;
    step.isOptional = NO;
    step.startTime = [NSDate date];
    return step;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.stepId forKey:@"stepId"];
    [coder encodeInteger:self.type forKey:@"type"];
    [coder encodeObject:self.stepDescription forKey:@"stepDescription"];
    [coder encodeInteger:self.status forKey:@"status"];
    [coder encodeInteger:self.priority forKey:@"priority"];
    [coder encodeFloat:self.confidence forKey:@"confidence"];
    [coder encodeObject:self.input forKey:@"input"];
    [coder encodeObject:self.output forKey:@"output"];
    [coder encodeObject:self.startTime forKey:@"startTime"];
    [coder encodeObject:self.endTime forKey:@"endTime"];
    [coder encodeBool:self.isOptional forKey:@"isOptional"];
    [coder encodeObject:self.dependencies forKey:@"dependencies"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _stepId = [coder decodeObjectOfClass:[NSString class] forKey:@"stepId"];
        _type = [coder decodeIntegerForKey:@"type"];
        _stepDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"stepDescription"];
        _status = [coder decodeIntegerForKey:@"status"];
        _priority = [coder decodeIntegerForKey:@"priority"];
        _confidence = [coder decodeFloatForKey:@"confidence"];
        _input = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"input"];
        _output = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"output"];
        _startTime = [coder decodeObjectOfClass:[NSDate class] forKey:@"startTime"];
        _endTime = [coder decodeObjectOfClass:[NSDate class] forKey:@"endTime"];
        _isOptional = [coder decodeBoolForKey:@"isOptional"];
        _dependencies = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSString class], nil] forKey:@"dependencies"];
    }
    return self;
}

- (NSTimeInterval)duration {
    if (self.endTime && self.startTime) {
        return [self.endTime timeIntervalSinceDate:self.startTime];
    }
    return 0;
}

- (NSString *)description {
    NSArray *statusNames = @[@"Pending", @"InProgress", @"Done", @"Failed", @"Skipped"];
    NSString *statusName = (self.status < statusNames.count) ? statusNames[self.status] : @"Unknown";
    return [NSString stringWithFormat:@"<PlanStep: %@ [%@] %@>", self.stepId, statusName, self.stepDescription];
}

@end

#pragma mark - ExecutionPlan

@implementation ExecutionPlan

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)planWithId:(NSString *)planId
                  songName:(NSString *)songName
                    artist:(NSString *)artist {
    ExecutionPlan *plan = [[ExecutionPlan alloc] init];
    plan.planId = planId;
    plan.songName = songName;
    plan.artist = artist;
    plan.steps = [NSMutableArray array];
    plan.overallProgress = 0.0;
    plan.createdAt = [NSDate date];
    plan.isRevised = NO;
    return plan;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.planId forKey:@"planId"];
    [coder encodeObject:self.songName forKey:@"songName"];
    [coder encodeObject:self.artist forKey:@"artist"];
    [coder encodeObject:self.steps forKey:@"steps"];
    [coder encodeFloat:self.overallProgress forKey:@"overallProgress"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeObject:self.completedAt forKey:@"completedAt"];
    [coder encodeBool:self.isRevised forKey:@"isRevised"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _planId = [coder decodeObjectOfClass:[NSString class] forKey:@"planId"];
        _songName = [coder decodeObjectOfClass:[NSString class] forKey:@"songName"];
        _artist = [coder decodeObjectOfClass:[NSString class] forKey:@"artist"];
        NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [PlanStep class], nil];
        _steps = [coder decodeObjectOfClasses:classes forKey:@"steps"];
        _overallProgress = [coder decodeFloatForKey:@"overallProgress"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _completedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"completedAt"];
        _isRevised = [coder decodeBoolForKey:@"isRevised"];
    }
    return self;
}

- (PlanStep *)stepWithId:(NSString *)stepId {
    for (PlanStep *step in self.steps) {
        if ([step.stepId isEqualToString:stepId]) {
            return step;
        }
    }
    return nil;
}

- (PlanStep *)nextPendingStep {
    for (PlanStep *step in self.steps) {
        if (step.status == PlanStepStatusPending) {
            // 检查依赖是否满足
            BOOL dependenciesMet = YES;
            for (NSString *depId in step.dependencies) {
                PlanStep *depStep = [self stepWithId:depId];
                if (depStep && depStep.status != PlanStepStatusDone && depStep.status != PlanStepStatusSkipped) {
                    dependenciesMet = NO;
                    break;
                }
            }
            if (dependenciesMet) {
                return step;
            }
        }
    }
    return nil;
}

- (NSArray<PlanStep *> *)completedSteps {
    NSMutableArray *completed = [NSMutableArray array];
    for (PlanStep *step in self.steps) {
        if (step.status == PlanStepStatusDone) {
            [completed addObject:step];
        }
    }
    return completed;
}

- (NSArray<PlanStep *> *)failedSteps {
    NSMutableArray *failed = [NSMutableArray array];
    for (PlanStep *step in self.steps) {
        if (step.status == PlanStepStatusFailed) {
            [failed addObject:step];
        }
    }
    return failed;
}

- (BOOL)isComplete {
    for (PlanStep *step in self.steps) {
        if (!step.isOptional &&
            step.status != PlanStepStatusDone &&
            step.status != PlanStepStatusSkipped) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)hasFailures {
    for (PlanStep *step in self.steps) {
        if (step.status == PlanStepStatusFailed && !step.isOptional) {
            return YES;
        }
    }
    return NO;
}

- (void)updateProgress {
    if (self.steps.count == 0) {
        self.overallProgress = 0.0;
        return;
    }
    
    NSInteger completed = 0;
    for (PlanStep *step in self.steps) {
        if (step.status == PlanStepStatusDone || step.status == PlanStepStatusSkipped) {
            completed++;
        }
    }
    
    self.overallProgress = (float)completed / (float)self.steps.count;
    
    if (self.isComplete && !self.completedAt) {
        self.completedAt = [NSDate date];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<ExecutionPlan: %@ | %@ - %@ | progress=%.1f%% | steps=%lu>",
            self.planId, self.songName, self.artist ?: @"Unknown",
            self.overallProgress * 100, (unsigned long)self.steps.count];
}

@end

#pragma mark - PlanContext

@implementation PlanContext

+ (instancetype)contextWithSongName:(NSString *)songName artist:(NSString *)artist {
    PlanContext *context = [[PlanContext alloc] init];
    context.songName = songName;
    context.artist = artist;
    context.urgency = 0.5;
    return context;
}

@end

#pragma mark - PlanFeedback

@implementation PlanFeedback

+ (instancetype)feedbackWithTransitionProblem:(BOOL)transition {
    PlanFeedback *feedback = [[PlanFeedback alloc] init];
    feedback.transitionProblem = transition;
    return feedback;
}

@end

#pragma mark - AgentPlanner

@interface AgentPlanner ()

@property (nonatomic, strong) ExecutionPlan *currentPlan;
@property (nonatomic, strong) NSMutableArray<ExecutionPlan *> *mutablePlanHistory;
@property (nonatomic, strong) NSString *cacheDirectory;

@end

@implementation AgentPlanner

#pragma mark - Singleton

+ (instancetype)sharedPlanner {
    static AgentPlanner *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AgentPlanner alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutablePlanHistory = [NSMutableArray array];
        [self setupCacheDirectory];
        [self loadPlanHistory];
    }
    return self;
}

- (void)setupCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    self.cacheDirectory = [cachesDir stringByAppendingPathComponent:@"AgentPlanner"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectory]) {
        [fm createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSArray<ExecutionPlan *> *)planHistory {
    return [self.mutablePlanHistory copy];
}

#pragma mark - Plan Generation

- (ExecutionPlan *)generatePlanWithContext:(PlanContext *)context {
    NSString *planId = [[NSUUID UUID] UUIDString];
    ExecutionPlan *plan = [ExecutionPlan planWithId:planId songName:context.songName artist:context.artist];
    
    // Step 1: 缓存查找
    if (context.hasCachedDecision) {
        PlanStep *cacheStep = [PlanStep stepWithId:@"cache_lookup"
                                              type:PlanStepTypeCacheLookup
                                       description:@"查找缓存决策"];
        cacheStep.priority = 0;
        [plan.steps addObject:cacheStep];
    }
    
    // Step 2: 风格分类
    PlanStep *classifyStep = [PlanStep stepWithId:@"classify_style"
                                             type:PlanStepTypeClassifyStyle
                                      description:@"分类音乐风格"];
    classifyStep.priority = 1;
    [plan.steps addObject:classifyStep];
    
    // Step 3: 用户偏好检查
    if (context.hasUserPreference) {
        PlanStep *prefStep = [PlanStep stepWithId:@"apply_preferences"
                                             type:PlanStepTypeApplyUserPreferences
                                      description:@"应用用户偏好"];
        prefStep.priority = 2;
        prefStep.dependencies = @[@"classify_style"];
        [plan.steps addObject:prefStep];
    }
    
    // Step 4: 情感映射（如果紧急程度不高）
    if (context.urgency < 0.7) {
        PlanStep *emotionStep = [PlanStep stepWithId:@"emotion_map"
                                                type:PlanStepTypeGenerateEmotionMap
                                         description:@"生成情感映射"];
        emotionStep.priority = 3;
        emotionStep.isOptional = YES;
        emotionStep.dependencies = @[@"classify_style"];
        [plan.steps addObject:emotionStep];
    }
    
    // Step 5: 分配特效
    PlanStep *assignStep = [PlanStep stepWithId:@"assign_effects"
                                           type:PlanStepTypeAssignEffects
                                    description:@"为各段落分配特效"];
    assignStep.priority = 4;
    assignStep.dependencies = @[@"classify_style"];
    [plan.steps addObject:assignStep];
    
    // Step 6: LLM 查询（如果需要）
    if (context.requiresLLM) {
        PlanStep *llmStep = [PlanStep stepWithId:@"llm_query"
                                            type:PlanStepTypeLLMQuery
                                     description:@"调用 LLM 进行分析"];
        llmStep.priority = 5;
        llmStep.dependencies = @[@"classify_style"];
        [plan.steps addObject:llmStep];
    }
    
    // Step 7: 验证过渡
    PlanStep *validateStep = [PlanStep stepWithId:@"validate_transitions"
                                             type:PlanStepTypeValidateTransitions
                                      description:@"验证特效过渡平滑"];
    validateStep.priority = 6;
    validateStep.dependencies = @[@"assign_effects"];
    [plan.steps addObject:validateStep];
    
    // Step 8: 参数优化
    PlanStep *optimizeStep = [PlanStep stepWithId:@"optimize_params"
                                             type:PlanStepTypeOptimizeParameters
                                      description:@"优化特效参数"];
    optimizeStep.priority = 7;
    optimizeStep.isOptional = YES;
    optimizeStep.dependencies = @[@"validate_transitions"];
    [plan.steps addObject:optimizeStep];
    
    self.currentPlan = plan;
    
    NSLog(@"📋 Planner: 生成计划 %@ (%lu 步骤) for %@", planId, (unsigned long)plan.steps.count, context.songName);
    
    return plan;
}

- (ExecutionPlan *)generateQuickPlanForSong:(NSString *)songName artist:(NSString *)artist {
    PlanContext *context = [PlanContext contextWithSongName:songName artist:artist];
    context.urgency = 0.9;  // 高紧急度
    context.requiresLLM = NO;
    
    NSString *planId = [[NSUUID UUID] UUIDString];
    ExecutionPlan *plan = [ExecutionPlan planWithId:planId songName:songName artist:artist];
    
    // 只有三步：缓存查找、风格分类、分配特效
    PlanStep *cacheStep = [PlanStep stepWithId:@"cache_lookup"
                                          type:PlanStepTypeCacheLookup
                                   description:@"查找缓存决策"];
    [plan.steps addObject:cacheStep];
    
    PlanStep *classifyStep = [PlanStep stepWithId:@"classify_style"
                                             type:PlanStepTypeClassifyStyle
                                      description:@"快速分类音乐风格"];
    classifyStep.dependencies = @[@"cache_lookup"];
    [plan.steps addObject:classifyStep];
    
    PlanStep *assignStep = [PlanStep stepWithId:@"assign_effects"
                                           type:PlanStepTypeAssignEffects
                                    description:@"分配特效"];
    assignStep.dependencies = @[@"classify_style"];
    [plan.steps addObject:assignStep];
    
    self.currentPlan = plan;
    
    NSLog(@"📋 Planner: 生成快速计划 %@ (3 步骤)", planId);
    
    return plan;
}

- (ExecutionPlan *)generateFullAnalysisPlanForSong:(NSString *)songName artist:(NSString *)artist {
    PlanContext *context = [PlanContext contextWithSongName:songName artist:artist];
    context.urgency = 0.3;  // 低紧急度，全面分析
    context.requiresLLM = YES;
    context.hasCachedDecision = YES;
    context.hasUserPreference = YES;
    
    ExecutionPlan *plan = [self generatePlanWithContext:context];
    
    // 添加完整曲目分析步骤
    PlanStep *fullAnalysis = [PlanStep stepWithId:@"analyze_full_track"
                                             type:PlanStepTypeAnalyzeTrack
                                      description:@"分析完整曲目结构"];
    fullAnalysis.priority = 0;
    [plan.steps insertObject:fullAnalysis atIndex:0];
    
    NSLog(@"📋 Planner: 生成完整分析计划 (%lu 步骤)", (unsigned long)plan.steps.count);
    
    return plan;
}

#pragma mark - Plan Execution

- (void)markStepInProgress:(NSString *)stepId inPlan:(ExecutionPlan *)plan {
    PlanStep *step = [plan stepWithId:stepId];
    if (step) {
        step.status = PlanStepStatusInProgress;
        step.startTime = [NSDate date];
        NSLog(@"📋 Planner: 步骤开始 [%@] %@", stepId, step.stepDescription);
    }
}

- (void)markStepDone:(NSString *)stepId
              inPlan:(ExecutionPlan *)plan
          withOutput:(NSDictionary *)output {
    PlanStep *step = [plan stepWithId:stepId];
    if (step) {
        step.status = PlanStepStatusDone;
        step.endTime = [NSDate date];
        step.output = output;
        step.confidence = 1.0;
        [plan updateProgress];
        
        NSLog(@"📋 Planner: 步骤完成 [%@] 耗时 %.2fs", stepId, step.duration);
    }
}

- (void)markStepFailed:(NSString *)stepId
                inPlan:(ExecutionPlan *)plan
             withError:(NSError *)error {
    PlanStep *step = [plan stepWithId:stepId];
    if (step) {
        step.status = PlanStepStatusFailed;
        step.endTime = [NSDate date];
        step.error = error;
        step.confidence = 0.0;
        [plan updateProgress];
        
        NSLog(@"📋 Planner: 步骤失败 [%@] 错误: %@", stepId, error.localizedDescription);
    }
}

- (void)skipStep:(NSString *)stepId inPlan:(ExecutionPlan *)plan reason:(NSString *)reason {
    PlanStep *step = [plan stepWithId:stepId];
    if (step) {
        step.status = PlanStepStatusSkipped;
        step.endTime = [NSDate date];
        step.output = @{@"skipReason": reason};
        [plan updateProgress];
        
        NSLog(@"📋 Planner: 步骤跳过 [%@] 原因: %@", stepId, reason);
    }
}

#pragma mark - Plan Revision

- (ExecutionPlan *)revisePlan:(ExecutionPlan *)plan withFeedback:(PlanFeedback *)feedback {
    plan.isRevised = YES;
    
    // 如果有过渡问题，添加优化步骤
    if (feedback.transitionProblem) {
        PlanStep *optimizeTransition = [PlanStep stepWithId:@"optimize_transition"
                                                       type:PlanStepTypeValidateTransitions
                                                description:@"重新优化特效过渡"];
        [self addStep:optimizeTransition toPlan:plan afterStep:@"validate_transitions"];
        
        NSLog(@"📋 Planner: 修订计划 - 添加过渡优化步骤");
    }
    
    // 如果风格匹配有问题，添加 LLM 查询
    if (feedback.styleMatchProblem) {
        PlanStep *step = [plan stepWithId:@"llm_query"];
        if (!step) {
            PlanStep *llmStep = [PlanStep stepWithId:@"llm_query_retry"
                                                type:PlanStepTypeLLMQuery
                                         description:@"调用 LLM 重新分析风格"];
            [self addStep:llmStep toPlan:plan afterStep:@"classify_style"];
        }
        
        NSLog(@"📋 Planner: 修订计划 - 添加 LLM 查询步骤");
    }
    
    // 如果有失败步骤，重置状态
    if (feedback.failedStepId) {
        PlanStep *failedStep = [plan stepWithId:feedback.failedStepId];
        if (failedStep) {
            failedStep.status = PlanStepStatusPending;
            failedStep.error = nil;
            
            // 添加降级步骤作为备份
            PlanStep *fallback = [PlanStep stepWithId:@"fallback_decision"
                                                 type:PlanStepTypeFallbackDecision
                                          description:@"使用降级决策"];
            fallback.dependencies = @[feedback.failedStepId];
            fallback.isOptional = YES;
            [plan.steps addObject:fallback];
        }
    }
    
    return plan;
}

- (void)addStep:(PlanStep *)step toPlan:(ExecutionPlan *)plan afterStep:(NSString *)afterStepId {
    if (afterStepId) {
        NSInteger index = 0;
        for (NSInteger i = 0; i < plan.steps.count; i++) {
            if ([plan.steps[i].stepId isEqualToString:afterStepId]) {
                index = i + 1;
                break;
            }
        }
        [plan.steps insertObject:step atIndex:index];
    } else {
        [plan.steps addObject:step];
    }
    
    [plan updateProgress];
}

- (void)removeStep:(NSString *)stepId fromPlan:(ExecutionPlan *)plan {
    PlanStep *step = [plan stepWithId:stepId];
    if (step) {
        [plan.steps removeObject:step];
        [plan updateProgress];
    }
}

#pragma mark - Plan Evaluation

- (NSDictionary *)evaluatePlan:(ExecutionPlan *)plan {
    NSMutableDictionary *evaluation = [NSMutableDictionary dictionary];
    
    evaluation[@"planId"] = plan.planId;
    evaluation[@"isComplete"] = @(plan.isComplete);
    evaluation[@"isRevised"] = @(plan.isRevised);
    evaluation[@"progress"] = @(plan.overallProgress);
    evaluation[@"totalSteps"] = @(plan.steps.count);
    evaluation[@"completedSteps"] = @(plan.completedSteps.count);
    evaluation[@"failedSteps"] = @(plan.failedSteps.count);
    
    // 计算总耗时
    NSTimeInterval totalDuration = 0;
    for (PlanStep *step in plan.steps) {
        totalDuration += step.duration;
    }
    evaluation[@"totalDuration"] = @(totalDuration);
    
    // 计算成功率
    float successRate = (plan.steps.count > 0) ?
        (float)plan.completedSteps.count / (float)plan.steps.count : 0;
    evaluation[@"successRate"] = @(successRate);
    
    // 保存到历史
    [self.mutablePlanHistory addObject:plan];
    while (self.mutablePlanHistory.count > kMaxPlanHistory) {
        [self.mutablePlanHistory removeObjectAtIndex:0];
    }
    [self savePlanHistory];
    
    return evaluation;
}

- (NSDictionary *)getPlanStatistics {
    if (self.mutablePlanHistory.count == 0) {
        return @{
            @"totalPlans": @0,
            @"averageSteps": @0,
            @"averageDuration": @0,
            @"successRate": @0
        };
    }
    
    NSInteger totalSteps = 0;
    NSTimeInterval totalDuration = 0;
    NSInteger successCount = 0;
    
    for (ExecutionPlan *plan in self.mutablePlanHistory) {
        totalSteps += plan.steps.count;
        
        for (PlanStep *step in plan.steps) {
            totalDuration += step.duration;
        }
        
        if (plan.isComplete && !plan.hasFailures) {
            successCount++;
        }
    }
    
    return @{
        @"totalPlans": @(self.mutablePlanHistory.count),
        @"averageSteps": @((float)totalSteps / self.mutablePlanHistory.count),
        @"averageDuration": @(totalDuration / self.mutablePlanHistory.count),
        @"successRate": @((float)successCount / self.mutablePlanHistory.count)
    };
}

#pragma mark - Persistence

- (void)savePlanHistory {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kPlanHistoryFile];
    
    @try {
        NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [ExecutionPlan class], [PlanStep class], nil];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.mutablePlanHistory requiringSecureCoding:YES error:nil];
        [data writeToFile:path atomically:YES];
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Planner: 保存计划历史失败: %@", exception.reason);
    }
}

- (void)loadPlanHistory {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kPlanHistoryFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [ExecutionPlan class], [PlanStep class], [NSString class], [NSDate class], [NSDictionary class], [NSArray class], nil];
            NSMutableArray *history = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (history) {
                self.mutablePlanHistory = history;
                NSLog(@"📂 Planner: 加载计划历史 %lu 条", (unsigned long)history.count);
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ Planner: 加载计划历史失败: %@", exception.reason);
        }
    }
}

- (void)clearHistory {
    [self.mutablePlanHistory removeAllObjects];
    [self savePlanHistory];
    NSLog(@"📋 Planner: 历史已清除");
}

@end
