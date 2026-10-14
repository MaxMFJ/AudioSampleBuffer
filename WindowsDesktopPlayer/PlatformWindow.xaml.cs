using System.Collections.ObjectModel;
using System.Diagnostics;
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
        if (CookieBox is null || ProviderPicker.SelectedIndex < 0) return;
        CookieBox.Text = _music.LoadCookie(SelectedProvider) ?? "";
        StatusText.Text = string.IsNullOrWhiteSpace(CookieBox.Text)
            ? "未保存账号。免费曲目可直接试听；需要登录的曲目请先保存平台 Cookie。"
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
                Album = track.Album, DurationSeconds = track.DurationSeconds
            };
            _onTrackDownloaded(local);
            StatusText.Text = $"已下载并加入曲库：{track.Title}";
        }
        catch (Exception error) { StatusText.Text = $"无法播放这首歌：{error.Message}"; }
        finally { SetBusy(false); }
    }

    private void LoginPage_Click(object sender, RoutedEventArgs e)
    {
        var url = SelectedProvider switch
        {
            MusicProvider.QQ => "https://y.qq.com/portal/profile.html",
            MusicProvider.NetEase => "https://music.163.com/",
            _ => "https://www.kugou.com/"
        };
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        StatusText.Text = "请在浏览器登录，再从该站点请求的 Cookie 请求头复制值粘贴到上方并保存。Cookie 会用 Windows DPAPI 加密到当前用户账户。";
    }

    private void SaveCookie_Click(object sender, RoutedEventArgs e)
    {
        var cookie = CookieBox.Text.Trim();
        if (cookie.Length == 0) { StatusText.Text = "先粘贴登录后的 Cookie。"; return; }
        if (!HasRequiredCookie(SelectedProvider, cookie))
        {
            StatusText.Text = SelectedProvider switch
            {
                MusicProvider.QQ => "QQ Cookie 至少需要 uin 和 qm_keyst / qqmusic_key。",
                MusicProvider.NetEase => "网易云 Cookie 需要 MUSIC_U。",
                _ => "酷狗 Cookie 需要 userid / KugooID 与 token。"
            };
            return;
        }
        try
        {
            _music.SaveCookie(SelectedProvider, cookie);
            CookieBox.Text = _music.LoadCookie(SelectedProvider) ?? "";
            StatusText.Text = "凭据已使用 Windows DPAPI 加密保存。";
        }
        catch (Exception error) { StatusText.Text = $"保存凭据失败：{error.Message}"; }
    }

    private void DeleteCookie_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _music.DeleteCookie(SelectedProvider);
            CookieBox.Clear();
            StatusText.Text = "已清除此平台的本机登录凭据。";
        }
        catch (Exception error) { StatusText.Text = $"清除失败：{error.Message}"; }
    }

    private static bool HasRequiredCookie(MusicProvider provider, string cookie)
    {
        var names = cookie.Split(';', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2)[0].Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return provider switch
        {
            MusicProvider.QQ => names.Contains("uin") && (names.Contains("qm_keyst") || names.Contains("qqmusic_key") || names.Contains("music_key") || names.Contains("wxskey")),
            MusicProvider.NetEase => names.Contains("MUSIC_U"),
            _ => (names.Contains("userid") || names.Contains("KugooID")) && (names.Contains("token") || names.Contains("t"))
        };
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
