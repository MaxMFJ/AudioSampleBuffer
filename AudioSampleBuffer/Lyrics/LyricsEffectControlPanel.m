//
//  LyricsEffectControlPanel.m
//  AudioSampleBuffer
//
//  歌词特效控制面板实现
//

#import "LyricsEffectControlPanel.h"

@interface LyricsEffectControlPanel ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *toggleVisibilityButton;
@property (nonatomic, strong) UICollectionView *effectCollectionView;
@property (nonatomic, strong) NSArray<LyricsEffectInfo *> *effects;

@end

@implementation LyricsEffectControlPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.hidden = YES;
    self.alpha = 0;
    
    // 获取所有特效
    _effects = [LyricsEffectManager allEffects];
    
    // 内容容器
    _contentView = [[UIView alloc] init];
    _contentView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
    _contentView.layer.cornerRadius = 20;
    _contentView.layer.borderWidth = 2;
    _contentView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.5 alpha:1.0].CGColor;
    
    // 添加发光效果
    _contentView.layer.shadowColor = [UIColor cyanColor].CGColor;
    _contentView.layer.shadowOffset = CGSizeZero;
    _contentView.layer.shadowRadius = 15;
    _contentView.layer.shadowOpacity = 0.5;
    
    [self addSubview:_contentView];
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"歌词特效选择器";
    _titleLabel.font = [UIFont boldSystemFontOfSize:20];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_contentView addSubview:_titleLabel];
    
    // 关闭按钮
    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    _closeButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8];
    _closeButton.layer.cornerRadius = 20;
    [_closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_closeButton];
    
    // 歌词显示/隐藏切换按钮
    _toggleVisibilityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _toggleVisibilityButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    _toggleVisibilityButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.9];
    _toggleVisibilityButton.layer.cornerRadius = 22;
    _toggleVisibilityButton.layer.borderWidth = 2;
    _toggleVisibilityButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0].CGColor;
    [_toggleVisibilityButton addTarget:self action:@selector(toggleVisibilityButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_toggleVisibilityButton];
    
    // 默认歌词可见
    _lyricsVisible = YES;
    [self updateToggleButtonAppearance];
    
    // 集合视图布局
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumInteritemSpacing = 15;
    layout.minimumLineSpacing = 15;
    layout.sectionInset = UIEdgeInsetsMake(15, 15, 15, 15);
    
    // 集合视图
    _effectCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _effectCollectionView.backgroundColor = [UIColor clearColor];
    _effectCollectionView.delegate = self;
    _effectCollectionView.dataSource = self;
    _effectCollectionView.showsVerticalScrollIndicator = NO;
    [_effectCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"EffectCell"];
    [_contentView addSubview:_effectCollectionView];
    
    _currentEffect = LyricsEffectTypeNone;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat padding = 20;
    CGFloat contentWidth = self.bounds.size.width - 2 * padding;
    CGFloat contentHeight = MIN(500, self.bounds.size.height - 100);
    
    _contentView.frame = CGRectMake(padding, 
                                    (self.bounds.size.height - contentHeight) / 2,
                                    contentWidth, 
                                    contentHeight);
    
    _closeButton.frame = CGRectMake(contentWidth - 50, 10, 40, 40);
    _titleLabel.frame = CGRectMake(20, 15, contentWidth - 90, 30);
    
    // 歌词显示/隐藏切换按钮 - 放在标题下方
    CGFloat toggleButtonWidth = 160;
    CGFloat toggleButtonHeight = 44;
    _toggleVisibilityButton.frame = CGRectMake((contentWidth - toggleButtonWidth) / 2, 
                                                55, 
                                                toggleButtonWidth, 
                                                toggleButtonHeight);
    
    // 集合视图位置下移，为切换按钮留出空间
    _effectCollectionView.frame = CGRectMake(0, 110, contentWidth, contentHeight - 110);
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _effects.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"EffectCell" forIndexPath:indexPath];
    
    // 清除之前的子视图
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }
    
    LyricsEffectInfo *info = _effects[indexPath.item];
    BOOL isSelected = (info.type == _currentEffect);
    
    // 设置背景
    cell.contentView.backgroundColor = isSelected ? 
        [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:0.9] : 
        [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:0.8];
    cell.contentView.layer.cornerRadius = 15;
    cell.contentView.layer.borderWidth = isSelected ? 3 : 1;
    cell.contentView.layer.borderColor = isSelected ? 
        [UIColor cyanColor].CGColor : 
        [UIColor colorWithWhite:0.5 alpha:0.5].CGColor;
    
    // 添加发光效果（选中状态）
    if (isSelected) {
        cell.contentView.layer.shadowColor = [UIColor cyanColor].CGColor;
        cell.contentView.layer.shadowOffset = CGSizeZero;
        cell.contentView.layer.shadowRadius = 10;
        cell.contentView.layer.shadowOpacity = 0.8;
    } else {
        cell.contentView.layer.shadowOpacity = 0;
    }
    
    // 图标（SF Symbols）
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 10, cell.contentView.bounds.size.width, 48)];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tintColor = [UIColor whiteColor];
    if (info.iconName.length > 0) {
        UIImage *icon = [UIImage systemImageNamed:info.iconName];
        if (icon) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightRegular];
            iconView.image = [icon imageWithConfiguration:config];
        }
    }
    [cell.contentView addSubview:iconView];
    
    // 特效名称
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 60, cell.contentView.bounds.size.width - 10, 25)];
    nameLabel.text = info.name;
    nameLabel.font = [UIFont boldSystemFontOfSize:14];
    nameLabel.textColor = [UIColor whiteColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [cell.contentView addSubview:nameLabel];
    
    // 描述
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 88, cell.contentView.bounds.size.width - 10, 30)];
    descLabel.text = info.effectDescription;
    descLabel.font = [UIFont systemFontOfSize:10];
    descLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 2;
    [cell.contentView addSubview:descLabel];
    
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    LyricsEffectInfo *info = _effects[indexPath.item];
    _currentEffect = info.type;
    
    // 刷新选中状态
    [collectionView reloadData];
    
    // 通知代理
    if ([_delegate respondsToSelector:@selector(lyricsEffectDidChange:)]) {
        [_delegate lyricsEffectDidChange:_currentEffect];
    }
    
    // 添加触觉反馈
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    
    NSLog(@"选择歌词特效: %@ (%@)", info.name, info.iconName);
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = (collectionView.bounds.size.width - 60) / 2; // 2列布局
    return CGSizeMake(width, 130);
}

#pragma mark - Public Methods

- (void)showAnimated:(BOOL)animated {
    self.hidden = NO;
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 1.0;
            self.contentView.transform = CGAffineTransformIdentity;
        }];
    } else {
        self.alpha = 1.0;
    }
    
    // 滚动到选中项
    if (_currentEffect >= 0 && _currentEffect < _effects.count) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:_currentEffect inSection:0];
        [_effectCollectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    }
}

- (void)hideAnimated:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.hidden = YES;
        }];
    } else {
        self.alpha = 0.0;
        self.hidden = YES;
    }
}

- (void)closeButtonTapped {
    [self hideAnimated:YES];
}

- (void)toggleVisibilityButtonTapped {
    _lyricsVisible = !_lyricsVisible;
    [self updateToggleButtonAppearance];
    
    // 通知代理
    if ([_delegate respondsToSelector:@selector(lyricsVisibilityDidChange:)]) {
        [_delegate lyricsVisibilityDidChange:_lyricsVisible];
    }
    
    // 添加触觉反馈
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    
    NSLog(@"歌词显示状态切换: %@", _lyricsVisible ? @"显示" : @"隐藏");
}

- (void)updateToggleButtonAppearance {
    if (_lyricsVisible) {
        [_toggleVisibilityButton setTitle:@"显示歌词" forState:UIControlStateNormal];
        [_toggleVisibilityButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _toggleVisibilityButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.9];
        _toggleVisibilityButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0].CGColor;
    } else {
        [_toggleVisibilityButton setTitle:@"隐藏歌词" forState:UIControlStateNormal];
        [_toggleVisibilityButton setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
        _toggleVisibilityButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.9];
        _toggleVisibilityButton.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:1.0].CGColor;
    }
}

#pragma mark - Setter

- (void)setLyricsVisible:(BOOL)lyricsVisible {
    _lyricsVisible = lyricsVisible;
    [self updateToggleButtonAppearance];
}

@end

