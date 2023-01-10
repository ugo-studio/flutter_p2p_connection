import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection_platform_interface.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterP2pConnectionPlatform
    with MockPlatformInterfaceMixin
    implements FlutterP2pConnectionPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String?> getPlatformModel() => Future.value('model');

  @override
  Future<bool?> connect(String address) => Future.value(true);

  @override
  Future<bool?> disconnect() => Future.value(true);

  @override
  Future<bool?> discover() => Future.value(true);

  @override
  Future<bool?> createGroup() => Future.value(true);

  @override
  Future<bool?> removeGroup() => Future.value(true);

  @override
  Future<String?> groupInfo() => Future.value("groupInfo");

  @override
  Future<bool?> initialize() => Future.value(true);

  @override
  Future<bool?> stopDiscovery() => Future.value(true);

  @override
  Future<List<String>?> fetchPeers() => Future.value([]);

  @override
  Future<bool?> resume() => Future.value(true);

  @override
  Future<bool?> pause() => Future.value(true);

  @override
  Future<bool?> checkLocationPermission() => Future.value(true);

  @override
  Future<bool?> askLocationPermission() => Future.value(true);

  @override
  Future<String?> checkLocationEnabled() => Future.value("true");

  @override
  Future<bool?> checkGpsEnabled() => Future.value(true);

  @override
  Future<bool?> enableLocationServices() => Future.value(true);

  @override
  Future<bool?> checkWifiEnabled() => Future.value(true);

  @override
  Future<bool?> enableWifiServices() => Future.value(true);
}

void main() {
  final FlutterP2pConnectionPlatform initialPlatform =
      FlutterP2pConnectionPlatform.instance;

  test('$MethodChannelFlutterP2pConnection is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterP2pConnection>());
  });

  test('getPlatformVersion', () async {
    FlutterP2pConnection flutterP2pConnectionPlugin = FlutterP2pConnection();
    MockFlutterP2pConnectionPlatform fakePlatform =
        MockFlutterP2pConnectionPlatform();
    FlutterP2pConnectionPlatform.instance = fakePlatform;

    expect(await flutterP2pConnectionPlugin.getPlatformVersion(), '42');
  });
}
