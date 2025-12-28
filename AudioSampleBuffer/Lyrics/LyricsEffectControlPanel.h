//
//  LyricsEffectControlPanel.h
//  AudioSampleBuffer
//
//  歌词特效控制面板
//

#import <UIKit/UIKit.h>
#import "LyricsEffectType.h"

NS_ASSUME_NONNULL_BEGIN

@protocol LyricsEffectControlDelegate <NSObject>

- (void)lyricsEffectDidChange:(LyricsEffectType)effectType;
- (void)lyricsVisibilityDidChange:(BOOL)isVisible;

@end

@interface LyricsEffectControlPanel : UIView

@property (nonatomic, weak) id<LyricsEffectControlDelegate> delegate;
@property (nonatomic, assign) LyricsEffectType currentEffect;
@property (nonatomic, assign) BOOL lyricsVisible; // 歌词是否可见

- (void)showAnimated:(BOOL)animated;
- (void)hideAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

