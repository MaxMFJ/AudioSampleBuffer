#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface MVLyricsProvider : NSObject
+ (void)fetchSongPath:(NSString *)songPath title:(NSString *)title artist:(NSString *)artist
           completion:(void (^)(NSDictionary * _Nullable result))completion
    NS_SWIFT_NAME(fetch(songPath:title:artist:completion:));
@end
NS_ASSUME_NONNULL_END
