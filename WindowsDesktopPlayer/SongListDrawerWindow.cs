using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace SoundDesk;

public sealed record DrawerRow(string Title, string Artist, string Duration, string? CoverUrl, object Source);

/// <summary>Left-edge song drawer mirroring the Mac PlaylistDrawer: a 72×120 handle that
/// slides open to a 324 pt panel with local / NetEase / QQ / Kugou segments.</summary>
public sealed class SongListDrawerWindow : Window
{
    private const double HandleWidth = 72;
    private const double HandleHeight = 120;
    private const double DrawerWidth = 324;
    private const int PageSize = 40;

    private static readonly SolidColorBrush Muted = Frozen(Color.FromRgb(0xAA, 0xB2, 0xC6));
    private static readonly SolidColorBrush Accent = Frozen(Color.FromRgb(0x0A, 0x84, 0xFF));

    private readonly ObservableCollection<LocalTrack> _tracks;
    private readonly Action<LocalTrack> _play;
    private readonly Action<LocalTrack> _remove;
    private readonly Action<PlatformTrack, IReadOnlyList<PlatformTrack>> _playPlatform;
    private readonly Action _openConsole;
    private readonly PlatformMusicService _platform = new();
    private readonly ObservableCollection<DrawerRow> _rows = [];
    private readonly List<PlatformTrack> _platformTracks = [];
    private readonly DispatcherTimer _searchDebounce = new() { Interval = TimeSpan.FromMilliseconds(280) };

    private readonly Grid _root = new();
    private readonly Border _handle;
    private readonly Border _panel;
    private readonly TranslateTransform _slide = new();
    private readonly TextBlock _heading = new() { FontSize = 20, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White };
    private readonly StackPanel _segments = new() { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 10) };
    private readonly TextBox _search = new() { Height = 34, VerticalContentAlignment = VerticalAlignment.Center, ToolTip = "搜索歌曲或歌手" };
    private readonly TextBlock _searchHint = new() { Text = "搜索歌曲或歌手", Foreground = Muted, Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
    private readonly ScrollViewer _chipScroller = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Margin = new Thickness(0, 10, 0, 0), Height = 66 };
    private readonly StackPanel _chips = new() { Orientation = Orientation.Horizontal };
    private readonly TextBlock _status = new() { Foreground = Muted, FontSize = 11, Margin = new Thickness(2, 8, 0, 6), TextWrapping = TextWrapping.Wrap };
    private readonly ListBox _list = new() { Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Brushes.White };
    private readonly Border _loadingCard;
    private readonly TextBlock _loadingText = new() { Foreground = Brushes.White, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };

    private int _source;
    private int _generation;
    private bool _expanded;
    private bool _loadingPage;
    private bool _hasMore;
    private PlatformPlaylist? _activePlaylist;

    public SongListDrawerWindow(ObservableCollection<LocalTrack> tracks, Action<LocalTrack> play, Action<LocalTrack> remove,
        Action<PlatformTrack, IReadOnlyList<PlatformTrack>> playPlatform, Action openConsole)
    {
        _tracks = tracks;
        _play = play;
        _remove = remove;
        _playPlatform = playPlatform;
        _openConsole = openConsole;
        Title = "歌曲列表";
        Width = HandleWidth;
        Height = HandleHeight;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        AllowsTransparency = true;
        Background = Brushes.Transparent;

        _handle = BuildHandle();
        _loadingCard = BuildLoadingCard();
        _panel = new Border
        {
            Width = DrawerWidth,
            Background = new SolidColorBrush(Color.FromArgb(240, 18, 22, 34)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(56, 255, 255, 255)),
            BorderThickness = new Thickness(0, 0, 1, 0),
            Padding = new Thickness(16, 18, 16, 14),
            RenderTransform = _slide,
            Visibility = Visibility.Collapsed,
            Child = BuildPanel()
        };
        _root.Children.Add(_panel);
        _root.Children.Add(_handle);
        Content = _root;

        _list.ItemsSource = _rows;
        _list.ItemTemplate = (DataTemplate)XamlReader.Parse(RowTemplate);
        _list.ItemContainerStyle = BuildRowStyle();
        VirtualizingPanel.SetIsVirtualizing(_list, true);
        _list.PreviewMouseLeftButtonUp += (_, e) =>
        {
            if (ItemsControl.ContainerFromElement(_list, e.OriginalSource as DependencyObject) is ListBoxItem { DataContext: DrawerRow row })
                PlayRow(row);
        };
        _list.PreviewMouseRightButtonDown += (_, e) =>
        {
            if (ItemsControl.ContainerFromElement(_list, e.OriginalSource as DependencyObject) is ListBoxItem item)
                _list.SelectedItem = item.DataContext;
        };
        _list.ContextMenu = BuildContextMenu();
        _list.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler(OnListScrolled));
        _search.TextChanged += (_, _) =>
        {
            _searchHint.Visibility = _search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            if (_source == 0) RefreshLocalRows();
            else { _searchDebounce.Stop(); _searchDebounce.Start(); }
        };
        _searchDebounce.Tick += async (_, _) => { _searchDebounce.Stop(); await ReloadPlatformAsync(); };
        _tracks.CollectionChanged += OnTracksChanged;
        Loaded += (_, _) => PlaceCollapsed();
        Deactivated += (_, _) => { if (_expanded && !_loadingCard.IsVisible) SetExpanded(false); };
        SelectSource(0);
    }

    public void OpenDrawer()
    {
        if (!IsVisible) Show();
        SetExpanded(true);
        Activate();
    }

    /// <summary>Shows the bottom loading card while a platform track resolves; null hides it.</summary>
    public void SetLoading(string? message)
    {
        _loadingText.Text = message ?? "";
        _loadingCard.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private const string RowTemplate = """
        <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Grid Height="58">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="48" /><ColumnDefinition Width="*" /><ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <Border Width="48" Height="48" CornerRadius="8" Background="#22FFFFFF" ClipToBounds="True">
                    <Grid>
                        <TextBlock Text="♪" FontSize="18" Foreground="#AAB2C6" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        <Image Source="{Binding CoverUrl, TargetNullValue={x:Null}, FallbackValue={x:Null}}" Stretch="UniformToFill"
                               xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" RenderOptions.BitmapScalingMode="HighQuality">
                            <Image.Clip><RectangleGeometry Rect="0,0,48,48" RadiusX="8" RadiusY="8" /></Image.Clip>
                        </Image>
                    </Grid>
                </Border>
                <StackPanel Grid.Column="1" Margin="12,0,8,0" VerticalAlignment="Center">
                    <TextBlock Text="{Binding Title}" FontSize="13" FontWeight="Medium" Foreground="White" TextTrimming="CharacterEllipsis" />
                    <TextBlock Text="{Binding Artist}" FontSize="11" Foreground="#AAB2C6" Margin="0,3,0,0" TextTrimming="CharacterEllipsis" />
                </StackPanel>
                <TextBlock Grid.Column="2" Text="{Binding Duration}" FontSize="11" Foreground="#AAB2C6" VerticalAlignment="Center" />
            </Grid>
        </DataTemplate>
        """;

    private static Style BuildRowStyle()
    {
        var style = new Style(typeof(ListBoxItem), Application.Current.TryFindResource(typeof(ListBoxItem)) as Style);
        style.Setters.Add(new Setter(PaddingProperty, new Thickness(6, 0, 6, 0)));
        style.Setters.Add(new Setter(MarginProperty, new Thickness(0, 0, 0, 2)));
        style.Setters.Add(new Setter(HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
        style.Setters.Add(new Setter(CursorProperty, Cursors.Hand));
        return style;
    }

    private Border BuildHandle()
    {
        var content = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        content.Children.Add(new TextBlock { Text = "♫", FontSize = 22, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center });
        content.Children.Add(new TextBlock { Text = "歌曲", FontSize = 11, Foreground = Muted, Margin = new Thickness(0, 6, 0, 0), HorizontalAlignment = HorizontalAlignment.Center });
        content.Children.Add(new TextBlock { Text = "❯", FontSize = 13, Foreground = Muted, Margin = new Thickness(0, 4, 0, 0), HorizontalAlignment = HorizontalAlignment.Center });
        var handle = new Border
        {
            Width = HandleWidth, Height = HandleHeight,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center,
            Background = new SolidColorBrush(Color.FromArgb(225, 22, 28, 42)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(60, 255, 255, 255)),
            BorderThickness = new Thickness(0, 1, 1, 1),
            CornerRadius = new CornerRadius(0, 18, 18, 0),
            Cursor = Cursors.Hand, ToolTip = "展开歌曲列表", Child = content
        };
        handle.MouseLeftButtonUp += (_, _) => OpenDrawer();
        return handle;
    }

    private Border BuildLoadingCard()
    {
        var row = new DockPanel();
        var spinner = new TextBlock { Text = "◌", FontSize = 16, Foreground = Accent, Margin = new Thickness(0, 0, 10, 0), RenderTransformOrigin = new Point(0.5, 0.55) };
        var rotate = new RotateTransform();
        spinner.RenderTransform = rotate;
        rotate.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1)) { RepeatBehavior = RepeatBehavior.Forever });
        DockPanel.SetDock(spinner, Dock.Left);
        row.Children.Add(spinner);
        row.Children.Add(_loadingText);
        return new Border
        {
            Margin = new Thickness(0, 8, 0, 0), Padding = new Thickness(12, 10, 12, 10), CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(Color.FromArgb(46, 10, 132, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(110, 10, 132, 255)), BorderThickness = new Thickness(1),
            Visibility = Visibility.Collapsed, Child = row
        };
    }

    private UIElement BuildPanel()
    {
        var content = new DockPanel { LastChildFill = true };

        var header = new DockPanel { LastChildFill = false };
        var collapse = new Button { Content = "❮", Padding = new Thickness(10, 4, 10, 4), ToolTip = "收起歌曲列表" };
        collapse.Click += (_, _) => SetExpanded(false);
        DockPanel.SetDock(collapse, Dock.Right);
        header.Children.Add(collapse);
        header.Children.Add(_heading);
        DockPanel.SetDock(header, Dock.Top);
        content.Children.Add(header);

        string[] titles = ["本地", "网易云", "QQ", "酷狗"];
        for (var index = 0; index < titles.Length; index++)
        {
            var source = index;
            var segment = new ToggleButton { Content = titles[index], Width = (DrawerWidth - 32) / 4 - 4, Height = 30, Margin = new Thickness(0, 0, 4, 0), Style = SegmentStyle() };
            segment.Click += (_, _) => SelectSource(source);
            _segments.Children.Add(segment);
        }
        DockPanel.SetDock(_segments, Dock.Top);
        content.Children.Add(_segments);

        var searchHost = new Grid();
        searchHost.Children.Add(_search);
        searchHost.Children.Add(_searchHint);
        DockPanel.SetDock(searchHost, Dock.Top);
        content.Children.Add(searchHost);

        _chipScroller.Content = _chips;
        DockPanel.SetDock(_chipScroller, Dock.Top);
        content.Children.Add(_chipScroller);
        DockPanel.SetDock(_status, Dock.Top);
        content.Children.Add(_status);

        var openConsole = new Button { Content = "打开控制面板", Height = 34, Margin = new Thickness(0, 10, 0, 0) };
        openConsole.Click += (_, _) => { SetExpanded(false); _openConsole(); };
        DockPanel.SetDock(openConsole, Dock.Bottom);
        content.Children.Add(openConsole);
        DockPanel.SetDock(_loadingCard, Dock.Bottom);
        content.Children.Add(_loadingCard);

        content.Children.Add(_list);
        return content;
    }

    private static Style SegmentStyle()
    {
        const string xaml = """
            <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="ToggleButton">
                <Setter Property="Foreground" Value="#D8DCEA" />
                <Setter Property="FontSize" Value="12" />
                <Setter Property="Cursor" Value="Hand" />
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ToggleButton">
                            <Border x:Name="Root" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="#14FFFFFF" CornerRadius="8">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Root" Property="Background" Value="#24FFFFFF" /></Trigger>
                                <Trigger Property="IsChecked" Value="True">
                                    <Setter TargetName="Root" Property="Background" Value="#0A84FF" />
                                    <Setter Property="Foreground" Value="White" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
            """;
        return (Style)XamlReader.Parse(xaml);
    }

    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();
        var remove = new MenuItem { Header = "从曲库移除" };
        remove.Click += (_, _) => { if (_list.SelectedItem is DrawerRow { Source: LocalTrack track }) _remove(track); };
        menu.Items.Add(remove);
        menu.Opened += (_, _) => remove.IsEnabled = _list.SelectedItem is DrawerRow { Source: LocalTrack };
        return menu;
    }

    private void PlayRow(DrawerRow row)
    {
        if (row.Source is LocalTrack track) _play(track);
        else if (row.Source is PlatformTrack online) _playPlatform(online, _platformTracks.ToList());
    }

    private void SelectSource(int source)
    {
        _source = source;
        for (var index = 0; index < _segments.Children.Count; index++)
            ((ToggleButton)_segments.Children[index]).IsChecked = index == source;
        _search.Text = "";
        _activePlaylist = null;
        _chips.Children.Clear();
        _chipScroller.Visibility = source == 0 ? Visibility.Collapsed : Visibility.Visible;
        _searchDebounce.Stop();
        if (source == 0) RefreshLocalRows();
        else _ = ReloadPlatformAsync();
    }

    private MusicProvider Provider => _source switch { 1 => MusicProvider.NetEase, 2 => MusicProvider.QQ, _ => MusicProvider.Kugou };
    private string ProviderTitle => _source switch { 1 => "网易云", 2 => "QQ 音乐", _ => "酷狗" };

    private void OnTracksChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (_source == 0) RefreshLocalRows();
    }

    private void RefreshLocalRows()
    {
        _generation++;
        _hasMore = false;
        var query = _search.Text.Trim();
        _rows.Clear();
        foreach (var track in _tracks)
        {
            if (query.Length > 0 && !track.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                && !track.Artist.Contains(query, StringComparison.CurrentCultureIgnoreCase)) continue;
            _rows.Add(new DrawerRow(track.Title, track.Artist, track.DurationText, track.CoverUrl, track));
        }
        _heading.Text = $"歌曲 · {_tracks.Count}";
        _status.Text = _tracks.Count == 0 ? "在控制台搜索下载或选择本地歌曲后会出现在这里" : "单击播放 · 右键移除";
    }

    private async Task ReloadPlatformAsync()
    {
        var generation = ++_generation;
        var provider = Provider;
        _rows.Clear();
        _platformTracks.Clear();
        _hasMore = false;
        _heading.Text = ProviderTitle;
        var query = _search.Text.Trim();
        try
        {
            if (query.Length > 0)
            {
                _status.Text = "正在搜索…";
                var results = await _platform.SearchAsync(provider, query, PageSize);
                if (generation != _generation) return;
                AppendPlatformTracks(results);
                _status.Text = results.Count == 0 ? "没有找到相关歌曲" : $"{results.Count} 首搜索结果 · 单击播放";
                return;
            }
            if (_chips.Children.Count == 0)
            {
                _status.Text = "正在读取歌单…";
                var playlists = await _platform.GetUserPlaylistsAsync(provider);
                if (generation != _generation) return;
                foreach (var playlist in playlists) _chips.Children.Add(BuildChip(playlist));
                _activePlaylist ??= playlists.FirstOrDefault();
                if (playlists.Count == 0) { _status.Text = "账号没有可用歌单，可直接搜索"; return; }
            }
            if (_activePlaylist is not null) await LoadPlaylistPageAsync(_activePlaylist, generation);
        }
        catch (Exception error)
        {
            if (generation == _generation)
                _status.Text = $"{error.Message}{Environment.NewLine}可在控制台“平台账号”中登录后重试，或直接搜索。";
        }
    }

    private Button BuildChip(PlatformPlaylist playlist)
    {
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = playlist.Name, FontSize = 12, FontWeight = FontWeights.Medium, Foreground = Brushes.White, TextTrimming = TextTrimming.CharacterEllipsis });
        if (playlist.TrackCount is { } count)
            text.Children.Add(new TextBlock { Text = $"{count} 首", FontSize = 10, Foreground = Muted, Margin = new Thickness(0, 2, 0, 0) });
        var chip = new Button
        {
            Width = 140, Height = 54, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(10, 4, 10, 4),
            HorizontalContentAlignment = HorizontalAlignment.Left, Content = text, Tag = playlist
        };
        chip.Click += async (_, _) =>
        {
            _activePlaylist = playlist;
            HighlightChips();
            var generation = ++_generation;
            _rows.Clear();
            _platformTracks.Clear();
            try { await LoadPlaylistPageAsync(playlist, generation); }
            catch (Exception error) { if (generation == _generation) _status.Text = error.Message; }
        };
        return chip;
    }

    private void HighlightChips()
    {
        foreach (var chip in _chips.Children.OfType<Button>())
            chip.BorderBrush = ReferenceEquals(chip.Tag, _activePlaylist) ? Accent : Brushes.Transparent;
    }

    private async Task LoadPlaylistPageAsync(PlatformPlaylist playlist, int generation)
    {
        HighlightChips();
        _loadingPage = true;
        _status.Text = _platformTracks.Count == 0 ? $"正在读取《{playlist.Name}》…" : "正在加载更多…";
        try
        {
            var page = await _platform.GetPlaylistTracksAsync(playlist, PageSize, _platformTracks.Count);
            if (generation != _generation) return;
            AppendPlatformTracks(page);
            _hasMore = page.Count == PageSize;
            _status.Text = $"{playlist.Name} · {_platformTracks.Count} 首 · 单击播放";
        }
        finally { if (generation == _generation) _loadingPage = false; }
    }

    private void AppendPlatformTracks(IEnumerable<PlatformTrack> tracks)
    {
        foreach (var track in tracks)
        {
            _platformTracks.Add(track);
            _rows.Add(new DrawerRow(track.Title, track.Artist, track.DurationText, track.CoverUrl, track));
        }
    }

    private async void OnListScrolled(object sender, ScrollChangedEventArgs e)
    {
        if (_source == 0 || !_hasMore || _loadingPage || _activePlaylist is null || _search.Text.Trim().Length > 0) return;
        if (e.VerticalOffset + e.ViewportHeight < e.ExtentHeight - 3) return;
        var generation = _generation;
        try { await LoadPlaylistPageAsync(_activePlaylist, generation); }
        catch (Exception error) { if (generation == _generation) _status.Text = error.Message; }
    }

    private void PlaceCollapsed()
    {
        var work = SystemParameters.WorkArea;
        Width = HandleWidth;
        Height = HandleHeight;
        Left = work.Left;
        Top = work.Top + (work.Height - HandleHeight) / 2;
    }

    private void SetExpanded(bool expanded)
    {
        if (_expanded == expanded) return;
        _expanded = expanded;
        var duration = TimeSpan.FromMilliseconds(220);
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        if (expanded)
        {
            var work = SystemParameters.WorkArea;
            Left = work.Left;
            Top = work.Top;
            Width = DrawerWidth;
            Height = work.Height;
            _handle.Visibility = Visibility.Collapsed;
            _panel.Visibility = Visibility.Visible;
            _slide.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-DrawerWidth, 0, duration) { EasingFunction = ease });
        }
        else
        {
            var animation = new DoubleAnimation(0, -DrawerWidth, duration) { EasingFunction = ease };
            animation.Completed += (_, _) =>
            {
                if (_expanded) return;
                _panel.Visibility = Visibility.Collapsed;
                _handle.Visibility = Visibility.Visible;
                PlaceCollapsed();
            };
            _slide.BeginAnimation(TranslateTransform.XProperty, animation);
        }
    }

    private static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
