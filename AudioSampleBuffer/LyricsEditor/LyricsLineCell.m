//
//  LyricsLineCell.m
//  AudioSampleBuffer
//
//  歌词行列表单元格 - 显示时间戳和歌词文本
//

#import "LyricsLineCell.h"

@interface LyricsLineCell ()

/// 行号标签
@property (nonatomic, strong) UILabel *indexLabel;

/// 时间戳标签
@property (nonatomic, strong) UILabel *timestampLabel;

/// 歌词文本标签
@property (nonatomic, strong) UILabel *lyricsLabel;

/// 状态指示器（当前行高亮）
@property (nonatomic, strong) UIView *statusIndicator;

/// 时间微调按钮容器
@property (nonatomic, strong) UIStackView *adjustButtonsStack;

/// 时间减少按钮
@property (nonatomic, strong) UIButton *decreaseTimeButton;

/// 时间增加按钮
@property (nonatomic, strong) UIButton *increaseTimeButton;

/// 当前歌词行数据
@property (nonatomic, strong) LRCEditableLine *currentLine;

/// 是否是当前打轴行
@property (nonatomic, assign) BOOL isCurrent;

@end

@implementation LyricsLineCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    
    // 状态指示器（左侧竖条）
    _statusIndicator = [[UIView alloc] init];
    _statusIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _statusIndicator.backgroundColor = [UIColor clearColor];
    _statusIndicator.layer.cornerRadius = 2;
    [self.contentView addSubview:_statusIndicator];
    
    // 行号标签
    _indexLabel = [[UILabel alloc] init];
    _indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _indexLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _indexLabel.textColor = [UIColor tertiaryLabelColor];
    _indexLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_indexLabel];
    
    // 时间戳标签
    _timestampLabel = [[UILabel alloc] init];
    _timestampLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timestampLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    _timestampLabel.textColor = [UIColor secondaryLabelColor];
    _timestampLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:_timestampLabel];
    
    // 歌词文本标签
    _lyricsLabel = [[UILabel alloc] init];
    _lyricsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _lyricsLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _lyricsLabel.textColor = [UIColor labelColor];
    _lyricsLabel.numberOfLines = 0;
    [self.contentView addSubview:_lyricsLabel];
    
    // 时间微调按钮
    _decreaseTimeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_decreaseTimeButton setImage:[UIImage systemImageNamed:@"minus.circle"] forState:UIControlStateNormal];
    _decreaseTimeButton.tintColor = [UIColor systemOrangeColor];
    [_decreaseTimeButton addTarget:self action:@selector(decreaseTimeTapped) forControlEvents:UIControlEventTouchUpInside];
    
    _increaseTimeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_increaseTimeButton setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
    _increaseTimeButton.tintColor = [UIColor systemGreenColor];
    [_increaseTimeButton addTarget:self action:@selector(increaseTimeTapped) forControlEvents:UIControlEventTouchUpInside];
    
    _adjustButtonsStack = [[UIStackView alloc] initWithArrangedSubviews:@[_decreaseTimeButton, _increaseTimeButton]];
    _adjustButtonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _adjustButtonsStack.axis = UILayoutConstraintAxisHorizontal;
    _adjustButtonsStack.spacing = 8;
    _adjustButtonsStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentView addSubview:_adjustButtonsStack];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        // 状态指示器
        [_statusIndicator.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
        [_statusIndicator.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_statusIndicator.widthAnchor constraintEqualToConstant:4],
        [_statusIndicator.heightAnchor constraintEqualToConstant:32],
        
        // 行号
        [_indexLabel.leadingAnchor constraintEqualToAnchor:_statusIndicator.trailingAnchor constant:8],
        [_indexLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_indexLabel.widthAnchor constraintEqualToConstant:28],
        
        // 时间戳
        [_timestampLabel.leadingAnchor constraintEqualToAnchor:_indexLabel.trailingAnchor constant:8],
        [_timestampLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_timestampLabel.widthAnchor constraintEqualToConstant:80],
        
        // 歌词文本
        [_lyricsLabel.leadingAnchor constraintEqualToAnchor:_timestampLabel.trailingAnchor constant:12],
        [_lyricsLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
        [_lyricsLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        [_lyricsLabel.trailingAnchor constraintEqualToAnchor:_adjustButtonsStack.leadingAnchor constant:-8],
        
        // 微调按钮
        [_adjustButtonsStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [_adjustButtonsStack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_adjustButtonsStack.widthAnchor constraintEqualToConstant:72],
        [_adjustButtonsStack.heightAnchor constraintEqualToConstant:32],
    ]];
}

- (void)configureWithLine:(LRCEditableLine *)line isCurrent:(BOOL)isCurrent index:(NSInteger)index {
    self.currentLine = line;
    self.isCurrent = isCurrent;
    self.lineIndex = index;
    
    // 行号
    self.indexLabel.text = [NSString stringWithFormat:@"%ld", (long)(index + 1)];
    
    // 时间戳
    self.timestampLabel.text = [line formattedTimestamp];
    
    // 歌词文本
    self.lyricsLabel.text = line.text;
    
    // 更新样式
    [self updateStyles];
}

- (void)updateCurrentState:(BOOL)isCurrent {
    self.isCurrent = isCurrent;
    [self updateStyles];
}

- (void)updateStyles {
    if (self.isCurrent) {
        // 当前打轴行样式
        self.statusIndicator.backgroundColor = [UIColor systemBlueColor];
        self.lyricsLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.lyricsLabel.textColor = [UIColor systemBlueColor];
        self.contentView.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
        self.timestampLabel.textColor = [UIColor systemBlueColor];
    } else if (self.currentLine.isTimestamped) {
        // 已打轴行样式
        self.statusIndicator.backgroundColor = [UIColor systemGreenColor];
        self.lyricsLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        self.lyricsLabel.textColor = [UIColor labelColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.timestampLabel.textColor = [UIColor systemGreenColor];
    } else {
        // 未打轴行样式
        self.statusIndicator.backgroundColor = [UIColor clearColor];
        self.lyricsLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        self.lyricsLabel.textColor = [UIColor tertiaryLabelColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.timestampLabel.textColor = [UIColor tertiaryLabelColor];
    }
    
    // 微调按钮只在已打轴时显示
    self.adjustButtonsStack.hidden = !self.currentLine.isTimestamped;
}

- (void)playStampAnimation {
    // 闪烁动画
    UIColor *originalColor = self.contentView.backgroundColor;
    
    [UIView animateWithDuration:0.15 animations:^{
        self.contentView.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.3];
        self.statusIndicator.transform = CGAffineTransformMakeScale(1.5, 1.0);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 animations:^{
            self.contentView.backgroundColor = originalColor;
            self.statusIndicator.transform = CGAffineTransformIdentity;
        }];
    }];
}

#pragma mark - Actions

- (void)decreaseTimeTapped {
    if ([self.delegate respondsToSelector:@selector(lyricsLineCell:didAdjustTimestamp:)]) {
        [self.delegate lyricsLineCell:self didAdjustTimestamp:-0.1];
    }
}

- (void)increaseTimeTapped {
    if ([self.delegate respondsToSelector:@selector(lyricsLineCell:didAdjustTimestamp:)]) {
        [self.delegate lyricsLineCell:self didAdjustTimestamp:0.1];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    self.currentLine = nil;
    self.isCurrent = NO;
    self.contentView.backgroundColor = [UIColor clearColor];
    self.statusIndicator.backgroundColor = [UIColor clearColor];
    self.statusIndicator.transform = CGAffineTransformIdentity;
}

@end

