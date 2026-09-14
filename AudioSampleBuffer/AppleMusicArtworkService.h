//
//  AppleMusicArtworkService.h
//  AudioSampleBuffer
//
//  从 Apple Music 目录检索专辑封面。
//  使用 Apple 官方 iTunes Search API（返回与 Apple Music 相同的 mzstatic 封面），
//  无需 MusicKit 权限、用户授权或 Apple Music 订阅。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppleMusicArtworkService : NSObject

+ (instancetype)sharedService;

/// 同步读取该音频文件已缓存的 Apple Music 封面（内存 / Caches）
- (nullable UIImage *)cachedArtworkForFilePath:(nullable NSString *)filePath;

/**
 * 按歌名、艺术家、专辑从 Apple Music 目录搜索封面。
 * 命中后写入 Caches，并在音频文件所在目录可写时保存 `{basename}_cover.jpg`。
 */
- (void)fetchArtworkWithTitle:(nullable NSString *)title
                       artist:(nullable NSString *)artist
                        album:(nullable NSString *)album
                     filePath:(nullable NSString *)filePath
                   completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
