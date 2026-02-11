//
//  AudioFileFormats.h
//  AudioSampleBuffer
//
//  Created by AudioSampleBuffer on 2025.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * NCM 文件解密器
 * 支持网易云音乐加密格式 (.ncm) 解密为 MP3/FLAC
 */
@interface NCMDecryptor : NSObject

/**
 * 解密 NCM 文件
 * @param inputPath NCM 文件路径
 * @param outputPath 输出文件路径（如果为 nil，自动生成）
 * @param error 错误信息
 * @return 输出文件路径，失败返回 nil
 */
+ (nullable NSString *)decryptNCMFile:(NSString *)inputPath
                           outputPath:(nullable NSString *)outputPath
                                error:(NSError **)error;

/**
 * 批量解密目录中的 NCM 文件
 * @param directoryPath 目录路径
 * @param recursive 是否递归子目录ˉ
 * @param progressBlock 进度回调 (当前索引, 总数, 文件名, 成功/失败)
 * @return 成功解密的文件数量
 */
+ (NSInteger)decryptNCMFilesInDirectory:(NSString *)directoryPath
                              recursive:(BOOL)recursive
                          progressBlock:(nullable void(^)(NSInteger current, NSInteger total, NSString *filename, BOOL success))progressBlock;

/**
 * 检测文件是否为 NCM 格式
 */
+ (BOOL)isNCMFile:(NSString *)filePath;

/**
 * 从 NCM 文件提取元数据（歌曲信息）
 */
+ (nullable NSDictionary *)extractMetadataFromNCM:(NSString *)filePath error:(NSError **)error;

/**
 * 从网易云音乐下载歌词
 * @param musicId 网易云音乐ID
 * @param completion 完成回调 (歌词内容, 错误)
 */
+ (void)downloadLyricsFromNetease:(NSString *)musicId
                       completion:(void(^)(NSString * _Nullable lyrics, NSError * _Nullable error))completion;

/**
 * 从 NCM 文件下载并保存歌词
 * @param ncmPath NCM 文件路径
 * @param outputPath 歌词输出路径（如果为 nil，自动生成）
 * @return 歌词文件路径，失败返回 nil
 */
+ (nullable NSString *)downloadLyricsForNCM:(NSString *)ncmPath
                                 outputPath:(nullable NSString *)outputPath
                                      error:(NSError **)error;

@end

/**
 * 音频文件格式工具类
 * 负责加载和管理各种音频格式，包括自动解密 NCM 文件
 */
@interface AudioFileFormats : NSObject

/**
 * 从 Bundle 中加载所有支持的音频文件
 * 自动检测并解密 NCM 文件
 * @return 音频文件名数组
 */
+ (NSArray<NSString *> *)loadAudioFilesFromBundle;

/**
 * 准备音频文件用于播放
 * 如果是 NCM 文件，会自动解密
 * @param fileName 文件名
 * @return 可播放的文件路径，如果失败返回原文件名
 */
+ (NSString *)prepareAudioFileForPlayback:(NSString *)fileName;

/**
 * 检查文件是否需要解密
 */
+ (BOOL)needsDecryption:(NSString *)fileName;

@end

NS_ASSUME_NONNULL_END
