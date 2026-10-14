using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace SoundDesk;

public partial class PlatformWindow : Window
{
    private readonly PlatformMusicService _music = new();
    private readonly ObservableCollection<PlatformTrack> _results = [];
    private readonly Action<LocalTrack> _onTrackDownloaded;
    private bool _busy;

    public PlatformWindow(Action<LocalTrack> onTrackDownloaded)
    {
        InitializeComponent();
        _onTrackDownloaded = onTrackDownloaded;
        ResultsList.ItemsSource = _results;
        LoadCookieForSelection();
    }

    private MusicProvider SelectedProvider => ProviderPicker.SelectedIndex switch
    {
        1 => MusicProvider.NetEase,
        2 => MusicProvider.Kugou,
        _ => MusicProvider.QQ
    };

    private void Provider_SelectionChanged(object sender, SelectionChangedEventArgs e) => LoadCookieForSelection();

    private void LoadCookieForSelection()
    {
        if (StatusText is null || ProviderPicker.SelectedIndex < 0) return;
        StatusText.Text = _music.LoadCookie(SelectedProvider) is null
            ? "尚未登录此平台。部分歌曲需要平台账号授权后才能播放。"
            : "已读取此平台的加密登录凭据。";
    }

    private async void Search_Click(object sender, RoutedEventArgs e) => await SearchAsync();

    private async Task SearchAsync()
    {
        if (_busy) return;
        if (string.IsNullOrWhiteSpace(SearchBox.Text))
        {
            StatusText.Text = "输入歌名或歌手后再搜索。";
            return;
        }
        SetBusy(true, "正在搜索…");
        try
        {
            var tracks = await _music.SearchAsync(SelectedProvider, SearchBox.Text.Trim());
            _results.Clear();
            foreach (var track in tracks) _results.Add(track);
            EmptyResults.Visibility = tracks.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            StatusText.Text = $"找到 {tracks.Count} 首歌曲。双击一首歌曲会解析音源、下载并加入本地曲库。";
        }
        catch (Exception error)
        {
            StatusText.Text = $"搜索失败：{error.Message}";
        }
        finally { SetBusy(false); }
    }

    private async void Results_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (ResultsList.SelectedItem is not PlatformTrack track || _busy) return;
        SetBusy(true, $"正在解析并下载《{track.Title}》…");
        try
        {
            var path = await _music.DownloadTrackAsync(track);
            var local = new LocalTrack
            {
                Path = path, Title = track.Title, Artist = string.IsNullOrWhiteSpace(track.Artist) ? "未知艺术家" : track.Artist,
                Album = track.Album, DurationSeconds = track.DurationSeconds, CoverUrl = track.CoverUrl
            };
            _onTrackDownloaded(local);
            StatusText.Text = $"已下载并加入曲库：{track.Title}";
        }
        catch (Exception error) { StatusText.Text = $"无法播放这首歌：{error.Message}"; }
        finally { SetBusy(false); }
    }

    private void LoginPage_Click(object sender, RoutedEventArgs e)
    {
        var login = new PlatformLoginWindow(SelectedProvider) { Owner = this };
        login.ShowDialog();
        LoadCookieForSelection();
    }

    private void DeleteCookie_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _music.DeleteCookie(SelectedProvider);
            StatusText.Text = "已清除此平台的本机登录凭据。";
        }
        catch (Exception error) { StatusText.Text = $"清除失败：{error.Message}"; }
    }

    private void SearchBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) _ = SearchAsync();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void SetBusy(bool busy, string? status = null)
    {
        _busy = busy;
        ProviderPicker.IsEnabled = !busy;
        SearchBox.IsEnabled = !busy;
        ResultsList.IsEnabled = !busy;
        if (status is not null) StatusText.Text = status;
    }
}
