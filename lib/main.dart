import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:capture_input_ouput/text_painter_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:system_audio_recorder/system_audio_recorder.dart';

import 'package:file_selector/file_selector.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class FixedLengthStream {
  List<double>? stream;
  int offset = 0;
  int maxLength = 0;
  int nowLength = 0;
  void init(sr) {
    stream = [];
    offset = 0;
    nowLength = 0;
    maxLength = sr * 4;
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  FlutterSoundRecorder? _mRecorder = FlutterSoundRecorder();
  bool _mPlayerIsInited = false;
  bool _mRecorderIsInited = false;
  String? inputPath;
  String? outputPath;
  String? processedPath;
  String? tempPath;
  int frameMs = 20; // 20ms
  bool startPlay = false;
  FlutterSoundPlayer? streamPlayer = FlutterSoundPlayer();

  XTypeGroup typeGroup = const XTypeGroup(label: "audio", extensions: <String>['mp3']);

  bool _mplaybackReady = false;
  //String? _mPath;
  StreamSubscription? _mRecordingDataSubscription;
  //Uint8List buffer = [];
  int sampleRate = 16000;

  int frameSize = 640;

  int maxDisplaySize = 16000 * 4;

  List<double> inputCache = List.empty(growable: true);
  List<double> processCache = List.empty(growable: true);
  List<double> outputCache = List.empty(growable: true);

  FixedLengthStream inputStream = FixedLengthStream();
  FixedLengthStream outputStream = FixedLengthStream();
  FixedLengthStream processStream = FixedLengthStream();

  StreamSubscription? _audioSubscription;
  FlutterSoundPlayer player = FlutterSoundPlayer();
  bool isRecording = false;
  Timer? timer;
  String? chooseFilePath;
  int inputTimestamp = 0;
  int outputTimestamp = 0;
  DateTime? inputClickStartTime;
  DateTime? outputClickStartTime;
  DateTime? inputStartTime;
  DateTime? outputStartTime;
  DateTime? inputEndTime;
  DateTime? outputEndTime;
  // Stream

  @override
  void initState() {
    super.initState();
    checkAndRequestPermission();
    
    _mPlayer!.openPlayer().then((value) {
      setState(() {
        _mPlayerIsInited = true;
      });
    });
    streamPlayer!.openPlayer().then((value) {});
    _openRecorder();
    inputStream.init(sampleRate);
    outputStream.init(sampleRate);
    processStream.init(sampleRate);

  }

  Future<void> checkAndRequestPermission() async {
    // 检查当前权限状态
    var status = await Permission.storage.status;
    if (await Permission.manageExternalStorage.request().isGranted) {
      print("manageExternalStorage granted");
    }
    if (status.isGranted) {
      // 权限已经授予
      print("storage permission granted.");
    } else if (status.isDenied) {
      // 请求权限
      PermissionStatus result = await Permission.storage.request();
      if (result.isGranted) {
        print("storage permission granted after request.");
      } else {
        print("storage permission denied.");
      }
    }
    status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
  }

  @override
  void dispose() {
    stopPlayer();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    streamPlayer!.closePlayer();
    streamPlayer = null;
    inputStream.dispose();
    outputStream.dispose();
    processStream.dispose();
    stopRecordInput();
    _mRecorder!.closeRecorder();
    _mRecorder = null;
    super.dispose();
  }

  Future<void> _openRecorder() async {
    await _mRecorder!.openRecorder();

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    setState(() {
      _mRecorderIsInited = true;
    });
  }

  void showAlertDialog(content) {
    showDialog<Null>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('提示'),
            content: SingleChildScrollView(child: Text(content)),
            actions: <Widget>[
              ElevatedButton(
                child: const Text('确定'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
  }

  Future<IOSink> createInputFile() async {
    try {
      inputPath = '/storage/emulated/0/recode_input.pcm';
      var outputFile = File(inputPath!);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile.openWrite();
    } catch (e) {
      var tempDir = await getExternalStorageDirectory();

      inputPath = '${tempDir?.parent.path}/recode_input.pcm';
      var outputFile = File(inputPath!);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile.openWrite();
    }
  }

  Future<IOSink> createOutputFile() async {
    try {
      outputPath = '/storage/emulated/0/recode_output.pcm';
      var outputFile = File(outputPath!);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile.openWrite();
    } catch (e) {
      var tempDir = await getExternalStorageDirectory();
      // var tempDir = await getTemporaryDirectory();
      outputPath = '${tempDir?.parent.path}/recode_output.pcm';
      var outputFile = File(outputPath!);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile.openWrite();
    }
  }

  Future<IOSink> createProcessedFile() async {
    try {
      processedPath = '/storage/emulated/0/processed.pcm';
      var outputFile = File(processedPath!);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile.openWrite();
    } catch (e) {
      var tempDir = await getExternalStorageDirectory();
      // var tempDir = await getTemporaryDirectory();
      processedPath = '${tempDir?.parent.path}/processed.pcm';
      var outputFile = File(processedPath!);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile.openWrite();
    }
  }

  Future<void> stopPlayer() async {
    await _mPlayer!.stopPlayer();
  }

  List<double> uint8LtoDoubleL(Uint8List rawData) {
    List<double> doubleArray = List.empty(growable: true);
    ByteData byteData = ByteData.sublistView(rawData);
    for (var i = 0; i < byteData.lengthInBytes; i += 2) {
      doubleArray.add(byteData.getInt16(i, Endian.little).toInt() / 65535);
    }
    return doubleArray;
  }

  Future<void> process(sink) async {
    processCache = inputCache.map((e) => e * 2).toList();
    setState(() {
      processStream.update(processCache);
    });
    List<int> temp = processCache.map((e) => (e * 65535).toInt()).toList();
    Int16List int16Temp = Int16List.fromList(temp);
    final byteBuffer = ByteData(int16Temp.lengthInBytes);
    for (int i = 0; i < int16Temp.length; i++) {
      byteBuffer.setInt16(i * 2, int16Temp[i], Endian.little);
    }

    sink.add(byteBuffer.buffer.asUint8List());
  }

  Future<void> recordInput() async {
    assert(_mRecorderIsInited && _mPlayer!.isStopped);
    var inSink = await createInputFile();
    var pSink = await createProcessedFile();
    var recordingDataController = StreamController<Uint8List>();
    _mRecordingDataSubscription = recordingDataController.stream.listen((buffer) async {
      if (isRecording) {
        // inputTimestamp = DateTime.now().microsecondsSinceEpoch;
        // print("input size: ${buffer.length}");
        // nowTimestamp = DateTime.now().millisecondsSinceEpoch;
        // print(nowTimestamp - lastTimestamp);
        // lastTimestamp = nowTimestamp;
        inputStartTime ??= DateTime.now();
        inputEndTime = DateTime.now();
        inSink.add(buffer);
        inputCache = uint8LtoDoubleL(buffer);
        // Buffer(inputCache, timestamp);
        setState(() {
          inputStream.update(inputCache);
        });

        process(pSink);
      }
    });
    await _mRecorder!.startRecorder(
      toStream: recordingDataController.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
      bufferSize: frameSize,
    );
    // _receivePort = ReceivePort();
    // _receivePort.listen(_processAudioData);
    //
    // await Isolate.spawn(startRecordingInIsolate, _receivePort.sendPort);
    setState(() {});
  }

  Future<bool> requestRecordOutput() async {
    bool start = await SystemAudioRecorder.requestRecord("test",
        titleNotification: "titleNotification", messageNotification: "messageNotification", sampleRate: 16000);
    return start;
  }

  Future<void> recordOutput() async {
    var outSink = await createOutputFile();
    bool start = await SystemAudioRecorder.startRecord;
    if (_audioSubscription == null && start) {
      _audioSubscription = SystemAudioRecorder.audioStream.receiveBroadcastStream({"config": "null"}).listen((data) {
        if (isRecording) {
          // print("output size: ${data.length}");
          outputStartTime ??= DateTime.now();
          outputEndTime = DateTime.now();
          if (isRecording) {
            outSink.add(data);
            setState(() {
              outputStream.update(uint8LtoDoubleL(data));
            });
          }
        }
      });
    }
  }

  Future<void> stopRecordInput() async {
    await _mRecorder!.stopRecorder();
    if (_mRecordingDataSubscription != null) {
      await _mRecordingDataSubscription!.cancel();
      _mRecordingDataSubscription = null;
    }
    _mplaybackReady = true;
    // _bufferTimer?.cancel();
  }

  Future<void> stopRecordOutput() async {
    await SystemAudioRecorder.stopRecord;
    if (_audioSubscription != null) {
      _audioSubscription?.cancel();
      _audioSubscription = null;
    }
  }

  Future<void> stop() async {
    if (!isRecording) {
      showAlertDialog("还没有录音");
      return;
    }

    // print(outputStartTime!.difference(outputClickStartTime!));
    // print(inputStartTime!.difference(inputClickStartTime!));
    if (startPlay) {
      await streamPlayer!.stopPlayer();
      setState(() {
        startPlay = false;
      });
    }
    timer?.cancel();

    await stopRecordOutput();
    await stopRecordInput();
    setState(() {
      isRecording = false;
    });
    print(outputStartTime!.difference(inputStartTime!));
    print(outputEndTime!.difference(inputEndTime!));
    inputStream.reset();
    outputStream.reset();
    processStream.reset();
    chooseFilePath = null;
  }

  Future<void> record() async {
    if (_mPlayer!.isPlaying) {
      showAlertDialog("正在播放");
      return;
    }
    if (isRecording) {
      showAlertDialog("正在录音");
      return;
    }
    inputStream.reset();
    outputStream.reset();
    processStream.reset();
    inputStartTime = null;
    outputStartTime = null;

    bool start = await requestRecordOutput();
    if (start) {
      await recordOutput();
      outputClickStartTime = DateTime.now();
      // print(DateTime.now());
      await recordInput();
      inputClickStartTime = DateTime.now();
      // print(DateTime.now());
      setState(() {
        isRecording = true;
      });
      if (chooseFilePath != null) {
        play(chooseFilePath, choose: true);
      }
    }
  }

  void showToast(msg) {
    Fluttertoast.showToast(
        msg: msg,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        // backgroundColor: Colors.red,
        // textColor: Colors.white,
        fontSize: 16.0);
  }

  void play(path, {choose = false}) async {
    if (choose) {
      if (_mPlayer != null && _mPlayer!.isPlaying) {
        await _mPlayer!.stopPlayer();
      }

      showToast("开始播放");
      await _mPlayer!.startPlayer(
          fromURI: path,
          whenFinished: () {
            showToast("播放完毕");
            setState(() {});
          });
    } else {
      if (isRecording) {
        showAlertDialog("正在录音，请先停止录音");
        return;
      }
      if (path == null) {
        showAlertDialog("还没有录音");
        return;
      }
      if (_mPlayer != null && _mPlayer!.isPlaying) {
        await _mPlayer!.stopPlayer();
      }

      showToast("开始播放");

      if (_mPlayerIsInited && _mplaybackReady && _mRecorder!.isStopped && _mPlayer!.isStopped) {
        await _mPlayer!.startPlayer(
            fromURI: path,
            sampleRate: sampleRate,
            codec: Codec.pcm16,
            numChannels: 1,
            whenFinished: () {
              showToast("播放完毕");
              setState(() {});
            });
      }
    }
  }

  Future<String?> openAudioFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null) {
      return result.files.single.path!;
    } else {
      // User canceled the picker
      return null;
    }
  }

  void playInput() {
    play(inputPath);
  }

  void playOutput() {
    play(outputPath);
  }

  void playProcessed() {
    play(processedPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextPainterButton(playfn: playInput, text: "input", waveform: inputStream.stream!),
            TextPainterButton(playfn: playOutput, text: "output", waveform: outputStream.stream!),
            TextPainterButton(playfn: playProcessed, text: "processed", waveform: processStream.stream!),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    record();
                  },
                  child: const Text("开始录制"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_mPlayer != null && _mPlayer!.isPlaying) {
                      await _mPlayer!.stopPlayer();
                    }
                    stop();
                  },
                  child: const Text('停止录制'),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                    onPressed: () async {
                      if (_mPlayer!.isPlaying) {
                        showToast("正在播放，请先停止播放");
                        return;
                      }
                      chooseFilePath = await openAudioFile();
                      if (chooseFilePath != null && !isRecording) {
                        showToast("点击开始录制后播放文件");
                      }
                      if (chooseFilePath != null && isRecording) {
                        play(chooseFilePath, choose: true);
                      } else {
                        showToast("取消播放文件");
                      }
                    },
                    child: const Text("播放文件")),
                ElevatedButton(
                    onPressed: () async {
                      if (_mPlayer != null && !_mPlayer!.isPlaying) {
                        showToast("已停止播放");
                      }
                      if (_mPlayer != null && _mPlayer!.isPlaying) {
                        await _mPlayer!.stopPlayer();
                      }
                    },
                    child: const Text("停止播放"))
              ],
            )
          ],
        ),
      ),
    );
  }
}
