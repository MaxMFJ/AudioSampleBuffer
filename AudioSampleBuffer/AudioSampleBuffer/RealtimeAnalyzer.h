#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RealtimeAnalyzer : NSObject

- (instancetype)initWithFFTSize:(int)fftSize;
- (NSArray *)analyse:(AVAudioPCMBuffer *)buffer withAmplitudeLevel:(int)amplitudeLevel;

@end

NS_ASSUME_NONNULL_END
