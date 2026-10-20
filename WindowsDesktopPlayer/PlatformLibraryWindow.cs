using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;

namespace SoundDesk;

/// <summary>Personal platform playlists and their tracks, mirroring the Mac platform library window.</summary>
public sealed class PlatformLibraryWindow : Window
{
    private const int PageSize = 100;
    private readonly PlatformMusicService _platform = new();
    private readonly Action<PlatformTrack, IReadOnlyList<PlatformTrack>> _play;
    private readonly ObservableCollection<PlatformPlaylist> _playlists = [];
    private readonly ObservableCollection<PlatformTrack> _tracks = [];
    private readonly ComboBox _provider = new() { Width = 130, Height = 32 };
    private readonly ListBox _playlistList = new() { DisplayMemberPath = nameof(PlatformPlaylist.Name) };
    private readonly ListBox _trackList = new();
    private readonly TextBlock _status = new() { FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
    private readonly Button _more = new() { Content = "加载更多", Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(0, 10, 0, 0), HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    private int _generation;

    public PlatformLibraryWindow(Action<PlatformTrack, IReadOnlyList<PlatformTrack>> play)
    {
        _play = play;
        Title = "平台歌单";
        Width = 860;
        Height = 560;
        MinWidth = 700;
        MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(0x14, 0x1A, 0x28));
        Foreground = Brushes.White;
        _status.Foreground = (Brush)Application.Current.FindResource("MutedBrush");

        var root = new DockPanel { Margin = new Thickness(20) };
        var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 14) };
        _provider.ItemsSource = new[] { "网易云音乐", "QQ 音乐", "酷狗音乐" };
        _provider.SelectedIndex = 0;
        _provider.SelectionChanged += async (_, _) => await LoadPlaylistsAsync();
        var refresh = new Button { Content = "刷新", Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(10, 0, 0, 0) };
        refresh.Click += async (_, _) => await LoadPlaylistsAsync();
        toolbar.Children.Add(_provider);
        toolbar.Children.Add(refresh);
        toolbar.Children.Add(_status);
        DockPanel.SetDock(toolbar, Dock.Top);
        root.Children.Add(toolbar);

        var columns = new Grid();
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        columns.ColumnDefinitions.Add(new ColumnDefinition());
        _playlistList.ItemsSource = _playlists;
        _playlistList.SelectionChanged += async (_, _) =>
        {
            if (_playlistList.SelectedItem is PlatformPlaylist playlist) await LoadTracksAsync(playlist, reset: true);
        };
        columns.Children.Add(_playlistList);

        var trackPanel = new DockPanel();
        DockPanel.SetDock(_more, Dock.Bottom);
        trackPanel.Children.Add(_more);
        _more.Click += async (_, _) =>
        {
            if (_playlistList.SelectedItem is PlatformPlaylist playlist) await LoadTracksAsync(playlist, reset: false);
        };
        _trackList.ItemsSource = _tracks;
        _trackList.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        _trackList.ItemTemplate = (DataTemplate)XamlReader.Parse(TrackTemplate);
        _trackList.AddHandler(Button.ClickEvent, new RoutedEventHandler((_, e) =>
        {
            if ((e.OriginalSource as FrameworkElement)?.DataContext is PlatformTrack track) _play(track, _tracks.ToList());
        }));
        trackPanel.Children.Add(_trackList);
        Grid.SetColumn(trackPanel, 2);
        columns.Children.Add(trackPanel);
        root.Children.Add(columns);
        Content = root;
        Loaded += async (_, _) => await LoadPlaylistsAsync();
    }

    private const string TrackTemplate = """
        <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
            <Grid Height="40">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" /><ColumnDefinition Width="0.6*" /><ColumnDefinition Width="56" /><ColumnDefinition Width="72" />
                </Grid.ColumnDefinitions>
                <TextBlock Text="{Binding Title}" FontSize="13" FontWeight="Medium" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,10,0" />
                <TextBlock Grid.Column="1" Text="{Binding Artist}" FontSize="12" Foreground="#AAB2C6" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,10,0" />
                <TextBlock Grid.Column="2" Text="{Binding DurationText}" FontSize="12" Foreground="#AAB2C6" VerticalAlignment="Center" />
                <Button Grid.Column="3" Content="播放" Height="28" Padding="0" />
            </Grid>
        </DataTemplate>
        """;

    private MusicProvider SelectedProvider => _provider.SelectedIndex switch { 1 => MusicProvider.QQ, 2 => MusicProvider.Kugou, _ => MusicProvider.NetEase };

    private async Task LoadPlaylistsAsync()
    {
        var generation = ++_generation;
        _playlists.Clear();
        _tracks.Clear();
        _more.Visibility = Visibility.Collapsed;
        _status.Text = "正在读取歌单…";
        try
        {
            var playlists = await _platform.GetUserPlaylistsAsync(SelectedProvider);
            if (generation != _generation) return;
            foreach (var playlist in playlists) _playlists.Add(playlist);
            _status.Text = playlists.Count == 0 ? "账号没有可用歌单" : $"{playlists.Count} 个歌单";
            if (playlists.Count > 0) _playlistList.SelectedIndex = 0;
        }
        catch (Exception error)
        {
            if (generation == _generation) _status.Text = $"{error.Message}（可在“平台账号”中登录）";
        }
    }

    private async Task LoadTracksAsync(PlatformPlaylist playlist, bool reset)
    {
        var generation = ++_generation;
        if (reset) _tracks.Clear();
        _more.Visibility = Visibility.Collapsed;
        _status.Text = $"正在读取《{playlist.Name}》…";
        try
        {
            var page = await _platform.GetPlaylistTracksAsync(playlist, PageSize, _tracks.Count);
            if (generation != _generation) return;
            foreach (var track in page) _tracks.Add(track);
            _more.Visibility = page.Count == PageSize ? Visibility.Visible : Visibility.Collapsed;
            _status.Text = $"{playlist.Name} · {_tracks.Count} 首";
        }
        catch (Exception error)
        {
            if (generation == _generation) _status.Text = error.Message;
        }
    }
}
