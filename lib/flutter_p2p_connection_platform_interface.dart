import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_p2p_connection_method_channel.dart';

abstract class FlutterP2pConnectionPlatform extends PlatformInterface {
  /// Constructs a FlutterP2pConnectionPlatform.
  FlutterP2pConnectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterP2pConnectionPlatform _instance =
      MethodChannelFlutterP2pConnection();

  /// The default instance of [FlutterP2pConnectionPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterP2pConnection].
  static FlutterP2pConnectionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterP2pConnectionPlatform] when
  /// they register themselves.
  static set instance(FlutterP2pConnectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> getPlatformVersion() async {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  Future<String> getPlatformModel() async {
    throw UnimplementedError('getPlatformModel() has not been implemented.');
  }

  Future<void> initialize({ String? serviceUuid }) async {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<void> dispose() async {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  Future<void> createHotspot() async {
    throw UnimplementedError('createHotspot() has not been implemented.');
  }

  Future<void> removeHotspot() async {
    throw UnimplementedError('removeHotspot() has not been implemented.');
  }

  Future<void> connectToHotspot(String ssid, String psk) async {
    throw UnimplementedError('connectToHotspot() has not been implemented.');
  }

  Future<void> disconnectFromHotspot() async {
    throw UnimplementedError(
        'disconnectFromHotspot() has not been implemented.');
  }

  Future<void> startBleAdvertising(String ssid, String psk) async {
    throw UnimplementedError('startBleAdvertising() has not been implemented.');
  }

  Future<void> stopBleAdvertising() async {
    throw UnimplementedError('stopBleAdvertising() has not been implemented.');
  }

  Future<void> startBleScan() async {
    throw UnimplementedError('startBleScan() has not been implemented.');
  }

  Future<void> stopBleScan() async {
    throw UnimplementedError('stopBleScan() has not been implemented.');
  }

  Future<void> connectBleDevice(String deviceAddress) async {
    throw UnimplementedError('connectBleDevice() has not been implemented.');
  }

  Future<void> disconnectBleDevice(String deviceAddress) async {
    throw UnimplementedError('disconnectBleDevice() has not been implemented.');
  }

  Future<bool> checkP2pPermissions() async {
    throw UnimplementedError('checkP2pPermissions() has not been implemented.');
  }

  Future<void> askP2pPermissions() async {
    throw UnimplementedError('askP2pPermissions() has not been implemented.');
  }

  Future<bool> checkLocationEnabled() async {
    throw UnimplementedError(
        'checkLocationEnabled() has not been implemented.');
  }

  Future<void> enableLocationServices() async {
    throw UnimplementedError(
        'enableLocationServices() has not been implemented.');
  }

  Future<bool> checkWifiEnabled() async {
    throw UnimplementedError('checkWifiEnabled() has not been implemented.');
  }

  Future<void> enableWifiServices() async {
    throw UnimplementedError('enableWifiServices() has not been implemented.');
  }

  Future<bool> checkBluetoothEnabled() async {
    throw UnimplementedError(
        'checkBluetoothEnabled() has not been implemented.');
  }

  Future<void> enableBluetoothServices() async {
    throw UnimplementedError(
        'enableBluetoothServices() has not been implemented.');
  }

  Stream<HotspotHostState> streamHotspotInfo() {
    throw UnimplementedError('streamHotspotInfo() has not been implemented.');
  }

  Stream<HotspotClientState> streamHotspotClientState() {
    throw UnimplementedError(
        'streamHotspotClientState() has not been implemented.');
  }

  Stream<BleConnectionState> streamBleConnectionState() {
    throw UnimplementedError(
        'streamBleConnectionState() has not been implemented.');
  }

  Stream<List<BleDiscoveredDevice>> streamBleScanResult() {
    throw UnimplementedError('streamBleScanResult() has not been implemented.');
  }

  Stream<BleReceivedData> streamBleReceivedData() {
    throw UnimplementedError(
        'streamBleReceivedData() has not been implemented.');
  }
}
