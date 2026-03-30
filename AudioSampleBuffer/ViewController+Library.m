#import "ViewController+Private.h"

#import "AudioFileFormats.h"
#import "AudioPlayCell.h"
#import "LLMAPISettings.h"
#import "LyricsManager.h"
#import "MusicAIAnalyzer.h"

#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ViewController (Library)

#pragma mark - Notifications

- (void)ncmDecryptionCompleted:(NSNotification *)notification {
    NSNumber *count = notification.userInfo[@"count"];
    NSLog(@"🎉 收到 NCM 解密完成通知: %@ 个文件", count);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ 解密完成"
                                                                       message:[NSString stringWithFormat:@"成功解密 %@ 个 NCM 文件\n现在可以播放了！", count]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Music Library

- (void)setupMusicLibrary {
    self.musicLibrary = [MusicLibraryManager sharedManager];
    self.currentCategory = MusicCategoryAll;
    self.currentSortType = MusicSortByName;
    self.sortAscending = YES;
    [self refreshMusicList];

    NSLog(@"🎵 音乐库初始化完成: %ld 首歌曲", (long)self.musicLibrary.totalMusicCount);
}

- (void)refreshMusicList {
    NSArray<MusicItem *> *musicList = [self.musicLibrary musicForCategory:self.currentCategory];

    if (self.searchBar.text.length > 0) {
        musicList = [self.musicLibrary searchMusic:self.searchBar.text inCategory:self.currentCategory];
    }

    self.displayedMusicItems = [self.musicLibrary sortMusic:musicList
                                                     byType:self.currentSortType
                                                  ascending:self.sortAscending];

    [self.tableView reloadData];
    NSLog(@"🔄 音乐列表已刷新: %ld 首", (long)self.displayedMusicItems.count);
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.displayedMusicItems.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AudioPlayCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cellID"];
    if (!cell) {
        cell = [[AudioPlayCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cellID"];
    }

    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    [cell configureWithMusicItem:musicItem];
    cell.playBtn.hidden = YES;

    __weak typeof(self) weakSelf = self;
    __weak AudioPlayCell *weakCell = cell;
    cell.playBlock = ^(BOOL isPlaying) {
        if (isPlaying) {
            [weakSelf.player stop];
        } else {
            NSString *playPath = nil;

            if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
                playPath = musicItem.decryptedPath;
            } else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
                NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
                playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];

                if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
                    [weakSelf.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
                }
            } else {
                playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
            }

            [weakSelf.player playWithFileName:playPath];
        }
    };

    cell.favoriteBlock = ^{
        [weakSelf.musicLibrary toggleFavoriteForMusic:musicItem];
        weakCell.favoriteButton.selected = musicItem.isFavorite;

        if (weakSelf.currentCategory == MusicCategoryFavorite && !musicItem.isFavorite) {
            [weakSelf refreshMusicList];
        }
    };

    cell.convertBlock = ^{
        [weakSelf convertNCMFile:musicItem atIndexPath:indexPath];
    };

    return cell;
}

#pragma mark - UITableView Editing

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];

    BOOL isBundleFile = ![musicItem.filePath hasPrefix:@"/var/mobile"] &&
                        ![musicItem.filePath hasPrefix:@"/Users"] &&
                        ![musicItem.filePath containsString:@"Documents"];

    if (isBundleFile) {
        return nil;
    }

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"删除"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        NSString *message = [NSString stringWithFormat:@"确定要删除 \"%@\" 吗？\n\n这将同时删除：\n• 音频文件\n• 歌词文件（如有）\n• 所有播放记录\n\n此操作不可撤销！", musicItem.displayName];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🗑️ 删除歌曲"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *confirmDelete = [UIAlertAction actionWithTitle:@"删除"
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^(UIAlertAction * _Nonnull action) {
            [self performDeleteMusicItem:musicItem atIndexPath:indexPath];
            completionHandler(YES);
        }];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction * _Nonnull action) {
            completionHandler(NO);
        }];

        [alert addAction:cancelAction];
        [alert addAction:confirmDelete];
        [self presentViewController:alert animated:YES completion:nil];
    }];

    deleteAction.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    BOOL isBundleFile = ![musicItem.filePath hasPrefix:@"/var/mobile"] &&
                        ![musicItem.filePath hasPrefix:@"/Users"] &&
                        ![musicItem.filePath containsString:@"Documents"];
    return !isBundleFile;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        MusicItem *musicItem = self.displayedMusicItems[indexPath.row];

        NSString *message = [NSString stringWithFormat:@"确定要删除 \"%@\" 吗？\n\n此操作不可撤销！", musicItem.displayName];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🗑️ 删除歌曲"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"删除"
                                                               style:UIAlertActionStyleDestructive
                                                             handler:^(UIAlertAction * _Nonnull action) {
            [self performDeleteMusicItem:musicItem atIndexPath:indexPath];
        }];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction * _Nonnull action) {
            [tableView setEditing:NO animated:YES];
        }];

        [alert addAction:cancelAction];
        [alert addAction:deleteAction];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)performDeleteMusicItem:(MusicItem *)musicItem atIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🗑️ 开始删除歌曲: %@", musicItem.displayName);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL success = [self.musicLibrary deleteMusicItem:musicItem error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self refreshMusicList];
                [self showToast:[NSString stringWithFormat:@"✅ 已删除 \"%@\"", musicItem.displayName]];
                NSLog(@"✅ 删除成功: %@", musicItem.displayName);
            } else {
                NSString *errorMessage = error ? error.localizedDescription : @"未知错误";
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"❌ 删除失败"
                                                                                    message:[NSString stringWithFormat:@"删除失败：%@", errorMessage]
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];

                NSLog(@"❌ 删除失败: %@ - %@", musicItem.displayName, errorMessage);
            }
        });
    });
}

- (void)showToast:(NSString *)message {
    UILabel *toastLabel = [[UILabel alloc] init];
    toastLabel.text = message;
    toastLabel.font = [UIFont systemFontOfSize:14];
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
    toastLabel.textAlignment = NSTextAlignmentCenter;
    toastLabel.numberOfLines = 0;
    toastLabel.layer.cornerRadius = 10;
    toastLabel.clipsToBounds = YES;

    CGSize textSize = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 80, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: toastLabel.font}
                                            context:nil].size;

    CGFloat width = textSize.width + 40;
    CGFloat height = textSize.height + 20;

    toastLabel.frame = CGRectMake((self.view.bounds.size.width - width) / 2,
                                  self.view.bounds.size.height - 150,
                                  width,
                                  height);
    toastLabel.alpha = 0;

    [self.view addSubview:toastLabel];

    [UIView animateWithDuration:0.3 animations:^{
        toastLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastLabel.alpha = 0;
            } completion:^(BOOL finished) {
                [toastLabel removeFromSuperview];
            }];
        });
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.searchBar resignFirstResponder];

    self.currentIndex = indexPath.row;

    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    [self.musicLibrary recordPlayForMusic:musicItem];
    [self updateAudioSelection];

    NSString *playPath = nil;

    NSLog(@"🎵 准备播放: fileName=%@, filePath=%@, decryptedPath=%@", musicItem.fileName, musicItem.filePath, musicItem.decryptedPath);

    if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
        playPath = musicItem.decryptedPath;
        NSLog(@"✅ 使用已解密文件播放: %@", playPath);
    } else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
        NSLog(@"🔓 检测到NCM文件，开始自动解密...");
        NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
        playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];

        if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
            NSLog(@"✅ 自动解密成功: %@", playPath);
        }
    } else if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
        playPath = musicItem.filePath;

        if ([[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            NSLog(@"✅ 使用完整路径播放: %@", playPath);
        } else {
            NSLog(@"❌ 文件不存在: %@，尝试从 Bundle 查找", playPath);
            playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
        }
    } else {
        playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
        NSLog(@"🎵 从 Bundle 播放: %@", playPath);
    }

    [self updateNowPlayingInfoImmediate];

    NSString *songName = musicItem.displayName ?: [musicItem.fileName stringByDeletingPathExtension];
    NSString *artist = musicItem.artist ?: @"";
    if (artist.length == 0 && songName.length > 0 && [songName containsString:@" - "]) {
        NSArray *parts = [songName componentsSeparatedByString:@" - "];
        if (parts.count >= 2) {
            artist = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            songName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }

    [self.player playWithFileName:playPath songName:songName artist:artist];
}

- (void)convertNCMFile:(MusicItem *)musicItem atIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🔄 开始转换 NCM 文件: %@", musicItem.fileName);

    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"⏳ 转换中"
                                                                          message:@"正在转换 NCM 文件，请稍候..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *fileURL = nil;
        NSString *sourcePath = nil;

        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            sourcePath = musicItem.filePath;
            if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
                fileURL = [NSURL fileURLWithPath:sourcePath];
                NSLog(@"✅ 找到导入的NCM文件: %@", sourcePath);
            }
        }

        if (!fileURL) {
            fileURL = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
            if (fileURL) {
                sourcePath = fileURL.path;
                NSLog(@"✅ 找到Bundle中的NCM文件: %@", sourcePath);
            }
        }

        if (!fileURL) {
            NSString *audioPath = [[NSBundle mainBundle] pathForResource:@"Audio" ofType:nil];
            if (audioPath) {
                sourcePath = [audioPath stringByAppendingPathComponent:musicItem.fileName];
                if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
                    fileURL = [NSURL fileURLWithPath:sourcePath];
                    NSLog(@"✅ 找到Audio目录中的NCM文件: %@", sourcePath);
                }
            }
        }

        if (!fileURL || !sourcePath) {
            NSLog(@"❌ 找不到NCM文件: fileName=%@, filePath=%@", musicItem.fileName, musicItem.filePath);
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingAlert dismissViewControllerAnimated:YES completion:^{
                    [self showAlert:@"❌ 错误" message:[NSString stringWithFormat:@"找不到文件: %@", musicItem.fileName]];
                }];
            });
            return;
        }

        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *outputFilename = [[musicItem.fileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp3"];
        NSString *outputPath = [documentsPath stringByAppendingPathComponent:outputFilename];

        NSError *error = nil;
        NSString *result = [NCMDecryptor decryptNCMFile:fileURL.path
                                             outputPath:outputPath
                                                  error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                if (result) {
                    NSLog(@"✅ NCM 转换成功: %@", result);

                    [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:result];
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];

                    NSLog(@"🎵 开始播放解密后的文件: %@", result);
                    NSString *songName = musicItem.displayName ?: [musicItem.fileName stringByDeletingPathExtension];
                    NSString *artist = musicItem.artist ?: @"";
                    [self.player playWithFileName:result songName:songName artist:artist];

                    [self showAlert:@"✅ 转换成功" message:[NSString stringWithFormat:@"已成功转换并开始播放: %@", musicItem.displayName ?: musicItem.fileName]];
                } else {
                    NSLog(@"❌ NCM 转换失败: %@", error.localizedDescription);
                    [self showAlert:@"❌ 转换失败" message:error.localizedDescription ?: @"未知错误"];
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }
            }];
        });
    });
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateAudioSelection {
    if (self.backgroundRingLayer) {
        self.backgroundRingLayer.strokeColor = [UIColor colorWithRed:arc4random() % 255 / 255.0
                                                               green:arc4random() % 255 / 255.0
                                                                blue:arc4random() % 255 / 255.0
                                                               alpha:1.0].CGColor;
    }

    if (self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
        NSString *songName = musicItem.displayName ?: musicItem.fileName;

        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
            NSLog(@"🖼️ 更新导入文件封面: %@", musicItem.filePath);
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
            NSLog(@"🖼️ 更新Bundle文件封面: %@", musicItem.fileName);
        }

        UIImage *image = [self musicImageWithMusicURL:fileUrl];

        if (image) {
            self.coverImageView.image = image;
            self.coverImageView.hidden = NO;
            self.vinylRecordView.hidden = YES;

            if (self.isShowingVinylRecord) {
                [self.vinylRecordView stopSpinning];
                self.isShowingVinylRecord = NO;

                [self.animationCoordinator addRotationViews:@[self.coverImageView]
                                                  rotations:@[@(6.0)]
                                                  durations:@[@(120.0)]
                                              rotationTypes:@[@(RotationTypeCounterClockwise)]];
            }

            [self.animationCoordinator updateParticleImage:image];
            NSLog(@"🖼️ 显示音乐封面");
        } else {
            self.coverImageView.hidden = YES;
            self.vinylRecordView.hidden = NO;
            self.isShowingVinylRecord = YES;

            [self.vinylRecordView regenerateAppearanceWithSongName:songName];

            if (self.player.isPlaying) {
                [self.vinylRecordView startSpinning];
            }

            NSLog(@"🎵 显示黑胶唱片动画（无封面）: %@", songName);
        }
    }
}

#pragma mark - File Metadata

- (UIImage *)musicImageWithMusicURL:(NSURL *)url {
    if (!url) {
        NSLog(@"⚠️ 无法获取封面：URL为空");
        return nil;
    }

    if ([url isFileURL] && [[url.path.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
        NSString *ncmPath = url.path;
        NSString *fileName = [ncmPath lastPathComponent];
        NSString *baseFileName = [fileName stringByDeletingPathExtension];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = paths.firstObject;
        NSArray *extensions = @[@"mp3", @"flac", @"m4a"];
        for (NSString *ext in extensions) {
            NSString *decryptedPath = [[documentsDirectory stringByAppendingPathComponent:baseFileName] stringByAppendingPathExtension:ext];
            if ([[NSFileManager defaultManager] fileExistsAtPath:decryptedPath]) {
                NSLog(@"🔄 NCM文件，从解密文件读取封面: %@", [decryptedPath lastPathComponent]);
                url = [NSURL fileURLWithPath:decryptedPath];
                break;
            }
        }
    }

    if ([url isFileURL]) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:url.path]) {
            NSLog(@"⚠️ 无法获取封面：文件不存在: %@", url.path);
            return nil;
        }

        UIImage *externalCover = [self loadExternalCoverForMusicFile:url.path];
        if (externalCover) {
            NSLog(@"✅ 使用外部封面文件: %@", url.path.lastPathComponent);
            return externalCover;
        }
    }

    NSData *data = nil;
    AVURLAsset *mp3Asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSLog(@"🔍 [封面读取] 文件: %@", url.path.lastPathComponent);

    for (NSString *format in [mp3Asset availableMetadataFormats]) {
        NSLog(@"   扫描格式: %@", format);

        for (AVMetadataItem *metadataItem in [mp3Asset metadataForFormat:format]) {
            if ([metadataItem.commonKey isEqualToString:@"artwork"]) {
                data = [metadataItem.value copyWithZone:nil];
                NSLog(@"   ✅ 找到封面 metadata (格式: %@)", format);
                break;
            }
        }

        if (data) {
            break;
        }
    }

    if (!data) {
        NSLog(@"⚠️ 无法获取封面：文件中没有封面数据: %@", url.path.lastPathComponent);
        return nil;
    }

    NSLog(@"✅ 成功提取封面数据 (%.0f KB): %@", (CGFloat)data.length / 1024.0, url.path.lastPathComponent);

    UIImage *image = [UIImage imageWithData:data];
    if (!image) {
        NSLog(@"⚠️ 警告：封面数据无法转换为UIImage");
        return nil;
    }

    NSLog(@"✅ 封面图片创建成功 (%.0fx%.0f)", image.size.width, image.size.height);
    return image;
}

- (UIImage *)loadExternalCoverForMusicFile:(NSString *)musicFilePath {
    if (musicFilePath.length == 0) {
        return nil;
    }

    NSString *baseFileName = [[musicFilePath lastPathComponent] stringByDeletingPathExtension];
    NSString *directory = [musicFilePath stringByDeletingLastPathComponent];
    NSArray *imageExtensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    NSArray *namingPatterns = @[@"%@_cover", @"%@"];

    for (NSString *pattern in namingPatterns) {
        NSString *fileName = [NSString stringWithFormat:pattern, baseFileName];
        for (NSString *ext in imageExtensions) {
            NSString *coverPath = [[directory stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:ext];
            if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath]) {
                UIImage *image = [UIImage imageWithContentsOfFile:coverPath];
                if (image) {
                    NSLog(@"🖼️ 找到外部封面: %@", [coverPath lastPathComponent]);
                    return image;
                }
            }
        }
    }

    return nil;
}

#pragma mark - UI Actions

- (void)categoryButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    MusicCategory selectedCategory = (MusicCategory)sender.tag;
    self.currentCategory = selectedCategory;

    for (UIButton *button in self.categoryButtons) {
        if (button.tag == selectedCategory) {
            button.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:0.9];
            button.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
            button.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } else {
            button.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.85];
            button.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.6].CGColor;
            button.transform = CGAffineTransformIdentity;
        }
    }

    [self refreshMusicList];

    NSLog(@"📂 切换分类: %@ (%ld 首)", [MusicLibraryManager nameForCategory:self.currentCategory], (long)self.displayedMusicItems.count);
}

- (void)reloadMusicLibraryButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    NSLog(@"🔄 开始重新扫描音乐库...");

    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在扫描"
                                                                          message:@"正在重新扫描音频文件..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.musicLibrary reloadMusicLibrary];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshMusicList];

            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                NSString *message = [NSString stringWithFormat:@"发现 %ld 首歌曲", (long)self.musicLibrary.totalMusicCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 扫描完成"
                                                                                      message:message
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];

                NSLog(@"✅ 音乐库重新加载完成: %ld 首歌曲", (long)self.musicLibrary.totalMusicCount);
            }];
        });
    });
}

- (void)importMusicButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    NSLog(@"📥 打开文件选择器导入音乐...");

    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        NSMutableArray *contentTypes = [NSMutableArray array];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"mp3"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"m4a"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"flac"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"wav"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"aac"]];

        UTType *ncmType = [UTType typeWithFilenameExtension:@"ncm"];
        if (ncmType) {
            [contentTypes addObject:ncmType];
        }

        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    } else {
        NSArray *audioTypes = @[
            @"public.audio",
            @"public.mp3",
            @"public.mpeg-4-audio",
            @"public.data",
            @"public.item"
        ];
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:audioTypes inMode:UIDocumentPickerModeImport];
    }

    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;

    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)clearAICacheButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    NSLog(@"🗑️ 准备清除 AI 缓存...");

    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"清除 AI 缓存"
                                                                          message:@"确定要清除所有 AI 音乐分析缓存吗？\n清除后，下次播放歌曲将重新进行 AI 分析。"
                                                                   preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [confirmAlert addAction:cancelAction];

    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"清除"
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [[MusicAIAnalyzer sharedAnalyzer] clearCache];

        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 清除成功"
                                                                              message:@"AI 缓存已清除，下次播放将重新分析"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [successAlert addAction:okAction];
        [self presentViewController:successAlert animated:YES completion:nil];

        NSLog(@"✅ AI 缓存清除完成");
    }];
    [confirmAlert addAction:confirmAction];

    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (void)aiSettingsButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    LLMAPISettings *settings = [LLMAPISettings sharedSettings];
    NSString *message = [NSString stringWithFormat:@"配置保存在 App 沙箱内，不会写进开源代码。\n当前模型：%@\n当前 Key：%@", settings.model, settings.maskedAPIKey];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🤖 AI 接口设置"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Base URL，例如 https://api.deepseek.com";
        textField.text = settings.baseURL;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.keyboardType = UIKeyboardTypeURL;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Model，例如 deepseek-chat";
        textField.text = settings.model;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"API Key";
        textField.text = settings.apiKey;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.secureTextEntry = YES;
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:cancelAction];

    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"保存"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
        NSString *baseURL = alert.textFields.count > 0 ? alert.textFields[0].text : @"";
        NSString *model = alert.textFields.count > 1 ? alert.textFields[1].text : @"";
        NSString *apiKey = alert.textFields.count > 2 ? alert.textFields[2].text : @"";

        NSURL *resolvedURL = [LLMAPISettings resolvedServiceURLForBaseURL:baseURL];
        if (!resolvedURL) {
            [self showAlert:@"❌ 保存失败" message:@"Base URL 无效，请检查后重新填写。"];
            return;
        }

        [[LLMAPISettings sharedSettings] updateWithBaseURL:baseURL
                                                     model:model
                                                    apiKey:apiKey];

        LLMAPISettings *updatedSettings = [LLMAPISettings sharedSettings];
        NSString *resultMessage = [NSString stringWithFormat:@"AI 接口配置已保存到 App 沙箱。\nBase URL：%@\nModel：%@\nAPI Key：%@",
                                   updatedSettings.baseURL,
                                   updatedSettings.model,
                                   updatedSettings.maskedAPIKey];
        [self showAlert:@"✅ 保存成功" message:resultMessage];
    }];
    [alert addAction:saveAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sortButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"排序方式"
                                                                   message:@"选择排序方式"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"按名称 A-Z"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByName;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"按艺术家 A-Z"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByArtist;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"按播放次数（最多）"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByPlayCount;
        self.sortAscending = NO;
        [self refreshMusicList];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"按添加日期（最新）"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByDate;
        self.sortAscending = NO;
        [self refreshMusicList];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"按时长（短到长）"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByDuration;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"按文件大小（小到大）"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByFileSize;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self refreshMusicList];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self refreshMusicList];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    [self refreshMusicList];
}

- (void)dismissKeyboard {
    [self.searchBar resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self.searchBar resignFirstResponder];
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSLog(@"📥 用户选择了 %ld 个文件", (long)urls.count);

    if (urls.count == 0) {
        return;
    }

    NSURL *firstURL = urls.firstObject;
    NSString *fileExtension = [firstURL.pathExtension lowercaseString];

    if ([fileExtension isEqualToString:@"lrc"]) {
        if (urls.count == 1) {
            [self handleSingleLRCImport:firstURL];
        } else {
            [self handleBatchLRCImport:urls];
        }
        return;
    }

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"正在导入"
                                                                            message:@"正在复制文件到音乐库..."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *targetDirectory = [MusicLibraryManager cloudDownloadDirectory];

        if (![fileManager fileExistsAtPath:targetDirectory]) {
            NSError *createError = nil;
            [fileManager createDirectoryAtPath:targetDirectory
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&createError];
            if (createError) {
                NSLog(@"❌ 创建目标目录失败: %@", createError.localizedDescription);
            }
        }

        NSInteger successCount = 0;
        NSInteger failureCount = 0;

        for (NSURL *sourceURL in urls) {
            BOOL didStartAccessing = [sourceURL startAccessingSecurityScopedResource];

            @try {
                NSString *fileName = sourceURL.lastPathComponent;
                NSString *targetPath = [targetDirectory stringByAppendingPathComponent:fileName];

                if ([fileManager fileExistsAtPath:targetPath]) {
                    NSString *baseName = [fileName stringByDeletingPathExtension];
                    NSString *extension = [fileName pathExtension];
                    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
                    fileName = [NSString stringWithFormat:@"%@_%ld.%@", baseName, (long)timestamp, extension];
                    targetPath = [targetDirectory stringByAppendingPathComponent:fileName];
                }

                NSError *copyError = nil;
                BOOL success = [fileManager copyItemAtURL:sourceURL toURL:[NSURL fileURLWithPath:targetPath] error:&copyError];

                if (success) {
                    successCount++;
                    NSLog(@"✅ 成功导入: %@", fileName);
                } else {
                    failureCount++;
                    NSLog(@"❌ 导入失败: %@ - %@", fileName, copyError.localizedDescription);
                }
            }
            @finally {
                if (didStartAccessing) {
                    [sourceURL stopAccessingSecurityScopedResource];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (successCount > 0) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self.musicLibrary reloadMusicLibrary];

                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self refreshMusicList];

                            NSString *message = nil;
                            if (failureCount > 0) {
                                message = [NSString stringWithFormat:@"成功导入 %ld 首\n失败 %ld 首", (long)successCount, (long)failureCount];
                            } else {
                                message = [NSString stringWithFormat:@"成功导入 %ld 首音乐文件", (long)successCount];
                            }

                            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 导入完成"
                                                                                                  message:message
                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                            [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                            [self presentViewController:successAlert animated:YES completion:nil];

                            NSLog(@"✅ 导入完成: 成功 %ld 首, 失败 %ld 首", (long)successCount, (long)failureCount);
                        });
                    });
                } else {
                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"❌ 导入失败"
                                                                                         message:@"所有文件导入失败，请检查文件格式"
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:errorAlert animated:YES completion:nil];

                    NSLog(@"❌ 导入失败: 所有文件导入失败");
                }
            }];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"📥 用户取消了文件选择");
}

@end
