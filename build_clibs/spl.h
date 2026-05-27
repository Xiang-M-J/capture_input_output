#include "signal_processing_library.h"


void InnoTalkSpl_AnalysisQMF(const int16_t* in_data,
                           int16_t* low_band,
                           int16_t* high_band,
                           int32_t* filter_state1,
                           int32_t* filter_state2);
void InnoTalkSpl_SynthesisQMF(const int16_t* low_band,
                            const int16_t* high_band,
                            int16_t* out_data,
                            int32_t* filter_state1,
                            int32_t* filter_state2);

void InnoTalk_rdft(int, int, float *, int *, float *);
void InnoTalk_cdft(int, int, float *, int *, float *);
void SignalIDFT(const float *in, short *out, const short FFTLen, const short FrameLen);
void SignalDFT(const short *in, float *out, const short FFTLen, const short FrameLen);
void stft1(const short* in, float* out, const short FFTLen, const short FrameLen);
void stft2(const short* in, float* out, const short FFTLen, const short FrameLen);
void istft(const float* in, short* out, const short FFTLen, const short FrameLen);