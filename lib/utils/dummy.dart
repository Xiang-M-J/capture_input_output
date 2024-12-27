// import 'dart:typed_data';
//
// import 'package:flutter/foundation.dart';
// import 'package:flutter/services.dart';
// import 'package:onnxruntime/onnxruntime.dart';
//
// class Model{
//   OrtSessionOptions? _sessionOptions;
//   OrtSession? _session;
//   bool isInitialed = false;
//
//   var input2 = OrtValueTensor.createTensorWithDataList(Float32List.fromList(List.filled(64, 0.0)));
//
//   Model();
//
//   // 在 dispose() 时调用
//   release() {
//     _sessionOptions?.release();
//     _sessionOptions = null;
//     _session?.release();
//     _session = null;
//   }
//
//   // 在 initState() 时调用
//   Future<bool> initModel() async {
//     _sessionOptions = OrtSessionOptions()
//       ..setInterOpNumThreads(1)
//       ..setIntraOpNumThreads(1)
//       ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
//     final rawAssetFile = await rootBundle.load("assets/model.onnx");
//     final bytes = rawAssetFile.buffer.asUint8List();
//     _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
//     return true;
//   }
//
//   // 重置状态
//   void reset(){
//     input2 = OrtValueTensor.createTensorWithDataList(Float32List.fromList(List.filled(64, 0.0)));
//   }
//
//   // 异步预测
//   Future<List<double>?> predictASync(List<List<int>> frames) {
//     return compute(predict, frames);
//   }
//
//   List<double>? predict(List<List<int>> frames) {
//
//     final input1 = OrtValueTensor.createTensorWithDataList(
//        Float32List.fromList(List.filled(64, 0.0)) , [1, 64]);
//
//     final runOptions = OrtRunOptions();
//     final inputs = {"input1": input1, "input2": input2};
//     final List<OrtValue?>? outputs;
//
//     outputs = _session?.run(runOptions, inputs);
//     input1.release();
//     runOptions.release();
//
//     List<double> output1 = (outputs?[0]?.value as List<List<double>>)[0];  // [2, 1, freqDim]
//     input2 = OrtValueTensor.createTensorWithDataList(outputs?[1]?.value as List<double>);
//
//     outputs?.forEach((element) {
//       element?.release();
//     });
//
//     return output1;
//   }
// }