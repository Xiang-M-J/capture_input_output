

import 'dart:math';

import 'package:capture_input_ouput/utils/cutils2.dart';
import 'package:capture_input_ouput/utils/type_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

int stateLength = 64;

enum FrameMode{
  mic,
  ref;
}
class MsaDpcrn2{
  OrtSessionOptions? _sessionOptions;
  OrtSession? _session;
  bool isInitialed = false;
  // 先取256个点，
  int frameSize = 512;
  int hopSize = 256;
  int sampleSize = 256;
  int freqDim = 0;
  double pi = 3.14159265358979323846;

  final stopWatch = Stopwatch();
  List<double> win = [];
  List<double>? refCacheLow;
  List<double>? micCacheLow;
  List<List<List<List<double>>>> state0 = List<List<List<List<double>>>>.filled(4, List<List<List<double>>>.filled(1, List<List<double>>.filled(stateLength, List.filled(64, 0.0))));
  List<List<List<List<double>>>> state1 = List<List<List<List<double>>>>.filled(4, List<List<List<double>>>.filled(1, List<List<double>>.filled(stateLength, List.filled(64, 0.0))));

  MsaDpcrn2();

  release() {
    refCacheLow?.clear();
    micCacheLow?.clear();
    refCacheLow = null;
    micCacheLow = null;
    _sessionOptions?.release();
    _sessionOptions = null;
    _session?.release();
    _session = null;
  }

  Future<bool> initModelByBuffer(Uint8List bytes ) async{
    _sessionOptions = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(1)
      ..appendCPUProvider(CPUFlags.useNone)
      ..appendNnapiProvider(NnapiFlags.useFp16)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

    _session = OrtSession.fromBuffer(bytes, _sessionOptions!);

    for(var i = 0; i< frameSize;i++){
      win.add(sqrt(0.5 * (1 - cos(2 * pi * i / (frameSize)))));
    }
    isInitialed = true;
    freqDim = frameSize ~/ 2 + 1;
    return true;
  }

  Future<bool> initModel() async {
    _sessionOptions = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    // const assetFileName = 'assets/models/fsmn_vad.onnx';
    final rawAssetFile = await rootBundle.load("assets/msa_dpcrn.onnx");
    final bytes = rawAssetFile.buffer.asUint8List();
    _session = OrtSession.fromBuffer(bytes, _sessionOptions!);

    for(var i = 0; i< frameSize;i++){
      win.add((sqrt(0.5 * (1 - cos(2 * pi * i / (frameSize))))));
    }
    isInitialed = true;
    freqDim = frameSize ~/ 2 + 1;
    return true;
  }

  void reset(){
    refCacheLow?.clear();
    micCacheLow?.clear();
    refCacheLow = null;
    micCacheLow = null;
    state0 = List<List<List<List<double>>>>.filled(4, List<List<List<double>>>.filled(1, List<List<double>>.filled(stateLength, List.filled(64, 0.0))));
    state1 = List<List<List<List<double>>>>.filled(4, List<List<List<double>>>.filled(1, List<List<double>>.filled(stateLength, List.filled(64, 0.0))));
    resetStates();
  }

  List<Float32List> specReshape(List<double> data){
    List<Float32List> spec = [];
    List<double> real = data.sublist(0, freqDim);
    List<double> imag = data.sublist(freqDim, 2*freqDim).map((e) => -1 * e).toList();

    spec.add(Float32List.fromList(real));
    spec.add(Float32List.fromList(imag));
    return spec;
  }

  List<double> specRevReshape(List<List<List<double>>> data){

    List<double> fullData = [];

    fullData.addAll(data[0][0]);
    fullData.addAll(data[1][0].map((e)=> -1 * e).toList());

    return fullData;
  }

  List<int> dqmf(List<int> frame, bool flag){
    List<int> low = aqmf(frame, frameSize, flag);
    // List<double> wav = intList2doubleList(low);
    return low;
  }

  // low 为 64点，和cachelow一起拼成128点
  List<Float32List> dstft(List<int> low, FrameMode mode){
    if (mode == FrameMode.mic){
      List<double> feature = stft2(low, frameSize, hopSize, true);
      List<Float32List> spec = specReshape(feature);
      return spec;
    }else{
      List<double> feature = stft2(low, frameSize, hopSize, false);
      List<Float32List> spec = specReshape(feature);
      return spec;
    }
  }


  List<List<List<Float32List>>> convertDoubleTensor(List<List<List<List<double>>>> tensor){
    List<List<List<Float32List>>> data = [];
    for(var i = 0; i < 4; i++){
      List<Float32List> t = [];
      for (var j = 0; j < stateLength; j++){
        t.add(Float32List.fromList(tensor[i][0][j]));
      }
      data.add([t]);
    }
    return data;
  }


  List<double>? predictMultiFrames2(List<List<int>> frames) {
    int numFrames = frames[0].length ~/ sampleSize;

    List<double> wav = [];
    for(var i = 0; i < numFrames; i++){
      List<int> micFrame = frames[0].sublist(i * hopSize, (i + 1) * hopSize);
      List<int> refFrame = frames[1].sublist(i * hopSize, (i + 1) * hopSize);
      // List<int> micLow = aqmf(micFrame, frameSize, true);
      // List<int> refLow = aqmf(refFrame, frameSize, false);

      List<Float32List> micSpec = dstft(micFrame, FrameMode.mic);
      List<Float32List> refSpec = dstft(refFrame, FrameMode.ref);

      final micOrt = OrtValueTensor.createTensorWithDataList(
          micSpec, [1, 2, 1, freqDim]);
      final refOrt = OrtValueTensor.createTensorWithDataList(refSpec, [1, 2, 1, freqDim]);
      final state0Ort = OrtValueTensor.createTensorWithDataList(convertDoubleTensor(state0), [4, 1, stateLength, 64]);
      final state1Ort = OrtValueTensor.createTensorWithDataList(convertDoubleTensor(state1), [4, 1, stateLength, 64]);
      final runOptions = OrtRunOptions();
      // final inputs = {'speech': inputOrt, "in_cache0": cache0,"in_cache1": cache1,"in_cache2": cache2,"in_cache3": cache3, };
      final inputs = {"mic": micOrt, "ref": refOrt, "h": state0Ort, "c": state1Ort};
      final List<OrtValue?>? outputs;

      outputs = _session?.run(runOptions, inputs);

      micOrt.release();
      refOrt.release();
      state0Ort.release();
      state1Ort.release();

      runOptions.release();

      /// Output probability & update h,c recursively
      if (outputs == null){
        return null;
      }
      List<List<List<double>>> feats = (outputs[0]?.value as List<List<List<List<double>>>>)[0];  // [2, 1, freqDim]
      state0 = outputs[1]?.value as List<List<List<List<double>>>>;
      state1 = outputs[2]?.value as List<List<List<List<double>>>>;
      for (var element in outputs) {
        element?.release();
      }

      // List<double> feats = complexApplyMask(micSpec, mask);
      List<double> spec = specRevReshape(feats);
      List<int> lowFrame = istft2(spec, frameSize, hopSize);
      // print(lowFrame[0]);
      // List<int> wavFrame = sqmf(lowFrame, 128);
      for (var i = 0; i < lowFrame.length; i++){
        double w = lowFrame[i] * 0.000030517578125;
        if (w > 1.0){
          wav.add(1.0);
        }else if (w < -1.0){
          wav.add(-1.0);
        }else{
          wav.add(w);
        }
      }
    }
    return wav;
  }
  // List<double>? testPredictMultiFrames() {
  //   int numFrames = 7;
  //   List<double> wav = [];
  //   List<double> micFrames = List.generate(512, (i) => (i + 32) / 512);
  //   List<double> refFrames = List.generate(512, (i) => i / 512);
  //   for(var i = 0; i < numFrames; i++){
  //     List<double> micFrame = micFrames.sublist(i * 64, i * 64 + 128);
  //     List<double> refFrame = refFrames.sublist(i * 64, i * 64 + 128);
  //     List<Float32List> micSpec = specReshape(stft2(micFrame, win, frameSize));
  //     List<Float32List> refSpec = specReshape(stft2(refFrame, win, frameSize));
  //
  //     final micOrt = OrtValueTensor.createTensorWithDataList(
  //         micSpec, [1, 2, 1, freqDim]);
  //     final refOrt = OrtValueTensor.createTensorWithDataList(refSpec, [1, 2, 1, freqDim]);
  //     final state0Ort = OrtValueTensor.createTensorWithDataList(convertDoubleTensor(state0), [4, 1, stateLength, 64]);
  //     final state1Ort = OrtValueTensor.createTensorWithDataList(convertDoubleTensor(state1), [4, 1, stateLength, 64]);
  //     final runOptions = OrtRunOptions();
  //     // final inputs = {'speech': inputOrt, "in_cache0": cache0,"in_cache1": cache1,"in_cache2": cache2,"in_cache3": cache3, };
  //     final inputs = {"mic": micOrt, "ref": refOrt, "h": state0Ort, "c": state1Ort};
  //     final List<OrtValue?>? outputs;
  //
  //     outputs = _session?.run(runOptions, inputs);
  //
  //     micOrt.release();
  //     refOrt.release();
  //     state0Ort.release();
  //     state1Ort.release();
  //
  //     runOptions.release();
  //
  //     /// Output probability & update h,c recursively
  //     if (outputs == null){
  //       return null;
  //     }
  //     List<List<List<double>>> feats = (outputs[0]?.value as List<List<List<List<double>>>>)[0];  // [2, 1, freqDim]
  //     state0 = outputs[2]?.value as List<List<List<List<double>>>>;
  //     state1 = outputs[3]?.value as List<List<List<List<double>>>>;
  //     for (var element in outputs) {
  //       element?.release();
  //     }
  //
  //     // List<double> feats = complexApplyMask(micSpec, mask);
  //     List<double> spec = specRevReshape2(feats);
  //     List<double> wavFrame = istft(spec, win, frameSize);
  //     for (var i = 0; i < wavFrame.length ~/ 2; i++){
  //       if (wavFrame[i] > 1.0){
  //         wav.add(1.0);
  //       }else if (wavFrame[i] < -1.0){
  //         wav.add(-1.0);
  //       }else{
  //         wav.add(wavFrame[i]);
  //       }
  //     }
  //   }
  //   return wav;
  // }
}