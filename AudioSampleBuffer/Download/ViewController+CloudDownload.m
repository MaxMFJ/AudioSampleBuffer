//
//  ViewController+CloudDownload.m
//  AudioSampleBuffer
//
//  云端下载功能实现（使用新API）
//

#import "ViewController+CloudDownload.h"
#import "MusicLibraryManager.h"
#import "QQMusicAPIService.h"
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

@implementation ViewController (CloudDownload)

#pragma mark - Public Methods

- (void)setupCloudDownloadFeature {
    NSLog(@"☁️ [云端下载] 功能已启用（使用新API）");
}

- (void)showCloudDownloadDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"☁️ 云端音乐库"
                                                                   message:@"从云端搜索并下载音乐\n支持免费下载大部分歌曲"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入：歌手 歌名";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.returnKeyType = UIReturnKeySearch;
    }];
    
    // 取消
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    // 搜索并选择
    UIAlertAction *searchAction = [UIAlertAction actionWithTitle:@"🔍 搜索"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
        NSString *keyword = alert.textFields.firstObject.text;
        if (keyword.length > 0) {
            [self searchAndShowResults:keyword];
        }
    }];
    
    // 快速下载（第一个结果）
    UIAlertAction *quickDownloadAction = [UIAlertAction actionWithTitle:@"⚡ 快速下载"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction *action) {
        NSString *keyword = alert.textFields.firstObject.text;
        if (keyword.length > 0) {
            [self quickDownloadMusic:keyword];
        }
    }];
    
    [alert addAction:cancelAction];
    [alert addAction:searchAction];
    [alert addAction:quickDownloadAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)searchCloudMusicWithKeyword:(NSString *)keyword {
    [self searchAndShowResults:keyword];
}

#pragma mark - Private Methods

- (void)cloudDownloadButtonTapped:(UIButton *)sender {
    [self showCloudDownloadDialog];
}

- (void)searchAndShowResults:(NSString *)keyword {
    if (!keyword || keyword.length == 0) {
        [self showSimpleAlert:@"提示" message:@"请输入搜索关键词"];
        return;
    }
    
    // 显示加载提示
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"🔍 搜索中..."
                                                                          message:@"正在从云端搜索\n请稍候..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 执行搜索
    [[QQMusicAPIService sharedService] searchMusic:keyword completion:^(NSArray<QQMusicSearchResult *> *results, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showSimpleAlert:@"❌ 搜索失败" message:error.localizedDescription];
                    return;
                }
                
                if (results.count == 0) {
                    [self showSimpleAlert:@"❌ 未找到" message:@"请尝试更换关键词\n例如：周杰伦 七里香"];
                    return;
                }
                
                NSLog(@"✅ [云端搜索] 找到 %lu 个结果", (unsigned long)results.count);
                
                // 显示搜索结果列表
                [self showSearchResultsList:results];
            }];
        });
    }];
}

- (void)showSearchResultsList:(NSArray<QQMusicSearchResult *> *)results {
    UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"🎵 搜索结果"
                                                                         message:[NSString stringWithFormat:@"找到 %lu 首歌曲，点击下载", (unsigned long)results.count]
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 显示前15个结果
    NSInteger maxShow = MIN(results.count, 15);
    for (NSInteger i = 0; i < maxShow; i++) {
        QQMusicSearchResult *result = results[i];
        
        // 格式化标题
        NSString *title = [NSString stringWithFormat:@"%@ - %@",
                          result.artist ?: @"未知",
                          result.name ?: @"未知"];
        
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            [self downloadMusicFromSearchResult:result];
        }];
        
        [resultAlert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [resultAlert addAction:cancelAction];
    
    // 如果是iPad，需要设置popoverPresentationController
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        resultAlert.popoverPresentationController.sourceView = self.view;
        resultAlert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    
    [self presentViewController:resultAlert animated:YES completion:nil];
}

- (void)downloadMusicFromSearchResult:(QQMusicSearchResult *)result {
    NSLog(@"⬇️ [云端下载] 准备下载: %@ - %@", result.artist, result.name);
    
    // 创建进度对话框
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"⬇️ 下载中"
                                                                           message:@"获取详情... 0%"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    // 先获取详情
    [[QQMusicAPIService sharedService] getMusicDetail:result.rid completion:^(QQMusicDetail *detail, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    [self showSimpleAlert:@"❌ 获取详情失败" message:error.localizedDescription];
                }];
            });
            return;
        }
        
        // 更新进度
        dispatch_async(dispatch_get_main_queue(), ^{
            progressAlert.message = @"开始下载... 30%";
        });
        
        // 开始下载
        [[QQMusicAPIService sharedService] downloadMusic:detail
                                                 progress:^(float progress, NSString *status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progressAlert.message = [NSString stringWithFormat:@"%@\n%.0f%%", status, 30 + progress * 70];
            });
        } completion:^(NSString *filePath, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progressAlert dismissViewControllerAnimated:YES completion:^{
                    if (error) {
                        [self showSimpleAlert:@"❌ 下载失败" message:error.localizedDescription];
                        return;
                    }
                    
                    NSLog(@"✅ [云端下载] 完成: %@", filePath);
                    
                    // 下载成功提示
                    NSString *fileName = filePath.lastPathComponent;
                    [self showDownloadSuccessAlert:fileName filePath:filePath];
                    
                    // 刷新音乐库
                    [self refreshMusicLibrary];
                }];
            });
        }];
    }];
}

- (void)quickDownloadMusic:(NSString *)keyword {
    if (!keyword || keyword.length == 0) {
        [self showSimpleAlert:@"提示" message:@"请输入搜索关键词"];
        return;
    }
    
    // 创建进度对话框
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"⚡ 快速下载"
                                                                           message:@"搜索并下载最佳匹配...\n0%"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    // 搜索并下载第一个结果
    [[QQMusicAPIService sharedService] searchAndDownload:keyword
                                                 progress:^(float progress, NSString *status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            progressAlert.message = [NSString stringWithFormat:@"%@\n%.0f%%", status, progress * 100];
        });
    } completion:^(NSString *filePath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    [self showSimpleAlert:@"❌ 下载失败" 
                                  message:[NSString stringWithFormat:@"%@\n\n💡 建议：使用「搜索」功能手动选择", error.localizedDescription]];
                    return;
                }
                
                NSLog(@"✅ [快速下载] 完成: %@", filePath);
                
                NSString *fileName = filePath.lastPathComponent;
                [self showDownloadSuccessAlert:fileName filePath:filePath];
                [self refreshMusicLibrary];
            }];
        });
    }];
}

#pragma mark - Helper Methods

- (void)showDownloadSuccessAlert:(NSString *)fileName filePath:(NSString *)filePath {
    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 下载完成"
                                                                          message:fileName
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    
    // 立即播放
    UIAlertAction *playAction = [UIAlertAction actionWithTitle:@"▶️ 立即播放"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
        // 🔧 修复：传递完整路径而不是文件名
        [self playDownloadedMusic:filePath];
    }];
    
    // 稍后播放
    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"稍后"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [successAlert addAction:playAction];
    [successAlert addAction:laterAction];
    
    [self presentViewController:successAlert animated:YES completion:nil];
}

- (void)playDownloadedMusic:(NSString *)filePath {
    NSLog(@"▶️ [播放下载] 准备播放: %@", [filePath lastPathComponent]);
    
    // 获取播放器
    if (![self respondsToSelector:@selector(player)]) {
        NSLog(@"❌ [播放下载] 找不到播放器");
        return;
    }
    
    id player = [self valueForKey:@"player"];
    if (!player || ![player respondsToSelector:@selector(playWithFileName:)]) {
        NSLog(@"❌ [播放下载] 播放器无效或不支持播放");
        return;
    }
    
    // 🔧 修复：直接使用传入的完整路径
    // filePath 已经是完整路径（可能是 .m4a 或 .mp3）
    
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"❌ [播放下载] 文件不存在: %@", filePath);
        return;
    }
    
    NSLog(@"✅ [播放下载] 文件路径: %@", filePath);
    
    // 🔧 修复：下载完成后延迟一点播放，确保音频会话准备就绪
    // 下载过程中可能音频会话被影响，需要给系统一点时间恢复
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"▶️ [播放下载] 开始播放（延迟后）");
        
        // 🔊 强制重新激活音频会话，解决下载后播放没声音的问题
        NSError *error = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:&error];
        [session setActive:YES error:&error];
        if (error) {
            NSLog(@"⚠️ [播放下载] 音频会话激活警告: %@", error.localizedDescription);
            error = nil;
        } else {
            NSLog(@"✅ [播放下载] 音频会话已重新激活");
        }
        
        // 🔧 关键修复：使用标准的播放流程（自动处理索引、封面、歌词）
        NSArray *allMusic = [[MusicLibraryManager sharedManager] allMusic];
        NSString *fileName = [filePath lastPathComponent];
        NSInteger foundIndex = -1;
        
        NSLog(@"🔍 [索引查找] 开始查找...");
        NSLog(@"   目标文件名: %@", fileName);
        NSLog(@"   目标路径: %@", filePath);
        NSLog(@"   音乐库总数: %ld", (long)allMusic.count);
        
        for (NSInteger i = 0; i < allMusic.count; i++) {
            MusicItem *item = allMusic[i];
            
            // 🔧 增强比较逻辑
            BOOL matchFileName = [item.fileName isEqualToString:fileName];
            BOOL matchFilePath = [item.filePath isEqualToString:filePath];
            
            if (matchFileName || matchFilePath) {
                foundIndex = i;
                NSLog(@"✅ [播放下载] 找到歌曲索引: %ld", (long)i);
                NSLog(@"   匹配方式: %@", matchFileName ? @"文件名" : @"完整路径");
                NSLog(@"   item.fileName: %@", item.fileName);
                NSLog(@"   item.filePath: %@", item.filePath);
                break;
            }
        }
        
        if (foundIndex >= 0) {
            // 🔧 使用 runtime 直接修改实例变量 index
            Ivar indexIvar = class_getInstanceVariable([self class], "index");
            ptrdiff_t offset = 0;
            
            if (indexIvar) {
                // 🔧 正确的方式：获取 ivar 地址并设置值
                void *selfPtr = (__bridge void *)self;
                offset = ivar_getOffset(indexIvar);
                NSInteger *indexPtr = (NSInteger *)(selfPtr + offset);
                
                NSLog(@"🔍 [索引设置] 准备设置索引...");
                NSLog(@"   self 指针: %p", self);
                NSLog(@"   offset: %td", offset);
                NSLog(@"   index 地址: %p", indexPtr);
                NSLog(@"   旧值: %ld", (long)*indexPtr);
                
                *indexPtr = foundIndex;
                
                NSLog(@"   新值: %ld", (long)*indexPtr);
                NSLog(@"✅ [播放下载] 索引已设置: %ld", (long)foundIndex);
            }
            
            // 更新 displayedMusicItems
            if ([self respondsToSelector:@selector(setDisplayedMusicItems:)]) {
                [self setValue:allMusic forKey:@"displayedMusicItems"];
            }
            
            // 🎯 关键：调用 updateAudioSelection 更新封面UI
            if ([self respondsToSelector:@selector(updateAudioSelection)]) {
                [self performSelector:@selector(updateAudioSelection)];
                NSLog(@"✅ [播放下载] 已调用 updateAudioSelection 更新封面");
            }
            
            // 🔧 先停止当前播放，避免冲突
            if ([player respondsToSelector:@selector(stop)]) {
                [player performSelector:@selector(stop)];
                NSLog(@"⏹️ [播放下载] 已停止当前播放");
            }
            
            // 🎯 使用标准播放方法（包含封面、歌词等完整流程）
            if ([self respondsToSelector:@selector(playCurrentTrack)]) {
                NSLog(@"▶️ [播放下载] 准备调用 playCurrentTrack...");
                
                // 再次验证索引值
                if (indexIvar && offset > 0) {
                    void *selfPtr = (__bridge void *)self;
                    NSInteger *indexPtr = (NSInteger *)(selfPtr + offset);
                    NSLog(@"🔍 [播放前验证] 索引值: %ld", (long)*indexPtr);
                }
                
                [self performSelector:@selector(playCurrentTrack)];
                NSLog(@"✅ [播放下载] playCurrentTrack 已调用");
            } else {
                // 备用：直接播放
                [player performSelector:@selector(playWithFileName:) withObject:filePath];
                NSLog(@"▶️ [播放下载] 使用备用方式播放");
            }
        } else {
            NSLog(@"⚠️ [播放下载] 未在音乐库中找到该文件！");
            NSLog(@"   尝试的文件名: %@", fileName);
            NSLog(@"   尝试的路径: %@", filePath);
            NSLog(@"   音乐库中的最后5首歌:");
            NSInteger start = MAX(0, allMusic.count - 5);
            for (NSInteger i = start; i < allMusic.count; i++) {
                MusicItem *item = allMusic[i];
                NSLog(@"     [%ld] %@ | %@", (long)i, item.fileName, item.filePath);
            }
            
            // 即使找不到索引，也尝试直接播放
            [player performSelector:@selector(playWithFileName:) withObject:filePath];
            NSLog(@"▶️ [播放下载] 未找到索引，尝试直接播放");
        }
    });
}

- (void)refreshMusicLibrary {
    NSLog(@"🔄 [音乐库] 开始刷新...");
    
    // 1️⃣ 重新加载音乐库管理器
    [[MusicLibraryManager sharedManager] reloadMusicLibrary];
    
    // 2️⃣ 更新 displayedMusicItems（显示全部音乐）
    if ([self respondsToSelector:@selector(setDisplayedMusicItems:)]) {
        NSArray *allMusic = [[MusicLibraryManager sharedManager] allMusic];
        [self setValue:allMusic forKey:@"displayedMusicItems"];
        NSLog(@"🔄 [音乐库] 更新显示列表: %ld 首歌曲", (long)allMusic.count);
    }
    
    // 3️⃣ 刷新表格视图
    if ([self respondsToSelector:@selector(tableView)]) {
        UITableView *tableView = [self valueForKey:@"tableView"];
        if (tableView) {
            [tableView reloadData];
            NSLog(@"🔄 [音乐库] 表格已刷新");
        }
    }
    
    NSLog(@"✅ [音乐库] 刷新完成");
}

- (void)showSimpleAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
