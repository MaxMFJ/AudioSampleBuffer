using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Threading;
using Microsoft.Win32;

namespace SoundDesk;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<LocalTrack> _tracks = [];
    private readonly ICollectionView _tracksView;
    private readonly DispatcherTimer _positionTimer;
    private readonly string _libraryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "library.json");
    private LocalTrack? _currentTrack;
    private bool _isSeeking;
    private bool _isPlaying;
    private int _repeatMode;

    public MainWindow()
    {
        InitializeComponent();
        _tracksView = CollectionViewSource.GetDefaultView(_tracks);
        _tracksView.Filter = FilterTrack;
        TrackList.ItemsSource = _tracksView;
        _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _positionTimer.Tick += (_, _) => RefreshPosition();
        LoadLibrary();
        RefreshLibraryState();
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
            added++;
        }
        SaveLibrary();
        RefreshLibraryState();
        if (added > 0 && _currentTrack is null) TrackList.SelectedItem = _tracks.LastOrDefault();
    }

    private void TrackList_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (TrackList.SelectedItem is LocalTrack track) PlayTrack(track);
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
            else if (_tracks.Count > 0) PlayTrack(_tracks[0]);
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
    }

    private void PlayTrack(LocalTrack track)
    {
        if (!File.Exists(track.Path))
        {
            MessageBox.Show(this, "找不到这个音频文件。请重新导入后再播放。", "无法播放", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        try
        {
            _currentTrack = track;
            TrackList.SelectedItem = track;
            SetTrackLabels(track);
            Player.Stop();
            Player.Source = new Uri(track.Path, UriKind.Absolute);
            Player.Play();
            _isPlaying = true;
            PlayButton.Content = "Ⅱ";
            _positionTimer.Start();
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
        if (_tracks.Count == 0) return;
        var index = _currentTrack is null ? -1 : _tracks.IndexOf(_currentTrack);
        var next = (index + delta + _tracks.Count) % _tracks.Count;
        PlayTrack(_tracks[next]);
    }

    private void Repeat_Click(object sender, RoutedEventArgs e)
    {
        _repeatMode = (_repeatMode + 1) % 3;
        RepeatButton.Content = _repeatMode switch { 1 => "列表循环", 2 => "单曲循环", _ => "顺序播放" };
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
        if (_repeatMode == 0 && _currentTrack is not null && _tracks.IndexOf(_currentTrack) == _tracks.Count - 1)
        {
            _isPlaying = false;
            _positionTimer.Stop();
            PlayButton.Content = "▶";
            ProgressSlider.Value = ProgressSlider.Maximum;
            return;
        }
        MoveTrack(1);
    }

    private void Player_MediaFailed(object sender, ExceptionRoutedEventArgs e)
    {
        _positionTimer.Stop();
        _isPlaying = false;
        PlayButton.Content = "▶";
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
        SaveLibrary();
        if (SectionTitle.Text == "我的收藏") _tracksView.Refresh();
    }

    private void RefreshPosition()
    {
        if (Player.Source is null || _isSeeking) return;
        _isSeeking = true;
        try
        {
            var position = Player.Position;
            if (Player.NaturalDuration.HasTimeSpan)
                ProgressSlider.Maximum = Math.Max(1, Player.NaturalDuration.TimeSpan.TotalSeconds);
            ProgressSlider.Value = Math.Min(position.TotalSeconds, ProgressSlider.Maximum);
            ElapsedText.Text = FormatTime(position);
        }
        finally { _isSeeking = false; }
    }

    private void Volume_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (Player is not null) Player.Volume = e.NewValue;
    }

    private void Search_TextChanged(object sender, TextChangedEventArgs e) => _tracksView.Refresh();
    private void AllSongs_Click(object sender, RoutedEventArgs e) { SectionTitle.Text = "所有歌曲"; _tracksView.Filter = FilterTrack; _tracksView.Refresh(); }
    private void Recent_Click(object sender, RoutedEventArgs e)
    {
        SectionTitle.Text = "最近播放";
        _tracksView.Filter = item => item is LocalTrack track && track.LastPlayedUtc.HasValue && FilterTrack(track);
        _tracksView.Refresh();
    }
    private void Favorites_Click(object sender, RoutedEventArgs e)
    {
        SectionTitle.Text = "我的收藏";
        _tracksView.Filter = item => item is LocalTrack track && track.IsFavorite && FilterTrack(track);
        _tracksView.Refresh();
    }

    private void OnlineSearch_Click(object sender, RoutedEventArgs e) => ShowNotAvailable("在线音乐搜索和平台账号登录将在后续 Windows 版本接入。当前可以先导入本地音频播放。");
    private void Lyrics_Click(object sender, RoutedEventArgs e) => ShowNotAvailable("歌词管理与桌面歌词正在移植中。此功能会沿用 Mac 端的控制台入口。");
    private void Effects_Click(object sender, RoutedEventArgs e) => ShowNotAvailable("音频响应式桌面效果正在移植中。Windows 版会用 Direct3D 渲染，复现 Mac 端的效果样式。");
    private void Accounts_Click(object sender, RoutedEventArgs e) => ShowNotAvailable("QQ、网易云和酷狗账号连接尚未接入 Windows 版。");
    private void Monitor_Click(object sender, RoutedEventArgs e) => ShowNotAvailable("窗口预览需要 Windows 桌面合成器接入，后续版本开放。");

    private void ShowNotAvailable(string message) => MessageBox.Show(this, message, "Windows 版开发中", MessageBoxButton.OK, MessageBoxImage.Information);

    private void SetTrackLabels(LocalTrack track)
    {
        NowPlayingTitle.Text = track.Title;
        NowPlayingArtist.Text = string.IsNullOrWhiteSpace(track.Artist) ? "本地文件" : track.Artist;
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

    private static string FormatTime(TimeSpan time) => $"{(int)time.TotalMinutes}:{time.Seconds:00}";

    protected override void OnClosed(EventArgs e)
    {
        _positionTimer.Stop();
        Player.Stop();
        SaveLibrary();
        base.OnClosed(e);
    }
}

public sealed class LocalTrack : INotifyPropertyChanged
{
    public string Path { get; set; } = "";
    public string Title { get; set; } = "";
    public string Artist { get; set; } = "";
    public string Album { get; set; } = "";
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
