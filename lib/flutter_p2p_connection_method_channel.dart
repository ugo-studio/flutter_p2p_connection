import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_p2p_connection_platform_interface.dart';

/// An implementation of [FlutterP2pConnectionPlatform] that uses method channels.
class MethodChannelFlutterP2pConnection extends FlutterP2pConnectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_p2p_connection');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool?> initialize() async {
    final initialized = await methodChannel.invokeMethod<bool?>("initialize");
    return initialized;
  }

  @override
  Future<bool?> discover() async {
    final discovering = await methodChannel.invokeMethod<bool?>("discover");
    return discovering;
  }

  @override
  Future<bool?> stopDiscovery() async {
    final stopped = await methodChannel.invokeMethod<bool?>("stopDiscovery");
    return stopped;
  }

  @override
  Future<bool?> connect(String address) async {
    final arg = {
      "address": address,
    };
    final connected = await methodChannel.invokeMethod<bool?>("connect", arg);
    return connected;
  }

  @override
  Future<bool?> disconnect() async {
    final disconnected = await methodChannel.invokeMethod<bool?>("disconnect");
    return disconnected;
  }

  @override
  Future<bool?> createGroup() async {
    final created = await methodChannel.invokeMethod<bool?>("createGroup");
    return created;
  }

  @override
  Future<bool?> removeGroup() async {
    final removed = await methodChannel.invokeMethod<bool?>("removeGroup");
    return removed;
  }

  @override
  Future<String?> groupInfo() async {
    final info = await methodChannel.invokeMethod<String?>("groupInfo");
    return info;
  }

  @override
  Future<List<String>?> fetchPeers() async {
    final peers = await methodChannel.invokeMethod<List<Object?>>("fetchPeers");
    List<String>? p = [];
    if (peers == null) return [];
    for (var obj in peers) {
      p.add(obj.toString());
    }
    return p;
  }

  @override
  Future<bool?> resume() async {
    final resume = await methodChannel.invokeMethod<bool?>("resume");
    return resume;
  }

  @override
  Future<bool?> pause() async {
    final pause = await methodChannel.invokeMethod<bool?>("pause");
    return pause;
  }
}
