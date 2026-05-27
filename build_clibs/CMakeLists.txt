# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(stft_qmf_library VERSION 0.0.1 LANGUAGES C)

add_library(stft_qmf SHARED
  "signal_processing_library.c"
)

set_target_properties(stft_qmf PROPERTIES
  PUBLIC_HEADER signal_processing_library.h
  OUTPUT_NAME "stft_qmf"
)

target_compile_definitions(stft_qmf PUBLIC DART_SHARED_LIB)
