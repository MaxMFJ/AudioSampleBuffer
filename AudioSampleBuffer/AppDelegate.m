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

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {

    NSLog(@"收到跳转：%@", url.absoluteString);

    // fakegame://login?uid=123&token=abc
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    
    // 构建显示内容
    NSMutableString *message = [NSMutableString string];
    [message appendFormat:@"完整 URL：\n%@\n\n", url.absoluteString];
    
    if (c.host) {
        [message appendFormat:@"Host：%@\n", c.host];
    }
    if (c.path) {
        [message appendFormat:@"Path：%@\n", c.path];
    }
    
    if (c.queryItems && c.queryItems.count > 0) {
        [message appendString:@"\n查询参数：\n"];
        for (NSURLQueryItem *item in c.queryItems) {
            NSLog(@"%@ = %@", item.name, item.value);
            [message appendFormat:@"%@ = %@\n", item.name, item.value ?: @"(null)"];
        }
    }
    
    // 显示弹窗
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收到 URL 跳转"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alert addAction:okAction];
        
        // 获取当前窗口的根视图控制器
        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController) {
            // 如果根视图控制器是导航控制器，获取最顶层的视图控制器
            if ([rootViewController isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navController = (UINavigationController *)rootViewController;
                rootViewController = navController.topViewController;
            }
            // 如果根视图控制器是标签栏控制器，获取选中的视图控制器
            if ([rootViewController isKindOfClass:[UITabBarController class]]) {
                UITabBarController *tabController = (UITabBarController *)rootViewController;
                rootViewController = tabController.selectedViewController;
                if ([rootViewController isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *navController = (UINavigationController *)rootViewController;
                    rootViewController = navController.topViewController;
                }
            }
            // 如果根视图控制器正在展示其他视图控制器，使用 presentedViewController
            while (rootViewController.presentedViewController) {
                rootViewController = rootViewController.presentedViewController;
            }
            
            [rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
    
    return YES;
}

@end
