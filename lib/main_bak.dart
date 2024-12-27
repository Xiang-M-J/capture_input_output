import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:capture_input_ouput/stream_utils.dart';
import 'package:capture_input_ouput/text_painter_button.dart';
import 'package:capture_input_ouput/utils/msadpcrn2.dart';
import 'package:capture_input_ouput/utils/type_converter.dart';
import 'package:flutter/material.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:permission_handler/permission_handler.dart';
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
// 127.0.0.1:5037
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

void inferenceTask(SendPort port) async {
  // initOrtEnv();
  MsaDpcrn2 msaAce = MsaDpcrn2();

  final receivePort = ReceivePort();
  port.send(receivePort.sendPort);

  await for (var msg in receivePort) {
    if (msg is String) {
      if (msg == "exit") {
        msaAce.release();
        // port.send("will release");
        // releaseOrtEnv();
        Isolate.exit(receivePort.sendPort);
      } else if (msg == "reset") {
        msaAce.reset();
        // port.send("has reset");
      }
    } else if (msg is Uint8List) {
      await msaAce.initModelByBuffer(msg);
    } else if (msg is List<List<int>>) {
      List<double>? result = msaAce.predictMultiFrames2(msg);
      // List<double>? result = msaAce.testPredictMultiFrames();
      port.send(result);
    } else {
      print("unknown msg type");
    }
  }
}

Future<List<int>> parsePcm16(String path) async {

  final byteData = await rootBundle.load("assets/$path");
  Uint8List bytes = byteData.buffer.asUint8List();
  final sampleCount = bytes.length ~/ 2;
  List<int> samples = [];
  for (var i = 0; i < sampleCount; i++) {
    // 每两个字节解析一个 16 位有符号整数（小端序）
    final sample = bytes.buffer.asByteData().getInt16(i * 2, Endian.little);
    samples.add(sample);
  }
  return samples;
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  bool _mPlayerIsInited = false;
  String? inputPath;
  String? outputPath;
  String? processedPath;
  String? tempPath;
  int frameMs = 20; // 20ms

  bool _mplaybackReady = false;
  //String? _mPath;
  //Uint8List buffer = [];
  int sampleRate = 16000;

  int frameSize = 256;
  int bytesSize = 512;

  int maxDisplaySize = 16000 * 2;
  int maxDisplaySeconds = 2;

  List<double> inputCache = List.empty(growable: true);
  List<double> processCache = List.empty(growable: true);
  List<double> outputCache = List.empty(growable: true);

  FixedLengthStream inputStream = FixedLengthStream();
  FixedLengthStream outputStream = FixedLengthStream();
  FixedLengthStream processStream = FixedLengthStream();

  StreamSubscription? audioSubscription;
  bool isRecording = false;
  Timer? timer;
  String? chooseFilePath;

  DateTime? inputClickStartTime;
  DateTime? outputClickStartTime;
  int? inputStartTime;
  int? outputStartTime;
  DateTime? inputEndTime;
  DateTime? outputEndTime;
  SyncFileStream? inputFileStream;
  SyncFileStream? processFileStream;
  SyncFileStream? outputFileStream;
  bool syncInputStart = true;
  bool syncOutputStart = true;
  double space = 0;
  bool firstPlay = true;
  bool playAudio = false;
  final stopWatch = Stopwatch();
  // MsaDpcrn? msaAce;
  List<int> usedTimes = [];
  ReceivePort? receivePort;
  SendPort? sendPort;
  int pointSpace = 64;   // 绘图时每隔pointSpace个点画一次
  bool isProcess = true;
  int padFramesNum = 25;   // 手机上是10


  @override
  void initState() {
    super.initState();
    checkAndRequestPermission();

    _mPlayer!.openPlayer().then((value) {
      setState(() {
        _mPlayerIsInited = true;
      });
    });
    _openRecorder();
    inputStream.init(sampleRate, maxDisplaySeconds);
    outputStream.init(sampleRate, maxDisplaySeconds);
    processStream.init(sampleRate, maxDisplaySeconds);
    inputFileStream = SyncFileStream(sampleRate, "record_input.pcm");
    processFileStream = SyncFileStream(sampleRate, "process_input.pcm");
    outputFileStream = SyncFileStream(sampleRate, "record_output.pcm");
    space = sampleRate / 1e3;
    initOrtEnv();
    initPort();
  }
  void initOrtEnv() {
    OrtEnv.instance.init();
    OrtEnv.instance.availableProviders().forEach((element) {
      print('onnx provider=$element');
    });
  }

  void releaseOrtEnv() {
    OrtEnv.instance.release();
  }
  void initPort() async {
    receivePort = ReceivePort();
    receivePort?.listen((msg) {
      if (msg is SendPort){
        sendPort = msg;
      }else if (msg is List<double>){
        processCache = msg;

        processStream.update(processCache);
        setState(() {

        });
        Uint8List u8Data = doubleList2Uint8List(msg);
        processFileStream?.update(u8Data);
      }else if (msg == null){
        print("result is null");
      }
    });
    await Isolate.spawn(inferenceTask, receivePort!.sendPort);

    final rawAssetFile = await rootBundle.load("assets/msa_dpcrn.onnx");
    final bytes = rawAssetFile.buffer.asUint8List();

    sendPort?.send(bytes);
  }

  Future<void> checkAndRequestPermission() async {
    // 检查当前权限状态
    var status = await Permission.storage.status;
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

    status = await Permission.manageExternalStorage.request();
    // if(status != PermissionStatus.granted){
    //   // showToast("没有读写权限");
    // }

    status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
  }

  @override
  void dispose() {
    sendPort?.send("exit");
    stopPlayer();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    inputStream.dispose();
    outputStream.dispose();
    processStream.dispose();
    stop();
    SystemAudioRecorder.dispose();
    inputFileStream?.reset();
    inputFileStream = null;
    outputFileStream?.reset();
    outputFileStream = null;
    processFileStream?.reset();
    processFileStream = null;
    // msaAce?.release();
    releaseOrtEnv();
    super.dispose();
  }

  void reset() {
    sendPort?.send("reset");
    syncInputStart = true;
    syncOutputStart = true;
    inputStartTime = null;
    outputStartTime = null;
    inputFileStream?.reset();
    processFileStream?.reset();
    outputFileStream?.reset();
    // msaAce?.reset();
  }

  Future<void> _openRecorder() async {
    await SystemAudioRecorder.openRecorder(sampleRate: sampleRate, bufferSize: bytesSize);

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

    setState(() {});
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

  Future<void> stopPlayer() async {
    await _mPlayer!.stopPlayer();
  }

  Future<void> startRecording() async {
    await inputFileStream?.init();
    inputPath = inputFileStream?.filePath;
    await processFileStream?.init();
    processedPath = processFileStream?.filePath;
    await outputFileStream?.init();
    outputPath = outputFileStream?.filePath;
    if (chooseFilePath == null) {
      inputFileStream!.update(Uint8List(bytesSize * padFramesNum));
    } else {
      inputFileStream!.update(Uint8List(bytesSize * padFramesNum));
    }

    bool isStarted = await SystemAudioRecorder.startRecord();
    if (isStarted && audioSubscription == null) {
      audioSubscription = SystemAudioRecorder.audioStream.receiveBroadcastStream({}).listen((buffer) {
        if (isRecording) {
          var iBuffer = buffer['input'];
          var oBuffer = buffer['output'];

          inputCache = uint8LtoDoubleList(iBuffer);

          inputStream.update(inputCache);

          inputFileStream?.update(iBuffer);

          outputCache = uint8LtoDoubleList(oBuffer);

          outputStream.update(outputCache);

          outputFileStream?.update(oBuffer);
          // 20241219 之前每次会取 384 个点
          int canSampleSize = min(inputFileStream!.canSampleSize(), outputFileStream!.canSampleSize());
          if (canSampleSize >= 1){

            List<int>? micFrame = inputFileStream!.sample3(canSampleSize);
            List<int>? refFrame = outputFileStream!.sample3(canSampleSize);
            if (micFrame != null && refFrame != null) {
              if(isProcess){
                sendPort?.send([micFrame, refFrame]);
              }else{
                processCache = inputCache.map((e) => e * 2).toList();
                setState(() {
                  processStream.update(processCache);
                });
                Uint8List processUint8List = doubleList2Uint8List(processCache);
                processFileStream?.update(processUint8List);
              }
            }
          }
        }
      });
    }
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
    reset();
    bool isConfirm = await SystemAudioRecorder.requestRecord("record",
        titleNotification: "titleNotification", messageNotification: "messageNotification");

    if (isConfirm) {
      startRecording();
      setState(() {
        isRecording = true;
      });

      if (chooseFilePath != null) {
        play(chooseFilePath, choose: true);
        // inputFileStream!.sink!.add(Uint8List((frameSize * 1).toInt()));
        firstPlay = false;
      }
      // timer = Timer.periodic(const Duration(milliseconds: 10), (t) async {
      //   if (!isRecording) {
      //     if (timer!.isActive) timer?.cancel();
      //   }
      //   if (inputFileStream!.canSample() && outputFileStream!.canSample()) {
      //     List<int>? micFrame = inputFileStream!.sample(); // 256
      //     List<int>? refFrame = outputFileStream!.sample();
      //
      //     if (micFrame != null && refFrame != null) {
      //
      //       sendPort?.send([micFrame, refFrame]);
      //     }
      //   }
      // });
    }
  }

  Future<void> stop() async {
    if (!isRecording) {
      showAlertDialog("还没有录音");
      return;
    }

    setState(() {
      isRecording = false;
    });
    timer?.cancel();
    _mplaybackReady = true;
    await SystemAudioRecorder.stopRecord();
    if (audioSubscription != null) {
      audioSubscription?.cancel();
      audioSubscription = null;
    }
    inputFileStream?.close();
    outputFileStream?.close();
    processFileStream?.close();

    inputStream.reset();
    outputStream.reset();
    processStream.reset();
    chooseFilePath = null;
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

      if (_mPlayerIsInited && _mplaybackReady && !isRecording && _mPlayer!.isStopped) {
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
            // NumberControllerWidget(
            //   numText: '$padFramesNum',
            // ),
            // TextField(
            //   controller: _controller,
            //   keyboardType: TextInputType.number,
            //   decoration: const InputDecoration(
            //     border: OutlineInputBorder(),
            //     labelText: '请输入数字',
            //     hintText: '例如：10',
            //   ),
            //   onChanged: (value) {
            //     setState(() {
            //       try{
            //         padFramesNum = int.parse(value);
            //         if (padFramesNum < 0) {
            //           padFramesNum = 10;
            //         }
            //       }catch(e){
            //         padFramesNum = 10;
            //       }
            //
            //     });
            //   },
            // ),

            TextPainterButton(playfn: playInput, text: "input", waveform: inputStream.stream!, frameSize: frameSize, pointSpace: pointSpace,),
            TextPainterButton(playfn: playOutput, text: "output", waveform: outputStream.stream!, frameSize: frameSize, pointSpace: pointSpace,),
            TextPainterButton(playfn: playProcessed, text: "processed", waveform: processStream.stream!, frameSize: frameSize, pointSpace: pointSpace,),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    record();
                    // testQmf();  // 不一致
                    // testSTFT();
                    // sendPort?.send("reset");
                    // List<int> micFrame = List.generate(1024, (e) => e * 10 + 100);
                    // List<int> refFrame = List.generate(1024, (e) => e * 10);
                    // //
                    // sendPort?.send([micFrame.sublist(0, 256), refFrame.sublist(0, 256)]);
                    // // testSTFT();
                    // //
                    // // List<int> micFrame = List.generate(256, (e) => e * 100 + 100);
                    // // List<int> refFrame = List.generate(256, (e) => e * 100);
                    // //
                    // sendPort?.send([micFrame.sublist(256, 512), refFrame.sublist(256, 512)]);
                    // sendPort?.send([micFrame.sublist(512, 768), refFrame.sublist(512, 768)]);
                    // sendPort?.send([micFrame.sublist(768, 1024), refFrame.sublist(768, 1024)]);
                    // processFileStream?.reset();
                    // sendPort?.send("reset");
                    // await processFileStream?.init();
                    // processedPath = processFileStream?.filePath;
                    //
                    // List<int> micSamples = await parsePcm16("record_input.pcm");
                    // List<int> refSamples = await parsePcm16("record_output.pcm");
                    // int numFrames = refSamples.length ~/ 256;
                    // for (var i = 0; i < numFrames; i++){
                    //   List<int> micFrame = micSamples.sublist(i * 256, i*256+256);
                    //   List<int> refFrame = refSamples.sublist(i * 256, i * 256 + 256);
                    //   sendPort?.send([micFrame, refFrame]);
                    //   sleep(Duration(milliseconds: 10));
                    // }
                    // print("done");
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
                        playAudio = true;
                        if (firstPlay) {
                          firstPlay = false;
                        }
                        // if (firstPlay){
                        //   inputFileStream!.sink!.add(Uint8List(frameSize * 2));
                        //   firstPlay = false;
                        // }else{
                        //   inputFileStream!.sink!.add(Uint8List((frameSize * 1).toInt()));
                        // }
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
            ),
            const SizedBox(
              height: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("模型处理"),
                const SizedBox(width: 20,),
                Switch(value: isProcess, onChanged: (bool value){
                  setState(() {
                    isProcess = value;
                  });
                }),
              ],
            ),

            const Text("Version: 1.0.4(2024-12-20)")
          ],
        ),
      ),
    );
  }
}
