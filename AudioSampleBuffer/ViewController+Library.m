#import "ViewController+Private.h"

#import "AudioFileFormats.h"
#import "AudioPlayCell.h"
#import "LLMAPISettings.h"
#import "LyricsManager.h"
#import "MusicAIAnalyzer.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <Photos/Photos.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static NSString * const kBackgroundMediaDirectoryName = @"BackgroundMedia";
static NSString * const kBackgroundMediaManifestFileName = @"background_media_items.dat";

@implementation BackgroundMediaItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)itemWithFilePath:(NSString *)filePath kind:(BackgroundMediaKind)kind displayName:(NSString *)displayName {
    BackgroundMediaItem *item = [[BackgroundMediaItem alloc] init];
    item.identifier = [[NSUUID UUID] UUIDString];
    item.filePath = [filePath copy];
    item.kind = kind;
    item.displayName = displayName.length > 0 ? [displayName copy] : [filePath lastPathComponent];
    item.addedDate = [NSDate date];
    return item;
}

- (NSString *)kindDisplayName {
    return self.kind == BackgroundMediaKindLivePhoto ? @"Live Photo" : @"视频";
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.identifier forKey:@"identifier"];
    [coder encodeObject:self.displayName forKey:@"displayName"];
    [coder encodeObject:self.filePath forKey:@"filePath"];
    [coder encodeInteger:self.kind forKey:@"kind"];
    [coder encodeObject:self.addedDate forKey:@"addedDate"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _identifier = [coder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
        _displayName = [coder decodeObjectOfClass:[NSString class] forKey:@"displayName"];
        _filePath = [coder decodeObjectOfClass:[NSString class] forKey:@"filePath"];
        _kind = [coder decodeIntegerForKey:@"kind"];
        _addedDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"addedDate"] ?: [NSDate date];
    }
    return self;
}

@end

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
    if (tableView == self.backgroundMediaTableView) {
        return self.backgroundMediaItems.count;
    }
    return self.displayedMusicItems.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.backgroundMediaTableView) {
        return 62;
    }
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.backgroundMediaTableView) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BackgroundMediaCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"BackgroundMediaCell"];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = [UIColor whiteColor];
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            UIView *selectedView = [[UIView alloc] init];
            selectedView.backgroundColor = [UIColor colorWithRed:0.18 green:0.42 blue:0.75 alpha:0.28];
            cell.selectedBackgroundView = selectedView;
        }

        BackgroundMediaItem *item = self.backgroundMediaItems[indexPath.row];
        cell.textLabel.text = item.displayName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [item kindDisplayName], item.addedDate.description.length > 10 ? [item.addedDate.description substringToIndex:10] : @""];
        cell.accessoryType = [item.identifier isEqualToString:self.selectedBackgroundMediaItem.identifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.tintColor = [UIColor colorWithRed:0.35 green:0.72 blue:1.0 alpha:1.0];
        return cell;
    }

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
    if (tableView == self.backgroundMediaTableView) {
        return nil;
    }

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
    if (tableView == self.backgroundMediaTableView) {
        return YES;
    }

    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    BOOL isBundleFile = ![musicItem.filePath hasPrefix:@"/var/mobile"] &&
                        ![musicItem.filePath hasPrefix:@"/Users"] &&
                        ![musicItem.filePath containsString:@"Documents"];
    return !isBundleFile;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.backgroundMediaTableView) {
        if (editingStyle == UITableViewCellEditingStyleDelete) {
            BackgroundMediaItem *item = self.backgroundMediaItems[indexPath.row];
            NSError *error = nil;
            if ([[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:item.filePath error:&error];
            }
            [self.backgroundMediaItems removeObjectAtIndex:indexPath.row];
            if ([self.selectedBackgroundMediaItem.identifier isEqualToString:item.identifier]) {
                self.selectedBackgroundMediaItem = self.backgroundMediaItems.firstObject;
                self.backgroundMediaPreviewColor = [self dominantColorForBackgroundMediaItem:self.selectedBackgroundMediaItem];
                if (self.isBackgroundMediaEffectActive) {
                    [self playSelectedBackgroundMediaIfNeeded];
                }
            }
            [self persistBackgroundMediaItems];
            [self.backgroundMediaTableView reloadData];
            self.backgroundMediaEmptyLabel.hidden = self.backgroundMediaItems.count > 0;
            if (error) {
                NSLog(@"⚠️ 删除背景媒体文件失败: %@", error.localizedDescription);
            }
        }
        return;
    }

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
    if (tableView == self.backgroundMediaTableView) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        self.selectedBackgroundMediaItem = self.backgroundMediaItems[indexPath.row];
        self.backgroundMediaPreviewColor = [self dominantColorForBackgroundMediaItem:self.selectedBackgroundMediaItem];
        [self persistBackgroundMediaItems];
        [self.backgroundMediaTableView reloadData];

        if (!self.isBackgroundMediaEffectActive) {
            self.isBackgroundMediaEffectActive = YES;
            [self stopBackgroundMediaPlayback];
        }
        [self playSelectedBackgroundMediaIfNeeded];
        [self updateAudioSelection];
        [self bringControlButtonsToFront];
        [self refreshSpectrumAdaptiveThemeIfNeeded];
        [self updateSpectrumLiveEditingAvailability];
        [self toggleBackgroundMediaPanel:NO animated:YES];
        return;
    }

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

    if (self.isBackgroundMediaEffectActive) {
        return;
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
            self.coverImageView.hidden = self.isBackgroundMediaEffectActive;
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
            self.vinylRecordView.hidden = self.isBackgroundMediaEffectActive;
            self.isShowingVinylRecord = !self.isBackgroundMediaEffectActive;

            [self.vinylRecordView regenerateAppearanceWithSongName:songName];

            if (!self.isBackgroundMediaEffectActive && self.player.isPlaying) {
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

#pragma mark - Background Media Library

- (NSString *)backgroundMediaDirectoryPath {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documentsPath stringByAppendingPathComponent:kBackgroundMediaDirectoryName];
}

- (NSString *)backgroundMediaManifestPath {
    return [[self backgroundMediaDirectoryPath] stringByAppendingPathComponent:kBackgroundMediaManifestFileName];
}

- (void)ensureBackgroundMediaDirectoryExists {
    NSString *directory = [self backgroundMediaDirectoryPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"❌ 创建背景媒体目录失败: %@", error.localizedDescription);
        }
    }
}

- (void)reloadBackgroundMediaLibrary {
    [self ensureBackgroundMediaDirectoryExists];

    NSData *data = [NSData dataWithContentsOfFile:[self backgroundMediaManifestPath]];
    NSArray<BackgroundMediaItem *> *items = nil;
    if (data) {
        NSSet *classes = [NSSet setWithObjects:[NSArray class], [BackgroundMediaItem class], [NSString class], [NSDate class], nil];
        items = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
    }

    self.backgroundMediaItems = items ? [items mutableCopy] : [NSMutableArray array];
    NSIndexSet *missingIndexes = [self.backgroundMediaItems indexesOfObjectsPassingTest:^BOOL(BackgroundMediaItem *item, NSUInteger idx, BOOL *stop) {
        return ![[NSFileManager defaultManager] fileExistsAtPath:item.filePath];
    }];
    if (missingIndexes.count > 0) {
        [self.backgroundMediaItems removeObjectsAtIndexes:missingIndexes];
        [self persistBackgroundMediaItems];
    }

    NSString *selectedID = [[NSUserDefaults standardUserDefaults] stringForKey:@"SelectedBackgroundMediaItemID"];
    self.selectedBackgroundMediaItem = nil;
    for (BackgroundMediaItem *item in self.backgroundMediaItems) {
        if ([item.identifier isEqualToString:selectedID]) {
            self.selectedBackgroundMediaItem = item;
            break;
        }
    }
    if (!self.selectedBackgroundMediaItem) {
        self.selectedBackgroundMediaItem = self.backgroundMediaItems.firstObject;
    }
    self.backgroundMediaPreviewColor = [self dominantColorForBackgroundMediaItem:self.selectedBackgroundMediaItem];

    [self.backgroundMediaTableView reloadData];
    self.backgroundMediaEmptyLabel.hidden = self.backgroundMediaItems.count > 0;
    [self refreshBackgroundMediaButtonState];
}

- (BOOL)isBackgroundMediaEnabled {
    // Persist across app launches; disabled automatically when no items.
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"BackgroundMediaEnabled"];
}

- (void)setBackgroundMediaEnabled:(BOOL)enabled {
    BOOL hasItems = (self.backgroundMediaItems.count > 0);
    BOOL resolvedEnabled = (enabled && hasItems);

    [[NSUserDefaults standardUserDefaults] setBool:resolvedEnabled forKey:@"BackgroundMediaEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (resolvedEnabled) {
        // Ensure the visual effect state flips into background-media mode.
        if (self.visualEffectManager.currentEffectType != VisualEffectTypeUserMediaBackground) {
            [self.visualEffectManager setCurrentEffect:VisualEffectTypeUserMediaBackground animated:YES];
        }
        self.backgroundMediaPreviewColor = [self dominantColorForBackgroundMediaItem:self.selectedBackgroundMediaItem];
        [self updateBackgroundMediaEffectStateForEffect:VisualEffectTypeUserMediaBackground];
        [self refreshSpectrumAdaptiveThemeIfNeeded];
    } else {
        // 关闭背景媒体时，强制关闭律动效果（避免残留rate/震动）
        [self setBackgroundRhythmEnabled:NO];
        // If we are currently on the background-media effect, switch back to a safe default.
        if (self.visualEffectManager.currentEffectType == VisualEffectTypeUserMediaBackground) {
            [self.visualEffectManager setCurrentEffect:VisualEffectTypeNeonGlow animated:YES];
        }
        [self updateBackgroundMediaEffectStateForEffect:self.visualEffectManager.currentEffectType];
    }

    [self refreshBackgroundMediaButtonState];
    [self updateSpectrumLiveEditingAvailability];
}

- (void)backgroundMediaRhythmButtonTapped:(UIButton *)sender {
    if (self.backgroundMediaItems.count == 0) {
        [self showAlert:@"没有可用背景媒体" message:@"请先点击“导入”添加视频或 Live Photo。"];
        [self setBackgroundRhythmEnabled:NO];
        return;
    }

    if (![self isBackgroundMediaEnabled]) {
        [self showAlert:@"请先开启背景媒体" message:@"开启背景媒体后，才能使用律动效果。"];
        [self setBackgroundRhythmEnabled:NO];
        return;
    }

    [self setBackgroundRhythmEnabled:!self.isBackgroundRhythmEnabled];
}

- (void)backgroundMediaRhythmRateSliderChanged:(UISlider *)sender {
    // 重新映射为 "震颤强度"：0..1
    // 旧的 rate 调速废弃（视频始终 1.0× 播放），这里只作为整体效果强度
    CGFloat span = sender.maximumValue - sender.minimumValue;
    CGFloat t = 0.5;
    if (span > 0.0001) {
        t = (sender.value - sender.minimumValue) / span;
    }
    t = MAX(0.0, MIN(t, 1.0));
    // 仍写回 baseRate/maxRate 兼容老属性，但仅用其映射强度（在 tick 中读 rateT=baseRate-1 区间）
    self.backgroundRhythmBaseRate = 1.0;
    self.backgroundRhythmMaxRate = 1.0 + t;
    [self refreshBackgroundMediaButtonState];
}

- (void)backgroundMediaRhythmShakeSliderChanged:(UISlider *)sender {
    // "色散" slider：控制色彩蒙版的 alpha 上限和位移上限
    // 注意：实际效果是有色蒙版叠加 + 蒙版位移，不是 RGB 通道分离（避免白闪刺眼）
    CGFloat t = MAX(0.0, MIN(sender.value, 1.0));
    self.backgroundRhythmShakeIntensity = t;
    self.backgroundRhythmColorMaskMaxAlpha = (CGFloat)(0.22 * t);   // 0..0.22
    self.backgroundRhythmColorMaskShiftMax = (CGFloat)(8.0 * t);    // 0..8 px

    [self syncRhythmColorMaskInHierarchy];
    [self refreshBackgroundMediaButtonState];
}

// 把蒙版 view 安装/移除到视图层级。slider=0 → 完全移除（不残留）
- (void)syncRhythmColorMaskInHierarchy {
    if (!self.isBackgroundRhythmEnabled || self.backgroundRhythmColorMaskMaxAlpha < 0.005) {
        if (self.backgroundRhythmColorMaskView.superview) {
            [self.backgroundRhythmColorMaskView removeFromSuperview];
        }
        self.backgroundRhythmColorMaskIntensity = 0.0;
        self.backgroundRhythmColorMaskOffset = CGPointZero;
        return;
    }
    if (!self.backgroundRhythmColorMaskView) {
        UIView *mask = [[UIView alloc] initWithFrame:self.view.bounds];
        mask.backgroundColor = [UIColor colorWithRed:0.95 green:0.20 blue:0.30 alpha:1.0];
        mask.alpha = 0.0;
        mask.userInteractionEnabled = NO;
        mask.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundRhythmColorMaskView = mask;
    }
    if (self.backgroundRhythmColorMaskView.superview != self.view) {
        // 蒙版在视频之上、闪屏/UI 之下；用 index 0 与 flashView 一起在最底层
        [self.view insertSubview:self.backgroundRhythmColorMaskView atIndex:0];
    }
    self.backgroundRhythmColorMaskView.frame = self.view.bounds;
    self.backgroundRhythmColorMaskView.hidden = NO;
}

- (void)setBackgroundRhythmEnabled:(BOOL)enabled {
    BOOL resolvedEnabled = enabled;
    if (!self.isBackgroundMediaEffectActive || ![self isBackgroundMediaEnabled]) {
        resolvedEnabled = NO;
    }

    self.isBackgroundRhythmEnabled = resolvedEnabled;

    if (self.backgroundRhythmBaseRate <= 0.0) self.backgroundRhythmBaseRate = 1.0;
    if (self.backgroundRhythmMaxRate <= 0.0) self.backgroundRhythmMaxRate = 1.4;
    if (self.backgroundRhythmShakeIntensity <= 0.0) self.backgroundRhythmShakeIntensity = 0.55;
    if (self.backgroundRhythmRotationDir == 0.0) self.backgroundRhythmRotationDir = 1.0;
    if (self.backgroundRhythmBeatPeriod <= 0.0) self.backgroundRhythmBeatPeriod = 0.50;

    if (!resolvedEnabled) {
        [self.backgroundRhythmDisplayLink invalidate];
        self.backgroundRhythmDisplayLink = nil;
        self.backgroundRhythmPulse = 0.0f;
        self.backgroundRhythmSmoothedBass = 0.0f;
        self.backgroundRhythmLastBeatTime = 0;
        self.backgroundRhythmShakeVelocity = CGPointZero;
        self.backgroundRhythmShakeOffset = CGPointZero;
        self.backgroundRhythmScalePulse = 0.0;
        self.backgroundRhythmRotationPulse = 0.0;
        self.backgroundRhythmFlashIntensity = 0.0;
        self.backgroundRhythmBeatCounter = 0;
        self.backgroundRhythmLoopAnchorSeconds = 0.0;
        [self.backgroundRhythmLastSpectrum removeAllObjects];
        [self.backgroundRhythmFluxHistory removeAllObjects];
        self.backgroundRhythmFluxHistoryIndex = 0;

        self.backgroundRhythmFilterIntensity = 0.0f;
        self.backgroundRhythmFilterShiftMax = 0.0f;
        self.backgroundRhythmFilterStrongMix = 0.0f;
        self.backgroundRhythmFilterMotionBlur = 0.0f;

        self.backgroundRhythmColorMaskIntensity = 0.0;
        self.backgroundRhythmColorMaskOffset = CGPointZero;
        if (self.backgroundRhythmColorMaskView.superview) {
            [self.backgroundRhythmColorMaskView removeFromSuperview];
        }

        if (self.backgroundVideoPlayer && self.isBackgroundMediaEffectActive) {
            [self.backgroundVideoPlayer setRate:1.0];
        }
        if (self.backgroundVideoLayer) {
            self.backgroundVideoLayer.affineTransform = CGAffineTransformIdentity;
        }
        if (self.backgroundRhythmFlashView.superview) {
            [self.backgroundRhythmFlashView removeFromSuperview];
        }
        if (self.backgroundRhythmFlashView) {
            self.backgroundRhythmFlashView.alpha = 0.0;
            self.backgroundRhythmFlashView.hidden = YES;
        }
    } else {
        if (!self.backgroundRhythmLastSpectrum) self.backgroundRhythmLastSpectrum = [NSMutableArray array];
        if (!self.backgroundRhythmFluxHistory) self.backgroundRhythmFluxHistory = [NSMutableArray array];

        // 滤镜初始为 0
        self.backgroundRhythmFilterIntensity = 0.0f;
        self.backgroundRhythmFilterStrongMix = 0.0f;
        self.backgroundRhythmFilterShiftMax = 0.0f;

        // 色散 slider → 蒙版 alpha 上限 / 位移上限
        CGFloat shakeT = MAX(0.0, MIN(self.backgroundRhythmShakeIntensity, 1.0));
        if (self.backgroundMediaRhythmShakeSlider) {
            shakeT = MAX(0.0, MIN(self.backgroundMediaRhythmShakeSlider.value, 1.0));
            self.backgroundRhythmShakeIntensity = shakeT;
        }
        self.backgroundRhythmColorMaskMaxAlpha = (CGFloat)(0.22 * shakeT);
        self.backgroundRhythmColorMaskShiftMax = (CGFloat)(8.0 * shakeT);
        self.backgroundRhythmColorMaskIntensity = 0.0;
        self.backgroundRhythmColorMaskOffset = CGPointZero;
        [self syncRhythmColorMaskInHierarchy];

        // 同步当前闪屏 slider 值到 maxAlpha；slider 为 0 时不创建/插入闪屏层
        self.backgroundRhythmFlashMaxAlpha = 0.0;
        if (self.backgroundMediaRhythmFlashSlider) {
            CGFloat v = MAX(0.0, MIN(self.backgroundMediaRhythmFlashSlider.value, 1.0));
            self.backgroundRhythmFlashMaxAlpha = (CGFloat)(0.55 * v);
        }
        if (self.backgroundRhythmFlashMaxAlpha >= 0.005) {
            if (!self.backgroundRhythmFlashView) {
                UIView *flash = [[UIView alloc] initWithFrame:self.view.bounds];
                flash.backgroundColor = [UIColor whiteColor];
                flash.alpha = 0.0;
                flash.userInteractionEnabled = NO;
                flash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                self.backgroundRhythmFlashView = flash;
            }
            if (self.backgroundRhythmFlashView.superview != self.view) {
                // 视频是 CALayer 在 view.layer 的 sublayer 0；
                // 把 flash view 插到 subview index 0（在 video layer 之上、其它 UI 之下）
                [self.view insertSubview:self.backgroundRhythmFlashView atIndex:0];
            }
            self.backgroundRhythmFlashView.frame = self.view.bounds;
            self.backgroundRhythmFlashView.hidden = NO;
            self.backgroundRhythmFlashView.alpha = 0.0;
        } else if (self.backgroundRhythmFlashView.superview) {
            [self.backgroundRhythmFlashView removeFromSuperview];
        }

        if (!self.backgroundRhythmDisplayLink) {
            self.backgroundRhythmDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(backgroundRhythmTick:)];
            if (@available(iOS 10.0, *)) {
                self.backgroundRhythmDisplayLink.preferredFramesPerSecond = 60;
            }
            [self.backgroundRhythmDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
    }

    [self refreshBackgroundMediaButtonState];
}

#pragma mark - Rhythm: Motionleap-style CIFilter pipeline

// 兼容旧调用：色散不再走 CIFilter，固定返回 0
- (float)rhythmComputeShiftMaxPixels {
    return 0.0f;
}

// 滤镜核心：仅在加速期注入 motion blur；不做任何颜色处理（避免白闪刺眼）
- (CIImage *)applyRhythmFilterToImage:(CIImage *)source
                            intensity:(float)intensity
                          shiftPixels:(float)shiftMax
                            strongMix:(float)strongMix
                           motionBlur:(float)motionBlur {
    if (source == nil) return source;
    (void)intensity; (void)shiftMax; (void)strongMix;

    if (motionBlur < 0.02f) {
        return source;
    }

    float radius = motionBlur * 18.0f;
    CGFloat angle = (self.backgroundRhythmShakeAxis == 1) ? (M_PI / 2.0) : 0.0;
    CIFilter *mb = [CIFilter filterWithName:@"CIMotionBlur"];
    if (!mb) return source;
    [mb setValue:source forKey:kCIInputImageKey];
    [mb setValue:@(radius) forKey:@"inputRadius"];
    [mb setValue:@(angle) forKey:@"inputAngle"];
    CIImage *blurred = mb.outputImage;
    if (!blurred) return source;
    return [blurred imageByCroppingToRect:source.extent];
}

// 把滤镜挂到 AVPlayerItem 上：每帧 GPU 处理一次
- (void)installRhythmVideoCompositionOnPlayerItem:(AVPlayerItem *)playerItem asset:(AVAsset *)asset {
    if (!playerItem || !asset) return;

    __weak typeof(self) weakSelf = self;
    AVMutableVideoComposition *vc =
        [AVMutableVideoComposition videoCompositionWithAsset:asset
                                applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest * _Nonnull request) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        CIImage *src = request.sourceImage;
        if (!strongSelf || !src) {
            [request finishWithImage:(src ?: [CIImage emptyImage]) context:nil];
            return;
        }
        float blur = strongSelf.backgroundRhythmFilterMotionBlur;

        if (blur < 0.02f) {
            [request finishWithImage:src context:nil];
            return;
        }

        CIImage *result = [strongSelf applyRhythmFilterToImage:src
                                                     intensity:0.0f
                                                   shiftPixels:0.0f
                                                     strongMix:0.0f
                                                    motionBlur:blur];
        [request finishWithImage:(result ?: src) context:nil];
    }];

    playerItem.videoComposition = vc;
}

#pragma mark - Rhythm: Beat Detection (spectral flux + adaptive threshold)

- (float)bassEnergyFromSpectrum:(NSArray<NSNumber *> *)spectrum {
    if (spectrum.count == 0) return 0.0f;
    NSUInteger count = MIN(spectrum.count, (NSUInteger)80);
    if (count == 0) return 0.0f;

    float bass = 0.0f;
    NSUInteger bassBins = MIN((NSUInteger)17, count);
    for (NSUInteger i = 0; i < bassBins; i++) {
        bass += (float)[spectrum[i] doubleValue];
    }
    bass /= (float)bassBins;
    return fminf(1.0f, fmaxf(0.0f, bass * 6.0f));
}

// 返回 (flux, isBeat)；flux 写入 outFlux，是否鼓点写入 outIsBeat。
- (void)detectBeatFromSpectrum:(NSArray<NSNumber *> *)spectrum
                         atTime:(CFTimeInterval)now
                        outFlux:(float *)outFlux
                       outIsBeat:(BOOL *)outIsBeat {
    if (outFlux) *outFlux = 0.0f;
    if (outIsBeat) *outIsBeat = NO;

    if (spectrum.count == 0) return;

    NSUInteger N = MIN(spectrum.count, (NSUInteger)64);

    // 初始化 last-spectrum
    if (self.backgroundRhythmLastSpectrum.count != N) {
        [self.backgroundRhythmLastSpectrum removeAllObjects];
        for (NSUInteger i = 0; i < N; i++) {
            [self.backgroundRhythmLastSpectrum addObject:@(0.0)];
        }
    }

    // 计算 spectral flux（只累正向能量增量），低频强加权
    float flux = 0.0f;
    for (NSUInteger i = 0; i < N; i++) {
        float curr = (float)[spectrum[i] doubleValue];
        float prev = (float)[self.backgroundRhythmLastSpectrum[i] doubleValue];
        float diff = curr - prev;
        if (diff > 0.0f) {
            float w = (i < 10) ? 2.4f : ((i < 24) ? 1.0f : 0.25f);
            flux += diff * w;
        }
        self.backgroundRhythmLastSpectrum[i] = @(curr);
    }
    flux /= (float)N;

    // 滑动窗口（最近 ~32 帧 ~0.5s）
    const NSUInteger HIST_LEN = 32;
    if (self.backgroundRhythmFluxHistory.count < HIST_LEN) {
        [self.backgroundRhythmFluxHistory addObject:@(flux)];
    } else {
        NSUInteger idx = self.backgroundRhythmFluxHistoryIndex % HIST_LEN;
        self.backgroundRhythmFluxHistory[idx] = @(flux);
        self.backgroundRhythmFluxHistoryIndex++;
    }

    // 自适应阈值：均值 + k*std
    NSUInteger histCount = self.backgroundRhythmFluxHistory.count;
    if (histCount < 8) {
        if (outFlux) *outFlux = flux;
        return;
    }
    float mean = 0.0f;
    for (NSNumber *n in self.backgroundRhythmFluxHistory) mean += n.floatValue;
    mean /= (float)histCount;
    float varSum = 0.0f;
    for (NSNumber *n in self.backgroundRhythmFluxHistory) {
        float d = n.floatValue - mean;
        varSum += d * d;
    }
    float stdv = sqrtf(varSum / (float)histCount);

    // 阈值：基线 + 1.45 std + 一个绝对最小值
    float threshold = mean + 1.45f * stdv + 0.0008f;

    // 节拍最小间隔：根据预估的 BPM 自适应（下限 ~140ms）
    CFTimeInterval minBeatInterval = 0.16;
    if (self.backgroundRhythmBeatPeriod > 0.30) {
        minBeatInterval = MAX(0.16, self.backgroundRhythmBeatPeriod * 0.55);
    }

    BOOL isBeat = (flux > threshold) && (now - self.backgroundRhythmLastBeatTime > minBeatInterval);

    if (outFlux) *outFlux = flux;
    if (outIsBeat) *outIsBeat = isBeat;
}

#pragma mark - Rhythm: Beat handling (Motionleap-style)

- (void)rhythmHandleBeatAtTime:(CFTimeInterval)now bass:(float)bass {
    // BPM 估计：用相邻 beat 间隔做低通融合（合理区间 ~55..220 BPM）
    CFTimeInterval interval = now - self.backgroundRhythmLastBeatTime;
    if (interval > 0.27 && interval < 1.10) {
        if (self.backgroundRhythmBeatPeriod > 0) {
            self.backgroundRhythmBeatPeriod = 0.65 * self.backgroundRhythmBeatPeriod + 0.35 * interval;
        } else {
            self.backgroundRhythmBeatPeriod = interval;
        }
    }

    self.backgroundRhythmLastBeatTime = now;
    self.backgroundRhythmBeatCounter += 1;

    // 强弱拍判定：4 拍循环里第 1 拍最强；其它叠 bass 能量
    BOOL strongDownbeat = (self.backgroundRhythmBeatCounter % 4 == 1);
    BOOL midBeat        = (self.backgroundRhythmBeatCounter % 2 == 1);
    float strongMix = strongDownbeat ? 1.0f : (midBeat ? 0.65f : 0.40f);
    float bassMix = MIN(1.0f, MAX(0.0f, bass));
    strongMix = MIN(1.0f, 0.55f * strongMix + 0.45f * bassMix);

    // "震颤" slider（rate slider）→ 物理 scale 脉冲 + 短暂快进幅度
    CGFloat rateT = 0.6;
    if (self.backgroundMediaRhythmRateSlider) {
        CGFloat span = self.backgroundMediaRhythmRateSlider.maximumValue - self.backgroundMediaRhythmRateSlider.minimumValue;
        if (span > 0) {
            rateT = (self.backgroundMediaRhythmRateSlider.value - self.backgroundMediaRhythmRateSlider.minimumValue) / span;
        }
    }
    rateT = MAX(0.0, MIN(rateT, 1.0));

    // 读取色散 / 闪屏 slider 当前值（用于严格门控）
    float shakeT = (float)MAX(0.0, MIN(self.backgroundRhythmShakeIntensity, 1.0));
    float flashT = self.backgroundMediaRhythmFlashSlider ?
        (float)MAX(0.0, MIN(self.backgroundMediaRhythmFlashSlider.value, 1.0)) : 0.0f;

    // **关键**：每个视觉通道严格乘以对应 slider，slider=0 → 通道完全关闭
    // 色散 slider 控制：彩色蒙版 alpha 脉冲 + 蒙版位移目标
    if (shakeT >= 0.02f && self.backgroundRhythmColorMaskMaxAlpha >= 0.005) {
        // beat 切色：在一组冷暖循环色中递进（不要白色，避免视觉刺激）
        self.backgroundRhythmColorMaskHueIndex = (self.backgroundRhythmColorMaskHueIndex + 1) % 6;
        UIColor *c = nil;
        switch (self.backgroundRhythmColorMaskHueIndex) {
            case 0: c = [UIColor colorWithRed:0.95 green:0.20 blue:0.30 alpha:1.0]; break; // 红
            case 1: c = [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0]; break; // 蓝
            case 2: c = [UIColor colorWithRed:0.95 green:0.50 blue:0.10 alpha:1.0]; break; // 橙
            case 3: c = [UIColor colorWithRed:0.30 green:0.85 blue:0.55 alpha:1.0]; break; // 青绿
            case 4: c = [UIColor colorWithRed:0.75 green:0.25 blue:0.85 alpha:1.0]; break; // 紫
            default:c = [UIColor colorWithRed:0.95 green:0.80 blue:0.20 alpha:1.0]; break; // 黄
        }
        if (self.backgroundRhythmColorMaskView) self.backgroundRhythmColorMaskView.backgroundColor = c;

        // alpha 脉冲：beat 上为 1，tick 中按帧衰减
        self.backgroundRhythmColorMaskIntensity = (CGFloat)(0.65 + 0.35 * (CGFloat)strongMix);

        // 位移目标：单轴方向，长度 = colorMaskShiftMax * (0.5..1) * intensity
        CGFloat dir = (self.backgroundRhythmColorMaskHueIndex % 2 == 0) ? 1.0 : -1.0;
        CGFloat amp = self.backgroundRhythmColorMaskShiftMax * (0.55 + 0.45 * (CGFloat)strongMix);
        if (self.backgroundRhythmShakeAxis == 0) {
            self.backgroundRhythmColorMaskOffset = CGPointMake(dir * amp, 0);
        } else {
            self.backgroundRhythmColorMaskOffset = CGPointMake(0, dir * amp);
        }
    }
    self.backgroundRhythmFilterIntensity = 0.0f;     // CIFilter 不再做色散
    self.backgroundRhythmFilterShiftMax  = 0.0f;
    self.backgroundRhythmFilterStrongMix = strongMix;

    // 震颤 slider 控制：物理 scale 脉冲、运动模糊、单轴抖动
    self.backgroundRhythmScalePulse    = (CGFloat)rateT * (0.30 + 0.70 * (CGFloat)rateT);
    self.backgroundRhythmRotationDir   = -self.backgroundRhythmRotationDir;
    if (self.backgroundRhythmRotationDir == 0) self.backgroundRhythmRotationDir = 1.0;
    self.backgroundRhythmRotationPulse = self.backgroundRhythmRotationDir;
    self.backgroundRhythmPulse         = (float)rateT;

    // 单轴抖动方向（rateT=0 时方向无意义但属性还是写一下）
    if (strongDownbeat) {
        self.backgroundRhythmShakeAxis = 1;
    } else {
        self.backgroundRhythmShakeAxis = 1 - self.backgroundRhythmShakeAxis;
    }

    // 运动模糊（独立于震颤 slider）：律动开 = 加速期一定有运动模糊
    self.backgroundRhythmFilterMotionBlur = MIN(1.0f, 0.55f + 0.20f * strongMix);

    // 闪屏 slider 控制：白屏 alpha 强度
    self.backgroundRhythmFlashIntensity = flashT * (0.60f + 0.40f * strongMix);

    // 加速 chain rate-burst：律动一开就有，不绑定 rate slider
    [self rhythmPerformBeatJumpWithStrongMix:strongMix];
}

// Motionleap 风格 chain rate-burst：基于上次录屏帧差分析，每个 beat 触发 1-3 个
// 连续短促的 ~130-170ms 倍速冲击，中间间隔 30-70ms 的 1.0× 喘息。
// 这样视觉上是"嘎嘎嘎-停-嘎嘎嘎-停"的强连续加速感，而不是单次长 burst。
// 律动一开就生效，不绑定任何 slider。
- (void)rhythmPerformBeatJumpWithStrongMix:(float)strongMix {
    AVQueuePlayer *player = self.backgroundVideoPlayer;
    if (!player) return;
    AVPlayerItem *item = player.currentItem;
    if (!item) return;
    if (item.status != AVPlayerItemStatusReadyToPlay) return;

    // 单段 burst 倍速：弱拍 ≈ 3.5×；强拍 ≈ 5.0×（baseline 不依赖任何 slider）
    float baseRate = 3.50f + 1.50f * strongMix;
    if (baseRate < 2.50f) baseRate = 2.50f;
    if (baseRate > 6.00f) baseRate = 6.00f;

    // 单段 burst 时长 / 段间停顿：固定值
    NSTimeInterval segDur = 0.150;
    NSTimeInterval gapDur = 0.055;

    // 段数：弱拍 1 段；中拍 2 段；强拍 3 段（用 strongMix 当连续插值）
    NSInteger segCount = 1;
    if (strongMix > 0.40f) segCount = 2;
    if (strongMix > 0.75f) segCount = 3;

    // 安排 chain：每段 [setRate:R, +segDur, setRate:1.0, +gapDur]
    CFTimeInterval cursor = 0.0;
    CFTimeInterval finalEnd = 0.0;
    for (NSInteger i = 0; i < segCount; i++) {
        // 后续段倍速略低（峰值递减），避免人耳/眼"塞车"
        float r = baseRate * (1.0f - 0.18f * i);
        if (r < 1.40f) r = 1.40f;

        CFTimeInterval startAt = cursor;
        CFTimeInterval endAt   = cursor + segDur;
        cursor = endAt + gapDur;
        finalEnd = endAt;

        [self rhythmScheduleSetRate:r atOffset:startAt];
        [self rhythmScheduleSetRate:1.0f atOffset:endAt];
    }

    // 立即把第一段的 rate 应用上（dispatch_after 0 也行，但直接调更即时）
    [player setRate:baseRate];
    self.backgroundRhythmLastBoostEndsAt = CACurrentMediaTime() + finalEnd;
}

// 在主线程延后 offset 秒执行 setRate；带互踩检测：若期间新的 chain 已经接管，跳过本次
- (void)rhythmScheduleSetRate:(float)rate atOffset:(CFTimeInterval)offset {
    if (offset <= 0.0001) {
        // 立即执行（已在主线程）
        AVQueuePlayer *p = self.backgroundVideoPlayer;
        if (!p || !self.isBackgroundRhythmEnabled) return;
        if (fabsf(p.rate - rate) > 0.01f) [p setRate:rate];
        return;
    }
    __weak typeof(self) weakSelf = self;
    CFTimeInterval scheduledFireAt = CACurrentMediaTime() + offset;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(offset * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        AVQueuePlayer *p = s.backgroundVideoPlayer;
        if (!p) return;

        // rhythm 已关：所有 setRate 只允许把 rate 拉回 1.0（避免开了一半的高速残留）
        if (!s.isBackgroundRhythmEnabled) {
            if (rate <= 1.001f && p.rate > 1.001f) [p setRate:1.0];
            return;
        }

        // 互踩判断：新 chain 已经把 finalEnd 推到本次预定时间之后 → 让新 chain 接管
        // 注意：仅对 "复位到 1.0" 的回调做互踩拦截；高倍速回调始终执行（保持 chain 完整性）
        if (rate <= 1.001f && s.backgroundRhythmLastBoostEndsAt > scheduledFireAt + 0.025) {
            return;
        }
        if (fabsf(p.rate - rate) > 0.01f) [p setRate:rate];
    });
}

#pragma mark - Rhythm: Flash slider + handler

- (void)backgroundMediaRhythmFlashSliderChanged:(UISlider *)sender {
    // 0..1，存在已有的 backgroundRhythmFlashIntensity（峰值用），用单独属性更清晰
    // 这里直接驱动 flash overlay 的最大 alpha 上限
    CGFloat v = MAX(0.0, MIN(sender.value, 1.0));
    // 闪屏过强会刺眼：上限 0.55
    self.backgroundRhythmFlashMaxAlpha = (CGFloat)(0.0 + 0.55 * v);
    // 没开启律动时，提前清掉 flash view 的残余
    if (!self.isBackgroundRhythmEnabled && self.backgroundRhythmFlashView) {
        self.backgroundRhythmFlashView.alpha = 0.0;
    }
}

#pragma mark - Rhythm: Display-link tick

- (void)backgroundRhythmTick:(CADisplayLink *)link {
    if (!self.isBackgroundRhythmEnabled) return;
    if (!self.isBackgroundMediaEffectActive) {
        [self setBackgroundRhythmEnabled:NO];
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = link.duration > 0 ? link.duration : (1.0 / 60.0);

    NSArray<NSNumber *> *spectrum = self.latestSpectrumData ?: @[];
    float bass = [self bassEnergyFromSpectrum:spectrum];
    self.backgroundRhythmSmoothedBass = 0.85f * self.backgroundRhythmSmoothedBass + 0.15f * bass;

    BOOL isBeat = NO;
    float flux = 0.0f;
    [self detectBeatFromSpectrum:spectrum atTime:now outFlux:&flux outIsBeat:&isBeat];

    if (isBeat) {
        [self rhythmHandleBeatAtTime:now bass:bass];
    }

    // 滤镜强度衰减：Motionleap 实测每次 beat 持续 ~3-5 帧（30fps 下 100~170ms）
    float filterIntensity = self.backgroundRhythmFilterIntensity;
    filterIntensity *= expf(-14.0f * (float)dt);
    if (filterIntensity < 0.0008f) filterIntensity = 0.0f;
    self.backgroundRhythmFilterIntensity = filterIntensity;

    // 物理脉冲衰减（比滤镜稍慢，让"震颤"持续可见）
    self.backgroundRhythmScalePulse    *= expf(-10.0f * (float)dt);
    self.backgroundRhythmRotationPulse *= expf(-9.0f  * (float)dt);
    self.backgroundRhythmPulse         *= expf(-12.0f * (float)dt);

    // 闪屏衰减（快衰减，~46ms 半衰期）。每帧实时从 slider 同步上限。
    self.backgroundRhythmFlashIntensity *= expf(-15.0f * (float)dt);
    CGFloat flashSliderV = self.backgroundMediaRhythmFlashSlider ?
        MAX(0.0, MIN(self.backgroundMediaRhythmFlashSlider.value, 1.0)) : 0.0;
    self.backgroundRhythmFlashMaxAlpha = (CGFloat)(0.55 * flashSliderV);

    if (self.backgroundRhythmFlashMaxAlpha < 0.005) {
        // slider 在 0：直接 remove from superview，避免任何残留可能
        if (self.backgroundRhythmFlashView && self.backgroundRhythmFlashView.superview) {
            [self.backgroundRhythmFlashView removeFromSuperview];
        }
    } else if (self.backgroundRhythmFlashView) {
        if (!self.backgroundRhythmFlashView.superview) {
            [self.view insertSubview:self.backgroundRhythmFlashView atIndex:0];
            self.backgroundRhythmFlashView.frame = self.view.bounds;
        }
        CGFloat a = (CGFloat)self.backgroundRhythmFlashIntensity * self.backgroundRhythmFlashMaxAlpha;
        if (a < 0.001) a = 0.0;
        if (a > self.backgroundRhythmFlashMaxAlpha) a = self.backgroundRhythmFlashMaxAlpha;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (self.backgroundRhythmFlashView.hidden) self.backgroundRhythmFlashView.hidden = NO;
        self.backgroundRhythmFlashView.alpha = a;
        [CATransaction commit];
    }

    // "震颤" slider 强度
    CGFloat rateT = 0.6;
    if (self.backgroundMediaRhythmRateSlider) {
        CGFloat span = self.backgroundMediaRhythmRateSlider.maximumValue - self.backgroundMediaRhythmRateSlider.minimumValue;
        if (span > 0) {
            rateT = (self.backgroundMediaRhythmRateSlider.value - self.backgroundMediaRhythmRateSlider.minimumValue) / span;
        }
    }
    rateT = MAX(0.0, MIN(rateT, 1.0));

    // 运动模糊衰减（boost 在期间内时缓慢衰减，过了 boost 期间快速衰减）
    BOOL boostActive = (CACurrentMediaTime() < self.backgroundRhythmLastBoostEndsAt);
    float blurDecayRate = boostActive ? 4.0f : 18.0f;
    float blur = self.backgroundRhythmFilterMotionBlur;
    blur *= expf(-blurDecayRate * (float)dt);
    if (blur < 0.001f) blur = 0.0f;
    self.backgroundRhythmFilterMotionBlur = blur;

    // 物理 transform：scale + 微旋转 + **单轴**正弦震颤（不再上下左右乱抖）
    if (self.backgroundVideoLayer && rateT > 0.001) {
        // 缩放：rateT=0 → 1.012 峰值；rateT=1 → 1.06 峰值
        CGFloat scaleAmp = 0.012 + 0.048 * rateT;
        CGFloat scale = 1.0 + (CGFloat)self.backgroundRhythmScalePulse * scaleAmp;

        // 旋转：极小，rateT=0 → 0.5°；rateT=1 → 2.5° 峰值
        CGFloat rotAmp = 0.009 + 0.035 * rateT;
        CGFloat rotation = (CGFloat)self.backgroundRhythmRotationPulse * rotAmp;

        // 单轴震颤：用衰减正弦波而不是随机数，每个 beat 一个方向交替轴
        // 振幅：4..14 px @ rateT=0..1
        CGFloat shakeAmp = (4.0 + 10.0 * rateT) * (CGFloat)self.backgroundRhythmScalePulse;
        CGFloat phase = (CACurrentMediaTime() - self.backgroundRhythmLastBeatTime) * (M_PI * 2.0 * 9.0); // ~9Hz 振荡
        CGFloat osc = sin(phase) * (CGFloat)self.backgroundRhythmRotationPulse;
        CGFloat dx = 0.0, dy = 0.0;
        if (self.backgroundRhythmShakeAxis == 0) {
            dx = osc * shakeAmp;
        } else {
            dy = osc * shakeAmp;
        }
        // 平滑追踪（避免每帧突变）
        CGPoint p = self.backgroundRhythmShakeOffset;
        p.x = p.x * 0.45 + dx * 0.55;
        p.y = p.y * 0.45 + dy * 0.55;
        self.backgroundRhythmShakeOffset = p;
        self.backgroundRhythmShakeVelocity = CGPointZero;

        CGAffineTransform t = CGAffineTransformIdentity;
        t = CGAffineTransformTranslate(t, p.x, p.y);
        t = CGAffineTransformScale(t, scale, scale);
        t = CGAffineTransformRotate(t, rotation);

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.backgroundVideoLayer.affineTransform = t;
        [CATransaction commit];
    } else if (self.backgroundVideoLayer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.backgroundVideoLayer.affineTransform = CGAffineTransformIdentity;
        [CATransaction commit];
        self.backgroundRhythmShakeOffset = CGPointZero;
        self.backgroundRhythmShakeVelocity = CGPointZero;
    }

    // 色彩蒙版：实时同步 slider，衰减 alpha 与位移
    CGFloat shakeSliderV = self.backgroundMediaRhythmShakeSlider ?
        MAX(0.0, MIN(self.backgroundMediaRhythmShakeSlider.value, 1.0)) : 0.0;
    self.backgroundRhythmShakeIntensity = shakeSliderV;
    self.backgroundRhythmColorMaskMaxAlpha = 0.22 * shakeSliderV;
    self.backgroundRhythmColorMaskShiftMax = 8.0 * shakeSliderV;

    if (self.backgroundRhythmColorMaskMaxAlpha < 0.005) {
        if (self.backgroundRhythmColorMaskView.superview) {
            [self.backgroundRhythmColorMaskView removeFromSuperview];
        }
        self.backgroundRhythmColorMaskIntensity = 0.0;
        self.backgroundRhythmColorMaskOffset = CGPointZero;
    } else if (self.backgroundRhythmColorMaskView) {
        if (!self.backgroundRhythmColorMaskView.superview) {
            [self.view insertSubview:self.backgroundRhythmColorMaskView atIndex:0];
            self.backgroundRhythmColorMaskView.frame = self.view.bounds;
        }
        // alpha 衰减（~120ms 半衰期）+ 位移衰减（~110ms 半衰期）
        self.backgroundRhythmColorMaskIntensity *= exp(-6.0 * dt);
        if (self.backgroundRhythmColorMaskIntensity < 0.005) self.backgroundRhythmColorMaskIntensity = 0.0;
        CGPoint mp = self.backgroundRhythmColorMaskOffset;
        CGFloat decay = exp(-6.5 * dt);
        mp.x *= decay; mp.y *= decay;
        if (fabs(mp.x) < 0.05) mp.x = 0; if (fabs(mp.y) < 0.05) mp.y = 0;
        self.backgroundRhythmColorMaskOffset = mp;

        CGFloat alpha = self.backgroundRhythmColorMaskIntensity * self.backgroundRhythmColorMaskMaxAlpha;
        if (alpha < 0.001) alpha = 0.0;
        if (alpha > self.backgroundRhythmColorMaskMaxAlpha) alpha = self.backgroundRhythmColorMaskMaxAlpha;

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.backgroundRhythmColorMaskView.alpha = alpha;
        self.backgroundRhythmColorMaskView.transform = CGAffineTransformMakeTranslation(mp.x, mp.y);
        [CATransaction commit];
    }
}

- (void)backgroundMediaEnableButtonTapped:(UIButton *)sender {
    [self reloadBackgroundMediaLibrary];

    if (self.backgroundMediaItems.count == 0) {
        [self showAlert:@"没有可用背景媒体" message:@"请先点击“导入”添加视频或 Live Photo。"];
        [self setBackgroundMediaEnabled:NO];
        return;
    }

    BOOL enabled = [self isBackgroundMediaEnabled];
    [self setBackgroundMediaEnabled:!enabled];
}

- (void)refreshBackgroundMediaButtonState {
    BOOL hasItems = (self.backgroundMediaItems.count > 0);
    BOOL enabled = [self isBackgroundMediaEnabled] && hasItems;

    if (self.backgroundMediaEnableButton) {
        self.backgroundMediaEnableButton.enabled = hasItems;
        self.backgroundMediaEnableButton.alpha = hasItems ? 1.0 : 0.55;

        NSString *title = hasItems ? (enabled ? @"关闭" : @"开启") : @"无媒体";
        [self.backgroundMediaEnableButton setTitle:title forState:UIControlStateNormal];

        if (enabled) {
            self.backgroundMediaEnableButton.backgroundColor = [UIColor colorWithRed:0.25 green:0.65 blue:0.35 alpha:1.0];
        } else {
            self.backgroundMediaEnableButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        }
    }

    if (self.backgroundMediaButton) {
        // Left-side utility button: subtle highlight when enabled.
        UIColor *borderColor = enabled ? [UIColor colorWithRed:0.35 green:0.72 blue:1.0 alpha:0.9] : [UIColor colorWithWhite:1.0 alpha:0.2];
        CGFloat borderWidth = enabled ? 1.5 : 1.0;
        self.backgroundMediaButton.layer.borderColor = borderColor.CGColor;
        self.backgroundMediaButton.layer.borderWidth = borderWidth;
        self.backgroundMediaButton.alpha = hasItems ? 1.0 : 0.55;
        self.backgroundMediaButton.enabled = YES; // still allow opening panel to import
    }

    if (self.importBackgroundMediaButton) {
        self.importBackgroundMediaButton.enabled = YES;
        self.importBackgroundMediaButton.alpha = 1.0;
    }

    if (self.backgroundMediaRhythmButton) {
        BOOL rhythmAvailable = enabled && self.isBackgroundMediaEffectActive;
        self.backgroundMediaRhythmButton.enabled = rhythmAvailable;
        self.backgroundMediaRhythmButton.alpha = rhythmAvailable ? 1.0 : 0.55;
        self.backgroundMediaRhythmButton.backgroundColor = self.isBackgroundRhythmEnabled ?
            [UIColor colorWithRed:0.95 green:0.55 blue:0.18 alpha:1.0] :
            [UIColor colorWithWhite:1.0 alpha:0.10];
        self.backgroundMediaRhythmButton.layer.borderWidth = self.isBackgroundRhythmEnabled ? 1.0 : 0.0;
        self.backgroundMediaRhythmButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    }

    if (self.backgroundMediaRhythmControlsView) {
        BOOL controlsEnabled = self.isBackgroundRhythmEnabled;
        self.backgroundMediaRhythmControlsView.alpha = controlsEnabled ? 1.0 : 0.55;
        self.backgroundMediaRhythmRateSlider.enabled = controlsEnabled;
        self.backgroundMediaRhythmShakeSlider.enabled = controlsEnabled;

        // 同步 slider -> 参数（以 slider 为准）
        if (self.backgroundMediaRhythmRateSlider) {
            CGFloat maxRate = self.backgroundMediaRhythmRateSlider.value;
            self.backgroundRhythmMaxRate = MAX(0.6, MIN(maxRate, 2.0));
            self.backgroundRhythmBaseRate = MIN(1.0, self.backgroundRhythmMaxRate);
        }
        if (self.backgroundMediaRhythmShakeSlider) {
            self.backgroundRhythmShakeIntensity = MAX(0.0, MIN(self.backgroundMediaRhythmShakeSlider.value, 1.0));
        }
    }

    [self updateSpectrumLiveEditingAvailability];
}

- (void)persistBackgroundMediaItems {
    [self ensureBackgroundMediaDirectoryExists];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.backgroundMediaItems requiringSecureCoding:YES error:nil];
    [data writeToFile:[self backgroundMediaManifestPath] atomically:YES];

    if (self.selectedBackgroundMediaItem.identifier.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:self.selectedBackgroundMediaItem.identifier forKey:@"SelectedBackgroundMediaItemID"];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SelectedBackgroundMediaItemID"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addBackgroundMediaFromURL:(NSURL *)sourceURL kind:(BackgroundMediaKind)kind displayName:(NSString *)displayName completion:(void (^)(BOOL success))completion {
    [self ensureBackgroundMediaDirectoryExists];

    BOOL didStartAccessing = [sourceURL startAccessingSecurityScopedResource];
    NSString *extension = sourceURL.pathExtension.length > 0 ? sourceURL.pathExtension : @"mov";
    NSString *baseName = [[displayName ?: sourceURL.lastPathComponent stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *fileName = [NSString stringWithFormat:@"%@_%lld.%@", baseName.length > 0 ? baseName : @"Background", (long long)([[NSDate date] timeIntervalSince1970] * 1000), extension];
    NSString *targetPath = [[self backgroundMediaDirectoryPath] stringByAppendingPathComponent:fileName];

    NSError *copyError = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:[NSURL fileURLWithPath:targetPath] error:&copyError];
    if (didStartAccessing) {
        [sourceURL stopAccessingSecurityScopedResource];
    }

    if (!copied) {
        NSLog(@"❌ 复制背景媒体失败: %@", copyError.localizedDescription);
        if (completion) completion(NO);
        return;
    }

    BackgroundMediaItem *item = [BackgroundMediaItem itemWithFilePath:targetPath kind:kind displayName:[displayName stringByDeletingPathExtension]];
    [self.backgroundMediaItems insertObject:item atIndex:0];
    self.selectedBackgroundMediaItem = item;
    [self persistBackgroundMediaItems];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.backgroundMediaTableView reloadData];
        self.backgroundMediaEmptyLabel.hidden = YES;
        [self updateBackgroundMediaEffectStateForEffect:VisualEffectTypeUserMediaBackground];
        if (completion) completion(YES);
    });
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) {
        return;
    }

    [self reloadBackgroundMediaLibrary];

    __block NSInteger pendingCount = results.count;
    __block NSInteger successCount = 0;
    __block BOOL didFinishAll = NO;
    NSObject *importStateLock = [[NSObject alloc] init];

    void (^finishImportOnMain)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (didFinishAll) {
                return;
            }
            didFinishAll = YES;
            [self toggleBackgroundMediaPanel:YES animated:YES];
            NSString *message = [NSString stringWithFormat:@"已导入 %ld 个背景媒体", (long)successCount];
            [self showToast:message];
        });
    };

    void (^finishOne)(BOOL) = ^(BOOL success) {
        __block BOOL shouldFinish = NO;
        @synchronized (importStateLock) {
            if (didFinishAll || pendingCount <= 0) {
                return;
            }
            if (success) {
                successCount++;
            }
            pendingCount--;
            shouldFinish = pendingCount <= 0;
        }
        if (shouldFinish) {
            finishImportOnMain();
        }
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __block BOOL shouldFinish = NO;
        @synchronized (importStateLock) {
            if (didFinishAll || pendingCount <= 0) {
                return;
            }
            NSLog(@"⚠️ 背景媒体导入等待超时，强制结束剩余 %ld 项", (long)pendingCount);
            pendingCount = 0;
            shouldFinish = YES;
        }
        if (shouldFinish) {
            finishImportOnMain();
        }
    });

    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        NSString *movieIdentifier = @"public.movie";
        if ([provider hasItemConformingToTypeIdentifier:movieIdentifier]) {
            [provider loadFileRepresentationForTypeIdentifier:movieIdentifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                if (url && !error) {
                    [self addBackgroundMediaFromURL:url kind:BackgroundMediaKindVideo displayName:provider.suggestedName ?: url.lastPathComponent completion:finishOne];
                } else {
                    NSLog(@"❌ 读取视频失败: %@", error.localizedDescription ?: @"未知错误");
                    finishOne(NO);
                }
            }];
        } else if ([provider canLoadObjectOfClass:[PHLivePhoto class]]) {
            NSArray<NSString *> *registeredTypes = provider.registeredTypeIdentifiers;
            NSString *liveMovieIdentifier = nil;
            for (NSString *typeIdentifier in registeredTypes) {
                if ([typeIdentifier isEqualToString:movieIdentifier] || [typeIdentifier hasPrefix:@"com.apple.quicktime-movie"] || [typeIdentifier hasPrefix:@"public.mpeg-4"]) {
                    liveMovieIdentifier = typeIdentifier;
                    break;
                }
            }

            if (!liveMovieIdentifier) {
                liveMovieIdentifier = movieIdentifier;
            }

            [provider loadFileRepresentationForTypeIdentifier:liveMovieIdentifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                if (url && !error) {
                    [self addBackgroundMediaFromURL:url kind:BackgroundMediaKindLivePhoto displayName:provider.suggestedName ?: url.lastPathComponent completion:finishOne];
                } else {
                    NSLog(@"❌ 读取 Live Photo 动态视频失败: %@", error.localizedDescription ?: @"未知错误");
                    finishOne(NO);
                }
            }];
        } else {
            NSLog(@"⚠️ 跳过不支持的背景媒体资源: %@", provider.registeredTypeIdentifiers);
            finishOne(NO);
        }
    }
}

- (void)playSelectedBackgroundMediaIfNeeded {
    if (!self.isBackgroundMediaEffectActive) {
        return;
    }

    BackgroundMediaItem *item = self.selectedBackgroundMediaItem ?: self.backgroundMediaItems.firstObject;
    if (!item || ![[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
        [self stopBackgroundMediaPlayback];
        return;
    }

    if (self.backgroundVideoPlayer &&
        self.backgroundVideoLayer.player == self.backgroundVideoPlayer &&
        [self.playingBackgroundMediaIdentifier isEqualToString:item.identifier]) {
        self.backgroundVideoLayer.hidden = NO;
        self.backgroundVideoLayer.frame = self.view.bounds;
        self.livePhotoPosterView.hidden = YES;
        [self.backgroundVideoPlayer play];
        return;
    }

    self.playingBackgroundMediaIdentifier = item.identifier;
    self.backgroundMediaPreviewColor = [self dominantColorForBackgroundMediaItem:item];
    [self refreshSpectrumAdaptiveThemeIfNeeded];

    NSURL *url = [NSURL fileURLWithPath:item.filePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];

    // 挂上 Motionleap 风格 CIFilter video composition：每帧 GPU 处理一次，
    // 滤镜强度由原子属性 backgroundRhythmFilter* 实时驱动。
    [self installRhythmVideoCompositionOnPlayerItem:playerItem asset:asset];

    AVQueuePlayer *queuePlayer = [[AVQueuePlayer alloc] initWithPlayerItem:playerItem];
    queuePlayer.muted = YES;
    queuePlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    if (@available(iOS 10.0, *)) {
        // 关键：律动 rate-burst 需要禁用系统的 "等待缓冲" 行为，否则 setRate(>1.0) 会被静默
        // 重置为 0 而表现成"暂停"。本地视频 + Looper 配合此项是安全的。
        queuePlayer.automaticallyWaitsToMinimizeStalling = NO;
    }

    self.backgroundVideoPlayer = queuePlayer;
    self.backgroundVideoLooper = [AVPlayerLooper playerLooperWithPlayer:queuePlayer templateItem:playerItem];

    if (!self.backgroundVideoLayer) {
        self.backgroundVideoLayer = [AVPlayerLayer playerLayerWithPlayer:queuePlayer];
        self.backgroundVideoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        self.backgroundVideoLayer.frame = self.view.bounds;
        [self.view.layer insertSublayer:self.backgroundVideoLayer atIndex:0];
    } else {
        self.backgroundVideoLayer.player = queuePlayer;
        self.backgroundVideoLayer.hidden = NO;
        self.backgroundVideoLayer.frame = self.view.bounds;
    }

    if (!self.livePhotoPosterView) {
        self.livePhotoPosterView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        self.livePhotoPosterView.contentMode = UIViewContentModeScaleAspectFill;
        self.livePhotoPosterView.clipsToBounds = YES;
        self.livePhotoPosterView.alpha = 0.0;
        [self.view insertSubview:self.livePhotoPosterView atIndex:0];
    }

    self.livePhotoPosterView.hidden = YES;
    [queuePlayer play];

    // 如果用户之前已开启律动，切换/重建播放器后继续生效
    if (self.isBackgroundRhythmEnabled) {
        [self setBackgroundRhythmEnabled:YES];
    }
}

- (void)stopBackgroundMediaPlayback {
    [self.backgroundVideoPlayer pause];
    self.backgroundVideoLayer.player = nil;
    self.backgroundVideoLayer.hidden = YES;
    self.backgroundVideoPlayer = nil;
    self.backgroundVideoLooper = nil;
    self.playingBackgroundMediaIdentifier = nil;

    // 停止背景播放时，律动也应停止并清理震动/速率
    [self setBackgroundRhythmEnabled:NO];
}

- (void)updateBackgroundMediaEffectStateForEffect:(VisualEffectType)effectType {
    BOOL shouldActivate = (effectType == VisualEffectTypeUserMediaBackground);
    self.isBackgroundMediaEffectActive = shouldActivate;

    if (shouldActivate) {
        self.coverImageView.hidden = YES;
        self.vinylRecordView.hidden = YES;
        self.isShowingVinylRecord = NO;
        [self.vinylRecordView stopSpinning];
        self.backgroundMediaPreviewColor = [self dominantColorForBackgroundMediaItem:self.selectedBackgroundMediaItem];
        [self playSelectedBackgroundMediaIfNeeded];
        [self refreshSpectrumAdaptiveThemeIfNeeded];
        [self bringControlButtonsToFront];
        if (self.backgroundMediaItems.count == 0) {
            [self toggleBackgroundMediaPanel:YES animated:YES];
        }
    } else {
        [self stopBackgroundMediaPlayback];
        [self updateAudioSelection];
        [self bringControlButtonsToFront];
    }

    // 触发 UI 状态刷新（包括律动按钮可用性）
    [self refreshBackgroundMediaButtonState];
    [self updateSpectrumLiveEditingAvailability];
}

- (void)backgroundMediaButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    [self reloadBackgroundMediaLibrary];

    if (self.backgroundMediaItems.count > 0) {
        [self updateBackgroundMediaEffectStateForEffect:VisualEffectTypeUserMediaBackground];
    }

    [self toggleBackgroundMediaPanel:!self.isBackgroundMediaPanelVisible animated:YES];
}

- (void)backgroundMediaCloseButtonTapped:(UIButton *)sender {
    [self toggleBackgroundMediaPanel:NO animated:YES];
}

- (void)importBackgroundMediaButtonTapped:(UIButton *)sender {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.selectionLimit = 0;
        configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[
            [PHPickerFilter videosFilter],
            [PHPickerFilter livePhotosFilter]
        ]];

        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }

    [self showAlert:@"当前系统不支持" message:@"导入背景视频或 Live Photo 需要 iOS 14 及以上系统。"]; 
}

- (void)toggleBackgroundMediaPanel:(BOOL)visible animated:(BOOL)animated {
    [self setupBackgroundMediaPanel];

    if (visible) {
        [self reloadBackgroundMediaLibrary];
        [self bringControlButtonsToFront];
    }

    if (self.isBackgroundMediaPanelVisible == visible) {
        self.backgroundMediaPanelView.hidden = !visible;
        self.backgroundMediaPanelView.alpha = visible ? 1.0 : 0.0;
        return;
    }

    self.isBackgroundMediaPanelVisible = visible;

    if (visible) {
        self.backgroundMediaPanelView.hidden = NO;
        if (animated) {
            self.backgroundMediaPanelView.transform = CGAffineTransformMakeTranslation(16.0, 0.0);
            [UIView animateWithDuration:0.25 animations:^{
                self.backgroundMediaPanelView.alpha = 1.0;
                self.backgroundMediaPanelView.transform = CGAffineTransformIdentity;
            } completion:nil];
        } else {
            self.backgroundMediaPanelView.alpha = 1.0;
            self.backgroundMediaPanelView.transform = CGAffineTransformIdentity;
        }
        return;
    }

    void (^hideBlock)(void) = ^{
        self.backgroundMediaPanelView.alpha = 0.0;
        self.backgroundMediaPanelView.transform = CGAffineTransformMakeTranslation(16.0, 0.0);
    };

    void (^completionBlock)(BOOL) = ^(BOOL finished) {
        self.backgroundMediaPanelView.hidden = YES;
        self.backgroundMediaPanelView.transform = CGAffineTransformIdentity;
    };

    if (animated) {
        [UIView animateWithDuration:0.2 animations:hideBlock completion:completionBlock];
    } else {
        hideBlock();
        completionBlock(YES);
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
