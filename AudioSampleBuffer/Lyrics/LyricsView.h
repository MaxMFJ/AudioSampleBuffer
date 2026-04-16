//
//  LyricsView.h
//  AudioSampleBuffer
//
//  Created for displaying synchronized lyrics
//

#import <UIKit/UIKit.h>
#import "LRCParser.h"
#import "LyricsEffectType.h"
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// 视觉歌词回调，便于外部驱动 Metal 风格歌词特效
@protocol LyricsViewVisualDelegate <NSObject>
@optional
- (void)lyricsView:(id)lyricsView didUpdateVisualLyricText:(nullable NSString *)text progress:(CGFloat)progress;
- (void)lyricsView:(id)lyricsView didUpdateVisualLyricLines:(NSArray<NSString *> *)lines currentIndex:(NSInteger)currentIndex;
@end

@class LyricsView;

/// 视觉歌词文本更新通知，userInfo: text, progress
extern NSString *const kLyricsViewDidUpdateVisualTextNotification;
/// 视觉歌词多行更新通知，userInfo: lines, currentIndex
extern NSString *const kLyricsViewDidUpdateVisualLinesNotification;

/// 歌词点击代理
@protocol LyricsViewDelegate <NSObject>
@optional
/**
 * 用户点击了某一行歌词
 * @param lyricsView 歌词视图
 * @param time 该行歌词对应的时间点
 * @param text 歌词文本
 * @param index 歌词索引
 */
- (void)lyricsView:(LyricsView *)lyricsView didTapLyricAtTime:(NSTimeInterval)time text:(NSString *)text index:(NSInteger)index;
@end

/// 歌词显示视图
@interface LyricsView : UIView

/// 代理
@property (nonatomic, weak, nullable) id<LyricsViewDelegate> delegate;

/// 视觉歌词代理
@property (nonatomic, weak, nullable) id<LyricsViewVisualDelegate> visualDelegate;

/// 歌词解析器
@property (nonatomic, strong, nullable) LRCParser *parser;

/// 当前高亮歌词颜色
@property (nonatomic, strong) UIColor *highlightColor;

/// 普通歌词颜色
@property (nonatomic, strong) UIColor *normalColor;

/// 字体大小
@property (nonatomic, strong) UIFont *lyricsFont;

/// 高亮歌词字体大小
@property (nonatomic, strong) UIFont *highlightFont;

/// 行间距
@property (nonatomic, assign) CGFloat lineSpacing;

/// 是否启用自动滚动（默认YES）
@property (nonatomic, assign) BOOL autoScroll;

/// 当前特效类型
@property (nonatomic, assign) LyricsEffectType currentEffect;

/// 当前高亮歌词索引（只读）
@property (nonatomic, assign, readonly) NSInteger currentIndex;

/**
 * 更新当前播放时间，自动高亮并滚动到对应歌词
 * @param currentTime 当前播放时间（秒）
 */
- (void)updateWithTime:(NSTimeInterval)currentTime;

/**
 * 重置显示
 */
- (void)reset;

/**
 * 滚动到指定索引的歌词
 * @param index 歌词索引
 * @param animated 是否动画
 */
- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated;

/**
 * 设置歌词特效
 * @param effectType 特效类型
 */
- (void)setLyricsEffect:(LyricsEffectType)effectType;

@end

NS_ASSUME_NONNULL_END

