//
//  LyricsEffectType.h
//  AudioSampleBuffer
//
//  歌词特效类型定义
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 歌词特效类型
typedef NS_ENUM(NSInteger, LyricsEffectType) {
    LyricsEffectTypeNone = 0,           // 无特效（默认）
    LyricsEffectTypeFadeInOut,          // 淡入淡出
    LyricsEffectTypeSplitMerge,         // 撕裂合并
    LyricsEffectTypeCharacterAssemble,  // 字符拼接
    LyricsEffectTypeWave,               // 波浪效果
    LyricsEffectTypeBounce,             // 弹跳效果
    LyricsEffectTypeGlitch,             // 故障艺术
    LyricsEffectTypeNeon,               // 霓虹发光
    LyricsEffectTypeTypewriter,         // 打字机效果
    LyricsEffectTypeParticle,           // 粒子效果
    LyricsEffectTypeCount               // 特效总数
};

/// 特效信息结构
@interface LyricsEffectInfo : NSObject

@property (nonatomic, assign) LyricsEffectType type;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *iconName; // SF Symbols system image name
@property (nonatomic, copy) NSString *effectDescription;

+ (instancetype)infoWithType:(LyricsEffectType)type
                        name:(NSString *)name
                    iconName:(NSString *)iconName
                 description:(NSString *)effectDescription;

@end

/// 特效管理器
@interface LyricsEffectManager : NSObject

/// 获取所有特效信息
+ (NSArray<LyricsEffectInfo *> *)allEffects;

/// 获取特效名称
+ (NSString *)nameForEffect:(LyricsEffectType)type;

/// 获取特效图标（SF Symbols system image name）
+ (NSString *)iconNameForEffect:(LyricsEffectType)type;

@end

NS_ASSUME_NONNULL_END

