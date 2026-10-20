using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SoundDesk;

/// <summary>Per-provider login status with embedded login, mirroring the Mac account window.</summary>
public sealed class PlatformAccountWindow : Window
{
    private readonly PlatformMusicService _platform = new();
    private readonly Dictionary<MusicProvider, TextBlock> _states = [];
    private readonly Dictionary<MusicProvider, Button> _logouts = [];
    private static readonly (MusicProvider Provider, string Title)[] Providers =
        [(MusicProvider.NetEase, "网易云音乐"), (MusicProvider.QQ, "QQ 音乐"), (MusicProvider.Kugou, "酷狗音乐")];

    public PlatformAccountWindow()
    {
        Title = "平台账号";
        Width = 620;
        Height = 430;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(0x14, 0x1A, 0x28));
        Foreground = Brushes.White;

        var root = new DockPanel { Margin = new Thickness(24) };
        var header = new StackPanel { Margin = new Thickness(0, 0, 0, 18) };
        header.Children.Add(new TextBlock { Text = "平台账号", FontSize = 22, FontWeight = FontWeights.SemiBold });
        header.Children.Add(new TextBlock
        {
            Text = "登录后可在歌曲列表中浏览个人歌单。登录状态由 Windows DPAPI 加密保存在本机。",
            FontSize = 12, Foreground = (Brush)Application.Current.FindResource("MutedBrush"), Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap
        });
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);

        var refreshAll = new Button { Content = "刷新全部状态", HorizontalAlignment = HorizontalAlignment.Right, Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(0, 12, 0, 0) };
        refreshAll.Click += async (_, _) => await RefreshAllAsync();
        DockPanel.SetDock(refreshAll, Dock.Bottom);
        root.Children.Add(refreshAll);

        var rows = new StackPanel();
        foreach (var (provider, title) in Providers) rows.Children.Add(BuildRow(provider, title));
        root.Children.Add(rows);
        Content = root;
        Loaded += async (_, _) => await RefreshAllAsync();
    }

    private Border BuildRow(MusicProvider provider, string title)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = title, FontSize = 15, FontWeight = FontWeights.Medium });
        var state = new TextBlock { Text = "检查中…", FontSize = 12, Foreground = (Brush)Application.Current.FindResource("MutedBrush"), Margin = new Thickness(0, 4, 0, 0) };
        _states[provider] = state;
        text.Children.Add(state);
        grid.Children.Add(text);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var login = new Button { Content = "内嵌登录", Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(0, 0, 8, 0) };
        login.Click += async (_, _) =>
        {
            new PlatformLoginWindow(provider) { Owner = this }.ShowDialog();
            await RefreshAsync(provider);
        };
        var refresh = new Button { Content = "刷新", Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(0, 0, 8, 0) };
        refresh.Click += async (_, _) => await RefreshAsync(provider);
        var logout = new Button { Content = "退出账号", Padding = new Thickness(12, 5, 12, 5), Visibility = Visibility.Collapsed };
        logout.Click += async (_, _) =>
        {
            if (MessageBox.Show(this, $"确定退出{title}账号？", "平台账号", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            _platform.DeleteCookie(provider);
            await RefreshAsync(provider);
        };
        _logouts[provider] = logout;
        actions.Children.Add(login);
        actions.Children.Add(refresh);
        actions.Children.Add(logout);
        Grid.SetColumn(actions, 1);
        grid.Children.Add(actions);

        return new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(14),
            Padding = new Thickness(16, 14, 16, 14), Margin = new Thickness(0, 0, 0, 10), Child = grid
        };
    }

    private Task RefreshAllAsync() => Task.WhenAll(Providers.Select(item => RefreshAsync(item.Provider)));

    private async Task RefreshAsync(MusicProvider provider)
    {
        var state = _states[provider];
        state.Text = "检查中…";
        try
        {
            var (loggedIn, account) = await _platform.GetLoginStatusAsync(provider);
            state.Text = loggedIn ? $"已登录 · {account ?? "账号"}" : "未登录";
            state.Foreground = loggedIn ? new SolidColorBrush(Color.FromRgb(0x5E, 0xD4, 0x8A)) : (Brush)Application.Current.FindResource("MutedBrush");
            _logouts[provider].Visibility = _platform.LoadCookie(provider) is { Length: > 0 } ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Exception error)
        {
            state.Text = $"状态检查失败：{error.Message}";
        }
    }
}
