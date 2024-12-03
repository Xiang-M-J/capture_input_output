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

  Future<bool> requestRecord(
      String name, {
        String notificationTitle = "",
        String notificationMessage = "",
        int sampleRate = 44100
      }) async {
    final bool start = await methodChannel.invokeMethod('requestRecord', {
      "name": name,
      "title": notificationTitle,
      "message": notificationMessage,
      "sampleRate": sampleRate
    });
    return start;
  }

  Future<bool> startRecord() async{
    final bool start = await methodChannel.invokeMethod("startRecord");
    return start;
  }


  Future<String> get stopRecord async {
    final String path = await methodChannel.invokeMethod('stopRecord');
    return path;
  }
}
