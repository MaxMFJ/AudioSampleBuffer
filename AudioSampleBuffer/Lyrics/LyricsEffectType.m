//
//  LyricsEffectType.m
//  AudioSampleBuffer
//
//  歌词特效类型实现
//

#import "LyricsEffectType.h"

@implementation LyricsEffectInfo

+ (instancetype)infoWithType:(LyricsEffectType)type
                        name:(NSString *)name
                    iconName:(NSString *)iconName
                 description:(NSString *)effectDescription {
    LyricsEffectInfo *info = [[LyricsEffectInfo alloc] init];
    info.type = type;
    info.name = name;
    info.iconName = iconName;
    info.effectDescription = effectDescription;
    return info;
}

@end

@implementation LyricsEffectManager

+ (NSArray<LyricsEffectInfo *> *)allEffects {
    static NSArray<LyricsEffectInfo *> *effects = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        effects = @[
            [LyricsEffectInfo infoWithType:LyricsEffectTypeNone
                                      name:@"默认"
                                  iconName:@"doc.text"
                               description:@"标准歌词显示"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeFadeInOut
                                      name:@"淡入淡出"
                                  iconName:@"hourglass"
                               description:@"柔和的淡入淡出效果"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeSplitMerge
                                      name:@"撕裂合并"
                                  iconName:@"scissors"
                               description:@"文字从两侧撕裂后合并"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeCharacterAssemble
                                      name:@"字符拼接"
                                  iconName:@"text.cursor"
                               description:@"逐个字符拼接组合"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeWave
                                      name:@"波浪"
                                  iconName:@"waveform"
                               description:@"文字呈波浪起伏"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeBounce
                                      name:@"弹跳"
                                  iconName:@"bolt.fill"
                               description:@"文字弹跳出现"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeGlitch
                                      name:@"故障艺术"
                                  iconName:@"tv"
                               description:@"赛博朋克故障效果"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeNeon
                                      name:@"霓虹发光"
                                  iconName:@"lightbulb.fill"
                               description:@"霓虹灯管发光效果"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeTypewriter
                                      name:@"打字机"
                                  iconName:@"keyboard"
                               description:@"逐字打印效果"],
            
            [LyricsEffectInfo infoWithType:LyricsEffectTypeParticle
                                      name:@"粒子"
                                  iconName:@"sparkles"
                               description:@"文字粒子化效果"]
        ];
    });
    return effects;
}

+ (NSString *)nameForEffect:(LyricsEffectType)type {
    NSArray<LyricsEffectInfo *> *effects = [self allEffects];
    if (type >= 0 && type < effects.count) {
        return effects[type].name;
    }
    return @"未知";
}

+ (NSString *)iconNameForEffect:(LyricsEffectType)type {
    NSArray<LyricsEffectInfo *> *effects = [self allEffects];
    if (type >= 0 && type < effects.count) {
        return effects[type].iconName;
    }
    return @"❓";
}

@end

