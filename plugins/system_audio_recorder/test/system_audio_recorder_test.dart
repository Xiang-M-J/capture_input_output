import 'package:flutter_test/flutter_test.dart';
import 'package:system_audio_recorder/system_audio_recorder.dart';
import 'package:system_audio_recorder/system_audio_recorder_platform_interface.dart';
import 'package:system_audio_recorder/system_audio_recorder_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSystemAudioRecorderPlatform
    with MockPlatformInterfaceMixin
    implements SystemAudioRecorderPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SystemAudioRecorderPlatform initialPlatform = SystemAudioRecorderPlatform.instance;

  test('$MethodChannelSystemAudioRecorder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSystemAudioRecorder>());
  });

  test('getPlatformVersion', () async {
    SystemAudioRecorder systemAudioRecorderPlugin = SystemAudioRecorder();
    MockSystemAudioRecorderPlatform fakePlatform = MockSystemAudioRecorderPlatform();
    SystemAudioRecorderPlatform.instance = fakePlatform;

    expect(await systemAudioRecorderPlugin.getPlatformVersion(), '42');
  });
}
