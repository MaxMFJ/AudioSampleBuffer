using System.Numerics;
using NAudio.Wave;

namespace SoundDesk;

/// <summary>Reads Windows' shared output loopback and publishes a smoothed 48-band spectrum.</summary>
public sealed class AudioReactiveMonitor : IDisposable
{
    private const int FftSize = 1024;
    private const int BandCount = 48;
    private readonly float[] _samples = new float[FftSize];
    private readonly Complex[] _fft = new Complex[FftSize];
    private float[] _spectrum = new float[BandCount];
    private WasapiLoopbackCapture? _capture;
    private int _writeIndex;
    private int _samplesSinceFft;
    private bool _disposed;

    public float[] Spectrum => Volatile.Read(ref _spectrum);

    public bool Start()
    {
        if (_capture is not null) return true;
        try
        {
            var capture = new WasapiLoopbackCapture();
            capture.DataAvailable += OnDataAvailable;
            capture.RecordingStopped += OnRecordingStopped;
            capture.StartRecording();
            _capture = capture;
            return true;
        }
        catch
        {
            _capture?.Dispose();
            _capture = null;
            return false;
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        var capture = _capture;
        if (capture is null || e.BytesRecorded == 0) return;
        var format = capture.WaveFormat;
        var bytesPerSample = Math.Max(1, format.BitsPerSample / 8);
        var frameBytes = bytesPerSample * Math.Max(1, format.Channels);
        var frameCount = e.BytesRecorded / frameBytes;
        for (var frame = 0; frame < frameCount; frame++)
        {
            var mono = 0f;
            for (var channel = 0; channel < format.Channels; channel++)
            {
                var offset = frame * frameBytes + channel * bytesPerSample;
                mono += ReadSample(e.Buffer, offset, format.BitsPerSample);
            }
            mono /= Math.Max(1, format.Channels);
            _samples[_writeIndex] = Math.Clamp(mono, -1f, 1f);
            _writeIndex = (_writeIndex + 1) % FftSize;
            if (++_samplesSinceFft >= FftSize / 2)
            {
                _samplesSinceFft = 0;
                PublishSpectrum();
            }
        }
    }

    private static float ReadSample(byte[] buffer, int offset, int bitsPerSample)
    {
        return bitsPerSample switch
        {
            32 => BitConverter.Int32BitsToSingle(BitConverter.ToInt32(buffer, offset)),
            24 => ReadInt24(buffer, offset) / 8_388_608f,
            16 => BitConverter.ToInt16(buffer, offset) / 32_768f,
            8 => (buffer[offset] - 128) / 128f,
            _ => 0f
        };
    }

    private static int ReadInt24(byte[] buffer, int offset)
    {
        var value = buffer[offset] | buffer[offset + 1] << 8 | buffer[offset + 2] << 16;
        return (value & 0x800000) == 0 ? value : value | unchecked((int)0xFF000000);
    }

    private void PublishSpectrum()
    {
        for (var index = 0; index < FftSize; index++)
        {
            var sampleIndex = (_writeIndex + index) % FftSize;
            var window = 0.5 - 0.5 * Math.Cos(2 * Math.PI * index / (FftSize - 1));
            _fft[index] = new Complex(_samples[sampleIndex] * window, 0);
        }
        Transform(_fft);

        var bands = new float[BandCount];
        const int minBin = 2;
        const int maxBin = FftSize / 2;
        for (var band = 0; band < BandCount; band++)
        {
            var start = (int)Math.Pow(maxBin / (double)minBin, band / (double)BandCount) * minBin;
            var end = Math.Max(start + 1, (int)Math.Pow(maxBin / (double)minBin, (band + 1d) / BandCount) * minBin);
            end = Math.Min(end, maxBin);
            var peak = 0d;
            for (var bin = start; bin < end; bin++) peak = Math.Max(peak, _fft[bin].Magnitude);
            var amplitude = (float)Math.Clamp(peak * (3.5 / FftSize), 0, 1);
            var previous = _spectrum[band];
            bands[band] = amplitude > previous ? amplitude : Math.Max(amplitude, previous * 0.82f);
        }
        Volatile.Write(ref _spectrum, bands);
    }

    private static void Transform(Complex[] data)
    {
        var length = data.Length;
        for (int index = 1, reversed = 0; index < length; index++)
        {
            var bit = length >> 1;
            for (; (reversed & bit) != 0; bit >>= 1) reversed ^= bit;
            reversed ^= bit;
            if (index < reversed) (data[index], data[reversed]) = (data[reversed], data[index]);
        }
        for (var size = 2; size <= length; size <<= 1)
        {
            var angle = -2 * Math.PI / size;
            var step = new Complex(Math.Cos(angle), Math.Sin(angle));
            for (var offset = 0; offset < length; offset += size)
            {
                var rotation = Complex.One;
                var half = size >> 1;
                for (var index = 0; index < half; index++)
                {
                    var even = data[offset + index];
                    var odd = data[offset + index + half] * rotation;
                    data[offset + index] = even + odd;
                    data[offset + index + half] = even - odd;
                    rotation *= step;
                }
            }
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception is not null) Volatile.Write(ref _spectrum, new float[BandCount]);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        var capture = _capture;
        _capture = null;
        if (capture is null) return;
        capture.DataAvailable -= OnDataAvailable;
        capture.RecordingStopped -= OnRecordingStopped;
        try { capture.StopRecording(); } catch { }
        capture.Dispose();
    }
}
