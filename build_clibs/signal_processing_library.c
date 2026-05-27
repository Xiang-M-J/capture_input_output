#include "signal_processing_library.h"

#include <math.h>
#include "stdio.h"
// Number of samples in a low/high-band frame.
enum
{
    kBandFrameLength = 64
};

#define PI 3.14159265358979

int cofip[8] = { 32, 32, 0, 64, 32, 96, 0, 0 };
float cofwfft[64] = { 1.00000000f, 0.00000000f, 0.707106769f, 0.707106769f, 0.923879504f, 0.382683456f, 0.382683456f, 0.923879504f, 0.980785251f, 0.195090324f, 0.555570245f, 0.831469595f, 0.831469595f, 0.555570245f, 0.195090324f, 0.980785251f, 0.995184720f, 0.0980171412f, 0.634393334f, 0.773010433f, 0.881921232f, 0.471396744f, 0.290284663f, 0.956940353f, 0.956940353f, 0.290284663f, 0.471396744f, 0.881921232f, 0.773010433f, 0.634393334f, 0.0980171412f, 0.995184720f, 0.707106769f, 0.499397725f, 0.497592360f, 0.494588256f, 0.490392625f, 0.485015631f, 0.478470176f, 0.470772028f, 0.461939752f, 0.451994658f, 0.440960616f, 0.428864300f, 0.415734798f, 0.401603758f, 0.386505216f, 0.370475560f, 0.353553385f, 0.335779488f, 0.317196667f, 0.297849655f, 0.277785122f, 0.257051378f, 0.235698372f, 0.213777542f, 0.191341728f, 0.168444932f, 0.145142332f, 0.121490099f, 0.0975451618f, 0.0733652338f, 0.0490085706f, 0.0245338380f };


// QMF filter coefficients in Q16.
static const uint16_t InnoTalkSpl_kAllPassFilter1[3] = {6418, 36982, 57261};
static const uint16_t InnoTalkSpl_kAllPassFilter2[3] = {21333, 49062, 63010};

void InnoTalkSpl_AllPassQMF(int32_t* in_data, int16_t data_length,
                          int32_t* out_data, const uint16_t* filter_coefficients,
                          int32_t* filter_state)
{
    // The procedure is to filter the input with three first order all pass filters
    // (cascade operations).
    //
    //         a_3 + q^-1    a_2 + q^-1    a_1 + q^-1
    // y[n] =  -----------   -----------   -----------   x[n]
    //         1 + a_3q^-1   1 + a_2q^-1   1 + a_1q^-1
    //
    // The input vector |filter_coefficients| includes these three filter coefficients.
    // The filter state contains the in_data state, in_data[-1], followed by
    // the out_data state, out_data[-1]. This is repeated for each cascade.
    // The first cascade filter will filter the |in_data| and store the output in
    // |out_data|. The second will the take the |out_data| as input and make an
    // intermediate storage in |in_data|, to save memory. The third, and final, cascade
    // filter operation takes the |in_data| (which is the output from the previous cascade
    // filter) and store the output in |out_data|.
    // Note that the input vector values are changed during the process.
    int16_t k;
    int32_t diff;
    // First all-pass cascade; filter from in_data to out_data.

    // Let y_i[n] indicate the output of cascade filter i (with filter coefficient a_i) at
    // vector position n. Then the final output will be y[n] = y_3[n]

    // First loop, use the states stored in memory.
    // "diff" should be safe from wrap around since max values are 2^25
    diff = INNOTALK_SPL_SUB_SAT_W32(in_data[0], filter_state[1]); // = (x[0] - y_1[-1])
    // y_1[0] =  x[-1] + a_1 * (x[0] - y_1[-1])
    out_data[0] = INNOTALK_SPL_SCALEDIFF32(filter_coefficients[0], diff, filter_state[0]);

    // For the remaining loops, use previous values.
    for (k = 1; k < data_length; k++)
    {
        diff = INNOTALK_SPL_SUB_SAT_W32(in_data[k], out_data[k - 1]); // = (x[n] - y_1[n-1])
        // y_1[n] =  x[n-1] + a_1 * (x[n] - y_1[n-1])
        out_data[k] = INNOTALK_SPL_SCALEDIFF32(filter_coefficients[0], diff, in_data[k - 1]);
    }

    // Update states.
    filter_state[0] = in_data[data_length - 1]; // x[N-1], becomes x[-1] next time
    filter_state[1] = out_data[data_length - 1]; // y_1[N-1], becomes y_1[-1] next time

    // Second all-pass cascade; filter from out_data to in_data.
    diff = INNOTALK_SPL_SUB_SAT_W32(out_data[0], filter_state[3]); // = (y_1[0] - y_2[-1])
    // y_2[0] =  y_1[-1] + a_2 * (y_1[0] - y_2[-1])
    in_data[0] = INNOTALK_SPL_SCALEDIFF32(filter_coefficients[1], diff, filter_state[2]);
    for (k = 1; k < data_length; k++)
    {
        diff = INNOTALK_SPL_SUB_SAT_W32(out_data[k], in_data[k - 1]); // =(y_1[n] - y_2[n-1])
        // y_2[0] =  y_1[-1] + a_2 * (y_1[0] - y_2[-1])
        in_data[k] = INNOTALK_SPL_SCALEDIFF32(filter_coefficients[1], diff, out_data[k-1]);
    }

    filter_state[2] = out_data[data_length - 1]; // y_1[N-1], becomes y_1[-1] next time
    filter_state[3] = in_data[data_length - 1]; // y_2[N-1], becomes y_2[-1] next time

    // Third all-pass cascade; filter from in_data to out_data.
    diff = INNOTALK_SPL_SUB_SAT_W32(in_data[0], filter_state[5]); // = (y_2[0] - y[-1])
    // y[0] =  y_2[-1] + a_3 * (y_2[0] - y[-1])
    out_data[0] = INNOTALK_SPL_SCALEDIFF32(filter_coefficients[2], diff, filter_state[4]);
    for (k = 1; k < data_length; k++)
    {
        diff = INNOTALK_SPL_SUB_SAT_W32(in_data[k], out_data[k - 1]); // = (y_2[n] - y[n-1])
        // y[n] =  y_2[n-1] + a_3 * (y_2[n] - y[n-1])
        out_data[k] = INNOTALK_SPL_SCALEDIFF32(filter_coefficients[2], diff, in_data[k-1]);
    }
    filter_state[4] = in_data[data_length - 1]; // y_2[N-1], becomes y_2[-1] next time
    filter_state[5] = out_data[data_length - 1]; // y[N-1], becomes y[-1] next time
}

void InnoTalkSpl_AnalysisQMF(const int16_t* in_data, 
                             int16_t* low_band,
                             int16_t* high_band, 
                             int32_t* filter_state1,
                             int32_t* filter_state2)
{
    int16_t i;
    int16_t k;
    int32_t tmp;
    int32_t half_in1[kBandFrameLength];
    int32_t half_in2[kBandFrameLength];
    int32_t filter1[kBandFrameLength];
    int32_t filter2[kBandFrameLength];

    // Split even and odd samples. Also shift them to Q10.
    for (i = 0, k = 0; i < kBandFrameLength; i++, k += 2)
    {
        half_in2[i] = INNOTALK_SPL_LSHIFT_W32((int32_t)in_data[k], 10);
        half_in1[i] = INNOTALK_SPL_LSHIFT_W32((int32_t)in_data[k + 1], 10);
    }

    // All pass filter even and odd samples, independently.
    InnoTalkSpl_AllPassQMF(half_in1, kBandFrameLength, filter1, InnoTalkSpl_kAllPassFilter1,
                         filter_state1);
    InnoTalkSpl_AllPassQMF(half_in2, kBandFrameLength, filter2, InnoTalkSpl_kAllPassFilter2,
                         filter_state2);

    // Take the sum and difference of filtered version of odd and even
    // branches to get upper & lower band.
    for (i = 0; i < kBandFrameLength; i++)
    {
        tmp = filter1[i] + filter2[i] + 1024;
        tmp = INNOTALK_SPL_RSHIFT_W32(tmp, 11);
        low_band[i] = InnoTalkSpl_SatW32ToW16(tmp);

        tmp = filter1[i] - filter2[i] + 1024;
        tmp = INNOTALK_SPL_RSHIFT_W32(tmp, 11);
        high_band[i] = InnoTalkSpl_SatW32ToW16(tmp);
    }
}

void InnoTalkSpl_SynthesisQMF(const int16_t* low_band, 
                              const int16_t* high_band,
                              int16_t* out_data, 
                              int32_t* filter_state1,
                              int32_t* filter_state2)
{
    int32_t tmp;
    int32_t half_in1[kBandFrameLength];
    int32_t half_in2[kBandFrameLength];
    int32_t filter1[kBandFrameLength];
    int32_t filter2[kBandFrameLength];
    int16_t i;
    int16_t k;

    // Obtain the sum and difference channels out of upper and lower-band channels.
    // Also shift to Q10 domain.
    for (i = 0; i < kBandFrameLength; i++)
    {
        tmp = (int32_t)low_band[i] + (int32_t)high_band[i];
        half_in1[i] = INNOTALK_SPL_LSHIFT_W32(tmp, 10);
        tmp = (int32_t)low_band[i] - (int32_t)high_band[i];
        half_in2[i] = INNOTALK_SPL_LSHIFT_W32(tmp, 10);
    }

    // all-pass filter the sum and difference channels
    InnoTalkSpl_AllPassQMF(half_in1, kBandFrameLength, filter1, InnoTalkSpl_kAllPassFilter2,
                         filter_state1);
    InnoTalkSpl_AllPassQMF(half_in2, kBandFrameLength, filter2, InnoTalkSpl_kAllPassFilter1,
                         filter_state2);

    // The filtered signals are even and odd samples of the output. Combine
    // them. The signals are Q10 should shift them back to Q0 and take care of
    // saturation.
    for (i = 0, k = 0; i < kBandFrameLength; i++)
    {
        tmp = INNOTALK_SPL_RSHIFT_W32(filter2[i] + 512, 10);
        out_data[k++] = InnoTalkSpl_SatW32ToW16(tmp);

        tmp = INNOTALK_SPL_RSHIFT_W32(filter1[i] + 512, 10);
        out_data[k++] = InnoTalkSpl_SatW32ToW16(tmp);
    }

}

void DSPF_sp_iir(float *y1, const float *x, float *y2, const float *hb, const float *ha, int n)
{
	int i, j;
	float sum;

	for (i = 0; i < n; i++)
	{
		sum = hb[0] * x[4 + i];
		for (j = 1; j <= 4; j++)
			sum += hb[j] * x[4 + i - j] - ha[j] * y1[4 + i - j];

		y1[4 + i] = sum;
		y2[i] = y1[4 + i];
	}
}

float h4816b1[5] = { 1.000000000000000f, 0.933349609375000f, 1.576143696904182f, 0.933349609375000f, 1.000000000000000f };
float h4816a1[5] = { 1.000000000000000f, -2.527832031250000f, 2.841476973146200f, -1.598608069121838f, 0.379345905035734f };
float h4816b2[5] = { 1.000000000000000f, -1.712097167968750f, 2.728731580078602f, -1.712097167968750f, 1.000000000000000f };
float h4816a2[5] = { 1.000000000000000f, -2.068603515625000f, 2.929914250969887f, -1.926375024020672f, 0.864411972463131f };
float g4816 = 0.009461402893066f;

void LRY_test_48_16N(short* in_data, short* out_data, IIR_State_DSPLIB_480* state)
{
	int i;
	//float tmp48k[N48];
	float tmp48k1[N48], tmp48k2[N48];
	memmove(state->w00, state->w00 + N48, 4 * sizeof(float));
	for (i = 0; i < N48; i++)
		state->w00[i + 4] = (float)(in_data[i]);
	DSPF_sp_iir(state->w01, state->w00, tmp48k1, h4816b1, h4816a1, N48);
	memmove(state->w01, state->w01 + N48, 4 * sizeof(float));
	//第二级
	memmove(state->w10, state->w10 + N48, 4 * sizeof(float));
	//DSPF_sp_blk_move (tmp48k1, &(state->w10[4]), N48);
	memcpy(&(state->w10[4]), tmp48k1, sizeof(float)*N48);
	//for (i = 0; i < N48; i++)
	//	state->w10[i + 4] = (float)(tmp48k1[i]);
	DSPF_sp_iir(state->w11, state->w10, tmp48k2, h4816b2, h4816a2, N48);
	memmove(state->w11, state->w11 + N48, 4 * sizeof(float));

	for (i = 0; i<N16; i++)
	{
		out_data[i] = (short)(tmp48k2[i * 3] * g4816);
	}
}

void LRY_test_16_48N(short* in_data, short* out_data, IIR_State_DSPLIB_480* state)
{
	float tmp48k[480];
	float tmp48k1[480], tmp48k2[480];
	short i = 0;

	for (i = 0; i<160; i++)
	{

		tmp48k[3 * i] = (float)in_data[i];
		tmp48k[3 * i + 1] = (float)in_data[i];
		tmp48k[3 * i + 2] = (float)in_data[i];
	}

	memmove(state->w00, state->w00 + N48, 4 * sizeof(float));
	//for (i = 0; i < N48; i++)
	//	state->w00[i + 4] = (float)(tmp48k[i]);
	memcpy(&(state->w00[4]), tmp48k, sizeof(float)*N48);
	DSPF_sp_iir(state->w01, state->w00, tmp48k1, h4816b1, h4816a1, N48);
	memmove(state->w01, state->w01 + N48, 4 * sizeof(float));
	//第二级
	memmove(state->w10, state->w10 + N48, 4 * sizeof(float));
	memcpy(&(state->w10[4]), tmp48k1, sizeof(float)*N48);
	//for (i = 0; i < N48; i++)
	//	state->w10[i + 4] = (float)(tmp48k1[i]);
	DSPF_sp_iir(state->w11, state->w10, tmp48k2, h4816b2, h4816a2, N48);
	memmove(state->w11, state->w11 + N48, 4 * sizeof(float));
	//step3:  96k-->32k

	for (i = 0; i < N48; i++)
	{
		out_data[i] = (short)(tmp48k2[i] * g4816);
	}

}
#define FFT_SIZE 512
#define PARTLEN 256
#define PARTLEN1 257
short mic1[FFT_SIZE] = { 0 };
short hismic1[FFT_SIZE] = { 0 };
short mic2[FFT_SIZE] = { 0 };
short hismic2[FFT_SIZE] = { 0 };
float frame[(FFT_SIZE - PARTLEN)] = { 0 };
float frame2[(FFT_SIZE - PARTLEN)] = { 0 };


void get_mic1(short * out) {
	for (size_t i = 0; i < FFT_SIZE; i++)
	{
		out[i] = mic1[i];
	}
}

void printMic() {
	for (size_t i = 0; i < FFT_SIZE; i++)
	{
		printf("%d ", mic1[i]);
	}
	printf("\n");
}
void reset() {
	memset(&mic1, 0, sizeof(short) * FFT_SIZE);
	memset(&hismic1, 0, sizeof(short) * FFT_SIZE);
	memset(&mic2, 0, sizeof(short) * FFT_SIZE);
	memset(&hismic2, 0, sizeof(short) * FFT_SIZE);
	memset(&frame, 0, sizeof(float) *( FFT_SIZE - PARTLEN));
	memset(&frame2, 0, sizeof(float) * (FFT_SIZE - PARTLEN));
	//frame2 = 0;
	/*for (size_t i = 0; i < FFT_SIZE; i++)
	{
		mic1[i] = 0; 
		hismic1[i] = 0;
	}
	for (size_t i = 0; i < FFT_SIZE - PARTLEN; i++)
	{
		frame[i] = 0;
	}*/
}

void DSPF_sp_vecmul(const float *x1, const float *x2, float *y, const int nx)
{
	int i;

	for (i = 0; i < nx; i++)
		y[i] = x1[i] * x2[i];
}

// y = m * x1 + x2
void DSPF_sp_w_vec(const float *x1, const float *x2, const float m, float *y, const int nx)
{
	int i;

	for (i = 0; i < nx; i++)
		y[i] = (m * x1[i]) + x2[i];
}

static const float kBlocks64w128[128] = {
	0.0000, 0.0245, 0.0491, 0.0736, 0.0980, 0.1224,
	0.1467, 0.1710, 0.1951, 0.2191, 0.2430, 0.2667,
	0.2903, 0.3137, 0.3369, 0.3599, 0.3827, 0.4052,
	0.4276, 0.4496, 0.4714, 0.4929, 0.5141, 0.5350,
	0.5556, 0.5758, 0.5957, 0.6152, 0.6344, 0.6532,
	0.6716, 0.6895, 0.7071, 0.7242, 0.7410, 0.7572,
	0.7730, 0.7883, 0.8032, 0.8176, 0.8315, 0.8449,
	0.8577, 0.8701, 0.8819, 0.8932, 0.9040, 0.9142,
	0.9239, 0.9330, 0.9415, 0.9495, 0.9569, 0.9638,
	0.9700, 0.9757, 0.9808, 0.9853, 0.9892, 0.9925,
	0.9952, 0.9973, 0.9988, 0.9997, 1.0000, 0.9997,
	0.9988, 0.9973, 0.9952, 0.9925, 0.9892, 0.9853,
	0.9808, 0.9757, 0.9700, 0.9638, 0.9569, 0.9495,
	0.9415, 0.9330, 0.9239, 0.9142, 0.9040, 0.8932,
	0.8819, 0.8701, 0.8577, 0.8449, 0.8315, 0.8176,
	0.8032, 0.7883, 0.7730, 0.7572, 0.7410, 0.7242,
	0.7071, 0.6895, 0.6716, 0.6532, 0.6344, 0.6152,
	0.5957, 0.5758, 0.5556, 0.5350, 0.5141, 0.4929,
	0.4714, 0.4496, 0.4276, 0.4052, 0.3827, 0.3599,
	0.3369, 0.3137, 0.2903, 0.2667, 0.2430, 0.2191,
	0.1951, 0.1710, 0.1467, 0.1224, 0.0980, 0.0736,
	0.0491, 0.0245 };

static const float kBlocks256w512[512] = {
	0.0000, 0.0061, 0.0123, 0.0184, 0.0245, 0.0307, 0.0368, 0.0429, 0.0491,
	0.0552, 0.0613, 0.0674, 0.0736, 0.0797, 0.0858, 0.0919, 0.0980, 0.1041,
	0.1102, 0.1163, 0.1224, 0.1285, 0.1346, 0.1407, 0.1467, 0.1528, 0.1589,
	0.1649, 0.1710, 0.1770, 0.1830, 0.1891, 0.1951, 0.2011, 0.2071, 0.2131,
	0.2191, 0.2251, 0.2311, 0.2370, 0.2430, 0.2489, 0.2549, 0.2608, 0.2667,
	0.2726, 0.2785, 0.2844, 0.2903, 0.2962, 0.3020, 0.3078, 0.3137, 0.3195,
	0.3253, 0.3311, 0.3369, 0.3427, 0.3484, 0.3542, 0.3599, 0.3656, 0.3713,
	0.3770, 0.3827, 0.3883, 0.3940, 0.3996, 0.4052, 0.4108, 0.4164, 0.4220,
	0.4276, 0.4331, 0.4386, 0.4441, 0.4496, 0.4551, 0.4605, 0.4660, 0.4714,
	0.4768, 0.4822, 0.4876, 0.4929, 0.4982, 0.5035, 0.5088, 0.5141, 0.5194,
	0.5246, 0.5298, 0.5350, 0.5402, 0.5453, 0.5505, 0.5556, 0.5607, 0.5657,
	0.5708, 0.5758, 0.5808, 0.5858, 0.5908, 0.5957, 0.6006, 0.6055, 0.6104,
	0.6152, 0.6201, 0.6249, 0.6296, 0.6344, 0.6391, 0.6438, 0.6485, 0.6532,
	0.6578, 0.6624, 0.6670, 0.6716, 0.6761, 0.6806, 0.6851, 0.6895, 0.6940,
	0.6984, 0.7028, 0.7071, 0.7114, 0.7157, 0.7200, 0.7242, 0.7285, 0.7327,
	0.7368, 0.7410, 0.7451, 0.7491, 0.7532, 0.7572, 0.7612, 0.7652, 0.7691,
	0.7730, 0.7769, 0.7807, 0.7846, 0.7883, 0.7921, 0.7958, 0.7995, 0.8032,
	0.8068, 0.8105, 0.8140, 0.8176, 0.8211, 0.8246, 0.8280, 0.8315, 0.8349,
	0.8382, 0.8416, 0.8449, 0.8481, 0.8514, 0.8546, 0.8577, 0.8609, 0.8640,
	0.8670, 0.8701, 0.8731, 0.8761, 0.8790, 0.8819, 0.8848, 0.8876, 0.8904,
	0.8932, 0.8960, 0.8987, 0.9013, 0.9040, 0.9066, 0.9092, 0.9117, 0.9142,
	0.9167, 0.9191, 0.9215, 0.9239, 0.9262, 0.9285, 0.9308, 0.9330, 0.9352,
	0.9373, 0.9395, 0.9415, 0.9436, 0.9456, 0.9476, 0.9495, 0.9514, 0.9533,
	0.9551, 0.9569, 0.9587, 0.9604, 0.9621, 0.9638, 0.9654, 0.9670, 0.9685,
	0.9700, 0.9715, 0.9729, 0.9743, 0.9757, 0.9770, 0.9783, 0.9796, 0.9808,
	0.9820, 0.9831, 0.9842, 0.9853, 0.9863, 0.9873, 0.9883, 0.9892, 0.9901,
	0.9909, 0.9917, 0.9925, 0.9932, 0.9939, 0.9946, 0.9952, 0.9958, 0.9963,
	0.9968, 0.9973, 0.9977, 0.9981, 0.9985, 0.9988, 0.9991, 0.9993, 0.9995,
	0.9997, 0.9998, 0.9999, 1.0000, 1.0000, 1.0000, 0.9999, 0.9998, 0.9997,
	0.9995, 0.9993, 0.9991, 0.9988, 0.9985, 0.9981, 0.9977, 0.9973, 0.9968,
	0.9963, 0.9958, 0.9952, 0.9946, 0.9939, 0.9932, 0.9925, 0.9917, 0.9909,
	0.9901, 0.9892, 0.9883, 0.9873, 0.9863, 0.9853, 0.9842, 0.9831, 0.9820,
	0.9808, 0.9796, 0.9783, 0.9770, 0.9757, 0.9743, 0.9729, 0.9715, 0.9700,
	0.9685, 0.9670, 0.9654, 0.9638, 0.9621, 0.9604, 0.9587, 0.9569, 0.9551,
	0.9533, 0.9514, 0.9495, 0.9476, 0.9456, 0.9436, 0.9415, 0.9395, 0.9373,
	0.9352, 0.9330, 0.9308, 0.9285, 0.9262, 0.9239, 0.9215, 0.9191, 0.9167,
	0.9142, 0.9117, 0.9092, 0.9066, 0.9040, 0.9013, 0.8987, 0.8960, 0.8932,
	0.8904, 0.8876, 0.8848, 0.8819, 0.8790, 0.8761, 0.8731, 0.8701, 0.8670,
	0.8640, 0.8609, 0.8577, 0.8546, 0.8514, 0.8481, 0.8449, 0.8416, 0.8382,
	0.8349, 0.8315, 0.8280, 0.8246, 0.8211, 0.8176, 0.8140, 0.8105, 0.8068,
	0.8032, 0.7995, 0.7958, 0.7921, 0.7883, 0.7846, 0.7807, 0.7769, 0.7730,
	0.7691, 0.7652, 0.7612, 0.7572, 0.7532, 0.7491, 0.7451, 0.7410, 0.7368,
	0.7327, 0.7285, 0.7242, 0.7200, 0.7157, 0.7114, 0.7071, 0.7028, 0.6984,
	0.6940, 0.6895, 0.6851, 0.6806, 0.6761, 0.6716, 0.6670, 0.6624, 0.6578,
	0.6532, 0.6485, 0.6438, 0.6391, 0.6344, 0.6296, 0.6249, 0.6201, 0.6152,
	0.6104, 0.6055, 0.6006, 0.5957, 0.5908, 0.5858, 0.5808, 0.5758, 0.5708,
	0.5657, 0.5607, 0.5556, 0.5505, 0.5453, 0.5402, 0.5350, 0.5298, 0.5246,
	0.5194, 0.5141, 0.5088, 0.5035, 0.4982, 0.4929, 0.4876, 0.4822, 0.4768,
	0.4714, 0.4660, 0.4605, 0.4551, 0.4496, 0.4441, 0.4386, 0.4331, 0.4276,
	0.4220, 0.4164, 0.4108, 0.4052, 0.3996, 0.3940, 0.3883, 0.3827, 0.3770,
	0.3713, 0.3656, 0.3599, 0.3542, 0.3484, 0.3427, 0.3369, 0.3311, 0.3253,
	0.3195, 0.3137, 0.3078, 0.3020, 0.2962, 0.2903, 0.2844, 0.2785, 0.2726,
	0.2667, 0.2608, 0.2549, 0.2489, 0.2430, 0.2370, 0.2311, 0.2251, 0.2191,
	0.2131, 0.2071, 0.2011, 0.1951, 0.1891, 0.1830, 0.1770, 0.1710, 0.1649,
	0.1589, 0.1528, 0.1467, 0.1407, 0.1346, 0.1285, 0.1224, 0.1163, 0.1102,
	0.1041, 0.0980, 0.0919, 0.0858, 0.0797, 0.0736, 0.0674, 0.0613, 0.0552,
	0.0491, 0.0429, 0.0368, 0.0307, 0.0245, 0.0184, 0.0123, 0.0061 };


void SignalDFT(const short *in, float *out, const short FFTLen, const short FrameLen)
{
	float mic1_f[FFT_SIZE] = { 0 };
	int i;
	float   real[FFT_SIZE], imag[FFT_SIZE];
	memcpy(&mic1[FFTLen - FrameLen], in, sizeof(short)*FrameLen);
	memcpy(mic1, &hismic1[FrameLen], sizeof(short)*(FFTLen - FrameLen));
	memcpy(hismic1, mic1, sizeof(short)*FFTLen);
	
	for (i = 0; i < FFTLen; ++i) {
		mic1_f[i] = (float)(mic1[i]) * 0.000030517578125f;
	}

	if (FFT_SIZE == 512)
	{
		DSPF_sp_vecmul(mic1_f, kBlocks256w512, mic1_f, FFTLen);
	}
	else {
		DSPF_sp_vecmul(mic1_f, kBlocks64w128, mic1_f, FFTLen);
	}
	
	
	InnoTalk_rdft(FFT_SIZE, 1, mic1_f, cofip, cofwfft); //虚部和matlab差了符号
#if 0
	memcpy(out, mic1_f, sizeof(float)*FFT_SIZE);  // 2x65-2 = 128
	imag[0] = 0;
	real[0] = out[0];
	imag[PARTLEN1 - 1] = 0;
	real[PARTLEN1 - 1] = out[1];
	for (i = 1; i < PARTLEN1 - 1; i++) {
		real[i] = out[2 * i];
		imag[i] = out[2 * i + 1];
	}
#else
	
	out[0] = mic1_f[0];
	out[PARTLEN1 - 1] = mic1_f[1];
	out[PARTLEN1] = 0;
	out[2*PARTLEN1 - 1] = 0;
	for (i = 1; i < PARTLEN1 - 1; i++) {
		out[i] = mic1_f[2 * i];
		out[i+ PARTLEN1] = mic1_f[2 * i + 1];
	}
	
#endif
}

void SignalDFT2(const short* in, float* out, const short FFTLen, const short FrameLen)
{
	float mic2_f[FFT_SIZE] = { 0 };
	int i;
	float   real[FFT_SIZE], imag[FFT_SIZE];
	memcpy(&mic2[FFTLen - FrameLen], in, sizeof(short) * FrameLen);
	memcpy(mic2, &hismic2[FrameLen], sizeof(short) * (FFTLen - FrameLen));
	memcpy(hismic2, mic2, sizeof(short) * FFTLen);

	for (i = 0; i < FFTLen; ++i) {
		mic2_f[i] = (float)(mic2[i]) * 0.000030517578125f;
	}

	if (FFT_SIZE == 512)
	{
		DSPF_sp_vecmul(mic2_f, kBlocks256w512, mic2_f, FFTLen);
	}
	else {
		DSPF_sp_vecmul(mic2_f, kBlocks64w128, mic2_f, FFTLen);
	}


	InnoTalk_rdft(FFT_SIZE, 1, mic2_f, cofip, cofwfft); //虚部和matlab差了符号
#if 0
	memcpy(out, mic1_f, sizeof(float) * FFT_SIZE);  // 2x65-2 = 128
	imag[0] = 0;
	real[0] = out[0];
	imag[PARTLEN1 - 1] = 0;
	real[PARTLEN1 - 1] = out[1];
	for (i = 1; i < PARTLEN1 - 1; i++) {
		real[i] = out[2 * i];
		imag[i] = out[2 * i + 1];
	}
#else
	out[0] = mic2_f[0];
	out[PARTLEN1 - 1] = mic2_f[1];
	out[PARTLEN1] = 0;
	out[2 * PARTLEN1 - 1] = 0;
	for (i = 1; i < PARTLEN1 - 1; i++) {
		out[i] = mic2_f[2 * i];
		out[i + PARTLEN1] = mic2_f[2 * i + 1];
	}
#endif
}

void SignalIDFT(const float *in, short *out, const short FFTLen, const short FrameLen)
{

	float   real[FFT_SIZE];
	int i;
	float out_sig[FFT_SIZE] = { 0 };

#if 0
	float* in_ = in;
#else
	float in_[FFT_SIZE] = {0};
	// r,r;i,i.. -> r[0],r[PARTLEN1-1],r[1],i[1],...
	in_[0] = in[0];
	in_[1] = in[PARTLEN1-1];
	for (i = 1; i < PARTLEN1 - 1; i++) {
		in_[2*i] = in[i];
		in_[2*i + 1] = in[i + PARTLEN1];
	}
#endif

	InnoTalk_rdft(FFT_SIZE, -1, in_, cofip, cofwfft);

	for (i = 0; i < FFT_SIZE; i++) {
		real[i] = 2.0f * in_[i] / FFT_SIZE; // fft scaling
	}
	if (FFT_SIZE == 512)
	{
		DSPF_sp_vecmul(real, kBlocks256w512, out_sig, FFTLen);
	}
	else {
		DSPF_sp_vecmul(real, kBlocks64w128, out_sig, FFTLen);
	}
	DSPF_sp_w_vec(out_sig, frame, 1, out_sig, (FFTLen - FrameLen));
	memcpy(frame, out_sig + FrameLen, sizeof(float) * (FFTLen - FrameLen));
	for (i = 0; i < FrameLen; i++) {
		out[i] = (short)(out_sig[i] * 32768);
	}
}


void swap(float* data, int m, int n)
{
	float temp = data[m];
	data[m] = data[n];
	data[n] = temp;
}

void fft_ifft_implement(float* data, int N, int flag)
{
	// 判断样本个数是不是2的指数倍，如果不是能否补零成指数倍？
	float number_log = log(N) / log(2);
	int mmax = 2, j = 0;
	int n = N << 1;
	int istep, m;
	float theta, wtemp, wpr, wpi, wr, wi, tempr, tempi;

	for (int i = 0; i < n - 1; i = i + 2)
	{
		if (j > i)
		{
			swap(data, j, i);
			swap(data, j + 1, i + 1);
		}
		m = n / 2;
		while (m >= 2 && j >= m)
		{
			j = j - m;
			m = m / 2;
		}
		j = j + m;
	}
	while (n > mmax)
	{
		istep = mmax << 1;
		theta = -2 * PI / (flag * mmax);
		wtemp = sin(0.5 * theta);
		wpr = -2.0 * wtemp * wtemp;
		wpi = sin(theta);
		wr = 1.0;
		wi = 0.0;
		for (int m = 1; m < mmax; m = m + 2)
		{
			for (int i = m; i < n + 1; i = i + istep)
			{
				int j = i + mmax;
				tempr = wr * data[j - 1] - wi * data[j];
				tempi = wr * data[j] + wi * data[j - 1];
				data[j - 1] = data[i - 1] - tempr;
				data[j] = data[i] - tempi;
				data[i - 1] += tempr;
				data[i] += tempi;
			}
			wtemp = wr;
			wr += wr * wpr - wi * wpi;
			wi += wi * wpr + wtemp * wpi;
		}
		mmax = istep;
	}
}


void fft(float* data, int N, float* result)
{
	// 需要给奇数部分填充虚数0
	for (int i = 0; i < N; ++i)
	{
		result[2 * i] = data[i];
		result[2 * i + 1] = 0;
	}
	int flag = 1;
	fft_ifft_implement(result, N, flag);
}

// data的长度是2n，result的长度为n,n必须是2的指数倍
void ifft(float* data, int N, float* result)
{
	int flag = -1;
	fft_ifft_implement(data, N, flag);
	// 奇数部分是虚数，需要舍弃
	for (int i = 0; i < N; i++)
	{
		result[i] = data[2 * i] / N;
	}
}


void stft1(const short* in, float* out, const short FFTLen, const short FrameLen)
{
	float mic1_f[FFT_SIZE] = { 0 };
	int i;
	memcpy(&mic1[FFTLen - FrameLen], in, sizeof(short) * FrameLen);
	memcpy(mic1, &hismic1[FrameLen], sizeof(short) * (FFTLen - FrameLen));
	memcpy(hismic1, mic1, sizeof(short) * FFTLen);

	for (i = 0; i < FFTLen; ++i) {
		mic1_f[i] = (float)(mic1[i]) * 0.000030517578125f;
	}

	if (FFT_SIZE == 512)
	{
		DSPF_sp_vecmul(mic1_f, kBlocks256w512, mic1_f, FFTLen);
	}
	else {
		DSPF_sp_vecmul(mic1_f, kBlocks64w128, mic1_f, FFTLen);
	}

	float result[2 * FFT_SIZE] = { 0.0 };
	fft(mic1_f, FFT_SIZE, result);

	out[0] = result[0];
	out[PARTLEN1 - 1] = result[2*PARTLEN];
	out[PARTLEN1] = 0;
	out[2 * PARTLEN1 - 1] = 0;
	for (i = 1; i < PARTLEN1 - 1; i++) {
		out[i] = result[2 * i];
		out[i + PARTLEN1] = -result[2 * i + 1];
	}
}

void stft2(const short* in, float* out, const short FFTLen, const short FrameLen)
{
	float mic2_f[FFT_SIZE] = { 0 };
	int i;
	float   real[FFT_SIZE], imag[FFT_SIZE];
	memcpy(&mic2[FFTLen - FrameLen], in, sizeof(short) * FrameLen);
	memcpy(mic2, &hismic2[FrameLen], sizeof(short) * (FFTLen - FrameLen));
	memcpy(hismic2, mic2, sizeof(short) * FFTLen);

	for (i = 0; i < FFTLen; ++i) {
		mic2_f[i] = (float)(mic2[i]) * 0.000030517578125f;
	}

	if (FFT_SIZE == 512)
	{
		DSPF_sp_vecmul(mic2_f, kBlocks256w512, mic2_f, FFTLen);
	}
	else {
		DSPF_sp_vecmul(mic2_f, kBlocks64w128, mic2_f, FFTLen);
	}

	float result[2 * FFT_SIZE] = { 0.0 };
	fft(mic2_f, FFT_SIZE, result);

	out[0] = result[0];
	out[PARTLEN1 - 1] = result[2 * PARTLEN];
	out[PARTLEN1] = 0;
	out[2 * PARTLEN1 - 1] = 0;
	for (i = 1; i < PARTLEN1 - 1; i++) {
		out[i] = result[2 * i];
		out[i + PARTLEN1] = -result[2 * i + 1];
	}
}

// input 的长度是 2*frameSize，output的长度为 frameSize
void istft(const float* in, short* out, const short FFTLen, const short FrameLen) {

	float input[2 * FFT_SIZE] = { 0 };
	input[0] = in[0];
	input[1] = - in[PARTLEN1];
	input[2 * PARTLEN] = in[PARTLEN1 - 1];
	input[2 * PARTLEN + 1] = -in[2 * PARTLEN + 1];

	for (size_t i = 1; i < PARTLEN; i++)
	{
		input[2 * i] = in[i];
		input[2 * i + 1] = - in[i + PARTLEN1];
		input[2 * (2 * PARTLEN - i)] = in[i];
		input[2 * (2 * PARTLEN - i) + 1] = in[i + PARTLEN1];
	}

	float output[FFT_SIZE] = { 0.0 };
	ifft(input, FFTLen, output);

	if (FFT_SIZE == 512)
	{
		for (size_t i = 0; i < FFTLen; i += 1)
		{
			output[i] = output[i] * kBlocks256w512[i];
		}
	}
	else
	{
		for (size_t i = 0; i < FFTLen; i += 1)
		{
			output[i] = output[i] * kBlocks64w128[i];
		}
	}
	//output[0] = frame2;
	DSPF_sp_w_vec(output, frame2, 1, output, (FFTLen - FrameLen));
	memcpy(frame2, output + FrameLen, sizeof(float) * (FFTLen - FrameLen));
	//frame2 = output[FrameLen];
	for (int i = 0; i < FrameLen; i++)
	{
		out[i] = (short)(output[i] * 32768);
	}
}


uint32_t InnoTalkSpl_DivU32U16(uint32_t num, uint16_t den)
{
	// Guard against division with 0
	if (den != 0)
	{
		return (uint32_t)(num / den);
	}
	else
	{
		return (uint32_t)0xFFFFFFFF;
	}
}

int32_t InnoTalkSpl_DivW32W16(int32_t num, int16_t den)
{
	// Guard against division with 0
	if (den != 0)
	{
		return (int32_t)(num / den);
	}
	else
	{
		return (int32_t)0x7FFFFFFF;
	}
}

int16_t InnoTalkSpl_DivW32W16ResW16(int32_t num, int16_t den)
{
	// Guard against division with 0
	if (den != 0)
	{
		return (int16_t)(num / den);
	}
	else
	{
		return (int16_t)0x7FFF;
	}
}

int32_t InnoTalkSpl_DivResultInQ31(int32_t num, int32_t den)
{
	int32_t L_num = num;
	int32_t L_den = den;
	int32_t div = 0;
	int k = 31;
	int change_sign = 0;

	if (num == 0)
		return 0;

	if (num < 0)
	{
		change_sign++;
		L_num = -num;
	}
	if (den < 0)
	{
		change_sign++;
		L_den = -den;
	}
	while (k--)
	{
		div <<= 1;
		L_num <<= 1;
		if (L_num >= L_den)
		{
			L_num -= L_den;
			div++;
		}
	}
	if (change_sign == 1)
	{
		div = -div;
	}
	return div;
}

int32_t InnoTalkSpl_DivW32HiLow(int32_t num, int16_t den_hi, int16_t den_low)
{
	int16_t approx, tmp_hi, tmp_low, num_hi, num_low;
	int32_t tmpW32;

	approx = (int16_t)InnoTalkSpl_DivW32W16((int32_t)0x1FFFFFFF, den_hi);
	// result in Q14 (Note: 3FFFFFFF = 0.5 in Q30)

	// tmpW32 = 1/den = approx * (2.0 - den * approx) (in Q30)
	tmpW32 = (INNOTALK_SPL_MUL_16_16(den_hi, approx) << 1)
		+ ((INNOTALK_SPL_MUL_16_16(den_low, approx) >> 15) << 1);
	// tmpW32 = den * approx

	tmpW32 = (int32_t)0x7fffffffL - tmpW32; // result in Q30 (tmpW32 = 2.0-(den*approx))

											// Store tmpW32 in hi and low format
	tmp_hi = (int16_t)INNOTALK_SPL_RSHIFT_W32(tmpW32, 16);
	tmp_low = (int16_t)INNOTALK_SPL_RSHIFT_W32((tmpW32
		- INNOTALK_SPL_LSHIFT_W32((int32_t)tmp_hi, 16)), 1);

	// tmpW32 = 1/den in Q29
	tmpW32 = ((INNOTALK_SPL_MUL_16_16(tmp_hi, approx) + (INNOTALK_SPL_MUL_16_16(tmp_low, approx)
		>> 15)) << 1);

	// 1/den in hi and low format
	tmp_hi = (int16_t)INNOTALK_SPL_RSHIFT_W32(tmpW32, 16);
	tmp_low = (int16_t)INNOTALK_SPL_RSHIFT_W32((tmpW32
		- INNOTALK_SPL_LSHIFT_W32((int32_t)tmp_hi, 16)), 1);

	// Store num in hi and low format
	num_hi = (int16_t)INNOTALK_SPL_RSHIFT_W32(num, 16);
	num_low = (int16_t)INNOTALK_SPL_RSHIFT_W32((num
		- INNOTALK_SPL_LSHIFT_W32((int32_t)num_hi, 16)), 1);

	// num * (1/den) by 32 bit multiplication (result in Q28)

	tmpW32 = (INNOTALK_SPL_MUL_16_16(num_hi, tmp_hi) + (INNOTALK_SPL_MUL_16_16(num_hi, tmp_low)
		>> 15) + (INNOTALK_SPL_MUL_16_16(num_low, tmp_hi) >> 15));

	// Put result in Q31 (convert from Q28)
	tmpW32 = INNOTALK_SPL_LSHIFT_W32(tmpW32, 3);

	return tmpW32;
}


int32_t InnoTalkSpl_DotProductWithScale(const int16_t* vector1,
	const int16_t* vector2,
	int length,
	int scaling) {
	int32_t sum = 0;
	int i = 0;

	/* Unroll the loop to improve performance. */
	for (i = 0; i < length - 3; i += 4) {
		sum += (vector1[i + 0] * vector2[i + 0]) >> scaling;
		sum += (vector1[i + 1] * vector2[i + 1]) >> scaling;
		sum += (vector1[i + 2] * vector2[i + 2]) >> scaling;
		sum += (vector1[i + 3] * vector2[i + 3]) >> scaling;
	}
	for (; i < length; i++) {
		sum += (vector1[i] * vector2[i]) >> scaling;
	}

	return sum;
}


// allpass filter coefficients.
static const uint16_t kResampleAllpass1[3] = { 3284, 24441, 49528 };
static const uint16_t kResampleAllpass2[3] = { 12199, 37471, 60255 };

// Multiply a 32-bit value with a 16-bit value and accumulate to another input:
#define MUL_ACCUM_1(a, b, c) INNOTALK_SPL_SCALEDIFF32(a, b, c)
#define MUL_ACCUM_2(a, b, c) INNOTALK_SPL_SCALEDIFF32(a, b, c)


// decimator
#if !defined(MIPS32_LE)
void InnoTalkSpl_DownsampleBy2(const int16_t* in, int16_t len,
	int16_t* out, int32_t* filtState) {
	int32_t tmp1, tmp2, diff, in32, out32;
	int16_t i;

	register int32_t state0 = filtState[0];
	register int32_t state1 = filtState[1];
	register int32_t state2 = filtState[2];
	register int32_t state3 = filtState[3];
	register int32_t state4 = filtState[4];
	register int32_t state5 = filtState[5];
	register int32_t state6 = filtState[6];
	register int32_t state7 = filtState[7];

	for (i = (len >> 1); i > 0; i--) {
		// lower allpass filter
		in32 = (int32_t)(*in++) << 10;
		diff = in32 - state1;
		tmp1 = MUL_ACCUM_1(kResampleAllpass2[0], diff, state0);
		state0 = in32;
		diff = tmp1 - state2;
		tmp2 = MUL_ACCUM_2(kResampleAllpass2[1], diff, state1);
		state1 = tmp1;
		diff = tmp2 - state3;
		state3 = MUL_ACCUM_2(kResampleAllpass2[2], diff, state2);
		state2 = tmp2;

		// upper allpass filter
		in32 = (int32_t)(*in++) << 10;
		diff = in32 - state5;
		tmp1 = MUL_ACCUM_1(kResampleAllpass1[0], diff, state4);
		state4 = in32;
		diff = tmp1 - state6;
		tmp2 = MUL_ACCUM_1(kResampleAllpass1[1], diff, state5);
		state5 = tmp1;
		diff = tmp2 - state7;
		state7 = MUL_ACCUM_2(kResampleAllpass1[2], diff, state6);
		state6 = tmp2;

		// add two allpass outputs, divide by two and round
		out32 = (state3 + state7 + 1024) >> 11;

		// limit amplitude to prevent wrap-around, and write to output array
		*out++ = InnoTalkSpl_SatW32ToW16(out32);
	}

	filtState[0] = state0;
	filtState[1] = state1;
	filtState[2] = state2;
	filtState[3] = state3;
	filtState[4] = state4;
	filtState[5] = state5;
	filtState[6] = state6;
	filtState[7] = state7;
}
#endif  // #if defined(MIPS32_LE)


void InnoTalkSpl_UpsampleBy2(const int16_t* in, int16_t len,
	int16_t* out, int32_t* filtState) {
	int32_t tmp1, tmp2, diff, in32, out32;
	int16_t i;

	register int32_t state0 = filtState[0];
	register int32_t state1 = filtState[1];
	register int32_t state2 = filtState[2];
	register int32_t state3 = filtState[3];
	register int32_t state4 = filtState[4];
	register int32_t state5 = filtState[5];
	register int32_t state6 = filtState[6];
	register int32_t state7 = filtState[7];

	for (i = len; i > 0; i--) {
		// lower allpass filter
		in32 = (int32_t)(*in++) << 10;
		diff = in32 - state1;
		tmp1 = MUL_ACCUM_1(kResampleAllpass1[0], diff, state0);
		state0 = in32;
		diff = tmp1 - state2;
		tmp2 = MUL_ACCUM_1(kResampleAllpass1[1], diff, state1);
		state1 = tmp1;
		diff = tmp2 - state3;
		state3 = MUL_ACCUM_2(kResampleAllpass1[2], diff, state2);
		state2 = tmp2;

		// round; limit amplitude to prevent wrap-around; write to output array
		out32 = (state3 + 512) >> 10;
		*out++ = InnoTalkSpl_SatW32ToW16(out32);

		// upper allpass filter
		diff = in32 - state5;
		tmp1 = MUL_ACCUM_1(kResampleAllpass2[0], diff, state4);
		state4 = in32;
		diff = tmp1 - state6;
		tmp2 = MUL_ACCUM_2(kResampleAllpass2[1], diff, state5);
		state5 = tmp1;
		diff = tmp2 - state7;
		state7 = MUL_ACCUM_2(kResampleAllpass2[2], diff, state6);
		state6 = tmp2;

		// round; limit amplitude to prevent wrap-around; write to output array
		out32 = (state7 + 512) >> 10;
		*out++ = InnoTalkSpl_SatW32ToW16(out32);
	}

	filtState[0] = state0;
	filtState[1] = state1;
	filtState[2] = state2;
	filtState[3] = state3;
	filtState[4] = state4;
	filtState[5] = state5;
	filtState[6] = state6;
	filtState[7] = state7;
}


int32_t InnoTalkSpl_SqrtLocal(int32_t in);

int32_t InnoTalkSpl_SqrtLocal(int32_t in)
{

	int16_t x_half, t16;
	int32_t A, B, x2;

	/* The following block performs:
	y=in/2
	x=y-2^30
	x_half=x/2^31
	t = 1 + (x_half) - 0.5*((x_half)^2) + 0.5*((x_half)^3) - 0.625*((x_half)^4)
	+ 0.875*((x_half)^5)
	*/

	B = in;

	B = INNOTALK_SPL_RSHIFT_W32(B, 1); // B = in/2
	B = B - ((int32_t)0x40000000); // B = in/2 - 1/2
	x_half = (int16_t)INNOTALK_SPL_RSHIFT_W32(B, 16);// x_half = x/2 = (in-1)/2
	B = B + ((int32_t)0x40000000); // B = 1 + x/2
	B = B + ((int32_t)0x40000000); // Add 0.5 twice (since 1.0 does not exist in Q31)

	x2 = ((int32_t)x_half) * ((int32_t)x_half) * 2; // A = (x/2)^2
	A = -x2; // A = -(x/2)^2
	B = B + (A >> 1); // B = 1 + x/2 - 0.5*(x/2)^2

	A = INNOTALK_SPL_RSHIFT_W32(A, 16);
	A = A * A * 2; // A = (x/2)^4
	t16 = (int16_t)INNOTALK_SPL_RSHIFT_W32(A, 16);
	B = B + INNOTALK_SPL_MUL_16_16(-20480, t16) * 2; // B = B - 0.625*A
													 // After this, B = 1 + x/2 - 0.5*(x/2)^2 - 0.625*(x/2)^4

	t16 = (int16_t)INNOTALK_SPL_RSHIFT_W32(A, 16);
	A = INNOTALK_SPL_MUL_16_16(x_half, t16) * 2; // A = (x/2)^5
	t16 = (int16_t)INNOTALK_SPL_RSHIFT_W32(A, 16);
	B = B + INNOTALK_SPL_MUL_16_16(28672, t16) * 2; // B = B + 0.875*A
													// After this, B = 1 + x/2 - 0.5*(x/2)^2 - 0.625*(x/2)^4 + 0.875*(x/2)^5

	t16 = (int16_t)INNOTALK_SPL_RSHIFT_W32(x2, 16);
	A = INNOTALK_SPL_MUL_16_16(x_half, t16) * 2; // A = x/2^3

	B = B + (A >> 1); // B = B + 0.5*A
					  // After this, B = 1 + x/2 - 0.5*(x/2)^2 + 0.5*(x/2)^3 - 0.625*(x/2)^4 + 0.875*(x/2)^5

	B = B + ((int32_t)32768); // Round off bit

	return B;
}

int32_t InnoTalkSpl_Sqrt(int32_t value)
{

	int16_t x_norm, nshift, t16, sh;
	int32_t A;

	int16_t k_sqrt_2 = 23170; // 1/sqrt2 (==5a82)

	A = value;

	if (A == 0)
		return (int32_t)0; // sqrt(0) = 0

	sh = InnoTalkSpl_NormW32(A); // # shifts to normalize A
	A = INNOTALK_SPL_LSHIFT_W32(A, sh); // Normalize A
	if (A < (INNOTALK_SPL_WORD32_MAX - 32767))
	{
		A = A + ((int32_t)32768); // Round off bit
	}
	else
	{
		A = INNOTALK_SPL_WORD32_MAX;
	}

	x_norm = (int16_t)INNOTALK_SPL_RSHIFT_W32(A, 16); // x_norm = AH

	nshift = INNOTALK_SPL_RSHIFT_W16(sh, 1); // nshift = sh>>1
	nshift = -nshift; // Negate the power for later de-normalization

	A = (int32_t)INNOTALK_SPL_LSHIFT_W32((int32_t)x_norm, 16);
	A = INNOTALK_SPL_ABS_W32(A); // A = abs(x_norm<<16)
	A = InnoTalkSpl_SqrtLocal(A); // A = sqrt(A)

	if ((-2 * nshift) == sh)
	{ // Even shift value case

		t16 = (int16_t)INNOTALK_SPL_RSHIFT_W32(A, 16); // t16 = AH

		A = INNOTALK_SPL_MUL_16_16(k_sqrt_2, t16) * 2; // A = 1/sqrt(2)*t16
		A = A + ((int32_t)32768); // Round off
		A = A & ((int32_t)0x7fff0000); // Round off

		A = INNOTALK_SPL_RSHIFT_W32(A, 15); // A = A>>16

	}
	else
	{
		A = INNOTALK_SPL_RSHIFT_W32(A, 16); // A = A>>16
	}

	A = A & ((int32_t)0x0000ffff);
	A = (int32_t)INNOTALK_SPL_SHIFT_W32(A, nshift); // De-normalize the result

	return A;
}

void InnoTalkSpl_MemSetW32(int32_t *ptr, int32_t set_value, int length)
{
	int j;
	int32_t *arrptr = ptr;

	for (j = length; j > 0; j--)
	{
		*arrptr++ = set_value;
	}
}

static void makewt(int nw, int *ip, float *w);
static void makect(int nc, int *ip, float *c);
static void bitrv2(int n, int *ip, float *a);
static void bitrv2conj(int n, int *ip, float *a);
static void cftfsub(int n, float *a, float *w);
static void cftbsub(int n, float *a, float *w);
static void cft1st(int n, float *a, float *w);
static void cftmdl(int n, int l, float *a, float *w);
static void rftfsub(int n, float *a, int nc, float *c);
static void rftbsub(int n, float *a, int nc, float *c);


void InnoTalk_cdft(int n, int isgn, float *a, int *ip, float *w)
{
	if (n > (ip[0] << 2)) {
		makewt(n >> 2, ip, w);
	}
	if (n > 4) {
		if (isgn >= 0) {
			bitrv2(n, ip + 2, a);
			cftfsub(n, a, w);
		}
		else {
			bitrv2conj(n, ip + 2, a);
			cftbsub(n, a, w);
		}
	}
	else if (n == 4) {
		cftfsub(n, a, w);
	}
}


void InnoTalk_rdft(int n, int isgn, float *a, int *ip, float *w)
{
	int nw, nc;
	float xi;

	nw = ip[0];
	if (n > (nw << 2)) {
		nw = n >> 2;
		makewt(nw, ip, w);
	}
	nc = ip[1];
	if (n > (nc << 2)) {
		nc = n >> 2;
		makect(nc, ip, w + nw);
	}
	if (isgn >= 0) {
		if (n > 4) {
			bitrv2(n, ip + 2, a);
			cftfsub(n, a, w);
			rftfsub(n, a, nc, w + nw);
		}
		else if (n == 4) {
			cftfsub(n, a, w);
		}
		xi = a[0] - a[1];
		a[0] += a[1];
		a[1] = xi;
	}
	else {
		a[1] = 0.5f * (a[0] - a[1]);
		a[0] -= a[1];
		if (n > 4) {
			rftbsub(n, a, nc, w + nw);
			bitrv2(n, ip + 2, a);
			cftbsub(n, a, w);
		}
		else if (n == 4) {
			cftfsub(n, a, w);
		}
	}
}

/* -------- initializing routines -------- */

static void makewt(int nw, int *ip, float *w)
{
	int j, nwh;
	float delta, x, y;

	ip[0] = nw;
	ip[1] = 1;
	if (nw > 2) {
		nwh = nw >> 1;
		delta = (float)atan(1.0f) / nwh;
		w[0] = 1;
		w[1] = 0;
		w[nwh] = (float)cos(delta * nwh);
		w[nwh + 1] = w[nwh];
		if (nwh > 2) {
			for (j = 2; j < nwh; j += 2) {
				x = (float)cos(delta * j);
				y = (float)sin(delta * j);
				w[j] = x;
				w[j + 1] = y;
				w[nw - j] = y;
				w[nw - j + 1] = x;
			}
			bitrv2(nw, ip + 2, w);
		}
	}
}


static void makect(int nc, int *ip, float *c)
{
	int j, nch;
	float delta;

	ip[1] = nc;
	if (nc > 1) {
		nch = nc >> 1;
		delta = (float)atan(1.0f) / nch;
		c[0] = (float)cos(delta * nch);
		c[nch] = 0.5f * c[0];
		for (j = 1; j < nch; j++) {
			c[j] = 0.5f * (float)cos(delta * j);
			c[nc - j] = 0.5f * (float)sin(delta * j);
		}
	}
}


/* -------- child routines -------- */


static void bitrv2(int n, int *ip, float *a)
{
	int j, j1, k, k1, l, m, m2;
	float xr, xi, yr, yi;

	ip[0] = 0;
	l = n;
	m = 1;
	while ((m << 3) < l) {
		l >>= 1;
		for (j = 0; j < m; j++) {
			ip[m + j] = ip[j] + l;
		}
		m <<= 1;
	}
	m2 = 2 * m;
	if ((m << 3) == l) {
		for (k = 0; k < m; k++) {
			for (j = 0; j < k; j++) {
				j1 = 2 * j + ip[k];
				k1 = 2 * k + ip[j];
				xr = a[j1];
				xi = a[j1 + 1];
				yr = a[k1];
				yi = a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 += 2 * m2;
				xr = a[j1];
				xi = a[j1 + 1];
				yr = a[k1];
				yi = a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 -= m2;
				xr = a[j1];
				xi = a[j1 + 1];
				yr = a[k1];
				yi = a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 += 2 * m2;
				xr = a[j1];
				xi = a[j1 + 1];
				yr = a[k1];
				yi = a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
			}
			j1 = 2 * k + m2 + ip[k];
			k1 = j1 + m2;
			xr = a[j1];
			xi = a[j1 + 1];
			yr = a[k1];
			yi = a[k1 + 1];
			a[j1] = yr;
			a[j1 + 1] = yi;
			a[k1] = xr;
			a[k1 + 1] = xi;
		}
	}
	else {
		for (k = 1; k < m; k++) {
			for (j = 0; j < k; j++) {
				j1 = 2 * j + ip[k];
				k1 = 2 * k + ip[j];
				xr = a[j1];
				xi = a[j1 + 1];
				yr = a[k1];
				yi = a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 += m2;
				xr = a[j1];
				xi = a[j1 + 1];
				yr = a[k1];
				yi = a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
			}
		}
	}
}


static void bitrv2conj(int n, int *ip, float *a)
{
	int j, j1, k, k1, l, m, m2;
	float xr, xi, yr, yi;

	ip[0] = 0;
	l = n;
	m = 1;
	while ((m << 3) < l) {
		l >>= 1;
		for (j = 0; j < m; j++) {
			ip[m + j] = ip[j] + l;
		}
		m <<= 1;
	}
	m2 = 2 * m;
	if ((m << 3) == l) {
		for (k = 0; k < m; k++) {
			for (j = 0; j < k; j++) {
				j1 = 2 * j + ip[k];
				k1 = 2 * k + ip[j];
				xr = a[j1];
				xi = -a[j1 + 1];
				yr = a[k1];
				yi = -a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 += 2 * m2;
				xr = a[j1];
				xi = -a[j1 + 1];
				yr = a[k1];
				yi = -a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 -= m2;
				xr = a[j1];
				xi = -a[j1 + 1];
				yr = a[k1];
				yi = -a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 += 2 * m2;
				xr = a[j1];
				xi = -a[j1 + 1];
				yr = a[k1];
				yi = -a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
			}
			k1 = 2 * k + ip[k];
			a[k1 + 1] = -a[k1 + 1];
			j1 = k1 + m2;
			k1 = j1 + m2;
			xr = a[j1];
			xi = -a[j1 + 1];
			yr = a[k1];
			yi = -a[k1 + 1];
			a[j1] = yr;
			a[j1 + 1] = yi;
			a[k1] = xr;
			a[k1 + 1] = xi;
			k1 += m2;
			a[k1 + 1] = -a[k1 + 1];
		}
	}
	else {
		a[1] = -a[1];
		a[m2 + 1] = -a[m2 + 1];
		for (k = 1; k < m; k++) {
			for (j = 0; j < k; j++) {
				j1 = 2 * j + ip[k];
				k1 = 2 * k + ip[j];
				xr = a[j1];
				xi = -a[j1 + 1];
				yr = a[k1];
				yi = -a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
				j1 += m2;
				k1 += m2;
				xr = a[j1];
				xi = -a[j1 + 1];
				yr = a[k1];
				yi = -a[k1 + 1];
				a[j1] = yr;
				a[j1 + 1] = yi;
				a[k1] = xr;
				a[k1 + 1] = xi;
			}
			k1 = 2 * k + ip[k];
			a[k1 + 1] = -a[k1 + 1];
			a[k1 + m2 + 1] = -a[k1 + m2 + 1];
		}
	}
}


static void cftfsub(int n, float *a, float *w)
{
	int j, j1, j2, j3, l;
	float x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;

	l = 2;
	if (n > 8) {
		cft1st(n, a, w);
		l = 8;
		while ((l << 2) < n) {
			cftmdl(n, l, a, w);
			l <<= 2;
		}
	}
	if ((l << 2) == n) {
		for (j = 0; j < l; j += 2) {
			j1 = j + l;
			j2 = j1 + l;
			j3 = j2 + l;
			x0r = a[j] + a[j1];
			x0i = a[j + 1] + a[j1 + 1];
			x1r = a[j] - a[j1];
			x1i = a[j + 1] - a[j1 + 1];
			x2r = a[j2] + a[j3];
			x2i = a[j2 + 1] + a[j3 + 1];
			x3r = a[j2] - a[j3];
			x3i = a[j2 + 1] - a[j3 + 1];
			a[j] = x0r + x2r;
			a[j + 1] = x0i + x2i;
			a[j2] = x0r - x2r;
			a[j2 + 1] = x0i - x2i;
			a[j1] = x1r - x3i;
			a[j1 + 1] = x1i + x3r;
			a[j3] = x1r + x3i;
			a[j3 + 1] = x1i - x3r;
		}
	}
	else {
		for (j = 0; j < l; j += 2) {
			j1 = j + l;
			x0r = a[j] - a[j1];
			x0i = a[j + 1] - a[j1 + 1];
			a[j] += a[j1];
			a[j + 1] += a[j1 + 1];
			a[j1] = x0r;
			a[j1 + 1] = x0i;
		}
	}
}


static void cftbsub(int n, float *a, float *w)
{
	int j, j1, j2, j3, l;
	float x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;

	l = 2;
	if (n > 8) {
		cft1st(n, a, w);
		l = 8;
		while ((l << 2) < n) {
			cftmdl(n, l, a, w);
			l <<= 2;
		}
	}
	if ((l << 2) == n) {
		for (j = 0; j < l; j += 2) {
			j1 = j + l;
			j2 = j1 + l;
			j3 = j2 + l;
			x0r = a[j] + a[j1];
			x0i = -a[j + 1] - a[j1 + 1];
			x1r = a[j] - a[j1];
			x1i = -a[j + 1] + a[j1 + 1];
			x2r = a[j2] + a[j3];
			x2i = a[j2 + 1] + a[j3 + 1];
			x3r = a[j2] - a[j3];
			x3i = a[j2 + 1] - a[j3 + 1];
			a[j] = x0r + x2r;
			a[j + 1] = x0i - x2i;
			a[j2] = x0r - x2r;
			a[j2 + 1] = x0i + x2i;
			a[j1] = x1r - x3i;
			a[j1 + 1] = x1i - x3r;
			a[j3] = x1r + x3i;
			a[j3 + 1] = x1i + x3r;
		}
	}
	else {
		for (j = 0; j < l; j += 2) {
			j1 = j + l;
			x0r = a[j] - a[j1];
			x0i = -a[j + 1] + a[j1 + 1];
			a[j] += a[j1];
			a[j + 1] = -a[j + 1] - a[j1 + 1];
			a[j1] = x0r;
			a[j1 + 1] = x0i;
		}
	}
}


static void cft1st(int n, float *a, float *w)
{
	int j, k1, k2;
	float wk1r, wk1i, wk2r, wk2i, wk3r, wk3i;
	float x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;

	x0r = a[0] + a[2];
	x0i = a[1] + a[3];
	x1r = a[0] - a[2];
	x1i = a[1] - a[3];
	x2r = a[4] + a[6];
	x2i = a[5] + a[7];
	x3r = a[4] - a[6];
	x3i = a[5] - a[7];
	a[0] = x0r + x2r;
	a[1] = x0i + x2i;
	a[4] = x0r - x2r;
	a[5] = x0i - x2i;
	a[2] = x1r - x3i;
	a[3] = x1i + x3r;
	a[6] = x1r + x3i;
	a[7] = x1i - x3r;
	wk1r = w[2];
	x0r = a[8] + a[10];
	x0i = a[9] + a[11];
	x1r = a[8] - a[10];
	x1i = a[9] - a[11];
	x2r = a[12] + a[14];
	x2i = a[13] + a[15];
	x3r = a[12] - a[14];
	x3i = a[13] - a[15];
	a[8] = x0r + x2r;
	a[9] = x0i + x2i;
	a[12] = x2i - x0i;
	a[13] = x0r - x2r;
	x0r = x1r - x3i;
	x0i = x1i + x3r;
	a[10] = wk1r * (x0r - x0i);
	a[11] = wk1r * (x0r + x0i);
	x0r = x3i + x1r;
	x0i = x3r - x1i;
	a[14] = wk1r * (x0i - x0r);
	a[15] = wk1r * (x0i + x0r);
	k1 = 0;
	for (j = 16; j < n; j += 16) {
		k1 += 2;
		k2 = 2 * k1;
		wk2r = w[k1];
		wk2i = w[k1 + 1];
		wk1r = w[k2];
		wk1i = w[k2 + 1];
		wk3r = wk1r - 2 * wk2i * wk1i;
		wk3i = 2 * wk2i * wk1r - wk1i;
		x0r = a[j] + a[j + 2];
		x0i = a[j + 1] + a[j + 3];
		x1r = a[j] - a[j + 2];
		x1i = a[j + 1] - a[j + 3];
		x2r = a[j + 4] + a[j + 6];
		x2i = a[j + 5] + a[j + 7];
		x3r = a[j + 4] - a[j + 6];
		x3i = a[j + 5] - a[j + 7];
		a[j] = x0r + x2r;
		a[j + 1] = x0i + x2i;
		x0r -= x2r;
		x0i -= x2i;
		a[j + 4] = wk2r * x0r - wk2i * x0i;
		a[j + 5] = wk2r * x0i + wk2i * x0r;
		x0r = x1r - x3i;
		x0i = x1i + x3r;
		a[j + 2] = wk1r * x0r - wk1i * x0i;
		a[j + 3] = wk1r * x0i + wk1i * x0r;
		x0r = x1r + x3i;
		x0i = x1i - x3r;
		a[j + 6] = wk3r * x0r - wk3i * x0i;
		a[j + 7] = wk3r * x0i + wk3i * x0r;
		wk1r = w[k2 + 2];
		wk1i = w[k2 + 3];
		wk3r = wk1r - 2 * wk2r * wk1i;
		wk3i = 2 * wk2r * wk1r - wk1i;
		x0r = a[j + 8] + a[j + 10];
		x0i = a[j + 9] + a[j + 11];
		x1r = a[j + 8] - a[j + 10];
		x1i = a[j + 9] - a[j + 11];
		x2r = a[j + 12] + a[j + 14];
		x2i = a[j + 13] + a[j + 15];
		x3r = a[j + 12] - a[j + 14];
		x3i = a[j + 13] - a[j + 15];
		a[j + 8] = x0r + x2r;
		a[j + 9] = x0i + x2i;
		x0r -= x2r;
		x0i -= x2i;
		a[j + 12] = -wk2i * x0r - wk2r * x0i;
		a[j + 13] = -wk2i * x0i + wk2r * x0r;
		x0r = x1r - x3i;
		x0i = x1i + x3r;
		a[j + 10] = wk1r * x0r - wk1i * x0i;
		a[j + 11] = wk1r * x0i + wk1i * x0r;
		x0r = x1r + x3i;
		x0i = x1i - x3r;
		a[j + 14] = wk3r * x0r - wk3i * x0i;
		a[j + 15] = wk3r * x0i + wk3i * x0r;
	}
}


static void cftmdl(int n, int l, float *a, float *w)
{
	int j, j1, j2, j3, k, k1, k2, m, m2;
	float wk1r, wk1i, wk2r, wk2i, wk3r, wk3i;
	float x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;

	m = l << 2;
	for (j = 0; j < l; j += 2) {
		j1 = j + l;
		j2 = j1 + l;
		j3 = j2 + l;
		x0r = a[j] + a[j1];
		x0i = a[j + 1] + a[j1 + 1];
		x1r = a[j] - a[j1];
		x1i = a[j + 1] - a[j1 + 1];
		x2r = a[j2] + a[j3];
		x2i = a[j2 + 1] + a[j3 + 1];
		x3r = a[j2] - a[j3];
		x3i = a[j2 + 1] - a[j3 + 1];
		a[j] = x0r + x2r;
		a[j + 1] = x0i + x2i;
		a[j2] = x0r - x2r;
		a[j2 + 1] = x0i - x2i;
		a[j1] = x1r - x3i;
		a[j1 + 1] = x1i + x3r;
		a[j3] = x1r + x3i;
		a[j3 + 1] = x1i - x3r;
	}
	wk1r = w[2];
	for (j = m; j < l + m; j += 2) {
		j1 = j + l;
		j2 = j1 + l;
		j3 = j2 + l;
		x0r = a[j] + a[j1];
		x0i = a[j + 1] + a[j1 + 1];
		x1r = a[j] - a[j1];
		x1i = a[j + 1] - a[j1 + 1];
		x2r = a[j2] + a[j3];
		x2i = a[j2 + 1] + a[j3 + 1];
		x3r = a[j2] - a[j3];
		x3i = a[j2 + 1] - a[j3 + 1];
		a[j] = x0r + x2r;
		a[j + 1] = x0i + x2i;
		a[j2] = x2i - x0i;
		a[j2 + 1] = x0r - x2r;
		x0r = x1r - x3i;
		x0i = x1i + x3r;
		a[j1] = wk1r * (x0r - x0i);
		a[j1 + 1] = wk1r * (x0r + x0i);
		x0r = x3i + x1r;
		x0i = x3r - x1i;
		a[j3] = wk1r * (x0i - x0r);
		a[j3 + 1] = wk1r * (x0i + x0r);
	}
	k1 = 0;
	m2 = 2 * m;
	for (k = m2; k < n; k += m2) {
		k1 += 2;
		k2 = 2 * k1;
		wk2r = w[k1];
		wk2i = w[k1 + 1];
		wk1r = w[k2];
		wk1i = w[k2 + 1];
		wk3r = wk1r - 2 * wk2i * wk1i;
		wk3i = 2 * wk2i * wk1r - wk1i;
		for (j = k; j < l + k; j += 2) {
			j1 = j + l;
			j2 = j1 + l;
			j3 = j2 + l;
			x0r = a[j] + a[j1];
			x0i = a[j + 1] + a[j1 + 1];
			x1r = a[j] - a[j1];
			x1i = a[j + 1] - a[j1 + 1];
			x2r = a[j2] + a[j3];
			x2i = a[j2 + 1] + a[j3 + 1];
			x3r = a[j2] - a[j3];
			x3i = a[j2 + 1] - a[j3 + 1];
			a[j] = x0r + x2r;
			a[j + 1] = x0i + x2i;
			x0r -= x2r;
			x0i -= x2i;
			a[j2] = wk2r * x0r - wk2i * x0i;
			a[j2 + 1] = wk2r * x0i + wk2i * x0r;
			x0r = x1r - x3i;
			x0i = x1i + x3r;
			a[j1] = wk1r * x0r - wk1i * x0i;
			a[j1 + 1] = wk1r * x0i + wk1i * x0r;
			x0r = x1r + x3i;
			x0i = x1i - x3r;
			a[j3] = wk3r * x0r - wk3i * x0i;
			a[j3 + 1] = wk3r * x0i + wk3i * x0r;
		}
		wk1r = w[k2 + 2];
		wk1i = w[k2 + 3];
		wk3r = wk1r - 2 * wk2r * wk1i;
		wk3i = 2 * wk2r * wk1r - wk1i;
		for (j = k + m; j < l + (k + m); j += 2) {
			j1 = j + l;
			j2 = j1 + l;
			j3 = j2 + l;
			x0r = a[j] + a[j1];
			x0i = a[j + 1] + a[j1 + 1];
			x1r = a[j] - a[j1];
			x1i = a[j + 1] - a[j1 + 1];
			x2r = a[j2] + a[j3];
			x2i = a[j2 + 1] + a[j3 + 1];
			x3r = a[j2] - a[j3];
			x3i = a[j2 + 1] - a[j3 + 1];
			a[j] = x0r + x2r;
			a[j + 1] = x0i + x2i;
			x0r -= x2r;
			x0i -= x2i;
			a[j2] = -wk2i * x0r - wk2r * x0i;
			a[j2 + 1] = -wk2i * x0i + wk2r * x0r;
			x0r = x1r - x3i;
			x0i = x1i + x3r;
			a[j1] = wk1r * x0r - wk1i * x0i;
			a[j1 + 1] = wk1r * x0i + wk1i * x0r;
			x0r = x1r + x3i;
			x0i = x1i - x3r;
			a[j3] = wk3r * x0r - wk3i * x0i;
			a[j3 + 1] = wk3r * x0i + wk3i * x0r;
		}
	}
}


static void rftfsub(int n, float *a, int nc, float *c)
{
	int j, k, kk, ks, m;
	float wkr, wki, xr, xi, yr, yi;

	m = n >> 1;
	ks = 2 * nc / m;
	kk = 0;
	for (j = 2; j < m; j += 2) {
		k = n - j;
		kk += ks;
		wkr = 0.5f - c[nc - kk];
		wki = c[kk];
		xr = a[j] - a[k];
		xi = a[j + 1] + a[k + 1];
		yr = wkr * xr - wki * xi;
		yi = wkr * xi + wki * xr;
		a[j] -= yr;
		a[j + 1] -= yi;
		a[k] += yr;
		a[k + 1] -= yi;
	}
}


static void rftbsub(int n, float *a, int nc, float *c)
{
	int j, k, kk, ks, m;
	float wkr, wki, xr, xi, yr, yi;

	a[1] = -a[1];
	m = n >> 1;
	ks = 2 * nc / m;
	kk = 0;
	for (j = 2; j < m; j += 2) {
		k = n - j;
		kk += ks;
		wkr = 0.5f - c[nc - kk];
		wki = c[kk];
		xr = a[j] - a[k];
		xi = a[j + 1] + a[k + 1];
		yr = wkr * xr + wki * xi;
		yi = wkr * xi - wki * xr;
		a[j] -= yr;
		a[j + 1] = yi - a[j + 1];
		a[k] += yr;
		a[k + 1] = yi - a[k + 1];
	}
	a[m + 1] = -a[m + 1];
}