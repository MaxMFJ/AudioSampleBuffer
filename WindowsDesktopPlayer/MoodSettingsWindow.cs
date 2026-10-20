using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SoundDesk;

/// <summary>OpenAI-compatible endpoint settings for <see cref="DesktopMoodService"/>.</summary>
public sealed class MoodSettingsWindow : Window
{
    private readonly TextBox _baseUrl = new() { Height = 32, VerticalContentAlignment = VerticalAlignment.Center };
    private readonly TextBox _model = new() { Height = 32, VerticalContentAlignment = VerticalAlignment.Center };
    private readonly PasswordBox _apiKey = new() { Height = 32, VerticalContentAlignment = VerticalAlignment.Center, Background = new SolidColorBrush(Color.FromRgb(0x20, 0x2B, 0x3E)), Foreground = Brushes.White, BorderBrush = new SolidColorBrush(Color.FromArgb(70, 255, 255, 255)), Padding = new Thickness(8, 0, 8, 0) };
    private readonly TextBlock _error = new() { Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x7A, 0x7A)), FontSize = 12, Margin = new Thickness(0, 10, 0, 0), TextWrapping = TextWrapping.Wrap };

    public MoodSettingsWindow()
    {
        Title = "氛围光 AI 设置";
        Width = 460;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(0x14, 0x1A, 0x28));
        Foreground = Brushes.White;
        var mood = DesktopMoodService.Shared;
        _baseUrl.Text = mood.BaseUrl;
        _model.Text = mood.Model;
        _apiKey.Password = mood.ApiKey;

        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock
        {
            Text = "使用 OpenAI 兼容接口，根据歌名为桌面光效生成情绪配色。API Key 会用 Windows DPAPI 加密保存在本机。",
            TextWrapping = TextWrapping.Wrap, Foreground = (Brush)Application.Current.FindResource("MutedBrush"), Margin = new Thickness(0, 0, 0, 16)
        });
        AddField(panel, "Base URL", _baseUrl);
        AddField(panel, "Model", _model);
        AddField(panel, "API Key", _apiKey);
        panel.Children.Add(_error);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        var cancel = new Button { Content = "取消", Width = 80, IsCancel = true, Margin = new Thickness(0, 0, 8, 0) };
        var save = new Button { Content = "保存", Width = 80, IsDefault = true };
        save.Click += (_, _) => Save();
        buttons.Children.Add(cancel);
        buttons.Children.Add(save);
        panel.Children.Add(buttons);
        Content = panel;
    }

    private static void AddField(Panel panel, string label, Control input)
    {
        panel.Children.Add(new TextBlock { Text = label, FontSize = 12, Margin = new Thickness(0, 0, 0, 5) });
        input.Margin = new Thickness(0, 0, 0, 12);
        panel.Children.Add(input);
    }

    private void Save()
    {
        if (!Uri.TryCreate(_baseUrl.Text.Trim(), UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
        {
            _error.Text = "Base URL 必须是 https:// 开头的有效地址。";
            return;
        }
        if (string.IsNullOrWhiteSpace(_model.Text))
        {
            _error.Text = "请填写模型名称。";
            return;
        }
        try
        {
            DesktopMoodService.Shared.Configure(_baseUrl.Text, _model.Text, _apiKey.Password);
            DialogResult = true;
        }
        catch (Exception error)
        {
            _error.Text = $"保存失败：{error.Message}";
        }
    }
}
