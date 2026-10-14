using System.Windows;
using System.Windows.Controls;
using System.IO;
using System.Text.Json;

namespace SoundDesk;

public sealed class LyricsDisplaySettings
{
    public bool Enabled { get; set; }
    public int LineCount { get; set; } = 3;
    public double PositionX { get; set; } = .5;
    public double PositionY { get; set; } = .82;
    public double LineSpacing { get; set; } = 8;
    public double WidthFraction { get; set; } = .72;
    public double FontSize { get; set; } = 28;
    public double InactiveScale { get; set; } = .68;
    public double InactiveOpacity { get; set; } = .55;
    public string WindowMode { get; set; } = "当前行居中";
    public string Layout { get; set; } = "纵向排列";
}

public sealed class LyricsSettingsWindow : Window
{
    private readonly Action<LyricsDisplaySettings> _changed;
    private readonly LyricsDisplaySettings _settings;
    private readonly StackPanel _settingsPanel = new() { Margin = new Thickness(22) };
    private bool _updating;

    public LyricsSettingsWindow(LyricsDisplaySettings settings, Action<LyricsDisplaySettings> changed)
    {
        _settings = settings;
        _changed = changed;
        Title = "歌词管理";
        Width = 620;
        Height = 760;
        MinWidth = 560;
        MinHeight = 640;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(16, 20, 31));
        Foreground = System.Windows.Media.Brushes.White;
        Content = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _settingsPanel };
        BuildControls();
    }

    private void BuildControls()
    {
        _settingsPanel.Children.Add(new TextBlock { Text = "歌词管理", FontSize = 25, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 4) });
        _settingsPanel.Children.Add(new TextBlock { Text = "修改立即生效，并自动保存到本机。", Foreground = System.Windows.Media.Brushes.LightGray, Margin = new Thickness(0, 0, 0, 18) });
        var enabled = new CheckBox { Content = "显示桌面歌词", IsChecked = _settings.Enabled, Margin = new Thickness(0, 0, 0, 15) };
        enabled.Checked += (_, _) => Update(() => _settings.Enabled = true);
        enabled.Unchecked += (_, _) => Update(() => _settings.Enabled = false);
        _settingsPanel.Children.Add(enabled);
        AddSection("显示方式");
        AddCombo("切换方式", ["当前行居中", "整组切换"], _settings.WindowMode, value => _settings.WindowMode = value);
        AddCombo("排列", ["纵向排列", "分散排列"], _settings.Layout, value => _settings.Layout = value);
        AddSlider("行数", 1, 12, _settings.LineCount, value => _settings.LineCount = (int)Math.Round(value), "0");
        AddSection("位置与尺寸");
        AddSlider("水平位置", 0, 1, _settings.PositionX, value => _settings.PositionX = value, "P");
        AddSlider("垂直位置", 0, 1, _settings.PositionY, value => _settings.PositionY = value, "P");
        AddSlider("行间距", 0, 30, _settings.LineSpacing, value => _settings.LineSpacing = value, "0");
        AddSlider("最大宽度", .2, 1, _settings.WidthFraction, value => _settings.WidthFraction = value, "P");
        AddSection("字体与非当前行");
        AddSlider("字号", 12, 72, _settings.FontSize, value => _settings.FontSize = value, "0");
        AddSlider("非当前行字号", .3, 1, _settings.InactiveScale, value => _settings.InactiveScale = value, "P");
        AddSlider("非当前行透明度", 0, 1, _settings.InactiveOpacity, value => _settings.InactiveOpacity = value, "P");
        var reset = new Button { Content = "恢复默认设置", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 18, 0, 0) };
        reset.Click += (_, _) =>
        {
            var defaults = new LyricsDisplaySettings { Enabled = _settings.Enabled };
            Copy(defaults, _settings);
            _settingsPanel.Children.Clear();
            BuildControls();
            _changed(_settings);
        };
        _settingsPanel.Children.Add(reset);
    }

    private void AddSection(string title) => _settingsPanel.Children.Add(new TextBlock
    {
        Text = title, FontSize = 15, FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 12, 0, 8), Foreground = System.Windows.Media.Brushes.LightSteelBlue
    });

    private void AddCombo(string title, string[] values, string selected, Action<string> assign)
    {
        var combo = new ComboBox { ItemsSource = values, SelectedItem = selected, Margin = new Thickness(0, 0, 0, 10), Height = 34 };
        combo.SelectionChanged += (_, _) => { if (!_updating && combo.SelectedItem is string value) Update(() => assign(value)); };
        var row = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 3, 0, 3) };
        row.Children.Add(new TextBlock { Text = title, Width = 150, VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(combo);
        _settingsPanel.Children.Add(row);
    }

    private void AddSlider(string title, double min, double max, double value, Action<double> assign, string format)
    {
        var slider = new Slider { Minimum = min, Maximum = max, Value = value, TickFrequency = (max - min) / 100, IsSnapToTickEnabled = false };
        var readout = new TextBlock { Width = 58, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        void Refresh() => readout.Text = format == "P" ? $"{slider.Value:P0}" : $"{slider.Value:0}";
        Refresh();
        slider.ValueChanged += (_, _) => { Refresh(); if (!_updating) Update(() => assign(slider.Value)); };
        var row = new Grid { Margin = new Thickness(0, 5, 0, 5) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(68) });
        row.Children.Add(new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(slider, 1); row.Children.Add(slider);
        Grid.SetColumn(readout, 2); row.Children.Add(readout);
        _settingsPanel.Children.Add(row);
    }

    private void Update(Action change) { change(); _changed(_settings); }

    private static void Copy(LyricsDisplaySettings source, LyricsDisplaySettings target)
    {
        target.LineCount = source.LineCount; target.PositionX = source.PositionX; target.PositionY = source.PositionY;
        target.LineSpacing = source.LineSpacing; target.WidthFraction = source.WidthFraction; target.FontSize = source.FontSize;
        target.InactiveScale = source.InactiveScale; target.InactiveOpacity = source.InactiveOpacity;
        target.WindowMode = source.WindowMode; target.Layout = source.Layout;
    }
}
