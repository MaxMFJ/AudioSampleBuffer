using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using Rectangle = System.Windows.Shapes.Rectangle;

namespace SoundDesk;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<LocalTrack> _tracks = [];
    private IReadOnlyList<LocalTrack> _playbackQueue = [];
    private readonly ICollectionView _tracksView;
    private readonly DispatcherTimer _positionTimer;
    private readonly DispatcherTimer _visualTimer;
    private readonly AudioReactiveMonitor _reactiveMonitor = new();
    private readonly DesktopWallpaperController _desktopWallpaper;
    private readonly Rectangle[] _spectrumBars = new Rectangle[48];
    private readonly Brush[] _spectrumBrushes = new Brush[48];
    private readonly string _libraryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "library.json");
    private readonly string _playlistsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "playlists.json");
    private readonly string _playbackSettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "playback-settings.json");
    private readonly ObservableCollection<UserPlaylist> _playlists = [];
    private readonly LyricsService _lyricsService = new();
    private IReadOnlyList<TimedLyric> _lyrics = [];
    private CancellationTokenSource? _lyricsCancellation;
    private LyricsOverlayWindow? _lyricsOverlay;
    private PlatformWindow? _platformWindow;
    private LyricsSettingsWindow? _lyricsSettings;
    private WindowsStatusBarPlayer? _statusPlayer;
    private SongListDrawerWindow? _songListDrawer;
    private string? _selectedPlaylistId;
    private int _lyricsGeneration;
    private int _visualizationMode;
    private int _brushMode = -1;
    private int _artworkGeneration;
    private double _visualTime;
    private LocalTrack? _currentTrack;
    private ImageSource? _currentArtwork;
    private bool _isSeeking;
    private bool _isPlaying;
    private bool _allowExit;
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
        _visualizationMode = _desktopWallpaper.EffectIndex;
        EffectSelector.SelectedIndex = _visualizationMode;
        RepeatButton.Content = RepeatModeTitle();
        _tracksView = CollectionViewSource.GetDefaultView(_tracks);
        _tracksView.Filter = FilterTrack;
        TrackList.ItemsSource = _tracksView;
        PlaylistList.ItemsSource = _playlists;
        _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _positionTimer.Tick += (_, _) => RefreshPosition();
        for (var index = 0; index < _spectrumBars.Length; index++)
        {
            var bar = new Rectangle { RadiusX = 4, RadiusY = 4, Opacity = 0.24, IsHitTestVisible = false };
            _spectrumBars[index] = bar;
            SpectrumCanvas.Children.Add(bar);
        }
        SpectrumCanvas.SizeChanged += (_, _) => RenderSpectrum();
        _visualTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        _visualTimer.Tick += (_, _) => RenderSpectrum();
        Loaded += (_, _) =>
        {
            _statusPlayer = new WindowsStatusBarPlayer(
                ShowConsoleFromTray, TogglePlaybackFromTray, PreviousFromTray, NextFromTray,
                RepeatFromTray, SeekFromTray, OpenSongListFromTray, OpenLyricsFromTray, ExitFromTray);
            RefreshTrayState();
            _songListDrawer = new SongListDrawerWindow(_tracks, PlayTrackFromDrawer, RemoveTrackFromLibrary, PlayPlatformTrackFromDrawer);
            _songListDrawer.Show();
            _reactiveMonitor.Start();
            _desktopWallpaper.Show();
            if (_desktopWallpaper.Error is { } wallpaperError)
                MessageBox.Show(this, wallpaperError, "动态桌面启动失败", MessageBoxButton.OK, MessageBoxImage.Warning);
            _visualTimer.Start();
        };
        LoadLibrary();
        LoadPlaylists();
        RefreshLibraryState();
        Closing += (_, e) =>
        {
            if (_allowExit) return;
            e.Cancel = true;
            Hide();
        };
    }

    private bool FilterTrack(object item)
    {
        if (item is not LocalTrack track) return false;
        var query = SearchBox?.Text?.Trim();
        return string.IsNullOrEmpty(query)
            || track.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)
            || track.Artist.Contains(query, StringComparison.CurrentCultureIgnoreCase)
            || track.Album.Contains(query, StringComparison.CurrentCultureIgnoreCase);
    }

    private void Import_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFileDialog
        {
            Title = "导入音乐",
            Filter = "音频文件|*.mp3;*.wav;*.wma;*.m4a;*.aac;*.flac;*.ogg|所有文件|*.*",
            Multiselect = true
        };
        if (picker.ShowDialog(this) != true) return;
        var added = 0;
        foreach (var path in picker.FileNames)
        {
            if (_tracks.Any(track => string.Equals(track.Path, path, StringComparison.OrdinalIgnoreCase))) continue;
            var title = Path.GetFileNameWithoutExtension(path);
            _tracks.Add(new LocalTrack { Path = path, Title = title, Artist = "本地文件", Album = "" });
            if (_selectedPlaylistId is not null)
                _playlists.FirstOrDefault(item => item.Id == _selectedPlaylistId)?.TrackPaths.Add(path);
            added++;
        }
        SaveLibrary();
        SavePlaylists();
        RefreshLibraryState();
        if (added > 0 && _currentTrack is null) TrackList.SelectedItem = _tracks.LastOrDefault();
    }

    private void TrackList_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (TrackList.SelectedItem is LocalTrack track) PlayTrack(track);
    }

    private void TrackList_RightClick(object sender, MouseButtonEventArgs e)
    {
        if (ItemsControl.ContainerFromElement(TrackList, e.OriginalSource as DependencyObject) is ListBoxItem item)
            TrackList.SelectedItem = item.DataContext;
    }

    private void TrackList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (TrackList.SelectedItem is LocalTrack track && _currentTrack is null)
            SetTrackLabels(track);
    }

    private void Play_Click(object sender, RoutedEventArgs e)
    {
        if (_currentTrack is null)
        {
            if (TrackList.SelectedItem is LocalTrack selected) PlayTrack(selected);
            else if (_tracksView.Cast<LocalTrack>().FirstOrDefault() is LocalTrack first) PlayTrack(first);
            else Import_Click(sender, e);
            return;
        }

        if (Player.Source is null) { PlayTrack(_currentTrack); return; }
        if (_isPlaying)
        {
            Player.Pause();
            _isPlaying = false;
            PlayButton.Content = "▶";
            _positionTimer.Stop();
        }
        else
        {
            Player.Play();
            _isPlaying = true;
            PlayButton.Content = "Ⅱ";
            _positionTimer.Start();
        }
        RefreshTrayState();
    }

    private void PlayTrack(LocalTrack track, bool updateQueue = true)
    {
        if (!File.Exists(track.Path))
        {
            MessageBox.Show(this, "找不到这个音频文件。请重新导入后再播放。", "无法播放", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        try
        {
            if (updateQueue)
            {
                var visible = _tracksView.Cast<LocalTrack>().ToList();
                _playbackQueue = visible.Contains(track) ? visible : [track];
            }
            _currentTrack = track;
            _currentArtwork = null;
            TrackList.SelectedItem = track;
            SetTrackLabels(track);
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
        ProgressSlider.Value = 0;
        ElapsedText.Text = "0:00";
        RefreshTrayState();
    }

    private void FavoriteCurrent_Click(object sender, RoutedEventArgs e)
    {
        if (_currentTrack is null) return;
        _currentTrack.IsFavorite = !_currentTrack.IsFavorite;
        FavoriteButton.Content = _currentTrack.IsFavorite ? "♥" : "♡";
        SaveLibrary();
        if (SectionTitle.Text == "我的收藏") _tracksView.Refresh();
    }

    private void Player_MediaOpened(object sender, RoutedEventArgs e)
    {
        if (Player.NaturalDuration.HasTimeSpan)
        {
            var duration = Player.NaturalDuration.TimeSpan;
            DurationText.Text = FormatTime(duration);
            ProgressSlider.Maximum = Math.Max(1, duration.TotalSeconds);
            if (_currentTrack is not null)
            {
                _currentTrack.DurationSeconds = duration.TotalSeconds;
                SaveLibrary();
                RefreshLibraryState();
            }
        }
    }

    private void Player_MediaEnded(object sender, RoutedEventArgs e)
    {
        if (_repeatMode == 2 && _currentTrack is not null) { PlayTrack(_currentTrack); return; }
        if (_repeatMode == 0 && _currentTrack is not null && _playbackQueue.ToList().IndexOf(_currentTrack) >= _playbackQueue.Count - 1)
        {
            _isPlaying = false;
            _positionTimer.Stop();
            PlayButton.Content = "▶";
            ProgressSlider.Value = ProgressSlider.Maximum;
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

    private void Progress_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (ElapsedText is not null) ElapsedText.Text = FormatTime(TimeSpan.FromSeconds(e.NewValue));
    }

    private void Progress_MouseDown(object sender, MouseButtonEventArgs e) => _isSeeking = true;

    private void Progress_MouseUp(object sender, MouseButtonEventArgs e)
    {
        _isSeeking = false;
        if (Player.Source is not null) Player.Position = TimeSpan.FromSeconds(ProgressSlider.Value);
    }

    private void Favorite_Click(object sender, RoutedEventArgs e)
    {
        if (TrackList.SelectedItem is not LocalTrack track) return;
        track.IsFavorite = !track.IsFavorite;
        if (ReferenceEquals(track, _currentTrack)) FavoriteButton.Content = track.IsFavorite ? "♥" : "♡";
        SaveLibrary();
        if (SectionTitle.Text == "我的收藏") _tracksView.Refresh();
    }

    private void RemoveFromPlaylist_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedPlaylistId is null || TrackList.SelectedItem is not LocalTrack track) return;
        var playlist = _playlists.FirstOrDefault(item => item.Id == _selectedPlaylistId);
        playlist?.TrackPaths.RemoveAll(path => string.Equals(path, track.Path, StringComparison.OrdinalIgnoreCase));
        SavePlaylists();
        _tracksView.Refresh();
    }

    private void TrackContextMenu_Opened(object sender, RoutedEventArgs e)
    {
        if (sender is not ContextMenu menu) return;
        var addToPlaylist = menu.Items.OfType<MenuItem>().FirstOrDefault(item => Equals(item.Header, "添加到歌单"));
        if (addToPlaylist is null) return;
        addToPlaylist.Items.Clear();
        if (_playlists.Count == 0)
        {
            addToPlaylist.Items.Add(new MenuItem { Header = "请先新建歌单", IsEnabled = false });
            return;
        }
        foreach (var playlist in _playlists)
        {
            var item = new MenuItem { Header = playlist.Name, Tag = playlist.Id };
            item.Click += (_, _) =>
            {
                if (TrackList.SelectedItem is not LocalTrack track) return;
                var target = _playlists.FirstOrDefault(candidate => candidate.Id == (string)item.Tag);
                if (target is null || target.TrackPaths.Contains(track.Path, StringComparer.OrdinalIgnoreCase)) return;
                target.TrackPaths.Add(track.Path);
                SavePlaylists();
                _tracksView.Refresh();
            };
            addToPlaylist.Items.Add(item);
        }
    }

    private void RemoveFromLibrary_Click(object sender, RoutedEventArgs e)
    {
        if (TrackList.SelectedItem is not LocalTrack track) return;
        RemoveTrackFromLibrary(track);
    }

    private void RemoveTrackFromLibrary(LocalTrack track)
    {
        _tracks.Remove(track);
        _playbackQueue = _playbackQueue.Where(item => !ReferenceEquals(item, track)).ToList();
        foreach (var playlist in _playlists)
            playlist.TrackPaths.RemoveAll(path => string.Equals(path, track.Path, StringComparison.OrdinalIgnoreCase));
        if (ReferenceEquals(_currentTrack, track))
        {
            Player.Stop();
            Player.Source = null;
            _currentTrack = null;
            _isPlaying = false;
            PlayButton.Content = "▶";
            _positionTimer.Stop();
            RefreshTrayState();
        }
        SaveLibrary();
        SavePlaylists();
        RefreshLibraryState();
    }

    private void PlayTrackFromDrawer(LocalTrack track)
    {
        _playbackQueue = _tracks.ToList();
        PlayTrack(track, updateQueue: false);
    }

    private async void PlayPlatformTrackFromDrawer(PlatformTrack track)
    {
        try
        {
            var service = new PlatformMusicService();
            var path = await service.DownloadTrackAsync(track);
            var local = new LocalTrack
            {
                Path = path, Title = track.Title, Artist = track.Artist, Album = track.Album,
                CoverUrl = track.CoverUrl, DurationSeconds = track.DurationSeconds
            };
            OnPlatformTrackDownloaded(local);
        }
        catch (Exception error)
        {
            MessageBox.Show(this, error.Message, "平台歌曲播放失败", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void SongList_Click(object sender, RoutedEventArgs e) => _songListDrawer?.OpenDrawer();

    private void EffectSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (EffectSelector is not null) _visualizationMode = Math.Max(0, EffectSelector.SelectedIndex);
        _desktopWallpaper?.SetEffect(_visualizationMode);
        RenderSpectrum();
    }

    private void RenderSpectrum()
    {
        if (_desktopWallpaper is not null && Player is not null)
        {
            _desktopWallpaper.UpdatePlayback(_isPlaying, Player.Position.TotalSeconds);
            if (WallpaperRendererStatus is not null) WallpaperRendererStatus.Text = _desktopWallpaper.RenderingStatus;
        }
        if (SpectrumCanvas is null || SpectrumCanvas.ActualWidth <= 0 || SpectrumCanvas.ActualHeight <= 0) return;
        var width = SpectrumCanvas.ActualWidth;
        var height = SpectrumCanvas.ActualHeight;
        var values = _reactiveMonitor.Spectrum;
        if (_brushMode != _visualizationMode) BuildSpectrumBrushes();
        var barSlot = width / _spectrumBars.Length;
        var baseline = Math.Max(0, height - 18);
        var maxHeight = Math.Min(height * 0.48, 230);
        _visualTime += 1d / 30;
        for (var index = 0; index < _spectrumBars.Length; index++)
        {
            var amplitude = values[index];
            var bar = _spectrumBars[index];
            var widthFactor = _visualizationMode switch { 1 => 0.12, 2 => 0.28, 3 => 0.48, _ => 0.64 };
            var barWidth = Math.Max(2, barSlot * widthFactor);
            var barHeight = 5 + Math.Pow(amplitude, 0.72) * maxHeight;
            var centerX = index * barSlot + barSlot / 2;
            Canvas.SetLeft(bar, centerX - barWidth / 2);
            Canvas.SetTop(bar, Math.Max(0, baseline - barHeight));
            bar.Width = barWidth;
            bar.Height = _visualizationMode == 2 ? Math.Max(4, barWidth) : barHeight;
            if (_visualizationMode == 2)
                Canvas.SetTop(bar, Math.Max(0, baseline - amplitude * maxHeight));

            bar.Fill = _spectrumBrushes[index];
            bar.Opacity = Math.Clamp(0.12 + amplitude * 1.8, 0.12, 0.82);
            if (_visualizationMode == 1)
            {
                var sway = Math.Sin(_visualTime * 0.8 + index * 0.35) * 16;
                Canvas.SetLeft(bar, centerX - barWidth / 2 + sway);
                bar.Opacity = Math.Clamp(0.08 + amplitude * 1.4, 0.08, 0.62);
            }
        }
    }

    private void BuildSpectrumBrushes()
    {
        for (var index = 0; index < _spectrumBrushes.Length; index++)
        {
            var color = _visualizationMode switch
            {
                1 => Color.FromRgb((byte)(255 - index * 2), (byte)(158 + index % 5 * 9), 105),
                2 => Color.FromRgb(138, (byte)(174 + index % 5 * 12), 255),
                3 => index % 3 == 0 ? Color.FromRgb(118, 255, 104) : Color.FromRgb(48, 226, 231),
                _ => Color.FromRgb((byte)(108 + index % 4 * 12), (byte)(165 + index % 5 * 9), 255)
            };
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            _spectrumBrushes[index] = brush;
        }
        _brushMode = _visualizationMode;
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

    private void Lyrics_Click(object sender, RoutedEventArgs e) => LyricsSettings_Click(sender, e);

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
        if (Player.Source is null || _isSeeking) { RefreshTrayState(); return; }
        _isSeeking = true;
        try
        {
            var position = Player.Position;
            if (Player.NaturalDuration.HasTimeSpan)
                ProgressSlider.Maximum = Math.Max(1, Player.NaturalDuration.TimeSpan.TotalSeconds);
            ProgressSlider.Value = Math.Min(position.TotalSeconds, ProgressSlider.Maximum);
            ElapsedText.Text = FormatTime(position);
            UpdateLyrics(position.TotalSeconds);
            RefreshTrayState();
        }
        finally { _isSeeking = false; }
    }

    private void Volume_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (Player is not null) Player.Volume = e.NewValue;
    }

    private void Search_TextChanged(object sender, TextChangedEventArgs e) => _tracksView.Refresh();
    private void AllSongs_Click(object sender, RoutedEventArgs e) { _selectedPlaylistId = null; PlaylistList.SelectedItem = null; SectionTitle.Text = "所有歌曲"; _tracksView.Filter = FilterTrack; _tracksView.Refresh(); }
    private void Recent_Click(object sender, RoutedEventArgs e)
    {
        SectionTitle.Text = "最近播放";
        _selectedPlaylistId = null;
        PlaylistList.SelectedItem = null;
        _tracksView.Filter = item => item is LocalTrack track && track.LastPlayedUtc.HasValue && FilterTrack(track);
        _tracksView.Refresh();
    }
    private void Favorites_Click(object sender, RoutedEventArgs e)
    {
        SectionTitle.Text = "我的收藏";
        _selectedPlaylistId = null;
        PlaylistList.SelectedItem = null;
        _tracksView.Filter = item => item is LocalTrack track && track.IsFavorite && FilterTrack(track);
        _tracksView.Refresh();
    }

    private void PlaylistList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (PlaylistList.SelectedItem is not UserPlaylist playlist) return;
        _selectedPlaylistId = playlist.Id;
        SectionTitle.Text = playlist.Name;
        _tracksView.Filter = item => item is LocalTrack track
            && playlist.TrackPaths.Contains(track.Path, StringComparer.OrdinalIgnoreCase)
            && FilterTrack(track);
        _tracksView.Refresh();
    }

    private void CreatePlaylist_Click(object sender, RoutedEventArgs e)
    {
        var name = TextPromptWindow.Show(this, "新建歌单", "歌单名称");
        if (string.IsNullOrWhiteSpace(name)) return;
        var playlist = new UserPlaylist { Name = name.Trim() };
        _playlists.Add(playlist);
        SavePlaylists();
        PlaylistList.SelectedItem = playlist;
    }

    private void DeletePlaylist_Click(object sender, RoutedEventArgs e)
    {
        if (PlaylistList.SelectedItem is not UserPlaylist playlist) return;
        _playlists.Remove(playlist);
        if (_selectedPlaylistId == playlist.Id) { _selectedPlaylistId = null; AllSongs_Click(sender, e); }
        SavePlaylists();
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

    private void OnlineSearch_Click(object sender, RoutedEventArgs e) => OpenPlatformWindow();
    private void Accounts_Click(object sender, RoutedEventArgs e) => OpenPlatformWindow();
    private void Monitor_Click(object sender, RoutedEventArgs e)
    {
        if (_desktopWallpaper.IsVisible)
        {
            _desktopWallpaper.Hide();
            MonitorButton.Content = "启用桌面背景";
        }
        else
        {
            _desktopWallpaper.Show();
            MonitorButton.Content = "关闭桌面背景";
        }
    }

    private void OpenPlatformWindow()
    {
        if (_platformWindow is { IsVisible: true }) { _platformWindow.Activate(); return; }
        _platformWindow = new PlatformWindow(OnPlatformTrackDownloaded) { Owner = this };
        _platformWindow.Closed += (_, _) => _platformWindow = null;
        _platformWindow.Show();
    }

    private void OnPlatformTrackDownloaded(LocalTrack track)
    {
        var existing = _tracks.FirstOrDefault(item => string.Equals(item.Path, track.Path, StringComparison.OrdinalIgnoreCase));
        if (existing is null) _tracks.Add(track);
        else track = existing;
        SaveLibrary();
        RefreshLibraryState();
        PlayTrack(track);
    }

    private void SetTrackLabels(LocalTrack track)
    {
        NowPlayingTitle.Text = track.Title;
        NowPlayingArtist.Text = string.IsNullOrWhiteSpace(track.Artist) ? "本地文件" : track.Artist;
        FavoriteButton.Content = track.IsFavorite ? "♥" : "♡";
        RefreshTrayState();
    }

    private void RefreshLibraryState()
    {
        TrackCount.Text = $"{_tracks.Count} 首歌曲";
        EmptyState.Visibility = _tracks.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        _tracksView.Refresh();
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

    private void LoadPlaylists()
    {
        try
        {
            if (!File.Exists(_playlistsPath)) return;
            var loaded = JsonSerializer.Deserialize<List<UserPlaylist>>(File.ReadAllText(_playlistsPath)) ?? [];
            foreach (var playlist in loaded.Where(item => !string.IsNullOrWhiteSpace(item.Name))) _playlists.Add(playlist);
        }
        catch (Exception error) { MessageBox.Show(this, $"读取歌单失败：{error.Message}", "Sound Desk", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private void SavePlaylists()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_playlistsPath)!);
            File.WriteAllText(_playlistsPath, JsonSerializer.Serialize(_playlists));
        }
        catch (IOException) { }
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

    private void TogglePlaybackFromTray() => Play_Click(this, new RoutedEventArgs());
    private void PreviousFromTray() => Previous_Click(this, new RoutedEventArgs());
    private void NextFromTray() => Next_Click(this, new RoutedEventArgs());
    private void RepeatFromTray() => Repeat_Click(this, new RoutedEventArgs());
    private void SeekFromTray(double seconds)
    {
        if (Player.Source is null) return;
        Player.Position = TimeSpan.FromSeconds(Math.Clamp(seconds, 0, Player.NaturalDuration.HasTimeSpan ? Player.NaturalDuration.TimeSpan.TotalSeconds : seconds));
        RefreshPosition();
    }
    private void OpenSongListFromTray()
    {
        _songListDrawer?.OpenDrawer();
    }
    private void OpenLyricsFromTray()
    {
        ShowConsoleFromTray();
        LyricsSettings_Click(this, new RoutedEventArgs());
    }
    private void ExitFromTray()
    {
        _allowExit = true;
        Close();
    }

    private static string FormatTime(TimeSpan time) => $"{(int)time.TotalMinutes}:{time.Seconds:00}";

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
        _lyricsOverlay?.Close();
        _lyricsSettings?.Close();
        _platformWindow?.Close();
        _songListDrawer?.Close();
        Interlocked.Increment(ref _artworkGeneration);
        SaveLibrary();
        SavePlaylists();
        base.OnClosed(e);
        Application.Current.Shutdown();
    }
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
