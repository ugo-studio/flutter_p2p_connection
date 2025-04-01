import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_p2p_connection_platform_interface.dart';

/// An implementation of [FlutterP2pConnectionPlatform] that uses method channels.
class MethodChannelFlutterP2pConnection extends FlutterP2pConnectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_p2p_connection');

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
  Future<bool> initialize() async {
    bool initialized = await methodChannel.invokeMethod("initialize");
    return initialized;
  }

  @override
  Future<bool> dispose() async {
    bool disposed = await methodChannel.invokeMethod("dispose");
    return disposed;
  }

  @override
  Future<bool> createGroup() async {
    final created = await methodChannel.invokeMethod("createGroup");
    return created;
  }

  @override
  Future<bool> removeGroup() async {
    final removed = await methodChannel.invokeMethod("removeGroup");
    return removed;
  }

  @override
  Future<Map<dynamic, dynamic>?> requestGroupInfo() async {
    final info = await methodChannel.invokeMethod("requestGroupInfo");
    return info;
  }

  @override
  Future<bool> startPeerDiscovery() async {
    bool started = await methodChannel.invokeMethod("startPeerDiscovery");
    return started;
  }

  @override
  Future<bool> stopPeerDiscovery() async {
    bool stopped = await methodChannel.invokeMethod("stopPeerDiscovery");
    return stopped;
  }

  @override
  Future<bool> connect(String address) async {
    final connected =
        await methodChannel.invokeMethod("connect", {"address": address});
    return connected;
  }

  @override
  Future<bool> disconnect() async {
    final disconnected = await methodChannel.invokeMethod("disconnect");
    return disconnected;
  }

  @override
  Future<List<dynamic>> fetchPeers() async {
    var peers = await methodChannel.invokeMethod("fetchPeers");
    return List.castFrom(peers);
  }

  @override
  Future<Map<dynamic, dynamic>?> fetchConnectionInfo() async {
    var info = await methodChannel.invokeMethod("fetchConnectionInfo");
    return info;
  }

  @override
  Future<bool> checkP2pPermissions() async {
    bool granted = await methodChannel.invokeMethod("checkP2pPermissions");
    return granted;
  }

  @override
  Future<bool> askP2pPermissions() async {
    bool granted = await methodChannel.invokeMethod("askP2pPermissions");
    return granted;
  }

  @override
  Future<bool> checkLocationEnabled() async {
    bool enabled = await methodChannel.invokeMethod("checkLocationEnabled");
    return enabled;
  }

  @override
  Future<bool> enableLocationServices() async {
    bool enabled = await methodChannel.invokeMethod("enableLocationServices");
    return enabled;
  }

  @override
  Future<bool> checkWifiEnabled() async {
    bool enabled = await methodChannel.invokeMethod("checkWifiEnabled");
    return enabled;
  }

  @override
  Future<bool> enableWifiServices() async {
    final enabled = await methodChannel.invokeMethod("enableWifiServices");
    return enabled;
  }
}
