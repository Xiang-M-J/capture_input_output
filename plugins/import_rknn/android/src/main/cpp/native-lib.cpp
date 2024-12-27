#include <jni.h>
#include <string>
#include "rknn_api.h"
#include "model.h"
//#include "mobilenet.h"

using namespace std::chrono;


extern "C"
JNIEXPORT jstring JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_stringFromJNI(JNIEnv *env, jobject thiz) {
    std::string hello = "Hello from C++";
    std::string rknn = std::to_string(RKNN_SUCC);
    return env->NewStringUTF(rknn.c_str());
}


extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_initModel(JNIEnv *env, jobject thiz,
                                                         jbyteArray model_data,
                                                         jint model_length) {
//    void *model = malloc(model_length);
    uint32_t model_len = env->GetArrayLength(model_data);
    LOGI("model length: %d", model_len)
    jbyte* byteArray = env->GetByteArrayElements(model_data, nullptr);

    uint8_t * u8_model_data = new uint8_t [model_len];
    memcpy(u8_model_data, byteArray, model_len);
    env->ReleaseByteArrayElements(model_data, byteArray, JNI_ABORT);
//    env->GetByteArrayRegion(model_data, 0, model_len, reinterpret_cast<jbyte *>(*u8_model_data));
    return init_model(u8_model_data, model_len);
}

extern "C"
JNIEXPORT jobject JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_destroy(JNIEnv *env, jobject thiz) {
    destroy();
    return nullptr;
}


extern "C"
JNIEXPORT jint JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_inference(JNIEnv *env, jobject thiz, jfloatArray mic,
                                                         jfloatArray ref, jfloatArray spec) {
//    auto start_time = system_clock::now();
    jboolean inputCopy = JNI_FALSE;
    jboolean outputCopy = JNI_FALSE;

    jfloat * const jmic = env->GetFloatArrayElements(mic, &inputCopy);
    jfloat * const jref = env->GetFloatArrayElements(ref, &inputCopy);
//    jfloat * const jh = env->GetFloatArrayElements(h, &inputCopy);
//    jfloat * const jc = env->GetFloatArrayElements(c, &inputCopy);

    jfloat * const jspec = env->GetFloatArrayElements(spec, &outputCopy);
//    jfloat * const jw = env->GetFloatArrayElements(w, &outputCopy);
//    jfloat * const jho = env->GetFloatArrayElements(ho, &outputCopy);
//    jfloat * const jco = env->GetFloatArrayElements(co, &outputCopy);

    inference(jmic, jref, jspec);

    env->ReleaseFloatArrayElements(mic, jmic, 0);
    env->ReleaseFloatArrayElements(ref, jref, 0);
//    for (int i = 0; i < 10; ++i) {
//        LOGI("jspec[%d] = %f", i, jspec[i]);
//    }
//    env->ReleaseFloatArrayElements(h, jh, 0);
//    env->ReleaseFloatArrayElements(c, jc, 0);
//    auto diff = std::chrono::duration_cast<std::chrono::microseconds>(system_clock::now()- start_time).count();
//    LOGI("C total cost time: %f", diff / 1000.0);
    return 0;
}


//extern "C"
//JNIEXPORT jboolean JNICALL
//Java_com_example_import_1rknn_ImportRknnPlugin_initMobileModel(JNIEnv *env, jobject thiz,
//                                                               jbyteArray model_data) {
//    uint32_t model_len = env->GetArrayLength(model_data);
//    LOGIM("model length: %d", model_len)
//    jbyte* byteArray = env->GetByteArrayElements(model_data, nullptr);
//
//    uint8_t * u8_model_data = new uint8_t [model_len];
//    memcpy(u8_model_data, byteArray, model_len);
//    env->ReleaseByteArrayElements(model_data, byteArray, JNI_ABORT);
////    env->GetByteArrayRegion(model_data, 0, model_len, reinterpret_cast<jbyte *>(*u8_model_data));
//    return init_mobile_model(u8_model_data, model_len);
//}
//extern "C"
//JNIEXPORT jboolean JNICALL
//Java_com_example_import_1rknn_ImportRknnPlugin_runInference(JNIEnv *env, jobject thiz,
//                                                            jbyteArray img_data) {
//    uint32_t model_len = env->GetArrayLength(img_data);
//    LOGIM("model length: %d", model_len)
//    jbyte* byteArray = env->GetByteArrayElements(img_data, nullptr);
//
//    uint8_t * u8_img_data = new uint8_t [model_len];
//    memcpy(u8_img_data, byteArray, model_len);
//    env->ReleaseByteArrayElements(img_data, byteArray, JNI_ABORT);
//    run_inference(u8_img_data);
//    return true;
//}

extern "C"
JNIEXPORT jobject JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_setFloat16(JNIEnv *env, jobject thiz) {
    setFloat16();
    return nullptr;
}
extern "C"
JNIEXPORT jobject JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_reset(JNIEnv *env, jobject thiz) {
    reset();
    return nullptr;
}
extern "C"
JNIEXPORT jfloatArray JNICALL
Java_com_example_import_1rknn_ImportRknnPlugin_inferenceWithOutput(JNIEnv *env, jobject thiz,
                                                                   jfloatArray mic,
                                                                   jfloatArray ref) {
    jboolean inputCopy = JNI_FALSE;
    jboolean outputCopy = JNI_FALSE;

    jfloat * const jmic = env->GetFloatArrayElements(mic, &inputCopy);
    jfloat * const jref = env->GetFloatArrayElements(ref, &inputCopy);
//    jfloat * const jh = env->GetFloatArrayElements(h, &inputCopy);
//    jfloat * const jc = env->GetFloatArrayElements(c, &inputCopy);
    int frameSize = 2 * 257;

    float *spec = (float *) malloc(frameSize * sizeof(float ));
//    jfloat * const jw = env->GetFloatArrayElements(w, &outputCopy);
//    jfloat * const jho = env->GetFloatArrayElements(ho, &outputCopy);
//    jfloat * const jco = env->GetFloatArrayElements(co, &outputCopy);

    inference(jmic, jref, spec);

    env->ReleaseFloatArrayElements(mic, jmic, 0);
    env->ReleaseFloatArrayElements(ref, jref, 0);
    jfloatArray jspec = env->NewFloatArray(frameSize);
    env->SetFloatArrayRegion(jspec, 0, frameSize, spec);
    return jspec;
}