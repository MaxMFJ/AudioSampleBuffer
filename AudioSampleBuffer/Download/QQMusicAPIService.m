//
//  QQMusicAPIService.m
//  AudioSampleBuffer
//
//  QQ音乐API服务实现
//

#import "QQMusicAPIService.h"
#import "MusicLibraryManager.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// API基础URL
static NSString *const kAPIBaseURL = @"https://api.qqmp3.vip/api";

@implementation QQMusicSearchResult
@end

@implementation QQMusicDetail
@end

@interface QQMusicAPIService ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation QQMusicAPIService

#pragma mark - Singleton

+ (instancetype)sharedService {
    static QQMusicAPIService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15",
            @"Accept": @"*/*",
            @"Accept-Language": @"zh-CN,zh-Hans;q=0.9",
            @"Accept-Encoding": @"gzip, deflate, br"
        };
        self.session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Public Methods

- (void)searchMusic:(NSString *)keyword completion:(void (^)(NSArray<QQMusicSearchResult *> * _Nullable, NSError * _Nullable))completion {
    if (!keyword || keyword.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"关键词不能为空"}];
        completion(nil, error);
        return;
    }
    
    // URL编码关键词
    NSString *encodedKeyword = [keyword stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"%@/songs.php?type=search&keyword=%@", kAPIBaseURL, encodedKeyword];
    
    NSLog(@"🔍 [搜索] URL: %@", urlString);
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://www.qqmp3.vip" forHTTPHeaderField:@"Referer"];
    [request setValue:@"https://www.qqmp3.vip" forHTTPHeaderField:@"Origin"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ [搜索] 网络错误: %@", error.localizedDescription);
            completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:httpResponse.statusCode
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"服务器返回错误: %ld", (long)httpResponse.statusCode]}];
            NSLog(@"❌ [搜索] HTTP错误: %ld", (long)httpResponse.statusCode);
            completion(nil, error);
            return;
        }
        
        // 解析JSON
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSLog(@"❌ [搜索] JSON解析错误: %@", jsonError.localizedDescription);
            completion(nil, jsonError);
            return;
        }
        
        // 检查返回状态
        NSNumber *code = json[@"code"];
        if (!code || [code integerValue] != 200) {
            NSString *message = json[@"message"] ?: @"搜索失败";
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:[code integerValue]
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
            NSLog(@"❌ [搜索] API错误: %@", message);
            completion(nil, error);
            return;
        }
        
        // 解析数据
        NSArray *dataArray = json[@"data"];
        if (![dataArray isKindOfClass:[NSArray class]]) {
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:-2
                                             userInfo:@{NSLocalizedDescriptionKey: @"数据格式错误"}];
            NSLog(@"❌ [搜索] 数据格式错误");
            completion(nil, error);
            return;
        }
        
        NSMutableArray<QQMusicSearchResult *> *results = [NSMutableArray array];
        for (NSDictionary *item in dataArray) {
            QQMusicSearchResult *result = [[QQMusicSearchResult alloc] init];
            // 🔧 安全地从字典中获取字符串值（处理 NSNull）
            result.rid = [self safeStringFromDict:item key:@"rid"];
            result.name = [self safeStringFromDict:item key:@"name"];
            result.artist = [self safeStringFromDict:item key:@"artist"];
            result.pic = [self safeStringFromDict:item key:@"pic"];
            result.src = [self safeStringFromDict:item key:@"src"];
            result.downurl = item[@"downurl"]; // 数组类型，保持原样
            [results addObject:result];
        }
        
        NSLog(@"✅ [搜索] 找到 %lu 个结果", (unsigned long)results.count);
        completion(results, nil);
    }];
    
    [task resume];
}

- (void)getMusicDetail:(NSString *)rid completion:(void (^)(QQMusicDetail * _Nullable, NSError * _Nullable))completion {
    if (!rid || rid.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"资源ID不能为空"}];
        completion(nil, error);
        return;
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@/kw.php?rid=%@&type=json&level=exhigh&lrc=true", kAPIBaseURL, rid];
    NSLog(@"📥 [详情] URL: %@", urlString);
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://www.qqmp3.vip" forHTTPHeaderField:@"Referer"];
    [request setValue:@"https://www.qqmp3.vip" forHTTPHeaderField:@"Origin"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ [详情] 网络错误: %@", error.localizedDescription);
            completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:httpResponse.statusCode
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"服务器返回错误: %ld", (long)httpResponse.statusCode]}];
            NSLog(@"❌ [详情] HTTP错误: %ld", (long)httpResponse.statusCode);
            completion(nil, error);
            return;
        }
        
        // 解析JSON
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            NSLog(@"❌ [详情] JSON解析错误: %@", jsonError.localizedDescription);
            completion(nil, jsonError);
            return;
        }
        
        // 检查返回状态
        NSNumber *code = json[@"code"];
        if (!code || [code integerValue] != 200) {
            NSString *message = json[@"msg"] ?: @"获取详情失败";
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:[code integerValue]
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
            NSLog(@"❌ [详情] API错误: %@", message);
            completion(nil, error);
            return;
        }
        
        // 解析数据
        NSDictionary *dataDict = json[@"data"];
        if (![dataDict isKindOfClass:[NSDictionary class]]) {
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:-2
                                             userInfo:@{NSLocalizedDescriptionKey: @"数据格式错误"}];
            NSLog(@"❌ [详情] 数据格式错误");
            completion(nil, error);
            return;
        }
        
        QQMusicDetail *detail = [[QQMusicDetail alloc] init];
        // 🔧 安全地从字典中获取字符串值（处理 NSNull）
        detail.rid = [self safeStringFromDict:dataDict key:@"rid"];
        detail.name = [self safeStringFromDict:dataDict key:@"name"];
        detail.artist = [self safeStringFromDict:dataDict key:@"artist"];
        detail.album = [self safeStringFromDict:dataDict key:@"album"];
        detail.quality = [self safeStringFromDict:dataDict key:@"quality"];
        detail.duration = [self safeStringFromDict:dataDict key:@"duration"];
        detail.size = [self safeStringFromDict:dataDict key:@"size"];
        detail.pic = [self safeStringFromDict:dataDict key:@"pic"];
        detail.url = [self safeStringFromDict:dataDict key:@"url"];
        detail.lrc = [self safeStringFromDict:dataDict key:@"lrc"];
        
        NSLog(@"✅ [详情] 获取成功: %@ - %@", detail.artist ?: @"未知", detail.name ?: @"未知");
        completion(detail, nil);
    }];
    
    [task resume];
}

- (void)downloadMusic:(QQMusicDetail *)detail
             progress:(void (^)(float, NSString *))progress
           completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    
    // 🔧 检查下载链接
    if (!detail.url || detail.url.length == 0 || [detail.url isKindOfClass:[NSNull class]]) {
        NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"下载链接无效"}];
        NSLog(@"❌ [下载] 下载链接无效");
        completion(nil, error);
        return;
    }
    
    // 🔧 检查歌曲名称（用于生成文件名）
    if ((!detail.name || detail.name.length == 0) && (!detail.artist || detail.artist.length == 0)) {
        NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"歌曲信息不完整，无法生成文件名"}];
        NSLog(@"❌ [下载] 歌曲信息不完整");
        completion(nil, error);
        return;
    }
    
    NSLog(@"⬇️ [下载] 开始: %@ - %@", detail.artist ?: @"未知", detail.name ?: @"未知");
    NSLog(@"⬇️ [下载] URL: %@", detail.url);
    
    // 🔧 创建下载目录（如果不存在）
    NSString *downloadDir = [MusicLibraryManager cloudDownloadDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:downloadDir]) {
        NSError *createError = nil;
        [fileManager createDirectoryAtPath:downloadDir 
               withIntermediateDirectories:YES 
                                attributes:nil 
                                     error:&createError];
        if (createError) {
            NSLog(@"❌ [下载] 创建下载目录失败: %@", createError.localizedDescription);
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:-1
                                             userInfo:@{NSLocalizedDescriptionKey: @"无法创建下载目录"}];
            completion(nil, error);
            return;
        }
        NSLog(@"✅ [下载] 下载目录已创建: %@", downloadDir);
    }
    
    // 生成文件名（艺术家 - 歌名）
    NSString *safeArtist = [self sanitizeFileName:detail.artist];
    NSString *safeName = [self sanitizeFileName:detail.name];
    NSString *baseFileName = [NSString stringWithFormat:@"%@ - %@", safeArtist, safeName];
    
    // 🔧 自动检测文件扩展名（从URL推断）
    NSString *downloadExtension = @"mp3";
    if ([detail.url containsString:@".aac"]) {
        downloadExtension = @"aac";
        NSLog(@"🔍 [下载] 检测到AAC格式");
    } else if ([detail.url containsString:@".m4a"]) {
        downloadExtension = @"m4a";
        NSLog(@"🔍 [下载] 检测到M4A格式");
    }
    
    // 🆕 先下载为临时文件，如果有封面则转换为M4A，否则保持原格式
    NSString *tempFilePath = [downloadDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_temp.%@", baseFileName, downloadExtension]];
    
    NSURL *url = [NSURL URLWithString:detail.url];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://www.qqmp3.vip" forHTTPHeaderField:@"Referer"];
    
    // 创建下载任务
    NSURLSessionDownloadTask *downloadTask = [self.session downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ [下载] 失败: %@", error.localizedDescription);
            completion(nil, error);
            return;
        }
        
        // 移动文件到临时位置
        NSError *moveError = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:tempFilePath] error:&moveError];
        if (moveError) {
            NSLog(@"❌ [下载] 移动文件失败: %@", moveError.localizedDescription);
            completion(nil, moveError);
            return;
        }
        
        NSLog(@"✅ [下载] 完成: %@_temp.%@", baseFileName, downloadExtension);
        
        // 🆕 下载封面并嵌入到音频文件中（如果有）
        if (detail.pic && detail.pic.length > 0 && ![detail.pic isKindOfClass:[NSNull class]]) {
            // 🎵 有封面：下载封面并转换为M4A格式（支持更好的metadata）
            NSString *finalM4APath = [downloadDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", baseFileName]];
            
            // 检查最终文件是否已存在
            if ([[NSFileManager defaultManager] fileExistsAtPath:finalM4APath]) {
                NSLog(@"⚠️ [下载] M4A文件已存在，删除临时文件");
                [[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];
                completion(finalM4APath, nil);
                return;
            }
            
            NSLog(@"🖼️ [封面] 开始下载并嵌入封面，转换为M4A格式...");
            [self downloadAndEmbedArtwork:detail.pic 
                              toMusicFile:tempFilePath
                           finalOutputPath:finalM4APath
                               artistName:detail.artist ?: @"未知艺术家"
                                 songName:detail.name ?: @"未知歌曲"
                               completion:^(BOOL success, NSString *outputPath) {
                
                if (success) {
                    NSLog(@"✅ [封面] 封面已成功嵌入到M4A文件");
                    
                    // 🔧 成功：删除临时文件
                    [[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];
                    
                    // 下载歌词（使用M4A文件名）
                    if (detail.lrc && detail.lrc.length > 0 && ![detail.lrc isKindOfClass:[NSNull class]]) {
                        [self saveLyrics:detail.lrc forFileName:[outputPath lastPathComponent]];
                    }
                    
                    completion(outputPath, nil);
                } else {
                    NSLog(@"⚠️ [封面] 封面嵌入失败，保留原音频文件");
                    
                    // 🔧 失败：将临时文件重命名为最终文件（保持原格式）
                    NSString *finalPath = [downloadDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseFileName, downloadExtension]];
                    NSError *renameError = nil;
                    
                    // 检查临时文件是否存在
                    if ([[NSFileManager defaultManager] fileExistsAtPath:tempFilePath]) {
                        [[NSFileManager defaultManager] moveItemAtPath:tempFilePath toPath:finalPath error:&renameError];
                        
                        if (renameError) {
                            NSLog(@"❌ [封面] 重命名文件失败: %@", renameError.localizedDescription);
                            completion(nil, renameError);
                            return;
                        }
                        
                        NSLog(@"✅ [封面] 音频文件已保存: %@", [finalPath lastPathComponent]);
                    } else {
                        NSLog(@"❌ [封面] 临时文件不存在: %@", tempFilePath);
                        NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                             code:-1
                                                         userInfo:@{NSLocalizedDescriptionKey: @"临时文件丢失"}];
                        completion(nil, error);
                        return;
                    }
                    
                    // 下载歌词（使用原格式文件名）
                    if (detail.lrc && detail.lrc.length > 0 && ![detail.lrc isKindOfClass:[NSNull class]]) {
                        [self saveLyrics:detail.lrc forFileName:[finalPath lastPathComponent]];
                    }
                    
                    completion(finalPath, nil);
                }
            }];
        } else {
            // 🎵 没有封面：保持原格式
            NSString *finalPath = [downloadDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseFileName, downloadExtension]];
            
            // 检查最终文件是否已存在
            if ([[NSFileManager defaultManager] fileExistsAtPath:finalPath]) {
                NSLog(@"⚠️ [下载] 文件已存在，删除临时文件");
                [[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];
                completion(finalPath, nil);
                return;
            }
            
            // 重命名临时文件为最终文件
            NSError *renameError = nil;
            [[NSFileManager defaultManager] moveItemAtPath:tempFilePath toPath:finalPath error:&renameError];
            if (renameError) {
                NSLog(@"❌ [下载] 重命名文件失败: %@", renameError.localizedDescription);
                completion(nil, renameError);
                return;
            }
            
            NSLog(@"✅ [下载] 最终文件: %@", [finalPath lastPathComponent]);
            
            // 下载歌词（如果有）
            if (detail.lrc && detail.lrc.length > 0 && ![detail.lrc isKindOfClass:[NSNull class]]) {
                [self saveLyrics:detail.lrc forFileName:[finalPath lastPathComponent]];
            }
            
            completion(finalPath, nil);
        }
    }];
    
    [downloadTask resume];
    
    // 更新进度
    if (progress) {
        progress(0.5, @"下载中...");
    }
}

- (void)searchAndDownload:(NSString *)keyword
                 progress:(void (^)(float, NSString *))progress
               completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    
    if (progress) {
        progress(0.0, @"搜索中...");
    }
    
    // 先搜索
    [self searchMusic:keyword completion:^(NSArray<QQMusicSearchResult *> *results, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        if (results.count == 0) {
            NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                                 code:-3
                                             userInfo:@{NSLocalizedDescriptionKey: @"没有找到相关歌曲"}];
            completion(nil, error);
            return;
        }
        
        if (progress) {
            progress(0.3, @"获取详情...");
        }
        
        // 获取第一个结果的详情
        QQMusicSearchResult *firstResult = results.firstObject;
        [self getMusicDetail:firstResult.rid completion:^(QQMusicDetail *detail, NSError *error) {
            if (error) {
                completion(nil, error);
                return;
            }
            
            if (progress) {
                progress(0.5, @"下载中...");
            }
            
            // 下载音乐
            [self downloadMusic:detail progress:^(float downloadProgress, NSString *status) {
                if (progress) {
                    // 0.5-1.0 的进度用于下载
                    progress(0.5 + downloadProgress * 0.5, status);
                }
            } completion:completion];
        }];
    }];
}

#pragma mark - Helper Methods

/// 🔧 安全地从字典中获取字符串值（处理 NSNull 和 nil）
- (NSString *)safeStringFromDict:(NSDictionary *)dict key:(NSString *)key {
    id value = dict[key];
    
    // 处理 nil 和 NSNull
    if (!value || [value isKindOfClass:[NSNull class]]) {
        return nil;
    }
    
    // 确保是字符串类型
    if ([value isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)value;
        // 返回非空字符串，否则返回 nil
        return str.length > 0 ? str : nil;
    }
    
    // 如果是数字，转换为字符串
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    
    return nil;
}

- (NSString *)sanitizeFileName:(NSString *)fileName {
    // 🔧 处理 nil 和 NSNull
    if (!fileName || [fileName isKindOfClass:[NSNull class]]) {
        return @"未知";
    }
    
    // 确保是字符串
    if (![fileName isKindOfClass:[NSString class]]) {
        return @"未知";
    }
    
    // 移除不安全的字符
    NSCharacterSet *illegalCharacters = [NSCharacterSet characterSetWithCharactersInString:@"/:*?\"<>|\\"];
    NSArray *components = [fileName componentsSeparatedByCharactersInSet:illegalCharacters];
    NSString *sanitized = [components componentsJoinedByString:@"_"];
    
    // 去除首尾空格
    sanitized = [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    return sanitized.length > 0 ? sanitized : @"未知";
}

- (void)saveLyrics:(NSString *)lrcContent forFileName:(NSString *)musicFileName {
    if (!lrcContent || lrcContent.length == 0) return;
    
    NSString *downloadDir = [MusicLibraryManager cloudDownloadDirectory];
    NSString *lrcFileName = [[musicFileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"lrc"];
    NSString *lrcPath = [downloadDir stringByAppendingPathComponent:lrcFileName];
    
    NSError *error = nil;
    [lrcContent writeToFile:lrcPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        NSLog(@"⚠️ [歌词] 保存失败: %@", error.localizedDescription);
    } else {
        NSLog(@"✅ [歌词] 保存成功: %@", lrcFileName);
    }
}

/// 🆕 下载封面并嵌入到音频文件中（转换为M4A格式）
- (void)downloadAndEmbedArtwork:(NSString *)coverURL
                    toMusicFile:(NSString *)musicFilePath
                 finalOutputPath:(NSString *)outputPath
                     artistName:(NSString *)artistName
                       songName:(NSString *)songName
                     completion:(void (^)(BOOL success, NSString *outputPath))completion {
    
    if (!coverURL || coverURL.length == 0) {
        NSLog(@"⚠️ [封面] URL为空，跳过");
        completion(NO, nil);
        return;
    }
    
    // 🔒 安全修复：自动将HTTP转换为HTTPS
    if ([coverURL hasPrefix:@"http://"]) {
        coverURL = [coverURL stringByReplacingOccurrencesOfString:@"http://" withString:@"https://"];
        NSLog(@"🔒 [封面] 已将HTTP转换为HTTPS: %@", coverURL);
    }
    
    NSURL *url = [NSURL URLWithString:coverURL];
    if (!url) {
        NSLog(@"⚠️ [封面] URL无效: %@", coverURL);
        completion(NO, nil);
        return;
    }
    
    NSLog(@"🖼️ [封面] 下载封面: %@", coverURL);
    
    // 下载封面图片
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ [封面] 下载失败: %@", error.localizedDescription);
            completion(NO, nil);
            return;
        }
        
        // 读取图片数据
        NSData *imageData = [NSData dataWithContentsOfURL:location];
        if (!imageData || imageData.length == 0) {
            NSLog(@"❌ [封面] 图片数据为空");
            completion(NO, nil);
            return;
        }
        
        UIImage *image = [UIImage imageWithData:imageData];
        if (!image) {
            NSLog(@"❌ [封面] 无法解析图片");
            completion(NO, nil);
            return;
        }
        
        NSLog(@"✅ [封面] 图片下载成功 (%.0fx%.0f, %.1f KB)", 
              image.size.width, image.size.height, imageData.length / 1024.0);
        
        // 将封面嵌入到音频文件中并转换为M4A
        [self embedArtwork:imageData 
               toMusicFile:musicFilePath
            outputFilePath:outputPath
                artistName:artistName
                  songName:songName
                completion:completion];
    }];
    
    [task resume];
}

/// 🆕 将封面和metadata嵌入到音频文件中（转换为M4A格式）
- (void)embedArtwork:(NSData *)artworkData
         toMusicFile:(NSString *)musicFilePath
      outputFilePath:(NSString *)outputFilePath
          artistName:(NSString *)artistName
            songName:(NSString *)songName
          completion:(void (^)(BOOL success, NSString *outputPath))completion {
    
    if (!artworkData || !musicFilePath || !outputFilePath) {
        NSLog(@"❌ [嵌入] 参数无效");
        completion(NO, nil);
        return;
    }
    
    NSURL *sourceURL = [NSURL fileURLWithPath:musicFilePath];
    
    // 创建AVAsset
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    
    NSLog(@"📋 [嵌入] 源文件信息:");
    NSLog(@"   路径: %@", musicFilePath);
    NSLog(@"   格式: %@", [[musicFilePath pathExtension] uppercaseString]);
    
    // 🔧 检查兼容的导出预设
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSLog(@"   兼容预设: %@", compatiblePresets);
    
    // 🔧 关键修复：使用适合音频转换的预设，而不是 Passthrough
    // AVAssetExportPresetAppleM4A 专门用于转换为 M4A 格式
    NSString *preset = nil;
    
    if ([compatiblePresets containsObject:AVAssetExportPresetAppleM4A]) {
        preset = AVAssetExportPresetAppleM4A;
        NSLog(@"✅ [嵌入] 使用 AppleM4A 预设（最佳）");
    } else if ([compatiblePresets containsObject:AVAssetExportPresetPassthrough]) {
        preset = AVAssetExportPresetPassthrough;
        NSLog(@"⚠️ [嵌入] 使用 Passthrough 预设（可能不支持格式转换）");
    } else if (compatiblePresets.count > 0) {
        preset = compatiblePresets.firstObject;
        NSLog(@"⚠️ [嵌入] 使用备用预设: %@", preset);
    } else {
        NSLog(@"❌ [嵌入] 没有兼容的导出预设");
        completion(NO, nil);
        return;
    }
    
    // 创建导出会话
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset 
                                                                            presetName:preset];
    if (!exportSession) {
        NSLog(@"❌ [嵌入] 创建导出会话失败");
        completion(NO, nil);
        return;
    }
    
    // 设置输出URL
    NSURL *outputURL = [NSURL fileURLWithPath:outputFilePath];
    
    exportSession.outputURL = outputURL;
    exportSession.outputFileType = AVFileTypeAppleM4A; // 使用M4A格式，支持更好的metadata
    
    // 🔧 检查输出文件类型是否支持
    NSArray *supportedTypes = exportSession.supportedFileTypes;
    if (![supportedTypes containsObject:AVFileTypeAppleM4A]) {
        NSLog(@"⚠️ [嵌入] M4A格式不支持，支持的格式: %@", supportedTypes);
        // 尝试使用第一个支持的格式
        if (supportedTypes.count > 0) {
            exportSession.outputFileType = supportedTypes.firstObject;
            NSLog(@"⚠️ [嵌入] 改用格式: %@", supportedTypes.firstObject);
        }
    }
    
    // 🎵 创建metadata数组
    NSMutableArray *metadata = [NSMutableArray array];
    
    // 封面图片
    AVMutableMetadataItem *artworkItem = [AVMutableMetadataItem metadataItem];
    artworkItem.keySpace = AVMetadataKeySpaceCommon;
    artworkItem.key = AVMetadataCommonKeyArtwork;
    artworkItem.value = artworkData;
    [metadata addObject:artworkItem];
    
    // 歌曲名
    if (songName && songName.length > 0) {
        AVMutableMetadataItem *titleItem = [AVMutableMetadataItem metadataItem];
        titleItem.keySpace = AVMetadataKeySpaceCommon;
        titleItem.key = AVMetadataCommonKeyTitle;
        titleItem.value = songName;
        [metadata addObject:titleItem];
    }
    
    // 艺术家
    if (artistName && artistName.length > 0) {
        AVMutableMetadataItem *artistItem = [AVMutableMetadataItem metadataItem];
        artistItem.keySpace = AVMetadataKeySpaceCommon;
        artistItem.key = AVMetadataCommonKeyArtist;
        artistItem.value = artistName;
        [metadata addObject:artistItem];
    }
    
    exportSession.metadata = metadata;
    
    NSLog(@"🔄 [嵌入] 开始导出（添加metadata）...");
    
    // 执行导出
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                NSLog(@"✅ [嵌入] 导出成功，M4A文件已创建");
                NSLog(@"✅ [嵌入] 封面和metadata已成功嵌入到音频文件: %@", [outputFilePath lastPathComponent]);
                
                // 验证文件是否存在
                if ([[NSFileManager defaultManager] fileExistsAtPath:outputFilePath]) {
                    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:outputFilePath error:nil];
                    NSLog(@"✅ [嵌入] 文件大小: %.2f MB", [attrs fileSize] / 1024.0 / 1024.0);
                    
                    // 🔍 验证封面是否真的嵌入成功
                    [self verifyEmbeddedArtwork:outputFilePath];
                    
                    completion(YES, outputFilePath);
                } else {
                    NSLog(@"❌ [嵌入] 警告：导出成功但文件不存在！");
                    completion(NO, nil);
                }
            } else {
                NSLog(@"❌ [嵌入] 导出失败");
                NSLog(@"   状态: %ld", (long)exportSession.status);
                if (exportSession.error) {
                    NSLog(@"   错误: %@", exportSession.error.localizedDescription);
                    NSLog(@"   详情: %@", exportSession.error);
                }
                
                // 清理输出文件（如果存在）
                [[NSFileManager defaultManager] removeItemAtPath:outputFilePath error:nil];
                completion(NO, nil);
            }
        });
    }];
}

/// 🔍 验证封面是否成功嵌入到音频文件
- (void)verifyEmbeddedArtwork:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    
    NSLog(@"🔍 [验证] 检查嵌入的metadata...");
    
    BOOL foundArtwork = NO;
    NSString *foundTitle = nil;
    NSString *foundArtist = nil;
    
    for (NSString *format in [asset availableMetadataFormats]) {
        NSLog(@"   格式: %@", format);
        
        for (AVMetadataItem *item in [asset metadataForFormat:format]) {
            if ([item.commonKey isEqualToString:@"artwork"]) {
                foundArtwork = YES;
                id value = [item.value copyWithZone:nil];
                if ([value isKindOfClass:[NSData class]]) {
                    NSData *data = (NSData *)value;
                    NSLog(@"   ✅ 封面: %.1f KB", data.length / 1024.0);
                }
            } else if ([item.commonKey isEqualToString:@"title"]) {
                id value = [item.value copyWithZone:nil];
                if ([value isKindOfClass:[NSString class]]) {
                    foundTitle = (NSString *)value;
                }
            } else if ([item.commonKey isEqualToString:@"artist"]) {
                id value = [item.value copyWithZone:nil];
                if ([value isKindOfClass:[NSString class]]) {
                    foundArtist = (NSString *)value;
                }
            }
        }
    }
    
    if (foundArtwork) {
        NSLog(@"✅ [验证] 封面已嵌入");
    } else {
        NSLog(@"⚠️ [验证] 未找到封面！");
    }
    
    if (foundTitle) {
        NSLog(@"   标题: %@", foundTitle);
    }
    if (foundArtist) {
        NSLog(@"   艺术家: %@", foundArtist);
    }
}

- (void)downloadCover:(NSString *)coverURL forFileName:(NSString *)musicFileName {
    if (!coverURL || coverURL.length == 0) return;
    
    NSURL *url = [NSURL URLWithString:coverURL];
    if (!url) return;
    
    NSLog(@"🖼️ [封面] 下载外部封面文件: %@", coverURL);
    
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"⚠️ [封面] 下载失败: %@", error.localizedDescription);
            return;
        }
        
        // 确定文件扩展名
        NSString *extension = @"jpg";
        if ([coverURL containsString:@".png"]) {
            extension = @"png";
        } else if ([coverURL containsString:@".webp"]) {
            extension = @"webp";
        }
        
        NSString *downloadDir = [MusicLibraryManager cloudDownloadDirectory];
        NSString *coverFileName = [[musicFileName stringByDeletingPathExtension] stringByAppendingPathExtension:extension];
        NSString *coverPath = [downloadDir stringByAppendingPathComponent:coverFileName];
        
        // 移动文件
        NSError *moveError = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:coverPath] error:&moveError];
        
        if (moveError) {
            NSLog(@"⚠️ [封面] 保存失败: %@", moveError.localizedDescription);
        } else {
            NSLog(@"✅ [外部封面] 保存成功: %@", coverFileName);
        }
    }];
    
    [task resume];
}

@end

