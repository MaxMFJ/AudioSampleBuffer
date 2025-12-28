//
//  LRCGenerator.h
//  AudioSampleBuffer
//
//  用于手动打轴生成 LRC 文件的模型类
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 歌词行编辑模型（支持可变时间戳）
@interface LRCEditableLine : NSObject

@property (nonatomic, assign) NSTimeInterval timestamp;  // 时间戳（秒），-1 表示未设置
@property (nonatomic, copy) NSString *text;               // 歌词文本
@property (nonatomic, assign) BOOL isTimestamped;         // 是否已打轴

- (instancetype)initWithText:(NSString *)text;
- (instancetype)initWithText:(NSString *)text timestamp:(NSTimeInterval)timestamp;

/// 格式化时间戳为 [mm:ss.xx] 格式
- (NSString *)formattedTimestamp;

/// 生成完整的 LRC 行（包含时间戳和文本）
- (NSString *)toLRCLine;

@end

/// LRC 元信息
@interface LRCMetadata : NSObject

@property (nonatomic, copy, nullable) NSString *title;   // 歌曲标题 [ti:]
@property (nonatomic, copy, nullable) NSString *artist;  // 艺术家 [ar:]
@property (nonatomic, copy, nullable) NSString *album;   // 专辑 [al:]
@property (nonatomic, copy, nullable) NSString *by;      // 制作者 [by:]
@property (nonatomic, assign) NSTimeInterval offset;      // 时间偏移（毫秒）[offset:]

/// 生成元信息的 LRC 格式字符串
- (NSString *)toLRCMetadata;

@end

/// LRC 生成器 - 管理歌词打轴和 LRC 文件生成
@interface LRCGenerator : NSObject

/// 元信息
@property (nonatomic, strong) LRCMetadata *metadata;

/// 歌词行数组
@property (nonatomic, strong, readonly) NSMutableArray<LRCEditableLine *> *lines;

/// 当前打轴索引
@property (nonatomic, assign) NSInteger currentIndex;

/// 是否所有行都已打轴完成
@property (nonatomic, readonly) BOOL isComplete;

/// 已打轴的行数
@property (nonatomic, readonly) NSInteger timestampedCount;

#pragma mark - 初始化

- (instancetype)init;

#pragma mark - 歌词导入

/// 从纯文本导入歌词（按行分割）
/// @param text 完整歌词文本
- (void)importFromText:(NSString *)text;

/// 从已有的 LRC 文件导入（保留时间戳）
/// @param lrcContent LRC 格式的歌词内容
- (void)importFromLRC:(NSString *)lrcContent;

#pragma mark - 歌词行操作

/// 添加一行歌词
/// @param text 歌词文本
- (void)addLine:(NSString *)text;

/// 在指定位置插入一行歌词
/// @param text 歌词文本
/// @param index 插入位置
- (void)insertLine:(NSString *)text atIndex:(NSInteger)index;

/// 删除指定位置的歌词行
/// @param index 删除位置
- (void)removeLineAtIndex:(NSInteger)index;

/// 修改指定位置的歌词文本
/// @param text 新的歌词文本
/// @param index 修改位置
- (void)updateLineText:(NSString *)text atIndex:(NSInteger)index;

/// 移动歌词行
/// @param fromIndex 原位置
/// @param toIndex 目标位置
- (void)moveLineFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;

#pragma mark - 打轴操作

/// 为当前行设置时间戳并前进到下一行
/// @param timestamp 时间戳（秒）
/// @return 设置成功返回 YES
- (BOOL)stampCurrentLineWithTime:(NSTimeInterval)timestamp;

/// 为指定行设置时间戳
/// @param timestamp 时间戳（秒）
/// @param index 行索引
- (void)setTimestamp:(NSTimeInterval)timestamp forLineAtIndex:(NSInteger)index;

/// 微调指定行的时间戳
/// @param delta 调整量（秒），正数为后移，负数为前移
/// @param index 行索引
- (void)adjustTimestamp:(NSTimeInterval)delta forLineAtIndex:(NSInteger)index;

/// 清除指定行的时间戳
/// @param index 行索引
- (void)clearTimestampAtIndex:(NSInteger)index;

/// 清除所有时间戳
- (void)clearAllTimestamps;

/// 回退到上一行（重新打轴）
/// @return 回退成功返回 YES
- (BOOL)goBackToPreviousLine;

/// 前进到下一行
/// @return 前进成功返回 YES
- (BOOL)goToNextLine;

/// 跳转到指定行
/// @param index 行索引
- (void)goToLineAtIndex:(NSInteger)index;

#pragma mark - LRC 生成

/// 生成完整的 LRC 文件内容
/// @return LRC 格式的字符串
- (NSString *)generateLRCContent;

/// 保存 LRC 文件到指定路径
/// @param path 文件保存路径
/// @param error 错误信息
/// @return 保存成功返回 YES
- (BOOL)saveLRCToPath:(NSString *)path error:(NSError **)error;

/// 保存 LRC 文件到 Documents 目录
/// @param fileName 文件名（不含扩展名）
/// @param error 错误信息
/// @return 保存的完整路径，失败返回 nil
- (nullable NSString *)saveLRCWithFileName:(NSString *)fileName error:(NSError **)error;

#pragma mark - 工具方法

/// 格式化时间为 [mm:ss.xx] 格式的字符串
/// @param time 时间（秒）
+ (NSString *)formatTime:(NSTimeInterval)time;

/// 解析 [mm:ss.xx] 格式的时间字符串
/// @param timeString 时间字符串
/// @return 时间（秒），解析失败返回 -1
+ (NSTimeInterval)parseTimeString:(NSString *)timeString;

@end

NS_ASSUME_NONNULL_END

