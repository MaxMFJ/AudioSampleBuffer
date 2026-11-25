#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Muted video follower driven by media-grounded song/video time mappings.
@interface SignatureMVClipPlayer : NSObject

- (instancetype)initWithHostView:(UIView *)hostView;
- (void)noteSongTitle:(nullable NSString *)title;
- (void)prepareResolvedVideoURL:(NSURL *)url song:(nullable NSString *)song;
- (void)updateWithTitle:(nullable NSString *)title time:(NSTimeInterval)time playing:(BOOL)playing;
- (void)updateWithTitle:(nullable NSString *)title
                   time:(NSTimeInterval)time
                playing:(BOOL)playing
             mvMoments:(NSArray<NSDictionary<NSString *, id> *> *)moments;
- (void)stop;
- (BOOL)isShowingVideo;

@end

NS_ASSUME_NONNULL_END
