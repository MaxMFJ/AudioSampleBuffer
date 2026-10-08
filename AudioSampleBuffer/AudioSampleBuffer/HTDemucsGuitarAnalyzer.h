#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// On-device HTDemucs6s guitar/piano/drums control curves, cached per local track.
@interface HTDemucsGuitarAnalyzer : NSObject

+ (instancetype)sharedAnalyzer;
- (void)cancelCurrentAnalysis;
- (nullable NSDictionary *)cachedAnalysisForAudioAtURL:(NSURL *)audioURL;
- (void)analyzeAudioAtURL:(NSURL *)audioURL
               completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
