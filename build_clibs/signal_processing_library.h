#ifndef INNOTALK_SPL_SIGNAL_PROCESSING_LIBRARY_H_
#define INNOTALK_SPL_SIGNAL_PROCESSING_LIBRARY_H_
#include <string.h>

typedef signed char         int8_t;
typedef signed short        int16_t;
typedef signed int          int32_t;
typedef unsigned char       uint8_t;
typedef unsigned short      uint16_t;
typedef unsigned int        uint32_t; 

#define  N48 384    //for 48k samples
#define  N16 128    //for 48k samples

typedef struct tag_IIR_State_DSPLIB_480
{
	float w00[N48 + 4];  //indata1
	float w01[N48 + 4];  //r1
	float w10[N48 + 4];  //indata2
	float w11[N48 + 4];  //r2

}IIR_State_DSPLIB_480;


// Macros specific for the fixed point implementation
#define INNOTALK_SPL_WORD16_MAX       32767
#define INNOTALK_SPL_WORD16_MIN       -32768
#define INNOTALK_SPL_WORD32_MAX       (int32_t)0x7fffffff
#define INNOTALK_SPL_WORD32_MIN       (int32_t)0x80000000
#define INNOTALK_SPL_MAX_LPC_ORDER    14
#define INNOTALK_SPL_MAX_SEED_USED    0x80000000L
#define INNOTALK_SPL_MIN(A, B)        (A < B ? A : B)  // Get min value
#define INNOTALK_SPL_MAX(A, B)        (A > B ? A : B)  // Get max value
// TODO(kma/bjorn): For the next two macros, investigate how to correct the code
// for inputs of a = INNOTALK_SPL_WORD16_MIN or INNOTALK_SPL_WORD32_MIN.
#define INNOTALK_SPL_ABS_W16(a) \
    (((int16_t)a >= 0) ? ((int16_t)a) : -((int16_t)a))
#define INNOTALK_SPL_ABS_W32(a) \
    (((int32_t)a >= 0) ? ((int32_t)a) : -((int32_t)a))

#ifdef INNOTALK_ARCH_LITTLE_ENDIAN
#define INNOTALK_SPL_GET_BYTE(a, nr)  (((int8_t *)a)[nr])
#define INNOTALK_SPL_SET_BYTE(d_ptr, val, index) \
    (((int8_t *)d_ptr)[index] = (val))
#else
#define INNOTALK_SPL_GET_BYTE(a, nr) \
    ((((int16_t *)a)[nr >> 1]) >> (((nr + 1) & 0x1) * 8) & 0x00ff)
#define INNOTALK_SPL_SET_BYTE(d_ptr, val, index) \
    ((int16_t *)d_ptr)[index >> 1] = \
    ((((int16_t *)d_ptr)[index >> 1]) \
    & (0x00ff << (8 * ((index) & 0x1)))) | (val << (8 * ((index + 1) & 0x1)))
#endif

#define INNOTALK_SPL_MUL(a, b) \
    ((int32_t) ((int32_t)(a) * (int32_t)(b)))
#define INNOTALK_SPL_UMUL(a, b) \
    ((uint32_t) ((uint32_t)(a) * (uint32_t)(b)))
#define INNOTALK_SPL_UMUL_RSFT16(a, b) \
    ((uint32_t) ((uint32_t)(a) * (uint32_t)(b)) >> 16)
#define INNOTALK_SPL_UMUL_16_16(a, b) \
    ((uint32_t) (uint16_t)(a) * (uint16_t)(b))
#define INNOTALK_SPL_UMUL_16_16_RSFT16(a, b) \
    (((uint32_t) (uint16_t)(a) * (uint16_t)(b)) >> 16)
#define INNOTALK_SPL_UMUL_32_16(a, b) \
    ((uint32_t) ((uint32_t)(a) * (uint16_t)(b)))
#define INNOTALK_SPL_UMUL_32_16_RSFT16(a, b) \
    ((uint32_t) ((uint32_t)(a) * (uint16_t)(b)) >> 16)
#define INNOTALK_SPL_MUL_16_U16(a, b) \
    ((int32_t)(int16_t)(a) * (uint16_t)(b))
#define INNOTALK_SPL_DIV(a, b) \
    ((int32_t) ((int32_t)(a) / (int32_t)(b)))
#define INNOTALK_SPL_UDIV(a, b) \
    ((uint32_t) ((uint32_t)(a) / (uint32_t)(b)))

#ifndef INNOTALK_ARCH_ARM_V7
// For ARMv7 platforms, these are inline functions in spl_inl_armv7.h
#ifndef MIPS32_LE
// For MIPS platforms, these are inline functions in spl_inl_mips.h
#define INNOTALK_SPL_MUL_16_16(a, b) \
    ((int32_t) (((int16_t)(a)) * ((int16_t)(b))))
#define INNOTALK_SPL_MUL_16_32_RSFT16(a, b) \
    (INNOTALK_SPL_MUL_16_16(a, b >> 16) \
     + ((INNOTALK_SPL_MUL_16_16(a, (b & 0xffff) >> 1) + 0x4000) >> 15))
#define INNOTALK_SPL_MUL_32_32_RSFT32(a32a, a32b, b32) \
    ((int32_t)(INNOTALK_SPL_MUL_16_32_RSFT16(a32a, b32) \
    + (INNOTALK_SPL_MUL_16_32_RSFT16(a32b, b32) >> 16)))
#define INNOTALK_SPL_MUL_32_32_RSFT32BI(a32, b32) \
    ((int32_t)(INNOTALK_SPL_MUL_16_32_RSFT16(( \
    (int16_t)(a32 >> 16)), b32) + \
    (INNOTALK_SPL_MUL_16_32_RSFT16(( \
    (int16_t)((a32 & 0x0000FFFF) >> 1)), b32) >> 15)))
#endif
#endif

#define INNOTALK_SPL_MUL_16_32_RSFT11(a, b) \
    ((INNOTALK_SPL_MUL_16_16(a, (b) >> 16) << 5) \
    + (((INNOTALK_SPL_MUL_16_U16(a, (uint16_t)(b)) >> 1) + 0x0200) >> 10))
#define INNOTALK_SPL_MUL_16_32_RSFT14(a, b) \
    ((INNOTALK_SPL_MUL_16_16(a, (b) >> 16) << 2) \
    + (((INNOTALK_SPL_MUL_16_U16(a, (uint16_t)(b)) >> 1) + 0x1000) >> 13))
#define INNOTALK_SPL_MUL_16_32_RSFT15(a, b) \
    ((INNOTALK_SPL_MUL_16_16(a, (b) >> 16) << 1) \
    + (((INNOTALK_SPL_MUL_16_U16(a, (uint16_t)(b)) >> 1) + 0x2000) >> 14))

#define INNOTALK_SPL_MUL_16_16_RSFT(a, b, c) \
    (INNOTALK_SPL_MUL_16_16(a, b) >> (c))

#define INNOTALK_SPL_MUL_16_16_RSFT_WITH_ROUND(a, b, c) \
    ((INNOTALK_SPL_MUL_16_16(a, b) + ((int32_t) \
                                  (((int32_t)1) << ((c) - 1)))) >> (c))
#define INNOTALK_SPL_MUL_16_16_RSFT_WITH_FIXROUND(a, b) \
    ((INNOTALK_SPL_MUL_16_16(a, b) + ((int32_t) (1 << 14))) >> 15)

// C + the 32 most significant bits of A * B
#define INNOTALK_SPL_SCALEDIFF32(A, B, C) \
    (C + (B >> 16) * A + (((uint32_t)(0x0000FFFF & B) * A) >> 16))

#define INNOTALK_SPL_ADD_SAT_W32(a, b)    InnoTalkSpl_AddSatW32(a, b)
#define INNOTALK_SPL_SAT(a, b, c)         (b > a ? a : b < c ? c : b)
#define INNOTALK_SPL_MUL_32_16(a, b)      ((a) * (b))

#define INNOTALK_SPL_SUB_SAT_W32(a, b)    InnoTalkSpl_SubSatW32(a, b)
#define INNOTALK_SPL_ADD_SAT_W16(a, b)    InnoTalkSpl_AddSatW16(a, b)
#define INNOTALK_SPL_SUB_SAT_W16(a, b)    InnoTalkSpl_SubSatW16(a, b)

// We cannot do casting here due to signed/unsigned problem
#define INNOTALK_SPL_IS_NEG(a)            ((a) & 0x80000000)
// Shifting with negative numbers allowed
// Positive means left shift
#define INNOTALK_SPL_SHIFT_W16(x, c) \
    (((c) >= 0) ? ((x) << (c)) : ((x) >> (-(c))))
#define INNOTALK_SPL_SHIFT_W32(x, c) \
    (((c) >= 0) ? ((x) << (c)) : ((x) >> (-(c))))

// Shifting with negative numbers not allowed
// We cannot do casting here due to signed/unsigned problem
#define INNOTALK_SPL_RSHIFT_W16(x, c)     ((x) >> (c))
#define INNOTALK_SPL_LSHIFT_W16(x, c)     ((x) << (c))
#define INNOTALK_SPL_RSHIFT_W32(x, c)     ((x) >> (c))
#define INNOTALK_SPL_LSHIFT_W32(x, c)     ((x) << (c))

#define INNOTALK_SPL_RSHIFT_U16(x, c)     ((uint16_t)(x) >> (c))
#define INNOTALK_SPL_LSHIFT_U16(x, c)     ((uint16_t)(x) << (c))
#define INNOTALK_SPL_RSHIFT_U32(x, c)     ((uint32_t)(x) >> (c))
#define INNOTALK_SPL_LSHIFT_U32(x, c)     ((uint32_t)(x) << (c))

#define INNOTALK_SPL_VNEW(t, n)           (t *) malloc (sizeof (t) * (n))
#define INNOTALK_SPL_FREE                 free

#define INNOTALK_SPL_RAND(a) \
    ((int16_t)(INNOTALK_SPL_MUL_16_16_RSFT((a), 18816, 7) & 0x00007fff))

#define INNOTALK_SPL_MEMCPY_W8(v1, v2, length) \
  memcpy(v1, v2, (length) * sizeof(char))
#define INNOTALK_SPL_MEMCPY_W16(v1, v2, length) \
  memcpy(v1, v2, (length) * sizeof(int16_t))

#define INNOTALK_SPL_MEMMOVE_W16(v1, v2, length) \
  memmove(v1, v2, (length) * sizeof(int16_t))

static __inline int16_t InnoTalkSpl_SatW32ToW16(int32_t value32) {
	int16_t out16 = (int16_t)value32;

	if (value32 > 32767)
		out16 = 32767;
	else if (value32 < -32768)
		out16 = -32768;

	return out16;
}

static __inline int16_t InnoTalkSpl_AddSatW16(int16_t a, int16_t b) {
	return InnoTalkSpl_SatW32ToW16((int32_t)a + (int32_t)b);
}

static __inline int16_t InnoTalkSpl_SubSatW16(int16_t var1, int16_t var2) {
	return InnoTalkSpl_SatW32ToW16((int32_t)var1 - (int32_t)var2);
}

static __inline int16_t InnoTalkSpl_GetSizeInBits(uint32_t n) {
	int16_t bits;

	if (0xFFFF0000 & n) {
		bits = 16;
	}
	else {
		bits = 0;
	}
	if (0x0000FF00 & (n >> bits)) bits += 8;
	if (0x000000F0 & (n >> bits)) bits += 4;
	if (0x0000000C & (n >> bits)) bits += 2;
	if (0x00000002 & (n >> bits)) bits += 1;
	if (0x00000001 & (n >> bits)) bits += 1;

	return bits;
}

static __inline int InnoTalkSpl_NormW32(int32_t a) {
	int zeros;

	if (a == 0) {
		return 0;
	}
	else if (a < 0) {
		a = ~a;
	}

	if (!(0xFFFF8000 & a)) {
		zeros = 16;
	}
	else {
		zeros = 0;
	}
	if (!(0xFF800000 & (a << zeros))) zeros += 8;
	if (!(0xF8000000 & (a << zeros))) zeros += 4;
	if (!(0xE0000000 & (a << zeros))) zeros += 2;
	if (!(0xC0000000 & (a << zeros))) zeros += 1;

	return zeros;
}

static __inline int InnoTalkSpl_NormU32(uint32_t a) {
	int zeros;

	if (a == 0) return 0;

	if (!(0xFFFF0000 & a)) {
		zeros = 16;
	}
	else {
		zeros = 0;
	}
	if (!(0xFF000000 & (a << zeros))) zeros += 8;
	if (!(0xF0000000 & (a << zeros))) zeros += 4;
	if (!(0xC0000000 & (a << zeros))) zeros += 2;
	if (!(0x80000000 & (a << zeros))) zeros += 1;

	return zeros;
}

static __inline int InnoTalkSpl_NormW16(int16_t a) {
	int zeros;

	if (a == 0) {
		return 0;
	}
	else if (a < 0) {
		a = ~a;
	}

	if (!(0xFF80 & a)) {
		zeros = 8;
	}
	else {
		zeros = 0;
	}
	if (!(0xF800 & (a << zeros))) zeros += 4;
	if (!(0xE000 & (a << zeros))) zeros += 2;
	if (!(0xC000 & (a << zeros))) zeros += 1;

	return zeros;
}

static __inline int32_t InnoTalk_MulAccumW16(int16_t a, int16_t b, int32_t c) {
	return (a * b + c);
}

static __inline int32_t InnoTalkSpl_AddSatW32(int32_t l_var1, int32_t l_var2) {
	int32_t l_sum;

	// Perform long addition
	l_sum = l_var1 + l_var2;

	if (l_var1 < 0) {  // Check for underflow.
		if ((l_var2 < 0) && (l_sum >= 0)) {
			l_sum = (int32_t)0x80000000;
		}
	}
	else {  // Check for overflow.
		if ((l_var2 > 0) && (l_sum < 0)) {
			l_sum = (int32_t)0x7FFFFFFF;
		}
	}

	return l_sum;
}

static __inline int32_t InnoTalkSpl_SubSatW32(int32_t l_var1, int32_t l_var2) {
	int32_t l_diff;

	// Perform subtraction.
	l_diff = l_var1 - l_var2;

	if (l_var1 < 0) {  // Check for underflow.
		if ((l_var2 > 0) && (l_diff > 0)) {
			l_diff = (int32_t)0x80000000;
		}
	}
	else {  // Check for overflow.
		if ((l_var2 < 0) && (l_diff < 0)) {
			l_diff = (int32_t)0x7FFFFFFF;
		}
	}

	return l_diff;
}


#ifdef __cplusplus
extern "C" {
#endif
	void LRY_test_48_16N(short* in_data, short* out_data, IIR_State_DSPLIB_480* state);
	void LRY_test_16_48N(short* in_data, short* out_data, IIR_State_DSPLIB_480* state);

void InnoTalkSpl_MemSetW32(int32_t *ptr, int32_t set_value, int length);

int32_t InnoTalkSpl_Sqrt(int32_t value);

uint32_t InnoTalkSpl_DivU32U16(uint32_t num, uint16_t den);
int32_t InnoTalkSpl_DivW32W16(int32_t num, int16_t den);
int16_t InnoTalkSpl_DivW32W16ResW16(int32_t num, int16_t den);
int32_t InnoTalkSpl_DivResultInQ31(int32_t num, int32_t den);
int32_t InnoTalkSpl_DivW32HiLow(int32_t num, int16_t den_hi, int16_t den_low);
// End: Divisions.

int32_t InnoTalkSpl_DotProductWithScale(const int16_t* vector1,
                                      const int16_t* vector2,
                                      int length,
                                      int scaling);

void InnoTalkSpl_DownsampleBy2(const int16_t* in, int16_t len,
                             int16_t* out, int32_t* filtState);

void InnoTalkSpl_UpsampleBy2(const int16_t* in, int16_t len,
                           int16_t* out, int32_t* filtState);

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
void get_mic1(short* out);
void InnoTalk_rdft(int, int, float *, int *, float *);
void InnoTalk_cdft(int, int, float *, int *, float *);
void SignalIDFT(const float *in, short *out, const short FFTLen, const short FrameLen);
void SignalDFT(const short *in, float *out, const short FFTLen, const short FrameLen);
void SignalDFT2(const short* in, float* out, const short FFTLen, const short FrameLen);
void reset();
void printMic();
void stft1(const short* in, float* out, const short FFTLen, const short FrameLen);
void stft2(const short* in, float* out, const short FFTLen, const short FrameLen);
void istft(const float* in, short* out, const short FFTLen, const short FrameLen);
#ifdef __cplusplus
}
#endif
#endif

