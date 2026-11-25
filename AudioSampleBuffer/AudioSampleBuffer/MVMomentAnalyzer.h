#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MVMomentAnalyzer : NSObject
+ (instancetype)sharedAnalyzer;
- (NSProgress *)analyzeFileAtURL:(NSURL *)url completion:(void (^)(NSArray<NSDictionary<NSString *, NSNumber *> *> * _Nullable moments, BOOL cacheHit, NSError * _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
