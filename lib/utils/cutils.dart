import 'dart:ffi';

import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';


final DynamicLibrary splLib = Platform.isAndroid ? DynamicLibrary.open("libSpl.so") : DynamicLibrary.process();

typedef STFTFunc = Void Function(Pointer<Float>, Pointer<Float>, Pointer<Float>, Int32);

typedef QMFFunc = Void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int>, Pointer<Int>);

final void Function(Pointer<Float>, Pointer<Float>, Pointer<Float>, int) stftFunc =
    splLib.lookup<NativeFunction<STFTFunc>>("stft").asFunction();
final void Function(Pointer<Float>, Pointer<Float>, Pointer<Float>, int) istftFunc =
    splLib.lookup<NativeFunction<STFTFunc>>("istft").asFunction();

final void Function(Pointer<Int16>, Pointer<Int16>, Pointer<Int>, Pointer<Int>) qmfFunc =
    splLib.lookup<NativeFunction<QMFFunc>>("InnoTalkSpl_AnalysisQMF").asFunction();


List<int> mFilterState1 = List.filled(6, 0);
List<int> mFilterState2 = List.filled(6, 0);
List<int> rFilterState1 = List.filled(6, 0);
List<int> rFilterState2 = List.filled(6, 0);

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

List<double> stft(List<double> wav, List<double> win, int frameSize) {
  Pointer<Float> wavPointer = doubleList2FloatPointer(wav);
  Pointer<Float> winPointer = doubleList2FloatPointer(win);

  Pointer<Float> output = calloc<Float>(frameSize * 4 * 2);
  stftFunc(wavPointer, output, winPointer, frameSize);
  List<double> o = floatPointer2DoubleList(output, frameSize + 2);
  malloc.free(wavPointer);
  malloc.free(winPointer);
  malloc.free(output);
  return o;
}

List<double> istft(
  List<double> spec,
  List<double> win,
  int frameSize,
) {
  Pointer<Float> specPointer = doubleList2FloatPointer(spec);
  Pointer<Float> winPointer = doubleList2FloatPointer(win);
  Pointer<Float> output = calloc<Float>(frameSize * 4);
  istftFunc(specPointer, output, winPointer, frameSize);
  List<double> o = floatPointer2DoubleList(output, frameSize);
  malloc.free(specPointer);
  malloc.free(winPointer);
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
}

// flag为true时为mic，flag为false时为ref
List<int> qmf(List<int> wav, int frameSize, bool flag) {
  Pointer<Int16> wavPointer = intList2Int16Pointer(wav);
  int outputFrameSize = frameSize ~/ 2;
  Pointer<Int16> lowPointer = calloc<Int16>(outputFrameSize * sizeOf<Int16>());
  if (flag) {
    Pointer<Int> fPointer1 = intList2IntPointer(mFilterState1);
    Pointer<Int> fPointer2 = intList2IntPointer(mFilterState2);
    qmfFunc(wavPointer, lowPointer, fPointer1, fPointer2);
    List<int> low = int16Pointer2IntList(lowPointer, outputFrameSize);
    mFilterState1 = intPointer2IntList(fPointer1, 6);
    mFilterState2 = intPointer2IntList(fPointer2, 6);
    malloc.free(wavPointer);
    malloc.free(lowPointer);
    malloc.free(fPointer1);
    malloc.free(fPointer2);
    return low;
  } else {
    Pointer<Int> fPointer1 = intList2IntPointer(rFilterState1);
    Pointer<Int> fPointer2 = intList2IntPointer(rFilterState2);
    qmfFunc(wavPointer, lowPointer, fPointer1, fPointer2);
    List<int> low = int16Pointer2IntList(lowPointer, outputFrameSize);
    rFilterState1 = intPointer2IntList(fPointer1, 6);
    rFilterState2 = intPointer2IntList(fPointer2, 6);
    malloc.free(wavPointer);
    malloc.free(lowPointer);
    malloc.free(fPointer1);
    malloc.free(fPointer2);
    return low;
  }
}

void testStft(){
  List<double> input = List.generate(128, (e)=> e / 128);
  List<double> win = List.generate(128, (e) => e / 128);
  int t1 = DateTime.now().microsecondsSinceEpoch;
  List<double> output = stft(input, win, 128);
  int t2 = DateTime.now().microsecondsSinceEpoch;
  print("c: ${t2 - t1}");
}


void main(){
  List<double> input = List.generate(128, (e)=> e / 128);
  List<double> win = List.generate(128, (e) => e / 128);
  int t1 = DateTime.now().microsecondsSinceEpoch;
  List<double> output = stft(input, win, 128);
  int t2 = DateTime.now().microsecondsSinceEpoch;
  print(t2 - t1);
}