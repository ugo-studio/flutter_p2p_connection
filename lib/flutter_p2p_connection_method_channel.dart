import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_p2p_connection/classes.dart';
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

  Stream<HotspotHostState>? _hotspotInfo;
  Stream<HotspotClientState>? _hotspotClientState;

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
  Future<void> connectToHotspot(String ssid, String password) async {
    await methodChannel.invokeMethod('connectToHotspot', {
      'ssid': ssid,
      'password': password,
    });
  }

  @override
  Future<void> disconnectFromHotspot() async {
    await methodChannel.invokeMethod('disconnectFromHotspot');
  }

  @override
  Future<bool> checkP2pPermissions() async {
    final bool? hasPermission =
        await methodChannel.invokeMethod('checkP2pPermissions');
    return hasPermission ?? false;
  }

  @override
  Future<void> askP2pPermissions() async {
    await methodChannel.invokeMethod('askP2pPermissions');
  }

  @override
  Future<bool> checkLocationEnabled() async {
    final bool? enabled =
        await methodChannel.invokeMethod('checkLocationEnabled');
    return enabled ?? false;
  }

  @override
  Future<void> enableLocationServices() async {
    await methodChannel.invokeMethod('enableLocationServices');
  }

  @override
  Future<bool> checkWifiEnabled() async {
    final bool? enabled = await methodChannel.invokeMethod('checkWifiEnabled');
    return enabled ?? false;
  }

  @override
  Future<void> enableWifiServices() async {
    await methodChannel.invokeMethod('enableWifiServices');
  }

  /// Returns a broadcast stream of [HotspotHostState] updates from the native platform.
  @override
  Stream<HotspotHostState> get hotspotInfo {
    _hotspotInfo ??= hotspotStateEventChannel.receiveBroadcastStream().map(
          (dynamic event) => HotspotHostState.fromMap(Map.castFrom(event)),
        );
    return _hotspotInfo!;
  }

  /// Returns a broadcast stream of [HotspotClientState] updates from the native platform.
  @override
  Stream<HotspotClientState> get hotspotClientState {
    _hotspotClientState ??=
        clientStateEventChannel.receiveBroadcastStream().map(
              (dynamic event) =>
                  HotspotClientState.fromMap(Map.castFrom(event)),
            );
    return _hotspotClientState!;
  }
}
