using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace SoundDesk;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<LocalTrack> _tracks = [];
    private IReadOnlyList<LocalTrack> _playbackQueue = [];
    private IReadOnlyList<PlatformTrack> _platformQueue = [];
    private int _platformIndex = -1;
    private int _platformGeneration;
    private readonly DispatcherTimer _positionTimer;
    private readonly DispatcherTimer _visualTimer;
    private readonly AudioReactiveMonitor _reactiveMonitor = new();
    private readonly DesktopWallpaperController _desktopWallpaper;
    private readonly string _libraryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "library.json");
    private readonly string _playbackSettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "playback-settings.json");
    private readonly LyricsService _lyricsService = new();
    private readonly OnlineMusicService _online = new();
    private readonly PlatformMusicService _platform = new();
    private readonly ObservableCollection<OnlineSearchResult> _onlineResults = [];
    private CancellationTokenSource? _onlineSearch;
    private IReadOnlyList<TimedLyric> _lyrics = [];
    private CancellationTokenSource? _lyricsCancellation;
    private LyricsOverlayWindow? _lyricsOverlay;
    private LyricsSettingsWindow? _lyricsSettings;
    private PlatformAccountWindow? _accountWindow;
    private PlatformLibraryWindow? _libraryWindow;
    private WindowMonitorWindow? _monitorWindow;
    private WindowsStatusBarPlayer? _statusPlayer;
    private SongListDrawerWindow? _songListDrawer;
    private readonly ToggleButton[] _effectButtons;
    private int _lyricsGeneration;
    private int _artworkGeneration;
    private LocalTrack? _currentTrack;
    private ImageSource? _currentArtwork;
    private bool _isPlaying;
    private bool _allowExit;
    private bool _downloading;
    private int _repeatMode;

    public MainWindow()
    {
        InitializeComponent();
        _desktopWallpaper = new DesktopWallpaperController(_reactiveMonitor);
        try
        {
            if (File.Exists(_playbackSettingsPath))
                _repeatMode = Math.Clamp(JsonSerializer.Deserialize<int>(File.ReadAllText(_playbackSettingsPath)), 0, 2);
        }
        catch (Exception error) when (error is IOException or JsonException) { }
        _effectButtons = [TyndallEffect, CoverDotsEffect, CellularEffect, HexagonEffect];
        SyncEffectButtons();
        GuitarSurgeToggle.IsChecked = _desktopWallpaper.GuitarSurgeEnabled;
        CenterRecordToggle.IsChecked = _desktopWallpaper.CenterRecordVisible;
        RepeatButton.Content = RepeatModeTitle();
        OnlineResults.ItemsSource = _onlineResults;
        SearchBox.TextChanged += (_, _) =>
            SearchPlaceholder.Visibility = SearchBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _positionTimer.Tick += (_, _) => RefreshPosition();
        _visualTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        _visualTimer.Tick += (_, _) =>
        {
            _desktopWallpaper.UpdatePlayback(_isPlaying, Player.Position.TotalSeconds);
            WallpaperRendererStatus.Text = _desktopWallpaper.RenderingStatus;
        };
        SourceInitialized += (_, _) => ApplySystemBackdrop();
        Loaded += (_, _) =>
        {
            _statusPlayer = new WindowsStatusBarPlayer(
                ShowConsoleFromTray, TogglePlayback, () => MoveTrack(-1), () => MoveTrack(1),
                () => Repeat_Click(this, new RoutedEventArgs()), SeekFromTray,
                () => _songListDrawer?.OpenDrawer(), OpenLyricsFromTray, ExitApplication);
            RefreshTrayState();
            _songListDrawer = new SongListDrawerWindow(_tracks, PlayTrackFromDrawer, RemoveTrackFromLibrary, PlayPlatformTrack, ShowConsoleFromTray);
            _songListDrawer.Show();
            _reactiveMonitor.Start();
            _desktopWallpaper.Show();
            WallpaperToggle.IsChecked = _desktopWallpaper.IsVisible;
            if (_desktopWallpaper.Error is { } wallpaperError)
                MessageBox.Show(this, wallpaperError, "动态桌面启动失败", MessageBoxButton.OK, MessageBoxImage.Warning);
            _visualTimer.Start();
        };
        LoadLibrary();
        Closing += (_, e) =>
        {
            if (_allowExit) return;
            e.Cancel = true;
            Hide();
        };
    }

    // Windows 11 22H2+ draws an acrylic system backdrop behind the client area,
    // matching the Mac console's NSVisualEffectView. Older builds keep the gradient.
    private void ApplySystemBackdrop()
    {
        if (Environment.OSVersion.Version.Build < 22621) return;
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            var dark = 1;
            DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));
            var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            if (DwmExtendFrameIntoClientArea(hwnd, ref margins) != 0) return;
            var backdrop = 3;
            if (DwmSetWindowAttribute(hwnd, 38, ref backdrop, sizeof(int)) != 0) return;
            if (HwndSource.FromHwnd(hwnd)?.CompositionTarget is { } target) target.BackgroundColor = Colors.Transparent;
            Background = Brushes.Transparent;
            RootSurface.Background = new SolidColorBrush(Color.FromArgb(0x70, 0x0C, 0x10, 0x1A));
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException) { }
    }

    private void SearchBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) Search_Click(sender, e);
    }

    private async void Search_Click(object sender, RoutedEventArgs e)
    {
        var keyword = SearchBox.Text.Trim();
        if (keyword.Length == 0) { SearchStatus.Text = "请输入歌曲或歌手"; return; }
        _onlineSearch?.Cancel();
        var cancellation = new CancellationTokenSource();
        _onlineSearch = cancellation;
        SearchStatus.Text = "正在搜索…";
        _onlineResults.Clear();
        try
        {
            var results = await _online.SearchAsync(keyword, cancellation.Token);
            if (cancellation.IsCancellationRequested) return;
            foreach (var result in results) _onlineResults.Add(result);
            SearchStatus.Text = results.Count == 0 ? "没有找到相关歌曲" : $"找到 {results.Count} 首歌曲";
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (!cancellation.IsCancellationRequested) SearchStatus.Text = $"搜索失败：{error.Message}";
        }
    }

    private async void DownloadResult_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not OnlineSearchResult result) return;
        if (_downloading) { SearchStatus.Text = "正在下载另一首歌曲，请稍候"; return; }
        _downloading = true;
        try
        {
            var status = new Progress<string>(message => SearchStatus.Text = message);
            var (path, title, artist) = await _online.DownloadAsync(result, status, CancellationToken.None);
            var track = _tracks.FirstOrDefault(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase));
            if (track is null)
            {
                track = new LocalTrack { Path = path, Title = title, Artist = artist, Album = "" };
                _tracks.Add(track);
                SaveLibrary();
            }
            SearchStatus.Text = $"下载完成：{title} - {artist}";
            _playbackQueue = _tracks.ToList();
            PlayTrack(track, updateQueue: false);
        }
        catch (Exception error)
        {
            SearchStatus.Text = $"下载失败：{error.Message}";
        }
        finally { _downloading = false; }
    }

    private void Effect_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && int.TryParse(tag, out var index))
            _desktopWallpaper.SetEffect(index);
        SyncEffectButtons();
    }

    private void SyncEffectButtons()
    {
        foreach (var button in _effectButtons)
            button.IsChecked = (string)button.Tag == _desktopWallpaper.EffectIndex.ToString();
    }

    private void GuitarSurge_Click(object sender, RoutedEventArgs e) =>
        _desktopWallpaper.SetGuitarSurgeEnabled(GuitarSurgeToggle.IsChecked == true);

    private void CenterRecord_Click(object sender, RoutedEventArgs e) =>
        _desktopWallpaper.SetCenterRecordVisible(CenterRecordToggle.IsChecked == true);

    private void WallpaperToggle_Click(object sender, RoutedEventArgs e)
    {
        if (WallpaperToggle.IsChecked == true)
        {
            _desktopWallpaper.Show();
            if (_desktopWallpaper.Error is { } error)
                MessageBox.Show(this, error, "动态桌面启动失败", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        else _desktopWallpaper.Hide();
        WallpaperToggle.IsChecked = _desktopWallpaper.IsVisible;
    }

    private void MoodSettings_Click(object sender, RoutedEventArgs e)
    {
        var window = new MoodSettingsWindow { Owner = this };
        if (window.ShowDialog() == true && _currentTrack is not null)
            DesktopMoodService.Shared.Analyze(_currentTrack.Title, _currentTrack.Artist);
    }

    private void OpenLocal_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFileDialog
        {
            Title = "选择本地歌曲",
            Filter = "音频文件|*.mp3;*.wav;*.wma;*.m4a;*.aac;*.flac;*.ogg|所有文件|*.*"
        };
        if (picker.ShowDialog(this) != true) return;
        var path = picker.FileName;
        var track = _tracks.FirstOrDefault(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase));
        if (track is null)
        {
            track = new LocalTrack { Path = path, Title = Path.GetFileNameWithoutExtension(path), Artist = "本地文件", Album = "" };
            _tracks.Add(track);
            SaveLibrary();
        }
        _playbackQueue = [track];
        PlayTrack(track, updateQueue: false);
    }

    private void Play_Click(object sender, RoutedEventArgs e) => TogglePlayback();

    private void TogglePlayback()
    {
        if (_currentTrack is null)
        {
            if (_tracks.FirstOrDefault() is { } first) PlayTrack(first);
            else OpenLocal_Click(this, new RoutedEventArgs());
            return;
        }
        if (Player.Source is null) { PlayTrack(_currentTrack, updateQueue: false, keepPlatformQueue: _platformIndex >= 0); return; }
        if (_isPlaying)
        {
            Player.Pause();
            _isPlaying = false;
            _positionTimer.Stop();
        }
        else
        {
            Player.Play();
            _isPlaying = true;
            _positionTimer.Start();
        }
        PlayButton.Content = _isPlaying ? "Ⅱ" : "▶";
        RefreshTrayState();
    }

    private void PlayTrack(LocalTrack track, bool updateQueue = true, bool keepPlatformQueue = false)
    {
        if (!File.Exists(track.Path))
        {
            MessageBox.Show(this, "找不到这个音频文件。请重新导入后再播放。", "无法播放", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!keepPlatformQueue)
        {
            _platformQueue = [];
            _platformIndex = -1;
            _platformGeneration++;
            _songListDrawer?.SetLoading(null);
        }
        try
        {
            if (updateQueue) _playbackQueue = _tracks.ToList();
            _currentTrack = track;
            _currentArtwork = null;
            SetTrackLabels(track);
            DesktopMoodService.Shared.Analyze(track.Title, track.Artist);
            LoadLyricsForTrack(track);
            if (_lyricsService.Settings.Enabled) ShowLyricsOverlay();
            LoadTrackArtwork(track);
            Player.Stop();
            Player.Source = new Uri(track.Path, UriKind.Absolute);
            Player.Play();
            _isPlaying = true;
            PlayButton.Content = "Ⅱ";
            _positionTimer.Start();
            RefreshTrayState();
            track.LastPlayedUtc = DateTime.UtcNow;
            SaveLibrary();
        }
        catch (Exception error)
        {
            MessageBox.Show(this, $"无法打开音频文件：{error.Message}", "播放失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Previous_Click(object sender, RoutedEventArgs e) => MoveTrack(-1);
    private void Next_Click(object sender, RoutedEventArgs e) => MoveTrack(1);

    private void MoveTrack(int delta)
    {
        if (_platformIndex >= 0 && _platformQueue.Count > 0)
        {
            var next = (_platformIndex + delta + _platformQueue.Count) % _platformQueue.Count;
            PlayPlatformTrack(_platformQueue[next], _platformQueue);
            return;
        }
        var queue = _playbackQueue;
        if (queue.Count == 0) return;
        var index = _currentTrack is null ? -1 : queue.ToList().IndexOf(_currentTrack);
        PlayTrack(queue[(index + delta + queue.Count) % queue.Count], updateQueue: false);
    }

    private void Repeat_Click(object sender, RoutedEventArgs e)
    {
        _repeatMode = (_repeatMode + 1) % 3;
        RepeatButton.Content = RepeatModeTitle();
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_playbackSettingsPath)!);
            File.WriteAllText(_playbackSettingsPath, JsonSerializer.Serialize(_repeatMode));
        }
        catch (IOException) { }
        RefreshTrayState();
    }

    private void Stop_Click(object sender, RoutedEventArgs e)
    {
        Player.Stop();
        Player.Source = null;
        _isPlaying = false;
        _positionTimer.Stop();
        PlayButton.Content = "▶";
        RefreshTrayState();
    }

    private void FavoriteCurrent_Click(object sender, RoutedEventArgs e)
    {
        if (_currentTrack is null) return;
        _currentTrack.IsFavorite = !_currentTrack.IsFavorite;
        FavoriteButton.Content = _currentTrack.IsFavorite ? "♥" : "♡";
        SaveLibrary();
    }

    private void Player_MediaOpened(object sender, RoutedEventArgs e)
    {
        if (Player.NaturalDuration.HasTimeSpan && _currentTrack is not null)
        {
            _currentTrack.DurationSeconds = Player.NaturalDuration.TimeSpan.TotalSeconds;
            SaveLibrary();
        }
        RefreshTrayState();
    }

    private void Player_MediaEnded(object sender, RoutedEventArgs e)
    {
        if (_repeatMode == 2 && _currentTrack is not null)
        {
            Player.Position = TimeSpan.Zero;
            Player.Play();
            return;
        }
        var atEnd = _platformIndex >= 0
            ? _platformIndex >= _platformQueue.Count - 1
            : _currentTrack is not null && _playbackQueue.ToList().IndexOf(_currentTrack) >= _playbackQueue.Count - 1;
        if (_repeatMode == 0 && atEnd)
        {
            _isPlaying = false;
            _positionTimer.Stop();
            PlayButton.Content = "▶";
            RefreshTrayState();
            return;
        }
        MoveTrack(1);
    }

    private void Player_MediaFailed(object sender, ExceptionRoutedEventArgs e)
    {
        _positionTimer.Stop();
        _isPlaying = false;
        PlayButton.Content = "▶";
        RefreshTrayState();
        var detail = e.ErrorException?.Message ?? "Windows 媒体组件无法解码此格式。";
        MessageBox.Show(this, $"当前文件无法播放。\n\n{detail}", "播放失败", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private void RemoveTrackFromLibrary(LocalTrack track)
    {
        _tracks.Remove(track);
        _playbackQueue = _playbackQueue.Where(item => !ReferenceEquals(item, track)).ToList();
        if (ReferenceEquals(_currentTrack, track))
        {
            Player.Stop();
            Player.Source = null;
            _currentTrack = null;
            _isPlaying = false;
            PlayButton.Content = "▶";
            NowPlaying.Text = "尚未播放";
            _positionTimer.Stop();
            RefreshTrayState();
        }
        SaveLibrary();
    }

    private void PlayTrackFromDrawer(LocalTrack track) => PlayTrack(track);

    /// <summary>Plays a platform track and keeps <paramref name="queue"/> as the
    /// previous/next context, like the Mac drawer's onPlatformAdjacentTrack.</summary>
    public async void PlayPlatformTrack(PlatformTrack track, IReadOnlyList<PlatformTrack> queue)
    {
        var generation = ++_platformGeneration;
        _platformQueue = queue.Count > 0 ? queue : [track];
        _platformIndex = Math.Max(0, IndexOfPlatformTrack(_platformQueue, track));
        _songListDrawer?.SetLoading($"正在加载 {track.Title}");
        try
        {
            var path = await _platform.DownloadTrackAsync(track);
            if (generation != _platformGeneration) return;
            var local = _tracks.FirstOrDefault(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase));
            if (local is null)
            {
                local = new LocalTrack
                {
                    Path = path, Title = track.Title, Artist = track.Artist, Album = track.Album,
                    CoverUrl = track.CoverUrl, DurationSeconds = track.DurationSeconds
                };
                _tracks.Add(local);
            }
            _songListDrawer?.SetLoading(null);
            PlayTrack(local, updateQueue: false, keepPlatformQueue: true);
            PrefetchNextPlatformTrack(generation);
        }
        catch (Exception error)
        {
            if (generation != _platformGeneration) return;
            _songListDrawer?.SetLoading(null);
            MessageBox.Show(this, error.Message, "平台歌曲播放失败", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void PrefetchNextPlatformTrack(int generation)
    {
        if (_platformQueue.Count < 2) return;
        var next = _platformQueue[(_platformIndex + 1) % _platformQueue.Count];
        try { await _platform.DownloadTrackAsync(next); }
        catch (Exception error)
        {
            if (generation == _platformGeneration) WallpaperDiagnostics.Write($"Prefetch skipped: {error.Message}");
        }
    }

    private static int IndexOfPlatformTrack(IReadOnlyList<PlatformTrack> queue, PlatformTrack track)
    {
        for (var index = 0; index < queue.Count; index++)
            if (queue[index].Provider == track.Provider && queue[index].Id == track.Id) return index;
        return -1;
    }

    private void SongList_Click(object sender, RoutedEventArgs e) => _songListDrawer?.OpenDrawer();

    private void Accounts_Click(object sender, RoutedEventArgs e)
    {
        if (_accountWindow is { IsVisible: true }) { _accountWindow.Activate(); return; }
        _accountWindow = new PlatformAccountWindow { Owner = this };
        _accountWindow.Closed += (_, _) => _accountWindow = null;
        _accountWindow.Show();
    }

    private void PlatformLibrary_Click(object sender, RoutedEventArgs e)
    {
        if (_libraryWindow is { IsVisible: true }) { _libraryWindow.Activate(); return; }
        _libraryWindow = new PlatformLibraryWindow(PlayPlatformTrack) { Owner = this };
        _libraryWindow.Closed += (_, _) => _libraryWindow = null;
        _libraryWindow.Show();
    }

    private void WindowMonitor_Click(object sender, RoutedEventArgs e)
    {
        if (_monitorWindow is { IsVisible: true }) { _monitorWindow.Activate(); return; }
        _monitorWindow = new WindowMonitorWindow();
        _monitorWindow.Closed += (_, _) => _monitorWindow = null;
        _monitorWindow.Show();
    }

    private async void LoadLyricsForTrack(LocalTrack track)
    {
        _lyricsCancellation?.Cancel();
        _lyricsCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _lyricsCancellation = cancellation;
        var generation = ++_lyricsGeneration;
        _lyrics = [];
        _lyricsOverlay?.ShowFrame("", "正在查找歌词…", "");
        try
        {
            var lines = await _lyricsService.LoadAsync(track, cancellation.Token);
            if (generation != _lyricsGeneration || !ReferenceEquals(track, _currentTrack)) return;
            _lyrics = lines;
            UpdateLyrics(Player.Position.TotalSeconds);
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (generation == _lyricsGeneration)
                _lyricsOverlay?.ShowFrame("", $"歌词加载失败：{error.Message}", "");
        }
    }

    private void UpdateLyrics(double time)
    {
        if (_lyricsOverlay is not { IsVisible: true }) return;
        _lyricsOverlay.ShowLyrics(_lyrics, time);
    }

    private async void LoadTrackArtwork(LocalTrack track)
    {
        var generation = Interlocked.Increment(ref _artworkGeneration);
        _desktopWallpaper.SetArtwork(null);
        byte[]? bytes = null;
        try
        {
            bytes = await Task.Run(() =>
            {
                try
                {
                    using var media = TagLib.File.Create(track.Path);
                    return media.Tag.Pictures.FirstOrDefault()?.Data.Data;
                }
                catch { return null; }
            });
            if (bytes is null && Uri.TryCreate(track.CoverUrl, UriKind.Absolute, out var coverUri))
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
                bytes = await http.GetByteArrayAsync(coverUri);
            }
            if (generation != Volatile.Read(ref _artworkGeneration) || bytes is not { Length: > 0 }) return;
            using var stream = new MemoryStream(bytes);
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = stream;
            image.EndInit();
            image.Freeze();
            _currentArtwork = image;
            _desktopWallpaper.SetArtwork(image);
            RefreshTrayState();
        }
        catch { /* Artwork is optional; keep the selected animated background available. */ }
    }

    private void RefreshPosition()
    {
        if (Player.Source is not null) UpdateLyrics(Player.Position.TotalSeconds);
        RefreshTrayState();
    }

    private void Volume_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (Player is not null) Player.Volume = e.NewValue;
    }

    private void LyricsSettings_Click(object sender, RoutedEventArgs e)
    {
        _lyricsSettings ??= new LyricsSettingsWindow(_lyricsService.Settings, settings =>
        {
            _lyricsService.UpdateSettings(settings);
            if (settings.Enabled) ShowLyricsOverlay(); else CloseLyricsOverlay();
            _lyricsOverlay?.ApplySettings(settings);
            UpdateLyrics(Player.Position.TotalSeconds);
        });
        _lyricsSettings.Owner = this;
        if (_lyricsSettings.IsVisible) { _lyricsSettings.Activate(); return; }
        _lyricsSettings.Show();
    }

    private void ShowLyricsOverlay()
    {
        if (_currentTrack is null) return;
        if (_lyrics.Count == 0)
            LoadLyricsForTrack(_currentTrack);
        _lyricsOverlay ??= new LyricsOverlayWindow(_lyricsService.Settings);
        if (!_lyricsOverlay.IsVisible) _lyricsOverlay.Show();
        UpdateLyrics(Player.Position.TotalSeconds);
    }

    private void CloseLyricsOverlay()
    {
        _lyricsOverlay?.Close();
        _lyricsOverlay = null;
    }

    private void SetTrackLabels(LocalTrack track)
    {
        NowPlaying.Text = string.IsNullOrWhiteSpace(track.Artist) ? track.Title : $"{track.Title} - {track.Artist}";
        NowPlaying.Foreground = (Brush)FindResource("TextBrush");
        FavoriteButton.Content = track.IsFavorite ? "♥" : "♡";
        RefreshTrayState();
    }

    private void LoadLibrary()
    {
        try
        {
            if (!File.Exists(_libraryPath)) return;
            var loaded = JsonSerializer.Deserialize<List<LocalTrack>>(File.ReadAllText(_libraryPath)) ?? [];
            foreach (var track in loaded.Where(track => !string.IsNullOrWhiteSpace(track.Path))) _tracks.Add(track);
        }
        catch (Exception error)
        {
            MessageBox.Show(this, $"读取本地曲库失败：{error.Message}", "Sound Desk", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void SaveLibrary()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_libraryPath)!);
            File.WriteAllText(_libraryPath, JsonSerializer.Serialize(_tracks));
        }
        catch (Exception error)
        {
            MessageBox.Show(this, $"保存曲库失败：{error.Message}", "Sound Desk", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void RefreshTrayState()
    {
        var duration = Player?.NaturalDuration.HasTimeSpan == true ? Player.NaturalDuration.TimeSpan.TotalSeconds : 0;
        _statusPlayer?.UpdateState(_isPlaying, _repeatMode, _currentTrack?.Title ?? "Sound Desk",
            _currentTrack?.Artist, _currentArtwork, Player?.Position.TotalSeconds ?? 0, duration);
    }

    private string RepeatModeTitle() => _repeatMode switch { 1 => "列表循环", 2 => "单曲循环", _ => "顺序播放" };

    private void ShowConsoleFromTray()
    {
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    private void SeekFromTray(double seconds)
    {
        if (Player.Source is null) return;
        Player.Position = TimeSpan.FromSeconds(Math.Clamp(seconds, 0, Player.NaturalDuration.HasTimeSpan ? Player.NaturalDuration.TimeSpan.TotalSeconds : seconds));
        RefreshPosition();
    }

    private void OpenLyricsFromTray()
    {
        ShowConsoleFromTray();
        LyricsSettings_Click(this, new RoutedEventArgs());
    }

    private void ExitApplication()
    {
        _allowExit = true;
        Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        _statusPlayer?.Dispose();
        _statusPlayer = null;
        _positionTimer.Stop();
        _visualTimer.Stop();
        _desktopWallpaper.Dispose();
        _reactiveMonitor.Dispose();
        Player.Stop();
        _lyricsCancellation?.Cancel();
        _onlineSearch?.Cancel();
        _lyricsOverlay?.Close();
        _lyricsSettings?.Close();
        _accountWindow?.Close();
        _libraryWindow?.Close();
        _monitorWindow?.Close();
        _songListDrawer?.Close();
        Interlocked.Increment(ref _artworkGeneration);
        SaveLibrary();
        base.OnClosed(e);
        Application.Current.Shutdown();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Margins { public int Left, Right, Top, Bottom; }

    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
}

public sealed class LocalTrack : INotifyPropertyChanged
{
    public string Path { get; set; } = "";
    public string Title { get; set; } = "";
    public string Artist { get; set; } = "";
    public string Album { get; set; } = "";
    public string? CoverUrl { get; set; }
    private double _durationSeconds;
    public double DurationSeconds
    {
        get => _durationSeconds;
        set
        {
            if (Math.Abs(_durationSeconds - value) < 0.01) return;
            _durationSeconds = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DurationText));
        }
    }
    public DateTime? LastPlayedUtc { get; set; }
    public bool IsFavorite { get; set; }
    public string DurationText => DurationSeconds <= 0 ? "—" : $"{(int)TimeSpan.FromSeconds(DurationSeconds).TotalMinutes}:{TimeSpan.FromSeconds(DurationSeconds).Seconds:00}";
    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
