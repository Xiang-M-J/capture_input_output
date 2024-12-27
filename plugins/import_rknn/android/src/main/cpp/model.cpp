//
// Created by xmj on 2024/12/23.
//
#include "model.h"
using namespace std::chrono;
using namespace half_float;
using namespace rknpu2;
rknn_context ctx = 0;
uint32_t n_input = 4;
uint32_t n_output = 4;
bool created = false;
rknn_tensor_attr input_attrs[4];
rknn_tensor_attr output_attrs[3];

rknn_tensor_mem *input_mems[4];
rknn_tensor_mem *output_mems[3];

rknn_input  inputs[4];

int frameSize = 1 * 2 * 1 * 257;
int stateSize = 4 * 1 * 64 * 64;

float *h = nullptr;
float *c = nullptr;


static void dump_tensor_attr(rknn_tensor_attr* attr)
{
    LOGI("  index=%d, name=%s, n_dims=%d, dims=[%d, %d, %d, %d], n_elems=%d, size=%d, fmt=%s, type=%s, qnt_type=%s, "
           "zp=%d, scale=%f\n",
           attr->index, attr->name, attr->n_dims, attr->dims[0], attr->dims[1], attr->dims[2], attr->dims[3],
           attr->n_elems, attr->size, get_format_string(attr->fmt), get_type_string(attr->type),
           get_qnt_type_string(attr->qnt_type), attr->zp, attr->scale);
}

// rknn 模型会进行量化，float32会被量化为float16
bool init_model(uint8_t *model_data, int64_t model_len) {
    int ret = rknn_init(&ctx, model_data, model_len, 0, nullptr);
    if (ret < 0){
        LOGE("rknn init fail!");
        return false;
    } else{
        LOGI("rknn init success !")
    }

    rknn_set_core_mask(ctx, RKNN_NPU_CORE_ALL);

    h = static_cast<float *>(malloc(stateSize * sizeof(float)));
    c = static_cast<float *>(malloc(stateSize * sizeof(float)));
    memset(h, 0, stateSize * sizeof(float ));
    memset(c, 0, stateSize * sizeof(float ));
    // 3. Query input/output attr.
    rknn_input_output_num io_num;
    rknn_query_cmd cmd = RKNN_QUERY_IN_OUT_NUM;

    ret = rknn_query(ctx, cmd, &io_num, sizeof(io_num));
    n_input = io_num.n_input;
    n_output = io_num.n_output;

    LOGI("n_input: %d, n_output: %d", n_input, n_output)

    LOGI("input attrs set")
    // 3.2 Query input attributes
    memset(input_attrs, 0, n_input * sizeof(rknn_tensor_attr));
    for (int i = 0; i < n_input; ++i) {
        input_attrs[i].index = i;
        cmd = RKNN_QUERY_INPUT_ATTR;
        ret = rknn_query(ctx, cmd, &(input_attrs[i]), sizeof(rknn_tensor_attr));
        if (ret < 0) {
            LOGE("rknn_query input_attrs[%d] fail!ret=%d\n", i, ret);
            return false;
        }
        dump_tensor_attr(&input_attrs[i]);
    }

    LOGI("output attrs set")
    // 3.4 Query output attributes
    memset(output_attrs, 0, n_output * sizeof(rknn_tensor_attr));
    for (int i = 0; i < n_output; ++i) {
        output_attrs[i].index = i;
        cmd = RKNN_QUERY_OUTPUT_ATTR;
        ret = rknn_query(ctx, cmd, &(output_attrs[i]), sizeof(rknn_tensor_attr));
        if (ret < 0) {
            LOGE("rknn_query output_attrs[%d] fail!ret=%d\n", i, ret);
            return false;
        }
        dump_tensor_attr(&output_attrs[i]);
    }

    LOGI("input attrs update")
    // 4.1 Update input attrs
    for (int i = 0; i < n_input; ++i) {
        input_attrs[i].index = i;
        input_attrs[i].type = RKNN_TENSOR_FLOAT16;
        if (i >= 2){
            input_attrs[i].size = stateSize * sizeof(float16);
        }else{
            input_attrs[i].size = frameSize * sizeof(float16);
        }

        input_attrs[i].fmt = RKNN_TENSOR_NHWC;

        input_attrs[i].pass_through = 0;
        dump_tensor_attr(&input_attrs[i]);
    }

    memset(inputs, 0, n_input * sizeof(rknn_input));
    for (int i = 0; i < io_num.n_input; i++) {
        inputs[i].index = i;
        inputs[i].pass_through = 0;
        inputs[i].type  = input_attrs[i].type;
        inputs[i].fmt = input_attrs[i].fmt;
//        inputs[i].buf          = input_data[i];
        inputs[i].buf = (float16 *) malloc(input_attrs[i].size);
        memset(inputs[i].buf, 0, input_attrs[i].size);
        inputs[i].size = input_attrs[i].size;
    }

//    // 4.2. Set outputs memory
//    for (int i = 0; i < n_output; ++i) {
//        output_attrs[i].index = i;
////        output_attrs[i].pass_through = 1;
//        output_mems[i] = rknn_create_mem(ctx, output_attrs[i].n_elems * sizeof(float ));
//        LOGI("output_mems: %d", output_mems[i]->size)
//        memset(output_mems[i]->virt_addr, 0, output_attrs[i].n_elems * sizeof(float ));
//        // 4.2.3 Set output buffer
//        output_attrs[i].type = RKNN_TENSOR_FLOAT32;
//        output_attrs[i].size = output_attrs[i].n_elems * sizeof(float );
//        rknn_set_io_mem(ctx, output_mems[i], &(output_attrs[i]));
//    }

    created = true;

    LOGI("rknn_init success!");
    return true;
}

void destroy() {
    LOGI("release related rknn res");
    // release io_mem resource
    for (int i = 0; i < n_input; ++i) {
        rknn_destroy_mem(ctx, input_mems[i]);
    }
    for (int i = 0; i < n_output; ++i) {
        rknn_destroy_mem(ctx, output_mems[i]);
    }
    rknn_destroy(ctx);
}
float16* float2float16(float * f32, int f16_size){
    float16* f16 = (float16*) malloc(f16_size);
    for (int i = 0; i < f16_size / 2; ++i) {
        f16[i] = float16(f32[i]);
    }
    return f16;
}

void set_input_mem(float * mem, int idx){
//    rknn_tensor_mem* rmem = rknn_create_mem(ctx, size * sizeof(float ));
//    memset(rmem->virt_addr, 0, )
//    rknn_set_io_mem(ctx, reinterpret_cast<rknn_tensor_mem *>(mem), &input_attrs[idx]);
//    float16* memf16 = malloc(inputs[idx].size);
//    void *memtmp = nullptr;
//    memtmp = malloc(inputs[idx].size);

    float16 * f16 = float2float16(mem, inputs[idx].size);
//    for (int i = 0; i < frameSize; i++){
//        LOGI("[%d] = %f", i, (float ) f16[i])
//    }
    memcpy(inputs[idx].buf, f16, inputs[idx].size);
}

void reset(){
    memset(h, 0, stateSize * sizeof(float ));
    memset(c, 0, stateSize * sizeof(float ));
}

void setFloat16(){
    float *f32 = (float *) malloc(32 * sizeof(float ));
    memset(f32, 0, sizeof(float ) * 32);
    for (int i = 0; i < 32; ++i) {
        f32[i] = i / 100.0;
    }
    for (int i = 0; i < 32; ++i) {
        LOGI("%f ", f32[i]);
    }
    float16* f16 = float2float16(f32, 32 * 2);
    for (int i = 0; i < 32; ++i) {
        LOGI("f16[%d]=%f ", i, float (f16[i]));
    }

//    free(f32);
//    free(f16);
//    free(memtmp);
//    memcpy()
}

bool
inference(float *mic, float *ref, float *spec) {
    int ret;
    bool status = false;
    if (!created){
        LOGE("run model: init model hasn't successful");
        return false;
    }
//    LOGI("h[0] = %f, ", h[0]);
//    auto start_time = system_clock::now();
//    LOGI("set input")
    set_input_mem(mic, 0);
    set_input_mem(ref, 1);
    set_input_mem(h, 2);
    set_input_mem(c, 3);
//    float16 * f16 = (float16*) inputs[0].buf;
//    for (int i = 0; i < frameSize; ++i) {
//        LOGI("inputs[0].buf[%d] = %f", i, (float ) f16[i]);
//    }
    rknn_inputs_set(ctx, n_input, inputs);
//    auto diff = std::chrono::duration_cast<std::chrono::microseconds>(system_clock::now()- start_time).count();
//    LOGI("set input cost time: %f", diff / 1000.0);
//    LOGI("set input end")
    // 运行程序


//    start_time = system_clock::now();
    ret = rknn_run(ctx, nullptr);
//    LOGI("run end")
//    diff = std::chrono::duration_cast<std::chrono::microseconds>(system_clock::now()- start_time).count();
//    LOGI("run model cost time: %f", diff / 1000.0);

//    start_time = system_clock::now();
    rknn_output outputs[n_output];
    memset(outputs, 0, n_output * sizeof(rknn_output));
    for (uint32_t i = 0; i < n_output; ++i) {
        outputs[i].want_float  = 1;
        outputs[i].index       = i;
        outputs[i].is_prealloc = 0;
    }
    ret = rknn_outputs_get(ctx, n_output, outputs, nullptr);
//    LOGI("get outputs end")


//    LOGI("outputs[0].size = %d, outputs[1].size = %d, outputs[2].size = %d", outputs[0].size, outputs[1].size, outputs[2].size)

//    float *specf32 = (float *)outputs[0].buf;
//    float *hof32 = (float *) outputs[1].buf;
//    float *cof32 = (float *) outputs[2].buf;
//    for (int i = 0; i < 100; ++i) {
//        LOGI("ho[%d] = %f", i, specf32[i]);
//    }
//    LOGI("outputs[0].size=%d", outputs[0].size);
    memcpy(spec, outputs[0].buf, outputs[0].size);
//    memcpy(w, outputs[1].buf, outputs[1].size);
    memcpy(h, outputs[1].buf, outputs[1].size);
    memcpy(c, outputs[2].buf, outputs[2].size);

//    for (int i = 0; i < outputs[0].size / 4; ++i) {
//        LOGI("spec[%d] = %f", i, spec[i]);
//    }

//    diff = std::chrono::duration_cast<std::chrono::microseconds>(system_clock::now()- start_time).count();
//    LOGI("get and copy output cost time: %f", diff / 1000.0);

//    LOGI("output copy end")
//    memcpy(w, output_mems[1]->virt_addr, output_attrs[1].n_elems * sizeof(float ));
//    memcpy(ho, output_mems[2]->virt_addr, output_attrs[2].n_elems * sizeof(float ));
//    memcpy(co, output_mems[3]->virt_addr, output_attrs[3].n_elems * sizeof(float ));
    return true;
}
