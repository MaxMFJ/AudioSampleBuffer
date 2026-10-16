using System.Numerics;

namespace SoundDesk;

/// <summary>Translation of Mac RealtimeDSP's 4096 FFT, 80 bands and HPSS features.</summary>
public sealed class MacVisualAudioAnalyzer
{
    private const int Size = 4096, Half = Size / 2, BandCount = 80;
    private const int TimeMedian = 11, FrequencyMedian = 17, FluxRingSize = 3;
    private readonly Complex[] _fft = new Complex[Size];
    private readonly float[] _samples = new float[Size], _window = new float[Size];
    private readonly float[] _magnitudes = new float[Half], _power = new float[Half];
    private readonly float[] _weights = new float[Half], _weighted = new float[Half];
    private readonly float[] _harmonicPower = new float[Half], _percussiveMagnitude = new float[Half];
    private readonly float[] _residualPower = new float[Half];
    private readonly float[][] _history = CreateRing(TimeMedian), _fluxRing = CreateRing(FluxRingSize);
    private readonly float[] _scratch = new float[FrequencyMedian];
    private readonly float[] _rawBands = new float[BandCount], _bands = new float[BandCount];
    private readonly int[] _starts = new int[BandCount], _ends = new int[BandCount];
    private float _sampleRate;
    private int _write, _historyWrite, _historyValid, _fluxWrite, _fluxValid;

    public MacVisualAudioAnalyzer(float sampleRate) => Configure(sampleRate);

    public void Configure(float sampleRate)
    {
        sampleRate = Math.Max(8000, sampleRate);
        if (Math.Abs(sampleRate - _sampleRate) < .5f) return;
        _sampleRate = sampleRate;
        for (var i = 0; i < Size; i++)
            // vDSP_HANN_NORM, as used by the Mac analyzer.
            _window[i] = (float)(.816496580927726 * (1 - Math.Cos(2 * Math.PI * i / Size)));
        const double c1 = 12194.217 * 12194.217, c2 = 20.598997 * 20.598997;
        const double c3 = 107.65265 * 107.65265, c4 = 737.86223 * 737.86223;
        for (var k = 0; k < Half; k++)
        {
            var f = k * (double)sampleRate / Size;
            var f2 = f * f;
            var denominator = (f2 + c2) * Math.Sqrt((f2 + c3) * (f2 + c4)) * (f2 + c1);
            _weights[k] = denominator > 0 ? (float)(1.2589 * c1 * f2 * f2 / denominator) : 0;
        }
        for (var b = 0; b < BandCount; b++)
        {
            _starts[b] = Bin((float)(50 * Math.Pow(360, b / (double)BandCount)), 0);
            _ends[b] = Math.Max(_starts[b], Bin((float)(50 * Math.Pow(360, (b + 1d) / BandCount)), 0));
        }
        Array.Clear(_samples);
        Array.Clear(_bands);
        foreach (var row in _history) Array.Clear(row);
        foreach (var row in _fluxRing) Array.Clear(row);
        _write = _historyWrite = _historyValid = _fluxWrite = _fluxValid = 0;
    }

    public void Add(ReadOnlySpan<float> input, out VisualAudioSnapshot snapshot)
    {
        foreach (var sample in input)
        {
            _samples[_write] = float.IsFinite(sample) ? sample : 0;
            _write = (_write + 1) % Size;
        }
        Analyze(out snapshot);
    }

    private void Analyze(out VisualAudioSnapshot snapshot)
    {
        for (var i = 0; i < Size; i++)
            _fft[i] = new Complex(_samples[(_write + i) % Size] * _window[i], 0);
        Transform(_fft);
        for (var k = 0; k < Half; k++)
        {
            // vDSP_fft_zrip produces twice the standard complex FFT amplitude.
            var magnitude = (float)(_fft[k].Magnitude * 2 / Size);
            if (k == 0) magnitude *= .5f;
            _magnitudes[k] = magnitude;
            _weighted[k] = magnitude * _weights[k];
            _power[k] = magnitude * magnitude;
        }
        UpdateBands();
        UpdateSeparation();
        var subEnd = Bin(60);
        var sub = MeanMagnitude(_harmonicPower, Bin(20), subEnd);
        var bass = MeanMagnitude(_harmonicPower, subEnd + 1, Bin(120));
        var harmonicEnd = Bin(8000);
        var harmonic = MeanMagnitude(_harmonicPower, 1, harmonicEnd);
        var peak = 0f;
        for (var k = 1; k <= harmonicEnd; k++)
            peak = Math.Max(peak, MathF.Sqrt(_harmonicPower[k]));
        var ratio = harmonic > 1e-9f ? peak / harmonic : 0;
        var noise = Clamp(MeanMagnitude(_residualPower, 1, Half - 1) * 12);
        var flatness = Flatness();
        snapshot = new VisualAudioSnapshot(
            Mean(_bands, 0, 10) * 5, Mean(_bands, 20, 50) * 5, Mean(_bands, 50, 80) * 5,
            [Clamp(UpdateFlux() * 20), Clamp(noise * .52f + flatness * .78f), flatness,
                Clamp(harmonic * 5 + ratio * .06f)],
            [ratio, sub, bass, sub + bass]);
    }

    private void UpdateBands()
    {
        for (var b = 0; b < BandCount; b++)
        {
            var maximum = 0f;
            for (var k = _starts[b]; k <= _ends[b]; k++) maximum = Math.Max(maximum, _weighted[k]);
            _rawBands[b] = maximum * 5;
        }
        for (var b = 0; b < BandCount; b++)
        {
            var highlighted = b == 0 || b == BandCount - 1 ? _rawBands[b]
                : _rawBands[b - 1] * .25f + _rawBands[b] * .5f + _rawBands[b + 1] * .25f;
            _bands[b] = _bands[b] * .65f + highlighted * .35f;
        }
    }

    private void UpdateSeparation()
    {
        Array.Copy(_power, _history[_historyWrite], Half);
        _historyWrite = (_historyWrite + 1) % TimeMedian;
        _historyValid = Math.Min(TimeMedian, _historyValid + 1);
        for (var k = 0; k < Half; k++)
        {
            for (var t = 0; t < _historyValid; t++) _scratch[t] = _history[t][k];
            var h = Median(_historyValid);
            var lo = Math.Max(0, k - FrequencyMedian / 2);
            var hi = Math.Min(Half - 1, k + FrequencyMedian / 2);
            for (var j = lo; j <= hi; j++) _scratch[j - lo] = _power[j];
            var p = Median(hi - lo + 1);
            var hardH = 0f;
            var hardP = 0f;
            if (h >= 1.8f * p) hardH = 1;
            else if (p >= 1.8f * h) hardP = 1;
            var softH = (h + 1e-12f) / (h + p + 1e-12f);
            var maskH = .8f * hardH + .2f * softH;
            var maskP = .8f * hardP + .2f * (1 - softH);
            _harmonicPower[k] = maskH * _power[k];
            _percussiveMagnitude[k] = MathF.Sqrt(maskP * _power[k]);
            _residualPower[k] = Math.Max(0, 1 - maskH - maskP) * _power[k];
        }
    }

    private float UpdateFlux()
    {
        var slot = _fluxRing[_fluxWrite];
        for (var k = 0; k < Half; k++)
        {
            var maximum = 0f;
            for (var j = Math.Max(0, k - 3); j <= Math.Min(Half - 1, k + 3); j++)
                maximum = Math.Max(maximum, _percussiveMagnitude[j]);
            slot[k] = maximum;
        }
        var current = _fluxWrite;
        _fluxWrite = (_fluxWrite + 1) % FluxRingSize;
        _fluxValid = Math.Min(FluxRingSize, _fluxValid + 1);
        if (_fluxValid < FluxRingSize) return 0;
        var lag = _fluxRing[(current + FluxRingSize - 2) % FluxRingSize];
        var flux = 0f;
        for (var k = 0; k < Half; k++) flux += Math.Max(0, _percussiveMagnitude[k] - lag[k]);
        return flux / Half;
    }

    private float Flatness()
    {
        var lo = Bin(80);
        var hi = Bin(8000);
        if (hi <= lo) return 0;
        double logarithms = 0, sum = 0;
        for (var k = lo; k <= hi; k++)
        {
            var value = Math.Max(1e-9f, _magnitudes[k]);
            logarithms += Math.Log(value);
            sum += value;
        }
        var count = hi - lo + 1;
        return Clamp((float)(Math.Exp(logarithms / count) / (sum / count)));
    }

    private int Bin(float frequency, int minimum = 1) =>
        Math.Clamp((int)(frequency / (_sampleRate / Size) + .5f), minimum, Half - 1);
    private float Median(int count)
    {
        // Small insertion sort matches MedianSmall in the shared DSP source.
        for (var i = 1; i < count; i++)
        {
            var value = _scratch[i];
            var j = i - 1;
            while (j >= 0 && _scratch[j] > value) { _scratch[j + 1] = _scratch[j]; j--; }
            _scratch[j + 1] = value;
        }
        return _scratch[count / 2];
    }
    private static float MeanMagnitude(float[] power, int lo, int hi)
    {
        if (hi < lo) return 0;
        var sum = 0f;
        for (var k = lo; k <= hi; k++) sum += MathF.Sqrt(power[k]);
        return sum / (hi - lo + 1);
    }
    private static float Mean(float[] values, int lo, int end)
    {
        var sum = 0f;
        for (var i = lo; i < end; i++) sum += values[i];
        return sum / (end - lo);
    }
    private static float Clamp(float value) => Math.Clamp(value, 0, 1);
    private static float[][] CreateRing(int length) =>
        Enumerable.Range(0, length).Select(_ => new float[Half]).ToArray();

    private static void Transform(Complex[] values)
    {
        for (int i = 1, j = 0; i < Size; i++)
        {
            var bit = Size >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) (values[i], values[j]) = (values[j], values[i]);
        }
        for (var size = 2; size <= Size; size <<= 1)
        {
            var step = Complex.Exp(new Complex(0, -2 * Math.PI / size));
            for (var offset = 0; offset < Size; offset += size)
            {
                var rotation = Complex.One;
                for (var i = 0; i < size / 2; i++)
                {
                    var even = values[offset + i];
                    var odd = values[offset + i + size / 2] * rotation;
                    values[offset + i] = even + odd;
                    values[offset + i + size / 2] = even - odd;
                    rotation *= step;
                }
            }
        }
    }
}

public sealed record VisualAudioSnapshot(float Low, float Mid, float High, float[] Signals, float[] Texture);
