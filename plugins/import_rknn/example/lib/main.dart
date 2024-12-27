
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:import_rknn/import_rknn.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _importRknnPlugin = ImportRknn();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _importRknnPlugin.getPlatformVersion() ?? 'Unknown platform version';
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
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body:

        Center(
          child: Column(
            children: [
              Text('Running on: $_platformVersion\n'),
              ElevatedButton(onPressed: () async {
                final info = await _importRknnPlugin.test();
                print(info);
              }, child: const Text("test")),
              ElevatedButton(onPressed: () async {
                final raw = await rootBundle.load("assets/msa_dpcrn.rknn");
                final status = await _importRknnPlugin.initModel(raw.buffer.asUint8List());
                print(status);
              }, child: const Text("init model")),
              ElevatedButton(onPressed: () async {
                int micSize = 2 * 65;
                int stateSize = 4 * 1 * 16 * 64;
                Float32List mic = Float32List.fromList(List<double>.generate(micSize, (i) => i / 1000));
                Float32List ref = Float32List.fromList(List<double>.generate(micSize, (i) => i / 1000 + 0.2));
                Float32List h = Float32List(stateSize);
                Float32List c = Float32List(stateSize);
                for (var i = 0; i < 1; i ++){
                  Map? result = await _importRknnPlugin.inference(mic, ref, h, c);
                  List<double> ho = List<double>.from(result!['ho']) ;
                  print(ho[0]);
                  // for(var i = 0; i<100; i++){
                  //   print(ho[i]);
                  // }
                  // sleep(const Duration(milliseconds: 20));
                  // if (result != null){
                  //   print(result.keys);
                  // }
                }


              }, child: const Text("inference")),
              ElevatedButton(onPressed: () async {
                await _importRknnPlugin.destroy();
              }, child: const Text("destroy")),
              ElevatedButton(onPressed: () async {
                final raw = await rootBundle.load("assets/mobilenet_v1.rknn");
                final status = await _importRknnPlugin.initMobileModel(raw.buffer.asUint8List());
                print(status);
              }, child: const Text("init mobile model")),

              ElevatedButton(onPressed: () async{
                final raw = await rootBundle.load("assets/dog.jpg");
                final status = await _importRknnPlugin.imgInference(raw.buffer.asUint8List());
                print(status);
              }, child: const Text("run img inference"))
            ],
          )
        ),
      ),
    );
  }
}
