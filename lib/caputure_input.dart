/*
 * Copyright 2018, 2019, 2020, 2021 Dooboolab.
 *
 * This file is part of Flutter-Sound.
 *
 * Flutter-Sound is free software: you can redistribute it and/or modify
 * it under the terms of the Mozilla Public License version 2 (MPL2.0),
 * as published by the Mozilla organization.
 *
 * Flutter-Sound is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * MPL General Public License for more details.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/*
 * This is an example showing how to record to a Dart Stream.
 * It writes all the recorded data from a Stream to a File, which is completely stupid:
 * if an App wants to record something to a File, it must not use Streams.
 *
 * The real interest of recording to a Stream is for example to feed a
 * Speech-to-Text engine, or for processing the Live data in Dart in real time.
 *
 */

///
typedef _Fn = void Function();

/// Example app.
class RecordInput extends StatefulWidget {
  const RecordInput({super.key});

  @override
  State<RecordInput> createState() => _RecordInputState();
}

class Recoder{
  int frameSize = 1600;
  List<int> cache = List.empty(growable: true);
  int cacheLength = 0;

  Future<void> processData(List<int> data){
    return compute(_processData, data);
  } 

  Future<void> processFrame(List<int> frame) async{
    print("process frame");
    sleep(const Duration(milliseconds: 1));
  }

  Future<void> _processData(List<int> data) async {
    List<int> intData = data.toList();
    if (cache.isNotEmpty){
      intData.insertAll(0, cache);
      cache.clear();
    }
    int index = 0;
    while (intData.length >= (index + 1) * frameSize) {
      List<int> frame = intData.sublist(index * frameSize, (index + 1) * frameSize);
      await processFrame(frame);
      index += 1;
    }
    if (intData.length != index * frameSize) {
      cache = intData.sublist(index * frameSize);
    }
  }
}

List<int> uint8LtoInt16List(Uint8List rawData) {
  List<int> intArray = List.empty(growable: true);
  ByteData byteData = ByteData.sublistView(rawData);
  for (var i = 0; i < byteData.lengthInBytes; i += 2) {
    intArray.add(byteData.getInt16(i, Endian.little).toInt());
  }
  return intArray;
}

class _RecordInputState extends State<RecordInput> {
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  FlutterSoundRecorder? _mRecorder = FlutterSoundRecorder();
  bool _mPlayerIsInited = false;
  bool _mRecorderIsInited = false;
  String? _mPath;

  bool _mplaybackReady = false;
  //String? _mPath;
  StreamSubscription? _mRecordingDataSubscription;
  //Uint8List buffer = [];
  int sampleRate = 16000;

  // 双缓存机制
  List<int> recordData = List.empty(growable: true);
  // List<int> processData = List.empty(growable: true);
  // Uint8List recordData = Uint8List.fromList(elements);
  // Uint8List processData = Uint8List.fromList([]);
  Timer? _bufferTimer; // 定时器
  int frameSize = 400;
  Recoder recoder = Recoder();

  Future<void> _openRecorder() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _mRecorder!.openRecorder();

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    //sampleRate = await _mRecorder!.getSampleRate();

    setState(() {
      _mRecorderIsInited = true;
    });
  }

  @override
  void initState() {
    super.initState();
    // Be careful : openAudioSession return a Future.
    // Do not access your FlutterSoundPlayer or FlutterSoundRecorder before the completion of the Future
    _mPlayer!.openPlayer().then((value) {
      setState(() {
        _mPlayerIsInited = true;
      });
    });
    _openRecorder();
  }

  @override
  void dispose() {
    stopPlayer();
    _mPlayer!.closePlayer();
    _mPlayer = null;

    stopRecorder();
    _mRecorder!.closeRecorder();
    _mRecorder = null;
    super.dispose();
  }

  Future<IOSink> createFile() async {
    var tempDir = await getTemporaryDirectory();
    _mPath = '${tempDir.path}/flutter_sound_example.pcm';
    var outputFile = File(_mPath!);
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    return outputFile.openWrite();
  }

  // Future<void> processFrame(List<int> frame) async {
  //   print("process frame: ${frame.length}");
  //   sleep(const Duration(milliseconds: 10));
  // }

  // ----------------------  Here is the code to record to a Stream ------------
  // Future<void> readRecordData() async {
  //   if (recordData.length > frameSize) {
  //     var temp = recordData;
  //     recordData = processData;
  //     processData = temp;
  //   }
  //   print(recordData.length);
  //   print(processData.length);
  //   while (processData.length > frameSize) {
  //     List<int> frame = processData.sublist(0, frameSize);
  //     processData = processData.sublist(frameSize);
  //     await processFrame(frame);
  //   }
  // }

  Future<void> record() async {
    assert(_mRecorderIsInited && _mPlayer!.isStopped);
    var sink = await createFile();
    var recordingDataController = StreamController<Uint8List>();
    _mRecordingDataSubscription =
        recordingDataController.stream.listen((buffer) async {
      sink.add(buffer);
      recordData.addAll(uint8LtoInt16List(buffer));
      // print(buffer.length);
      // await recoder.processData(buffer);
      // recordData.addAll(buffer);
    });
    await _mRecorder!.startRecorder(
      toStream: recordingDataController.sink,
      codec: Codec.pcm16,
      numChannels: 2,
      sampleRate: sampleRate,
      bufferSize: 400,
    );
    setState(() {});
    _bufferTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) async {
          int maxIndex = recordData.length ~/ frameSize;
          List<int> seg = recordData.sublist(0, maxIndex * frameSize);
        recordData = recordData.sublist(maxIndex * frameSize);
      await recoder.processData(seg);
    });
  }
  // --------------------- (it was very simple, wasn't it ?) -------------------

  Future<void> stopRecorder() async {
    await _mRecorder!.stopRecorder();
    if (_mRecordingDataSubscription != null) {
      await _mRecordingDataSubscription!.cancel();
      _mRecordingDataSubscription = null;
    }
    _mplaybackReady = true;
    _bufferTimer?.cancel();
  }

  _Fn? getRecorderFn() {
    if (!_mRecorderIsInited || !_mPlayer!.isStopped) {
      return null;
    }
    return _mRecorder!.isStopped
        ? record
        : () {
            stopRecorder().then((value) => setState(() {}));
          };
  }

  void play() async {
    assert(_mPlayerIsInited &&
        _mplaybackReady &&
        _mRecorder!.isStopped &&
        _mPlayer!.isStopped);
    await _mPlayer!.startPlayer(
        fromURI: _mPath,
        sampleRate: sampleRate,
        codec: Codec.pcm16,
        numChannels: 2,
        whenFinished: () {
          setState(() {});
        });
    setState(() {});
  }

  Future<void> stopPlayer() async {
    await _mPlayer!.stopPlayer();
  }

  _Fn? getPlaybackFn() {
    if (!_mPlayerIsInited || !_mplaybackReady || !_mRecorder!.isStopped) {
      return null;
    }
    return _mPlayer!.isStopped
        ? play
        : () {
            stopPlayer().then((value) => setState(() {}));
          };
  }

  // ----------------------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget makeBody() {
      return Column(children: [
        Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.all(3),
          height: 120,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFAF0E6),
            border: Border.all(
              color: Colors.indigo,
              width: 3,
            ),
          ),
          child: Column(children: [
            Row(children: [
              ElevatedButton(
                onPressed: getRecorderFn(),
                //color: Colors.white,
                //disabledColor: Colors.grey,
                child: Text(_mRecorder!.isRecording ? 'Stop' : 'Record'),
              ),
              const SizedBox(
                width: 20,
              ),
              Text(_mRecorder!.isRecording
                  ? 'Recording in progress'
                  : 'Recorder is stopped'),
            ]),
          ]),
        ),
        Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(3),
            height: 120,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFAF0E6),
              border: Border.all(
                color: Colors.indigo,
                width: 3,
              ),
            ),
            child: Row(children: [
              ElevatedButton(
                onPressed: getPlaybackFn(),
                //color: Colors.white,
                //disabledColor: Colors.grey,
                child: Text(_mPlayer!.isPlaying ? 'Stop' : 'Play'),
              ),
              const SizedBox(
                width: 20,
              ),
              Text(_mPlayer!.isPlaying
                  ? 'Playback in progress'
                  : 'Player is stopped'),
            ])),
      ]);
    }

    return Scaffold(
      backgroundColor: Colors.blue,
      appBar: AppBar(
        title: const Text('Record to Stream ex.'),
      ),
      body: makeBody(),
    );
  }
}
