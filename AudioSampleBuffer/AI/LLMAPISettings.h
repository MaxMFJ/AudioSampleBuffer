//
//  LLMAPISettings.h
//  AudioSampleBuffer
//
//  在 App 沙箱内保存可配置的 LLM 接口信息
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kLLMAPISettingsDidChangeNotification;

@interface LLMAPISettings : NSObject

@property (nonatomic, copy, readonly) NSString *baseURL;
@property (nonatomic, copy, readonly) NSString *model;
@property (nonatomic, copy, readonly) NSString *apiKey;
@property (nonatomic, copy, readonly) NSString *maskedAPIKey;
@property (nonatomic, strong, readonly, nullable) NSURL *serviceURL;

+ (instancetype)sharedSettings;

+ (NSString *)defaultBaseURL;
+ (NSString *)defaultModel;
+ (nullable NSURL *)resolvedServiceURLForBaseURL:(nullable NSString *)baseURL;

- (BOOL)isConfigured;
- (void)reload;
- (void)updateWithBaseURL:(nullable NSString *)baseURL
                    model:(nullable NSString *)model
                   apiKey:(nullable NSString *)apiKey;

@end

NS_ASSUME_NONNULL_END
