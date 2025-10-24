//
//  QQMusicAPIService.h
//  AudioSampleBuffer
//
//  QQ音乐API服务（新API）
//  替代酷狗等平台，使用 api.qqmp3.vip
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 音乐搜索结果模型
@interface QQMusicSearchResult : NSObject

@property (nonatomic, strong) NSString *rid;           // 资源ID
@property (nonatomic, strong) NSString *name;          // 歌曲名
@property (nonatomic, strong) NSString *artist;        // 艺术家
@property (nonatomic, strong) NSString *album;         // 专辑名
@property (nonatomic, strong) NSString *pic;           // 封面图片URL
@property (nonatomic, strong) NSString *src;           // 播放链接（带歌词）
@property (nonatomic, strong) NSArray<NSString *> *downurl; // 下载链接数组

@end

/// 音乐详情模型（包含下载链接和歌词）
@interface QQMusicDetail : NSObject

@property (nonatomic, strong) NSString *rid;           // 资源ID
@property (nonatomic, strong) NSString *name;          // 歌曲名
@property (nonatomic, strong) NSString *artist;        // 艺术家
@property (nonatomic, strong) NSString *album;         // 专辑
@property (nonatomic, strong) NSString *quality;       // 音质描述
@property (nonatomic, strong) NSString *duration;      // 时长
@property (nonatomic, strong) NSString *size;          // 文件大小
@property (nonatomic, strong) NSString *pic;           // 封面图片URL
@property (nonatomic, strong) NSString *url;           // MP3下载链接
@property (nonatomic, strong) NSString *lrc;           // 歌词内容（LRC格式）

@end

/// QQ音乐API服务
@interface QQMusicAPIService : NSObject

/// 单例
+ (instancetype)sharedService;

/**
 * 搜索音乐
 * @param keyword 搜索关键词（歌手 歌名）
 * @param completion 完成回调：(搜索结果数组, 错误信息)
 */
- (void)searchMusic:(NSString *)keyword
         completion:(void (^)(NSArray<QQMusicSearchResult *> * _Nullable results, NSError * _Nullable error))completion;

/**
 * 获取音乐详情（包含下载链接和歌词）
 * @param rid 资源ID
 * @param completion 完成回调：(音乐详情, 错误信息)
 */
- (void)getMusicDetail:(NSString *)rid
            completion:(void (^)(QQMusicDetail * _Nullable detail, NSError * _Nullable error))completion;

/**
 * 下载音乐文件
 * @param detail 音乐详情
 * @param progress 进度回调：(下载进度 0.0-1.0, 状态描述)
 * @param completion 完成回调：(本地文件路径, 错误信息)
 */
- (void)downloadMusic:(QQMusicDetail *)detail
             progress:(void (^)(float progress, NSString *status))progress
           completion:(void (^)(NSString * _Nullable filePath, NSError * _Nullable error))completion;

/**
 * 搜索并下载第一个结果（快速下载）
 * @param keyword 搜索关键词
 * @param progress 进度回调
 * @param completion 完成回调
 */
- (void)searchAndDownload:(NSString *)keyword
                 progress:(void (^)(float progress, NSString *status))progress
               completion:(void (^)(NSString * _Nullable filePath, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

