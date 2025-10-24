//
//  AppDelegate.m
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 🎵 配置全局音频会话（初始设置）
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    // 设置为播放类别（不带混音选项，让 AudioSpectrumPlayer 根据开关动态控制）
    BOOL success = [audioSession setCategory:AVAudioSessionCategoryPlayback 
                                  withOptions:0 
                                        error:&error];
    if (!success || error) {
        NSLog(@"❌ AppDelegate: 音频会话初始配置失败: %@", error);
    } else {
        NSLog(@"✅ AppDelegate: 音频会话初始配置成功");
    }
    
    // 激活音频会话
    error = nil;
    success = [audioSession setActive:YES error:&error];
    if (!success || error) {
        NSLog(@"❌ AppDelegate: 音频会话激活失败: %@", error);
    } else {
        NSLog(@"✅ AppDelegate: 音频会话已激活");
    }
    
    return YES;
}



- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}
- (void)applicationWillResignActive:(UIApplication *)application {
    // 🔊 重要：不要在这里设置音频会话，这会覆盖用户的混音开关设置
    // 音频会话由 AudioSpectrumPlayer 管理，根据用户的混音开关动态配置
    
    NSLog(@"📱 应用即将失去焦点 (applicationWillResignActive)");
}

@end
