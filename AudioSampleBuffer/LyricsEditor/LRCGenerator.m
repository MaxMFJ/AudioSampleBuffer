//
//  LRCGenerator.m
//  AudioSampleBuffer
//
//  用于手动打轴生成 LRC 文件的模型类
//

#import "LRCGenerator.h"

#pragma mark - LRCEditableLine Implementation

@implementation LRCEditableLine

- (instancetype)initWithText:(NSString *)text {
    return [self initWithText:text timestamp:-1];
}

- (instancetype)initWithText:(NSString *)text timestamp:(NSTimeInterval)timestamp {
    if (self = [super init]) {
        _text = [text copy] ?: @"";
        _timestamp = timestamp;
        _isTimestamped = (timestamp >= 0);
    }
    return self;
}

- (void)setTimestamp:(NSTimeInterval)timestamp {
    _timestamp = timestamp;
    _isTimestamped = (timestamp >= 0);
}

- (NSString *)formattedTimestamp {
    if (!self.isTimestamped) {
        return @"[--:--.--]";
    }
    return [LRCGenerator formatTime:self.timestamp];
}

- (NSString *)toLRCLine {
    if (!self.isTimestamped) {
        return self.text;
    }
    return [NSString stringWithFormat:@"%@%@", [self formattedTimestamp], self.text];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ %@>", 
            NSStringFromClass([self class]), 
            [self formattedTimestamp], 
            self.text];
}

@end

#pragma mark - LRCMetadata Implementation

@implementation LRCMetadata

- (instancetype)init {
    if (self = [super init]) {
        _offset = 0;
    }
    return self;
}

- (NSString *)toLRCMetadata {
    NSMutableString *result = [NSMutableString string];
    
    if (self.title.length > 0) {
        [result appendFormat:@"[ti:%@]\n", self.title];
    }
    if (self.artist.length > 0) {
        [result appendFormat:@"[ar:%@]\n", self.artist];
    }
    if (self.album.length > 0) {
        [result appendFormat:@"[al:%@]\n", self.album];
    }
    if (self.by.length > 0) {
        [result appendFormat:@"[by:%@]\n", self.by];
    }
    if (self.offset != 0) {
        [result appendFormat:@"[offset:%.0f]\n", self.offset];
    }
    
    return result;
}

@end

#pragma mark - LRCGenerator Implementation

@interface LRCGenerator ()

@property (nonatomic, strong, readwrite) NSMutableArray<LRCEditableLine *> *lines;

@end

@implementation LRCGenerator

#pragma mark - 初始化

- (instancetype)init {
    if (self = [super init]) {
        _lines = [NSMutableArray array];
        _metadata = [[LRCMetadata alloc] init];
        _currentIndex = 0;
    }
    return self;
}

#pragma mark - 属性

- (BOOL)isComplete {
    if (self.lines.count == 0) {
        return NO;
    }
    
    for (LRCEditableLine *line in self.lines) {
        if (!line.isTimestamped) {
            return NO;
        }
    }
    return YES;
}

- (NSInteger)timestampedCount {
    NSInteger count = 0;
    for (LRCEditableLine *line in self.lines) {
        if (line.isTimestamped) {
            count++;
        }
    }
    return count;
}

#pragma mark - 歌词导入

- (void)importFromText:(NSString *)text {
    [self.lines removeAllObjects];
    self.currentIndex = 0;
    
    if (!text || text.length == 0) {
        return;
    }
    
    // 统一换行符
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    
    // 按行分割
    NSArray<NSString *> *rawLines = [text componentsSeparatedByString:@"\n"];
    
    for (NSString *line in rawLines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        // 跳过空行（可选：保留空行作为歌词间隔）
        if (trimmedLine.length == 0) {
            continue;
        }
        
        LRCEditableLine *editableLine = [[LRCEditableLine alloc] initWithText:trimmedLine];
        [self.lines addObject:editableLine];
    }
}

- (void)importFromLRC:(NSString *)lrcContent {
    [self.lines removeAllObjects];
    self.currentIndex = 0;
    
    if (!lrcContent || lrcContent.length == 0) {
        return;
    }
    
    // 按行分割
    NSArray<NSString *> *rawLines = [lrcContent componentsSeparatedByString:@"\n"];
    
    // 时间戳正则表达式
    NSRegularExpression *timeRegex = [NSRegularExpression 
        regularExpressionWithPattern:@"\\[(\\d+):(\\d+)(?:\\.(\\d+))?\\]"
        options:0
        error:nil];
    
    // 元数据正则表达式
    NSRegularExpression *metaRegex = [NSRegularExpression 
        regularExpressionWithPattern:@"\\[([a-z]+):([^\\]]+)\\]"
        options:NSRegularExpressionCaseInsensitive
        error:nil];
    
    for (NSString *line in rawLines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (trimmedLine.length == 0) {
            continue;
        }
        
        // 检查是否是元数据
        NSTextCheckingResult *metaMatch = [metaRegex firstMatchInString:trimmedLine 
                                                                options:0 
                                                                  range:NSMakeRange(0, trimmedLine.length)];
        
        if (metaMatch && metaMatch.numberOfRanges >= 3) {
            NSString *tag = [[trimmedLine substringWithRange:[metaMatch rangeAtIndex:1]] lowercaseString];
            NSString *value = [trimmedLine substringWithRange:[metaMatch rangeAtIndex:2]];
            
            if ([tag isEqualToString:@"ti"]) {
                self.metadata.title = value;
            } else if ([tag isEqualToString:@"ar"]) {
                self.metadata.artist = value;
            } else if ([tag isEqualToString:@"al"]) {
                self.metadata.album = value;
            } else if ([tag isEqualToString:@"by"]) {
                self.metadata.by = value;
            } else if ([tag isEqualToString:@"offset"]) {
                self.metadata.offset = [value doubleValue];
            }
            continue;
        }
        
        // 检查是否有时间戳
        NSArray<NSTextCheckingResult *> *timeMatches = [timeRegex 
            matchesInString:trimmedLine 
            options:0 
            range:NSMakeRange(0, trimmedLine.length)];
        
        if (timeMatches.count > 0) {
            // 提取文本部分
            NSString *text = trimmedLine;
            for (NSTextCheckingResult *match in timeMatches.reverseObjectEnumerator) {
                text = [text stringByReplacingCharactersInRange:match.range withString:@""];
            }
            text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            
            // 为每个时间戳创建一行（处理一行多时间戳的情况）
            for (NSTextCheckingResult *match in timeMatches) {
                NSString *minutes = [trimmedLine substringWithRange:[match rangeAtIndex:1]];
                NSString *seconds = [trimmedLine substringWithRange:[match rangeAtIndex:2]];
                NSString *milliseconds = @"0";
                
                if (match.numberOfRanges >= 4 && [match rangeAtIndex:3].location != NSNotFound) {
                    milliseconds = [trimmedLine substringWithRange:[match rangeAtIndex:3]];
                }
                
                NSTimeInterval time = [minutes intValue] * 60.0 +
                                      [seconds intValue] +
                                      [milliseconds intValue] / 100.0;
                
                LRCEditableLine *editableLine = [[LRCEditableLine alloc] initWithText:text timestamp:time];
                [self.lines addObject:editableLine];
            }
        } else {
            // 没有时间戳的纯文本行
            LRCEditableLine *editableLine = [[LRCEditableLine alloc] initWithText:trimmedLine];
            [self.lines addObject:editableLine];
        }
    }
    
    // 按时间排序（有时间戳的在前，没有的按原顺序）
    [self.lines sortUsingComparator:^NSComparisonResult(LRCEditableLine *obj1, LRCEditableLine *obj2) {
        if (obj1.isTimestamped && obj2.isTimestamped) {
            if (obj1.timestamp < obj2.timestamp) return NSOrderedAscending;
            if (obj1.timestamp > obj2.timestamp) return NSOrderedDescending;
            return NSOrderedSame;
        }
        if (obj1.isTimestamped) return NSOrderedAscending;
        if (obj2.isTimestamped) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // 找到第一个未打轴的行
    for (NSInteger i = 0; i < self.lines.count; i++) {
        if (!self.lines[i].isTimestamped) {
            self.currentIndex = i;
            break;
        }
    }
}

#pragma mark - 歌词行操作

- (void)addLine:(NSString *)text {
    LRCEditableLine *line = [[LRCEditableLine alloc] initWithText:text];
    [self.lines addObject:line];
}

- (void)insertLine:(NSString *)text atIndex:(NSInteger)index {
    if (index < 0 || index > self.lines.count) {
        return;
    }
    
    LRCEditableLine *line = [[LRCEditableLine alloc] initWithText:text];
    [self.lines insertObject:line atIndex:index];
    
    // 调整当前索引
    if (index <= self.currentIndex) {
        self.currentIndex++;
    }
}

- (void)removeLineAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.lines.count) {
        return;
    }
    
    [self.lines removeObjectAtIndex:index];
    
    // 调整当前索引
    if (index < self.currentIndex) {
        self.currentIndex--;
    } else if (index == self.currentIndex && self.currentIndex >= self.lines.count) {
        self.currentIndex = MAX(0, self.lines.count - 1);
    }
}

- (void)updateLineText:(NSString *)text atIndex:(NSInteger)index {
    if (index < 0 || index >= self.lines.count) {
        return;
    }
    
    self.lines[index].text = text ?: @"";
}

- (void)moveLineFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    if (fromIndex < 0 || fromIndex >= self.lines.count ||
        toIndex < 0 || toIndex >= self.lines.count ||
        fromIndex == toIndex) {
        return;
    }
    
    LRCEditableLine *line = self.lines[fromIndex];
    [self.lines removeObjectAtIndex:fromIndex];
    [self.lines insertObject:line atIndex:toIndex];
    
    // 调整当前索引
    if (self.currentIndex == fromIndex) {
        self.currentIndex = toIndex;
    } else if (fromIndex < self.currentIndex && toIndex >= self.currentIndex) {
        self.currentIndex--;
    } else if (fromIndex > self.currentIndex && toIndex <= self.currentIndex) {
        self.currentIndex++;
    }
}

#pragma mark - 打轴操作

- (BOOL)stampCurrentLineWithTime:(NSTimeInterval)timestamp {
    if (self.currentIndex < 0 || self.currentIndex >= self.lines.count) {
        return NO;
    }
    
    self.lines[self.currentIndex].timestamp = timestamp;
    
    // 自动前进到下一行
    if (self.currentIndex < self.lines.count - 1) {
        self.currentIndex++;
    }
    
    return YES;
}

- (void)setTimestamp:(NSTimeInterval)timestamp forLineAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.lines.count) {
        return;
    }
    
    self.lines[index].timestamp = timestamp;
}

- (void)adjustTimestamp:(NSTimeInterval)delta forLineAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.lines.count) {
        return;
    }
    
    LRCEditableLine *line = self.lines[index];
    if (line.isTimestamped) {
        NSTimeInterval newTime = MAX(0, line.timestamp + delta);
        line.timestamp = newTime;
    }
}

- (void)clearTimestampAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.lines.count) {
        return;
    }
    
    self.lines[index].timestamp = -1;
}

- (void)clearAllTimestamps {
    for (LRCEditableLine *line in self.lines) {
        line.timestamp = -1;
    }
    self.currentIndex = 0;
}

- (BOOL)goBackToPreviousLine {
    if (self.currentIndex <= 0) {
        return NO;
    }
    
    // 清除当前行的时间戳（如果有的话）
    if (self.lines[self.currentIndex].isTimestamped) {
        [self clearTimestampAtIndex:self.currentIndex];
    }
    
    self.currentIndex--;
    
    // 清除上一行的时间戳，准备重新打轴
    [self clearTimestampAtIndex:self.currentIndex];
    
    return YES;
}

- (BOOL)goToNextLine {
    if (self.currentIndex >= self.lines.count - 1) {
        return NO;
    }
    
    self.currentIndex++;
    return YES;
}

- (void)goToLineAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.lines.count) {
        return;
    }
    
    self.currentIndex = index;
}

#pragma mark - LRC 生成

- (NSString *)generateLRCContent {
    NSMutableString *content = [NSMutableString string];
    
    // 添加元信息
    NSString *metadataStr = [self.metadata toLRCMetadata];
    if (metadataStr.length > 0) {
        [content appendString:metadataStr];
        [content appendString:@"\n"];
    }
    
    // 按时间排序歌词行
    NSArray<LRCEditableLine *> *sortedLines = [self.lines sortedArrayUsingComparator:^NSComparisonResult(LRCEditableLine *obj1, LRCEditableLine *obj2) {
        if (!obj1.isTimestamped && !obj2.isTimestamped) {
            return NSOrderedSame;
        }
        if (!obj1.isTimestamped) return NSOrderedDescending;
        if (!obj2.isTimestamped) return NSOrderedAscending;
        
        if (obj1.timestamp < obj2.timestamp) return NSOrderedAscending;
        if (obj1.timestamp > obj2.timestamp) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // 添加歌词行
    for (LRCEditableLine *line in sortedLines) {
        if (line.isTimestamped) {
            [content appendString:[line toLRCLine]];
            [content appendString:@"\n"];
        }
    }
    
    return content;
}

- (BOOL)saveLRCToPath:(NSString *)path error:(NSError **)error {
    NSString *content = [self generateLRCContent];
    
    return [content writeToFile:path 
                     atomically:YES 
                       encoding:NSUTF8StringEncoding 
                          error:error];
}

- (nullable NSString *)saveLRCWithFileName:(NSString *)fileName error:(NSError **)error {
    if (!fileName || fileName.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"LRCGenerator" 
                                         code:1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件名不能为空"}];
        }
        return nil;
    }
    
    // 确保文件名有 .lrc 扩展名
    if (![[fileName pathExtension] isEqualToString:@"lrc"]) {
        fileName = [fileName stringByAppendingPathExtension:@"lrc"];
    }
    
    // 获取 Documents 目录
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = paths.firstObject;
    
    // 创建 Lyrics 子目录
    NSString *lyricsDir = [documentsPath stringByAppendingPathComponent:@"Lyrics"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:lyricsDir]) {
        [fm createDirectoryAtPath:lyricsDir 
      withIntermediateDirectories:YES 
                       attributes:nil 
                            error:nil];
    }
    
    NSString *fullPath = [lyricsDir stringByAppendingPathComponent:fileName];
    
    if ([self saveLRCToPath:fullPath error:error]) {
        return fullPath;
    }
    
    return nil;
}

#pragma mark - 工具方法

+ (NSString *)formatTime:(NSTimeInterval)time {
    if (time < 0) {
        return @"[--:--.--]";
    }
    
    int minutes = (int)(time / 60);
    int seconds = (int)time % 60;
    int hundredths = (int)((time - (int)time) * 100);
    
    return [NSString stringWithFormat:@"[%02d:%02d.%02d]", minutes, seconds, hundredths];
}

+ (NSTimeInterval)parseTimeString:(NSString *)timeString {
    if (!timeString || timeString.length == 0) {
        return -1;
    }
    
    NSRegularExpression *regex = [NSRegularExpression 
        regularExpressionWithPattern:@"\\[?(\\d+):(\\d+)(?:\\.(\\d+))?\\]?"
        options:0
        error:nil];
    
    NSTextCheckingResult *match = [regex firstMatchInString:timeString 
                                                    options:0 
                                                      range:NSMakeRange(0, timeString.length)];
    
    if (!match || match.numberOfRanges < 3) {
        return -1;
    }
    
    NSString *minutes = [timeString substringWithRange:[match rangeAtIndex:1]];
    NSString *seconds = [timeString substringWithRange:[match rangeAtIndex:2]];
    NSString *milliseconds = @"0";
    
    if (match.numberOfRanges >= 4 && [match rangeAtIndex:3].location != NSNotFound) {
        milliseconds = [timeString substringWithRange:[match rangeAtIndex:3]];
    }
    
    NSTimeInterval time = [minutes intValue] * 60.0 +
                          [seconds intValue] +
                          [milliseconds intValue] / 100.0;
    
    return time;
}

@end

