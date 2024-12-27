
import 'dart:typed_data';

import 'import_rknn_platform_interface.dart';

class ImportRknn {
  Future<String?> getPlatformVersion() {
    return ImportRknnPlatform.instance.getPlatformVersion();
  }

  Future<String?> test(){
    return ImportRknnPlatform.instance.test();
  }

  Future<bool?> initModel(Uint8List modelData){
    return ImportRknnPlatform.instance.initModel(modelData);
  }

  Future<bool?> reset(){
    return ImportRknnPlatform.instance.reset();
  }



  Future<Float32List?> inference(Float32List mic, Float32List ref){
    // mic ref: NHWC [1, 1, 65, 2]
    // h c: NHWC [4 16 64 1]
    // spec, w: N C H W [1 2 1 65]
    // ho, co: N C H W [4 1 16 64]
    return ImportRknnPlatform.instance.inference(mic, ref);
  }

  Future<bool?> destroy(){
    return ImportRknnPlatform.instance.destroy();
  }

  // Future<bool?> initMobileModel(Uint8List modelData){
  //   return ImportRknnPlatform.instance.initMobileModel(modelData);
  // }
  //
  // Future<bool?> imgInference(Uint8List img){
  //   return ImportRknnPlatform.instance.imgInference(img);
  // }
}
