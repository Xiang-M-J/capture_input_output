//
// Created by xmj on 2024/12/23.
//

#ifndef IMPORT_RKNN_MODEL_H
#define IMPORT_RKNN_MODEL_H
#include "Float16.h"
#include <cstdlib>
#include <vector>
#include <cstdio>
#include <android/log.h>
#include <vector>
#include "rknn_api.h"
#include <chrono>
#include "half.hpp"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "rktest", ##__VA_ARGS__);
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "rktest", ##__VA_ARGS__);


bool init_model(uint8_t* model_data, int64_t model_len);

void destroy();

bool inference(float * mic, float *ref, float *spec);

void setFloat16();

void reset();
#endif //IMPORT_RKNN_MODEL_H
