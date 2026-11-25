//
//  QQMusicLyricsAPI.m
//  AudioSampleBuffer
//
//  QQ音乐歌词API - 实现
//

#import "QQMusicLyricsAPI.h"
#import <AVFoundation/AVFoundation.h>

@implementation QQMusicLyrics
@end

@implementation QQMusicLyricsAPI

#pragma mark - Public API Methods

+ (void)fetchLyricsWithSongMid:(NSString *)songMid
                    completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion {
    if (!songMid || songMid.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"songMid 不能为空"}];
        if (completion) completion(nil, error);
        return;
    }
    
    // QQ音乐歌词API接口（注意：返回的歌词是Base64编码的）
    NSString *urlString = [NSString stringWithFormat:
        @"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=%@&format=json",
        songMid];
    
    [self performLyricsRequest:urlString completion:completion];
}

+ (void)fetchLyricsWithSongId:(NSString *)songId
                   completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion {
    if (!songId || songId.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"songId 不能为空"}];
        if (completion) completion(nil, error);
        return;
    }
    
    // 备用接口：使用 songid（注意：返回的歌词是Base64编码的）
    NSString *urlString = [NSString stringWithFormat:
        @"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric.fcg?songid=%@&format=json",
        songId];
    
    [self performLyricsRequest:urlString completion:completion];
}

+ (void)searchAndFetchLyricsWithSongName:(NSString *)songName
                              artistName:(nullable NSString *)artistName
                              completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion {
    if (!songName || songName.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"歌曲名不能为空"}];
        if (completion) completion(nil, error);
        return;
    }
    
    // 构建搜索关键词
    NSString *keyword = artistName ? [NSString stringWithFormat:@"%@ %@", artistName, songName] : songName;
    NSString *encodedKeyword = [keyword stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // QQ音乐搜索API
    NSString *searchURL = [NSString stringWithFormat:
        @"https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=20&w=%@&format=json",
        encodedKeyword];
    
    NSURL *url = [NSURL URLWithString:searchURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://y.qq.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request 
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"❌ [QQ音乐] 搜索失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            // 解析搜索结果
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *songs = json[@"data"][@"song"][@"list"];
            
            if (!songs || songs.count == 0) {
                NSError *notFoundError = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                                             code:-404 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"未找到匹配的歌曲"}];
                NSLog(@"❌ [QQ音乐] 未找到歌曲: %@", keyword);
                if (completion) completion(nil, notFoundError);
                return;
            }
            
            // 长歌手串会把同组的另一首歌排到第一位。只接受歌名完全一致的结果。
            NSDictionary *firstSong = [self bestMatchInSongs:songs songName:songName artistName:artistName];
            if (!firstSong) {
                NSLog(@"❌ [QQ音乐] 没有与《%@》同名的结果，首条是 %@", songName, songs.firstObject[@"songname"] ?: @"");
                NSError *notFoundError = [NSError errorWithDomain:@"QQMusicLyricsAPI"
                                                             code:-404
                                                         userInfo:@{NSLocalizedDescriptionKey: @"未找到同名歌曲"}];
                if (completion) completion(nil, notFoundError);
                return;
            }
            NSString *songMid = firstSong[@"songmid"];
            NSString *foundSongName = firstSong[@"songname"];
            NSString *foundArtistName = [self joinedSingers:firstSong];
            if (firstSong != songs.firstObject) {
                NSLog(@"[QQ音乐] 已跳过标题不符的首条结果: %@", songs.firstObject[@"songname"] ?: @"");
            }
            NSLog(@"✅ [QQ音乐] 搜索到: %@ - %@ (songmid: %@)", foundArtistName, foundSongName, songMid);
            
            // 用找到的 songmid 获取歌词
            [self fetchLyricsWithSongMid:songMid completion:^(QQMusicLyrics *lyrics, NSError *error) {
                if (lyrics) {
                    lyrics.songName = foundSongName;
                    lyrics.artistName = foundArtistName;
                    lyrics.sourceSongMid = songMid;
                    lyrics.sourceDuration = [firstSong[@"interval"] doubleValue];
                }
                if (completion) completion(lyrics, error);
            }];
        }];
    [task resume];
}

+ (void)fetchLyricsFromAudioFile:(NSString *)audioFilePath
                      completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion {
    // 1. 先尝试从元数据中提取 QQ音乐 ID
    NSDictionary *metadata = [self extractQQMusicMetadataFromFile:audioFilePath];
    
    if (metadata[@"songmid"]) {
        NSLog(@"🎵 [QQ音乐] 从元数据找到 songmid: %@", metadata[@"songmid"]);
        [self fetchLyricsWithSongMid:metadata[@"songmid"] completion:completion];
        return;
    }
    
    if (metadata[@"songid"]) {
        NSLog(@"🎵 [QQ音乐] 从元数据找到 songid: %@", metadata[@"songid"]);
        [self fetchLyricsWithSongId:metadata[@"songid"] completion:completion];
        return;
    }
    
    // 2. 如果没有 ID，尝试用歌名和艺术家搜索
    NSString *songName = metadata[@"songName"];
    NSString *artistName = metadata[@"artistName"];
    
    if (songName) {
        NSLog(@"🎵 [QQ音乐] 未找到ID，尝试搜索: %@ - %@", artistName ?: @"未知", songName);
        [self searchAndFetchLyricsWithSongName:songName artistName:artistName completion:completion];
        return;
    }
    
    // 3. 完全没有有效信息
    NSError *error = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                         code:-2 
                                     userInfo:@{NSLocalizedDescriptionKey: @"音频文件不包含 QQ音乐元数据"}];
    NSLog(@"❌ [QQ音乐] 文件不包含元数据: %@", audioFilePath.lastPathComponent);
    if (completion) completion(nil, error);
}

+ (nullable NSDictionary *)extractQQMusicMetadataFromFile:(NSString *)audioFilePath {
    NSURL *audioURL = [NSURL fileURLWithPath:audioFilePath];
    AVAsset *asset = [AVAsset assetWithURL:audioURL];
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    // 获取所有元数据
    NSArray *metadata = [asset commonMetadata];
    
    for (AVMetadataItem *item in metadata) {
        NSString *key = item.commonKey ?: [item.identifier description];
        NSString *value = [item.stringValue copy];
        
        if (!value) continue;
        
        // 检查各种可能的 QQ音乐标识
        if ([key containsString:@"songmid"] || [key containsString:@"QQMUSICID"]) {
            result[@"songmid"] = value;
            NSLog(@"  📌 找到 songmid: %@", value);
        }
        else if ([key containsString:@"songid"] || [key containsString:@"SONGID"]) {
            result[@"songid"] = value;
            NSLog(@"  📌 找到 songid: %@", value);
        }
        else if ([item.commonKey isEqualToString:AVMetadataCommonKeyTitle]) {
            result[@"songName"] = value;
            NSLog(@"  📌 歌曲名: %@", value);
        }
        else if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtist]) {
            result[@"artistName"] = value;
            NSLog(@"  📌 艺术家: %@", value);
        }
        else if ([item.commonKey isEqualToString:AVMetadataCommonKeyAlbumName]) {
            result[@"albumName"] = value;
        }
    }
    
    // 检查是否为 QQ音乐来源 (通过 comment 或 encoder 标签)
    NSArray *commentItems = [AVMetadataItem metadataItemsFromArray:metadata 
                                                           withKey:AVMetadataCommonKeyDescription
                                                          keySpace:AVMetadataKeySpaceCommon];
    for (AVMetadataItem *item in commentItems) {
        NSString *comment = [item.stringValue copy];
        if ([comment containsString:@"QQMusic"] || [comment containsString:@"qq.com"]) {
            result[@"isQQMusic"] = @YES;
            NSLog(@"  ✅ 确认为 QQ音乐来源");
        }
    }
    
    if (result[@"songmid"] == nil) {
        NSString *base = [[audioFilePath lastPathComponent] stringByDeletingPathExtension];
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^qqMusic-([0-9A-Za-z]{8,32})$" options:0 error:nil];
        NSTextCheckingResult *match = [expression firstMatchInString:base options:0 range:NSMakeRange(0, base.length)];
        if (match.numberOfRanges >= 2) {
            result[@"songmid"] = [base substringWithRange:[match rangeAtIndex:1]];
            NSLog(@"  📌 从文件名找到 songmid: %@", result[@"songmid"]);
        }
    }

    return result.count > 0 ? result : nil;
}

+ (NSString *)foldedToken:(NSString *)value {
    NSString *folded = [(value ?: @"") lowercaseString];
    folded = [folded stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    return [[folded componentsSeparatedByCharactersInSet:[NSCharacterSet alphanumericCharacterSet].invertedSet] componentsJoinedByString:@""];
}

+ (NSString *)joinedSingers:(NSDictionary *)song {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id singer in song[@"singer"]) {
        if ([singer isKindOfClass:NSDictionary.class] && [singer[@"name"] isKindOfClass:NSString.class]) [names addObject:singer[@"name"]];
    }
    return [names componentsJoinedByString:@";"];
}

+ (NSDictionary *)bestMatchInSongs:(NSArray *)songs songName:(NSString *)songName artistName:(NSString *)artistName {
    NSString *wanted = [self foldedToken:songName];
    if (wanted.length == 0) return nil;
    NSCharacterSet *splits = [NSCharacterSet characterSetWithCharactersInString:@"/、,，&;"];
    NSDictionary *best = nil;
    NSInteger bestScore = -1;
    for (NSDictionary *song in songs) {
        if (![song isKindOfClass:NSDictionary.class] || ![[self foldedToken:song[@"songname"]] isEqualToString:wanted]) continue;
        NSInteger score = 0;
        NSString *artists = [self foldedToken:[self joinedSingers:song]];
        for (NSString *token in [artistName componentsSeparatedByCharactersInSet:splits]) {
            NSString *key = [self foldedToken:token];
            if (key.length >= 2 && [artists containsString:key]) score += 1;
        }
        if (score > bestScore) { bestScore = score; best = song; }
    }
    return best;
}

#pragma mark - Private Helper Methods

+ (void)performLyricsRequest:(NSString *)urlString 
                  completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // 设置必要的请求头（绕过防爬虫）
    [request setValue:@"https://y.qq.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:10.0];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request 
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"❌ [QQ音乐] 请求失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            // 解析 JSON 响应
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"❌ [QQ音乐] JSON解析失败: %@", jsonError.localizedDescription);
                if (completion) completion(nil, jsonError);
                return;
            }
            
            // 检查返回码
            NSInteger retcode = [json[@"retcode"] integerValue];
            if (retcode != 0) {
                NSError *apiError = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                                        code:retcode 
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"API返回错误码: %ld", (long)retcode]}];
                NSLog(@"❌ [QQ音乐] API错误: retcode=%ld", (long)retcode);
                if (completion) completion(nil, apiError);
                return;
            }
            
            // 提取歌词数据
            QQMusicLyrics *lyricsObj = [[QQMusicLyrics alloc] init];
            
            // 原文歌词 (Base64编码的)
            NSString *lyricBase64 = json[@"lyric"];
            if (lyricBase64 && lyricBase64.length > 0) {
                lyricsObj.originalLyrics = [self decodeBase64String:lyricBase64];
            }
            
            // 翻译歌词
            NSString *transBase64 = json[@"trans"];
            if (transBase64 && transBase64.length > 0) {
                lyricsObj.translatedLyrics = [self decodeBase64String:transBase64];
            }
            
            // 罗马音/拼音歌词
            NSString *romaBase64 = json[@"roma"];
            if (romaBase64 && romaBase64.length > 0) {
                lyricsObj.romaLyrics = [self decodeBase64String:romaBase64];
            }
            
            if (lyricsObj.originalLyrics) {
                NSLog(@"✅ [QQ音乐] 歌词获取成功，长度: %lu 字符", (unsigned long)lyricsObj.originalLyrics.length);
                if (completion) completion(lyricsObj, nil);
            } else {
                NSError *noLyricsError = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                                             code:-3 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"该歌曲暂无歌词"}];
                NSLog(@"⚠️ [QQ音乐] 该歌曲无歌词");
                if (completion) completion(nil, noLyricsError);
            }
        }];
    [task resume];
}

+ (NSString *)decodeBase64String:(NSString *)base64String {
    if (!base64String || base64String.length == 0) {
        return nil;
    }
    
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
    if (!decodedData) {
        return nil;
    }
    
    return [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
}

#pragma mark - 🆕 逐字歌词 API

+ (void)fetchWordByWordLyricsWithSongMid:(NSString *)songMid
                               completion:(void(^)(QQMusicLyrics * _Nullable lyrics, NSError * _Nullable error))completion {
    
    if (!songMid || songMid.length == 0) {
        NSError *error = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                             code:-1 
                                         userInfo:@{NSLocalizedDescriptionKey: @"songmid 不能为空"}];
        if (completion) completion(nil, error);
        return;
    }
    
    NSLog(@"🎤 [QQ音乐] 获取逐字歌词: songmid=%@", songMid);
    
    // 🔑 关键：使用 lrctype=4 参数获取逐字歌词
    // 参考: https://blog.csdn.net/gitblog_00146/article/details/151094966
    NSString *urlString = [NSString stringWithFormat:
        @"https://c.y.qq.com/lyric/fcgi-bin/fcg_download_lyric.fcg?songmid=%@&lrctype=4&format=json",
        songMid];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // 设置必要的请求头
    [request setValue:@"https://y.qq.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error) {
                NSLog(@"❌ [QQ音乐] 网络请求失败: %@", error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            
            // 解析JSON
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"❌ [QQ音乐] JSON解析失败: %@", jsonError.localizedDescription);
                if (completion) completion(nil, jsonError);
                return;
            }
            
            // 检查返回码
            NSInteger retcode = [json[@"retcode"] integerValue];
            if (retcode != 0) {
                NSError *apiError = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                                        code:retcode 
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"逐字歌词API错误码: %ld", (long)retcode]}];
                NSLog(@"❌ [QQ音乐] 逐字歌词API错误: retcode=%ld", (long)retcode);
                if (completion) completion(nil, apiError);
                return;
            }
            
            // 提取歌词数据
            QQMusicLyrics *lyricsObj = [[QQMusicLyrics alloc] init];
            
            // 逐字歌词 (lrctype=4 返回的是 Base64 编码)
            NSString *wordByWordBase64 = json[@"lyric"];
            if (wordByWordBase64 && wordByWordBase64.length > 0) {
                lyricsObj.wordByWordLyrics = [self decodeBase64String:wordByWordBase64];
                lyricsObj.hasWordByWord = YES;
            }
            
            // 同时也可能返回普通歌词
            NSString *lyricBase64 = json[@"lyric"];
            if (lyricBase64 && lyricBase64.length > 0) {
                lyricsObj.originalLyrics = [self decodeBase64String:lyricBase64];
            }
            
            // 翻译歌词
            NSString *transBase64 = json[@"trans"];
            if (transBase64 && transBase64.length > 0) {
                lyricsObj.translatedLyrics = [self decodeBase64String:transBase64];
            }
            
            if (lyricsObj.wordByWordLyrics) {
                NSLog(@"✅ [QQ音乐] 逐字歌词获取成功，长度: %lu 字符", (unsigned long)lyricsObj.wordByWordLyrics.length);
                NSLog(@"📝 [QQ音乐] 逐字歌词预览: %@", [lyricsObj.wordByWordLyrics substringToIndex:MIN(100, lyricsObj.wordByWordLyrics.length)]);
                if (completion) completion(lyricsObj, nil);
            } else {
                NSError *noLyricsError = [NSError errorWithDomain:@"QQMusicLyricsAPI" 
                                                             code:-3 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"该歌曲暂无逐字歌词"}];
                NSLog(@"⚠️ [QQ音乐] 该歌曲无逐字歌词");
                if (completion) completion(nil, noLyricsError);
            }
        }];
    [task resume];
}

@end

