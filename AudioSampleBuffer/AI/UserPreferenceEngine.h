//
//  UserPreferenceEngine.h
//  AudioSampleBuffer
//
//  用户偏好学习引擎 - 多维度偏好学习和情境感知
//

#import <Foundation/Foundation.h>
#import "MusicStyleClassifier.h"
#import "UserContext.h"
#import "VisualEffectType.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 偏好记录

@interface PreferenceRecord : NSObject <NSCoding, NSSecureCoding>

@property (nonatomic, assign) MusicStyle style;
@property (nonatomic, assign) VisualEffectType effect;
@property (nonatomic, strong) UserContext *context;
@property (nonatomic, assign) float engagementScore;  // 参与度分数 [-1, 1]
@property (nonatomic, strong) NSDate *timestamp;

+ (instancetype)recordWithStyle:(MusicStyle)style
                         effect:(VisualEffectType)effect
                        context:(UserContext *)context
                          score:(float)score;

@end

#pragma mark - 偏好查询结果

@interface PreferenceQueryResult : NSObject

@property (nonatomic, assign) VisualEffectType preferredEffect;
@property (nonatomic, assign) float confidence;       // 置信度 [0-1]
@property (nonatomic, assign) NSInteger sampleCount;  // 基于多少条记录

@end

#pragma mark - 用户偏好引擎

@interface UserPreferenceEngine : NSObject

/// 单例
+ (instancetype)sharedEngine;

/// 当前上下文
@property (nonatomic, strong, readonly) UserContext *currentContext;

/// 会话开始时间
@property (nonatomic, strong, readonly) NSDate *sessionStartTime;

#pragma mark - 记录用户行为

/// 记录展示的特效
- (void)recordEffectShown:(VisualEffectType)effect
                 forStyle:(MusicStyle)style
                  context:(UserContext *)context;

/// 记录用户跳过歌曲（负反馈）
- (void)recordUserSkippedSong;

/// 记录用户手动切换特效（原特效负反馈，新特效正反馈）
- (void)recordUserManuallyChangedEffect:(VisualEffectType)newEffect
                             fromEffect:(VisualEffectType)oldEffect;

/// 记录用户完整听完歌曲（正反馈）
- (void)recordUserListenedFull;

/// 记录用户长时间停留在某特效（正反馈）
- (void)recordUserStayedOnEffect:(VisualEffectType)effect
                        duration:(NSTimeInterval)duration;

#pragma mark - 查询偏好

/// 查询某风格下的偏好特效
- (PreferenceQueryResult *)preferredEffectForStyle:(MusicStyle)style
                                           context:(UserContext *)context;

/// 获取特效在某风格下的偏好分数
- (float)preferenceScoreForEffect:(VisualEffectType)effect
                          inStyle:(MusicStyle)style;

/// 获取特效在特定场景下的偏好分数
- (float)preferenceScoreForEffect:(VisualEffectType)effect
                          inScene:(UsageScene)scene;

/// 获取用户的总体偏好特效列表（按分数排序）
- (NSArray<NSNumber *> *)topPreferredEffects:(NSInteger)count;

#pragma mark - 数据管理

/// 更新当前上下文
- (void)updateCurrentContext;

/// 开始新会话
- (void)startNewSession;

/// 清除所有偏好数据
- (void)clearAllPreferences;

/// 导出偏好数据（用于调试）
- (NSDictionary *)exportPreferences;

#pragma mark - 策略调整

/// 用户偏好权重（决策时应用）
@property (nonatomic, assign) float preferenceWeight;

/// 增加用户偏好权重
- (void)boostUserPreferenceWeight:(float)amount;

/// 保存偏好权重
- (void)savePreferenceWeight;

@end

NS_ASSUME_NONNULL_END
