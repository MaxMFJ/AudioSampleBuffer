#ifndef GlassResonanceAudio_h
#define GlassResonanceAudio_h
#include <math.h>
#include <string.h>

// Independent of UIKit: the exact live envelope can be exercised by the probe.
typedef struct {
    float fast, floor, elapsed, candidateAge, lowAge, cooldown;
    float age, strength, envelope;
    int latched, active;
} GlassRayState;
typedef struct {
    float low, mid, high, energy, impact, strain, phase, impactAge;
    float bassHistory, transientHistory, refractory, kick;
    float kickAmp, kickClock, quietAge, climax, climaxFloor;
    GlassRayState rays;
} GlassAudioState;
static inline float glassUnit(float x) { return isfinite(x) ? fminf(fmaxf(x, 0), 1) : 0; }
static inline float glassFollow(float a, float b, float dt, float attack, float release) {
    return a + (b-a) * (1-expf(-dt*(b>a ? attack : release)));
}
static inline float glassSmooth(float e0, float e1, float x) {
    float t=glassUnit((x-e0)/fmaxf(e1-e0,1e-5f));
    return t*t*(3.0f-2.0f*t);
}

// Star Vortex keeps its flare layers visible while the high band stays above
// threshold. Use the same continuous response here, with hysteresis and a short
// confirmation window so isolated hats do not flash the whole screen.
static inline void glassRayStep(GlassRayState *s, float high, float section, float dt) {
    dt=isfinite(dt) ? fminf(fmaxf(dt,0),0.1f) : 0;
    high=glassUnit(high);
    section=glassUnit(section);
    s->elapsed+=dt;
    s->fast=glassFollow(s->fast,high,dt,10.0f,3.2f);

    const float enterHigh=0.055f;
    const float exitHigh=0.040f;
    if (!s->active) {
        // Confirmation uses the current band value rather than the follower;
        // repeated short hi-hats cannot accumulate into a false sustained hit.
        s->candidateAge=high>=enterHigh ? s->candidateAge+dt : 0;
        if (s->candidateAge>=0.20f) {
            s->active=1;
            s->candidateAge=0;
            s->age=0;
        }
    } else if (s->fast<exitHigh) {
        s->active=0;
    }

    // Star Vortex starts its high response near 0.08. The player path uses a
    // lower amplitude scale than the recorder, so 0.045–0.13 is equivalent in
    // this live feed. The square root keeps the first visible layer readable.
    float highResponse=sqrtf(glassSmooth(0.045f,0.13f,s->fast));
    float sectionBoost=1.0f+glassSmooth(0.24f,0.66f,section)*0.16f;
    float target=s->active ? glassUnit((0.56f+highResponse*0.44f)*sectionBoost) : 0;
    s->strength=target;
    s->envelope=glassFollow(s->envelope,target,dt,5.8f,1.35f);
    if (s->active || s->envelope>0.01f) s->age+=dt;
    else s->age=0;
}
static inline void glassAudioStep(GlassAudioState *s, const float bands[80],
                                  float transient, float subBass, float climax,
                                  float externalBeat, float sensitivity, float dt) {
    dt = fminf(fmaxf(dt, 0), 0.1f);
    float low=0, mid=0, high=0;
    // Legacy analyzer: 80 logarithmic bands from 50 Hz to 18 kHz.
    for (int i=0; i<80; i++) {
        float v=glassUnit(bands[i]);
        if (i<22) low+=v*v; else if(i<53) mid+=v*v; else high+=v*v;
    }
    low=sqrtf(low/22); mid=sqrtf(mid/31); high=sqrtf(high/27);
    float rawEnergy=low*0.45f+mid*0.35f+high*0.20f;
    float rawLow=low, rawMid=mid, rawHigh=high;
    // Stale analysis / AI callbacks cannot animate an absent audio stream.
    float gate=glassUnit((rawEnergy-0.003f)*65);
    float gain=fminf(fmaxf(sensitivity,0.25f),2.5f);
    // The legacy FFT is A-weighted and quiet recordings often occupy < 0.1.
    // A fixed soft knee reveals these dynamics without per-song normalization
    // pumping up silence or destroying loud/soft contrast.
    low=glassUnit(1-expf(-3.5f*fmaxf(low,glassUnit(subBass)*gate*0.6f)*gain));
    mid=glassUnit(1-expf(-3.5f*mid*gain)); high=glassUnit(1-expf(-3.5f*high*gain));
    transient=glassUnit(transient)*gate;
    float onset=fmaxf(0,low-s->bassHistory)*3.4f+
                fmaxf(0,transient-s->transientHistory)*0.7f;
    float hit=glassUnit(fmaxf(onset,glassUnit(externalBeat)*gate));
    float wasQuiet=s->quietAge;
    if (hit>0.08f) s->quietAge=0; else s->quietAge+=dt;
    s->impactAge+=dt;
    const float kickDuration=0.42f;
    const float kickGap=0.10f;
    if (s->kickAmp>0.001f) {
        // One-shot whoosh. Later beats are ignored until this envelope returns to rest.
        s->kickClock+=dt;
        if (s->kickClock>=kickDuration) {
            s->kickAmp=0; s->kick=0; s->kickClock=0; s->impact=0;
        } else {
            float t=s->kickClock/kickDuration;
            float env=0.5f-0.5f*cosf(6.2831853f*t); // smooth 0→1→0, no restack
            s->kick=s->kickAmp*env;
            s->impact=s->kick;
        }
    } else {
        s->kick=0; s->impact*=expf(-6.5f*dt);
        // Gap detection: only arm after the previous whoosh and a quiet interval.
        if (hit>0.10f && wasQuiet>=kickGap) {
            s->kickAmp=hit; s->kickClock=0; s->kick=0;
            s->impact=0; s->impactAge=0;
        }
    }
    s->bassHistory=glassFollow(s->bassHistory,low,dt,18,5);
    s->transientHistory=glassFollow(s->transientHistory,transient,dt,24,8);
    s->low=glassFollow(s->low,low,dt,12,3.4f);
    s->mid=glassFollow(s->mid,mid,dt,8,2.8f);
    s->high=glassFollow(s->high,high,dt,16,5);
    s->energy=glassFollow(s->energy,glassUnit(1-expf(-3.5f*rawEnergy*gain)),dt,9,3);
    float strain=glassUnit((s->energy-0.30f)*1.5f+high*0.25f+glassUnit(climax)*gate*0.3f);
    s->strain=glassFollow(s->strain,strain,dt,2.5f,1.4f);
    // Match Cyberpunk's boosted band averages. Absolute RMS thresholds
    // either never fire or stay on; this scale is what actually plays in-app.
    float bassA=fminf(fmaxf(rawLow*1.8f,0),1.5f);
    float midA=fminf(fmaxf(rawMid*1.9f,0),1.5f);
    float trebleA=fminf(fmaxf(rawHigh*1.6f,0),1.5f);
    float peakA=fmaxf(bassA,fmaxf(midA,trebleA));
    float meanA=(bassA+midA+trebleA)*(1.0f/3.0f);
    if (s->climaxFloor<0.02f) s->climaxFloor=peakA;
    s->climaxFloor=glassFollow(s->climaxFloor,peakA,dt,0.42f,0.42f);
    float lift=(peakA-s->climaxFloor)/fmaxf(s->climaxFloor,0.05f);
    float absTarget=glassSmooth(0.16f,0.34f,peakA);
    float meanTarget=glassSmooth(0.14f,0.32f,meanA);
    float relTarget=glassSmooth(0.18f,0.55f,lift);
    float section=glassUnit(climax)*gate;
    float climaxTarget=fmaxf(absTarget,fmaxf(meanTarget,fmaxf(relTarget,section)));
    s->climax=glassFollow(s->climax,climaxTarget,dt,5.5f,0.90f);
    // Rays follow sustained raw treble, matching Star Vortex's direct high-band
    // response. Continuous material deformation still uses the soft-knee bands.
    glassRayStep(&s->rays,rawHigh,section,dt);
    s->phase+=dt*(0.12f+0.18f*s->energy+1.55f*s->kick+0.12f*s->low+0.10f*s->climax);
}
#endif
