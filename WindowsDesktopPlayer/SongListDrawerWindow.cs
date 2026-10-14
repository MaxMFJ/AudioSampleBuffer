using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace SoundDesk;

public sealed class SongListDrawerWindow : Window
{
    private const double HandleWidth = 72;
    private const double DrawerWidth = 340;
    private readonly ObservableCollection<LocalTrack> _tracks;
    private readonly ListCollectionView _view;
    private readonly Action<LocalTrack> _play;
    private readonly Action<LocalTrack> _remove;
    private readonly Action<PlatformTrack> _playPlatform;
    private readonly PlatformMusicService _platform = new();
    private readonly ObservableCollection<PlatformTrack> _platformTracks = [];
    private readonly ComboBox _sourcePicker = new() { Margin = new Thickness(0, 0, 0, 8), Height = 32 };
    private readonly ComboBox _playlistPicker = new() { Margin = new Thickness(0, 0, 0, 8), Height = 32, DisplayMemberPath = nameof(PlatformPlaylist.Name) };
    private readonly TextBlock _status = new() { Foreground = Brushes.LightGray, FontSize = 11, Margin = new Thickness(0, 0, 0, 6) };
    private readonly Button _more = new() { Content = "加载更多", Margin = new Thickness(0, 0, 0, 8), Padding = new Thickness(8, 4, 8, 4), Visibility = Visibility.Collapsed };
    private int _platformOffset;
    private PlatformPlaylist? _activePlaylist;
    private readonly Button _toggle = new() { Content = "❯", FontSize = 22, Foreground = Brushes.White, Background = Brushes.Transparent, BorderThickness = new Thickness(0) };
    private readonly TextBlock _heading = new() { Text = "歌曲", FontSize = 20, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White };
    private readonly TextBox _search = new() { Height = 36, Margin = new Thickness(0, 12, 0, 12), VerticalContentAlignment = VerticalAlignment.Center };
    private readonly ListBox _list = new() { Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Brushes.White };
    private readonly Border _panel;
    private bool _expanded;

    public SongListDrawerWindow(ObservableCollection<LocalTrack> tracks, Action<LocalTrack> play, Action<LocalTrack> remove, Action<PlatformTrack> playPlatform)
    {
        _tracks = tracks;
        _play = play;
        _remove = remove;
        _playPlatform = playPlatform;
        _view = new ListCollectionView((System.Collections.IList)tracks) { Filter = FilterTrack };
        _list.ItemsSource = _view;
        Title = "歌曲列表";
        Width = HandleWidth;
        Height = 120;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = false;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        _panel = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(238, 20, 26, 40)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(80, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(0, 18, 18, 0),
            Padding = new Thickness(14),
            Child = BuildPanel()
        };
        _toggle.Click += (_, _) => SetExpanded(!_expanded);
        Content = _panel;
        Loaded += (_, _) => PlaceCollapsed();
        _search.TextChanged += (_, _) => _view.Refresh();
        _sourcePicker.ItemsSource = new[] { "本地歌曲", "网易云歌单", "QQ 音乐歌单", "酷狗歌单" };
        _sourcePicker.SelectedIndex = 0;
        _sourcePicker.SelectionChanged += async (_, _) => await SelectSourceAsync();
        _playlistPicker.SelectionChanged += async (_, _) =>
        {
            if (_playlistPicker.SelectedItem is PlatformPlaylist playlist) await LoadPlatformPlaylistAsync(playlist, reset: true);
        };
        _more.Click += async (_, _) => { if (_activePlaylist is not null) await LoadPlatformPlaylistAsync(_activePlaylist, reset: false); };
        _list.MouseDoubleClick += (_, _) =>
        {
            if (_list.SelectedItem is LocalTrack track) _play(track);
            else if (_list.SelectedItem is PlatformTrack online) _playPlatform(online);
        };
        _list.ContextMenu = BuildContextMenu();
        _list.PreviewMouseRightButtonDown += (_, e) =>
        {
            if (ItemsControl.ContainerFromElement(_list, e.OriginalSource as DependencyObject) is ListBoxItem item)
                _list.SelectedItem = item.DataContext;
        };
        _tracks.CollectionChanged += (_, _) => { _view.Refresh(); UpdateHeading(); };
        UpdateHeading();
    }

    public void OpenDrawer()
    {
        if (!IsVisible) Show();
        SetExpanded(true);
        Activate();
    }

    private UIElement BuildPanel()
    {
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(HandleWidth - 28) });
        root.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(_toggle, 0);
        root.Children.Add(_toggle);
        var content = new DockPanel { Margin = new Thickness(14, 0, 0, 0), LastChildFill = true };
        var header = new DockPanel { LastChildFill = false };
        var collapse = new Button { Content = "❮", Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(8, 0, 0, 0), ToolTip = "收起歌曲列表" };
        collapse.Click += (_, _) => SetExpanded(false);
        DockPanel.SetDock(collapse, Dock.Right);
        header.Children.Add(collapse);
        header.Children.Add(_heading);
        DockPanel.SetDock(header, Dock.Top);
        content.Children.Add(header);
        DockPanel.SetDock(_status, Dock.Top);
        content.Children.Add(_status);
        DockPanel.SetDock(_more, Dock.Top);
        content.Children.Add(_more);
        DockPanel.SetDock(_playlistPicker, Dock.Top);
        content.Children.Add(_playlistPicker);
        DockPanel.SetDock(_sourcePicker, Dock.Top);
        content.Children.Add(_sourcePicker);
        DockPanel.SetDock(_search, Dock.Top);
        _search.ToolTip = "搜索歌曲或歌手";
        content.Children.Add(_search);
        var templateRoot = new FrameworkElementFactory(typeof(StackPanel));
        var title = new FrameworkElementFactory(typeof(TextBlock));
        title.SetBinding(TextBlock.TextProperty, new Binding(nameof(LocalTrack.Title)));
        title.SetValue(TextBlock.FontWeightProperty, FontWeights.Medium);
        var artist = new FrameworkElementFactory(typeof(TextBlock));
        artist.SetBinding(TextBlock.TextProperty, new Binding(nameof(LocalTrack.Artist)));
        artist.SetValue(TextBlock.ForegroundProperty, Brushes.LightGray);
        artist.SetValue(TextBlock.FontSizeProperty, 11d);
        templateRoot.AppendChild(title);
        templateRoot.AppendChild(artist);
        _list.ItemTemplate = new DataTemplate { VisualTree = templateRoot };
        content.Children.Add(_list);
        Grid.SetColumn(content, 1);
        root.Children.Add(content);
        return root;
    }

    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();
        var remove = new MenuItem { Header = "从曲库移除" };
        remove.Click += (_, _) => { if (_list.SelectedItem is LocalTrack track) _remove(track); };
        menu.Items.Add(remove);
        return menu;
    }

    private bool FilterTrack(object item)
    {
        if (item is not LocalTrack track) return false;
        var query = _search.Text.Trim();
        return query.Length == 0 || track.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)
            || track.Artist.Contains(query, StringComparison.CurrentCultureIgnoreCase);
    }

    private void UpdateHeading() => _heading.Text = $"歌曲 · {_tracks.Count}";

    private async Task SelectSourceAsync()
    {
        if (_sourcePicker.SelectedIndex <= 0)
        {
            _list.ItemsSource = _view;
            _playlistPicker.Visibility = Visibility.Collapsed;
            _more.Visibility = Visibility.Collapsed;
            _status.Text = "";
            UpdateHeading();
            return;
        }
        var provider = _sourcePicker.SelectedIndex switch { 1 => MusicProvider.NetEase, 2 => MusicProvider.QQ, _ => MusicProvider.Kugou };
        _list.ItemsSource = _platformTracks;
        _playlistPicker.Visibility = Visibility.Visible;
        _more.Visibility = Visibility.Collapsed;
        _status.Text = "正在读取平台歌单…";
        try
        {
            var playlists = await _platform.GetUserPlaylistsAsync(provider);
            _playlistPicker.ItemsSource = playlists;
            _playlistPicker.SelectedIndex = playlists.Count > 0 ? 0 : -1;
            if (playlists.Count == 0) _status.Text = "账号没有可用歌单";
        }
        catch (Exception error) { _status.Text = error.Message; _playlistPicker.ItemsSource = null; }
    }

    private async Task LoadPlatformPlaylistAsync(PlatformPlaylist playlist, bool reset)
    {
        _activePlaylist = playlist;
        if (reset) { _platformOffset = 0; _platformTracks.Clear(); }
        _status.Text = "正在读取歌曲…";
        try
        {
            var page = await _platform.GetPlaylistTracksAsync(playlist, 50, _platformOffset);
            foreach (var track in page) _platformTracks.Add(track);
            _platformOffset += page.Count;
            _status.Text = $"{_platformTracks.Count} 首 · 双击播放";
            _more.Visibility = page.Count == 50 ? Visibility.Visible : Visibility.Collapsed;
            UpdateHeading();
        }
        catch (Exception error) { _status.Text = error.Message; }
    }

    private void PlaceCollapsed()
    {
        var work = SystemParameters.WorkArea;
        Left = work.Left;
        Top = work.Top + (work.Height - Height) / 2;
    }

    private void SetExpanded(bool expanded)
    {
        if (_expanded == expanded) return;
        _expanded = expanded;
        var work = SystemParameters.WorkArea;
        if (expanded)
        {
            Width = DrawerWidth;
            Height = work.Height;
            Left = work.Left;
            Top = work.Top;
            _toggle.Visibility = Visibility.Collapsed;
            _panel.CornerRadius = new CornerRadius(0, 18, 18, 0);
        }
        else
        {
            Width = HandleWidth;
            Height = 120;
            PlaceCollapsed();
            _toggle.Visibility = Visibility.Visible;
        }
    }
}
