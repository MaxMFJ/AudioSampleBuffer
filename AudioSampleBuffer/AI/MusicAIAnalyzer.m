//
//  MusicAIAnalyzer.m
//  AudioSampleBuffer
//

#import "MusicAIAnalyzer.h"
#import "LLMAPISettings.h"
#import <CommonCrypto/CommonDigest.h>

// 缓存配置
static NSString *const kCacheDirectory = @"MusicAICache";
static NSTimeInterval const kCacheExpiration = 30 * 24 * 60 * 60; // 30 天

// 通知
NSString *const kAIConfigurationDidChangeNotification = @"AIConfigurationDidChangeNotification";
NSString *const kAIConfigurationKey = @"configuration";

@interface MusicAIAnalyzer ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, strong) AIColorConfiguration *currentConfiguration;
@property (nonatomic, assign) BOOL isAnalyzing;
@end

@implementation MusicAIAnalyzer

+ (instancetype)sharedAnalyzer {
    static MusicAIAnalyzer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MusicAIAnalyzer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;
        config.timeoutIntervalForResource = 60.0;
        _session = [NSURLSession sessionWithConfiguration:config];
        
        // 设置缓存目录
        NSString *cacheRoot = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        _cacheDirectory = [cacheRoot stringByAppendingPathComponent:kCacheDirectory];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        
        // 加载默认配置
        _currentConfiguration = [AIColorConfiguration defaultConfiguration];
        
        NSLog(@"🎨 MusicAIAnalyzer 初始化完成");
    }
    return self;
}

#pragma mark - Public Methods

- (void)analyzeSong:(NSString *)songName
             artist:(NSString *)artist
         completion:(AIAnalysisCompletion)completion {
    
    if (!songName || songName.length == 0) {
        NSError *error = [NSError errorWithDomain:@"MusicAIAnalyzer"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"歌曲名不能为空"}];
        completion(nil, error);
        return;
    }
    
    // 检查缓存
    AIColorConfiguration *cached = [self getCachedConfigurationForSong:songName artist:artist];
    if (cached) {
        // 旧缓存中可能是网络失败后的降级配置，允许重新请求 LLM 避免长期卡死在默认配色
        if (!cached.isLLMGenerated) {
            NSLog(@"♻️ 检测到降级缓存，清除并重新请求 AI 服务: %@ - %@", songName, artist ?: @"Unknown");
            [self clearCacheForSong:songName artist:artist];
        } else {
            NSLog(@"✅ 使用缓存配置: %@ - %@", songName, artist);
            NSLog(@"🎨 缓存颜色: laserFanBlue=(%.2f, %.2f, %.2f), topLightArray=(%.2f, %.2f, %.2f)",
                  cached.laserFanBlueColor.x, cached.laserFanBlueColor.y, cached.laserFanBlueColor.z,
                  cached.topLightArrayColor.x, cached.topLightArrayColor.y, cached.topLightArrayColor.z);
            self.currentConfiguration = cached;
            [self applyConfiguration:cached];
            completion(cached, nil);
            return;
        }
    }
    
    // 调用 API 分析
    [self forceAnalyzeSong:songName artist:artist completion:completion];
}

- (void)forceAnalyzeSong:(NSString *)songName
                  artist:(NSString *)artist
              completion:(AIAnalysisCompletion)completion {
    
    if (self.isAnalyzing) {
        NSLog(@"⏳ 正在分析中，跳过本次请求");
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MusicAIAnalyzer"
                                                 code:-2
                                             userInfo:@{NSLocalizedDescriptionKey: @"另一个分析正在进行中"}];
            completion(nil, error);
        }
        return;
    }
    
    self.isAnalyzing = YES;
    NSLog(@"🔍 开始 AI 分析: %@ - %@", songName, artist ?: @"Unknown");
    
    // 构建 prompt
    NSString *prompt = [self buildPromptForSong:songName artist:artist];
    
    // 调用已配置的 LLM API
    [self callDeepSeekAPI:prompt completion:^(NSDictionary *response, NSError *error) {
        self.isAnalyzing = NO;
        
        if (error) {
            NSLog(@"❌ AI 分析失败: %@", error.localizedDescription);
            // 降级：根据歌曲名简单判断情感
            AIColorConfiguration *fallback = [self generateFallbackConfiguration:songName artist:artist];
            NSLog(@"🎨 降级颜色: laserFanBlue=(%.2f, %.2f, %.2f), topLightArray=(%.2f, %.2f, %.2f)",
                  fallback.laserFanBlueColor.x, fallback.laserFanBlueColor.y, fallback.laserFanBlueColor.z,
                  fallback.topLightArrayColor.x, fallback.topLightArrayColor.y, fallback.topLightArrayColor.z);
            self.currentConfiguration = fallback;
            [self applyConfiguration:fallback];
            completion(fallback, nil);
            return;
        }
        
        // 解析响应
        AIColorConfiguration *config = [self parseAPIResponse:response songName:songName artist:artist];
        if (config) {
            NSLog(@"✅ AI 分析成功: BPM=%ld, 情感=%@", (long)config.bpm, [self emotionToString:config.emotion]);
            config.isLLMGenerated = YES;
            [self cacheConfiguration:config forSong:songName artist:artist];
            self.currentConfiguration = config;
            [self applyConfiguration:config];
            completion(config, nil);
        } else {
            NSLog(@"⚠️ 解析响应失败，使用降级配置");
            AIColorConfiguration *fallback = [self generateFallbackConfiguration:songName artist:artist];
            self.currentConfiguration = fallback;
            [self applyConfiguration:fallback];
            completion(fallback, nil);
        }
    }];
}

- (nullable AIColorConfiguration *)getCachedConfigurationForSong:(NSString *)songName
                                                          artist:(NSString *)artist {
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    NSString *cachePath = [self.cacheDirectory stringByAppendingPathComponent:cacheKey];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        return nil;
    }
    
    // 检查缓存是否过期
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:cachePath error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    if ([[NSDate date] timeIntervalSinceDate:modificationDate] > kCacheExpiration) {
        NSLog(@"🗑️ 缓存已过期: %@", songName);
        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
        return nil;
    }
    
    // 读取缓存
    @try {
        NSData *data = [NSData dataWithContentsOfFile:cachePath];
        AIColorConfiguration *config = [NSKeyedUnarchiver unarchivedObjectOfClass:[AIColorConfiguration class]
                                                                          fromData:data
                                                                             error:nil];
        return config;
    } @catch (NSException *exception) {
        NSLog(@"❌ 读取缓存失败: %@", exception);
        return nil;
    }
}

- (void)clearCache {
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:self.cacheDirectory error:&error];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.cacheDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSLog(@"🗑️ 已清除所有 AI 缓存");
}

- (void)clearCacheForSong:(NSString *)songName artist:(NSString *)artist {
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    NSString *cachePath = [self.cacheDirectory stringByAppendingPathComponent:cacheKey];
    [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
    NSLog(@"🗑️ 已清除缓存: %@ - %@", songName, artist);
}

- (void)applyConfiguration:(AIColorConfiguration *)configuration {
    [[NSNotificationCenter defaultCenter] postNotificationName:kAIConfigurationDidChangeNotification
                                                        object:self
                                                      userInfo:@{kAIConfigurationKey: configuration}];
}

#pragma mark - Private Methods

- (NSString *)buildPromptForSong:(NSString *)songName artist:(NSString *)artist {
    NSString *artistInfo = artist && artist.length > 0 ? [NSString stringWithFormat:@" by %@", artist] : @"";
    
    return [NSString stringWithFormat:
        @"请分析歌曲《%@》%@，返回严格的 JSON 格式（不要包含任何其他文字）：\n"
        @"{\n"
        @"  \"analysis\": {\n"
        @"    \"bpm\": <数字>,\n"
        @"    \"emotion\": \"<calm/sad/happy/energetic/intense>\",\n"
        @"    \"energy\": <0-1 浮点数>,\n"
        @"    \"danceability\": <0-1 浮点数>,\n"
        @"    \"valence\": <0-1 浮点数>\n"
        @"  },\n"
        @"  \"colors\": {\n"
        @"    \"atmosphere\": [R, G, B],\n"
        @"    \"volumetricBeam\": [R, G, B],\n"
        @"    \"topLightArray\": [R, G, B],\n"
        @"    \"laserFanBlue\": [R, G, B],\n"
        @"    \"laserFanGreen\": [R, G, B],\n"
        @"    \"rotatingBeam\": [R, G, B],\n"
        @"    \"rotatingBeamExtra\": [R, G, B],\n"
        @"    \"edgeLight\": [R, G, B],\n"
        @"    \"coronaFilaments\": [R, G, B],\n"
        @"    \"pulseRing\": [R, G, B]\n"
        @"  },\n"
        @"  \"parameters\": {\n"
        @"    \"animationSpeed\": <0.5-2.0>,\n"
        @"    \"brightnessMultiplier\": <0.5-1.5>,\n"
        @"    \"triggerSensitivity\": <0.5-1.5>,\n"
        @"    \"atmosphereIntensity\": <0.2-0.8>\n"
        @"  }\n"
        @"}\n\n"
        @"说明：\n"
        @"1. 根据歌曲的情感、节奏、风格推荐舞台灯光颜色和参数\n"
        @"2. RGB 值为 0-1 浮点数\n"
        @"3. emotion: calm(平静), sad(悲伤), happy(快乐), energetic(充满活力), intense(强烈)\n"
        @"4. energy: 歌曲能量，0=低能量，1=高能量\n"
        @"5. danceability: 适合跳舞程度，0=不适合，1=非常适合\n"
        @"6. valence: 情绪正负值，0=消极，1=积极\n"
        @"7. 颜色应该与歌曲情感匹配（例如：悲伤用冷色调蓝紫，快乐用暖色调黄橙）\n"
        @"8. 颜色说明：\n"
        @"   - atmosphere: 背景烟雾氛围底色\n"
        @"   - volumetricBeam: 左右两侧体积光/大灯颜色\n"
        @"   - topLightArray: 顶部灯光阵列颜色\n"
        @"   - laserFanBlue: 主激光扇形颜色（应与 topLightArray 有明显区别，可以是互补色或完全不同色系）\n"
        @"   - laserFanGreen: 副激光颜色（应与 laserFanBlue 形成对比）\n"
        @"   - rotatingBeam: 中心旋转光束主色\n"
        @"   - rotatingBeamExtra: 中心旋转光束副色/细丝\n"
        @"   - edgeLight: 底部边缘描绘光颜色\n"
        @"   - coronaFilaments: 外围长丝/日冕丝颜色\n"
        @"   - pulseRing: 脉冲环扩散颜色\n"
        @"9. 重要：每首歌的颜色应该有显著差异 建议：\n"
        @"   - 流行歌：蓝、青、紫为主\n"
        @"   - 摇滚/电子：红、橙、品红为主\n"
        @"   - 抒情/慢歌：紫、靛、深蓝为主\n"
        @"   - 欢快/舞曲：黄、橙、粉、青为主\n"
        @"   - laserFanBlue 可以是红色、橙色、品红、青色等任何与歌曲匹配的颜色",
        songName, artistInfo
    ];
}

- (void)callDeepSeekAPI:(NSString *)prompt completion:(void(^)(NSDictionary *response, NSError *error))completion {
    LLMAPISettings *settings = [LLMAPISettings sharedSettings];
    if (settings.apiKey.length == 0) {
        NSError *configError = [NSError errorWithDomain:@"LLMConfiguration"
                                                   code:-1001
                                               userInfo:@{NSLocalizedDescriptionKey: @"请先在 AI 设置中填写 API Key"}];
        completion(nil, configError);
        return;
    }
    
    NSURL *url = settings.serviceURL;
    if (!url) {
        NSError *configError = [NSError errorWithDomain:@"LLMConfiguration"
                                                   code:-1002
                                               userInfo:@{NSLocalizedDescriptionKey: @"AI 设置中的 Base URL 无效，请重新填写"}];
        completion(nil, configError);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", settings.apiKey] forHTTPHeaderField:@"Authorization"];
    
    NSDictionary *payload = @{
        @"model": settings.model,
        @"messages": @[
            @{
                @"role": @"system",
                @"content": @"你是一个音乐分析专家，擅长根据歌曲情感和风格推荐视觉效果配置。颜色需要丰富多样，每首歌应该有显著不同的色彩方案。laserFanBlue 这个字段名只是代号，实际颜色可以是红色、橙色、紫色等任何符合歌曲气质的颜色。只返回 JSON，不要包含任何其他文字。"
            },
            @{
                @"role": @"user",
                @"content": prompt
            }
        ],
        @"temperature": @0.7,
        @"max_tokens": @1000
    };
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError) {
        completion(nil, jsonError);
        return;
    }
    
    request.HTTPBody = jsonData;
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSString *errorMsg = [NSString stringWithFormat:@"API 返回错误: %ld", (long)httpResponse.statusCode];
            NSError *apiError = [NSError errorWithDomain:@"LLMAPI"
                                                    code:httpResponse.statusCode
                                                userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, apiError);
            });
            return;
        }
        
        NSError *parseError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, parseError);
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(json, nil);
        });
    }];
    
    [task resume];
}

- (nullable AIColorConfiguration *)parseAPIResponse:(NSDictionary *)response
                                           songName:(NSString *)songName
                                             artist:(NSString *)artist {
    // DeepSeek API 响应格式
    NSArray *choices = response[@"choices"];
    if (!choices || choices.count == 0) {
        return nil;
    }
    
    NSDictionary *choice = choices[0];
    NSDictionary *message = choice[@"message"];
    NSString *content = message[@"content"];
    
    if (!content || content.length == 0) {
        return nil;
    }
    
    // 提取 JSON（可能包含在 ```json ... ``` 中）
    NSString *jsonString = [self extractJSONFromContent:content];
    if (!jsonString) {
        return nil;
    }
    
    // 解析 JSON
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (error || !json) {
        NSLog(@"❌ JSON 解析失败: %@", error);
        return nil;
    }
    
    // 创建配置
    NSMutableDictionary *configJSON = [json mutableCopy];
    configJSON[@"songName"] = songName;
    configJSON[@"artist"] = artist ?: @"";
    configJSON[@"songIdentifier"] = [self cacheKeyForSong:songName artist:artist];
    
    return [AIColorConfiguration configurationFromJSON:configJSON];
}

- (NSString *)extractJSONFromContent:(NSString *)content {
    // 尝试提取 ```json ... ``` 包裹的 JSON
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"```json\\s*([\\s\\S]*?)```"
                                                                           options:0
                                                                             error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
    
    if (match && match.numberOfRanges > 1) {
        return [content substringWithRange:[match rangeAtIndex:1]];
    }
    
    // 尝试提取 { ... }
    NSRange startRange = [content rangeOfString:@"{"];
    NSRange endRange = [content rangeOfString:@"}" options:NSBackwardsSearch];
    
    if (startRange.location != NSNotFound && endRange.location != NSNotFound && endRange.location > startRange.location) {
        return [content substringWithRange:NSMakeRange(startRange.location, endRange.location - startRange.location + 1)];
    }
    
    return content;
}

- (AIColorConfiguration *)generateFallbackConfiguration:(NSString *)songName artist:(NSString *)artist {
    // 简单的关键词匹配生成降级配置
    NSString *lowerName = [songName lowercaseString];
    
    MusicEmotion emotion = MusicEmotionEnergetic; // 默认
    
    if ([lowerName containsString:@"sad"] || [lowerName containsString:@"悲"] ||
        [lowerName containsString:@"cry"] || [lowerName containsString:@"tears"]) {
        emotion = MusicEmotionSad;
    } else if ([lowerName containsString:@"happy"] || [lowerName containsString:@"joy"] ||
               [lowerName containsString:@"乐"] || [lowerName containsString:@"笑"]) {
        emotion = MusicEmotionHappy;
    } else if ([lowerName containsString:@"calm"] || [lowerName containsString:@"quiet"] ||
               [lowerName containsString:@"peace"] || [lowerName containsString:@"静"]) {
        emotion = MusicEmotionCalm;
    } else if ([lowerName containsString:@"rock"] || [lowerName containsString:@"metal"] ||
               [lowerName containsString:@"摇滚"] || [lowerName containsString:@"燃"]) {
        emotion = MusicEmotionIntense;
    }
    
    AIColorConfiguration *config = [AIColorConfiguration configurationForEmotion:emotion];
    config.isLLMGenerated = NO;
    config.songName = songName;
    config.artist = artist ?: @"";
    config.songIdentifier = [self cacheKeyForSong:songName artist:artist];
    
    NSLog(@"🔄 使用降级配置: 情感=%@", [self emotionToString:emotion]);
    
    return config;
}

#pragma mark - Cache Helpers

- (NSString *)cacheKeyForSong:(NSString *)songName artist:(NSString *)artist {
    NSString *combined = [NSString stringWithFormat:@"%@_%@", songName, artist ?: @""];
    return [self md5Hash:combined];
}

- (NSString *)md5Hash:(NSString *)string {
    const char *cStr = [string UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

- (void)cacheConfiguration:(AIColorConfiguration *)configuration
                   forSong:(NSString *)songName
                    artist:(NSString *)artist {
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    NSString *cachePath = [self.cacheDirectory stringByAppendingPathComponent:cacheKey];
    
    @try {
        NSError *error;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:configuration
                                             requiringSecureCoding:YES
                                                             error:&error];
        if (error) {
            NSLog(@"❌ 缓存序列化失败: %@", error);
            return;
        }
        
        [data writeToFile:cachePath atomically:YES];
        NSLog(@"💾 已缓存配置: %@ - %@", songName, artist);
    } @catch (NSException *exception) {
        NSLog(@"❌ 缓存写入失败: %@", exception);
    }
}

- (NSString *)emotionToString:(MusicEmotion)emotion {
    switch (emotion) {
        case MusicEmotionCalm: return @"平静";
        case MusicEmotionSad: return @"悲伤";
        case MusicEmotionHappy: return @"快乐";
        case MusicEmotionEnergetic: return @"活力";
        case MusicEmotionIntense: return @"强烈";
    }
}

@end
