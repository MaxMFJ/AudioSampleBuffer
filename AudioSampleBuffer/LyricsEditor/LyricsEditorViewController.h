//
//  LyricsEditorViewController.h
//  AudioSampleBuffer
//
//  歌词打轴编辑器主控制器 - 手动为歌词添加时间戳并生成 LRC 文件
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class LyricsEditorViewController;

/// 歌词编辑器代理
@protocol LyricsEditorViewControllerDelegate <NSObject>

@optional

/// 歌词编辑完成，返回生成的 LRC 内容
- (void)lyricsEditor:(LyricsEditorViewController *)editor didFinishWithLRCContent:(NSString *)lrcContent;

/// 歌词编辑完成，返回保存的 LRC 文件路径
- (void)lyricsEditor:(LyricsEditorViewController *)editor didSaveLRCToPath:(NSString *)path;

/// 歌词编辑取消
- (void)lyricsEditorDidCancel:(LyricsEditorViewController *)editor;

@end

/// 歌词打轴编辑器
@interface LyricsEditorViewController : UIViewController

/// 代理
@property (nonatomic, weak, nullable) id<LyricsEditorViewControllerDelegate> delegate;

/// 音频文件路径
@property (nonatomic, copy, nullable) NSString *audioFilePath;

/// 音频文件 URL
@property (nonatomic, strong, nullable) NSURL *audioFileURL;

/// 预设的歌曲信息
@property (nonatomic, copy, nullable) NSString *songTitle;
@property (nonatomic, copy, nullable) NSString *artistName;
@property (nonatomic, copy, nullable) NSString *albumName;

/// 预设的歌词文本（可选，用于编辑已有歌词）
@property (nonatomic, copy, nullable) NSString *initialLyricsText;

/// 从已有 LRC 文件加载（用于修改时间戳）
@property (nonatomic, copy, nullable) NSString *existingLRCContent;

#pragma mark - 初始化

/// 使用音频文件路径初始化
- (instancetype)initWithAudioFilePath:(NSString *)audioPath;

/// 使用音频文件 URL 初始化
- (instancetype)initWithAudioFileURL:(NSURL *)audioURL;

#pragma mark - 外部控制

/// 开始打轴流程
- (void)startTimingProcess;

/// 暂停播放
- (void)pausePlayback;

/// 继续播放
- (void)resumePlayback;

/// 获取当前生成的 LRC 内容
- (NSString *)currentLRCContent;

@end

NS_ASSUME_NONNULL_END

