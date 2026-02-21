//
//  AudioFeatureExtractor.h
//  AudioSampleBuffer
//
//  音频特征提取器 - 从FFT频谱数据提取高级音乐特征
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 音乐段落枚举

typedef NS_ENUM(NSUInteger, MusicSegment) {
    MusicSegmentUnknown = 0,
    MusicSegmentIntro,      // 前奏
    MusicSegmentVerse,      // 主歌
    MusicSegmentChorus,     // 副歌/高潮
    MusicSegmentBridge,     // 过渡
    MusicSegmentOutro       // 尾奏
};

#pragma mark - 音频特征模型

@interface AudioFeatures : NSObject <NSCopying>

@property (nonatomic, assign) float bpm;                    // 节拍速度
@property (nonatomic, assign) float energy;                 // 整体能量 [0-1]
@property (nonatomic, assign) float bassEnergy;             // 低频能量 (20-250Hz) [0-1]
@property (nonatomic, assign) float midEnergy;              // 中频能量 (250-4kHz) [0-1]
@property (nonatomic, assign) float highEnergy;             // 高频能量 (4k-20kHz) [0-1]
@property (nonatomic, assign) float spectralCentroid;       // 频谱重心（亮度指标）[0-1]
@property (nonatomic, assign) float spectralFlux;           // 频谱变化率（节奏强度）[0-1]
@property (nonatomic, assign) MusicSegment currentSegment;  // 当前段落
@property (nonatomic, assign) BOOL beatDetected;            // 当前帧是否检测到节拍
@property (nonatomic, assign) BOOL segmentChanged;          // 段落是否刚发生变化
@property (nonatomic, assign) NSTimeInterval timestamp;     // 时间戳

+ (instancetype)emptyFeatures;

@end

#pragma mark - 特征观察者协议

@protocol AudioFeatureObserver <NSObject>
@optional
- (void)audioFeatureExtractor:(id)extractor didUpdateFeatures:(AudioFeatures *)features;
- (void)audioFeatureExtractor:(id)extractor didDetectBeatAtTime:(NSTimeInterval)time;
- (void)audioFeatureExtractor:(id)extractor didChangeSegmentFrom:(MusicSegment)oldSegment to:(MusicSegment)newSegment;
@end

#pragma mark - 音频特征提取器

@interface AudioFeatureExtractor : NSObject

/// 单例
+ (instancetype)sharedExtractor;

/// 当前特征
@property (nonatomic, strong, readonly) AudioFeatures *currentFeatures;

/// 平均BPM（基于历史数据计算）
@property (nonatomic, assign, readonly) float averageBPM;

/// 处理频谱数据
/// @param spectrum FFT频谱数组（通常为512或1024个频点）
- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum;

/// 处理频谱数据（带采样率）
/// @param spectrum FFT频谱数组
/// @param sampleRate 采样率（默认44100）
- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum sampleRate:(float)sampleRate;

/// 重置状态
- (void)reset;

/// 添加观察者
- (void)addObserver:(id<AudioFeatureObserver>)observer;

/// 移除观察者
- (void)removeObserver:(id<AudioFeatureObserver>)observer;

@end

NS_ASSUME_NONNULL_END
