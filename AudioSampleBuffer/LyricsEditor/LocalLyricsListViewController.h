//
//  LocalLyricsListViewController.h
//  AudioSampleBuffer
//
//  本地歌词列表管理 - 查看、删除本地保存的 LRC 歌词文件
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class LocalLyricsListViewController;

/// 歌词选择代理
@protocol LocalLyricsListViewControllerDelegate <NSObject>

@optional
/// 选中了一个歌词文件
- (void)lyricsListViewController:(LocalLyricsListViewController *)controller didSelectLyricsAtPath:(NSString *)path;

@end

/// 本地歌词列表管理控制器
@interface LocalLyricsListViewController : UIViewController

/// 代理
@property (nonatomic, weak, nullable) id<LocalLyricsListViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END

