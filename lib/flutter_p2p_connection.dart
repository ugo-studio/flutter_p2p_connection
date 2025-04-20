import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';

// const _maxNetworkInfoPoolingTime = Duration(seconds: 6);
// const _transportDefaultPort = 8858;

class FlutterP2pConnectionBle {
  // Private variables
  bool _isAdvertising = false;
  bool _isScanning = false;

  // Public variables
  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;

  // Methods

  Future<void> dispose() async {
    _isAdvertising = false;
    _isScanning = false;
    await stopAdvertising();
    await stopScan();
  }

  Future<void> startAdvertising(String ssid, String psk) async {
    if (_isAdvertising) {
      await stopAdvertising();
    }
    await FlutterP2pConnectionPlatform.instance.startBleAdvertising(ssid, psk);
    _isAdvertising = true;
  }

  Future<void> stopAdvertising() async {
    await FlutterP2pConnectionPlatform.instance.stopBleAdvertising();
    _isAdvertising = false;
  }

  Future<StreamSubscription<BleFoundDevice>> startScan(
    void Function(BleFoundDevice)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    var streamSub =
        FlutterP2pConnectionPlatform.instance.streamBleScanResult().listen(
              onData,
              onError: onError,
              onDone: onDone,
              cancelOnError: cancelOnError,
            );
    Future.delayed(timeout).then((_) async {
      await streamSub.cancel();
      await stopScan();
    });

    try {
      await FlutterP2pConnectionPlatform.instance.startBleScan();
    } catch (_) {
      await streamSub.cancel();
      await stopScan();
      rethrow;
    }

    _isScanning = true;
    return streamSub;
  }

  Future<void> stopScan() async {
    await FlutterP2pConnectionPlatform.instance.stopBleScan();
    _isScanning = false;
  }

  Future<StreamSubscription<BleReceivedData>> connectDevice(
    String deviceAddress, {
    void Function(BleReceivedData)? onData,
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) async {
    await FlutterP2pConnectionPlatform.instance.connectBleDevice(deviceAddress);
    return FlutterP2pConnectionPlatform.instance.streamBleReceivedData().listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }

  Future<void> disconnectDevice(String deviceAddress) async {
    await FlutterP2pConnectionPlatform.instance
        .disconnectBleDevice(deviceAddress);
  }

  Stream<BleConnectionState> onConnectionStateChanged() {
    return FlutterP2pConnectionPlatform.instance.streamBleConnectionState();
  }
}

/// The [FlutterP2pConnectionHost] class represents a host for P2P connections.
/// It provides methods to create and manage a hotspot for P2P connections.
class FlutterP2pConnectionHost {
  // Private variables
  P2pTransportHost? _p2pTransport;

  // Public variables
  P2pTransportHost? get p2pTransport => _p2pTransport;

  // Methods

  /// Initializes the P2P connection host.
  /// This method should be called before using any other methods in this class.
  Future<void> initialize() async {
    _p2pTransport = null;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes the P2P connection host and stops the transport.
  Future<void> dispose() async {
    await removeGroup().catchError(
      (_) => null,
    ); // Always remove group before disposing
    await FlutterP2pConnectionPlatform.instance.dispose();
  }

  /// Creates a hotspot for P2P connections.
  Future<void> createGroup() async {
    // Create hotspot
    await FlutterP2pConnectionPlatform.instance.createHotspot();
  }

  /// Removes the hotspot and stops the transport.
  Future<void> removeGroup() async {
    // Stop the transport if it is running
    await _p2pTransport?.stop();
    _p2pTransport = null;
    // Remove the hotspot
    await FlutterP2pConnectionPlatform.instance.removeHotspot();
  }

  /// Streams hostspot information.
  /// This method returns a stream of [HotspotHostState] objects that contain
  /// information about the current state of the hotspot.
  /// The stream will emit new values whenever the hotspot state changes.
  Stream<HotspotHostState> onHotspotStateChanged() {
    return FlutterP2pConnectionPlatform.instance.streamHotspotInfo();
  }
}

/// The [FlutterP2pConnectionClient] class represents a client for P2P connections.
/// It provides methods to connect to a hotspot and manage the connection.
class FlutterP2pConnectionClient {
  // Private variables
  P2pTransportClient? _p2pTransport;

  // Methods
  /// Initializes the P2P connection client.
  Future<void> initialize() async {
    _p2pTransport = null;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes the P2P connection client and stops the transport.
  Future<void> dispose() async {
    await disconnectFromHotspot()
        .catchError((_) => null); // Always disconnect hotspot before disposing
    await FlutterP2pConnectionPlatform.instance.dispose();
  }

  /// Connects to a hotspot using the provided SSID and password.
  Future<void> connectToHotspot(String ssid, String password) async {
    await FlutterP2pConnectionPlatform.instance
        .connectToHotspot(ssid, password);
  }

  /// Disconnects from the hotspot and stops the transport.
  /// This method should be called when the client no longer needs to be connected to the hotspot.
  Future<void> disconnectFromHotspot() async {
    await _p2pTransport?.disconnect();
    _p2pTransport = null;
    await FlutterP2pConnectionPlatform.instance.disconnectFromHotspot();
  }

  /// Streams client's hostspot information.
  /// This method returns a stream of [HotspotClientState] objects that contain
  /// information about the current state of the client's hotspot.
  /// The stream will emit new values whenever the client's hotspot state changes.
  Stream<HotspotClientState> onHotspotStateChanged() {
    return FlutterP2pConnectionPlatform.instance.streamHotspotClientState();
  }
}

/// The [FlutterP2pConnection] class provides methods to manage P2P connections.
/// It includes methods to check and enable location services, Wi-Fi permissions,
class FlutterP2pConnection {
  // /// Get the platform version.
  // /// This method returns the version of the platform on which the app is running.
  // Future<String> getPlatformVersion() =>
  //     FlutterP2pConnectionPlatform.instance.getPlatformVersion();

  /// Get device model
  /// This method returns the model of the device.
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  /// Check if location services are enabled.
  /// This method checks if the location services are enabled on the device.
  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();

  /// Enable location services.
  /// This method takes user to the location settings to enable location services on the device.
  Future<bool> enableLocationServices() async {
    await FlutterP2pConnectionPlatform.instance.enableLocationServices();
    return await checkLocationEnabled();
  }

  /// Check if Wi-Fi is enabled.
  /// This method checks if the Wi-Fi is enabled on the device.
  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();

  /// Enable Wi-Fi services.
  /// This method takes user to the wifi settings to enable Wi-Fi services on the device.
  Future<bool> enableWifiServices() async {
    await FlutterP2pConnectionPlatform.instance.enableWifiServices();
    return await checkWifiEnabled();
  }

  /// Check if Bluetooth is enabled.
  /// This method checks if the Bluetooth is enabled on the device.
  Future<bool> checkBluetoothEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkBluetoothEnabled();

  /// Enable Bluetooth services.
  /// This method takes user to the bluetooth settings to enable Bluetooth services on the device.
  Future<bool> enableBluetoothServices() async {
    await FlutterP2pConnectionPlatform.instance.enableBluetoothServices();
    return await checkBluetoothEnabled();
  }

  /// Check if bluetooth permissions are granted.
  Future<bool> checkBluetoothPermissions() async {
    var perms = [
      Permission.bluetoothConnect.status,
      Permission.bluetoothAdvertise.status,
      Permission.bluetoothScan.status,
    ];
    for (var perm in perms) {
      if (!(await perm.isGranted)) {
        return false;
      }
    }
    return true;
  }

  /// Ask for Bluetooth permissions.
  Future<bool> askBluetoothPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.bluetoothConnect
    ].request();
    return await checkBluetoothPermissions();
  }

  /// Check if P2P permissions are granted.
  /// This method checks if the necessary permissions for P2P connections (NEARBY_WIFI_DEVICES, ACCESS_FINE_LOCATION and CHANGE_WIFI_STATE) are granted.
  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();

  /// Ask for P2P permissions.
  /// This method will request the necessary permissions for P2P connections (NEARBY_WIFI_DEVICES, ACCESS_FINE_LOCATION and CHANGE_WIFI_STATE).
  Future<bool> askP2pPermissions() async {
    await FlutterP2pConnectionPlatform.instance.askP2pPermissions();
    return await checkP2pPermissions();
  }

  /// Check if storage permission is granted.
  /// This method checks if the storage permission is granted on the device.
  /// This permission is required for file transfers.
  Future<bool> checkStoragePermission() async =>
      (await Permission.storage.status).isGranted;

  /// Ask for storage permission.
  /// This method will request the storage permission.
  /// This permission is required for file transfers.
  Future<bool> askStoragePermission() async =>
      (await Permission.storage.request()).isGranted;

  /// P2P connection host instance.
  /// This method returns an instance of [FlutterP2pConnectionHost] class.
  /// This class provides methods to manage P2P connections as a host.
  FlutterP2pConnectionHost host = FlutterP2pConnectionHost();

  /// P2P connection client instance.
  /// This method returns an instance of [FlutterP2pConnectionClient] class.
  /// This class provides methods to manage P2P connections as a client.
  FlutterP2pConnectionClient client = FlutterP2pConnectionClient();

  FlutterP2pConnectionBle bluetooth = FlutterP2pConnectionBle();
}

/// The [HotspotHostState] class represents the state of a hotspot host.
/// It contains information about the hotspot's SSID, pre-shared key,
/// IP address, and whether the hotspot is active or not.
/// It also includes a failure reason if the hotspot is not active.
class HotspotHostState {
  final bool isActive;
  final String? ssid;
  final String? preSharedKey;
  final String? hostIpAddress;
  final int? failureReason;

  HotspotHostState({
    required this.isActive,
    this.ssid,
    this.preSharedKey,
    this.hostIpAddress,
    this.failureReason,
  });

  factory HotspotHostState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotHostState(
      isActive: map['isActive'] as bool,
      ssid: map['ssid'] as String?,
      preSharedKey: map['preSharedKey'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
      failureReason: map['failureReason'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'ssid': ssid,
      'preSharedKey': preSharedKey,
      'hostIpAddress': hostIpAddress,
      'failureReason': failureReason,
    };
  }
}

/// The [HotspotClientState] class represents the state of a hotspot client.
/// It contains information about whether the client is active or not,
/// the host's SSID, gateway IP address, and IP address.
class HotspotClientState {
  final bool isActive;
  final String? hostSsid;
  final String? hostGatewayIpAddress;
  final String? hostIpAddress;

  HotspotClientState({
    required this.isActive,
    this.hostSsid,
    this.hostGatewayIpAddress,
    this.hostIpAddress,
  });

  factory HotspotClientState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotClientState(
      isActive: map['isActive'] as bool,
      hostSsid: map['hostSsid'] as String?,
      hostGatewayIpAddress: map['hostGatewayIpAddress'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
    );
  }
}

class BleConnectionState {
  final String deviceAddress;
  final String deviceName;
  final bool isConnected;

  BleConnectionState({
    required this.deviceAddress,
    required this.deviceName,
    required this.isConnected,
  });

  factory BleConnectionState.fromMap(Map<dynamic, dynamic> map) {
    return BleConnectionState(
      deviceAddress: map['deviceAddress'] as String,
      deviceName: map['deviceName'] as String,
      isConnected: map['isConnected'] as bool,
    );
  }
}

class BleFoundDevice {
  final String deviceAddress;
  final String deviceName;
  final int rssi;

  BleFoundDevice({
    required this.deviceAddress,
    required this.deviceName,
    required this.rssi,
  });

  factory BleFoundDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleFoundDevice(
      deviceAddress: map['deviceAddress'] as String,
      deviceName: map['deviceName'] as String,
      rssi: map['rssi'] as int,
    );
  }
}

class BleReceivedData {
  final String deviceAddress;
  final String characteristicUuid;
  final Uint8List data;

  BleReceivedData({
    required this.deviceAddress,
    required this.characteristicUuid,
    required this.data,
  });

  factory BleReceivedData.fromMap(Map<dynamic, dynamic> map) {
    return BleReceivedData(
      deviceAddress: map['deviceAddress'] as String,
      characteristicUuid: map['characteristicUuid'] as String,
      data: map['data'] as Uint8List,
    );
  }
}
