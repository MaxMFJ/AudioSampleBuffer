using System.Windows;
using System.Windows.Controls;

namespace SoundDesk;

internal sealed class TextPromptWindow : Window
{
    private readonly TextBox _input = new() { MinWidth = 280, Margin = new Thickness(0, 14, 0, 18) };
    private string? _result;

    private TextPromptWindow(string title, string prompt)
    {
        Title = title;
        Width = 380;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(16, 20, 31));
        Foreground = System.Windows.Media.Brushes.White;
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock { Text = prompt });
        panel.Children.Add(_input);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", IsCancel = true, Margin = new Thickness(0, 0, 8, 0) };
        var confirm = new Button { Content = "创建", IsDefault = true };
        cancel.Click += (_, _) => Close();
        confirm.Click += (_, _) => { _result = _input.Text; DialogResult = true; };
        actions.Children.Add(cancel);
        actions.Children.Add(confirm);
        panel.Children.Add(actions);
        Content = panel;
        Loaded += (_, _) => _input.Focus();
    }

    public static string? Show(Window owner, string title, string prompt)
    {
        var dialog = new TextPromptWindow(title, prompt) { Owner = owner };
        return dialog.ShowDialog() == true ? dialog._result : null;
    }
}
