//
//  SpectrumReduce.metal
//  AudioSampleBuffer
//
//  GPU 频谱归约：将 FFT 幅度 (halfFFTSize) 经 A 计权后按频段取 max，输出 80 频段。
//  可与 CPU 端 FFT (vDSP) 配合：CPU 做 FFT + magnitude，上传 magnitudes 后由此 kernel 完成 A 权 + 频段归约。
//

#include <metal_stdlib>
using namespace metal;

constant int kFrequencyBands = 80;

/// 将 FFT 幅度按预计算的频段区间做 A 权后取每段最大值，并乘以 amplitudeLevel。
/// 每个 thread 处理一个频段。
///
/// @param magnitudes   [halfFFTSize] FFT 幅度（由 CPU vDSP 计算后上传）
/// @param aWeights     [halfFFTSize] A 计权系数（与 CPU 端 ComputeAWeights 一致）
/// @param bandStartBin [80] 每频段起始 bin 下标
/// @param bandEndBin   [80] 每频段结束 bin 下标（含）
/// @param bandSpectrum [80] 输出：每频段最大值 * amplitudeLevel
/// @param amplitudeLevel 幅度缩放
kernel void reduceMagnitudesToBands(
    device const float *magnitudes [[buffer(0)]],
    device const float *aWeights   [[buffer(1)]],
    device const int   *bandStartBin [[buffer(2)]],
    device const int   *bandEndBin   [[buffer(3)]],
    device float       *bandSpectrum [[buffer(4)]],
    constant float     &amplitudeLevel [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= (uint)kFrequencyBands) return;

    int startIdx = bandStartBin[id];
    int endIdx   = bandEndBin[id];
    float maxVal = 0.0f;

    for (int k = startIdx; k <= endIdx; k++) {
        float v = magnitudes[k] * aWeights[k];
        if (v > maxVal) maxVal = v;
    }

    bandSpectrum[id] = maxVal * amplitudeLevel;
}
