//
//  LocalLyricsListViewController.m
//  AudioSampleBuffer
//
//  本地歌词列表管理 - 查看、删除本地保存的 LRC 歌词文件
//

#import "LocalLyricsListViewController.h"

@interface LocalLyricsListViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>

/// 歌词文件列表
@property (nonatomic, strong) NSMutableArray<NSString *> *lyricsFiles;

/// 表格视图
@property (nonatomic, strong) UITableView *tableView;

/// 空状态标签
@property (nonatomic, strong) UILabel *emptyLabel;

/// 歌词目录路径
@property (nonatomic, strong) NSString *lyricsDirectoryPath;

/// 当前要导出的文件路径（用于 UIDocumentPickerDelegate 回调）
@property (nonatomic, strong) NSString *pendingExportPath;

@end

@implementation LocalLyricsListViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"本地歌词";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 设置歌词目录路径
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.lyricsDirectoryPath = [documentsPath stringByAppendingPathComponent:@"Lyrics"];
    
    [self setupNavigationBar];
    [self setupTableView];
    [self setupEmptyLabel];
    [self loadLyricsFiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 显示导航栏
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    
    // 刷新列表
    [self loadLyricsFiles];
}

#pragma mark - Setup

- (void)setupNavigationBar {
    // 关闭按钮
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(closeButtonTapped)];
    self.navigationItem.leftBarButtonItem = closeButton;
    
    // 刷新按钮
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(refreshButtonTapped)];
    self.navigationItem.rightBarButtonItem = refreshButton;
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor systemBackgroundColor];
    _tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"LyricsFileCell"];
    [self.view addSubview:_tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupEmptyLabel {
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.text = @"暂无本地歌词文件\n\n完成打轴后保存的歌词将显示在这里";
    _emptyLabel.textColor = [UIColor secondaryLabelColor];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.font = [UIFont systemFontOfSize:16];
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
    ]];
}

#pragma mark - Data Loading

- (void)loadLyricsFiles {
    self.lyricsFiles = [NSMutableArray array];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // 确保目录存在
    if (![fileManager fileExistsAtPath:self.lyricsDirectoryPath]) {
        [fileManager createDirectoryAtPath:self.lyricsDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.lyricsDirectoryPath error:&error];
    
    if (error) {
        NSLog(@"❌ 读取歌词目录失败: %@", error);
        [self updateEmptyState];
        return;
    }
    
    // 过滤 .lrc 文件并按修改时间排序
    NSMutableArray *lrcFiles = [NSMutableArray array];
    for (NSString *file in files) {
        if ([[file pathExtension].lowercaseString isEqualToString:@"lrc"]) {
            [lrcFiles addObject:file];
        }
    }
    
    // 按修改时间排序（最新的在前面）
    [lrcFiles sortUsingComparator:^NSComparisonResult(NSString *file1, NSString *file2) {
        NSString *path1 = [self.lyricsDirectoryPath stringByAppendingPathComponent:file1];
        NSString *path2 = [self.lyricsDirectoryPath stringByAppendingPathComponent:file2];
        
        NSDictionary *attrs1 = [fileManager attributesOfItemAtPath:path1 error:nil];
        NSDictionary *attrs2 = [fileManager attributesOfItemAtPath:path2 error:nil];
        
        NSDate *date1 = attrs1[NSFileModificationDate];
        NSDate *date2 = attrs2[NSFileModificationDate];
        
        return [date2 compare:date1]; // 降序
    }];
    
    self.lyricsFiles = lrcFiles;
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    BOOL isEmpty = (self.lyricsFiles.count == 0);
    self.emptyLabel.hidden = !isEmpty;
    self.tableView.hidden = isEmpty;
}

#pragma mark - Actions

- (void)closeButtonTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)refreshButtonTapped {
    [self loadLyricsFiles];
    
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

- (void)deleteLyricsAtIndex:(NSInteger)index {
    if (index >= self.lyricsFiles.count) return;
    
    NSString *fileName = self.lyricsFiles[index];
    NSString *filePath = [self.lyricsDirectoryPath stringByAppendingPathComponent:fileName];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    
    if (error) {
        NSLog(@"❌ 删除歌词文件失败: %@", error);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除失败"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self.lyricsFiles removeObjectAtIndex:index];
        [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateEmptyState];
        
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.lyricsFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LyricsFileCell" forIndexPath:indexPath];
    
    NSString *fileName = self.lyricsFiles[indexPath.row];
    NSString *filePath = [self.lyricsDirectoryPath stringByAppendingPathComponent:fileName];
    
    // 配置 cell
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = [fileName stringByDeletingPathExtension];
    config.image = [UIImage systemImageNamed:@"music.note.list"];
    config.imageProperties.tintColor = [UIColor systemBlueColor];
    
    // 获取文件信息
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    if (attrs) {
        NSDate *modDate = attrs[NSFileModificationDate];
        unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        
        config.secondaryText = [NSString stringWithFormat:@"%@ · %.1f KB", [formatter stringFromDate:modDate], fileSize / 1024.0];
    }
    
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *fileName = self.lyricsFiles[indexPath.row];
    NSString *filePath = [self.lyricsDirectoryPath stringByAppendingPathComponent:fileName];
    
    // 显示歌词内容
    [self showLyricsPreviewForPath:filePath];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    // 删除操作
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"删除"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self confirmDeleteAtIndex:indexPath.row];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    
    // 导出操作
    UIContextualAction *exportAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:@"导出"
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *fileName = self.lyricsFiles[indexPath.row];
        NSString *filePath = [self.lyricsDirectoryPath stringByAppendingPathComponent:fileName];
        [self exportLyricsToFilesAtPath:filePath];
        completionHandler(YES);
    }];
    exportAction.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    exportAction.backgroundColor = [UIColor systemBlueColor];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, exportAction]];
}

#pragma mark - Preview

- (void)showLyricsPreviewForPath:(NSString *)path {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"读取失败"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSString *fileName = [[path lastPathComponent] stringByDeletingPathExtension];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:fileName
                                                                   message:content
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self shareLyricsAtPath:path];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"导出到文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self exportLyricsToFilesAtPath:path];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSInteger index = [self.lyricsFiles indexOfObject:[path lastPathComponent]];
        if (index != NSNotFound) {
            [self confirmDeleteAtIndex:index];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteAtIndex:(NSInteger)index {
    if (index >= self.lyricsFiles.count) return;
    
    NSString *fileName = self.lyricsFiles[index];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认删除"
                                                                   message:[NSString stringWithFormat:@"确定要删除 \"%@\" 吗？\n此操作不可恢复", [fileName stringByDeletingPathExtension]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteLyricsAtIndex:index];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareLyricsAtPath:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                             applicationActivities:nil];
    
    // iPad 适配
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

#pragma mark - Export to Files

- (void)exportLyricsToFilesAtPath:(NSString *)path {
    // 保存待导出路径
    self.pendingExportPath = path;
    
    // 创建文档选择器（选择目录模式）
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:path]]];
    picker.delegate = self;
    
    // iPad 适配
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        picker.popoverPresentationController.sourceView = self.view;
        picker.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    }
    
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        NSURL *destinationURL = urls.firstObject;
        NSLog(@"✅ 歌词已导出到: %@", destinationURL.path);
        
        // 显示成功提示
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出成功"
                                                                       message:[NSString stringWithFormat:@"歌词已保存到:\n%@", destinationURL.lastPathComponent]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        
        // 触觉反馈
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
    
    self.pendingExportPath = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"📄 用户取消了文件导出");
    self.pendingExportPath = nil;
}

@end

