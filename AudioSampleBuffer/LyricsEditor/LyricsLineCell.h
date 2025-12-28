//
//  LyricsLineCell.h
//  AudioSampleBuffer
//
//  歌词行列表单元格 - 显示时间戳和歌词文本
//

#import <UIKit/UIKit.h>
#import "LRCGenerator.h"

NS_ASSUME_NONNULL_BEGIN

@class LyricsLineCell;

/// 歌词行单元格代理
@protocol LyricsLineCellDelegate <NSObject>

@optional

/// 时间戳微调（±0.1s）
- (void)lyricsLineCell:(LyricsLineCell *)cell didAdjustTimestamp:(NSTimeInterval)delta;

/// 点击编辑歌词文本
- (void)lyricsLineCellDidTapEdit:(LyricsLineCell *)cell;

/// 点击删除歌词行
- (void)lyricsLineCellDidTapDelete:(LyricsLineCell *)cell;

/// 点击清除时间戳
- (void)lyricsLineCellDidTapClearTimestamp:(LyricsLineCell *)cell;

@end

/// 歌词行单元格
@interface LyricsLineCell : UITableViewCell

/// 代理
@property (nonatomic, weak, nullable) id<LyricsLineCellDelegate> delegate;

/// 行索引
@property (nonatomic, assign) NSInteger lineIndex;

/// 配置单元格
/// @param line 歌词行数据
/// @param isCurrent 是否是当前打轴行
/// @param index 行索引
- (void)configureWithLine:(LRCEditableLine *)line isCurrent:(BOOL)isCurrent index:(NSInteger)index;

/// 更新当前行状态
/// @param isCurrent 是否是当前打轴行
- (void)updateCurrentState:(BOOL)isCurrent;

/// 播放闪烁动画（打轴成功时）
- (void)playStampAnimation;

@end

NS_ASSUME_NONNULL_END

