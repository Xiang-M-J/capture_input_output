import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'import_rknn_method_channel.dart';

abstract class ImportRknnPlatform extends PlatformInterface {
  /// Constructs a ImportRknnPlatform.
  ImportRknnPlatform() : super(token: _token);

  static final Object _token = Object();

  static ImportRknnPlatform _instance = MethodChannelImportRknn();

  /// The default instance of [ImportRknnPlatform] to use.
  ///
  /// Defaults to [MethodChannelImportRknn].
  static ImportRknnPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ImportRknnPlatform] when
  /// they register themselves.
  static set instance(ImportRknnPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> test(){
    throw UnimplementedError('test() has not been implemented.');
  }

  Future<bool?> initModel(Uint8List modelData){
    throw UnimplementedError("initModel() has not been implemented");
  }

  Future<Float32List?> inference(Float32List mic, Float32List ref){
    throw UnimplementedError("inference() has not been implemented");
  }

  Future<bool?> destroy(){
    throw UnimplementedError("destroy() has not been implemented");
  }

  Future<bool?> reset(){
    throw UnimplementedError("reset() has not been implemented");
  }

  Future<bool?> initMobileModel(Uint8List modelData){
    throw UnimplementedError("initMobileModel() has not been implemented");
  }

  Future<bool?> imgInference(Uint8List img){
    throw UnimplementedError("imgInference() has not been implemented");
  }

}
