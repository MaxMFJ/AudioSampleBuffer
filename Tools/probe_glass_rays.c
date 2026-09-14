#include "../AudioSampleBuffer/VisualEffects/Metal/GlassResonanceAudio.h"
#include <assert.h>
#include <stdio.h>

// Regression probe using the exact production audio step; no UI or snapshots.
typedef struct {
    GlassAudioState audio;
    float time, lastStart, shortestGap, maxEnvelope;
    int events;
} Probe;

static void step(Probe *p, float low, float mid, float high, float section, float dt) {
    float bands[80];
    for (int i=0;i<80;i++) bands[i]=i<22 ? low : (i<53 ? mid : high);
    int wasActive=p->audio.rays.active;
    glassAudioStep(&p->audio,bands,0.9f,low,section,0.9f,1.35f,dt);
    p->time+=dt;
    if (!wasActive && p->audio.rays.active) {
        if (p->events>0) p->shortestGap=fminf(p->shortestGap,p->time-p->lastStart);
        p->lastStart=p->time;
        p->events++;
    }
    assert(isfinite(p->audio.rays.envelope));
    assert(p->audio.rays.envelope>=0 && p->audio.rays.envelope<=1);
    p->maxEnvelope=fmaxf(p->maxEnvelope,p->audio.rays.envelope);
}

static void hold(Probe *p,float seconds,float low,float mid,float high,float section,int fps) {
    for (int i=0;i<(int)lroundf(seconds*fps);i++) step(p,low,mid,high,section,1.0f/fps);
}

int main(void) {
    const int rates[]={24,30,60};
    for (int r=0;r<3;r++) {
        int fps=rates[r];
        Probe quiet={0}, ordinary={0}, bass={0}, hats={0}, below={0}, sustained={0}, hysteresis={0};
        hold(&quiet,20,0,0,0,1,fps);
        hold(&ordinary,30,0.018f,0.018f,0.018f,0,fps);
        hold(&bass,20,0.85f,0.025f,0.025f,1,fps);
        hold(&below,20,0.025f,0.025f,0.050f,1,fps);
        assert(quiet.events==0 && ordinary.events==0 && bass.events==0 && below.events==0);
        // Short high-band hats at 120 / 180 BPM must not satisfy the hold time.
        for (int i=0;i<fps*30;i++) {
            float t=(float)i/fps;
            float period=t<15 ? 0.5f : 1.0f/3.0f;
            float high=fmodf(t,period)<0.07f ? 0.12f : 0.012f;
            step(&hats,0.018f,0.018f,high,1,1.0f/fps);
        }
        assert(hats.events==0);

        // Sustained treble stays visible for the whole high-energy passage.
        hold(&sustained,8,0.025f,0.035f,0.070f,0,fps);
        assert(sustained.events==1 && sustained.audio.rays.active);
        assert(sustained.maxEnvelope>0.65f);
        float ageBefore=sustained.audio.rays.age;
        hold(&sustained,4,0.025f,0.035f,0.070f,1,fps);
        assert(sustained.audio.rays.active && sustained.audio.rays.envelope>0.65f);
        assert(sustained.audio.rays.age>ageBefore+3.8f);

        // Separate enter/exit thresholds prevent chatter near the boundary.
        hold(&hysteresis,2,0.02f,0.03f,0.065f,0,fps);
        assert(hysteresis.audio.rays.active);
        hold(&hysteresis,3,0.02f,0.03f,0.045f,0,fps);
        assert(hysteresis.audio.rays.active);
        hold(&hysteresis,3,0.02f,0.03f,0.025f,0,fps);
        assert(!hysteresis.audio.rays.active && hysteresis.audio.rays.envelope<0.08f);

        printf("%d fps PASS: high-band threshold, hat rejection, sustained rays and hysteresis\n",fps);
    }
    Probe invalid={0};
    step(&invalid,NAN,INFINITY,-1,NAN,1.0f/30);
    assert(invalid.events==0);
    puts("PASS: production continuous treble ray gate and nonfinite input.");
    return 0;
}
