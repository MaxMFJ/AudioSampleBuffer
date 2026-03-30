//
//  AIColorConfiguration.m
//  AudioSampleBuffer
//

#import "AIColorConfiguration.h"

@implementation AIColorConfiguration

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 设置默认值
        _bpm = 120;
        _emotion = MusicEmotionEnergetic;
        _energy = 0.7;
        _danceability = 0.7;
        _valence = 0.7;
        
        _animationSpeed = 1.0;
        _brightnessMultiplier = 1.0;
        _triggerSensitivity = 1.0;
        _atmosphereIntensity = 0.45;
        _isLLMGenerated = NO;
        
        _cachedDate = [NSDate date];
    }
    return self;
}

+ (instancetype)configurationFromJSON:(NSDictionary *)json {
    AIColorConfiguration *config = [[AIColorConfiguration alloc] init];
    
    // 基本信息
    config.songName = json[@"songName"] ?: @"";
    config.artist = json[@"artist"] ?: @"";
    config.songIdentifier = json[@"songIdentifier"] ?: @"";
    
    // 分析数据
    NSDictionary *analysis = json[@"analysis"];
    if (analysis) {
        config.bpm = [analysis[@"bpm"] integerValue] ?: 120;
        config.energy = [analysis[@"energy"] floatValue] ?: 0.7;
        config.danceability = [analysis[@"danceability"] floatValue] ?: 0.7;
        config.valence = [analysis[@"valence"] floatValue] ?: 0.7;
        
        NSString *emotionStr = analysis[@"emotion"];
        if ([emotionStr isEqualToString:@"calm"]) {
            config.emotion = MusicEmotionCalm;
        } else if ([emotionStr isEqualToString:@"sad"]) {
            config.emotion = MusicEmotionSad;
        } else if ([emotionStr isEqualToString:@"happy"]) {
            config.emotion = MusicEmotionHappy;
        } else if ([emotionStr isEqualToString:@"energetic"]) {
            config.emotion = MusicEmotionEnergetic;
        } else if ([emotionStr isEqualToString:@"intense"]) {
            config.emotion = MusicEmotionIntense;
        }
    }

    id llmFlag = json[@"isLLMGenerated"];
    config.isLLMGenerated = llmFlag ? [llmFlag boolValue] : YES;
    
    // 颜色方案
    NSDictionary *colors = json[@"colors"];
    if (colors) {
        config.atmosphereColor = [self parseColorArray:colors[@"atmosphere"] defaultColor:simd_make_float3(1.0, 0.88, 0.72)];
        config.volumetricBeamColor = [self parseColorArray:colors[@"volumetricBeam"] defaultColor:simd_make_float3(1.0, 0.85, 0.65)];
        config.topLightArrayColor = [self parseColorArray:colors[@"topLightArray"] defaultColor:simd_make_float3(0.3, 0.6, 1.0)];
        config.laserFanBlueColor = [self parseColorArray:colors[@"laserFanBlue"] defaultColor:simd_make_float3(0.25, 0.55, 1.0)];
        config.laserFanGreenColor = [self parseColorArray:colors[@"laserFanGreen"] defaultColor:simd_make_float3(0.35, 1.0, 0.45)];
        config.rotatingBeamColor = [self parseColorArray:colors[@"rotatingBeam"] defaultColor:simd_make_float3(1.0, 0.4, 0.8)];
        config.rotatingBeamExtraColor = [self parseColorArray:colors[@"rotatingBeamExtra"] defaultColor:simd_make_float3(1.0, 0.5, 0.9)];
        config.edgeLightColor = [self parseColorArray:colors[@"edgeLight"] defaultColor:simd_make_float3(1.0, 0.75, 0.35)];
        config.coronaFilamentsColor = [self parseColorArray:colors[@"coronaFilaments"] defaultColor:simd_make_float3(0.9, 0.6, 0.8)];
        config.pulseRingColor = [self parseColorArray:colors[@"pulseRing"] defaultColor:simd_make_float3(0.8, 0.3, 1.0)];
        
        // 调试：打印 AI 返回的颜色
        NSLog(@"🎨 AI 颜色配置:");
        NSLog(@"   topLightArray: (%.2f, %.2f, %.2f)", config.topLightArrayColor.x, config.topLightArrayColor.y, config.topLightArrayColor.z);
        NSLog(@"   laserFanBlue: (%.2f, %.2f, %.2f)", config.laserFanBlueColor.x, config.laserFanBlueColor.y, config.laserFanBlueColor.z);
        NSLog(@"   laserFanGreen: (%.2f, %.2f, %.2f)", config.laserFanGreenColor.x, config.laserFanGreenColor.y, config.laserFanGreenColor.z);
        NSLog(@"   rotatingBeam: (%.2f, %.2f, %.2f)", config.rotatingBeamColor.x, config.rotatingBeamColor.y, config.rotatingBeamColor.z);
    } else {
        [config setDefaultColors];
    }
    
    // 动画参数
    NSDictionary *params = json[@"parameters"];
    if (params) {
        config.animationSpeed = [params[@"animationSpeed"] floatValue] ?: 1.0;
        config.brightnessMultiplier = [params[@"brightnessMultiplier"] floatValue] ?: 1.0;
        config.triggerSensitivity = [params[@"triggerSensitivity"] floatValue] ?: 1.0;
        config.atmosphereIntensity = [params[@"atmosphereIntensity"] floatValue] ?: 0.45;
    }
    
    return config;
}

- (NSDictionary *)toJSON {
    return @{
        @"songName": self.songName ?: @"",
        @"artist": self.artist ?: @"",
        @"songIdentifier": self.songIdentifier ?: @"",
        @"analysis": @{
            @"bpm": @(self.bpm),
            @"emotion": [self emotionToString:self.emotion],
            @"energy": @(self.energy),
            @"danceability": @(self.danceability),
            @"valence": @(self.valence)
        },
        @"colors": @{
            @"atmosphere": [self colorToArray:self.atmosphereColor],
            @"volumetricBeam": [self colorToArray:self.volumetricBeamColor],
            @"topLightArray": [self colorToArray:self.topLightArrayColor],
            @"laserFanBlue": [self colorToArray:self.laserFanBlueColor],
            @"laserFanGreen": [self colorToArray:self.laserFanGreenColor],
            @"rotatingBeam": [self colorToArray:self.rotatingBeamColor],
            @"rotatingBeamExtra": [self colorToArray:self.rotatingBeamExtraColor],
            @"edgeLight": [self colorToArray:self.edgeLightColor],
            @"coronaFilaments": [self colorToArray:self.coronaFilamentsColor],
            @"pulseRing": [self colorToArray:self.pulseRingColor]
        },
        @"parameters": @{
            @"animationSpeed": @(self.animationSpeed),
            @"brightnessMultiplier": @(self.brightnessMultiplier),
            @"triggerSensitivity": @(self.triggerSensitivity),
            @"atmosphereIntensity": @(self.atmosphereIntensity)
        },
        @"isLLMGenerated": @(self.isLLMGenerated),
        @"cachedDate": self.cachedDate
    };
}

+ (instancetype)defaultConfiguration {
    AIColorConfiguration *config = [[AIColorConfiguration alloc] init];
    [config setDefaultColors];
    return config;
}

+ (instancetype)configurationForEmotion:(MusicEmotion)emotion {
    AIColorConfiguration *config = [[AIColorConfiguration alloc] init];
    config.emotion = emotion;
    
    switch (emotion) {
        case MusicEmotionCalm:
            config.atmosphereColor = simd_make_float3(0.05, 0.06, 0.1);
            config.volumetricBeamColor = simd_make_float3(0.7, 0.8, 1.0);
            config.topLightArrayColor = simd_make_float3(0.4, 0.6, 1.0);
            config.laserFanBlueColor = simd_make_float3(0.4, 0.6, 1.0);
            config.laserFanGreenColor = simd_make_float3(0.5, 0.9, 0.7);
            config.rotatingBeamColor = simd_make_float3(0.6, 0.7, 1.0);
            config.rotatingBeamExtraColor = simd_make_float3(0.7, 0.8, 1.0);
            config.edgeLightColor = simd_make_float3(0.5, 0.7, 1.0);
            config.coronaFilamentsColor = simd_make_float3(0.6, 0.7, 0.9);
            config.pulseRingColor = simd_make_float3(0.5, 0.6, 1.0);
            config.animationSpeed = 0.7;
            break;
            
        case MusicEmotionSad:
            config.atmosphereColor = simd_make_float3(0.04, 0.04, 0.08);
            config.volumetricBeamColor = simd_make_float3(0.6, 0.6, 0.9);
            config.topLightArrayColor = simd_make_float3(0.3, 0.4, 0.8);
            config.laserFanBlueColor = simd_make_float3(0.3, 0.4, 0.8);
            config.laserFanGreenColor = simd_make_float3(0.4, 0.7, 0.6);
            config.rotatingBeamColor = simd_make_float3(0.5, 0.4, 0.9);
            config.rotatingBeamExtraColor = simd_make_float3(0.6, 0.5, 0.9);
            config.edgeLightColor = simd_make_float3(0.4, 0.5, 0.8);
            config.coronaFilamentsColor = simd_make_float3(0.5, 0.4, 0.7);
            config.pulseRingColor = simd_make_float3(0.5, 0.3, 0.8);
            config.animationSpeed = 0.6;
            config.brightnessMultiplier = 0.7;
            break;
            
        case MusicEmotionHappy:
            config.atmosphereColor = simd_make_float3(0.08, 0.07, 0.04);
            config.volumetricBeamColor = simd_make_float3(1.0, 0.9, 0.5);
            config.topLightArrayColor = simd_make_float3(0.3, 0.8, 1.0);
            config.laserFanBlueColor = simd_make_float3(0.3, 0.8, 1.0);
            config.laserFanGreenColor = simd_make_float3(0.5, 1.0, 0.3);
            config.rotatingBeamColor = simd_make_float3(1.0, 0.6, 0.3);
            config.rotatingBeamExtraColor = simd_make_float3(1.0, 0.8, 0.4);
            config.edgeLightColor = simd_make_float3(1.0, 0.85, 0.4);
            config.coronaFilamentsColor = simd_make_float3(1.0, 0.7, 0.5);
            config.pulseRingColor = simd_make_float3(1.0, 0.8, 0.3);
            config.animationSpeed = 1.2;
            config.brightnessMultiplier = 1.1;
            break;
            
        case MusicEmotionEnergetic:
            config.atmosphereColor = simd_make_float3(0.08, 0.05, 0.03);
            config.volumetricBeamColor = simd_make_float3(1.0, 0.7, 0.3);
            config.topLightArrayColor = simd_make_float3(0.2, 0.5, 1.0);
            config.laserFanBlueColor = simd_make_float3(0.2, 0.5, 1.0);
            config.laserFanGreenColor = simd_make_float3(0.3, 1.0, 0.5);
            config.rotatingBeamColor = simd_make_float3(1.0, 0.4, 0.8);
            config.rotatingBeamExtraColor = simd_make_float3(1.0, 0.5, 0.9);
            config.edgeLightColor = simd_make_float3(1.0, 0.75, 0.35);
            config.coronaFilamentsColor = simd_make_float3(0.9, 0.6, 0.8);
            config.pulseRingColor = simd_make_float3(0.8, 0.3, 1.0);
            config.animationSpeed = 1.4;
            config.triggerSensitivity = 1.2;
            break;
            
        case MusicEmotionIntense:
            config.atmosphereColor = simd_make_float3(0.1, 0.03, 0.03);
            config.volumetricBeamColor = simd_make_float3(1.0, 0.3, 0.3);
            config.topLightArrayColor = simd_make_float3(0.8, 0.2, 1.0);
            config.laserFanBlueColor = simd_make_float3(0.8, 0.2, 1.0);
            config.laserFanGreenColor = simd_make_float3(1.0, 0.2, 0.4);
            config.rotatingBeamColor = simd_make_float3(1.0, 0.2, 0.3);
            config.rotatingBeamExtraColor = simd_make_float3(1.0, 0.3, 0.5);
            config.edgeLightColor = simd_make_float3(1.0, 0.4, 0.2);
            config.coronaFilamentsColor = simd_make_float3(1.0, 0.3, 0.6);
            config.pulseRingColor = simd_make_float3(1.0, 0.2, 0.8);
            config.animationSpeed = 1.6;
            config.brightnessMultiplier = 1.2;
            config.triggerSensitivity = 1.3;
            break;
    }
    
    return config;
}

- (void)setDefaultColors {
    self.atmosphereColor = simd_make_float3(1.0, 0.88, 0.72);
    self.volumetricBeamColor = simd_make_float3(1.0, 0.85, 0.65);
    self.topLightArrayColor = simd_make_float3(0.3, 0.6, 1.0);
    self.laserFanBlueColor = simd_make_float3(0.25, 0.55, 1.0);
    self.laserFanGreenColor = simd_make_float3(0.35, 1.0, 0.45);
    self.rotatingBeamColor = simd_make_float3(1.0, 0.4, 0.8);
    self.rotatingBeamExtraColor = simd_make_float3(1.0, 0.5, 0.9);
    self.edgeLightColor = simd_make_float3(1.0, 0.75, 0.35);
    self.coronaFilamentsColor = simd_make_float3(0.9, 0.6, 0.8);
    self.pulseRingColor = simd_make_float3(0.8, 0.3, 1.0);
}

#pragma mark - Helper Methods

+ (simd_float3)parseColorArray:(NSArray *)array defaultColor:(simd_float3)defaultColor {
    if (array && array.count >= 3) {
        float r = [array[0] floatValue];
        float g = [array[1] floatValue];
        float b = [array[2] floatValue];
        return simd_make_float3(r, g, b);
    }
    return defaultColor;
}

- (NSArray *)colorToArray:(simd_float3)color {
    return @[@(color.x), @(color.y), @(color.z)];
}

- (NSString *)emotionToString:(MusicEmotion)emotion {
    switch (emotion) {
        case MusicEmotionCalm: return @"calm";
        case MusicEmotionSad: return @"sad";
        case MusicEmotionHappy: return @"happy";
        case MusicEmotionEnergetic: return @"energetic";
        case MusicEmotionIntense: return @"intense";
    }
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.songName forKey:@"songName"];
    [coder encodeObject:self.artist forKey:@"artist"];
    [coder encodeObject:self.songIdentifier forKey:@"songIdentifier"];
    [coder encodeInteger:self.bpm forKey:@"bpm"];
    [coder encodeInteger:self.emotion forKey:@"emotion"];
    [coder encodeFloat:self.energy forKey:@"energy"];
    [coder encodeFloat:self.danceability forKey:@"danceability"];
    [coder encodeFloat:self.valence forKey:@"valence"];
    [coder encodeObject:self.cachedDate forKey:@"cachedDate"];
    
    // 编码颜色（转换为 NSData）
    [coder encodeBytes:(const uint8_t *)&_atmosphereColor length:sizeof(simd_float3) forKey:@"atmosphereColor"];
    [coder encodeBytes:(const uint8_t *)&_volumetricBeamColor length:sizeof(simd_float3) forKey:@"volumetricBeamColor"];
    [coder encodeBytes:(const uint8_t *)&_topLightArrayColor length:sizeof(simd_float3) forKey:@"topLightArrayColor"];
    [coder encodeBytes:(const uint8_t *)&_laserFanBlueColor length:sizeof(simd_float3) forKey:@"laserFanBlueColor"];
    [coder encodeBytes:(const uint8_t *)&_laserFanGreenColor length:sizeof(simd_float3) forKey:@"laserFanGreenColor"];
    [coder encodeBytes:(const uint8_t *)&_rotatingBeamColor length:sizeof(simd_float3) forKey:@"rotatingBeamColor"];
    [coder encodeBytes:(const uint8_t *)&_rotatingBeamExtraColor length:sizeof(simd_float3) forKey:@"rotatingBeamExtraColor"];
    [coder encodeBytes:(const uint8_t *)&_edgeLightColor length:sizeof(simd_float3) forKey:@"edgeLightColor"];
    [coder encodeBytes:(const uint8_t *)&_coronaFilamentsColor length:sizeof(simd_float3) forKey:@"coronaFilamentsColor"];
    [coder encodeBytes:(const uint8_t *)&_pulseRingColor length:sizeof(simd_float3) forKey:@"pulseRingColor"];
    
    [coder encodeFloat:self.animationSpeed forKey:@"animationSpeed"];
    [coder encodeFloat:self.brightnessMultiplier forKey:@"brightnessMultiplier"];
    [coder encodeFloat:self.triggerSensitivity forKey:@"triggerSensitivity"];
    [coder encodeFloat:self.atmosphereIntensity forKey:@"atmosphereIntensity"];
    [coder encodeBool:self.isLLMGenerated forKey:@"isLLMGenerated"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _songName = [coder decodeObjectOfClass:[NSString class] forKey:@"songName"];
        _artist = [coder decodeObjectOfClass:[NSString class] forKey:@"artist"];
        _songIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"songIdentifier"];
        _bpm = [coder decodeIntegerForKey:@"bpm"];
        _emotion = [coder decodeIntegerForKey:@"emotion"];
        _energy = [coder decodeFloatForKey:@"energy"];
        _danceability = [coder decodeFloatForKey:@"danceability"];
        _valence = [coder decodeFloatForKey:@"valence"];
        _cachedDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"cachedDate"];
        
        // 解码颜色
        NSUInteger length;
        const uint8_t *bytes;
        
        bytes = [coder decodeBytesForKey:@"atmosphereColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_atmosphereColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"volumetricBeamColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_volumetricBeamColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"topLightArrayColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_topLightArrayColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"laserFanBlueColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_laserFanBlueColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"laserFanGreenColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_laserFanGreenColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"rotatingBeamColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_rotatingBeamColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"rotatingBeamExtraColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_rotatingBeamExtraColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"edgeLightColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_edgeLightColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"coronaFilamentsColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_coronaFilamentsColor, bytes, sizeof(simd_float3));
        
        bytes = [coder decodeBytesForKey:@"pulseRingColor" returnedLength:&length];
        if (bytes && length == sizeof(simd_float3)) memcpy(&_pulseRingColor, bytes, sizeof(simd_float3));
        
        _animationSpeed = [coder decodeFloatForKey:@"animationSpeed"];
        _brightnessMultiplier = [coder decodeFloatForKey:@"brightnessMultiplier"];
        _triggerSensitivity = [coder decodeFloatForKey:@"triggerSensitivity"];
        _atmosphereIntensity = [coder decodeFloatForKey:@"atmosphereIntensity"];
        _isLLMGenerated = [coder decodeBoolForKey:@"isLLMGenerated"];
    }
    return self;
}

@end
