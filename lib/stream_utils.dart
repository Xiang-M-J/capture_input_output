import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:capture_input_ouput/utils/type_converter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

class SyncFileStream {
  List<int>? audioCache;
  int sampleRate = 16000;
  int fileCacheLength = 0;
  File? file;
  IOSink? sink;
  String fileName = "";
  String? filePath;
  int frameSize = 256;
  int hopSize = 128;
  bool canWrite = false;
  int maxArrayLength = 30;
  // bool firstSample = true;
  List<Uint8List>? arrayCache;

  Future<void> init({bool isCache = false}) async {
    audioCache = List<int>.empty(growable: true);
    file = await createFile(fileName);
    filePath = file?.path;
    fileCacheLength = 0;
    sink = file?.openWrite();
    canWrite = true;
    // if (isCache){
    //   arrayCache =
    // }
  }

  Future<void> reset() async {
    audioCache?.clear();
    audioCache = null;
    fileCacheLength = 0;
    file = null;
    filePath = null;
    sink = null;
  }

  Future<File> createFile(String name) async {
    // try {
    //   String path = "/mnt/sdcard/$name";
    //   var outputFile = File(path);
    //   var dir = Directory("/mnt/sdcard/");
    //   if (dir.existsSync()) {
    //     if (outputFile.existsSync()) {
    //       await outputFile.delete();
    //     }
    //     return outputFile;
    //   } else {
    //     throw Exception("no dir exist");
    //   }
    // } catch (e) {
      var tempDir = await getExternalStorageDirectory();

      String path = '${tempDir?.parent.path}/$name';
      var outputFile = File(path);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile;
    // }
  }

  void update(Uint8List data, {bool writeToFile = true, bool writeToCache = true}) {
    if (writeToFile) {
      if (canWrite) {
        sink!.add(data);
      }
    }
    if (writeToCache) {
      List<int> temp = uint8LtoInt16List(data);
      audioCache!.addAll(temp);
    }
  }

  List<int>? sample({int frameSize = 256}) {
    List<int> samples = audioCache!.sublist(0, frameSize);
    audioCache!.removeRange(0, hopSize);
    return samples;
  }

  List<int>? sample2(int n, {int frameSize = 256, int hopSize = 128}) {
    int sampleNum = (n + 1) * hopSize;
    List<int> samples = audioCache!.sublist(0, sampleNum);
    audioCache!.removeRange(0, sampleNum - hopSize);
    return samples;
  }

  List<int>? sample3(int n, {int sampleSize = 128}) {
    List<int> samples = audioCache!.sublist(0, n * sampleSize);
    audioCache!.removeRange(0, n * sampleSize);
    return samples;
  }

  int canSampleSize({int sampleSize = 128}) {
    return audioCache!.length ~/ sampleSize - 1;
  }

  bool canSample({int frameSize = 256}) {
    return audioCache!.length > frameSize;
  }

  void close() {
    sink?.close();
    canWrite = false;
  }

  SyncFileStream(this.sampleRate, this.fileName) {
    // maxAudioCacheLength = frameSize * 20;
  }
}

class FixedLengthStream {
  List<double>? stream;
  int offset = 0;
  int maxLength = 0;
  int nowLength = 0;
  void init(sr, maxShowSeconds) {
    stream = [];
    offset = 0;
    nowLength = 0;
    maxLength = sr * maxShowSeconds;
  }

  void update(List<double> data) {
    stream?.addAll(data);
    nowLength += data.length;
    if (nowLength > maxLength) {
      stream = stream!.sublist(nowLength - maxLength);
      nowLength = maxLength;
    }
    offset = (offset + 1) % maxLength;
  }

  void reset() {
    stream?.clear();
    offset = 0;
    nowLength = 0;
  }

  void dispose() {
    stream?.clear();
    stream = null;
  }
}

class TaskScheduler {
  final Queue<Function> _taskQueue = Queue();
  bool _isRunning = false;

  void addTask(Future<void> Function() task) {
    _taskQueue.add(task);
    _startNextTask();
  }

  void _startNextTask() {
    if (_isRunning || _taskQueue.isEmpty) {
      return;
    }

    _isRunning = true;

    final task = _taskQueue.removeFirst();
    task().whenComplete(() {
      _isRunning = false;
      _startNextTask();
    });
  }
}
