import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'system_audio_recorder_method_channel.dart';

abstract class SystemAudioRecorderPlatform extends PlatformInterface {
  /// Constructs a SystemAudioRecorderPlatform.
  SystemAudioRecorderPlatform() : super(token: _token);

  static final Object _token = Object();

  static SystemAudioRecorderPlatform _instance = MethodChannelSystemAudioRecorder();

  /// The default instance of [SystemAudioRecorderPlatform] to use.
  ///
  /// Defaults to [MethodChannelSystemAudioRecorder].
  static SystemAudioRecorderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SystemAudioRecorderPlatform] when
  /// they register themselves.
  static set instance(SystemAudioRecorderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> startRecord(){
    throw UnimplementedError();
  }

  Future<bool> requestRecord(
      String name, {
        String notificationTitle = "",
        String notificationMessage = "",
        int sampleRate = 44100
      }) {
    throw UnimplementedError();
  }

  Future<String> get stopRecord {
    throw UnimplementedError();
  }
}
