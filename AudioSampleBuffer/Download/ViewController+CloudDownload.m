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
        // 播放新下载的音乐
        [self playDownloadedMusic:fileName];
    }];
    
    // 稍后播放
    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"稍后"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [successAlert addAction:playAction];
    [successAlert addAction:laterAction];
    
    [self presentViewController:successAlert animated:YES completion:nil];
}

- (void)playDownloadedMusic:(NSString *)fileName {
    NSLog(@"▶️ [播放下载] 准备播放: %@", fileName);
    
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
    
    // 构建完整文件路径（使用统一的下载目录）
    NSString *downloadDir = [MusicLibraryManager cloudDownloadDirectory];
    NSString *filePath = [downloadDir stringByAppendingPathComponent:fileName];
    
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"❌ [播放下载] 文件不存在: %@", filePath);
        return;
    }
    
    NSLog(@"✅ [播放下载] 文件路径: %@", filePath);
    
    // 使用完整路径播放（AudioSpectrumPlayer支持完整路径）
    [player performSelector:@selector(playWithFileName:) withObject:filePath];
    NSLog(@"▶️ [播放下载] 开始播放");
    
    // 更新当前播放索引到下载的歌曲
    NSArray *allMusic = [[MusicLibraryManager sharedManager] allMusic];
    for (NSInteger i = 0; i < allMusic.count; i++) {
        MusicItem *item = allMusic[i];
        if ([item.fileName isEqualToString:fileName] || [item.filePath isEqualToString:filePath]) {
            // 更新 displayedMusicItems 和 index
            if ([self respondsToSelector:@selector(setDisplayedMusicItems:)]) {
                [self setValue:allMusic forKey:@"displayedMusicItems"];
            }
            if ([self respondsToSelector:@selector(setIndex:)]) {
                [self setValue:@(i) forKey:@"index"];
            }
            NSLog(@"✅ [播放下载] 更新播放索引: %ld", (long)i);
            break;
        }
    }
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
