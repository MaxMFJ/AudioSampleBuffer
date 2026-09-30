#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// On-device, cache-backed HTDemucs6s guitar control curve for one local track.
@interface HTDemucsGuitarAnalyzer : NSObject

+ (instancetype)sharedAnalyzer;
- (nullable NSDictionary *)cachedAnalysisForAudioAtURL:(NSURL *)audioURL;
- (void)analyzeAudioAtURL:(NSURL *)audioURL
               completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
