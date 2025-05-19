import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'flutter_p2p_connection_platform_interface.dart';

/// An implementation of [FlutterP2pConnectionPlatform] that uses method channels
/// for communication with the native platform code (Android/iOS).
class MethodChannelFlutterP2pConnection extends FlutterP2pConnectionPlatform {
  /// The method channel used to invoke native methods.
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('flutter_p2p_connection');

  // --- Event Channels for receiving streams from native ---

  /// The event channel for receiving [HotspotHostState] updates.
  @visibleForTesting
  final EventChannel hotspotStateEventChannel =
      const EventChannel('flutter_p2p_connection_hotspotState');

  /// The event channel for receiving [HotspotClientState] updates.
  @visibleForTesting
  final EventChannel clientStateEventChannel =
      const EventChannel('flutter_p2p_connection_clientState');

  /// The event channel for receiving [BleConnectionState] updates.
  @visibleForTesting
  final EventChannel bleConnectionStateEventChannel =
      const EventChannel('flutter_p2p_connection_bleConnectionState');

  /// The event channel for receiving lists of [BleDiscoveredDevice] during scans.
  @visibleForTesting
  final EventChannel bleScanResultEventChannel =
      const EventChannel('flutter_p2p_connection_bleScanResult');

  /// The event channel for receiving [BleReceivedData] from connected BLE devices.
  @visibleForTesting
  final EventChannel bleReceivedDataEventChannel =
      const EventChannel('flutter_p2p_connection_bleReceivedData');

  // --- Cached Stream Instances ---
  // Caching streams avoids recreating the stream pipeline on every call.
  Stream<HotspotHostState>? _hotspotInfoStream;
  Stream<HotspotClientState>? _clientStateStream;
  Stream<BleConnectionState>? _bleConnectionStateStream;
  Stream<List<BleDiscoveredDevice>>? _bleScanResultStream;
  Stream<BleReceivedData>? _bleReceivedDataStream;

  /// Fetches the native platform version string.
  ///
  /// Example: "Android 13" or "iOS 16.1".
  /// Returns a [Future] completing with the platform version string.
  @override
  Future<String> getPlatformVersion() async {
    final String version =
        await methodChannel.invokeMethod('getPlatformVersion') ??
            'Unknown Platform Version';
    return version;
  }

  /// Fetches the native device model identifier.
  ///
  /// Example: "Pixel 7 Pro" or "iPhone14,5".
  /// Returns a [Future] completing with the device model string.
  @override
  Future<String> getPlatformModel() async {
    final String model = await methodChannel.invokeMethod('getPlatformModel') ??
        'Unknown Device Model';
    return model;
  }

  /// Initializes native P2P and BLE resources.
  ///
  /// Must be called before most other host or client operations.
  /// Returns a [Future] that completes when initialization is done.
  @override
  Future<void> initialize({
    String? serviceUuid,
    bool? bondingRequired,
    bool? encryptionRequired,
  }) async {
    await methodChannel.invokeMethod('initialize', {
      'serviceUuid': serviceUuid,
      'bondingRequired': bondingRequired,
      'encryptionRequired': encryptionRequired,
    });
  }

  /// Disposes native P2P and BLE resources and cleans up connections.
  ///
  /// Should be called when the plugin is no longer needed to release
  /// system resources.
  /// Returns a [Future] that completes when disposal is done.
  @override
  Future<void> dispose() async {
    // Clear cached streams on dispose
    _hotspotInfoStream = null;
    _clientStateStream = null;
    _bleConnectionStateStream = null;
    _bleScanResultStream = null;
    _bleReceivedDataStream = null;
    await methodChannel.invokeMethod('dispose');
  }

  /// Initiates the creation of a Wi-Fi Direct group (hotspot) on the native side.
  ///
  /// Listen to [streamHotspotInfo] for state updates including SSID, PSK, and IP address.
  /// Returns a [Future] that completes when the creation process is initiated.
  @override
  Future<void> createHotspot() async {
    await methodChannel.invokeMethod('createHotspot');
  }

  /// Removes the currently active Wi-Fi Direct group (hotspot) on the native side.
  ///
  /// Returns a [Future] that completes when the removal process is initiated.
  @override
  Future<void> removeHotspot() async {
    await methodChannel.invokeMethod('removeHotspot');
  }

  /// Initiates a connection attempt to a Wi-Fi Direct hotspot using the provided credentials.
  ///
  /// - [ssid]: The network name (SSID) of the target hotspot.
  /// - [psk]: The password (Pre-Shared Key) of the target hotspot.
  /// Listen to [streamHotspotClientState] for connection status updates.
  /// Returns a [Future] that completes when the connection attempt is initiated.
  @override
  Future<void> connectToHotspot(String ssid, String psk) async {
    await methodChannel.invokeMethod(
      'connectToHotspot',
      {'ssid': ssid, 'psk': psk},
    );
  }

  /// Disconnects from the currently connected Wi-Fi Direct hotspot.
  ///
  /// Returns a [Future] that completes when the disconnection process is initiated.
  @override
  Future<void> disconnectFromHotspot() async {
    await methodChannel.invokeMethod('disconnectFromHotspot');
  }

  /// Starts BLE advertising with the provided Wi-Fi hotspot credentials.
  ///
  /// This allows BLE clients to discover the hotspot's SSID and PSK.
  /// - [ssid]: The network name (SSID) to advertise.
  /// - [psk]: The password (Pre-Shared Key) to advertise.
  /// Requires necessary Bluetooth permissions.
  /// Returns a [Future] that completes when advertising is started.
  @override
  Future<void> startBleAdvertising(String ssid, String psk) async {
    await methodChannel.invokeMethod(
      'ble#startAdvertising',
      {'ssid': ssid, 'psk': psk},
    );
  }

  /// Stops ongoing BLE advertising.
  ///
  /// Returns a [Future] that completes when advertising is stopped.
  @override
  Future<void> stopBleAdvertising() async {
    await methodChannel.invokeMethod('ble#stopAdvertising');
  }

  /// Starts scanning for nearby BLE devices.
  ///
  /// Listen to [streamBleScanResult] for discovered devices.
  /// Requires necessary Bluetooth and Location permissions.
  /// Returns a [Future] that completes when the scan is initiated.
  @override
  Future<void> startBleScan() async {
    await methodChannel.invokeMethod('ble#startScan');
  }

  /// Stops the ongoing BLE scan.
  ///
  /// Returns a [Future] that completes when the scan is stopped.
  @override
  Future<void> stopBleScan() async {
    await methodChannel.invokeMethod('ble#stopScan');
  }

  /// Initiates a connection attempt to a specific BLE device.
  ///
  /// - [deviceAddress]: The MAC address of the target BLE device.
  /// Listen to [streamBleConnectionState] for connection status updates and
  /// [streamBleReceivedData] for data received from the device.
  /// Returns a [Future] that completes when the connection attempt is initiated.
  @override
  Future<void> connectBleDevice(String deviceAddress) async {
    await methodChannel.invokeMethod(
      'ble#connect',
      {'deviceAddress': deviceAddress},
    );
  }

  /// Disconnects from a connected BLE device.
  ///
  /// - [deviceAddress]: The MAC address of the BLE device to disconnect from.
  /// Returns a [Future] that completes when the disconnection process is initiated.
  @override
  Future<void> disconnectBleDevice(String deviceAddress) async {
    await methodChannel.invokeMethod(
      'ble#disconnect',
      {'deviceAddress': deviceAddress},
    );
  }

  /// Checks if the necessary Wi-Fi P2P (Wi-Fi Direct) permissions are granted.
  ///
  /// Permissions may include Location and Nearby Devices depending on the platform version.
  /// Returns a [Future] completing with `true` if permissions are granted, `false` otherwise.
  @override
  Future<bool> checkP2pPermissions() async {
    final bool? hasPermission =
        await methodChannel.invokeMethod('checkP2pPermissions');
    return hasPermission ?? false;
  }

  /// Requests necessary Wi-Fi P2P (Wi-Fi Direct) permissions from the user.
  ///
  /// This will typically show system dialogs.
  /// Returns a [Future] that completes when the permission request flow finishes.
  /// Check the result using [checkP2pPermissions] afterwards.
  @override
  Future<void> askP2pPermissions() async {
    await methodChannel.invokeMethod('askP2pPermissions');
  }

  /// Checks if location services are enabled on the device.
  ///
  /// Often required for Wi-Fi and BLE scanning.
  /// Returns a [Future] completing with `true` if enabled, `false` otherwise.
  @override
  Future<bool> checkLocationEnabled() async {
    final bool? enabled =
        await methodChannel.invokeMethod('checkLocationEnabled');
    return enabled ?? false;
  }

  /// Attempts to open the device's location settings screen for the user to enable location services.
  ///
  /// Returns a [Future] that completes when the settings screen is opened.
  /// Check the result using [checkLocationEnabled] after the user returns to the app.
  @override
  Future<void> enableLocationServices() async {
    await methodChannel.invokeMethod('enableLocationServices');
  }

  /// Checks if Wi-Fi is enabled on the device.
  ///
  /// Returns a [Future] completing with `true` if enabled, `false` otherwise.
  @override
  Future<bool> checkWifiEnabled() async {
    final bool? enabled = await methodChannel.invokeMethod('checkWifiEnabled');
    return enabled ?? false;
  }

  /// Attempts to open the device's Wi-Fi settings screen for the user to enable Wi-Fi.
  ///
  /// Returns a [Future] that completes when the settings screen is opened.
  /// Check the result using [checkWifiEnabled] after the user returns to the app.
  @override
  Future<void> enableWifiServices() async {
    await methodChannel.invokeMethod('enableWifiServices');
  }

  /// Checks if Bluetooth is enabled on the device.
  ///
  /// Returns a [Future] completing with `true` if enabled, `false` otherwise.
  @override
  Future<bool> checkBluetoothEnabled() async {
    final bool? enabled =
        await methodChannel.invokeMethod('checkBluetoothEnabled');
    return enabled ?? false;
  }

  /// Attempts to open the device's Bluetooth settings screen for the user to enable Bluetooth.
  ///
  /// Returns a [Future] that completes when the settings screen is opened.
  /// Check the result using [checkBluetoothEnabled] after the user returns to the app.
  @override
  Future<void> enableBluetoothServices() async {
    await methodChannel.invokeMethod('enableBluetoothServices');
  }

  /// Provides a broadcast stream of [HotspotHostState] updates.
  ///
  /// This stream emits events whenever the host's Wi-Fi Direct group status changes
  /// (e.g., created, failed, IP address assigned).
  /// Being a broadcast stream, it supports multiple listeners simultaneously.
  /// Each listener will receive events emitted after it subscribes.
  ///
  /// Returns a [Stream] of [HotspotHostState].
  @override
  Stream<HotspotHostState> streamHotspotInfo() {
    _hotspotInfoStream ??= hotspotStateEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
      // Ensure the event is a Map before attempting to parse
      if (event is Map) {
        try {
          return HotspotHostState.fromMap(Map.from(event));
        } catch (e) {
          debugPrint(
              "[MethodChannelFlutterP2pConnection] Error parsing HotspotHostState: $e, Event: $event");
          // Depending on requirements, you might want to return a default error state
          // or filter out invalid events. Here, we rethrow to signal a parsing issue.
          rethrow;
        }
      } else {
        debugPrint(
            "[MethodChannelFlutterP2pConnection] Received non-map event on hotspotStateEventChannel: $event");
        // Filter out unexpected event types by returning null or throwing
        // For robustness, let's throw an error indicating unexpected data.
        throw FormatException(
            "Received unexpected data type on hotspotStateEventChannel: ${event.runtimeType}");
      }
    })
        // Ensure the resulting stream is broadcast (map usually preserves it, but this is explicit)
        .asBroadcastStream();
    return _hotspotInfoStream!;
  }

  /// Provides a broadcast stream of [HotspotClientState] updates.
  ///
  /// This stream emits events whenever the client's connection status to a
  /// Wi-Fi Direct hotspot changes (e.g., connected, disconnected, IP info updated).
  /// Being a broadcast stream, it supports multiple listeners simultaneously.
  /// Each listener will receive events emitted after it subscribes.
  ///
  /// Returns a [Stream] of [HotspotClientState].
  @override
  Stream<HotspotClientState> streamHotspotClientState() {
    _clientStateStream ??=
        clientStateEventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event is Map) {
        try {
          return HotspotClientState.fromMap(Map.from(event));
        } catch (e) {
          debugPrint(
              "[MethodChannelFlutterP2pConnection] Error parsing HotspotClientState: $e, Event: $event");
          rethrow;
        }
      } else {
        debugPrint(
            "[MethodChannelFlutterP2pConnection] Received non-map event on clientStateEventChannel: $event");
        throw FormatException(
            "Received unexpected data type on clientStateEventChannel: ${event.runtimeType}");
      }
    }).asBroadcastStream();
    return _clientStateStream!;
  }

  /// Provides a broadcast stream of [BleConnectionState] updates.
  ///
  /// This stream emits events when the connection status to a specific BLE device changes.
  /// Being a broadcast stream, it supports multiple listeners simultaneously.
  /// Each listener will receive events emitted after it subscribes.
  ///
  /// Returns a [Stream] of [BleConnectionState].
  @override
  Stream<BleConnectionState> streamBleConnectionState() {
    _bleConnectionStateStream ??= bleConnectionStateEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
      if (event is Map) {
        try {
          return BleConnectionState.fromMap(Map.from(event));
        } catch (e) {
          debugPrint(
              "[MethodChannelFlutterP2pConnection] Error parsing BleConnectionState: $e, Event: $event");
          rethrow;
        }
      } else {
        debugPrint(
            "[MethodChannelFlutterP2pConnection] Received non-map event on bleConnectionStateEventChannel: $event");
        throw FormatException(
            "Received unexpected data type on bleConnectionStateEventChannel: ${event.runtimeType}");
      }
    }).asBroadcastStream();
    return _bleConnectionStateStream!;
  }

  /// Provides a broadcast stream emitting lists of [BleDiscoveredDevice] during a BLE scan.
  ///
  /// Each event is a list of devices found or updated in the latest scan interval.
  /// Being a broadcast stream, it supports multiple listeners simultaneously.
  /// Each listener will receive events emitted after it subscribes.
  ///
  /// Returns a [Stream] of `List<BleDiscoveredDevice>`.
  @override
  Stream<List<BleDiscoveredDevice>> streamBleScanResult() {
    _bleScanResultStream ??=
        bleScanResultEventChannel.receiveBroadcastStream().map((dynamic event) {
      // Expecting a List from the platform channel
      if (event is List) {
        try {
          return event
              .whereType<Map>() // Filter out any non-map elements defensively
              .map((deviceMap) =>
                  BleDiscoveredDevice.fromMap(Map.from(deviceMap)))
              .toList();
        } catch (e) {
          debugPrint(
              "[MethodChannelFlutterP2pConnection] Error parsing BleDiscoveredDevice list: $e, Event: $event");
          rethrow;
        }
      } else {
        debugPrint(
            "[MethodChannelFlutterP2pConnection] Received non-list event on bleScanResultEventChannel: $event");
        throw FormatException(
            "Received unexpected data type on bleScanResultEventChannel: ${event.runtimeType}");
      }
    }).asBroadcastStream();
    return _bleScanResultStream!;
  }

  /// Provides a broadcast stream of [BleReceivedData] from connected BLE devices.
  ///
  /// This stream emits data received via BLE characteristics (e.g., notifications or reads
  /// triggered by the native side).
  /// Being a broadcast stream, it supports multiple listeners simultaneously.
  /// Each listener will receive events emitted after it subscribes.
  ///
  /// Returns a [Stream] of [BleReceivedData].
  @override
  Stream<BleReceivedData> streamBleReceivedData() {
    _bleReceivedDataStream ??= bleReceivedDataEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
      if (event is Map) {
        try {
          return BleReceivedData.fromMap(Map.from(event));
        } catch (e) {
          debugPrint(
              "[MethodChannelFlutterP2pConnection] Error parsing BleReceivedData: $e, Event: $event");
          rethrow;
        }
      } else {
        debugPrint(
            "[MethodChannelFlutterP2pConnection] Received non-map event on bleReceivedDataEventChannel: $event");
        throw FormatException(
            "Received unexpected data type on bleReceivedDataEventChannel: ${event.runtimeType}");
      }
    }).asBroadcastStream();
    return _bleReceivedDataStream!;
  }
}
