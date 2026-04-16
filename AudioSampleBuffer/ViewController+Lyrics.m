#import "ViewController+Private.h"

#import "KaraokeViewController.h"
#import "LyricsManager.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ViewController (Lyrics)

#pragma mark - Lyrics Actions

- (void)karaokeButtonTapped:(UIButton *)sender {
    if (self.displayedMusicItems.count == 0 || self.currentIndex >= self.displayedMusicItems.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"请先选择一首歌曲"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    self.shouldPreventAutoResume = YES;

    KaraokeViewController *karaokeVC = [[KaraokeViewController alloc] init];
    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    karaokeVC.currentSongName = musicItem.fileName;
    karaokeVC.currentSongPath = [musicItem playableFilePath];

    NSLog(@"🎤 进入卡拉OK模式: %@ -> %@", musicItem.fileName, karaokeVC.currentSongPath);
    [self.navigationController pushViewController:karaokeVC animated:YES];
}

- (void)lyricsEffectButtonTapped:(UIButton *)sender {
    if (!self.lyricsEffectPanel) {
        self.lyricsEffectPanel = [[LyricsEffectControlPanel alloc] initWithFrame:self.view.bounds];
        self.lyricsEffectPanel.delegate = self;
        [self.view addSubview:self.lyricsEffectPanel];

        if (self.lyricsView) {
            self.lyricsEffectPanel.currentEffect = self.lyricsView.currentEffect;
        }
    }

    self.lyricsEffectPanel.lyricsVisible = (self.lyricsContainer.alpha > 0.5);
    [self.lyricsEffectPanel showAnimated:YES];
    [self.view bringSubviewToFront:self.lyricsEffectPanel];

    NSLog(@"🎭 打开歌词特效面板");
}

- (void)importLyricsButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    if (self.displayedMusicItems.count == 0 || self.currentIndex < 0 || self.currentIndex >= self.displayedMusicItems.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"请先选择要关联歌词的歌曲"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    MusicItem *currentMusicItem = self.displayedMusicItems[self.currentIndex];
    NSLog(@"📝 为歌曲导入歌词: %@", currentMusicItem.fileName);

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"导入歌词"
                                                                         message:[NSString stringWithFormat:@"为「%@」导入歌词", currentMusicItem.fileName]
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *importAction = [UIAlertAction actionWithTitle:@"📂 从文件选择 LRC"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self openLRCFilePicker];
    }];
    [actionSheet addAction:importAction];

    UIAlertAction *batchImportAction = [UIAlertAction actionWithTitle:@"📁 批量导入歌词文件"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * _Nonnull action) {
        [self openBatchLRCFilePicker];
    }];
    [actionSheet addAction:batchImportAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [actionSheet addAction:cancelAction];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sender;
        actionSheet.popoverPresentationController.sourceRect = sender.bounds;
    }

    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)openLRCFilePicker {
    NSLog(@"📂 打开 LRC 文件选择器...");

    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        UTType *lrcType = [UTType typeWithFilenameExtension:@"lrc"];
        UTType *txtType = UTTypeText;

        NSMutableArray *contentTypes = [NSMutableArray array];
        if (lrcType) {
            [contentTypes addObject:lrcType];
        }
        [contentTypes addObject:txtType];

        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    } else {
        NSArray *lrcTypes = @[@"public.text", @"public.plain-text", @"public.data"];
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:lrcTypes inMode:UIDocumentPickerModeImport];
    }

    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    documentPicker.view.accessibilityHint = @"lyrics_import_single";

    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)lyricsTimingButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];

    if (self.displayedMusicItems.count == 0 || self.currentIndex < 0 || self.currentIndex >= self.displayedMusicItems.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                       message:@"请先选择要打轴的歌曲"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    MusicItem *currentMusicItem = self.displayedMusicItems[self.currentIndex];
    NSLog(@"🎼 进入歌词打轴: %@", currentMusicItem.fileName);

    [self.player stop];
    self.shouldPreventAutoResume = YES;

    LyricsEditorViewController *editor = [[LyricsEditorViewController alloc] initWithAudioFilePath:[currentMusicItem playableFilePath]];
    editor.songTitle = currentMusicItem.displayName ?: currentMusicItem.fileName;
    editor.artistName = currentMusicItem.artist;
    editor.albumName = currentMusicItem.album;
    editor.delegate = (id<LyricsEditorViewControllerDelegate>)self;

    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - LyricsEditorViewControllerDelegate

- (void)lyricsEditor:(LyricsEditorViewController *)editor didFinishWithLRCContent:(NSString *)lrcContent {
    NSLog(@"🎼 歌词打轴完成，LRC 内容长度: %lu", (unsigned long)lrcContent.length);
}

- (void)lyricsEditor:(LyricsEditorViewController *)editor didSaveLRCToPath:(NSString *)path {
    NSLog(@"🎼 歌词已保存到: %@", path);

    if (self.currentIndex >= 0 && self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *currentMusicItem = self.displayedMusicItems[self.currentIndex];
        [[LyricsManager sharedManager] clearLyricsCacheForAudioFile:currentMusicItem.filePath];
        [self.player loadLyricsForCurrentTrack];
    }
}

- (void)lyricsEditorDidCancel:(LyricsEditorViewController *)editor {
    NSLog(@"🎼 歌词打轴已取消");
}

- (void)openBatchLRCFilePicker {
    NSLog(@"📁 打开批量 LRC 文件选择器...");

    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        UTType *lrcType = [UTType typeWithFilenameExtension:@"lrc"];
        UTType *txtType = UTTypeText;

        NSMutableArray *contentTypes = [NSMutableArray array];
        if (lrcType) {
            [contentTypes addObject:lrcType];
        }
        [contentTypes addObject:txtType];

        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    } else {
        NSArray *lrcTypes = @[@"public.text", @"public.plain-text", @"public.data"];
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:lrcTypes inMode:UIDocumentPickerModeImport];
    }

    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    documentPicker.view.accessibilityHint = @"lyrics_import_batch";

    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark - Lyrics View

- (void)setupLyricsView {
    CGFloat containerWidth = self.view.bounds.size.width - 40;
    CGFloat containerHeight = 180;
    CGFloat containerY = self.view.bounds.size.height - containerHeight - 120;

    self.lyricsContainer = [[UIView alloc] initWithFrame:CGRectMake(20, containerY, containerWidth, containerHeight)];
    self.lyricsContainer.backgroundColor = [UIColor clearColor];
    self.lyricsContainer.layer.cornerRadius = 15;
    self.lyricsContainer.clipsToBounds = YES;

    if (self.tableView) {
        [self.view insertSubview:self.lyricsContainer belowSubview:self.tableView];
    } else {
        [self.view addSubview:self.lyricsContainer];
    }

    self.lyricsView = [[LyricsView alloc] initWithFrame:self.lyricsContainer.bounds];
    self.lyricsView.backgroundColor = [UIColor clearColor];
    self.lyricsView.highlightColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.lyricsView.normalColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self.lyricsView.highlightFont = [UIFont boldSystemFontOfSize:16];
    self.lyricsView.lyricsFont = [UIFont systemFontOfSize:13];
    self.lyricsView.lineSpacing = 18;
    self.lyricsView.autoScroll = YES;

    [self.lyricsContainer addSubview:self.lyricsView];
    [self setupVisualLyricsOverlay];
    [self addGradientMaskToLyricsContainer];

    self.lyricsContainer.hidden = YES;

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleLyricsView:)];
    tapGesture.numberOfTapsRequired = 2;
    [self.lyricsContainer addGestureRecognizer:tapGesture];

    NSLog(@"🎵 歌词视图已创建（优化版：缩小尺寸 + 渐变边缘）");
}

- (void)addGradientMaskToLyricsContainer {
    CAGradientLayer *gradientMask = [CAGradientLayer layer];
    gradientMask.frame = self.lyricsContainer.bounds;
    gradientMask.colors = @[
        (id)[UIColor clearColor].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.3].CGColor,
        (id)[UIColor whiteColor].CGColor,
        (id)[UIColor whiteColor].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.3].CGColor,
        (id)[UIColor clearColor].CGColor
    ];
    gradientMask.locations = @[@0.0, @0.15, @0.25, @0.75, @0.85, @1.0];
    gradientMask.startPoint = CGPointMake(0.5, 0);
    gradientMask.endPoint = CGPointMake(0.5, 1);
    self.lyricsContainer.layer.mask = gradientMask;
}

- (void)setupVisualLyricsOverlay {
    if (self.visualLyricsOverlayView) {
        [self.visualLyricsOverlayView removeFromSuperview];
    }

    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.userInteractionEnabled = NO;
    overlay.backgroundColor = [UIColor clearColor];
    overlay.hidden = YES;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NSArray<NSNumber *> *angles = @[@(-45.0), @(-45.0), @(-45.0), @(-45.0)];
    NSArray<NSValue *> *centers = @[
        [NSValue valueWithCGPoint:CGPointMake(self.view.bounds.size.width * 0.28, self.view.bounds.size.height * 0.80)],
        [NSValue valueWithCGPoint:CGPointMake(self.view.bounds.size.width * 0.78, self.view.bounds.size.height * 0.26)],
        [NSValue valueWithCGPoint:CGPointMake(self.view.bounds.size.width * 0.44, self.view.bounds.size.height * 0.58)],
        [NSValue valueWithCGPoint:CGPointMake(self.view.bounds.size.width * 0.64, self.view.bounds.size.height * 0.44)]
    ];

    for (NSInteger i = 0; i < angles.count; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width * 0.84, 52)];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.42;
        label.textColor = [UIColor colorWithWhite:1.0 alpha:0.32];
        label.font = [UIFont boldSystemFontOfSize:(i == 0 ? 30.0 : 24.0)];
        label.layer.shadowColor = [UIColor colorWithRed:0.55 green:0.85 blue:1.0 alpha:1.0].CGColor;
        label.layer.shadowOpacity = 0.85;
        label.layer.shadowRadius = 14.0;
        label.layer.shadowOffset = CGSizeZero;
        label.center = [centers[i] CGPointValue];
        label.transform = CGAffineTransformMakeRotation((CGFloat)([angles[i] doubleValue] * M_PI / 180.0));
        label.hidden = YES;
        [overlay addSubview:label];
        [labels addObject:label];
    }

    [self.view addSubview:overlay];
    self.visualLyricsOverlayView = overlay;
    self.visualLyricsOverlayLabels = [labels copy];
    self.visualLyricsOverlayBaseCenters = centers;
}

- (void)updateVisualLyricsOverlayForCurrentIndex:(NSInteger)currentIndex {
    if (!self.visualLyricsOverlayLabels.count) {
        return;
    }

    NSArray<LRCLine *> *lyrics = self.lyricsView.parser.lyrics;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSString *currentText = (currentIndex >= 0 && currentIndex < lyrics.count) ? (lyrics[currentIndex].text ?: @"") : @"";
    if (currentIndex >= 0 && currentIndex < lyrics.count) {
        NSInteger start = MAX(0, currentIndex - 3);
        NSInteger end = MIN((NSInteger)lyrics.count - 1, currentIndex + 3);
        for (NSInteger i = start; i <= end; i++) {
            NSString *text = lyrics[i].text ?: @"";
            if (text.length > 0) {
                [texts addObject:text];
            }
        }
    }

    BOOL shouldRefreshHighlightSlot = NO;
    if (currentText.length == 0) {
        self.visualLyricsHighlightSlot = NSNotFound;
        self.visualLyricsLastHighlightedText = nil;
    } else {
        if (self.visualLyricsHighlightSlot == NSNotFound || self.visualLyricsHighlightSlot >= self.visualLyricsOverlayLabels.count) {
            shouldRefreshHighlightSlot = YES;
        }
        if (![self.visualLyricsLastHighlightedText isEqualToString:currentText]) {
            shouldRefreshHighlightSlot = YES;
        }
    }
    if (shouldRefreshHighlightSlot) {
        self.visualLyricsHighlightSlot = arc4random_uniform((uint32_t)MAX((NSUInteger)1, self.visualLyricsOverlayLabels.count));
        self.visualLyricsLastHighlightedText = [currentText copy];
    }

    for (NSInteger i = 0; i < self.visualLyricsOverlayLabels.count; i++) {
        UILabel *label = self.visualLyricsOverlayLabels[i];
        CGPoint baseCenter = (i < self.visualLyricsOverlayBaseCenters.count) ? [self.visualLyricsOverlayBaseCenters[i] CGPointValue] : label.center;
        label.center = baseCenter;

        NSString *newText = i < texts.count ? texts[i] : @"";
        BOOL isCurrent = currentText.length > 0 && (i == self.visualLyricsHighlightSlot);
        if (isCurrent && currentText.length > 0) {
            newText = currentText;
        }
        BOOL wasVisible = !label.hidden && label.text.length > 0;
        BOOL textChanged = !((label.text == nil && newText.length == 0) || [label.text isEqualToString:newText]);

        label.text = newText;
        label.hidden = (newText.length == 0);
        label.alpha = newText.length == 0 ? 0.0 : (isCurrent ? 1.0 : (i == 0 ? 0.68 : 0.46));
        label.textColor = isCurrent ? [UIColor colorWithRed:1.0 green:0.96 blue:0.88 alpha:1.0] : [UIColor colorWithWhite:1.0 alpha:(i == 0 ? 0.38 : 0.28)];
        label.font = [UIFont boldSystemFontOfSize:isCurrent ? 34.0 : (i == 0 ? 30.0 : 24.0)];
        label.layer.shadowColor = (isCurrent ? [UIColor colorWithRed:1.0 green:0.72 blue:0.40 alpha:1.0] : [UIColor colorWithRed:0.55 green:0.85 blue:1.0 alpha:1.0]).CGColor;
        label.layer.shadowRadius = isCurrent ? 20.0 : 12.0;

        if (textChanged && wasVisible) {
            label.layer.opacity = label.alpha;
        }
    }

    [self refreshVisualLyricsOverlayVisibility];
}

- (void)animateVisualLyricsOverlayWithBass:(CGFloat)bass mid:(CGFloat)mid treble:(CGFloat)treble {
    // 关闭前景歌词抖动，避免 UIView 频繁位移导致 GPU 飙升
}

- (void)refreshVisualLyricsOverlayVisibility {
    BOOL shouldShow = self.visualEffectManager.currentEffectType == VisualEffectTypeVisualLyricsTunnel && self.lyricsView.parser.lyrics.count > 0;
    self.visualLyricsOverlayView.hidden = !shouldShow;
    if (shouldShow) {
        [self.view bringSubviewToFront:self.visualLyricsOverlayView];
    }
}

- (void)toggleLyricsView:(UITapGestureRecognizer *)gesture {
    [UIView animateWithDuration:0.3 animations:^{
        self.lyricsContainer.alpha = self.lyricsContainer.alpha > 0.5 ? 0.3 : 1.0;
    }];
}

#pragma mark - LyricsEffectControlDelegate

- (void)lyricsEffectDidChange:(LyricsEffectType)effectType {
    NSLog(@"🎭 歌词特效已切换: %@", [LyricsEffectManager nameForEffect:effectType]);

    if (self.lyricsView) {
        [self.lyricsView setLyricsEffect:effectType];
    }

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

- (void)lyricsVisibilityDidChange:(BOOL)isVisible {
    NSLog(@"👁️ 歌词可见性已切换: %@", isVisible ? @"显示" : @"隐藏");

    [UIView animateWithDuration:0.3 animations:^{
        self.lyricsContainer.alpha = isVisible ? 1.0 : 0.0;
    } completion:^(BOOL finished) {
        self.lyricsContainer.hidden = !isVisible;
        [self refreshVisualLyricsOverlayVisibility];
    }];

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

#pragma mark - Lyrics Import

- (void)handleSingleLRCImport:(NSURL *)lrcURL {
    if (self.currentIndex < 0 || self.currentIndex >= self.displayedMusicItems.count) {
        [self handleBatchLRCImport:@[lrcURL]];
        return;
    }

    MusicItem *currentMusicItem = self.displayedMusicItems[self.currentIndex];
    NSString *audioPath = [currentMusicItem playableFilePath];

    NSLog(@"📝 导入歌词关联到: %@", currentMusicItem.fileName);

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"正在导入歌词"
                                                                            message:@"请稍候..."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];

    [[LyricsManager sharedManager] importLRCFile:lrcURL
                                    forAudioFile:audioPath
                                      completion:^(LRCParser *parser, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (parser) {
                    NSString *message = [NSString stringWithFormat:@"已为「%@」导入歌词\n共 %lu 行歌词",
                                         currentMusicItem.fileName,
                                         (unsigned long)parser.lyrics.count];

                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 歌词导入成功"
                                                                                          message:message
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:successAlert animated:YES completion:nil];

                    if (self.player.isPlaying) {
                        self.lyricsView.parser = parser;
                        self.lyricsContainer.hidden = NO;
                    }

                    NSLog(@"✅ 歌词导入成功: %@ (%lu 行)", currentMusicItem.fileName, (unsigned long)parser.lyrics.count);
                } else {
                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"❌ 歌词导入失败"
                                                                                         message:error.localizedDescription ?: @"无法解析歌词文件"
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:errorAlert animated:YES completion:nil];

                    NSLog(@"❌ 歌词导入失败: %@", error.localizedDescription);
                }
            }];
        });
    }];
}

- (void)handleBatchLRCImport:(NSArray<NSURL *> *)lrcURLs {
    NSLog(@"📁 批量导入 %ld 个歌词文件", (long)lrcURLs.count);

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"正在批量导入歌词"
                                                                            message:[NSString stringWithFormat:@"共 %ld 个文件...", (long)lrcURLs.count]
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSInteger successCount = 0;
        __block NSInteger failureCount = 0;
        dispatch_group_t group = dispatch_group_create();

        for (NSURL *lrcURL in lrcURLs) {
            dispatch_group_enter(group);

            [[LyricsManager sharedManager] importLRCFile:lrcURL
                                              completion:^(LRCParser *parser, NSError *error) {
                if (parser) {
                    successCount++;
                } else {
                    failureCount++;
                }
                dispatch_group_leave(group);
            }];
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                NSString *title = nil;
                NSString *message = nil;

                if (successCount > 0 && failureCount == 0) {
                    title = @"✅ 批量导入完成";
                    message = [NSString stringWithFormat:@"成功导入 %ld 个歌词文件", (long)successCount];
                } else if (successCount > 0) {
                    title = @"⚠️ 部分导入成功";
                    message = [NSString stringWithFormat:@"成功: %ld 个\n失败: %ld 个", (long)successCount, (long)failureCount];
                } else {
                    title = @"❌ 导入失败";
                    message = @"所有歌词文件导入失败";
                }

                UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:title
                                                                                      message:message
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [resultAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:resultAlert animated:YES completion:nil];

                NSLog(@"📁 批量歌词导入完成: 成功 %ld, 失败 %ld", (long)successCount, (long)failureCount);
            }];
        });
    });
}

@end
