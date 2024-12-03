import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:system_audio_recorder/system_audio_recorder.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';

class RecordOutput extends StatefulWidget {
  const RecordOutput({super.key});

  @override
  State<RecordOutput> createState() => _RecordOutputState();
}

class _RecordOutputState extends State<RecordOutput> {
  String _platformVersion = 'Unknown';
  final _systemAudioRecorderPlugin = SystemAudioRecorder();
  StreamSubscription? _audioSubscription;
  List<int> allData = List.empty(growable: true);
  Uint8List? udata;
  FlutterSoundPlayer player = FlutterSoundPlayer();
  bool isRecording = false;
  requestPermissions() async {
    if (!kIsWeb) {
      if (await Permission.storage.request().isDenied) {
        await Permission.storage.request();
      }
      if (await Permission.photos.request().isDenied) {
        await Permission.photos.request();
      }
      if (await Permission.microphone.request().isDenied) {
        await Permission.microphone.request();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    requestPermissions();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion = await _systemAudioRecorderPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: Center(
        child: Column(children: [
          Text('Running on: $_platformVersion\n'),
          TextButton(
              onPressed: () async {
                allData.clear();
                bool start = await SystemAudioRecorder.startRecord("test",
                    titleNotification: "titleNotification",
                    messageNotification: "messageNotification",
                    sampleRate: 16000);

                if (_audioSubscription == null) {
                  _audioSubscription =
                      SystemAudioRecorder.audioStream.receiveBroadcastStream({"config": "null"}).listen((data) {
                        // print("${data.length}");
                        allData.addAll(data);
                      });
                }
                setState(() {
                  isRecording = true;
                });
                // if (start) {
                //   _audioSubscription = SystemAudioRecorder.audioStream.receiveBroadcastStream().listen((audioData){
                //     print("Received audio data: ${audioData.length} bytes");
                //   });
                // }
              },
              child: const Text("开始录制")),
          TextButton(
              onPressed: () async {
                String path = await SystemAudioRecorder.stopRecord;
                if (_audioSubscription != null) {
                  _audioSubscription?.cancel();
                  _audioSubscription = null;
                }
                setState(() {
                  isRecording = false;
                });
                print(path);
              },
              child: const Text("停止录制")),
          TextButton(
              onPressed: isRecording ? null : () async {
                if (allData.isEmpty){
                  return;
                }
                udata = Uint8List.fromList(allData);
                await player.openPlayer();
                await player.startPlayerFromStream(codec: Codec.pcm16, numChannels: 1, sampleRate: 16000);
                await player.feedFromStream(udata!);
                await player.stopPlayer();
              },
              child: const Text("播放录制的声音")),
        ]),
      )
    );
  }
}
