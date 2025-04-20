import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'flutter_p2p_connection_platform_interface.dart';

/// An implementation of [FlutterP2pConnectionPlatform] that uses method channels.
class MethodChannelFlutterP2pConnection extends FlutterP2pConnectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('flutter_p2p_connection');

  /// The event channel used for hotspot connection info events.
  @visibleForTesting
  final EventChannel hotspotStateEventChannel =
      const EventChannel('flutter_p2p_connection_hotspotState');
  @visibleForTesting
  final EventChannel clientStateEventChannel =
      const EventChannel('flutter_p2p_connection_clientState');
  @visibleForTesting
  final EventChannel bleConnectionStateEventChannel =
      const EventChannel('flutter_p2p_connection_bleConnectionState');
  @visibleForTesting
  final EventChannel bleScanResultEventChannel =
      const EventChannel('flutter_p2p_connection_bleScanResult');
  @visibleForTesting
  final EventChannel bleReceivedDataEventChannel =
      const EventChannel('flutter_p2p_connection_bleReceivedData');

  @override
  Future<String> getPlatformVersion() async {
    String version = await methodChannel.invokeMethod('getPlatformVersion');
    return version;
  }

  @override
  Future<String> getPlatformModel() async {
    String model = await methodChannel.invokeMethod('getPlatformModel');
    return model;
  }

  @override
  Future<void> initialize() async {
    await methodChannel.invokeMethod('initialize');
  }

  @override
  Future<void> dispose() async {
    await methodChannel.invokeMethod('dispose');
  }

  @override
  Future<void> createHotspot() async {
    await methodChannel.invokeMethod('createHotspot');
  }

  @override
  Future<void> removeHotspot() async {
    await methodChannel.invokeMethod('removeHotspot');
  }

  @override
  Future<void> connectToHotspot(String ssid, String psk) async {
    await methodChannel.invokeMethod(
      'connectToHotspot',
      {
        'ssid': ssid,
        'psk': psk,
      },
    );
  }

  @override
  Future<void> disconnectFromHotspot() async {
    await methodChannel.invokeMethod('disconnectFromHotspot');
  }

  @override
  Future<void> startBleAdvertising(String ssid, String psk) async {
    await methodChannel.invokeMethod(
      'ble#startAdvertising',
      {
        'ssid': ssid,
        'psk': psk,
      },
    );
  }

  @override
  Future<void> stopBleAdvertising() async {
    await methodChannel.invokeMethod('ble#stopAdvertising');
  }

  @override
  Future<void> startBleScan() async {
    await methodChannel.invokeMethod('ble#startScan');
  }

  @override
  Future<void> stopBleScan() async {
    await methodChannel.invokeMethod('ble#stopScan');
  }

  @override
  Future<void> connectBleDevice(String deviceAddress) async {
    await methodChannel.invokeMethod(
      'ble#connect',
      {'deviceAddress': deviceAddress},
    );
  }

  @override
  Future<void> disconnectBleDevice(String deviceAddress) async {
    await methodChannel.invokeMethod(
      'ble#disconnect',
      {'deviceAddress': deviceAddress},
    );
  }

  @override
  Future<bool> checkP2pPermissions() async {
    bool? hasPermission =
        await methodChannel.invokeMethod('checkP2pPermissions');
    return hasPermission ?? false;
  }

  @override
  Future<void> askP2pPermissions() async {
    await methodChannel.invokeMethod('askP2pPermissions');
  }

  @override
  Future<bool> checkLocationEnabled() async {
    bool? enabled = await methodChannel.invokeMethod('checkLocationEnabled');
    return enabled ?? false;
  }

  @override
  Future<void> enableLocationServices() async {
    await methodChannel.invokeMethod('enableLocationServices');
  }

  @override
  Future<bool> checkWifiEnabled() async {
    bool? enabled = await methodChannel.invokeMethod('checkWifiEnabled');
    return enabled ?? false;
  }

  @override
  Future<void> enableWifiServices() async {
    await methodChannel.invokeMethod('enableWifiServices');
  }

  @override
  Future<bool> checkBluetoothEnabled() async {
    bool? enabled = await methodChannel.invokeMethod('checkBluetoothEnabled');
    return enabled ?? false;
  }

  @override
  Future<void> enableBluetoothServices() async {
    await methodChannel.invokeMethod('enableBluetoothServices');
  }

  /// Returns a broadcast stream of [HotspotHostState] updates from the native platform.
  @override
  Stream<HotspotHostState> streamHotspotInfo() {
    var stream = hotspotStateEventChannel.receiveBroadcastStream().map(
      (dynamic event) {
        return HotspotHostState.fromMap(Map.from(event));
      },
    );
    return stream;
  }

  /// Returns a broadcast stream of [HotspotClientState] updates from the native platform.
  @override
  Stream<HotspotClientState> streamHotspotClientState() {
    var stream = clientStateEventChannel.receiveBroadcastStream().map(
      (dynamic evt) {
        return HotspotClientState.fromMap(Map.from(evt));
      },
    );
    return stream;
  }

  @override
  Stream<BleConnectionState> streamBleConnectionState() {
    var stream = bleConnectionStateEventChannel.receiveBroadcastStream().map(
      (dynamic evt) {
        return BleConnectionState.fromMap(Map.from(evt));
      },
    );
    return stream;
  }

  @override
  Stream<List<BleFoundDevice>> streamBleScanResult() {
    var stream = bleScanResultEventChannel.receiveBroadcastStream().map(
      (dynamic evt) {
        return List.from(evt)
            .map((device) => BleFoundDevice.fromMap(Map.from(device)))
            .toList();
      },
    );
    return stream;
  }

  @override
  Stream<BleReceivedData> streamBleReceivedData() {
    var stream = bleReceivedDataEventChannel.receiveBroadcastStream().map(
      (dynamic evt) {
        return BleReceivedData.fromMap(Map.from(evt));
      },
    );
    return stream;
  }
}
