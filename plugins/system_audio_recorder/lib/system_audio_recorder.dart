
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'system_audio_recorder_platform_interface.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class SystemAudioRecorder {
  static const EventChannel audioStream = EventChannel('system_audio_recorder/audio_stream');
  Future<String?> getPlatformVersion() {
    return SystemAudioRecorderPlatform.instance.getPlatformVersion();
  }
  static Future<bool> requestRecord(String name, {String? titleNotification, String? messageNotification, int? sampleRate}) async {
    try {
      if (titleNotification == null) {
        titleNotification = "";
      }
      if (messageNotification == null) {
        messageNotification = "";
      }

      if (sampleRate == null){
        sampleRate = 44100;
      }

      await _maybeStartFGS(titleNotification, messageNotification);
      final bool start = await SystemAudioRecorderPlatform.instance.requestRecord(
        name,
        notificationTitle: titleNotification,
        notificationMessage: messageNotification,
        sampleRate: sampleRate,
      );

      return start;
    } catch (err) {
      print("startRecord err");
      print(err);
    }

    return false;
  }

  static Future<bool> get startRecord async {
    try {

      final bool start = await SystemAudioRecorderPlatform.instance.startRecord();

      return start;
    } catch (err) {
      print("startRecord err");
      print(err);
    }
    return false;
  }

  static Future<String> get stopRecord async {
    try {
      final String path = await SystemAudioRecorderPlatform.instance.stopRecord;
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.stopService();
      }
      return path;
    } catch (err) {
      print("stopRecord err");
      print(err);
    }
    return "";
  }

  // static Stream<List<int>> get audioStream {
  //   return _audioStream.receiveBroadcastStream({"config": "null"}).map((data) => List<int>.from(data));
  // }

  static _maybeStartFGS(String titleNotification, String messageNotification) {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'notification_channel_id',
            channelName: titleNotification,
            channelDescription: messageNotification,
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
            iconData: const NotificationIconData(
              resType: ResourceType.mipmap,
              resPrefix: ResourcePrefix.ic,
              name: 'launcher',
            ),
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: true,
            playSound: false,
          ),
          foregroundTaskOptions: const ForegroundTaskOptions(
            interval: 5000,
            autoRunOnBoot: true,
            allowWifiLock: true,
          ),
        );
      }
    } catch (err) {
      print("_maybeStartFGS err");
      print(err);
    }
  }

}
