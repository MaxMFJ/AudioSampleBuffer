using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace SoundDesk;

/// <summary>
/// Owns the notification area icon and its small player menu. The host owns all
/// player and window lifetime; callbacks are deliberately injected here.
/// </summary>
public sealed class WindowsStatusBarPlayer : IDisposable
{
    private const uint WmUser = 0x0400;
    private const uint WmTray = WmUser + 1;
    private const uint WmCommand = 0x0111;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmLButtonDblClk = 0x0203;
    private const uint WmRButtonUp = 0x0205;
    private const uint TpmRightButton = 0x0002;
    private const uint TpmReturnCmd = 0x0100;
    private const uint NifMessage = 0x0001;
    private const uint NifIcon = 0x0002;
    private const uint NifTip = 0x0004;
    private const uint NimAdd = 0x0000;
    private const uint NimModify = 0x0001;
    private const uint NimDelete = 0x0002;
    private const uint MfString = 0x0000;
    private const uint MfSeparator = 0x0800;
    private const uint MfChecked = 0x0008;
    private const uint MfUnchecked = 0x0000;
    private const uint MiimState = 0x0001;
    private const uint MiimString = 0x0040;

    private const int OpenConsole = 1001;
    private const int Previous = 1002;
    private const int TogglePlayback = 1003;
    private const int Next = 1004;
    private const int Repeat = 1005;
    private const int SongList = 1006;
    private const int LyricsManager = 1007;
    private const int Exit = 1008;

    private readonly Action _openConsole;
    private readonly Action _togglePlayback;
    private readonly Action _previous;
    private readonly Action _next;
    private readonly Action _repeat;
    private readonly Action _songList;
    private readonly Action _lyricsManager;
    private readonly Action _exit;
    private readonly Action<double> _seek;
    private readonly HwndSource _source;
    private readonly NOTIFYICONDATA _icon;
    private bool _isPlaying;
    private bool _repeatEnabled;
    private string _trackTitle = "Sound Desk";
    private bool _disposed;
    private IntPtr _menu;
    private readonly StatusBarFlyoutWindow _flyout;

    public WindowsStatusBarPlayer(
        Action openConsole, Action togglePlayback, Action previous, Action next,
        Action repeat, Action<double> seek, Action songList, Action lyricsManager, Action exit)
    {
        _openConsole = openConsole ?? throw new ArgumentNullException(nameof(openConsole));
        _togglePlayback = togglePlayback ?? throw new ArgumentNullException(nameof(togglePlayback));
        _previous = previous ?? throw new ArgumentNullException(nameof(previous));
        _next = next ?? throw new ArgumentNullException(nameof(next));
        _repeat = repeat ?? throw new ArgumentNullException(nameof(repeat));
        _seek = seek ?? throw new ArgumentNullException(nameof(seek));
        _songList = songList ?? throw new ArgumentNullException(nameof(songList));
        _lyricsManager = lyricsManager ?? throw new ArgumentNullException(nameof(lyricsManager));
        _exit = exit ?? throw new ArgumentNullException(nameof(exit));
        _flyout = new StatusBarFlyoutWindow(_togglePlayback, _previous, _next, _repeat, _seek, _openConsole, _songList, _lyricsManager);

        var parameters = new HwndSourceParameters("SoundDesk.Tray") { Width = 0, Height = 0 };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
        _icon = new NOTIFYICONDATA
        {
            cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _source.Handle,
            uID = 1,
            uFlags = NifMessage | NifIcon | NifTip,
            uCallbackMessage = WmTray,
            hIcon = LoadIcon(IntPtr.Zero, new IntPtr(32512)),
            szTip = "Sound Desk"
        };
        if (!Shell_NotifyIcon(NimAdd, ref _icon))
            throw new InvalidOperationException("Unable to create the Sound Desk notification area icon.");
    }

    public void UpdateState(bool isPlaying, int repeatMode, string? trackTitle = null, string? artist = null,
        ImageSource? artwork = null, double position = 0, double duration = 0)
    {
        _isPlaying = isPlaying;
        _repeatEnabled = repeatMode != 0;
        if (!string.IsNullOrWhiteSpace(trackTitle)) _trackTitle = trackTitle!;
        _flyout.UpdateState(isPlaying, repeatMode, _trackTitle, artist ?? "", artwork, position, duration);
        if (_disposed) return;
        _icon.szTip = TrimTip(_trackTitle);
        _icon.uFlags = NifTip;
        Shell_NotifyIcon(NimModify, ref _icon);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_menu != IntPtr.Zero) { DestroyMenu(_menu); _menu = IntPtr.Zero; }
        _flyout.Close();
        Shell_NotifyIcon(NimDelete, ref _icon);
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == (int)WmTray)
        {
            var mouseMessage = unchecked((uint)lParam.ToInt64());
            if (mouseMessage is WmLButtonDblClk) { _flyout.Hide(); _openConsole(); }
            else if (mouseMessage == WmLButtonUp) _flyout.OpenNearTaskbar();
            else if (mouseMessage == WmRButtonUp) { _flyout.Hide(); ShowMenu(); }
            handled = true;
        }
        else if (msg == WmCommand)
        {
            InvokeCommand(unchecked((int)(wParam.ToInt64() & 0xffff)));
            handled = true;
        }
        return IntPtr.Zero;
    }

    private void ShowMenu()
    {
        if (_menu != IntPtr.Zero) DestroyMenu(_menu);
        _menu = CreatePopupMenu();
        AddItem(OpenConsole, "打开控制台");
        AddItem(Previous, "上一首");
        AddItem(TogglePlayback, _isPlaying ? "暂停" : "播放");
        AddItem(Next, "下一首");
        AddItem(Repeat, _repeatEnabled ? "循环  ✓" : "循环");
        AppendMenu(_menu, MfSeparator, UIntPtr.Zero, string.Empty);
        AddItem(SongList, "歌曲列表");
        AddItem(LyricsManager, "歌词管理");
        AppendMenu(_menu, MfSeparator, UIntPtr.Zero, string.Empty);
        AddItem(Exit, "退出");
        GetCursorPos(out var point);
        SetForegroundWindow(_source.Handle);
        var command = TrackPopupMenu(_menu, TpmRightButton | TpmReturnCmd, point.X, point.Y, 0, _source.Handle, IntPtr.Zero);
        PostMessage(_source.Handle, 0, IntPtr.Zero, IntPtr.Zero);
        if (command != 0) InvokeCommand(unchecked((int)command));
        DestroyMenu(_menu);
        _menu = IntPtr.Zero;
    }

    private void AddItem(int id, string text) => AppendMenu(_menu, MfString, (UIntPtr)id, text);

    private void InvokeCommand(int id)
    {
        switch (id)
        {
            case OpenConsole: _openConsole(); break;
            case Previous: _previous(); break;
            case TogglePlayback: _togglePlayback(); break;
            case Next: _next(); break;
            case Repeat: _repeat(); break;
            case SongList: _songList(); break;
            case LyricsManager: _lyricsManager(); break;
            case Exit: _exit(); break;
        }
    }

    private static string TrimTip(string value) => value.Length > 63 ? value[..63] : value;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public uint cbSize; public IntPtr hWnd; public uint uID; public uint uFlags;
        public uint uCallbackMessage; public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState; public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct MENUITEMINFO
    {
        public uint cbSize, fMask, fType, fState; public uint wID; public IntPtr hSubMenu, hbmpChecked, hbmpUnchecked, dwItemData, dwTypeData; public uint cch;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern bool Shell_NotifyIcon(uint message, ref NOTIFYICONDATA data);
    [DllImport("user32.dll")] private static extern IntPtr LoadIcon(IntPtr instance, IntPtr name);
    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool AppendMenu(IntPtr menu, uint flags, UIntPtr id, string text);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenu(IntPtr menu, uint flags, int x, int y, int reserved, IntPtr hwnd, IntPtr rect);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
