//
//  AppleMusicArtworkService.m
//  AudioSampleBuffer
//

#import "AppleMusicArtworkService.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <string.h>

static NSString * const kAppleMusicArtworkErrorDomain = @"AppleMusicArtworkService";
static NSTimeInterval const kNegativeCacheTTL = 6 * 60 * 60;
static NSInteger const kArtworkPixelSize = 1200;

@interface AppleMusicArtworkService ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *negativeCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *inflightCompletions;
@end

@implementation AppleMusicArtworkService

+ (instancetype)sharedService {
    static AppleMusicArtworkService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AppleMusicArtworkService alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _queue = dispatch_queue_create("com.mfj.AppleMusicArtworkService", DISPATCH_QUEUE_SERIAL);
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = 8;
        _negativeCache = [NSMutableDictionary dictionary];
        _inflightCompletions = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 15.0;
        config.timeoutIntervalForResource = 30.0;
        config.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Public

- (nullable UIImage *)cachedArtworkForFilePath:(nullable NSString *)filePath {
    if (filePath.length == 0) {
        return nil;
    }

    NSString *fileKey = [self fileCacheKey:filePath];
    UIImage *memory = [self.memoryCache objectForKey:fileKey];
    if (memory) {
        return memory;
    }

    NSString *diskPath = [self diskCachePathForKey:fileKey];
    UIImage *diskImage = [UIImage imageWithContentsOfFile:diskPath];
    if (diskImage) {
        [self.memoryCache setObject:diskImage forKey:fileKey];
        return diskImage;
    }

    return nil;
}

- (void)fetchArtworkWithTitle:(nullable NSString *)title
                       artist:(nullable NSString *)artist
                        album:(nullable NSString *)album
                     filePath:(nullable NSString *)filePath
                   completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error))completion {
    if (!completion) {
        return;
    }

    UIImage *cached = [self cachedArtworkForFilePath:filePath];
    if (cached) {
        completion(cached, nil);
        return;
    }

    dispatch_async(self.queue, ^{
        NSString *resolvedTitle = [self trimmed:title];
        NSString *resolvedArtist = [self trimmed:artist];
        NSString *resolvedAlbum = [self trimmed:album];
        [self enrichMetadataFromFilePath:filePath
                                   title:&resolvedTitle
                                  artist:&resolvedArtist
                                   album:&resolvedAlbum];

        if (![self isUsableQueryTitle:resolvedTitle]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [self errorWithCode:-1 message:@"缺少可用于搜索的歌名"]);
            });
            return;
        }

        NSString *searchKey = [self searchCacheKeyWithTitle:resolvedTitle artist:resolvedArtist album:resolvedAlbum];
        UIImage *searchCached = [self.memoryCache objectForKey:searchKey];
        if (!searchCached) {
            searchCached = [UIImage imageWithContentsOfFile:[self diskCachePathForKey:searchKey]];
            if (searchCached) {
                [self.memoryCache setObject:searchCached forKey:searchKey];
            }
        }
        if (searchCached) {
            [self persistImage:searchCached filePath:filePath searchKey:searchKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(searchCached, nil);
            });
            return;
        }

        NSNumber *failedAt = self.negativeCache[searchKey];
        if (failedAt && ([[NSDate date] timeIntervalSince1970] - failedAt.doubleValue) < kNegativeCacheTTL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [self errorWithCode:-2 message:@"近期已搜索过且未命中"]);
            });
            return;
        }

        NSMutableArray *waiters = self.inflightCompletions[searchKey];
        if (waiters) {
            [waiters addObject:[completion copy]];
            return;
        }

        self.inflightCompletions[searchKey] = [NSMutableArray arrayWithObject:[completion copy]];
        NSLog(@"🍎 [Apple Music] 搜索封面: title=%@ artist=%@ album=%@", resolvedTitle, resolvedArtist ?: @"", resolvedAlbum ?: @"");
        [self searchCatalogWithTitle:resolvedTitle
                              artist:resolvedArtist
                               album:resolvedAlbum
                          completion:^(UIImage *image, NSError *error) {
            dispatch_async(self.queue, ^{
                NSArray *callbacks = [self.inflightCompletions[searchKey] copy];
                [self.inflightCompletions removeObjectForKey:searchKey];

                if (image) {
                    [self persistImage:image filePath:filePath searchKey:searchKey];
                    [self.negativeCache removeObjectForKey:searchKey];
                } else {
                    self.negativeCache[searchKey] = @([[NSDate date] timeIntervalSince1970]);
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    for (void (^callback)(UIImage *, NSError *) in callbacks) {
                        callback(image, error);
                    }
                });
            });
        }];
    });
}

#pragma mark - Catalog search

- (void)searchCatalogWithTitle:(NSString *)title
                        artist:(nullable NSString *)artist
                         album:(nullable NSString *)album
                    completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error))completion {
    NSArray<NSString *> *storefronts = [self storefrontsForTitle:title artist:artist];
    [self searchStorefronts:storefronts
                      index:0
                      title:title
                     artist:artist
                      album:album
                 completion:completion];
}

- (void)searchStorefronts:(NSArray<NSString *> *)storefronts
                    index:(NSUInteger)index
                    title:(NSString *)title
                   artist:(nullable NSString *)artist
                    album:(nullable NSString *)album
               completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error))completion {
    if (index >= storefronts.count) {
        completion(nil, [self errorWithCode:-3 message:@"Apple Music 未找到匹配封面"]);
        return;
    }

    NSString *country = storefronts[index];
    NSString *term = [self searchTermWithTitle:title artist:artist album:album];
    [self performSearchWithTerm:term country:country entity:@"song" completion:^(NSArray<NSDictionary *> *songs, NSError *error) {
        NSDictionary *best = [self bestMatchInResults:songs title:title artist:artist album:album];
        if (!best) {
            [self performSearchWithTerm:term country:country entity:@"album" completion:^(NSArray<NSDictionary *> *albums, NSError *albumError) {
                NSDictionary *albumMatch = [self bestAlbumMatchInResults:albums title:title artist:artist album:album];
                NSString *artworkURL = [self highResArtworkURLFromResult:albumMatch];
                if (artworkURL.length > 0) {
                    [self downloadArtworkAtURL:artworkURL completion:completion];
                    return;
                }

                [self searchStorefronts:storefronts
                                  index:index + 1
                                  title:title
                                 artist:artist
                                  album:album
                             completion:completion];
                (void)error;
                (void)albumError;
            }];
            return;
        }

        NSString *artworkURL = [self highResArtworkURLFromResult:best];
        if (artworkURL.length == 0) {
            [self searchStorefronts:storefronts
                              index:index + 1
                              title:title
                             artist:artist
                              album:album
                         completion:completion];
            return;
        }

        NSLog(@"🍎 [Apple Music] 命中: %@ - %@ (%@)", best[@"trackName"], best[@"artistName"], country);
        [self downloadArtworkAtURL:artworkURL completion:completion];
    }];
}

- (void)performSearchWithTerm:(NSString *)term
                      country:(NSString *)country
                       entity:(NSString *)entity
                   completion:(void(^)(NSArray<NSDictionary *> *results, NSError * _Nullable error))completion {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"term" value:term],
        [NSURLQueryItem queryItemWithName:@"entity" value:entity],
        [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"8"],
        [NSURLQueryItem queryItemWithName:@"country" value:country],
        [NSURLQueryItem queryItemWithName:@"lang" value:@"zh_cn"]
    ];

    NSURL *url = components.URL;
    if (!url) {
        completion(@[], [self errorWithCode:-4 message:@"无法构建搜索 URL"]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"AudioSampleBuffer/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            completion(@[], error);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *results = [json[@"results"] isKindOfClass:[NSArray class]] ? json[@"results"] : @[];
        NSMutableArray<NSDictionary *> *dicts = [NSMutableArray array];
        for (id item in results) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                [dicts addObject:item];
            }
        }
        completion(dicts, nil);
    }];
    [task resume];
}

#pragma mark - Matching

- (NSDictionary *)bestMatchInResults:(NSArray<NSDictionary *> *)results
                               title:(NSString *)title
                              artist:(nullable NSString *)artist
                               album:(nullable NSString *)album {
    NSDictionary *best = nil;
    CGFloat bestScore = 0;
    for (NSDictionary *item in results) {
        CGFloat score = [self scoreResult:item title:title artist:artist album:album];
        if (score > bestScore) {
            bestScore = score;
            best = item;
        }
    }
    return bestScore >= 55.0 ? best : nil;
}

- (NSDictionary *)bestAlbumMatchInResults:(NSArray<NSDictionary *> *)results
                                    title:(NSString *)title
                                   artist:(nullable NSString *)artist
                                    album:(nullable NSString *)album {
    NSDictionary *best = nil;
    CGFloat bestScore = 0;
    for (NSDictionary *item in results) {
        CGFloat score = 0;
        score += [self similarity:[self normalized:item[@"collectionName"]] with:[self normalized:album.length ? album : title]] * 70.0;
        if (artist.length > 0) {
            score += [self similarity:[self normalized:item[@"artistName"]] with:[self normalized:artist]] * 30.0;
        }
        if (score > bestScore) {
            bestScore = score;
            best = item;
        }
    }
    return bestScore >= 50.0 ? best : nil;
}

- (CGFloat)scoreResult:(NSDictionary *)item
                 title:(NSString *)title
                artist:(nullable NSString *)artist
                 album:(nullable NSString *)album {
    NSString *track = [self normalized:item[@"trackName"]];
    NSString *wantTitle = [self normalized:title];
    CGFloat score = [self similarity:track with:wantTitle] * 70.0;

    if (artist.length > 0) {
        score += [self similarity:[self normalized:item[@"artistName"]] with:[self normalized:artist]] * 25.0;
    }
    if (album.length > 0) {
        score += [self similarity:[self normalized:item[@"collectionName"]] with:[self normalized:album]] * 10.0;
    }
    return score;
}

- (CGFloat)similarity:(NSString *)a with:(NSString *)b {
    if (a.length == 0 || b.length == 0) {
        return 0;
    }
    if ([a isEqualToString:b]) {
        return 1.0;
    }
    if ([a containsString:b] || [b containsString:a]) {
        NSUInteger shorter = MIN(a.length, b.length);
        NSUInteger longer = MAX(a.length, b.length);
        return longer > 0 ? (CGFloat)shorter / (CGFloat)longer : 0;
    }
    return 0;
}

#pragma mark - Artwork download

- (NSString *)highResArtworkURLFromResult:(NSDictionary *)result {
    NSString *url = result[@"artworkUrl100"];
    if (![url isKindOfClass:[NSString class]] || url.length == 0) {
        url = result[@"artworkUrl60"];
    }
    if (url.length == 0) {
        return nil;
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+x\\d+[a-z]*"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    NSString *replacement = [NSString stringWithFormat:@"%ldx%ldbb", (long)kArtworkPixelSize, (long)kArtworkPixelSize];
    return [regex stringByReplacingMatchesInString:url
                                           options:0
                                             range:NSMakeRange(0, url.length)
                                      withTemplate:replacement];
}

- (void)downloadArtworkAtURL:(NSString *)urlString
                  completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil, [self errorWithCode:-5 message:@"封面 URL 无效"]);
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = http.statusCode;
        UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
        if (error || !image || status >= 400) {
            if ([urlString containsString:@"1200x1200"]) {
                NSString *fallback = [urlString stringByReplacingOccurrencesOfString:@"1200x1200bb" withString:@"600x600bb"];
                if (![fallback isEqualToString:urlString]) {
                    NSLog(@"🍎 [Apple Music] 高清封面失败，回退 600px");
                    [self downloadArtworkAtURL:fallback completion:completion];
                    return;
                }
            }
            completion(nil, error ?: [self errorWithCode:-6 message:@"封面下载失败"]);
            return;
        }

        NSLog(@"🍎 [Apple Music] 封面下载成功 (%.0fx%.0f, %.1f KB)",
              image.size.width, image.size.height, data.length / 1024.0);
        completion(image, nil);
    }];
    [task resume];
}

#pragma mark - Persistence

- (void)persistImage:(UIImage *)image filePath:(NSString *)filePath searchKey:(NSString *)searchKey {
    if (!image) {
        return;
    }

    [self.memoryCache setObject:image forKey:searchKey];
    if (filePath.length > 0) {
        [self.memoryCache setObject:image forKey:[self fileCacheKey:filePath]];
    }

    NSData *jpeg = UIImageJPEGRepresentation(image, 0.9);
    if (jpeg.length == 0) {
        return;
    }

    NSString *searchPath = [self diskCachePathForKey:searchKey];
    [jpeg writeToFile:searchPath atomically:YES];

    if (filePath.length > 0) {
        NSString *fileCachePath = [self diskCachePathForKey:[self fileCacheKey:filePath]];
        [jpeg writeToFile:fileCachePath atomically:YES];
        [self writeSidecarCover:jpeg nextToFilePath:filePath];
    }
}

- (void)writeSidecarCover:(NSData *)jpeg nextToFilePath:(NSString *)filePath {
    if (filePath.length == 0 || ![filePath hasPrefix:@"/"]) {
        return;
    }

    NSString *directory = [filePath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] isWritableFileAtPath:directory]) {
        return;
    }

    NSString *baseName = [[filePath lastPathComponent] stringByDeletingPathExtension];
    NSString *coverPath = [[directory stringByAppendingPathComponent:[baseName stringByAppendingString:@"_cover"]] stringByAppendingPathExtension:@"jpg"];
    NSError *error = nil;
    [jpeg writeToFile:coverPath options:NSDataWritingAtomic error:&error];
    if (error) {
        NSLog(@"⚠️ [Apple Music] 写入外部封面失败: %@", error.localizedDescription);
    } else {
        NSLog(@"✅ [Apple Music] 已保存外部封面: %@", coverPath.lastPathComponent);
    }
}

- (NSString *)diskCacheDirectory {
    static NSString *directory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        directory = [caches stringByAppendingPathComponent:@"AppleMusicArtwork"];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    });
    return directory;
}

- (NSString *)diskCachePathForKey:(NSString *)key {
    return [[self diskCacheDirectory] stringByAppendingPathComponent:[[self sha256:key] stringByAppendingPathExtension:@"jpg"]];
}

#pragma mark - Metadata helpers

- (void)enrichMetadataFromFilePath:(NSString *)filePath
                             title:(NSString **)title
                            artist:(NSString **)artist
                             album:(NSString **)album {
    if (filePath.length == 0 || ![filePath hasPrefix:@"/"]) {
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:filePath] options:nil];
    for (AVMetadataItem *item in asset.commonMetadata) {
        NSString *key = item.commonKey;
        NSString *value = nil;
        if ([item.value isKindOfClass:[NSString class]]) {
            value = [self trimmed:(NSString *)item.value];
        } else {
            value = [self trimmed:item.stringValue];
        }
        if (value.length == 0) {
            continue;
        }

        if ([key isEqualToString:AVMetadataCommonKeyTitle] && (*title).length == 0) {
            *title = value;
        } else if ([key isEqualToString:AVMetadataCommonKeyArtist] && (*artist).length == 0) {
            *artist = value;
        } else if ([key isEqualToString:AVMetadataCommonKeyAlbumName] && (*album).length == 0) {
            *album = value;
        }
    }
}

- (NSArray<NSString *> *)storefrontsForTitle:(NSString *)title artist:(nullable NSString *)artist {
    NSString *probe = [NSString stringWithFormat:@"%@%@", title ?: @"", artist ?: @""];
    BOOL hasCJK = [probe rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0x4E00, 0x9FFF)]].location != NSNotFound;
    BOOL hasKana = [probe rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0x3040, 0xC0)]].location != NSNotFound;
    BOOL hasHangul = [probe rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0xAC00, 0xD7AF - 0xAC00 + 1)]].location != NSNotFound;

    if (hasHangul) {
        return @[@"kr", @"us", @"cn"];
    }
    if (hasKana) {
        return @[@"jp", @"us", @"cn"];
    }
    if (hasCJK) {
        return @[@"cn", @"hk", @"tw", @"us"];
    }
    return @[@"us", @"cn", @"jp"];
}

- (NSString *)searchTermWithTitle:(NSString *)title artist:(nullable NSString *)artist album:(nullable NSString *)album {
    NSMutableArray *parts = [NSMutableArray array];
    if (artist.length > 0) {
        [parts addObject:artist];
    }
    [parts addObject:title];
    if (album.length > 0 && parts.count < 3) {
        [parts addObject:album];
    }
    return [parts componentsJoinedByString:@" "];
}

- (BOOL)isUsableQueryTitle:(NSString *)title {
    NSString *normalized = [self normalized:title];
    if (normalized.length < 2) {
        return NO;
    }
    NSArray *ignored = @[@"unknown", @"untitled", @"track", @"未知", @"未知歌曲", @"无标题"];
    return ![ignored containsObject:normalized];
}

- (NSString *)searchCacheKeyWithTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album {
    return [NSString stringWithFormat:@"%@|%@|%@",
            [self normalized:artist] ?: @"",
            [self normalized:title] ?: @"",
            [self normalized:album] ?: @""];
}

- (NSString *)fileCacheKey:(NSString *)filePath {
    return [@"file:" stringByAppendingString:filePath ?: @""];
}

- (NSString *)trimmed:(NSString *)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

- (NSString *)normalized:(NSString *)value {
    NSString *trimmed = [self trimmed:value];
    if (!trimmed) {
        return @"";
    }

    NSString *lower = trimmed.lowercaseString;
    NSMutableString *folded = [lower mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)folded, NULL, kCFStringTransformFullwidthHalfwidth, false);

    NSRegularExpression *feat = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(\\[]?(feat\\.?|ft\\.)\\s+.*$"
                                                                          options:NSRegularExpressionCaseInsensitive
                                                                            error:nil];
    folded = [[feat stringByReplacingMatchesInString:folded options:0 range:NSMakeRange(0, folded.length) withTemplate:@""] mutableCopy];

    NSCharacterSet *keep = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *compact = [NSMutableString string];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar c = [folded characterAtIndex:i];
        if ([keep characterIsMember:c] || c > 0x7F) {
            [compact appendFormat:@"%C", c];
        }
    }
    return compact;
}

- (NSString *)sha256:(NSString *)string {
    const char *cStr = string.UTF8String ?: "";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:kAppleMusicArtworkErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

@end
