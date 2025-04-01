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

  Future<String> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String> getPlatformModel() {
    throw UnimplementedError('getPlatformModel() has not been implemented.');
  }

  Future<bool> initialize() {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<bool> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  Future<bool> startPeerDiscovery() {
    throw UnimplementedError('startPeerDiscovery() has not been implemented.');
  }

  Future<bool> stopPeerDiscovery() {
    throw UnimplementedError('stopPeerDiscovery() has not been implemented.');
  }

  Future<bool> connect(String address) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  Future<bool> createGroup() {
    throw UnimplementedError('createGroup() has not been implemented.');
  }

  Future<bool> removeGroup() {
    throw UnimplementedError('removeGroup() has not been implemented.');
  }

  Future<Map<dynamic, dynamic>?> requestGroupInfo() {
    throw UnimplementedError('requestGroupInfo() has not been implemented.');
  }

  Future<List<dynamic>> fetchPeers() {
    throw UnimplementedError('fetchPeers() has not been implemented.');
  }

  Future<Map<dynamic, dynamic>?> fetchConnectionInfo() {
    throw UnimplementedError('fetchConnectionInfo() has not been implemented.');
  }

  Future<bool> checkP2pPermissions() {
    throw UnimplementedError('checkP2pPermissions() has not been implemented.');
  }

  Future<bool> askP2pPermissions() {
    throw UnimplementedError(
        'askLocationPermissions() has not been implemented.');
  }

  Future<bool> checkLocationEnabled() {
    throw UnimplementedError(
        'checkLocationEnabled() has not been implemented.');
  }

  Future<bool> enableLocationServices() {
    throw UnimplementedError(
        'enableLocationServices() has not been implemented.');
  }

  Future<bool> checkWifiEnabled() {
    throw UnimplementedError('checkWifiEnabled() has not been implemented.');
  }

  Future<bool> enableWifiServices() {
    throw UnimplementedError('enableWifiServices() has not been implemented.');
  }
}
