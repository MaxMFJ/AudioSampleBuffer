#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Offline YAMNet analysis records, keyed by the audio-file SHA-256 and model version.
@interface YAMNetAudioAnalyzer : NSObject

+ (instancetype)sharedAnalyzer;

/// True after the bundled model is installed or while first-launch compilation runs.
@property (nonatomic, assign, readonly) BOOL modelInstalled;

/// Install a local .mlmodel or .mlpackage. Core ML compiles it into the app's
/// Application Support directory; the model is not copied into the app bundle.
- (void)installModelAtURL:(NSURL *)modelURL
               completion:(void (^)(NSError * _Nullable error))completion;

/// Decode local audio to 16 kHz mono PCM, run YAMNet, and cache all 521 class
/// scores per 0.96-second patch. This runs off the caller's thread.
- (void)analyzeAudioAtURL:(NSURL *)audioURL
               completion:(void (^)(NSDictionary * _Nullable result,
                                    NSError * _Nullable error))completion;

/// Return a previously cached analysis for this exact audio file and model version.
- (nullable NSDictionary *)cachedAnalysisForAudioAtURL:(NSURL *)audioURL;

@end

NS_ASSUME_NONNULL_END
