import 'package:flutter_test/flutter_test.dart';
import 'package:import_rknn/import_rknn.dart';
import 'package:import_rknn/import_rknn_platform_interface.dart';
import 'package:import_rknn/import_rknn_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockImportRknnPlatform
    with MockPlatformInterfaceMixin
    implements ImportRknnPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ImportRknnPlatform initialPlatform = ImportRknnPlatform.instance;

  test('$MethodChannelImportRknn is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelImportRknn>());
  });

  test('getPlatformVersion', () async {
    ImportRknn importRknnPlugin = ImportRknn();
    MockImportRknnPlatform fakePlatform = MockImportRknnPlatform();
    ImportRknnPlatform.instance = fakePlatform;

    expect(await importRknnPlugin.getPlatformVersion(), '42');
  });
}
