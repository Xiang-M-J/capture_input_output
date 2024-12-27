

import 'dart:math';

import 'package:capture_input_ouput/utils/type_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'cutils.dart';
int stateLength = 17;

enum FrameMode{
  mic,
  ref;
}
class MsaDpcrn{
  OrtSessionOptions? _sessionOptions;
  OrtSession? _session;
  bool isInitialed = false;
  // 先取256个点，
  int frameSize = 128;
  int hopSize = 64;
  int sampleSize = 128;
  int freqDim = 0;
  double pi = 3.14159265358979323846;

  final stopWatch = Stopwatch();
  List<double> win = [];
  List<double>? refCacheLow;
  List<double>? micCacheLow;
  List<List<List<List<double>>>> state0 = List<List<List<List<double>>>>.filled(4, List<List<List<double>>>.filled(1, List<List<double>>.filled(stateLength, List.filled(64, 0.0))));
  List<List<List<List<double>>>> state1 = List<List<List<List<double>>>>.filled(4, List<List<List<double>>>.filled(1, List<List<double>>.filled(stateLength, List.filled(64, 0.0))));

  MsaDpcrn();

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
    resetFilterState();
  }

  Future<List<double>?> predictASync(List<List<int>> frames) async {
    return compute(predict, frames);
  }

  List<double> complexApplyMask(List<Float32List> input, List<List<List<double>>> mask){
    List<double> feat = List<double>.empty(growable: true);
    double rt = 0;
    double it = 0;
    for(var i = 0; i< freqDim; i++){
      rt = input[0][i] * mask[0][0][i] - input[1][i] * mask[1][0][i];
      it = input[0][i] * mask[1][0][i] + input[1][i] * mask[0][0][i];
      feat.add(rt);
      feat.add(it);
    }

    return feat;
  }

  List<Float32List> specReshape(List<double> data){
    List<Float32List> spec = [];
    List<double> real = [];
    List<double> imag = [];
    for(var i = 0; i< freqDim * 2; i+=2){
      real.add(data[i]);
      imag.add(data[i+1]);
    }
    spec.add(Float32List.fromList(real));
    spec.add(Float32List.fromList(imag));
    return spec;
  }

  List<double> specRevReshape(List<double> data){

    List<double> fullData = List<double>.empty(growable: true);

    fullData.addAll(data);

    // 添加共轭部分
    for (var i = 1; i < freqDim - 1; i++){
      fullData.add(data[2 * i]);
      fullData.add(-data[2 * i + 1]);
    }
    // List<double> conData

    return fullData;
  }

  List<double> specRevReshape2(List<List<List<double>>> data){

    List<double> fullData = List.filled(2 * frameSize, 0.0);
    fullData[0] = data[0][0][0];
    fullData[1] = data[1][0][0];
    fullData[2*freqDim - 2] = data[0][0][freqDim - 1];
    fullData[2*freqDim - 1] = data[1][0][freqDim - 1];

    for (var i = 1; i < freqDim - 1; i++){
      fullData[2 * i] = data[0][0][i];
      fullData[2 * i + 1] = data[1][0][i];
      fullData[2 * ( 2 * freqDim - 2 - i)] = data[0][0][i];
      fullData[2 * (2 * freqDim - 2 - i) + 1] = - data[1][0][i];
    }

    return fullData;
  }

  List<double> dqmf(List<int> frame, bool flag){
    List<int> low = qmf(frame, frameSize, flag);
    List<double> wav = intList2doubleList(low);
    return wav;
  }

  // low 为 64点，和cachelow一起拼成128点
  List<Float32List> dstft(List<double> low, FrameMode mode){
    List<double> temp = [];
    if (mode == FrameMode.mic){
      temp.addAll(micCacheLow!);
      temp.addAll(low);
      micCacheLow = low;
    }else if(mode == FrameMode.ref){
      temp.addAll(refCacheLow!);
      temp.addAll(low);
      refCacheLow = low;
    }
    List<double> feature = stft(temp, win, frameSize);
    List<Float32List> spec = specReshape(feature);
    return spec;
  }

  List<Float32List> frame2Spec(List<int> frame, bool flag){
    List<int> low = qmf(frame, frameSize, flag);

    List<double> wav = intList2doubleList(low);
    List<double> feature = stft(wav, win, frameSize);
    List<Float32List> spec = specReshape(feature);
    return spec;
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

  List<double>? predict(List<List<int>> frames) {
    // 小于 1 ms
    // stopWatch.start();

    List<Float32List> micSpec = frame2Spec(frames[0], true);
    List<Float32List> refSpec = frame2Spec(frames[1], false);
    // stopWatch.stop();
    // print("frame time: ${stopWatch.elapsedMilliseconds}");
    // stopWatch.reset();
    // stopWatch.start();
    final micOrt = OrtValueTensor.createTensorWithDataList(
        micSpec, [1, 2, 1, freqDim]);
    final refOrt = OrtValueTensor.createTensorWithDataList(refSpec, [1, 2, 1, freqDim]);
    final state0Ort = OrtValueTensor.createTensorWithDataList(convertDoubleTensor(state0), [4, 1, stateLength, 64]);
    final state1Ort = OrtValueTensor.createTensorWithDataList(convertDoubleTensor(state1), [4, 1, stateLength, 64]);
    final runOptions = OrtRunOptions();
    // final inputs = {'speech': inputOrt, "in_cache0": cache0,"in_cache1": cache1,"in_cache2": cache2,"in_cache3": cache3, };
    final inputs = {"mic": micOrt, "ref": refOrt, "h": state0Ort, "c": state1Ort};
    final List<OrtValue?>? outputs;
    // stopWatch.stop();
    // print("init time: ${stopWatch.elapsedMilliseconds}");
    // stopWatch.reset();

    // stopWatch.start();
    outputs = _session?.run(runOptions, inputs);

    // stopWatch.stop();
    // print("run time: ${stopWatch.elapsedMilliseconds}");
    // stopWatch.reset();

    // stopWatch.start();
    micOrt.release();
    refOrt.release();
    state0Ort.release();
    state1Ort.release();

    runOptions.release();

    /// Output probability & update h,c recursively
    if (outputs == null){
      return null;
    }
    List<List<List<double>>> mask = (outputs[0]?.value as List<List<List<List<double>>>>)[0];  // [2, 1, freqDim]
    state0 = outputs[1]?.value as List<List<List<List<double>>>>;
    state1 = outputs[2]?.value as List<List<List<List<double>>>>;
    outputs.forEach((element) {
      element?.release();
    });

    // stopWatch.stop();
    // print("release time: ${stopWatch.elapsedMilliseconds}");
    // stopWatch.reset();

    // stopWatch.start();
    List<double> feats = complexApplyMask(micSpec, mask);
    List<double> spec = specRevReshape(feats);
    List<double> wav = istft(spec, win, frameSize);
    for(var i = 0; i<wav.length; i++){
      if (wav[i] > 1.0) wav[i] = 1.0;
      if (wav[i] < -1.0) wav[i] = -1.0;
    }

    // stopWatch.stop();
    // print("istft time: ${stopWatch.elapsedMilliseconds}");
    // stopWatch.reset();

    return wav;
  }

  List<double>? predictMultiFrames(List<List<int>> frames) {
    int numFrames = frames[0].length ~/ 128 - 1;
    List<double> wav = [];
    for(var i = 0; i < numFrames; i++){
      List<int> micFrame = frames[0].sublist(i * 128, i * 128 + 256);
      List<int> refFrame = frames[1].sublist(i * 128, i * 128 + 256);
      List<Float32List> micSpec = frame2Spec(micFrame, true);
      List<Float32List> refSpec = frame2Spec(refFrame, false);

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
      state0 = outputs[2]?.value as List<List<List<List<double>>>>;
      state1 = outputs[3]?.value as List<List<List<List<double>>>>;
      for (var element in outputs) {
        element?.release();
      }

      // List<double> feats = complexApplyMask(micSpec, mask);
      List<double> spec = specRevReshape2(feats);
      List<double> wavFrame = istft(spec, win, frameSize);
      for (var i = 0; i < wavFrame.length ~/ 2; i++){
        if (wavFrame[i] > 1.0){
          wav.add(1.0);
        }else if (wavFrame[i] < -1.0){
          wav.add(-1.0);
        }else{
          wav.add(wavFrame[i]);
        }
      }
    }
    return wav;
  }

  List<double>? predictMultiFrames2(List<List<int>> frames) {
    int numFrames = frames[0].length ~/ sampleSize;

    // 第一次处理时，设置缓存
    if (refCacheLow == null || micCacheLow == null){
      // 如果只有128个点，那就将缓存帧设为0，否则取第1帧作为缓存
      if (numFrames == 1){
        refCacheLow = List<double>.filled(64, 0.0);
        micCacheLow = List<double>.filled(64, 0.0);
      }
      else{
        micCacheLow = dqmf(frames[0].sublist(0, sampleSize), true);
        refCacheLow = dqmf(frames[1].sublist(0, sampleSize), false);
        frames[0].removeRange(0, sampleSize);
        frames[1].removeRange(0, sampleSize);
        numFrames -= 1;
      }
    }

    List<double> wav = [];
    for(var i = 0; i < numFrames; i++){
      List<int> micFrame = frames[0].sublist(i * 128, (i + 1) * 128);
      List<int> refFrame = frames[1].sublist(i * 128, (i + 1) * 128);
      List<double> micLow = dqmf(micFrame, true);
      List<double> refLow = dqmf(refFrame, false);

      List<Float32List> micSpec = dstft(micLow, FrameMode.mic);
      List<Float32List> refSpec = dstft(refLow, FrameMode.ref);

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
      state0 = outputs[2]?.value as List<List<List<List<double>>>>;
      state1 = outputs[3]?.value as List<List<List<List<double>>>>;
      for (var element in outputs) {
        element?.release();
      }

      // List<double> feats = complexApplyMask(micSpec, mask);
      List<double> spec = specRevReshape2(feats);
      List<double> wavFrame = istft(spec, win, frameSize);
      for (var i = 0; i < wavFrame.length ~/ 2; i++){
        if (wavFrame[i] > 1.0){
          wav.add(1.0);
        }else if (wavFrame[i] < -1.0){
          wav.add(-1.0);
        }else{
          wav.add(wavFrame[i]);
        }
      }
    }
    return wav;
  }
  List<double>? testPredictMultiFrames() {
    int numFrames = 7;
    List<double> wav = [];
    List<double> micFrames = List.generate(512, (i) => (i + 32) / 512);
    List<double> refFrames = List.generate(512, (i) => i / 512);
    for(var i = 0; i < numFrames; i++){
      List<double> micFrame = micFrames.sublist(i * 64, i * 64 + 128);
      List<double> refFrame = refFrames.sublist(i * 64, i * 64 + 128);
      List<Float32List> micSpec = specReshape(stft(micFrame, win, frameSize));
      List<Float32List> refSpec = specReshape(stft(refFrame, win, frameSize));

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
      state0 = outputs[2]?.value as List<List<List<List<double>>>>;
      state1 = outputs[3]?.value as List<List<List<List<double>>>>;
      for (var element in outputs) {
        element?.release();
      }

      // List<double> feats = complexApplyMask(micSpec, mask);
      List<double> spec = specRevReshape2(feats);
      List<double> wavFrame = istft(spec, win, frameSize);
      for (var i = 0; i < wavFrame.length ~/ 2; i++){
        if (wavFrame[i] > 1.0){
          wav.add(1.0);
        }else if (wavFrame[i] < -1.0){
          wav.add(-1.0);
        }else{
          wav.add(wavFrame[i]);
        }
      }
    }
    return wav;
  }
}