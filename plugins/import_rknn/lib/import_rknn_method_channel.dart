
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'import_rknn_platform_interface.dart';

/// An implementation of [ImportRknnPlatform] that uses method channels.
class MethodChannelImportRknn extends ImportRknnPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('import_rknn');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<String?> test() async {
    // TODO: implement test
    final info = await methodChannel.invokeMethod<String>("test");
    return info;
  }

  @override
  Future<bool?> initModel(Uint8List modelData) async {

    final status = await methodChannel.invokeMethod<bool>("initModel", {"modelData": modelData, "modelLength": modelData.lengthInBytes});
    return status;
  }

  @override
  Future<Float32List?> inference(Float32List mic, Float32List ref) async {
    final data = await methodChannel.invokeMethod<Float32List>("inference", {
      "mic": mic,
      "ref": ref,
    });
    return data;
  }

  @override
  Future<bool?> destroy() async {
    final status = await methodChannel.invokeMethod<bool>("destroy");
    return status;
  }

  @override
  Future<bool?> reset() async {
    final status = await methodChannel.invokeMethod<bool>("reset");
    return status;
  }

  @override
  Future<bool?> initMobileModel(Uint8List modelData) async {
    final status = await methodChannel.invokeMethod<bool>("initMobileNet", {"modelData": modelData});
    return status;
  }

  @override
  Future<bool?> imgInference(Uint8List img) async {
    final status = await methodChannel.invokeMethod<bool>("runInference", {"img": img});
    return status;
  }
}
