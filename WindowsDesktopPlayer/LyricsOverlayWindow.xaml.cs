using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace SoundDesk;

public partial class LyricsOverlayWindow : Window
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExToolWindow = 0x00000080;
    private LyricsDisplaySettings _settings;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint window, int index, nint value);

    public LyricsOverlayWindow(LyricsDisplaySettings settings)
    {
        InitializeComponent();
        _settings = settings;
        Loaded += (_, _) => { ApplySettings(settings); EnableClickThrough(); };
    }

    public void ApplySettings(LyricsDisplaySettings settings)
    {
        _settings = settings;
        var area = SystemParameters.WorkArea;
        Width = Math.Max(320, area.Width * settings.WidthFraction);
        Height = Math.Max(100, settings.LineCount * (settings.FontSize * 1.25 + settings.LineSpacing));
        Left = area.Left + area.Width * settings.PositionX - Width / 2;
        Top = area.Top + area.Height * settings.PositionY - Height / 2;
        LyricsStack.Width = Width;
    }

    public void ShowLyrics(IReadOnlyList<TimedLyric> lines, double time)
    {
        LyricsStack.Children.Clear();
        if (lines.Count == 0)
        {
            LyricsStack.Children.Add(CreateLine("暂无歌词", true, 0));
            return;
        }

        var frame = LyricsService.FrameAt(lines, time);
        var count = Math.Clamp(_settings.LineCount, 1, 12);
        var active = frame.Active;
        if (active < 0)
        {
            for (var i = 0; i < Math.Min(count, lines.Count); i++) LyricsStack.Children.Add(CreateLine(lines[i].Text, false, i));
            return;
        }
        var start = _settings.WindowMode == "整组切换"
            ? Math.Clamp(active, 0, Math.Max(0, lines.Count - count))
            : Math.Clamp(active - count / 2, 0, Math.Max(0, lines.Count - count));
        for (var index = start; index < Math.Min(lines.Count, start + count); index++)
            LyricsStack.Children.Add(CreateLine(lines[index].Text, index == active, index - start));
    }

    public void ShowFrame(string previous, string current, string next)
    {
        LyricsStack.Children.Clear();
        if (!string.IsNullOrWhiteSpace(previous)) LyricsStack.Children.Add(CreateLine(previous, false, 0));
        LyricsStack.Children.Add(CreateLine(current.Length == 0 ? "♪" : current, true, 1));
        if (!string.IsNullOrWhiteSpace(next)) LyricsStack.Children.Add(CreateLine(next, false, 2));
    }

    private TextBlock CreateLine(string text, bool active, int index)
    {
        var block = new TextBlock
        {
            Text = text,
            Foreground = active ? Brushes.White : new SolidColorBrush(Color.FromArgb((byte)(255 * _settings.InactiveOpacity), 220, 228, 245)),
            FontSize = active ? _settings.FontSize : _settings.FontSize * _settings.InactiveScale,
            FontWeight = active ? FontWeights.SemiBold : FontWeights.Medium,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap,
            Margin = new Thickness(0, _settings.LineSpacing / 2, 0, _settings.LineSpacing / 2),
            Effect = active ? new DropShadowEffect { Color = Color.FromRgb(104, 199, 255), BlurRadius = 22, ShadowDepth = 0, Opacity = .9 } : null
        };
        if (_settings.Layout == "分散排列") block.RenderTransform = new TranslateTransform(index % 2 == 0 ? -Width * .08 : Width * .08, 0);
        return block;
    }

    private void EnableClickThrough()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var style = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        SetWindowLongPtr(handle, GwlExStyle, (nint)(style | WsExTransparent | WsExToolWindow));
    }
}
