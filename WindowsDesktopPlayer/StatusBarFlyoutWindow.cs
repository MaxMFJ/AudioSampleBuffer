using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SoundDesk;

public sealed class StatusBarFlyoutWindow : Window
{
    private readonly TextBlock _title = new() { Text = "尚未播放", FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock _artist = new() { Foreground = Brushes.LightGray, FontSize = 11 };
    private readonly TextBlock _elapsed = new() { Width = 40, Foreground = Brushes.LightGray, FontSize = 10 };
    private readonly TextBlock _duration = new() { Width = 40, Foreground = Brushes.LightGray, FontSize = 10, TextAlignment = TextAlignment.Right };
    private readonly Image _artwork = new() { Width = 58, Height = 58, Stretch = Stretch.UniformToFill };
    private readonly Slider _progress = new() { Minimum = 0, Maximum = 1, Height = 24 };
    private readonly Button _play = new() { Content = "▶", Width = 42 };
    private readonly Button _repeat = new() { Content = "顺序播放", MinWidth = 76 };
    private readonly Action _toggle, _previous, _next, _repeatAction, _openConsole, _openSongs, _openLyrics;
    private readonly Action<double> _seek;
    private bool _dragging;

    public StatusBarFlyoutWindow(Action toggle, Action previous, Action next, Action repeatAction,
        Action<double> seek, Action openConsole, Action openSongs, Action openLyrics)
    {
        _toggle = toggle; _previous = previous; _next = next; _repeatAction = repeatAction; _seek = seek;
        _openConsole = openConsole; _openSongs = openSongs; _openLyrics = openLyrics;
        Width = 360; Height = 290;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false; Topmost = true; AllowsTransparency = true;
        Background = Brushes.Transparent; ShowActivated = true;
        Content = BuildContent();
        Deactivated += (_, _) => Hide();
        _play.Click += (_, _) => _toggle();
        _repeat.Click += (_, _) => _repeatAction();
        _progress.PreviewMouseLeftButtonDown += (_, _) => _dragging = true;
        _progress.PreviewMouseLeftButtonUp += (_, _) => { _dragging = false; _seek(_progress.Value); };
        _progress.KeyUp += (_, _) => _seek(_progress.Value);
    }

    public void UpdateState(bool isPlaying, int repeatMode, string title, string artist,
        ImageSource? artwork, double position, double duration)
    {
        _title.Text = string.IsNullOrWhiteSpace(title) ? "尚未播放" : title;
        _artist.Text = artist;
        _artwork.Source = artwork;
        _play.Content = isPlaying ? "Ⅱ" : "▶";
        _repeat.Content = repeatMode switch { 1 => "列表循环", 2 => "单曲循环", _ => "顺序播放" };
        _progress.Maximum = Math.Max(1, duration);
        if (!_dragging) _progress.Value = Math.Clamp(position, 0, _progress.Maximum);
        _elapsed.Text = TimeLabel(position);
        _duration.Text = TimeLabel(duration);
        _progress.IsEnabled = duration > 0;
    }

    public void OpenNearTaskbar()
    {
        var work = SystemParameters.WorkArea;
        Left = Math.Clamp(work.Left + work.Width - Width - 10, work.Left, work.Right - Width);
        Top = Math.Max(work.Top, work.Bottom - Height - 8);
        if (!IsVisible) Show();
        Activate();
    }

    private UIElement BuildContent()
    {
        var panel = new StackPanel { Margin = new Thickness(18) };
        var card = new Border
        {
            CornerRadius = new CornerRadius(18), Padding = new Thickness(16),
            BorderThickness = new Thickness(1), BorderBrush = new SolidColorBrush(Color.FromArgb(65, 255, 255, 255)),
            Background = new SolidColorBrush(Color.FromArgb(245, 24, 30, 45)), Child = panel
        };
        panel.Children.Add(new TextBlock { Text = "SOUND DESK", Foreground = Brushes.LightSteelBlue, FontSize = 10, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 12) });
        var meta = new Grid { Height = 58, Margin = new Thickness(0, 0, 0, 8) };
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(58) });
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        meta.ColumnDefinitions.Add(new ColumnDefinition());
        _artwork.Clip = new RectangleGeometry(new Rect(0, 0, 58, 58), 10, 10);
        meta.Children.Add(_artwork);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(_title); text.Children.Add(_artist);
        Grid.SetColumn(text, 2); meta.Children.Add(text);
        panel.Children.Add(meta);
        var seek = new Grid { Margin = new Thickness(0, 4, 0, 4) };
        seek.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        seek.ColumnDefinitions.Add(new ColumnDefinition());
        seek.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        seek.Children.Add(_elapsed); Grid.SetColumn(_progress, 1); seek.Children.Add(_progress);
        Grid.SetColumn(_duration, 2); seek.Children.Add(_duration); panel.Children.Add(seek);
        var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 10) };
        var previous = new Button { Content = "|◀", Width = 44 }; previous.Click += (_, _) => _previous();
        var next = new Button { Content = "▶|", Width = 44 }; next.Click += (_, _) => _next();
        controls.Children.Add(previous); controls.Children.Add(_play); controls.Children.Add(next); controls.Children.Add(_repeat);
        panel.Children.Add(controls);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        var songs = new Button { Content = "歌曲列表", Margin = new Thickness(3), Padding = new Thickness(8, 5, 8, 5) };
        var lyrics = new Button { Content = "歌词管理", Margin = new Thickness(3), Padding = new Thickness(8, 5, 8, 5) };
        var console = new Button { Content = "打开控制台", Margin = new Thickness(3), Padding = new Thickness(8, 5, 8, 5) };
        songs.Click += (_, _) => { Hide(); _openSongs(); };
        lyrics.Click += (_, _) => { Hide(); _openLyrics(); };
        console.Click += (_, _) => { Hide(); _openConsole(); };
        actions.Children.Add(songs); actions.Children.Add(lyrics); actions.Children.Add(console);
        panel.Children.Add(actions);
        return card;
    }

    private static string TimeLabel(double seconds)
    {
        var time = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return $"{(int)time.TotalMinutes}:{time.Seconds:00}";
    }
}
