#import "MVLyricsProvider.h"
#import "QQMusicLyricsAPI.h"

@implementation MVLyricsProvider
+ (NSString *)normalized:(NSString *)value {
    NSString *folded = [value.lowercaseString stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    return [[folded componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
}

+ (void)fetchSongPath:(NSString *)songPath title:(NSString *)title artist:(NSString *)artist completion:(void (^)(NSDictionary *))completion {
    NSDictionary *metadata = [QQMusicLyricsAPI extractQQMusicMetadataFromFile:songPath];
    NSString *mid = [metadata[@"songmid"] isKindOfClass:NSString.class] ? metadata[@"songmid"] : nil;
    NSString *songID = metadata[@"songid"] ? [metadata[@"songid"] description] : nil;
    void (^finish)(QQMusicLyrics *, NSError *) = ^(QQMusicLyrics *lyrics, NSError *error) {
        if (error || !lyrics.originalLyrics.length) { completion(nil); return; }
        BOOL exactID = mid.length || songID.length;
        if (!exactID) {
            NSString *wanted = [self normalized:title];
            NSString *actual = [self normalized:lyrics.songName ?: @""];
            NSString *actualArtist = [self normalized:lyrics.artistName ?: @""];
            BOOL artistMatched = NO;
            for (NSString *token in [artist componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/、,，&"]]) {
                NSString *key = [self normalized:token];
                if (key.length >= 2 && [actualArtist containsString:key]) artistMatched = YES;
            }
            if (!wanted.length || ![wanted isEqual:actual] || !artistMatched) { completion(nil); return; }
        }
        NSString *sourceMid = mid.length ? mid : lyrics.sourceSongMid;
        NSString *source = sourceMid.length ? [NSString stringWithFormat:@"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=%@", sourceMid] :
            songID.length ? [NSString stringWithFormat:@"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?musicid=%@", songID] :
            @"https://c.y.qq.com/soso/fcgi-bin/client_search_cp";
        completion(@{@"title": lyrics.songName ?: title, @"artist": lyrics.artistName ?: artist,
                     @"lrc": lyrics.originalLyrics, @"sourceURL": source,
                     @"provenance": exactID ? @"qq_music_file_id" : @"qq_music_search_result",
                     @"versionConfirmed": @(exactID), @"matchedDuration": @(lyrics.sourceDuration)});
    };
    if (mid.length) [QQMusicLyricsAPI fetchLyricsWithSongMid:mid completion:finish];
    else if (songID.length) [QQMusicLyricsAPI fetchLyricsWithSongId:songID completion:finish];
    else [QQMusicLyricsAPI searchAndFetchLyricsWithSongName:title artistName:artist completion:finish];
}
@end
