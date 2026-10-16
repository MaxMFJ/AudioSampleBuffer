using System.Diagnostics;
using System.IO;
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
    private WallpaperAnimationState _animation = new();
    private float _lastPlaybackTime = -1;
    private float _lastFrameTime = -1;
    public bool IsOperational => _handle != IntPtr.Zero && !_failed;
    private IntPtr _handle;
    private bool _hasArtwork;
    private bool _failed;
    private bool _presented;

    public static NativeWallpaperRenderer? TryCreate(IntPtr parent, int width, int height, out string error)
    {
        error = "";
        try
        {
            if (Native.GetApiVersion() != 4)
            {
                error = "WallpaperD3D.dll is outdated. Rebuild native/WallpaperD3D.vcxproj with Visual Studio MSBuild.";
                return null;
            }
            var shader = Path.Combine(AppContext.BaseDirectory, "WallpaperShaders.hlsl");
            var handle = Native.Create(parent, width, height, shader);
            if (handle != IntPtr.Zero)
            {
                WallpaperDiagnostics.Write($"Direct3D API 4 initialized: {width}x{height}; shader={shader}");
                return new NativeWallpaperRenderer { _handle = handle };
            }
            error = Native.GetLastError();
        }
        catch (DllNotFoundException) { error = "WallpaperD3D.dll is missing. Build with the Visual C++ toolset installed."; }
        catch (EntryPointNotFoundException exception) { error = $"WallpaperD3D.dll is outdated or incomplete. Rebuild the native project. {exception.Message}"; }
        catch (BadImageFormatException) { error = "WallpaperD3D.dll architecture does not match the player."; }
        return null;
    }

    public void SetVisible(bool visible)
    {
        if (_handle != IntPtr.Zero) Native.Show(_handle, visible && !_failed ? 1 : 0);
    }

    public bool Render(int effectIndex, float[] spectrum, VisualAudioSnapshot audio, bool playing, float playbackTime)
    {
        if (_handle == IntPtr.Zero || _failed) return false;
        _frame.Time = (float)_clock.Elapsed.TotalSeconds;
        _frame.EffectIndex = (uint)Math.Clamp(effectIndex, 0, 3);
        _frame.HasArtwork = _hasArtwork ? 1 : 0;
        var count = Math.Min(spectrum.Length, _frame.Bands.Length);
        Array.Clear(_frame.Bands);
        Array.Copy(spectrum, _frame.Bands, count);
        _frame.Low = audio.Low;
        _frame.Mid = audio.Mid;
        _frame.High = audio.High;
        Array.Copy(audio.Signals, _frame.DspFeatureSignals, 4);
        Array.Copy(audio.Texture, _frame.DspFeatureTexture, 4);
        _frame.Guitar = Math.Clamp(_frame.Mid * .55f + _frame.High * .85f, 0, 1);
        _frame.Piano = Math.Clamp(_frame.Mid * .55f, 0, 1);
        _frame.Drums = _frame.Low;
        if (!playing)
        {
            _frame.Low = _frame.Mid = _frame.High = _frame.Guitar = _frame.Piano = _frame.Drums = 0;
            Array.Clear(_frame.DspFeatureSignals);
            Array.Clear(_frame.DspFeatureTexture);
        }
        var dt = _lastFrameTime >= 0 ? Math.Max(0, _frame.Time - _lastFrameTime) : 0;
        if (_lastPlaybackTime >= 0 && Math.Abs(playbackTime - _lastPlaybackTime) > Math.Max(.35f, dt * 3))
            _animation = new WallpaperAnimationState();
        _lastFrameTime = _frame.Time;
        _lastPlaybackTime = playbackTime;
        // FFT instrument estimates remain a fallback until the model port is available.
        _frame.Viewport[3] = playing ? 1 : 0;
        _animation.Update(_frame.Time, _frame.Low, _frame.Mid, _frame.High,
            _frame.Guitar, _frame.Piano, _frame.Drums, playing);
        Array.Copy(_animation.Dynamics, _frame.Dynamics, 4);
        Array.Copy(_animation.HiveWaves, _frame.HiveWaves, 32);
        Array.Copy(_animation.AnimationStarts, _frame.AnimationStarts, 4);
        Array.Copy(_animation.AnimationStrengths, _frame.AnimationStrengths, 4);
        Array.Copy(_animation.AnimationPeak, _frame.AnimationPeak, 4);
        Array.Copy(_animation.TyndallBands, _frame.TyndallBands, 3);
        _frame.InstrumentEnvelopes[0] = _animation.GuitarEnvelope;
        _frame.InstrumentEnvelopes[1] = _animation.PianoEnvelope;
        _frame.InstrumentEnvelopes[2] = playbackTime;
        if (Native.Render(_handle, _frame) != 0)
        {
            if (!_presented) WallpaperDiagnostics.Write("First Direct3D frame submitted (culling disabled).");
            _presented = true;
            return true;
        }
        _failed = true;
        Native.Show(_handle, 0);
        WallpaperDiagnostics.Write($"Direct3D wallpaper render failed; switching to WPF: {Native.GetLastError()}");
        return false;
    }

    public void SetArtwork(ImageSource? image)
    {
        if (_handle == IntPtr.Zero) return;
        if (image is not BitmapSource source || source.PixelWidth <= 0 || source.PixelHeight <= 0)
        {
            _hasArtwork = false;
            _animation = new WallpaperAnimationState();
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
            WallpaperDiagnostics.Write(_hasArtwork
                ? $"Direct3D artwork uploaded: {converted.PixelWidth}x{converted.PixelHeight}; relief particles enabled."
                : $"Direct3D artwork upload failed: {Native.GetLastError()}");
        }
        finally { pin.Free(); }
    }

    public void Dispose()
    {
        if (_handle == IntPtr.Zero) return;
        Native.Destroy(_handle);
        _handle = IntPtr.Zero;
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
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] Viewport = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] Dynamics = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] AnimationStarts = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] AnimationStrengths = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] AnimationPeak = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] LaserGeometry = [12, .60f, 8, 12];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] LaserMotion = [7, .90f, .24f, .28f];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] LaserAppearance = [1, .12f, .90f, 1];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public float[] HiveWaves = new float[32];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] CoverRotation = [0, 0, 1, 0];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] CoverPointer = [-10, -10, 0, .22f];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] TyndallBands = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] InstrumentEnvelopes = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] DspFeatureSignals = new float[4];
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public float[] DspFeatureTexture = new float[4];
    }

    private static class Native
    {
        private const string Library = "WallpaperD3D.dll";

        [DllImport(Library, EntryPoint = "WallpaperD3D_GetApiVersion", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
        internal static extern uint GetApiVersion();

        [DllImport(Library, EntryPoint = "WallpaperD3D_Create", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        internal static extern IntPtr Create(IntPtr parent, int width, int height, string shaderPath);
        [DllImport(Library, EntryPoint = "WallpaperD3D_Destroy", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void Destroy(IntPtr handle);
        [DllImport(Library, EntryPoint = "WallpaperD3D_Show", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void Show(IntPtr handle, int visible);
        [DllImport(Library, EntryPoint = "WallpaperD3D_SetArtwork", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int SetArtwork(IntPtr handle, IntPtr pixels, int width, int height, int stride);
        [DllImport(Library, EntryPoint = "WallpaperD3D_Render", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int Render(IntPtr handle, [In] WallpaperFrame frame);
        [DllImport(Library, EntryPoint = "WallpaperD3D_GetLastError", ExactSpelling = true, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        private static extern int GetLastError(StringBuilder destination, int capacity);

        internal static string GetLastError()
        {
            var buffer = new StringBuilder(2048);
            GetLastError(buffer, buffer.Capacity);
            return buffer.ToString();
        }
    }
}
