using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace SoundDesk;

/// <summary>Hosts a reactive, click-through WPF surface behind the Windows desktop icons.</summary>
public sealed class DesktopWallpaperController : IDisposable
{
    private const int DesktopEffectCount = 4;
    private readonly AudioReactiveMonitor _audio;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(40) };
    private readonly string _settingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SoundDesk", "desktop-effect.txt");
    private WallpaperWindow? _window;
    private bool _disposed;

    public int EffectIndex { get; private set; }
    public bool IsVisible => _window?.IsVisible == true;

    public DesktopWallpaperController(AudioReactiveMonitor audio)
    {
        _audio = audio;
        try
        {
            if (int.TryParse(File.ReadAllText(_settingsPath), out var saved))
                EffectIndex = Math.Clamp(saved, 0, DesktopEffectCount - 1);
        }
        catch (IOException) { }
        _timer.Tick += (_, _) => _window?.Surface.InvalidateVisual();
    }

    public void SetEffect(int effectIndex)
    {
        EffectIndex = Math.Clamp(effectIndex, 0, DesktopEffectCount - 1);
        if (_window is not null) _window.Surface.EffectIndex = EffectIndex;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
            File.WriteAllText(_settingsPath, EffectIndex.ToString());
        }
        catch (IOException) { }
    }

    public void SetArtwork(ImageSource? artwork) => _window?.Surface.SetArtwork(artwork);

    public void Show()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_window is null)
        {
            _window = new WallpaperWindow(_audio, EffectIndex);
            _window.Show();
            AttachBehindDesktopIcons(_window);
        }
        else _window.Show();
        _timer.Start();
    }

    public void Hide()
    {
        _timer.Stop();
        _window?.Hide();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _window?.Close();
        _window = null;
    }

    private static void AttachBehindDesktopIcons(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        var host = FindDesktopWallpaperHost();
        if (host == IntPtr.Zero) return;

        var style = GetWindowLongPtr(hwnd, GwlStyle).ToInt64();
        style = (style | WsChild | WsVisible) & ~WsPopup;
        SetWindowLongPtr(hwnd, GwlStyle, new IntPtr(style));
        var exStyle = GetWindowLongPtr(hwnd, GwlExStyle).ToInt64();
        exStyle |= WsExTransparent | WsExNoActivate | WsExToolWindow;
        SetWindowLongPtr(hwnd, GwlExStyle, new IntPtr(exStyle));
        SetParent(hwnd, host);
        SetWindowPos(hwnd, IntPtr.Zero, GetSystemMetrics(SmX), GetSystemMetrics(SmY),
            GetSystemMetrics(SmCxVirtualScreen), GetSystemMetrics(SmCyVirtualScreen),
            SwpNoActivate | SwpFrameChanged | SwpShowWindow);
    }

    private static IntPtr FindDesktopWallpaperHost()
    {
        var programManager = FindWindow("Progman", null);
        if (programManager != IntPtr.Zero)
            SendMessageTimeout(programManager, 0x052C, new IntPtr(0xD), new IntPtr(0x1), 0, 1000, out _);

        var host = IntPtr.Zero;
        EnumWindows((top, _) =>
        {
            var shellView = FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (shellView == IntPtr.Zero) return true;
            host = FindWindowEx(IntPtr.Zero, top, "WorkerW", null);
            return false;
        }, IntPtr.Zero);
        return host != IntPtr.Zero ? host : programManager;
    }

    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const long WsChild = 0x40000000L;
    private const long WsPopup = unchecked((long)0x80000000);
    private const long WsVisible = 0x10000000L;
    private const long WsExTransparent = 0x00000020L;
    private const long WsExToolWindow = 0x00000080L;
    private const long WsExNoActivate = 0x08000000L;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpFrameChanged = 0x0020;
    private const uint SwpShowWindow = 0x0040;
    private const int SmX = 76;
    private const int SmY = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string className, string? title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string? title);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetParent(IntPtr child, IntPtr newParent);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);

    private sealed class WallpaperWindow : Window
    {
        public DesktopWallpaperSurface Surface { get; }

        public WallpaperWindow(AudioReactiveMonitor audio, int effectIndex)
        {
            Surface = new DesktopWallpaperSurface(audio) { EffectIndex = effectIndex };
            Content = Surface;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = false;
            Focusable = false;
            IsHitTestVisible = false;
            Background = System.Windows.Media.Brushes.Black;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = SystemParameters.VirtualScreenLeft;
            Top = SystemParameters.VirtualScreenTop;
            Width = SystemParameters.VirtualScreenWidth;
            Height = SystemParameters.VirtualScreenHeight;
        }
    }
}
