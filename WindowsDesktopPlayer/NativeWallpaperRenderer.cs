using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SoundDesk;

/// <summary>Thin managed bridge to the native Direct3D 11 wallpaper renderer.</summary>
internal sealed class NativeWallpaperRenderer : IDisposable
{
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly WallpaperFrame _frame = new();
    private IntPtr _handle;
    private bool _hasArtwork;

    public static NativeWallpaperRenderer? TryCreate(IntPtr parent, int width, int height, out string error)
    {
        error = "";
        try
        {
            var shader = Path.Combine(AppContext.BaseDirectory, "WallpaperShaders.hlsl");
            var handle = Native.Create(parent, width, height, shader);
            if (handle != IntPtr.Zero) return new NativeWallpaperRenderer { _handle = handle };
            error = Native.GetLastError();
        }
        catch (DllNotFoundException) { error = "WallpaperD3D.dll is missing. Build with the Visual C++ toolset installed."; }
        catch (EntryPointNotFoundException exception) { error = exception.Message; }
        catch (BadImageFormatException) { error = "WallpaperD3D.dll architecture does not match the player."; }
        return null;
    }

    public void SetVisible(bool visible)
    {
        if (_handle != IntPtr.Zero) Native.Show(_handle, visible ? 1 : 0);
    }

    public void Render(int effectIndex, float[] spectrum)
    {
        if (_handle == IntPtr.Zero) return;
        _frame.Time = (float)_clock.Elapsed.TotalSeconds;
        _frame.EffectIndex = (uint)Math.Clamp(effectIndex, 0, 3);
        _frame.HasArtwork = _hasArtwork ? 1 : 0;
        var count = Math.Min(spectrum.Length, _frame.Bands.Length);
        Array.Copy(spectrum, _frame.Bands, count);
        _frame.Low = Average(spectrum, 0, 8);
        _frame.Mid = Average(spectrum, 8, 16);
        _frame.High = Average(spectrum, 24, Math.Max(0, spectrum.Length - 24));
        _frame.Guitar = Math.Clamp(_frame.High * 0.78f, 0, 1);
        _frame.Piano = Math.Clamp(_frame.Mid * 0.72f, 0, 1);
        _frame.Drums = Math.Clamp(_frame.Low * 0.92f, 0, 1);
        Native.Render(_handle, _frame);
    }

    public void SetArtwork(ImageSource? image)
    {
        if (_handle == IntPtr.Zero) return;
        if (image is not BitmapSource source || source.PixelWidth <= 0 || source.PixelHeight <= 0)
        {
            _hasArtwork = false;
            Native.SetArtwork(_handle, IntPtr.Zero, 0, 0, 0);
            return;
        }
        var converted = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);
        var pin = GCHandle.Alloc(pixels, GCHandleType.Pinned);
        try
        {
            _hasArtwork = Native.SetArtwork(_handle, pin.AddrOfPinnedObject(), converted.PixelWidth, converted.PixelHeight, stride) != 0;
        }
        finally { pin.Free(); }
    }

    public void Dispose()
    {
        if (_handle == IntPtr.Zero) return;
        Native.Destroy(_handle);
        _handle = IntPtr.Zero;
    }

    private static float Average(float[] values, int start, int count)
    {
        if (count <= 0 || values.Length <= start) return 0;
        var end = Math.Min(values.Length, start + count);
        var total = 0f;
        for (var index = start; index < end; index++) total += values[index];
        return total / (end - start);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private sealed class WallpaperFrame
    {
        public float Time;
        public float Low;
        public float Mid;
        public float High;
        public float Guitar;
        public float Piano;
        public float Drums;
        public float Aspect = (float)(SystemParameters.VirtualScreenWidth / Math.Max(1, SystemParameters.VirtualScreenHeight));
        public uint EffectIndex;
        public float HasArtwork;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2)] public float[] Padding = new float[2];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)] public float[] Bands = new float[128];
    }

    private static class Native
    {
        private const string Library = "WallpaperD3D.dll";

        [DllImport(Library, EntryPoint = "WallpaperD3D_Create", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        internal static extern IntPtr Create(IntPtr parent, int width, int height, string shaderPath);
        [DllImport(Library, EntryPoint = "WallpaperD3D_Destroy", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void Destroy(IntPtr handle);
        [DllImport(Library, EntryPoint = "WallpaperD3D_Show", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void Show(IntPtr handle, int visible);
        [DllImport(Library, EntryPoint = "WallpaperD3D_SetArtwork", CallingConvention = CallingConvention.Cdecl)]
        internal static extern int SetArtwork(IntPtr handle, IntPtr pixels, int width, int height, int stride);
        [DllImport(Library, EntryPoint = "WallpaperD3D_Render", CallingConvention = CallingConvention.Cdecl)]
        internal static extern void Render(IntPtr handle, [In] WallpaperFrame frame);
        [DllImport(Library, EntryPoint = "WallpaperD3D_GetLastError", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        private static extern int GetLastError(StringBuilder destination, int capacity);

        internal static string GetLastError()
        {
            var buffer = new StringBuilder(2048);
            GetLastError(buffer, buffer.Capacity);
            return buffer.ToString();
        }
    }
}
