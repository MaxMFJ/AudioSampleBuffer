//
//  AppDelegate.h
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
- (void)handleIncomingURL:(NSURL *)url;

@end

