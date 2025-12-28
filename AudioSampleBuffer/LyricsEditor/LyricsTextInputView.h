//
//  LyricsTextInputView.h
//  AudioSampleBuffer
//
//  歌词文本输入/编辑视图 - 用于粘贴和编辑歌词文本
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class LyricsTextInputView;

/// 歌词文本输入视图代理
@protocol LyricsTextInputViewDelegate <NSObject>

/// 确认导入歌词
- (void)lyricsTextInputView:(LyricsTextInputView *)view didConfirmWithText:(NSString *)text;

/// 取消导入
- (void)lyricsTextInputViewDidCancel:(LyricsTextInputView *)view;

@end

/// 歌词文本输入视图
@interface LyricsTextInputView : UIView

/// 代理
@property (nonatomic, weak, nullable) id<LyricsTextInputViewDelegate> delegate;

/// 设置初始文本（用于编辑已有歌词）
@property (nonatomic, copy, nullable) NSString *initialText;

/// 预览歌词行数
@property (nonatomic, readonly) NSInteger previewLineCount;

/// 清空输入
- (void)clearInput;

/// 从剪贴板粘贴
- (void)pasteFromClipboard;

@end

NS_ASSUME_NONNULL_END

