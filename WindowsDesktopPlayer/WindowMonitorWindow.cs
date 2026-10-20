using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace SoundDesk;

public sealed record MonitoredWindow(IntPtr Handle, string Title)
{
    public override string ToString() => Title;
}

/// <summary>Live preview of another app window through a DWM thumbnail, the Windows
/// counterpart of the Mac ScreenCaptureKit window monitor.</summary>
public sealed class WindowMonitorWindow : Window
{
    private readonly ComboBox _picker = new() { Width = 360, Height = 32 };
    private readonly CheckBox _topmost = new() { Content = "置顶", IsChecked = true, Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
    private readonly Border _host = new() { Background = new SolidColorBrush(Color.FromRgb(0x0B, 0x0E, 0x16)), CornerRadius = new CornerRadius(12) };
    private readonly TextBlock _placeholder = new() { Text = "选择一个窗口开始实时预览", Foreground = Brushes.Gray, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private IntPtr _thumbnail;

    public WindowMonitorWindow()
    {
        Title = "窗口预览";
        Width = 720;
        Height = 480;
        MinWidth = 420;
        MinHeight = 300;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(0x14, 0x1A, 0x28));
        Foreground = Brushes.White;

        var root = new DockPanel { Margin = new Thickness(14) };
        var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 12) };
        var refresh = new Button { Content = "刷新窗口", Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(10, 0, 0, 0) };
        refresh.Click += (_, _) => RefreshWindows();
        _picker.SelectionChanged += (_, _) => Attach(_picker.SelectedItem as MonitoredWindow);
        _topmost.Click += (_, _) => Topmost = _topmost.IsChecked == true;
        toolbar.Children.Add(_picker);
        toolbar.Children.Add(refresh);
        toolbar.Children.Add(_topmost);
        DockPanel.SetDock(toolbar, Dock.Top);
        root.Children.Add(toolbar);
        _host.Child = _placeholder;
        root.Children.Add(_host);
        Content = root;

        Loaded += (_, _) => RefreshWindows();
        _host.SizeChanged += (_, _) => UpdateThumbnail();
        Closed += (_, _) => Detach();
    }

    private void RefreshWindows()
    {
        var selected = (_picker.SelectedItem as MonitoredWindow)?.Handle;
        var own = Environment.ProcessId;
        var windows = new List<MonitoredWindow>();
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd) || GetWindow(hwnd, 4) != IntPtr.Zero) return true;
            if ((GetWindowLongPtr(hwnd, -20).ToInt64() & 0x80) != 0) return true;
            if (DwmGetWindowAttribute(hwnd, 14, out var cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == own) return true;
            var length = GetWindowTextLength(hwnd);
            if (length == 0) return true;
            var text = new StringBuilder(length + 1);
            GetWindowText(hwnd, text, text.Capacity);
            var processName = "";
            try { processName = Process.GetProcessById((int)pid).ProcessName; } catch { }
            windows.Add(new MonitoredWindow(hwnd, processName.Length > 0 ? $"{text} — {processName}" : text.ToString()));
            return true;
        }, IntPtr.Zero);
        _picker.ItemsSource = windows;
        _picker.SelectedItem = windows.FirstOrDefault(item => item.Handle == selected);
        if (_picker.SelectedItem is null) Attach(null);
    }

    private void Attach(MonitoredWindow? window)
    {
        Detach();
        _placeholder.Visibility = Visibility.Visible;
        if (window is null) return;
        var self = new WindowInteropHelper(this).Handle;
        if (DwmRegisterThumbnail(self, window.Handle, out _thumbnail) != 0)
        {
            _thumbnail = IntPtr.Zero;
            _placeholder.Text = "无法预览这个窗口";
            return;
        }
        _placeholder.Visibility = Visibility.Collapsed;
        UpdateThumbnail();
    }

    private void Detach()
    {
        if (_thumbnail == IntPtr.Zero) return;
        DwmUnregisterThumbnail(_thumbnail);
        _thumbnail = IntPtr.Zero;
    }

    private void UpdateThumbnail()
    {
        if (_thumbnail == IntPtr.Zero || PresentationSource.FromVisual(this) is not { CompositionTarget: { } target }) return;
        var scale = target.TransformToDevice;
        var origin = _host.TransformToAncestor(this).Transform(new Point(0, 0));
        var area = new Rect(origin.X * scale.M11, origin.Y * scale.M22, _host.ActualWidth * scale.M11, _host.ActualHeight * scale.M22);
        if (DwmQueryThumbnailSourceSize(_thumbnail, out var source) == 0 && source.X > 0 && source.Y > 0)
        {
            var fit = Math.Min(area.Width / source.X, area.Height / source.Y);
            var width = source.X * fit;
            var height = source.Y * fit;
            area = new Rect(area.X + (area.Width - width) / 2, area.Y + (area.Height - height) / 2, width, height);
        }
        var properties = new DwmThumbnailProperties
        {
            Flags = 0x1 | 0x4 | 0x8 | 0x10,
            Destination = new NativeRect { Left = (int)area.Left, Top = (int)area.Top, Right = (int)area.Right, Bottom = (int)area.Bottom },
            Opacity = 255,
            Visible = true,
            SourceClientAreaOnly = false
        };
        DwmUpdateThumbnailProperties(_thumbnail, ref properties);
    }

    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct NativeSize { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DwmThumbnailProperties
    {
        public int Flags;
        public NativeRect Destination;
        public NativeRect Source;
        public byte Opacity;
        [MarshalAs(UnmanagedType.Bool)] public bool Visible;
        [MarshalAs(UnmanagedType.Bool)] public bool SourceClientAreaOnly;
    }

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmRegisterThumbnail(IntPtr destination, IntPtr source, out IntPtr thumbnail);
    [DllImport("dwmapi.dll")] private static extern int DwmUnregisterThumbnail(IntPtr thumbnail);
    [DllImport("dwmapi.dll")] private static extern int DwmUpdateThumbnailProperties(IntPtr thumbnail, ref DwmThumbnailProperties properties);
    [DllImport("dwmapi.dll")] private static extern int DwmQueryThumbnailSourceSize(IntPtr thumbnail, out NativeSize size);
}
