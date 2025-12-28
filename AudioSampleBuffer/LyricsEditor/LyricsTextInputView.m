//
//  LyricsTextInputView.m
//  AudioSampleBuffer
//
//  歌词文本输入/编辑视图 - 用于粘贴和编辑歌词文本
//

#import "LyricsTextInputView.h"

@interface LyricsTextInputView () <UITextViewDelegate>

/// 标题标签
@property (nonatomic, strong) UILabel *titleLabel;

/// 说明标签
@property (nonatomic, strong) UILabel *hintLabel;

/// 文本输入框
@property (nonatomic, strong) UITextView *textView;

/// 行数预览标签
@property (nonatomic, strong) UILabel *lineCountLabel;

/// 粘贴按钮
@property (nonatomic, strong) UIButton *pasteButton;

/// 清空按钮
@property (nonatomic, strong) UIButton *clearButton;

/// 取消按钮
@property (nonatomic, strong) UIButton *cancelButton;

/// 确认按钮
@property (nonatomic, strong) UIButton *confirmButton;

/// 按钮容器
@property (nonatomic, strong) UIStackView *buttonStack;

/// 占位符标签
@property (nonatomic, strong) UILabel *placeholderLabel;

@end

@implementation LyricsTextInputView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor systemBackgroundColor];
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = @"导入歌词";
    _titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    _titleLabel.textColor = [UIColor labelColor];
    [self addSubview:_titleLabel];
    
    // 说明
    _hintLabel = [[UILabel alloc] init];
    _hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _hintLabel.text = @"粘贴完整歌词文本，每行一句歌词";
    _hintLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _hintLabel.textColor = [UIColor secondaryLabelColor];
    [self addSubview:_hintLabel];
    
    // 快捷按钮
    _pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_pasteButton setTitle:@"从剪贴板粘贴" forState:UIControlStateNormal];
    [_pasteButton setImage:[UIImage systemImageNamed:@"doc.on.clipboard"] forState:UIControlStateNormal];
    _pasteButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [_pasteButton addTarget:self action:@selector(pasteButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    _clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_clearButton setTitle:@"清空" forState:UIControlStateNormal];
    [_clearButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    _clearButton.tintColor = [UIColor systemRedColor];
    _clearButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [_clearButton addTarget:self action:@selector(clearButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIStackView *toolStack = [[UIStackView alloc] initWithArrangedSubviews:@[_pasteButton, _clearButton]];
    toolStack.translatesAutoresizingMaskIntoConstraints = NO;
    toolStack.axis = UILayoutConstraintAxisHorizontal;
    toolStack.spacing = 20;
    toolStack.distribution = UIStackViewDistributionFillEqually;
    [self addSubview:toolStack];
    
    // 文本输入框
    _textView = [[UITextView alloc] init];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.font = [UIFont systemFontOfSize:16];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _textView.layer.cornerRadius = 12;
    _textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    _textView.delegate = self;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self addSubview:_textView];
    
    // 占位符
    [self updatePlaceholder];
    
    // 行数预览
    _lineCountLabel = [[UILabel alloc] init];
    _lineCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _lineCountLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _lineCountLabel.textColor = [UIColor tertiaryLabelColor];
    _lineCountLabel.textAlignment = NSTextAlignmentRight;
    _lineCountLabel.text = @"0 行";
    [self addSubview:_lineCountLabel];
    
    // 底部按钮
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    [_cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    _confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_confirmButton setTitle:@"确认导入" forState:UIControlStateNormal];
    _confirmButton.backgroundColor = [UIColor systemBlueColor];
    [_confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _confirmButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _confirmButton.layer.cornerRadius = 12;
    [_confirmButton addTarget:self action:@selector(confirmButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    _buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[_cancelButton, _confirmButton]];
    _buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonStack.axis = UILayoutConstraintAxisHorizontal;
    _buttonStack.spacing = 16;
    _buttonStack.distribution = UIStackViewDistributionFillEqually;
    [self addSubview:_buttonStack];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        // 标题
        [_titleLabel.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:20],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        
        // 说明
        [_hintLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8],
        [_hintLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_hintLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        
        // 工具按钮
        [toolStack.topAnchor constraintEqualToAnchor:_hintLabel.bottomAnchor constant:16],
        [toolStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [toolStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20],
        
        // 文本输入框
        [_textView.topAnchor constraintEqualToAnchor:toolStack.bottomAnchor constant:16],
        [_textView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_textView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        
        // 行数
        [_lineCountLabel.topAnchor constraintEqualToAnchor:_textView.bottomAnchor constant:8],
        [_lineCountLabel.trailingAnchor constraintEqualToAnchor:_textView.trailingAnchor],
        
        // 底部按钮
        [_buttonStack.topAnchor constraintEqualToAnchor:_lineCountLabel.bottomAnchor constant:16],
        [_buttonStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_buttonStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [_buttonStack.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [_buttonStack.heightAnchor constraintEqualToConstant:50],
    ]];
}

#pragma mark - Properties

- (void)setInitialText:(NSString *)initialText {
    _initialText = [initialText copy];
    self.textView.text = initialText;
    [self updateLineCount];
    [self updatePlaceholder];
}

- (NSInteger)previewLineCount {
    return [self calculateLineCount:self.textView.text];
}

#pragma mark - Public Methods

- (void)clearInput {
    self.textView.text = @"";
    [self updateLineCount];
    [self updatePlaceholder];
}

- (void)pasteFromClipboard {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.string.length > 0) {
        self.textView.text = pasteboard.string;
        [self updateLineCount];
        [self updatePlaceholder];
    }
}

#pragma mark - Actions

- (void)pasteButtonTapped {
    [self pasteFromClipboard];
}

- (void)clearButtonTapped {
    [self clearInput];
}

- (void)cancelButtonTapped {
    [self.textView resignFirstResponder];
    
    if ([self.delegate respondsToSelector:@selector(lyricsTextInputViewDidCancel:)]) {
        [self.delegate lyricsTextInputViewDidCancel:self];
    }
}

- (void)confirmButtonTapped {
    // 🔧 先关闭键盘
    [self.textView resignFirstResponder];
    [self endEditing:YES];
    
    NSString *text = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (text.length == 0) {
        // 震动反馈
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeError];
        
        // 抖动动画
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        animation.duration = 0.5;
        animation.values = @[@(-10), @(10), @(-8), @(8), @(-5), @(5), @(0)];
        [self.textView.layer addAnimation:animation forKey:@"shake"];
        
        return;
    }
    
    // 🔧 延迟通知代理，确保键盘完全关闭后再切换视图
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(lyricsTextInputView:didConfirmWithText:)]) {
            [self.delegate lyricsTextInputView:self didConfirmWithText:text];
        }
    });
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [self updateLineCount];
    [self updatePlaceholder];
}

#pragma mark - Helpers

- (void)updateLineCount {
    NSInteger count = [self calculateLineCount:self.textView.text];
    self.lineCountLabel.text = [NSString stringWithFormat:@"%ld 行", (long)count];
}

- (NSInteger)calculateLineCount:(NSString *)text {
    if (!text || text.length == 0) {
        return 0;
    }
    
    // 统一换行符
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSInteger count = 0;
    
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            count++;
        }
    }
    
    return count;
}

- (void)updatePlaceholder {
    // 使用实例变量作为占位符（避免 static 导致的问题）
    if (!_placeholderLabel) {
        _placeholderLabel = [[UILabel alloc] init];
        _placeholderLabel.text = @"在此粘贴或输入歌词文本...\n\n每行一句歌词，例如：\n我是一句歌词\n这是第二句\n这是第三句...";
        _placeholderLabel.font = [UIFont systemFontOfSize:16];
        _placeholderLabel.textColor = [UIColor placeholderTextColor];
        _placeholderLabel.numberOfLines = 0;
        _placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.textView addSubview:_placeholderLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_placeholderLabel.topAnchor constraintEqualToAnchor:self.textView.topAnchor constant:12],
            [_placeholderLabel.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor constant:16],
            [_placeholderLabel.trailingAnchor constraintEqualToAnchor:self.textView.trailingAnchor constant:-16],
        ]];
    }
    
    _placeholderLabel.hidden = self.textView.text.length > 0;
}

@end

