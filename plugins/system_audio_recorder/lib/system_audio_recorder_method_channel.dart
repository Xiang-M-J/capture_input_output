import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'system_audio_recorder_platform_interface.dart';

/// An implementation of [SystemAudioRecorderPlatform] that uses method channels.
class MethodChannelSystemAudioRecorder extends SystemAudioRecorderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('system_audio_recorder');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> openRecorder({int sampleRate = 16000, int bufferSize = 640}) async {
    final bool isOpen = await methodChannel.invokeMethod("openRecorder", {
      "sampleRate": sampleRate, "bufferSize": bufferSize
    });
    return isOpen;
  }

  @override
  Future<bool> requestRecord(
      String name, {
        String notificationTitle = "",
        String notificationMessage = ""
      }) async {
    final bool start = await methodChannel.invokeMethod('requestRecord', {
      "name": name,
      "title": notificationTitle,
      "message": notificationMessage,
    });
    return start;
  }

  @override
  Future<bool> startRecord() async{
    final bool start = await methodChannel.invokeMethod("startRecord");
    return start;
  }

  @override
  Future<void> dispose() async {
    await methodChannel.invokeMethod("dispose");
  }

  @override
  Future<String> stopRecord() async {
    final String path = await methodChannel.invokeMethod('stopRecord');
    return path;
  }
}
