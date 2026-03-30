//
//  LLMAPISettings.m
//  AudioSampleBuffer
//

#import "LLMAPISettings.h"

NSString *const kLLMAPISettingsDidChangeNotification = @"LLMAPISettingsDidChangeNotification";

static NSString *const kLLMAPIBaseURLDefaultsKey = @"LLMAPISettings.baseURL";
static NSString *const kLLMAPIModelDefaultsKey = @"LLMAPISettings.model";
static NSString *const kLLMAPIKeyDefaultsKey = @"LLMAPISettings.apiKey";
static NSString *const kLLMDefaultEndpointPath = @"/v1/chat/completions";

@interface LLMAPISettings ()
@property (nonatomic, copy, readwrite) NSString *baseURL;
@property (nonatomic, copy, readwrite) NSString *model;
@property (nonatomic, copy, readwrite) NSString *apiKey;
@end

@implementation LLMAPISettings

+ (instancetype)sharedSettings {
    static LLMAPISettings *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LLMAPISettings alloc] init];
    });
    return instance;
}

+ (NSString *)defaultBaseURL {
    return @"https://api.deepseek.com";
}

+ (NSString *)defaultModel {
    return @"deepseek-chat";
}

+ (nullable NSURL *)resolvedServiceURLForBaseURL:(nullable NSString *)baseURL {
    NSString *trimmedBaseURL = [[baseURL ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    NSString *candidate = trimmedBaseURL.length > 0 ? trimmedBaseURL : [self defaultBaseURL];
    NSURLComponents *components = [NSURLComponents componentsWithString:candidate];
    if (components.scheme.length == 0 || components.host.length == 0) {
        return nil;
    }
    
    NSString *path = components.path ?: @"";
    if (path.length == 0 || [path isEqualToString:@"/"]) {
        components.path = kLLMDefaultEndpointPath;
    } else if ([path isEqualToString:@"/v1"]) {
        components.path = @"/v1/chat/completions";
    } else if ([path isEqualToString:@"/v1/"]) {
        components.path = @"/v1/chat/completions";
    }
    
    return components.URL;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reload];
    }
    return self;
}

- (BOOL)isConfigured {
    return self.apiKey.length > 0 && self.model.length > 0 && self.serviceURL != nil;
}

- (NSURL *)serviceURL {
    return [[self class] resolvedServiceURLForBaseURL:self.baseURL];
}

- (NSString *)maskedAPIKey {
    if (self.apiKey.length == 0) {
        return @"未填写";
    }
    
    NSUInteger visibleLength = MIN((NSUInteger)4, self.apiKey.length);
    NSString *suffix = [self.apiKey substringFromIndex:self.apiKey.length - visibleLength];
    return [NSString stringWithFormat:@"****%@", suffix];
}

- (void)reload {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storedBaseURL = [self trimmedString:[defaults stringForKey:kLLMAPIBaseURLDefaultsKey]];
    NSString *storedModel = [self trimmedString:[defaults stringForKey:kLLMAPIModelDefaultsKey]];
    NSString *storedAPIKey = [self trimmedString:[defaults stringForKey:kLLMAPIKeyDefaultsKey]];
    
    self.baseURL = storedBaseURL.length > 0 ? storedBaseURL : [[self class] defaultBaseURL];
    self.model = storedModel.length > 0 ? storedModel : [[self class] defaultModel];
    self.apiKey = storedAPIKey ?: @"";
}

- (void)updateWithBaseURL:(nullable NSString *)baseURL
                    model:(nullable NSString *)model
                   apiKey:(nullable NSString *)apiKey {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSString *trimmedBaseURL = [self trimmedString:baseURL];
    NSString *trimmedModel = [self trimmedString:model];
    NSString *trimmedAPIKey = [self trimmedString:apiKey];
    
    if (trimmedBaseURL.length > 0) {
        [defaults setObject:trimmedBaseURL forKey:kLLMAPIBaseURLDefaultsKey];
    } else {
        [defaults removeObjectForKey:kLLMAPIBaseURLDefaultsKey];
    }
    
    if (trimmedModel.length > 0) {
        [defaults setObject:trimmedModel forKey:kLLMAPIModelDefaultsKey];
    } else {
        [defaults removeObjectForKey:kLLMAPIModelDefaultsKey];
    }
    
    if (trimmedAPIKey.length > 0) {
        [defaults setObject:trimmedAPIKey forKey:kLLMAPIKeyDefaultsKey];
    } else {
        [defaults removeObjectForKey:kLLMAPIKeyDefaultsKey];
    }
    
    [self reload];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kLLMAPISettingsDidChangeNotification
                                                        object:self];
}

- (NSString *)trimmedString:(nullable NSString *)value {
    return [[value ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
}

@end
