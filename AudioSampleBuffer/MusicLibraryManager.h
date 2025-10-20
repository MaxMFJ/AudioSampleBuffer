//
//  MusicLibraryManager.h
//  AudioSampleBuffer
//
//  音乐库管理器 - 支持分类、搜索、排序
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 音乐分类枚举

typedef NS_ENUM(NSInteger, MusicCategory) {
    MusicCategoryAll = 0,           // 全部
    MusicCategoryRecent,            // 最近播放
    MusicCategoryFavorite,          // 我的最爱
    MusicCategoryMP3,               // MP3 文件
    MusicCategoryNCM,               // NCM 加密文件
    MusicCategoryFLAC,              // FLAC 无损
    MusicCategoryOther,             // 其他格式
    MusicCategoryChinese,           // 华语歌曲
    MusicCategoryEnglish,           // 英文歌曲
    MusicCategoryJapanese,          // 日文歌曲
    MusicCategoryKorean,            // 韩文歌曲
    MusicCategoryClassical,         // 古典音乐
    MusicCategoryPop,               // 流行音乐
    MusicCategoryRock,              // 摇滚
    MusicCategoryJazz,              // 爵士
    MusicCategoryCustom,            // 自定义分类
};

#pragma mark - 排序方式

typedef NS_ENUM(NSInteger, MusicSortType) {
    MusicSortByName = 0,            // 按名称
    MusicSortByArtist,              // 按艺术家
    MusicSortByDate,                // 按添加日期
    MusicSortByPlayCount,           // 按播放次数
    MusicSortByDuration,            // 按时长
    MusicSortByFileSize,            // 按文件大小
};

#pragma mark - 音乐项模型

@interface MusicItem : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *fileName;        // 文件名
@property (nonatomic, copy) NSString *displayName;     // 显示名称
@property (nonatomic, copy) NSString *filePath;        // 完整路径
@property (nonatomic, copy) NSString *fileExtension;   // 文件扩展名
@property (nonatomic, copy, nullable) NSString *artist;        // 艺术家
@property (nonatomic, copy, nullable) NSString *album;         // 专辑
@property (nonatomic, assign) NSTimeInterval duration;         // 时长
@property (nonatomic, assign) long long fileSize;              // 文件大小（字节）
@property (nonatomic, strong) NSDate *addedDate;               // 添加日期
@property (nonatomic, assign) NSInteger playCount;             // 播放次数
@property (nonatomic, strong, nullable) NSDate *lastPlayDate;  // 最后播放日期
@property (nonatomic, assign) BOOL isFavorite;                 // 是否收藏
@property (nonatomic, assign) BOOL isNCM;                      // 是否是 NCM 文件
@property (nonatomic, assign) BOOL isDecrypted;                // NCM 是否已解密
@property (nonatomic, copy, nullable) NSString *decryptedPath; // 解密后的路径
@property (nonatomic, strong, nullable) NSArray<NSString *> *categories; // 所属分类

// 便利初始化方法
+ (instancetype)itemWithFileName:(NSString *)fileName;
+ (instancetype)itemWithFileName:(NSString *)fileName filePath:(NSString *)filePath;

// 获取可播放的路径（自动处理 NCM 解密）
- (NSString *)playableFilePath;

// 格式化显示
- (NSString *)formattedDuration;        // 格式化时长 (3:45)
- (NSString *)formattedFileSize;        // 格式化文件大小 (4.5 MB)
- (NSString *)formattedArtistAndAlbum;  // 艺术家 - 专辑

@end

#pragma mark - 音乐库管理器

@interface MusicLibraryManager : NSObject

+ (instancetype)sharedManager;

/**
 * 获取云下载目录路径（与 MusicDownloadManager 保持一致）
 */
+ (NSString *)cloudDownloadDirectory;

#pragma mark - 基础操作

// 加载音乐库（从 Bundle 和 Documents）
- (void)loadMusicLibrary;

// 刷新音乐库
- (void)reloadMusicLibrary;

// 获取所有音乐
- (NSArray<MusicItem *> *)allMusic;

// 获取音乐总数
- (NSInteger)totalMusicCount;

#pragma mark - 分类管理

// 获取指定分类的音乐
- (NSArray<MusicItem *> *)musicForCategory:(MusicCategory)category;

// 获取分类数量
- (NSInteger)countForCategory:(MusicCategory)category;

// 获取分类名称
+ (NSString *)nameForCategory:(MusicCategory)category;

// 获取所有可用分类
- (NSArray<NSNumber *> *)availableCategories;

// 添加自定义分类
- (void)addCustomCategory:(NSString *)categoryName forMusic:(NSArray<MusicItem *> *)musicItems;

#pragma mark - 搜索功能

// 搜索音乐（按名称、艺术家、专辑）
- (NSArray<MusicItem *> *)searchMusic:(NSString *)keyword;

// 搜索指定分类中的音乐
- (NSArray<MusicItem *> *)searchMusic:(NSString *)keyword inCategory:(MusicCategory)category;

#pragma mark - 排序功能

// 排序音乐列表
- (NSArray<MusicItem *> *)sortMusic:(NSArray<MusicItem *> *)musicList
                             byType:(MusicSortType)sortType
                         ascending:(BOOL)ascending;

#pragma mark - 播放记录

// 记录播放
- (void)recordPlayForMusic:(MusicItem *)music;

// 获取最近播放
- (NSArray<MusicItem *> *)recentPlayedMusic:(NSInteger)limit;

// 获取播放次数最多的歌曲
- (NSArray<MusicItem *> *)mostPlayedMusic:(NSInteger)limit;

#pragma mark - 收藏管理

// 添加/移除收藏
- (void)toggleFavoriteForMusic:(MusicItem *)music;

// 获取收藏列表
- (NSArray<MusicItem *> *)favoriteMusic;

#pragma mark - NCM 文件管理

// 获取所有 NCM 文件
- (NSArray<MusicItem *> *)allNCMFiles;

// 获取未解密的 NCM 文件
- (NSArray<MusicItem *> *)unDecryptedNCMFiles;

// 更新 NCM 解密状态
- (void)updateNCMDecryptionStatus:(MusicItem *)music decryptedPath:(NSString *)path;

#pragma mark - 统计信息

// 获取统计信息
- (NSDictionary *)statistics;

#pragma mark - 持久化

// 保存到磁盘
- (void)saveToCache;

// 从磁盘加载
- (void)loadFromCache;

@end

NS_ASSUME_NONNULL_END

