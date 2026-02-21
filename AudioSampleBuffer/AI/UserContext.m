//
//  UserContext.m
//  AudioSampleBuffer
//

#import "UserContext.h"

@implementation UserContext

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)currentContext {
    UserContext *context = [[UserContext alloc] init];
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitWeekday)
                                               fromDate:[NSDate date]];
    
    context.hourOfDay = components.hour;
    context.isWeekend = (components.weekday == 1 || components.weekday == 7); // 周日=1, 周六=7
    context.usageScene = [UserContext usageSceneForHour:components.hour];
    context.recentListeningEnergy = 0.5;
    context.lastManualEffectChoice = nil;
    context.sessionDuration = 0;
    context.todayPlayCount = 0;
    
    return context;
}

+ (UsageScene)usageSceneForHour:(NSInteger)hour {
    if (hour >= 6 && hour < 9) {
        return UsageSceneMorning;
    } else if (hour >= 9 && hour < 18) {
        return UsageSceneDaytime;
    } else if (hour >= 18 && hour < 21) {
        return UsageSceneEvening;
    } else if (hour >= 21 && hour < 24) {
        return UsageSceneNight;
    } else {
        return UsageSceneLateNight;
    }
}

+ (NSString *)nameForScene:(UsageScene)scene {
    switch (scene) {
        case UsageSceneUnknown: return @"未知";
        case UsageSceneMorning: return @"早晨";
        case UsageSceneDaytime: return @"白天";
        case UsageSceneEvening: return @"傍晚";
        case UsageSceneNight: return @"夜晚";
        case UsageSceneLateNight: return @"深夜";
    }
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.hourOfDay forKey:@"hourOfDay"];
    [coder encodeBool:self.isWeekend forKey:@"isWeekend"];
    [coder encodeInteger:self.usageScene forKey:@"usageScene"];
    [coder encodeFloat:self.recentListeningEnergy forKey:@"recentListeningEnergy"];
    [coder encodeObject:self.lastManualEffectChoice forKey:@"lastManualEffectChoice"];
    [coder encodeDouble:self.sessionDuration forKey:@"sessionDuration"];
    [coder encodeInteger:self.todayPlayCount forKey:@"todayPlayCount"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _hourOfDay = [coder decodeIntegerForKey:@"hourOfDay"];
        _isWeekend = [coder decodeBoolForKey:@"isWeekend"];
        _usageScene = [coder decodeIntegerForKey:@"usageScene"];
        _recentListeningEnergy = [coder decodeFloatForKey:@"recentListeningEnergy"];
        _lastManualEffectChoice = [coder decodeObjectOfClass:[NSString class] forKey:@"lastManualEffectChoice"];
        _sessionDuration = [coder decodeDoubleForKey:@"sessionDuration"];
        _todayPlayCount = [coder decodeIntegerForKey:@"todayPlayCount"];
    }
    return self;
}

@end
