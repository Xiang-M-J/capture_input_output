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

class SyncFileStream {
  List<int>? fileCache;
  int sampleRate = 16000;
  List<int>? startCache;
  int fileCacheLength = 0;
  File? file;
  IOSink? sink;
  String fileName = "";
  String? filePath;
  int numSaveFrames = 0;
  int numSavePoints = 0;
  int mode = 0; // mode: 0 将录制数据存入缓存， mode: 1 将数据存入文件
  int maxFileCacheLength = 0;
  int frameSize = 0;

  Future<void> init() async {
    fileCache = List<int>.empty(growable: true);
    startCache = List<int>.empty(growable: true);
    mode = 0;
    file = await createFile(fileName);
    filePath = file?.path;
    fileCacheLength = 0;
    sink = file?.openWrite();
  }

  Future<void> reset() async {
    fileCache?.clear();
    fileCache = null;
    fileCacheLength = 0;
    startCache?.clear();
    startCache = null;
    file = null;
    filePath = null;
    sink = null;
    mode = 0;
    numSaveFrames = 0;
    numSavePoints = 0;
  }

  Future<File> createFile(String name) async {
    try {
      String path = "/storage/emulated/0/$name";
      var outputFile = File(path);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile;
    } catch (e) {
      var tempDir = await getExternalStorageDirectory();

      String path = '${tempDir?.parent.path}/$name';
      var outputFile = File(path);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      return outputFile;
    }
  }

  void update(Uint8List data, int? numPadFrames, int? numPadPoints) {
    if (mode == 0) {
      startCache?.addAll(data);
      if (numPadFrames != null && numPadPoints != null) {
        print("npf: $numPadFrames, npp: $numPadPoints");

        if (numPadPoints > 0) {
          Uint8List pad = Uint8List(numPadPoints);
          numSavePoints = pad.length;
          sink!.add(pad);
        }
        if (numPadFrames > 0) {
          sink!.add(Uint8List(numPadFrames * frameSize));
          numSaveFrames += numPadFrames;
        }
        int len = startCache!.length;
        numSaveFrames += len ~/ frameSize;
        numSavePoints += len % frameSize;
        if (numSavePoints > frameSize){
          numSaveFrames += numSavePoints ~/ frameSize;
          numSavePoints = numSavePoints % frameSize;
        }
        sink!.add(Uint8List.fromList(startCache!));
        print("numSaveFrames: $numSaveFrames, numSavePoints: $numSavePoints");
        mode = 1;
      }
    } else if (mode == 1) {
      if (fileCacheLength < maxFileCacheLength) {
        fileCache!.addAll(data);
        fileCacheLength += data.length;
      }else {
        int numFrames = (fileCacheLength - maxFileCacheLength) ~/ frameSize + 1;
        int saveLength = numFrames * frameSize;
        List<int> subList = fileCache!.sublist(0, saveLength);
        sink!.add(subList);
        numSaveFrames += numFrames;
        fileCache!.removeRange(0, saveLength);
        fileCacheLength -= saveLength;
      }
    }
  }

  void close(int numSaveFrames, int numSavePoints) {
    if (numSaveFrames >= 0){
      if (numSaveFrames * frameSize >= fileCacheLength) {
        sink!.add(Uint8List.fromList(fileCache!));
        this.numSaveFrames += fileCacheLength ~/ frameSize;
      } else {
        int frameLength = numSaveFrames * frameSize;
        sink!.add(Uint8List.fromList(fileCache!.sublist(0, frameLength)));
        this.numSaveFrames += numSaveFrames;
        if (numSavePoints > 0) {
          sink!.add(Uint8List.fromList(fileCache!.sublist(frameLength, frameLength + numSavePoints)));
        }
        this.numSavePoints += numSavePoints;
      }
    }else{
      sink!.add(Uint8List.fromList(fileCache!));
    }
    sink?.close();
  }

  SyncFileStream(this.sampleRate, this.fileName) {
    frameSize = (sampleRate * 0.02 * 2).toInt();
    maxFileCacheLength = frameSize * 25;
  }
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
  bool isRecording = false;
  Timer? timer;
  String? chooseFilePath;

  DateTime? inputClickStartTime;
  DateTime? outputClickStartTime;
  DateTime? inputStartTime;
  DateTime? outputStartTime;
  DateTime? inputEndTime;
  DateTime? outputEndTime;
  SyncFileStream? inputFileStream;
  SyncFileStream? processFileStream;
  SyncFileStream? outputFileStream;
  bool syncInputStart = true;
  bool syncOutputStart = true;
  double space = 0;

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
    inputStream.init(sampleRate);
    outputStream.init(sampleRate);
    processStream.init(sampleRate);
    inputFileStream = SyncFileStream(sampleRate, "record_input.pcm");
    processFileStream = SyncFileStream(sampleRate, "process_input.pcm");
    outputFileStream = SyncFileStream(sampleRate, "record_output.pcm");
    space = sampleRate / 1e6;
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
    stopPlayer();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    inputStream.dispose();
    outputStream.dispose();
    processStream.dispose();
    stop();
    _mRecorder!.closeRecorder();
    _mRecorder = null;
    inputFileStream?.reset();
    inputFileStream = null;
    outputFileStream?.reset();
    outputFileStream = null;
    processFileStream?.reset();
    processFileStream = null;
    super.dispose();
  }

  void reset() {
    syncInputStart = true;
    syncOutputStart = true;
    inputStartTime = null;
    outputStartTime = null;
    inputFileStream?.reset();
    processFileStream?.reset();
    outputFileStream?.reset();
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

  Future<void> process(numSkipFrame, numSkipPoints) async {
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
    processFileStream?.update(byteBuffer.buffer.asUint8List(), numSkipFrame, numSkipPoints);
  }

  List<int> calculateStartInfo(int time) {
    int points = (space * time).round();
    int numFrame = points ~/ frameSize;
    int numPoints = (points % frameSize) ~/ 2 * 2;
    return [numFrame, numPoints];
  }

  Future<void> recordInput() async {
    assert(_mRecorderIsInited && _mPlayer!.isStopped);
    await inputFileStream?.init();
    inputPath = inputFileStream?.filePath;
    await processFileStream?.init();
    processedPath = processFileStream?.filePath;
    var recordingDataController = StreamController<Uint8List>();
    _mRecordingDataSubscription = recordingDataController.stream.listen((buffer) async {
      if (isRecording) {
        inputStartTime ??= DateTime.now();
        inputEndTime = DateTime.now();
        inputCache = uint8LtoDoubleL(buffer);
        // Buffer(inputCache, timestamp);
        setState(() {
          inputStream.update(inputCache);
        });
        if (syncInputStart) {
          if (inputStartTime != null && outputStartTime != null) {
            int diffTime = inputStartTime!.microsecondsSinceEpoch - outputStartTime!.microsecondsSinceEpoch;
            if (diffTime <= 0) {
              // 说明input先录，无需补零
              inputFileStream?.update(buffer, 0, 0);
              process(0, 0);
            } else {
              // 说明input后录，需要补零
              List<int> startInfo = calculateStartInfo(diffTime);
              inputFileStream?.update(buffer, startInfo[0], startInfo[1]);
              process(startInfo[0], startInfo[1]);
            }
            syncInputStart = false;
          } else {
            inputFileStream?.update(buffer, null, null);
            process(null, null);
          }
        } else {
          inputFileStream?.update(buffer, null, null);
          process(null, null);
        }
      }

    });
    await _mRecorder!.startRecorder(
      toStream: recordingDataController.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
      bufferSize: frameSize,
    );
    setState(() {});
  }

  Future<bool> requestRecordOutput() async {
    bool start = await SystemAudioRecorder.requestRecord("test",
        titleNotification: "titleNotification", messageNotification: "messageNotification", sampleRate: 16000);
    return start;
  }

  Future<void> recordOutput() async {
    await outputFileStream?.init();
    outputPath = outputFileStream?.filePath;
    bool start = await SystemAudioRecorder.startRecord;
    if (_audioSubscription == null && start) {
      _audioSubscription = SystemAudioRecorder.audioStream.receiveBroadcastStream({"config": "null"}).listen((buffer) {
        if (isRecording) {
          outputStartTime ??= DateTime.now();
          outputEndTime = DateTime.now();

          if (syncOutputStart) {
            if (inputStartTime != null && outputStartTime != null) {
              int diffTime = outputStartTime!.microsecondsSinceEpoch - inputStartTime!.microsecondsSinceEpoch;
              if (diffTime <= 0) {
                // output先录
                outputFileStream?.update(buffer, 0, 0);
              } else {
                // output后录，需要补零
                List<int> startInfo = calculateStartInfo(diffTime);
                outputFileStream?.update(buffer, startInfo[0], startInfo[1]);
              }
              syncOutputStart = false;
            } else {
              outputFileStream?.update(buffer, null, null);
            }
          }
          else {
            outputFileStream?.update(buffer, null, null);
          }
          setState(() {
            outputStream.update(uint8LtoDoubleL(buffer));
          });
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

  List<int> calculateSaveInfo() {
    List<int> saveInfo = [0, 0, 0, 0]; // input_frame, input_point, output_frame, output_point
    int inputSaveFrames = inputFileStream!.numSaveFrames;
    int inputSavePoints = inputFileStream!.numSavePoints;
    int inputFileCacheLength = inputFileStream!.fileCacheLength ~/ inputFileStream!.frameSize;
    int outputSaveFrames = outputFileStream!.numSaveFrames;
    int outputSavePoints = outputFileStream!.numSavePoints;
    int outputFileCacheLength = outputFileStream!.fileCacheLength ~/ outputFileStream!.frameSize;

    int inputMaxFrames = inputSaveFrames + inputFileCacheLength;

    int outputMaxFrames = outputSaveFrames + outputFileCacheLength;

    int maxFrames = min(inputMaxFrames, outputMaxFrames);
    saveInfo[0] = maxFrames - inputSaveFrames;
    saveInfo[2] = maxFrames - outputSaveFrames;
    if (inputSavePoints > 0) {
      saveInfo[0] -= 1;
      saveInfo[1] = inputFileStream!.frameSize - inputSavePoints;
    }
    if (outputSavePoints > 0) {
      saveInfo[1] -= 1;
      saveInfo[3] = outputFileStream!.frameSize - outputSavePoints;
    }
    return saveInfo;
  }

  Future<void> stop() async {
    if (!isRecording) {
      showAlertDialog("还没有录音");
      return;
    }

    print(outputStartTime!.difference(outputClickStartTime!));
    print(inputStartTime!.difference(inputClickStartTime!));

    timer?.cancel();

    await stopRecordOutput();
    await stopRecordInput();

    setState(() {
      isRecording = false;
    });
    List<int> saveInfo = calculateSaveInfo();
    print(saveInfo);
    inputFileStream?.close(saveInfo[0], saveInfo[1]);
    outputFileStream?.close(saveInfo[2], saveInfo[3]);
    processFileStream?.close(saveInfo[0], saveInfo[1]);
    print("isf: ${inputFileStream!.numSaveFrames}, isp: ${inputFileStream!.numSavePoints}");
    print("osf: ${outputFileStream!.numSaveFrames}, osp: ${outputFileStream!.numSavePoints}");
    // print(outputStartTime!.difference(inputStartTime!));
    // print(outputEndTime!.difference(inputEndTime!));
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
    reset();
    bool start = await requestRecordOutput();
    if (start) {
      await recordOutput();
      outputClickStartTime = DateTime.now();

      await recordInput();
      inputClickStartTime = DateTime.now();
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
