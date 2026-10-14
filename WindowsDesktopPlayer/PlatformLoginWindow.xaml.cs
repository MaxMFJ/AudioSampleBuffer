using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace SoundDesk;

public partial class PlatformLoginWindow : Window
{
    private readonly MusicProvider _provider;
    private readonly PlatformMusicService _music = new();
    private readonly Uri _loginUri;
    private bool _initializing;
    private bool _saved;

    public PlatformLoginWindow(MusicProvider provider)
    {
        InitializeComponent();
        _provider = provider;
        _loginUri = new Uri(provider switch
        {
            MusicProvider.QQ => "https://y.qq.com/portal/profile.html",
            MusicProvider.NetEase => "https://music.163.com/",
            _ => "https://www.kugou.com/"
        });
        Loaded += async (_, _) => await InitializeBrowserAsync();
    }

    private async Task InitializeBrowserAsync()
    {
        if (_initializing) return;
        _initializing = true;
        try
        {
            await LoginBrowser.EnsureCoreWebView2Async();
            LoginBrowser.CoreWebView2.NavigationCompleted += async (_, _) => await CaptureCookiesAsync();
            LoginBrowser.CoreWebView2.NewWindowRequested += (_, args) =>
            {
                args.NewWindow = LoginBrowser.CoreWebView2;
                args.Handled = true;
            };
            LoginBrowser.Source = _loginUri;
        }
        catch (Exception error)
        {
            LoginStatus.Text = $"内置登录页启动失败：{error.Message}。请确认远程电脑已安装 Microsoft Edge WebView2 Runtime。";
        }
    }

    private async void Capture_Click(object sender, RoutedEventArgs e) => await CaptureCookiesAsync();

    private async Task CaptureCookiesAsync()
    {
        if (LoginBrowser.CoreWebView2 is null || _saved) return;
        try
        {
            var cookies = await LoginBrowser.CoreWebView2.CookieManager.GetCookiesAsync(_loginUri.AbsoluteUri);
            var cookie = string.Join("; ", cookies
                .Where(item => !string.IsNullOrWhiteSpace(item.Name))
                .GroupBy(item => item.Name, StringComparer.OrdinalIgnoreCase)
                .Select(group => $"{group.Key}={group.Last().Value}"));
            if (!HasRequiredCookie(_provider, cookie))
            {
                LoginStatus.Text = "尚未检测到有效登录状态。请先完成平台登录；如果刚登录完成，可点“检查登录状态”。";
                return;
            }
            _music.SaveCookie(_provider, cookie);
            _saved = true;
            LoginStatus.Text = "登录成功，账号会话已自动加密保存。可以关闭此窗口。";
        }
        catch (Exception error)
        {
            LoginStatus.Text = $"读取登录状态失败：{error.Message}";
        }
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

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
