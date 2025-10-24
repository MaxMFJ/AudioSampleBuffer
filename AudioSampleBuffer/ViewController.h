//
//  ViewController.h
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

/// 停止当前播放
- (void)stopPlayback;

/// 播放下一首
- (void)playNext;

/// 播放上一首
- (void)playPrevious;

@end

