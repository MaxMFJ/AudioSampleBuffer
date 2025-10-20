//
//  SpeexDSPBridge.mm
//  AudioSampleBuffer
//
//  SpeexDSP 音频处理桥接层实现
//

#import "SpeexDSPBridge.h"
#import "SpeexDSP/speex/speex_preprocess.h"
#import "SpeexDSP/speex/speex_echo.h"
#import "SpeexDSP/speex/speex_resampler.h"

#include <vector>
#include <Accelerate/Accelerate.h>

#pragma mark - SpeexDSP 预处理器实现

@interface SpeexPreprocessor ()
@property (nonatomic, assign) SpeexPreprocessState *preprocessState;
@property (nonatomic, assign) int frameSize;
@property (nonatomic, assign) int sampleRate;
@property (nonatomic, assign) std::vector<float> *floatBuffer;
@property (nonatomic, assign) std::vector<SInt16> *int16Buffer;
@property (nonatomic, assign) BOOL isInitialized;
@end

@implementation SpeexPreprocessor

- (instancetype)initWithFrameSize:(int)frameSize sampleRate:(int)sampleRate {
    self = [super init];
    if (self) {
        _frameSize = frameSize;
        _sampleRate = sampleRate;
        _floatBuffer = new std::vector<float>();
        _int16Buffer = new std::vector<SInt16>();
        
        _preprocessState = speex_preprocess_state_init(frameSize, sampleRate);
        if (!_preprocessState) {
            NSLog(@"❌ SpeexDSP 预处理器初始化失败");
            return nil;
        }
        
        // 默认禁用所有功能
        int zero = 0;
        speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_DENOISE, &zero);
        speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC, &zero);
        speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_VAD, &zero);
        
        _isInitialized = YES;
        
        NSLog(@"✅ SpeexPreprocessor 初始化成功 (帧: %d, 采样率: %d Hz)", frameSize, sampleRate);
    }
    return self;
}

- (void)dealloc {
    if (_preprocessState) {
        speex_preprocess_state_destroy(_preprocessState);
        _preprocessState = NULL;
    }
    if (_floatBuffer) {
        delete _floatBuffer;
        _floatBuffer = nullptr;
    }
    if (_int16Buffer) {
        delete _int16Buffer;
        _int16Buffer = nullptr;
    }
}

#pragma mark - 处理方法

- (int)processFrame:(float *)frame {
    if (!_isInitialized) return 0;
    
    // 转换为 SInt16（使用对称的转换系数）
    _int16Buffer->resize(_frameSize);
    for (int i = 0; i < _frameSize; i++) {
        float sample = fmaxf(-1.0f, fminf(1.0f, frame[i]));
        (*_int16Buffer)[i] = (SInt16)(sample * 32767.0f);
    }
    
    // 处理
    int vad = speex_preprocess_run(_preprocessState, (spx_int16_t *)_int16Buffer->data());
    
    // 转回 float（修复：使用32767.0f保持对称）
    for (int i = 0; i < _frameSize; i++) {
        frame[i] = (*_int16Buffer)[i] / 32767.0f;
    }
    
    return vad;
}

- (int)processInt16Frame:(SInt16 *)frame {
    if (!_isInitialized) return 0;
    return speex_preprocess_run(_preprocessState, (spx_int16_t *)frame);
}

- (float)processSamples:(SInt16 *)samples count:(NSUInteger)sampleCount {
    if (!_isInitialized || sampleCount == 0) return 0.0f;
    
    int totalVAD = 0;
    int frameCount = 0;
    
    // 🔧 修复杂音问题：处理完整帧
    for (NSUInteger i = 0; i < sampleCount; i += _frameSize) {
        NSUInteger remainingSamples = sampleCount - i;
        if (remainingSamples < _frameSize) {
            // ⚠️ 剩余样本不足一帧，使用零填充处理
            // 这样可以避免未处理样本与处理样本混合产生杂音
            _int16Buffer->resize(_frameSize);
            memcpy(_int16Buffer->data(), &samples[i], remainingSamples * sizeof(SInt16));
            // 零填充剩余部分
            memset(_int16Buffer->data() + remainingSamples, 0, (_frameSize - remainingSamples) * sizeof(SInt16));
            
            // 处理填充后的帧
            int vad = speex_preprocess_run(_preprocessState, (spx_int16_t *)_int16Buffer->data());
            
            // 只复制有效样本回去（忽略填充部分）
            memcpy(&samples[i], _int16Buffer->data(), remainingSamples * sizeof(SInt16));
            
            totalVAD += vad;
            frameCount++;
            break;
        }
        
        int vad = [self processInt16Frame:&samples[i]];
        totalVAD += vad;
        frameCount++;
    }
    
    return frameCount > 0 ? (float)totalVAD / frameCount : 0.0f;
}

#pragma mark - AGC 控制

- (void)setAGCEnabled:(BOOL)enabled {
    if (!_isInitialized) return;
    int agc = enabled ? 1 : 0;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC, &agc);
}

- (void)setAGCLevel:(int)level {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC_LEVEL, &level);
}

- (void)setAGCMaxGain:(int)maxGain {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC_MAX_GAIN, &maxGain);
}

- (void)setAGCIncrement:(int)increment {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC_INCREMENT, &increment);
}

- (void)setAGCDecrement:(int)decrement {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC_DECREMENT, &decrement);
}

#pragma mark - 噪声抑制控制

- (void)setDenoiseEnabled:(BOOL)enabled {
    if (!_isInitialized) return;
    int denoise = enabled ? 1 : 0;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_DENOISE, &denoise);
}

- (void)setNoiseSuppress:(int)suppress {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &suppress);
}

#pragma mark - VAD 控制

- (void)setVADEnabled:(BOOL)enabled {
    if (!_isInitialized) return;
    int vad = enabled ? 1 : 0;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_VAD, &vad);
}

- (void)setVADProbability:(float)prob {
    if (!_isInitialized) return;
    int prob_val = (int)(prob * 100);
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_PROB_START, &prob_val);
}

#pragma mark - 去混响控制

- (void)setDereverbEnabled:(BOOL)enabled {
    if (!_isInitialized) return;
    int dereverb = enabled ? 1 : 0;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_DEREVERB, &dereverb);
}

- (void)setDereverbLevel:(float)level {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_DEREVERB_LEVEL, &level);
}

- (void)setDereverbDecay:(float)decay {
    if (!_isInitialized) return;
    speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_DEREVERB_DECAY, &decay);
}

#pragma mark - 实用方法

- (void)reset {
    if (!_isInitialized) return;
    
    // SpeexDSP 没有 reset 函数，需要重新初始化
    if (_preprocessState) {
        speex_preprocess_state_destroy(_preprocessState);
    }
    
    _preprocessState = speex_preprocess_state_init(_frameSize, _sampleRate);
    if (_preprocessState) {
        // 重新设置默认参数
        int zero = 0;
        speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_DENOISE, &zero);
        speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_AGC, &zero);
        speex_preprocess_ctl(_preprocessState, SPEEX_PREPROCESS_SET_VAD, &zero);
    }
}

- (NSString *)getConfigInfo {
    return [NSString stringWithFormat:@"SpeexPreprocessor: 帧=%d, 采样率=%d Hz, 状态=%@",
            _frameSize, _sampleRate, _isInitialized ? @"OK" : @"未初始化"];
}

@end

#pragma mark - SpeexDSP 回声消除器实现

@interface SpeexEchoCanceller ()
@property (nonatomic, assign) SpeexEchoState *echoState;
@property (nonatomic, assign) int frameSize;
@property (nonatomic, assign) int filterLength;
@property (nonatomic, assign) int sampleRate;
@property (nonatomic, assign) BOOL isInitialized;
@end

@implementation SpeexEchoCanceller

- (instancetype)initWithFrameSize:(int)frameSize 
                     filterLength:(int)filterLength 
                       sampleRate:(int)sampleRate {
    self = [super init];
    if (self) {
        _frameSize = frameSize;
        _filterLength = filterLength;
        _sampleRate = sampleRate;
        
        int filter_length_samples = (filterLength * sampleRate) / 1000;
        _echoState = speex_echo_state_init(frameSize, filter_length_samples);
        if (!_echoState) {
            NSLog(@"❌ SpeexDSP 回声消除器初始化失败");
            return nil;
        }
        
        speex_echo_ctl(_echoState, SPEEX_ECHO_SET_SAMPLING_RATE, &sampleRate);
        _isInitialized = YES;
        
        NSLog(@"✅ SpeexEchoCanceller 初始化成功 (帧: %d, 滤波器: %dms)", frameSize, filterLength);
    }
    return self;
}

- (void)dealloc {
    if (_echoState) {
        speex_echo_state_destroy(_echoState);
        _echoState = NULL;
    }
}

- (void)processInputFrame:(SInt16 *)inputFrame 
                echoFrame:(SInt16 *)echoFrame 
              outputFrame:(SInt16 *)outputFrame {
    if (!_isInitialized) {
        memcpy(outputFrame, inputFrame, _frameSize * sizeof(SInt16));
        return;
    }
    
    speex_echo_cancellation(_echoState, 
                           (spx_int16_t *)inputFrame, 
                           (spx_int16_t *)echoFrame, 
                           (spx_int16_t *)outputFrame);
}

- (void)processFloatInputFrame:(float *)inputFrame 
                     echoFrame:(float *)echoFrame 
                   outputFrame:(float *)outputFrame {
    if (!_isInitialized) {
        memcpy(outputFrame, inputFrame, _frameSize * sizeof(float));
        return;
    }
    
    std::vector<SInt16> int16Input(_frameSize);
    std::vector<SInt16> int16Echo(_frameSize);
    std::vector<SInt16> int16Output(_frameSize);
    
    for (int i = 0; i < _frameSize; i++) {
        int16Input[i] = (SInt16)(inputFrame[i] * 32767.0f);
        int16Echo[i] = (SInt16)(echoFrame[i] * 32767.0f);
    }
    
    [self processInputFrame:int16Input.data() 
                  echoFrame:int16Echo.data() 
                outputFrame:int16Output.data()];
    
    // 🔧 修复：使用32767.0f保持对称，避免精度损失
    for (int i = 0; i < _frameSize; i++) {
        outputFrame[i] = int16Output[i] / 32767.0f;
    }
}

- (void)reset {
    if (_echoState) {
        speex_echo_state_reset(_echoState);
    }
}

@end

#pragma mark - SpeexDSP 重采样器实现

@interface SpeexResampler ()
@property (nonatomic, assign) SpeexResamplerState *resamplerState;
@property (nonatomic, assign) int channels;
@property (nonatomic, assign) int inputRate;
@property (nonatomic, assign) int outputRate;
@property (nonatomic, assign) int quality;
@property (nonatomic, assign) BOOL isInitialized;
@end

@implementation SpeexResampler

- (instancetype)initWithChannels:(int)channels 
                       inputRate:(int)inputRate 
                      outputRate:(int)outputRate 
                         quality:(int)quality {
    self = [super init];
    if (self) {
        _channels = channels;
        _inputRate = inputRate;
        _outputRate = outputRate;
        _quality = quality;
        
        int err;
        _resamplerState = speex_resampler_init(channels, inputRate, outputRate, quality, &err);
        if (err != RESAMPLER_ERR_SUCCESS) {
            NSLog(@"❌ SpeexDSP 重采样器初始化失败: %d", err);
            return nil;
        }
        
        _isInitialized = YES;
        NSLog(@"✅ SpeexResampler 初始化成功 (%dch, %d→%d Hz, 质量:%d)", 
              channels, inputRate, outputRate, quality);
    }
    return self;
}

- (void)dealloc {
    if (_resamplerState) {
        speex_resampler_destroy(_resamplerState);
        _resamplerState = NULL;
    }
}

- (int)processInt16Input:(SInt16 *)inputSamples 
             inputLength:(int)inputLength 
                  output:(SInt16 *)outputSamples 
         maxOutputLength:(int)maxOutputLength {
    if (!_isInitialized) return 0;
    
    spx_uint32_t in_len = inputLength;
    spx_uint32_t out_len = maxOutputLength;
    
    speex_resampler_process_interleaved_int(_resamplerState, 
                                            (spx_int16_t *)inputSamples, 
                                            &in_len, 
                                            (spx_int16_t *)outputSamples, 
                                            &out_len);
    
    return (int)out_len;
}

- (int)processFloatInput:(float *)inputSamples 
             inputLength:(int)inputLength 
                  output:(float *)outputSamples 
         maxOutputLength:(int)maxOutputLength {
    if (!_isInitialized) return 0;
    
    spx_uint32_t in_len = inputLength;
    spx_uint32_t out_len = maxOutputLength;
    
    speex_resampler_process_interleaved_float(_resamplerState, 
                                              inputSamples, 
                                              &in_len, 
                                              outputSamples, 
                                              &out_len);
    
    return (int)out_len;
}

- (void)setInputRate:(int)inputRate outputRate:(int)outputRate {
    _inputRate = inputRate;
    _outputRate = outputRate;
    if (_resamplerState) {
        speex_resampler_set_rate(_resamplerState, inputRate, outputRate);
    }
}

- (void)setQuality:(int)quality {
    _quality = quality;
    if (_resamplerState) {
        speex_resampler_set_quality(_resamplerState, quality);
    }
}

- (void)reset {
    if (_resamplerState) {
        speex_resampler_reset_mem(_resamplerState);
    }
}

- (void)skipZeros:(int)samples {
    if (_resamplerState) {
        speex_resampler_skip_zeros(_resamplerState);
    }
}

@end
