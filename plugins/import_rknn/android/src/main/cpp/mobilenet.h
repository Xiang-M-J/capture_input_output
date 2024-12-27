//
// Created by xmj on 2024/12/23.
//

#ifndef IMPORT_RKNN_MOBILENET_H
#define IMPORT_RKNN_MOBILENET_H

#include "rknn_api.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <sys/time.h>
#include <android/log.h>
#include <fstream>
#include <iostream>



#define LOGIM(...) __android_log_print(ANDROID_LOG_INFO, "rktest", ##__VA_ARGS__);
#define LOGEM(...) __android_log_print(ANDROID_LOG_ERROR, "rktest", ##__VA_ARGS__);

bool init_mobile_model(uint8_t *model_data, int64_t model_len);
int run_inference(uint8_t * mat);

#endif //IMPORT_RKNN_MOBILENET_H
