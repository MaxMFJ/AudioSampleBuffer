using System;

namespace SoundDesk;

/// <summary>CPU animation state shared by the native wallpaper effects.</summary>
internal sealed class WallpaperAnimationState
{
    public float[] Dynamics { get; } = new float[4];
    public float[] HiveWaves { get; } = new float[32];
    public float[] AnimationStarts { get; } = new float[] { -1, -1, -1, -1 };
    public float[] AnimationStrengths { get; } = new float[4];
    public float[] AnimationPeak { get; } = new float[] { -1, 0, 0, 0 };
    public float[] TyndallBands { get; } = new float[3];
    public float GuitarEnvelope { get; private set; }
    public float PianoEnvelope { get; private set; }

    private readonly float[] _previous = new float[2];
    private readonly float[] _activationDurations = { 12f, 14f, 15.384615f, 9f };
    private readonly float[] _thresholds = { .02f, .02f, .12f, .13f };
    private readonly float[] _minimums = { .08f, .13f, .20f, .20f };
    private float _lastTime = -1;
    private float _previousGuitar;
    private float _lastWaveTrigger;
    private int _nextWaveSlot;
    private int _nextPalette;

    public void Update(float time, float low, float mid, float high, float guitar,
                       float piano, float drums, bool playing)
    {
        float dt = _lastTime >= 0 ? Math.Clamp(time - _lastTime, 0, .12f) : 1f / 60f;
        _lastTime = time;
        float bass = Math.Clamp(low, 0, 1), drum = Math.Clamp(drums, 0, 1);
        float bassRise = Math.Max(bass - _previous[0], 0);
        float drumRise = Math.Max(drum - _previous[1], 0);
        float hit = Math.Max(bassRise * 5.5f, drumRise * 3.2f);
        float beat = Dynamics[0] * MathF.Exp(-1.8f * dt);
        float age = Dynamics[1] + dt;
        if (hit > .10f && age > .10f) { beat = Math.Max(beat, Math.Min(1, hit)); age = 0; }
        Dynamics[0] = beat; Dynamics[1] = age;
        _previous[0] = bass; _previous[1] = drum;

        if (!playing) { TyndallBands[0] = 0; TyndallBands[1] = 0; TyndallBands[2] = 0; }

        float coverFollow = 1 - MathF.Exp(-6f * dt);
        GuitarEnvelope += (Math.Clamp(guitar, 0, 1) - GuitarEnvelope) * coverFollow;
        PianoEnvelope += (Math.Clamp(piano, 0, 1) - PianoEnvelope) * coverFollow;
        float tyndallFollow = 1 - MathF.Exp(-(playing ? 14f : 15f) * dt);
        TyndallBands[0] += (Math.Clamp(low / 5, 0, 1) - TyndallBands[0]) * tyndallFollow;
        TyndallBands[1] += (Math.Clamp(mid / 5, 0, 1) - TyndallBands[1]) * tyndallFollow;
        TyndallBands[2] += (Math.Clamp(high / 5, 0, 1) - TyndallBands[2]) * tyndallFollow;
        Dynamics[2] = 0; // No separated guitar peak model is available on Windows.
        Dynamics[3] = PianoEnvelope;

        for (int i = 0; i < 8; i++)
        {
            int o = i * 4;
            if (HiveWaves[o + 1] > 0) { HiveWaves[o] += dt; if (HiveWaves[o] >= 2.8f) HiveWaves[o + 1] = 0; }
        }
        float g = Math.Clamp(guitar, 0, 1);
        if (g > .12f && g - _previousGuitar > .022f && (_lastWaveTrigger <= 0 || time - _lastWaveTrigger >= .38f))
        {
            int slot = _nextWaveSlot;
            for (int n = 0; n < 8; n++) { int candidate = (_nextWaveSlot + n) % 8; if (HiveWaves[candidate * 4 + 1] <= 0) { slot = candidate; break; } }
            int p = slot * 4; HiveWaves[p] = 0; HiveWaves[p + 1] = g; HiveWaves[p + 2] = _nextPalette++ % 4; HiveWaves[p + 3] = 0;
            _nextWaveSlot = (slot + 1) % 8; _lastWaveTrigger = time;
        }
        _previousGuitar = g;

        // Mac Tyndall requests isolated instruments; model-only activations stay off.
        float[] inputs = { TyndallBands[1], TyndallBands[2], 0, 0 };
        for (int i = 0; i < 4; i++) UpdateActivation(i, inputs[i], time, dt, playing);
        AnimationPeak[0] = -1; AnimationPeak[1] = 0; // Honest fallback without guitar peak.
    }

    private void UpdateActivation(int i, float input, float time, float dt, bool playing)
    {
        if (!playing) { AnimationStarts[i] = -1; AnimationStrengths[i] = 0; return; }
        bool active = AnimationStarts[i] >= 0 && time - AnimationStarts[i] < _activationDurations[i];
        if (!active && input >= _thresholds[i]) { AnimationStarts[i] = time; AnimationStrengths[i] = Math.Max(input, _minimums[i]); return; }
        if (!active) { AnimationStarts[i] = -1; AnimationStrengths[i] = 0; return; }
        float target = Math.Max(input, _minimums[i]);
        float rate = target > AnimationStrengths[i] ? 10 : 4;
        AnimationStrengths[i] += (target - AnimationStrengths[i]) * (1 - MathF.Exp(-rate * dt));
    }
}
