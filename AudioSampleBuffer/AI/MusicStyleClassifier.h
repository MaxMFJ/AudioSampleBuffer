//
//  MusicStyleClassifier.h
//  AudioSampleBuffer
//
//  音乐风格分类器 - 基于音频特征判断音乐风格
//

#import <Foundation/Foundation.h>
#import "AudioFeatureExtractor.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 音乐风格枚举

typedef NS_ENUM(NSUInteger, MusicStyle) {
    MusicStyleUnknown = 0,
    MusicStyleElectronic,    // 电子/EDM - 强节拍、合成器
    MusicStyleRock,          // 摇滚 - 强鼓点、吉他
    MusicStyleClassical,     // 古典 - 动态范围大、无明显节拍
    MusicStylePop,           // 流行 - 中等能量、人声突出
    MusicStyleJazz,          // 爵士 - 复杂和声、摇摆节奏
    MusicStyleHipHop,        // 嘻哈 - 强低音、规律节拍
    MusicStyleAmbient,       // 氛围 - 低能量、缓慢变化
    MusicStyleMetal,         // 金属 - 极高能量、失真
    MusicStyleRnB,           // R&B - 节奏蓝调、中等能量
    MusicStyleCountry,       // 乡村 - 声学乐器
    MusicStyleDance,         // 舞曲 - 强节拍、高能量
    MusicStyleAcoustic,      // 原声 - 简单、清晰
    MusicStyleCount
};

#pragma mark - 风格分类结果

@interface MusicStyleResult : NSObject

@property (nonatomic, assign) MusicStyle primaryStyle;           // 主要风格
@property (nonatomic, assign) MusicStyle secondaryStyle;         // 次要风格
@property (nonatomic, assign) float primaryConfidence;           // 主要风格置信度 [0-1]
@property (nonatomic, assign) float secondaryConfidence;         // 次要风格置信度 [0-1]
@property (nonatomic, strong) NSDictionary<NSNumber *, NSNumber *> *styleProbabilities;  // 各风格概率

+ (instancetype)resultWithStyle:(MusicStyle)style confidence:(float)confidence;

@end

#pragma mark - 音乐风格分类器

@interface MusicStyleClassifier : NSObject

/// 单例
+ (instancetype)sharedClassifier;

/// 当前分类结果
@property (nonatomic, strong, readonly) MusicStyleResult *currentResult;

/// 根据音频特征分类风格
/// @param features 音频特征
/// @return 分类结果
- (MusicStyleResult *)classifyWithFeatures:(AudioFeatures *)features;

/// 根据累积特征分类（更准确）
/// @param features 当前特征
/// @param accumulate 是否累积历史数据
- (MusicStyleResult *)classifyWithFeatures:(AudioFeatures *)features accumulate:(BOOL)accumulate;

/// 根据歌曲名和艺术家预分类（基于关键词）
/// @param songName 歌曲名
/// @param artist 艺术家
/// @return 分类结果（如果无法判断则返回nil）
- (nullable MusicStyleResult *)preclassifyWithSongName:(NSString *)songName artist:(nullable NSString *)artist;

/// 重置累积数据
- (void)reset;

/// 获取风格名称
+ (NSString *)nameForStyle:(MusicStyle)style;

/// 获取风格的推荐能量范围
+ (void)getEnergyRangeForStyle:(MusicStyle)style minEnergy:(float *)minEnergy maxEnergy:(float *)maxEnergy;

@end

NS_ASSUME_NONNULL_END
