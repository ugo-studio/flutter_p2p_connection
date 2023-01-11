import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection_method_channel.dart';

void main() {
  MethodChannelFlutterP2pConnection platform =
      MethodChannelFlutterP2pConnection();
  const MethodChannel channel = MethodChannel('flutter_p2p_connection');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
