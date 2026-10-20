using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace SoundDesk;

/// <summary>Notification-area popover mirroring the Mac status bar player: artwork backdrop
/// under a dark scrim, centered metadata, seek bar, transport, console and quit actions.</summary>
public sealed class StatusBarFlyoutWindow : Window
{
    private const double PopoverWidth = 360;
    private const double PopoverHeight = 292;

    private readonly TextBlock _title = new() { Text = "尚未播放", FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center };
    private readonly TextBlock _artist = new() { Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)), FontSize = 12, Margin = new Thickness(0, 4, 0, 0), TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center };
    private readonly TextBlock _elapsed = new() { Width = 40, Foreground = Brushes.Gainsboro, FontSize = 10, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _duration = new() { Width = 40, Foreground = Brushes.Gainsboro, FontSize = 10, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    private readonly Image _artwork = new() { Stretch = Stretch.UniformToFill, Effect = new BlurEffect { Radius = 18 }, Margin = new Thickness(-24) };
    private readonly Slider _progress = new() { Minimum = 0, Maximum = 1, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button _play = new() { Content = "▶", Width = 54, Height = 40, FontSize = 16 };
    private readonly Button _repeat = new() { Content = "顺序播放", Height = 30, Padding = new Thickness(12, 0, 12, 0), FontSize = 12 };
    private readonly Action _toggle, _previous, _next, _repeatAction, _openConsole, _exit;
    private readonly Action<double> _seek;
    private bool _dragging;

    public StatusBarFlyoutWindow(Action toggle, Action previous, Action next, Action repeatAction,
        Action<double> seek, Action openConsole, Action exit)
    {
        _toggle = toggle; _previous = previous; _next = next; _repeatAction = repeatAction; _seek = seek;
        _openConsole = openConsole; _exit = exit;
        Width = PopoverWidth; Height = PopoverHeight;
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
        _artist.Text = string.IsNullOrWhiteSpace(artist) ? "Sound Desk" : artist;
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
        var layers = new Grid();
        layers.Children.Add(new Border { Background = new SolidColorBrush(Color.FromRgb(24, 30, 45)) });
        layers.Children.Add(_artwork);
        layers.Children.Add(new Border { Background = new SolidColorBrush(Color.FromArgb(148, 0, 0, 0)) });

        var panel = new StackPanel { Margin = new Thickness(22, 26, 22, 18), VerticalAlignment = VerticalAlignment.Center };
        panel.Children.Add(_title);
        panel.Children.Add(_artist);

        var seek = new Grid { Margin = new Thickness(0, 22, 0, 6) };
        seek.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        seek.ColumnDefinitions.Add(new ColumnDefinition());
        seek.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        seek.Children.Add(_elapsed);
        Grid.SetColumn(_progress, 1); seek.Children.Add(_progress);
        Grid.SetColumn(_duration, 2); seek.Children.Add(_duration);
        panel.Children.Add(seek);

        var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 10) };
        var previous = new Button { Content = "⏮", Width = 44, Height = 34, Margin = new Thickness(0, 0, 14, 0) };
        previous.Click += (_, _) => _previous();
        var next = new Button { Content = "⏭", Width = 44, Height = 34, Margin = new Thickness(14, 0, 0, 0) };
        next.Click += (_, _) => _next();
        controls.Children.Add(previous); controls.Children.Add(_play); controls.Children.Add(next);
        panel.Children.Add(controls);

        var repeatRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 12) };
        repeatRow.Children.Add(_repeat);
        panel.Children.Add(repeatRow);

        var actions = new Grid();
        actions.ColumnDefinitions.Add(new ColumnDefinition());
        actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        actions.ColumnDefinitions.Add(new ColumnDefinition());
        var console = new Button { Content = "打开控制台", Height = 32 };
        console.Click += (_, _) => { Hide(); _openConsole(); };
        var quit = new Button { Content = "退出程序", Height = 32 };
        quit.Click += (_, _) => { Hide(); _exit(); };
        actions.Children.Add(console);
        Grid.SetColumn(quit, 2); actions.Children.Add(quit);
        panel.Children.Add(actions);
        layers.Children.Add(panel);

        return new Border
        {
            CornerRadius = new CornerRadius(16), ClipToBounds = true,
            BorderThickness = new Thickness(1), BorderBrush = new SolidColorBrush(Color.FromArgb(65, 255, 255, 255)),
            Child = layers,
            Clip = new RectangleGeometry(new Rect(0, 0, PopoverWidth, PopoverHeight), 16, 16)
        };
    }

    private static string TimeLabel(double seconds)
    {
        var time = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return $"{(int)time.TotalMinutes}:{time.Seconds:00}";
    }
}
