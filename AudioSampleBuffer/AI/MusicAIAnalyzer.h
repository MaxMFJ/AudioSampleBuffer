//
//  MusicAIAnalyzer.h
//  AudioSampleBuffer
//
//  使用可配置的 LLM API 分析音乐并生成视觉效果配置
//

#import <Foundation/Foundation.h>
#import "AIColorConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

/// AI 配置更新时发送的通知
extern NSString *const kAIConfigurationDidChangeNotification;
/// 通知 userInfo 中配置对象的 key
extern NSString *const kAIConfigurationKey;

typedef void(^AIAnalysisCompletion)(AIColorConfiguration * _Nullable config, NSError * _Nullable error);

/// 音乐 AI 分析器
@interface MusicAIAnalyzer : NSObject

/// 单例
+ (instancetype)sharedAnalyzer;

/// 当前配置
@property (nonatomic, strong, readonly, nullable) AIColorConfiguration *currentConfiguration;

/// 是否正在分析
@property (nonatomic, assign, readonly) BOOL isAnalyzing;

/// 分析歌曲（自动处理缓存）
/// @param songName 歌曲名
/// @param artist 艺术家
/// @param completion 完成回调
- (void)analyzeSong:(NSString *)songName
             artist:(NSString *)artist
         completion:(AIAnalysisCompletion)completion;

/// 强制重新分析（跳过缓存）
- (void)forceAnalyzeSong:(NSString *)songName
                  artist:(NSString *)artist
              completion:(AIAnalysisCompletion)completion;

/// 获取缓存的配置
- (nullable AIColorConfiguration *)getCachedConfigurationForSong:(NSString *)songName
                                                          artist:(NSString *)artist;

/// 清除所有缓存
- (void)clearCache;

/// 清除特定歌曲缓存
- (void)clearCacheForSong:(NSString *)songName artist:(NSString *)artist;

/// 应用配置到当前渲染器（通过通知机制）
- (void)applyConfiguration:(AIColorConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
