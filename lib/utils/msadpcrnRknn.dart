

import 'dart:math';

import 'package:capture_input_ouput/utils/cutils2.dart';
import 'package:capture_input_ouput/utils/type_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:import_rknn/import_rknn.dart';
import 'package:onnxruntime/onnxruntime.dart';


int stateLength = 64;

enum FrameMode{
  mic,
  ref;
}
class MsaDpcrnRknn{
  ImportRknn? rknnEnv1;
  // ImportRknn? rknnEnv2;
  bool isInitialed = false;
  // 先取256个点，
  int frameSize = 512;
  int hopSize = 256;
  int sampleSize = 256;
  int freqDim = 0;

  final stopWatch = Stopwatch();

  List<List<List<double>>> state0 = List<List<List<double>>>.filled(4, List<List<double>>.filled(stateLength, List.filled(64, 0.0)));
  List<List<List<double>>> state1 = List<List<List<double>>>.filled(4, List<List<double>>.filled(stateLength, List.filled(64, 0.0)));

  MsaDpcrnRknn();

  release() {

    rknnEnv1?.destroy();
    rknnEnv1 = null;

    // rknnEnv2?.destroy();
    // rknnEnv2 = null;
  }

  void init(){
    rknnEnv1 = ImportRknn();
    // rknnEnv2 = ImportRknn();
  }


  Future<bool> initModelByBuffer(Uint8List bytes ) async{

    final status = await rknnEnv1?.initModel(bytes);
    if (status != null){
      if(status){
        isInitialed = true;
        freqDim = frameSize ~/ 2 + 1;
        return status;
      }else{
        return false;
      }
    }else{
      return false;
    }
  }

  void reset(){
    state0 = List<List<List<double>>>.filled(4, List<List<double>>.filled(stateLength, List.filled(64, 0.0)));
    state1 = List<List<List<double>>>.filled(4, List<List<double>>.filled(stateLength, List.filled(64, 0.0)));
    resetStates();
    rknnEnv1?.reset();
  }

  Float32List specReshape(List<double> data){
    // N H W C 格式 [1, 1, 257, 2]
    List<double> spec = [];
    List<double> real = data.sublist(0, freqDim);
    List<double> imag = data.sublist(freqDim, 2 * freqDim).map((e) => -1 * e).toList();
    for(var i = 0; i < freqDim; i++){
      spec.add(real[i]);
      spec.add(imag[i]);
    }

    return Float32List.fromList(spec);
  }

  List<double> specRevReshape(List<double> data){

    List<double> fullData = [];

    fullData.addAll(data.sublist(0, freqDim));
    fullData.addAll(data.sublist(freqDim, 2*freqDim).map((e) => -1 * e).toList());

    return fullData;
  }

  List<int> dqmf(List<int> frame, bool flag){
    List<int> low = aqmf(frame, frameSize, flag);
    // List<double> wav = intList2doubleList(low);
    return low;
  }

  Float32List dstft(List<int> low, FrameMode mode){
    if (mode == FrameMode.mic){
      List<double> feature = stft2(low, frameSize, hopSize, true);
      Float32List spec = specReshape(feature);
      return spec;
    }else{
      List<double> feature = stft2(low, frameSize, hopSize, false);
      Float32List spec = specReshape(feature);
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

  // Float32List stateReshape(List<List<List<double>>> s){
  //   List<double> state = [];
  //   for(var i = 0; i < 4; i++){
  //     for(var j = 0; j < stateLength; j++){
  //       state.addAll(s[i][j]);
  //     }
  //   }
  //   return Float32List.fromList(state);
  // }

  // List<List<List<double>>> stateRevReShape(List<double> out){
  //   List<List<List<double>>> state = [];
  //   for(var i = 0; i < 4; i++){
  //     List<List<double>> ste = [];
  //     for (var j = 0; j < stateLength; j++){
  //       int idx = i * stateLength + j;
  //       ste.add(out.sublist(idx * 64, idx * 64 + 64));
  //     }
  //     state.add(ste);
  //   }
  //   return state;
  // }

  Future<List<double>?> predictMultiFrames2(List<List<int>> frames) async {
    int numFrames = frames[0].length ~/ sampleSize;

    List<double> wav = [];
    for(var i = 0; i < numFrames; i++){
      List<int> micFrame = frames[0].sublist(i * hopSize, (i + 1) * hopSize);
      List<int> refFrame = frames[1].sublist(i * hopSize, (i + 1) * hopSize);
      // List<int> micLow = aqmf(micFrame, frameSize, true);
      // List<int> refLow = aqmf(refFrame, frameSize, false);
      // stopWatch.start();
      Float32List micSpec = dstft(micFrame, FrameMode.mic);
      Float32List refSpec = dstft(refFrame, FrameMode.ref);
      // stopWatch.stop();
      // print( "elapsedMicroseconds: ${stopWatch.elapsedMicroseconds / 1000}" );
      // stopWatch.reset();
      // Float32List state0f = stateReshape(state0);
      // Float32List state1f = stateReshape(state1);
      // final inputs = {'speech': inputOrt, "in_cache0": cache0,"in_cache1": cache1,"in_cache2": cache2,"in_cache3": cache3, };

      // stopWatch.start();
      final outputs = await rknnEnv1?.inference(micSpec, refSpec);
      // stopWatch.stop();
      // print("elapsedMicroseconds: ${stopWatch.elapsedMicroseconds / 1000}");
      // stopWatch.reset();
      /// Output probability & update h,c recursively
      if (outputs == null){
        return null;
      }

      List<double> feats = List<double>.from(outputs);
      // List<double> ho = List<double>.from(outputs['ho']);
      // List<double> co = List<double>.from(outputs['co']);

      // state0 = stateRevReShape(ho);
      // state1 = stateRevReShape(co);
      // List<double> feats = complexApplyMask(micSpec, mask);
      List<double> spec = specRevReshape(feats);
      List<int> lowFrame = istft2(spec, frameSize, hopSize);
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