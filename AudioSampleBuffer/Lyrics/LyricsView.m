//
//  LyricsView.m
//  AudioSampleBuffer
//
//  Created for displaying synchronized lyrics
//

#import "LyricsView.h"
#import "LyricsEffectCell.h"
#import <QuartzCore/QuartzCore.h>

NSString *const kLyricsViewDidUpdateVisualTextNotification = @"LyricsViewDidUpdateVisualTextNotification";
NSString *const kLyricsViewDidUpdateVisualLinesNotification = @"LyricsViewDidUpdateVisualLinesNotification";

@interface LyricsView () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) UILabel *noLyricsLabel;
@property (nonatomic, copy, nullable) NSString *currentVisualText;

@end

@implementation LyricsView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
        [self setupDefaultStyle];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
        [self setupDefaultStyle];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    
    // TableView
    _tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.showsHorizontalScrollIndicator = NO;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // 设置内容边距，让当前歌词显示在中间
    _tableView.contentInset = UIEdgeInsetsMake(self.bounds.size.height / 2,
                                                0,
                                                self.bounds.size.height / 2,
                                                0);
    
    [self addSubview:_tableView];
    
    // 无歌词提示
    _noLyricsLabel = [[UILabel alloc] initWithFrame:self.bounds];
    _noLyricsLabel.text = @"暂无lrc文件歌词";
    _noLyricsLabel.textAlignment = NSTextAlignmentCenter;
    _noLyricsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    _noLyricsLabel.font = [UIFont systemFontOfSize:16];
    _noLyricsLabel.hidden = YES;
    _noLyricsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_noLyricsLabel];
    
    _currentIndex = -1;
    _autoScroll = YES;
}

- (void)setupDefaultStyle {
    _highlightColor = [UIColor whiteColor];
    _normalColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    _lyricsFont = [UIFont systemFontOfSize:15];
    _highlightFont = [UIFont boldSystemFontOfSize:17];
    _lineSpacing = 20;
    _currentEffect = LyricsEffectTypeNone;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 更新内容边距
    _tableView.contentInset = UIEdgeInsetsMake(self.bounds.size.height / 2,
                                                0,
                                                self.bounds.size.height / 2,
                                                0);
}

#pragma mark - Public Methods

- (void)setParser:(LRCParser *)parser {
    _parser = parser;
    _currentIndex = -1;
    self.currentVisualText = nil;
    
    // ⚠️ 关键修复：确保所有 UI 更新都在主线程执行
    // 如果已经在主线程，直接执行；否则调度到主线程
    if ([NSThread isMainThread]) {
        // 先设置可见性，再 reloadData，避免 tableView 在隐藏状态下更新导致崩溃
        if (!parser || parser.lyrics.count == 0) {
            _noLyricsLabel.hidden = NO;
            _tableView.hidden = YES;
        } else {
            _noLyricsLabel.hidden = YES;
            _tableView.hidden = NO;
        }
        
        // 在 tableView 可见后才调用 reloadData
        [_tableView reloadData];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 先设置可见性，再 reloadData，避免 tableView 在隐藏状态下更新导致崩溃
            if (!parser || parser.lyrics.count == 0) {
                self->_noLyricsLabel.hidden = NO;
                self->_tableView.hidden = YES;
            } else {
                self->_noLyricsLabel.hidden = YES;
                self->_tableView.hidden = NO;
            }
            
            // 在 tableView 可见后才调用 reloadData
            [self->_tableView reloadData];
        });
    }
}

- (void)updateWithTime:(NSTimeInterval)currentTime {
    if (!_parser) {
        return;
    }
    
    NSInteger newIndex = [_parser indexForTime:currentTime];
    [self notifyVisualDelegateForTime:currentTime currentIndex:newIndex];
    
    if (newIndex != _currentIndex && newIndex >= 0) {
        NSInteger oldIndex = _currentIndex;
        _currentIndex = newIndex;
        
        // 🔧 使用 CATransaction 禁用隐式动画，避免闪烁
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        
        // 🔧 刷新旧的、新的和周围的行（用于更新透明度渐变效果）
        NSMutableArray *indexPaths = [NSMutableArray array];
        
        // 添加旧索引及其周围的行
        if (oldIndex >= 0 && oldIndex < _parser.lyrics.count) {
            for (NSInteger i = oldIndex - 3; i <= oldIndex + 3; i++) {
                if (i >= 0 && i < _parser.lyrics.count) {
                    [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
            }
        }
        
        // 添加新索引及其周围的行
        if (newIndex >= 0 && newIndex < _parser.lyrics.count) {
            for (NSInteger i = newIndex - 3; i <= newIndex + 3; i++) {
                if (i >= 0 && i < _parser.lyrics.count) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                    if (![indexPaths containsObject:indexPath]) {
                        [indexPaths addObject:indexPath];
                    }
                }
            }
        }
        
        if (indexPaths.count > 0) {
            // 🔧 使用 beginUpdates/endUpdates 来批量更新，减少闪烁
            [_tableView beginUpdates];
            [_tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
            [_tableView endUpdates];
        }
        
        [CATransaction commit];
        
        // 🔧 自动滚动到当前歌词（在 CATransaction 之外执行，保持滚动动画）
        if (_autoScroll && newIndex >= 0) {
            [self scrollToIndex:newIndex animated:YES];
        }
    }
}

- (void)reset {
    _currentIndex = -1;
    self.currentVisualText = nil;
    [_tableView reloadData];
    [_tableView setContentOffset:CGPointMake(0, -_tableView.contentInset.top) animated:NO];
    [self notifyVisualDelegateForTime:0 currentIndex:-1];
}

- (void)scrollToIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < 0 || index >= _parser.lyrics.count) {
        return;
    }
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    [_tableView scrollToRowAtIndexPath:indexPath
                      atScrollPosition:UITableViewScrollPositionMiddle
                              animated:animated];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _parser ? _parser.lyrics.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LyricsEffectCell";
    
    LyricsEffectCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[LyricsEffectCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }
    
    LRCLine *line = _parser.lyrics[indexPath.row];
    BOOL isCurrentLine = (indexPath.row == _currentIndex);
    
    // 🔧 先设置样式属性，再设置文本和高亮状态，避免闪烁
    cell.effectType = _currentEffect;
    cell.highlightColor = _highlightColor;
    cell.normalColor = _normalColor;
    cell.highlightFont = _highlightFont;
    cell.normalFont = _lyricsFont;
    
    // 🔧 设置高亮状态在设置文本之前，确保颜色立即正确
    cell.isHighlighted = isCurrentLine;
    cell.lyricsText = line.text;
    
    // 🎨 计算距离当前行的距离，实现渐进渐出效果
    NSInteger distance = labs(indexPath.row - _currentIndex);
    CGFloat alpha = 1.0;
    
    if (distance == 0) {
        alpha = 1.0; // 当前行完全不透明
    } else if (distance == 1) {
        alpha = 0.8; // 相邻行
    } else if (distance == 2) {
        alpha = 0.6; // 第二行
    } else if (distance == 3) {
        alpha = 0.4; // 第三行
    } else {
        alpha = 0.2; // 更远的行，几乎透明
    }
    
    cell.alpha = alpha;
    
    // 🔧 应用特效（在所有属性设置完成后）
    if (isCurrentLine) {
        [cell applyEffect:YES];
    } else {
        [cell resetEffect];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    LRCLine *line = _parser.lyrics[indexPath.row];
    BOOL isCurrentLine = (indexPath.row == _currentIndex);
    UIFont *font = isCurrentLine ? _highlightFont : _lyricsFont;
    
    CGFloat width = tableView.bounds.size.width - 40; // 左右各20边距
    CGSize size = [line.text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{NSFontAttributeName: font}
                                          context:nil].size;
    
    return MAX(size.height + _lineSpacing, _lineSpacing * 2);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 获取点击的歌词信息
    if (indexPath.row >= 0 && indexPath.row < _parser.lyrics.count) {
        LRCLine *line = _parser.lyrics[indexPath.row];
        
        NSLog(@"🎵 点击歌词: 索引=%ld, 时间=%.2f秒, 文本=%@", 
              (long)indexPath.row, line.time, line.text);
        
        // 🆕 通知代理
        if ([_delegate respondsToSelector:@selector(lyricsView:didTapLyricAtTime:text:index:)]) {
            [_delegate lyricsView:self 
                didTapLyricAtTime:line.time 
                             text:line.text 
                            index:indexPath.row];
        }
    }
    
    // 点击歌词后暂时禁用自动滚动
    _autoScroll = NO;
    
    // 延迟恢复自动滚动
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.autoScroll = YES;
    });
}

#pragma mark - Public Methods - Effect

- (void)setLyricsEffect:(LyricsEffectType)effectType {
    _currentEffect = effectType;
    [_tableView reloadData];
}

- (void)notifyVisualDelegateForTime:(NSTimeInterval)currentTime currentIndex:(NSInteger)currentIndex {
    BOOL hasVisualDelegate = (self.visualDelegate != nil);

    NSString *currentText = nil;
    CGFloat progress = 0.0;

    if (currentIndex >= 0 && currentIndex < self.parser.lyrics.count) {
        LRCLine *currentLine = self.parser.lyrics[currentIndex];
        currentText = currentLine.text;

        NSTimeInterval startTime = currentLine.time;
        NSTimeInterval endTime = currentIndex + 1 < self.parser.lyrics.count ? self.parser.lyrics[currentIndex + 1].time : startTime + 4.0;
        NSTimeInterval duration = MAX(0.25, endTime - startTime);
        progress = (CGFloat)((currentTime - startTime) / duration);
        progress = MAX(0.0, MIN(1.0, progress));
    }

    NSMutableArray<NSString *> *visibleLines = [NSMutableArray array];
    if (currentIndex >= 0) {
        NSInteger start = MAX(0, currentIndex - 5);
        NSInteger end = MIN((NSInteger)self.parser.lyrics.count - 1, currentIndex + 5);
        for (NSInteger i = start; i <= end; i++) {
            NSString *text = self.parser.lyrics[i].text ?: @"";
            if (text.length > 0) {
                [visibleLines addObject:text];
            }
        }
    }

    // 视觉歌词特效没有可读文字输入时，仍然保留一组占位行，确保 45° 斜向轨道始终可见。
    if (visibleLines.count == 0) {
        [visibleLines addObjectsFromArray:@[@"MUSIC", @"FLOW", @"LYRIC", @"PULSE"]];
    }

    BOOL textChanged = !((self.currentVisualText == nil && currentText == nil) || [self.currentVisualText isEqualToString:currentText]);
    BOOL linesChanged = (currentIndex != self.currentIndex) || textChanged;
    self.currentVisualText = currentText;

    if (linesChanged && hasVisualDelegate && [self.visualDelegate respondsToSelector:@selector(lyricsView:didUpdateVisualLyricLines:currentIndex:)]) {
        [self.visualDelegate lyricsView:self didUpdateVisualLyricLines:[visibleLines copy] currentIndex:currentIndex];
    }
    if (linesChanged) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kLyricsViewDidUpdateVisualLinesNotification
                                                            object:self
                                                          userInfo:@{ @"lines": [visibleLines copy],
                                                                      @"currentIndex": @(currentIndex) }];
    }

    if (hasVisualDelegate && [self.visualDelegate respondsToSelector:@selector(lyricsView:didUpdateVisualLyricText:progress:)]) {
        [self.visualDelegate lyricsView:self didUpdateVisualLyricText:currentText progress:progress];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kLyricsViewDidUpdateVisualTextNotification
                                                        object:self
                                                      userInfo:@{ @"text": currentText ?: @"",
                                                                  @"progress": @(progress) }];
}

@end

