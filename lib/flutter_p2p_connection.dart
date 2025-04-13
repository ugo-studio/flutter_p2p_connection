import 'dart:async';
import 'package:flutter_p2p_connection/transport.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';
import 'classes.dart';

// const _maxNetworkInfoPoolingTime = Duration(seconds: 6);
// const _transportDefaultPort = 8858;

class FlutterP2pConnection {
  // device information
  Future<String> getPlatformVersion() =>
      FlutterP2pConnectionPlatform.instance.getPlatformVersion();
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  // p2p permissions
  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();
  Future<bool> askP2pPermissions() async {
    await FlutterP2pConnectionPlatform.instance.askP2pPermissions();
    return await checkP2pPermissions();
  }

  // location services
  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();
  Future<bool> enableLocationServices() async {
    await FlutterP2pConnectionPlatform.instance.enableLocationServices();
    return await checkLocationEnabled();
  }

  // wifi permissions
  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();
  Future<bool> enableWifiServices() async {
    await FlutterP2pConnectionPlatform.instance.enableWifiServices();
    return await checkWifiEnabled();
  }

  // storage permissions
  Future<bool> checkStoragePermission() async =>
      (await Permission.storage.status).isGranted;
  Future<bool> askStoragePermission() async =>
      (await Permission.storage.request()).isGranted;
}

class FlutterP2pConnectionHost extends FlutterP2pConnection {
  // Private variables
  bool _groupCreated = false;
  P2pTransportHost? _p2pTransport;

  // Public variables
  bool get groupCreated => _groupCreated;
  P2pTransportHost? get p2pTransport => _p2pTransport;

  // Methods

  /// Initializes the P2P connection host.
  /// This method should be called before using any other methods in this class.
  Future<void> initialize() async {
    _p2pTransport = null;
    _groupCreated = false;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes the P2P connection host and stops the transport.
  Future<void> dispose() async {
    await FlutterP2pConnectionPlatform.instance.dispose();
    await _p2pTransport?.stop();
    _p2pTransport = null;
    _groupCreated = false;
  }

  /// Creates a hotspot for P2P connections.
  Future<void> createHotspot() async {
    await FlutterP2pConnectionPlatform.instance.createHotspot();

    // // Get network info
    // WifiNetworkInfo info = await streamWifiNetworkInfo()
    //     .timeout(_maxNetworkInfoPoolingTime, onTimeout: (evt) => evt.close())
    //     .firstWhere(
    //       (info) => info.hasInfo(),
    //       orElse: () => WifiNetworkInfo(hostIp: null, bssid: null),
    //     );
    // if (info.hasInfo()) throw Exception('Failed to get network info');

    // // create transport
    // var transport = P2pTransportHost(
    //   hostIp: info.hostIp!,
    //   defaultPort: _transportDefaultPort,
    // );
    // await transport.start();

    _groupCreated = true;
    // _p2pTransport = transport;

    // return transport;
  }

  /// Removes the hotspot and stops the transport.
  Future<void> removeHotspot() async {
    await FlutterP2pConnectionPlatform.instance.removeHotspot();
    await _p2pTransport?.stop();
    _p2pTransport = null;
    _groupCreated = false;
  }

  /// Requests hotspot information.
  Future<HotspotInfo?> requestHotspotInfo() async {
    return await FlutterP2pConnectionPlatform.instance.requestHotspotInfo();
  }
}

class FlutterP2pConnectionClient extends FlutterP2pConnection {
  // Private variables
  bool _isConnected = false;
  P2pTransportClient? _p2pTransport;

  // Public variables
  bool get isConnected => _isConnected;

  // Methods

  /// Initializes the P2P connection client.
  Future<void> initialize() async {
    _p2pTransport = null;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes the P2P connection client and stops the transport.
  Future<void> dispose() async {
    _p2pTransport = null;
    await _p2pTransport?.disconnect();
    await FlutterP2pConnectionPlatform.instance.dispose();
  }

  /// Connects to a hotspot using the provided SSID and password.
  Future<void> connectToHotspot(String ssid, String password) async {
    await FlutterP2pConnectionPlatform.instance
        .connectToHotspot(ssid, password);

    // // Get network info
    // WifiNetworkInfo info = await streamWifiNetworkInfo()
    //     .timeout(_maxNetworkInfoPoolingTime, onTimeout: (evt) => evt.close())
    //     .firstWhere(
    //       (info) => info.hasInfo(),
    //       orElse: () => WifiNetworkInfo(hostIp: null, bssid: null),
    //     );
    // if (info.hasInfo()) throw Exception('Failed to get network info');

    // // create transport
    // var transport = P2pTransportClient(
    //   hostIp: info.hostIp!,
    //   defaultPort: _transportDefaultPort,
    // );
    // await transport.connect();

    _isConnected = true;
    // _p2pTransport = transport;

    // return transport;
  }

  /// Disconnects from the hotspot and stops the transport.
  /// This method should be called when the client no longer needs to be connected to the hotspot.
  Future<void> disconnectFromHotspot() async {
    _p2pTransport = null;
    _isConnected = false;
    await _p2pTransport?.disconnect();
    await FlutterP2pConnectionPlatform.instance.disconnectFromHotspot();
  }

  /// Streams client hostspot information.
  /// This method returns a stream of [HotspotClientState] objects that contain
  /// information about the current state of the hotspot client.
  /// The stream will emit new values whenever the hotspot client state changes.
  Stream<HotspotClientState> streamHotspotClientState() {
    return FlutterP2pConnectionPlatform.instance.hotspotClientState;
  }
}
