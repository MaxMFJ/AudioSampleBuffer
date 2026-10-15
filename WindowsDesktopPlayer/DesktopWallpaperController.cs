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
    private NativeWallpaperRenderer? _nativeRenderer;
    private ImageSource? _artwork;
    private bool _disposed;

    public int EffectIndex { get; private set; }
    public bool IsVisible => _window?.IsVisible == true;
    public string? Error { get; private set; }

    public DesktopWallpaperController(AudioReactiveMonitor audio)
    {
        _audio = audio;
        try
        {
            if (int.TryParse(File.ReadAllText(_settingsPath), out var saved))
                EffectIndex = Math.Clamp(saved, 0, DesktopEffectCount - 1);
        }
        catch (IOException) { }
        _timer.Tick += (_, _) =>
        {
            if (_nativeRenderer?.Render(EffectIndex, _audio.Spectrum) != true)
                _window?.Surface.InvalidateVisual();
        };
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

    public void SetArtwork(ImageSource? artwork)
    {
        _artwork = artwork;
        _window?.Surface.SetArtwork(artwork);
        _nativeRenderer?.SetArtwork(artwork);
    }

    public void Show()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        Error = null;
        if (_window is null)
        {
            WallpaperDiagnostics.Write($"Starting wallpaper; effect={EffectIndex}; directory={AppContext.BaseDirectory}");
            _window = new WallpaperWindow(_audio, EffectIndex);
            _window.Show();
            if (!AttachBehindDesktopIcons(_window))
            {
                Error = "无法把动态桌面窗口挂载到 Windows 桌面层（WorkerW/Progman）。";
                WallpaperDiagnostics.Write(Error);
                _window.Close();
                _window = null;
                return;
            }
            var hwnd = new WindowInteropHelper(_window).Handle;
            GetClientRect(hwnd, out var client);
            WallpaperDiagnostics.Write($"Desktop host attached; parent=0x{GetParent(hwnd).ToInt64():X}; client={client.Right - client.Left}x{client.Bottom - client.Top}");
            _nativeRenderer = NativeWallpaperRenderer.TryCreate(hwnd,
                Math.Max(1, client.Right - client.Left), Math.Max(1, client.Bottom - client.Top), out var rendererError);
            if (_nativeRenderer is not null) _nativeRenderer.SetArtwork(_artwork);
            else WallpaperDiagnostics.Write($"Direct3D wallpaper unavailable; using WPF fallback: {rendererError}");
        }
        else _window.Show();
        _nativeRenderer?.SetVisible(true);
        _timer.Start();
    }

    public void Hide()
    {
        _timer.Stop();
        _nativeRenderer?.SetVisible(false);
        _window?.Hide();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _nativeRenderer?.Dispose();
        _nativeRenderer = null;
        _window?.Close();
        _window = null;
    }

    private static bool AttachBehindDesktopIcons(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return false;
        var host = FindDesktopWallpaperHost();
        var programManager = FindWindow("Progman", null);
        if (host != IntPtr.Zero && TryAttach(hwnd, host)) return true;
        return programManager != IntPtr.Zero && programManager != host && TryAttach(hwnd, programManager);
    }

    private static bool TryAttach(IntPtr hwnd, IntPtr host)
    {
        var oldParent = GetParent(hwnd);
        var style = GetWindowLongPtr(hwnd, GwlStyle).ToInt64();
        var exStyle = GetWindowLongPtr(hwnd, GwlExStyle).ToInt64();
        var childStyle = (style | WsChild | WsVisible) & ~WsPopup;
        var clickThroughStyle = exStyle | WsExTransparent | WsExNoActivate | WsExToolWindow;
        SetWindowLongPtr(hwnd, GwlStyle, new IntPtr(childStyle));
        SetWindowLongPtr(hwnd, GwlExStyle, new IntPtr(clickThroughStyle));
        SetParent(hwnd, host);
        var attached = GetParent(hwnd) == host && SetWindowPos(hwnd, IntPtr.Zero, GetSystemMetrics(SmX), GetSystemMetrics(SmY),
            GetSystemMetrics(SmCxVirtualScreen), GetSystemMetrics(SmCyVirtualScreen),
            SwpNoActivate | SwpFrameChanged | SwpShowWindow);
        if (attached) return true;

        SetParent(hwnd, oldParent);
        SetWindowLongPtr(hwnd, GwlStyle, new IntPtr(style));
        SetWindowLongPtr(hwnd, GwlExStyle, new IntPtr(exStyle));
        SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, SwpNoActivate | SwpNoMove | SwpNoSize | SwpFrameChanged | SwpShowWindow);
        return false;
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
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpFrameChanged = 0x0020;
    private const uint SwpShowWindow = 0x0040;
    private const int SmX = 76;
    private const int SmY = 77;
    private const int SmCxVirtualScreen = 78;
    private const int SmCyVirtualScreen = 79;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetClientRect(IntPtr hwnd, out NativeRect rect);

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string className, string? title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string? title);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetParent(IntPtr child, IntPtr newParent);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetParent(IntPtr child);
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
