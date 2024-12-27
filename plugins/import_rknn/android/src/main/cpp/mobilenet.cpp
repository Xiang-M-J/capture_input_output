//
// Created by xmj on 2024/12/23.
//
// Copyright (c) 2021 by Rockchip Electronics Co., Ltd. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/*-------------------------------------------
                Includes
-------------------------------------------*/
#include "mobilenet.h"

/*-------------------------------------------
                  Functions
-------------------------------------------*/
rknn_context ctxM = 0;
uint32_t n_inputM = 4;
uint32_t n_outputM = 4;


static void dump_tensor_attr(rknn_tensor_attr* attr)
{
    LOGIM("  index=%d, name=%s, n_dims=%d, dims=[%d, %d, %d, %d], n_elems=%d, size=%d, fmt=%s, type=%s, qnt_type=%s, "
           "zp=%d, scale=%f\n",
           attr->index, attr->name, attr->n_dims, attr->dims[0], attr->dims[1], attr->dims[2], attr->dims[3],
           attr->n_elems, attr->size, get_format_string(attr->fmt), get_type_string(attr->type),
           get_qnt_type_string(attr->qnt_type), attr->zp, attr->scale);
}

bool init_mobile_model(uint8_t *model_data, int64_t model_len) {
    int ret = rknn_init(&ctxM, model_data, model_len, 0, nullptr);
    if (ret < 0){
        LOGEM("rknn init fail!");
        return false;
    } else{
        LOGIM("rknn init success !")
    }

    // 3. Query input/output attr.
    rknn_input_output_num io_num;
    rknn_query_cmd cmd = RKNN_QUERY_IN_OUT_NUM;

    ret = rknn_query(ctxM, cmd, &io_num, sizeof(io_num));
    n_inputM = io_num.n_input;
    n_outputM = io_num.n_output;

    LOGIM("n_input: %d, n_output: %d", n_inputM, n_outputM)


    return true;
}

static int rknn_GetTop(float* pfProb, float* pfMaxProb, uint32_t* pMaxClass, uint32_t outputCount, uint32_t topNum)
{
    uint32_t i, j;

#define MAX_TOP_NUM 20
    if (topNum > MAX_TOP_NUM)
        return 0;

    memset(pfMaxProb, 0, sizeof(float) * topNum);
    memset(pMaxClass, 0xff, sizeof(float) * topNum);

    for (j = 0; j < topNum; j++) {
        for (i = 0; i < outputCount; i++) {
            if ((i == *(pMaxClass + 0)) || (i == *(pMaxClass + 1)) || (i == *(pMaxClass + 2)) || (i == *(pMaxClass + 3)) ||
                (i == *(pMaxClass + 4))) {
                continue;
            }

            if (pfProb[i] > *(pfMaxProb + j)) {
                *(pfMaxProb + j) = pfProb[i];
                *(pMaxClass + j) = i;
            }
        }
    }

    return 1;
}

/*-------------------------------------------
                  Main Function
-------------------------------------------*/
int run_inference(uint8_t * mat)
{
    const int MODEL_IN_WIDTH    = 224;
    const int MODEL_IN_HEIGHT   = 224;
    const int MODEL_IN_CHANNELS = 3;

    int ret;
    int model_len = 0;
    unsigned char* model;


    LOGIM("input tensors:\n");
    rknn_tensor_attr input_attrs[n_inputM];
    memset(input_attrs, 0, sizeof(input_attrs));
    for (int i = 0; i < n_inputM; i++) {
        input_attrs[i].index = i;
        ret = rknn_query(ctxM, RKNN_QUERY_INPUT_ATTR, &(input_attrs[i]), sizeof(rknn_tensor_attr));
        if (ret != RKNN_SUCC) {
            LOGEM("rknn_query fail! ret=%d\n", ret);
            return -1;
        }
        dump_tensor_attr(&(input_attrs[i]));
    }

    LOGIM("output tensors:\n");
    rknn_tensor_attr output_attrs[n_outputM];
    memset(output_attrs, 0, sizeof(output_attrs));
    for (int i = 0; i < n_outputM; i++) {
        output_attrs[i].index = i;
        ret = rknn_query(ctxM, RKNN_QUERY_OUTPUT_ATTR, &(output_attrs[i]), sizeof(rknn_tensor_attr));
        if (ret != RKNN_SUCC) {
            LOGEM("rknn_query fail! ret=%d\n", ret);
            return -1;
        }
        dump_tensor_attr(&(output_attrs[i]));
    }

    // Set Input Data
    rknn_input inputs[1];
    memset(inputs, 0, sizeof(inputs));
    inputs[0].index = 0;
    inputs[0].type  = RKNN_TENSOR_UINT8;
    inputs[0].size  = 224 * 224 * 3 * sizeof(uint8_t);
    inputs[0].fmt   = RKNN_TENSOR_NHWC;
    inputs[0].buf   = mat;

    ret = rknn_inputs_set(ctxM, n_inputM, inputs);
    if (ret < 0) {
        LOGEM("rknn_input_set fail! ret=%d\n", ret);
        return -1;
    }

    // Run
    LOGIM("rknn_run\n");
    ret = rknn_run(ctxM, nullptr);
    if (ret < 0) {
        LOGEM("rknn_run fail! ret=%d\n", ret);
        return -1;
    }

    // Get Output
    rknn_output outputs[1];
    memset(outputs, 0, sizeof(outputs));
    outputs[0].want_float = 1;
    ret = rknn_outputs_get(ctxM, 1, outputs, nullptr);
    if (ret < 0) {
        LOGEM("rknn_outputs_get fail! ret=%d\n", ret);
        return -1;
    }

    // Post Process
    for (int i = 0; i < n_outputM; i++) {
        uint32_t MaxClass[5];
        float    fMaxProb[5];
        float*   buffer = (float*)outputs[i].buf;
        uint32_t sz     = outputs[i].size / 4;

        rknn_GetTop(buffer, fMaxProb, MaxClass, sz, 5);

        printf(" --- Top5 ---\n");
        for (int i = 0; i < 5; i++) {
            LOGIM("%3d: %8.6f\n", MaxClass[i], fMaxProb[i]);
        }
    }

    LOGIM("release begin")
    // Release rknn_outputs
    rknn_outputs_release(ctxM, 1, outputs);
    LOGIM("release end")
    // Release
    if (ctxM > 0)
    {
        rknn_destroy(ctxM);
    }
    LOGIM("destroy end")

    return 0;
}
