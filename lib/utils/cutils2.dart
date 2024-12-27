import 'dart:ffi';

import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

final DynamicLibrary splLib = Platform.isAndroid ? DynamicLibrary.open("libSpl2.so") : DynamicLibrary.process();

typedef STFTFunc = Void Function(Pointer<Int16>, Pointer<Float>, Int16, Int16);
typedef ISTFTFunc = Void Function(Pointer<Float>, Pointer<Int16>, Int16, Int16);

typedef AQMFFunc = Void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int16>, Pointer<Int>, Pointer<Int>);
typedef SQMFFunc = Void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int16>, Pointer<Int>, Pointer<Int>);

typedef MICFunc = Void Function(Pointer<Int16>);
typedef RESETFunc = Void Function();

final void Function(Pointer<Int16>, Pointer<Float>, int, int) stftFunc =
    splLib.lookup<NativeFunction<STFTFunc>>("stft1").asFunction();

final void Function(Pointer<Int16>, Pointer<Float>, int, int) stft2Func =
splLib.lookup<NativeFunction<STFTFunc>>("stft2").asFunction();

final void Function(Pointer<Float>, Pointer<Int16>, int, int) istftFunc =
    splLib.lookup<NativeFunction<ISTFTFunc>>("istft").asFunction();

final void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int16>, Pointer<Int>, Pointer<Int>) aqmfFunc =
    splLib.lookup<NativeFunction<AQMFFunc>>("InnoTalkSpl_AnalysisQMF").asFunction();

final void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int16>, Pointer<Int>, Pointer<Int>) sqmfFunc =
    splLib.lookup<NativeFunction<SQMFFunc>>("InnoTalkSpl_SynthesisQMF").asFunction();

final void Function(Pointer<Int16>) micFunc = splLib.lookup<NativeFunction<MICFunc>>("get_mic1").asFunction();

final void Function() resetFunc = splLib.lookup<NativeFunction<RESETFunc>>("reset").asFunction();

List<int> mFilterState1 = List.filled(6, 0);
List<int> mFilterState2 = List.filled(6, 0);
List<int> rFilterState1 = List.filled(6, 0);
List<int> rFilterState2 = List.filled(6, 0);
List<int> sFilterState1 = List.filled(6, 0);
List<int> sFilterState2 = List.filled(6, 0);

Pointer<Float> doubleList2FloatPointer(List<double> list) {
  int s = list.length * 4;
  Pointer<Float> fp = calloc<Float>(s);
  for (var i = 0; i < list.length; i++) {
    fp[i] = list[i].toDouble();
  }
  return fp;
}

List<double> floatPointer2DoubleList(Pointer<Float> fp, int size) {
  List<double> l = List.empty(growable: true);
  for (var i = 0; i < size; i++) {
    l.add(fp[i]);
  }
  return l;
}

Pointer<Int16> intList2Int16Pointer(List<int> list) {
  int s = list.length * sizeOf<Int16>();
  Pointer<Int16> fp = calloc<Int16>(s);
  for (var i = 0; i < list.length; i++) {
    fp[i] = list[i];
  }
  return fp;
}

List<int> int16Pointer2IntList(Pointer<Int16> fp, int size) {
  List<int> l = List.empty(growable: true);
  for (var i = 0; i < size; i++) {
    l.add(fp[i]);
  }
  return l;
}

List<int> intPointer2IntList(Pointer<Int> fp, int size) {
  List<int> l = List.empty(growable: true);
  for (var i = 0; i < size; i++) {
    l.add(fp[i]);
  }
  return l;
}

Pointer<Int> intList2IntPointer(List<int> state) {
  int s = state.length * sizeOf<Int>();
  Pointer<Int> pState = calloc<Int>(s);
  for (var i = 0; i < state.length; i++) {
    pState[i] = state[i];
  }
  return pState;
}

void getMic() {
  Pointer<Int16> micPointer = calloc<Int16>(128 * 2);
  micFunc(micPointer);
  List<int> out = int16Pointer2IntList(micPointer, 128);
  print(out);
}

void resetStates() {
  resetFunc();
  resetFilterState();
}

List<double> stft2(List<int> wav, int frameSize, int frameLen, bool isMic) {
  Pointer<Int16> wavPointer = intList2Int16Pointer(wav);
  // Pointer<Float> winPointer = doubleList2FloatPointer(win);

  Pointer<Float> output = calloc<Float>((frameSize + 2) * 4);
  if (isMic){
    stftFunc(wavPointer, output, frameSize, frameLen);
  }else{
    stft2Func(wavPointer, output, frameSize, frameLen);
  }

  List<double> o = floatPointer2DoubleList(output, frameSize + 2);
  malloc.free(wavPointer);
  // malloc.free(winPointer);
  malloc.free(output);
  return o;
}

// spec [r[0], r[1], r[2], .., -i[0], -i[1]]
// output: frameLen
List<int> istft2(List<double> spec, int frameSize, int frameLen) {
  Pointer<Float> specPointer = doubleList2FloatPointer(spec);
  Pointer<Int16> output = calloc<Int16>(frameLen * 2);
  istftFunc(specPointer, output, frameSize, frameLen);
  List<int> o = int16Pointer2IntList(output, frameLen);
  malloc.free(specPointer);
  malloc.free(output);
  return o;
}

void printFilterState() {
  print(mFilterState1);
  print(mFilterState2);
}

void resetFilterState() {
  mFilterState1 = List.filled(6, 0);
  mFilterState2 = List.filled(6, 0);
  rFilterState1 = List.filled(6, 0);
  rFilterState2 = List.filled(6, 0);
  sFilterState1 = List.filled(6, 0);
  sFilterState2 = List.filled(6, 0);
}

// flag为true时为mic，flag为false时为ref
List<int> aqmf(List<int> wav, int frameSize, bool flag) {
  Pointer<Int16> wavPointer = intList2Int16Pointer(wav);
  int outputFrameSize = frameSize ~/ 2;
  Pointer<Int16> lowPointer = calloc<Int16>(outputFrameSize * sizeOf<Int16>());
  Pointer<Int16> highPointer = calloc<Int16>(outputFrameSize * sizeOf<Int16>());
  if (flag) {
    Pointer<Int> fPointer1 = intList2IntPointer(mFilterState1);
    Pointer<Int> fPointer2 = intList2IntPointer(mFilterState2);
    aqmfFunc(wavPointer, lowPointer, highPointer, fPointer1, fPointer2);
    List<int> low = int16Pointer2IntList(lowPointer, outputFrameSize);
    mFilterState1 = intPointer2IntList(fPointer1, 6);
    mFilterState2 = intPointer2IntList(fPointer2, 6);
    malloc.free(wavPointer);
    malloc.free(lowPointer);
    malloc.free(highPointer);
    malloc.free(fPointer1);
    malloc.free(fPointer2);
    return low;
  } else {
    Pointer<Int> fPointer1 = intList2IntPointer(rFilterState1);
    Pointer<Int> fPointer2 = intList2IntPointer(rFilterState2);
    aqmfFunc(wavPointer, lowPointer, highPointer, fPointer1, fPointer2);
    List<int> low = int16Pointer2IntList(lowPointer, outputFrameSize);
    rFilterState1 = intPointer2IntList(fPointer1, 6);
    rFilterState2 = intPointer2IntList(fPointer2, 6);
    malloc.free(wavPointer);
    malloc.free(lowPointer);
    malloc.free(highPointer);
    malloc.free(fPointer1);
    malloc.free(fPointer2);
    return low;
  }
}

// 合成
List<int> sqmf(List<int> low, int frameSize) {

  Pointer<Int16> lowPointer = intList2Int16Pointer(low);
  int outputFrameSize = frameSize ~/ 2;
  Pointer<Int16> wavPointer = calloc<Int16>(frameSize * sizeOf<Int16>());
  Pointer<Int16> highPointer = calloc<Int16>(outputFrameSize * sizeOf<Int16>());

  Pointer<Int> fPointer1 = intList2IntPointer(sFilterState1);
  Pointer<Int> fPointer2 = intList2IntPointer(sFilterState2);
  sqmfFunc(lowPointer, highPointer, wavPointer, fPointer1, fPointer2);
  List<int> wav = int16Pointer2IntList(wavPointer, frameSize);
  sFilterState1 = intPointer2IntList(fPointer1, 6);
  sFilterState2 = intPointer2IntList(fPointer2, 6);
  malloc.free(wavPointer);
  malloc.free(lowPointer);
  malloc.free(highPointer);
  malloc.free(fPointer1);
  malloc.free(fPointer2);
  return wav;
}

void testStft2() {
  // List<double> input = List.generate(128, (e)=> e / 128);
  // List<double> win = List.generate(128, (e) => e / 128);
  // int t1 = DateTime.now().microsecondsSinceEpoch;
  // List<double> output = stft2(input, win, 128, 64);
  // int t2 = DateTime.now().microsecondsSinceEpoch;
  // print("c: ${t2 - t1}");
  List<int> input = List.generate(64, (e) => e * 100 + 100);
  // List<double> win = List.generate(128, (e) => e / 128);
  int t1 = DateTime.now().microsecondsSinceEpoch;
  List<double> output = stft2(input, 128, 64, true);
  print(output);
  int t2 = DateTime.now().microsecondsSinceEpoch;
  print(t2 - t1);
}

void testIstft(){
  // List<int> input = List.generate(64, (e))
}

void main() {
  List<int> input = List.generate(64, (e) => e * 100 + 100);
  // List<double> win = List.generate(128, (e) => e / 128);
  int t1 = DateTime.now().microsecondsSinceEpoch;
  List<double> output = stft2(input, 128, 64, true);
  print(output);
  int t2 = DateTime.now().microsecondsSinceEpoch;
  print(t2 - t1);
}
