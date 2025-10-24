//
//  QQMusicAPIService.m
//  AudioSampleBuffer
//
//  QQ音乐API服务实现
//

#import "QQMusicAPIService.h"
#import "MusicLibraryManager.h"

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
            result.rid = item[@"rid"];
            result.name = item[@"name"];
            result.artist = item[@"artist"];
            result.pic = item[@"pic"];
            result.src = item[@"src"];
            result.downurl = item[@"downurl"];
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
        detail.rid = dataDict[@"rid"];
        detail.name = dataDict[@"name"];
        detail.artist = dataDict[@"artist"];
        detail.album = dataDict[@"album"];
        detail.quality = dataDict[@"quality"];
        detail.duration = dataDict[@"duration"];
        detail.size = dataDict[@"size"];
        detail.pic = dataDict[@"pic"];
        detail.url = dataDict[@"url"];
        detail.lrc = dataDict[@"lrc"];
        
        NSLog(@"✅ [详情] 获取成功: %@ - %@", detail.artist, detail.name);
        completion(detail, nil);
    }];
    
    [task resume];
}

- (void)downloadMusic:(QQMusicDetail *)detail
             progress:(void (^)(float, NSString *))progress
           completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    
    if (!detail.url || detail.url.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicAPIService"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"下载链接无效"}];
        completion(nil, error);
        return;
    }
    
    NSLog(@"⬇️ [下载] 开始: %@ - %@", detail.artist, detail.name);
    NSLog(@"⬇️ [下载] URL: %@", detail.url);
    
    // 创建下载目录
    NSString *downloadDir = [MusicLibraryManager cloudDownloadDirectory];
    
    // 生成文件名（艺术家 - 歌名.mp3）
    NSString *safeArtist = [self sanitizeFileName:detail.artist];
    NSString *safeName = [self sanitizeFileName:detail.name];
    NSString *fileName = [NSString stringWithFormat:@"%@ - %@.mp3", safeArtist, safeName];
    NSString *filePath = [downloadDir stringByAppendingPathComponent:fileName];
    
    // 检查文件是否已存在
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"⚠️ [下载] 文件已存在: %@", fileName);
        // 文件已存在，直接返回
        completion(filePath, nil);
        return;
    }
    
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
        
        // 移动文件到目标位置
        NSError *moveError = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:filePath] error:&moveError];
        if (moveError) {
            NSLog(@"❌ [下载] 移动文件失败: %@", moveError.localizedDescription);
            completion(nil, moveError);
            return;
        }
        
        NSLog(@"✅ [下载] 完成: %@", fileName);
        
        // 下载歌词（如果有）
        if (detail.lrc && detail.lrc.length > 0) {
            [self saveLyrics:detail.lrc forFileName:fileName];
        }
        
        // 下载封面（如果有）
        if (detail.pic && detail.pic.length > 0) {
            [self downloadCover:detail.pic forFileName:fileName];
        }
        
        completion(filePath, nil);
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

- (NSString *)sanitizeFileName:(NSString *)fileName {
    if (!fileName) return @"未知";
    
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

- (void)downloadCover:(NSString *)coverURL forFileName:(NSString *)musicFileName {
    if (!coverURL || coverURL.length == 0) return;
    
    NSURL *url = [NSURL URLWithString:coverURL];
    if (!url) return;
    
    NSLog(@"🖼️ [封面] 下载中: %@", coverURL);
    
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
            NSLog(@"✅ [封面] 保存成功: %@", coverFileName);
        }
    }];
    
    [task resume];
}

@end

