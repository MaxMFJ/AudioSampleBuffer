//
//  ViewController+CloudDownload.m
//  AudioSampleBuffer
//
//  云端下载功能实现
//

#import "ViewController+CloudDownload.h"
#import "MusicLibraryManager.h"
#import <objc/runtime.h>

@implementation ViewController (CloudDownload)

#pragma mark - Public Methods

- (void)setupCloudDownloadFeature {
    // 计算按钮位置
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70;
    
    // 创建云端下载按钮
    UIButton *cloudButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cloudButton setTitle:@"☁️ 云端" forState:UIControlStateNormal];
    [cloudButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cloudButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    cloudButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.9];
    cloudButton.layer.cornerRadius = 25;
    cloudButton.layer.borderWidth = 2.0;
    cloudButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0].CGColor;
    cloudButton.frame = CGRectMake(260, topOffset, 100, 50);
    
    // 添加阴影效果
    cloudButton.layer.shadowColor = [UIColor cyanColor].CGColor;
    cloudButton.layer.shadowOffset = CGSizeMake(0, 2);
    cloudButton.layer.shadowOpacity = 0.8;
    cloudButton.layer.shadowRadius = 4;
    
    [cloudButton addTarget:self 
                    action:@selector(cloudDownloadButtonTapped:) 
          forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:cloudButton];
    
    // 🔑 保存按钮引用到ViewController属性中，以便在UI切换时可以隐藏/显示
    [self setValue:cloudButton forKey:@"cloudButton"];
    
    NSLog(@"☁️ [云端下载] 功能已启用");
}

- (void)showCloudDownloadDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"☁️ 云端音乐库"
                                                                   message:@"从酷狗音乐搜索并下载\n支持免费下载大部分歌曲"
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
                                                                          message:@"正在从酷狗音乐搜索\n请稍候..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 执行搜索 - 只搜索酷狗音乐（目前唯一支持下载的平台）
    [[MusicDownloadManager sharedManager] searchMusic:keyword
                                             platforms:@[@(MusicSourcePlatformKugou)]  // 只搜索酷狗
                                            maxResults:15   // 增加结果数量
                                            completion:^(NSArray<MusicSearchResult *> *results, NSError *error) {
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

- (void)showSearchResultsList:(NSArray<MusicSearchResult *> *)results {
    UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"🎵 搜索结果"
                                                                         message:[NSString stringWithFormat:@"找到 %lu 首歌曲，点击下载", (unsigned long)results.count]
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 显示前12个结果
    NSInteger maxShow = MIN(results.count, 12);
    for (NSInteger i = 0; i < maxShow; i++) {
        MusicSearchResult *result = results[i];
        
        // 格式化文件大小
        CGFloat sizeMB = result.fileSize / 1024.0 / 1024.0;
        NSString *sizeStr = sizeMB > 0 ? [NSString stringWithFormat:@"%.1fMB", sizeMB] : @"";
        
        // 格式化标题
        NSString *title = [NSString stringWithFormat:@"%@ - %@\n[%@] %@",
                          result.artistName ?: @"未知",
                          result.songName ?: @"未知",
                          [self platformEmoji:result.platform],
                          sizeStr];
        
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            [self downloadMusicResult:result];
        }];
        
        [resultAlert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [resultAlert addAction:cancelAction];
    
    [self presentViewController:resultAlert animated:YES completion:nil];
}

- (void)downloadMusicResult:(MusicSearchResult *)result {
    NSLog(@"⬇️ [云端下载] 开始: %@ - %@", result.artistName, result.songName);
    
    // 创建进度对话框
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"⬇️ 下载中"
                                                                           message:@"准备下载... 0%"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    
    // 添加取消按钮（如果需要）
    // UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    // [progressAlert addAction:cancelAction];
    
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    // 开始下载
    [[MusicDownloadManager sharedManager] downloadMusic:result
                                                 quality:MusicQualityAuto
                                         downloadLyrics:YES  // 同时下载歌词
                                          downloadCover:YES  // 同时下载封面
                                                progress:^(float progress, NSString *status) {
        // 更新进度
        dispatch_async(dispatch_get_main_queue(), ^{
            progressAlert.message = [NSString stringWithFormat:@"%@\n%.0f%%", status, progress * 100];
        });
        
    } completion:^(NSString *filePath, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (error) {
                    NSString *errorMsg = error.localizedDescription;
                    if ([errorMsg containsString:@"暂不支持"]) {
                        errorMsg = [NSString stringWithFormat:@"%@\n\n💡 提示：当前仅支持部分平台下载\n推荐选择酷狗音乐的结果", errorMsg];
                    }
                    [self showSimpleAlert:@"❌ 下载失败" message:errorMsg];
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
    [[MusicDownloadManager sharedManager] searchAndDownloadMusic:keyword
                                                          quality:MusicQualityAuto
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

- (NSString *)platformEmoji:(MusicSourcePlatform)platform {
    switch (platform) {
        case MusicSourcePlatformQQMusic: return @"QQ音乐";
        case MusicSourcePlatformNetease: return @"网易云";
        case MusicSourcePlatformKugou:   return @"酷狗";
        case MusicSourcePlatformBaidu:   return @"百度";
        default: return @"未知";
    }
}

@end
