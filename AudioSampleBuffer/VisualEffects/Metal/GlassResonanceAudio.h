#ifndef GlassResonanceAudio_h
#define GlassResonanceAudio_h
#include <math.h>
#include <string.h>

// Independent of UIKit: the exact live envelope can be exercised by the probe.
typedef struct {
    float low, mid, high, energy, impact, strain, phase, impactAge;
    float bassHistory, transientHistory, refractory;
} GlassAudioState;
static inline float glassUnit(float x) { return isfinite(x) ? fminf(fmaxf(x, 0), 1) : 0; }
static inline float glassFollow(float a, float b, float dt, float attack, float release) {
    return a + (b-a) * (1-expf(-dt*(b>a ? attack : release)));
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
    s->refractory=fmaxf(0,s->refractory-dt);
    s->impact*=expf(-6.5f*dt); s->impactAge+=dt;
    float hit=glassUnit(fmaxf(onset,glassUnit(externalBeat)*gate));
    if(s->refractory<=0 && hit>0.10f) {
        s->impact=fmaxf(s->impact,hit); s->impactAge=0; s->refractory=0.14f;
    }
    s->bassHistory=glassFollow(s->bassHistory,low,dt,18,5);
    s->transientHistory=glassFollow(s->transientHistory,transient,dt,24,8);
    s->low=glassFollow(s->low,low,dt,12,3.4f);
    s->mid=glassFollow(s->mid,mid,dt,8,2.8f);
    s->high=glassFollow(s->high,high,dt,16,5);
    s->energy=glassFollow(s->energy,glassUnit(1-expf(-3.5f*rawEnergy*gain)),dt,9,3);
    float strain=glassUnit((s->energy-0.30f)*1.5f+high*0.25f+glassUnit(climax)*gate*0.3f);
    s->strain=glassFollow(s->strain,strain,dt,2.5f,1.4f);
    s->phase+=dt*(0.13f+0.22f*s->energy); // Integrated speed, never time * changing speed.
}
#endif
