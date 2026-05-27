LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE := libSpl2
LOCAL_C_INCLUDES := signal_processing_library.h
LOCAL_SRC_FILES := signal_processing_library.c

LOCAL_LDLIBS := -llog

include $(BUILD_SHARED_LIBRARY)
