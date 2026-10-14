using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace SoundDesk;

public partial class LyricsOverlayWindow : Window
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExToolWindow = 0x00000080;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern nint SetWindowLongPtr(nint window, int index, nint value);

    public LyricsOverlayWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => PositionOnPrimaryScreen();
        SourceInitialized += (_, _) => EnableClickThrough();
    }

    public void ShowFrame(string previous, string current, string next)
    {
        PreviousLine.Text = previous;
        CurrentLine.Text = current.Length == 0 ? "♪" : current;
        NextLine.Text = next;
    }

    private void PositionOnPrimaryScreen()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2;
        Top = workArea.Bottom - Height - 54;
    }

    private void EnableClickThrough()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var style = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        SetWindowLongPtr(handle, GwlExStyle, (nint)(style | WsExTransparent | WsExToolWindow));
    }
}
