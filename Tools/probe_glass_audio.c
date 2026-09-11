#include "../AudioSampleBuffer/AudioSampleBuffer/RealtimeAnalyzerDSP.h"
#include "../AudioSampleBuffer/VisualEffects/Metal/GlassResonanceAudio.h"
#include <stdio.h>
#include <assert.h>
// Compile with the production DSP, then run from the repository root.
int main(void) {
    const float frequencies[]={100,900,6000};
    for(int k=0;k<3;k++) {
        AnalyzerDSPRef dsp=AnalyzerDSP_Create(2048,80,50,18000,44100);
        assert(dsp);
        GlassAudioState state={0}; float samples[2048],bands[80];
        for(int frame=0;frame<44;frame++) {
            for(int j=0;j<2048;j++) samples[j]=0.12f*sinf(2*M_PI*frequencies[k]*(frame*2048+j)/44100);
            AnalyzerDSP_ProcessChannelLegacyExact(dsp,samples,0,5,44100,bands);
            glassAudioStep(&state,bands,0,0,0,0,1.15,2048.0f/44100);
        }
        float response[]={state.low,state.mid,state.high};
        printf("%.0f Hz PCM -> actual legacy FFT -> low %.4f mid %.4f high %.4f\n",frequencies[k],response[0],response[1],response[2]);
        assert(response[k]>0.03f);
        assert(response[k]>response[(k+1)%3] && response[k]>response[(k+2)%3]);
        // Write the exact live envelope for the Metal preview probe.
        char path[256];snprintf(path,sizeof(path),"build/GlassResonancePreview/pcm-%d.bin",k);
        FILE *out=fopen(path,"wb");assert(out);assert(fwrite(&state,sizeof(state),1,out)==1);fclose(out);
        for(int frame=0;frame<120;frame++) {
            memset(samples,0,sizeof(samples));
            AnalyzerDSP_ProcessChannelLegacyExact(dsp,samples,0,5,44100,bands);
            glassAudioStep(&state,bands,0,0,0,0,1.15,2048.0f/44100);
        }
        assert(state.low<0.001 && state.mid<0.001 && state.high<0.001);
        AnalyzerDSP_Destroy(dsp);
    }
    puts("PASS: PCM frequency isolation and silence through production FFT + glass envelopes.");
}
