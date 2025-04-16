import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection_platform_interface.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterP2pConnectionPlatform
    with MockPlatformInterfaceMixin
    implements FlutterP2pConnectionPlatform {
  @override
  Future<String> getPlatformVersion() => Future.value('42');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final FlutterP2pConnectionPlatform initialPlatform =
      FlutterP2pConnectionPlatform.instance;

  test('$MethodChannelFlutterP2pConnection is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterP2pConnection>());
  });

  test('getDeviceModel', () async {
    FlutterP2pConnection flutterP2pConnectionPlugin = FlutterP2pConnection();
    MockFlutterP2pConnectionPlatform fakePlatform =
        MockFlutterP2pConnectionPlatform();
    FlutterP2pConnectionPlatform.instance = fakePlatform;

    expect(await flutterP2pConnectionPlugin.getDeviceModel(), 'Test Model');
  });
}
