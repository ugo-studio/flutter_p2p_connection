import 'package:flutter/foundation.dart';

/// Represents the state of the Wi-Fi Direct group (hotspot) created by the host.
@immutable
class HotspotHostState {
  /// `true` if the hotspot is currently active and ready for connections.
  final bool isActive;

  /// The Service Set Identifier (network name) of the hotspot. Null if inactive or not yet determined.
  final String? ssid;

  /// The Pre-Shared Key (password) of the hotspot. Null if inactive or not yet determined.
  final String? preSharedKey;

  /// The IP address of the host device within the created group. Null if inactive or not yet assigned.
  final String? hostIpAddress;

  /// A platform-specific code indicating the reason for failure, if [isActive] is `false`.
  final int? failureReason;

  /// Creates a representation of the host's hotspot state.
  const HotspotHostState({
    required this.isActive,
    this.ssid,
    this.preSharedKey,
    this.hostIpAddress,
    this.failureReason,
  });

  /// Creates a [HotspotHostState] instance from a map (typically from platform channel).
  factory HotspotHostState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotHostState(
      isActive: map['isActive'] as bool? ?? false,
      ssid: map['ssid'] as String?,
      preSharedKey: map['preSharedKey'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
      failureReason: map['failureReason'] as int?,
    );
  }

  /// Converts the [HotspotHostState] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'ssid': ssid,
      'preSharedKey': preSharedKey,
      'hostIpAddress': hostIpAddress,
      'failureReason': failureReason,
    };
  }

  @override
  String toString() {
    return 'HotspotHostState(isActive: $isActive, ssid: $ssid, preSharedKey: ${preSharedKey != null ? "[set]" : "null"}, hostIpAddress: $hostIpAddress, failureReason: $failureReason)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HotspotHostState &&
        other.isActive == isActive &&
        other.ssid == ssid &&
        other.preSharedKey == preSharedKey &&
        other.hostIpAddress == hostIpAddress &&
        other.failureReason == failureReason;
  }

  @override
  int get hashCode =>
      Object.hash(isActive, ssid, preSharedKey, hostIpAddress, failureReason);
}

/// Represents the state of the client's connection to a Wi-Fi Direct group (hotspot).
@immutable
class HotspotClientState {
  /// `true` if the client is currently connected to a hotspot.
  final bool isActive;

  /// The SSID (network name) of the hotspot the client is connected to. Null if inactive.
  final String? hostSsid;

  /// The IP address of the gateway (usually the host device) in the hotspot network.
  final String?
      hostGatewayIpAddress; // Host's Gateway IP (for WebSocket connection)
  /// The IP address assigned to the client device within the hotspot network.
  final String?
      hostIpAddress; // Client's own IP in the P2P group (for its file server)

  /// Creates a representation of the client's connection state.
  const HotspotClientState({
    required this.isActive,
    this.hostSsid,
    this.hostGatewayIpAddress,
    this.hostIpAddress,
  });

  /// Creates a [HotspotClientState] instance from a map (typically from platform channel).
  factory HotspotClientState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotClientState(
      isActive: map['isActive'] as bool? ?? false,
      hostSsid: map['hostSsid'] as String?,
      hostGatewayIpAddress: map['hostGatewayIpAddress'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
    );
  }

  /// Converts the [HotspotClientState] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'hostSsid': hostSsid,
      'hostGatewayIpAddress': hostGatewayIpAddress,
      'hostIpAddress': hostIpAddress,
    };
  }

  @override
  String toString() {
    return 'HotspotClientState(isActive: $isActive, hostSsid: $hostSsid, hostGatewayIpAddress: $hostGatewayIpAddress, clientIpAddressInGroup: $hostIpAddress)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HotspotClientState &&
        other.isActive == isActive &&
        other.hostSsid == hostSsid &&
        other.hostGatewayIpAddress == hostGatewayIpAddress &&
        other.hostIpAddress == hostIpAddress;
  }

  @override
  int get hashCode =>
      Object.hash(isActive, hostSsid, hostGatewayIpAddress, hostIpAddress);
}

/// Represents the connection state of a specific BLE device.
@immutable
class BleConnectionState {
  /// The MAC address of the BLE device.
  final String deviceAddress;

  /// The name of the BLE device.
  final String deviceName;

  /// `true` if the client is currently connected to this BLE device.
  final bool isConnected;

  /// Creates a representation of a BLE device's connection state.
  const BleConnectionState({
    required this.deviceAddress,
    required this.deviceName,
    required this.isConnected,
  });

  /// Creates a [BleConnectionState] instance from a map (typically from platform channel).
  factory BleConnectionState.fromMap(Map<dynamic, dynamic> map) {
    return BleConnectionState(
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      deviceName: map['deviceName'] as String? ?? 'Unknown Name',
      isConnected: map['isConnected'] as bool? ?? false,
    );
  }

  /// Converts the [BleConnectionState] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'deviceName': deviceName,
      'isConnected': isConnected,
    };
  }

  @override
  String toString() {
    return 'BleConnectionState(deviceAddress: $deviceAddress, deviceName: $deviceName, isConnected: $isConnected)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BleConnectionState &&
        other.deviceAddress == deviceAddress &&
        other.deviceName == deviceName &&
        other.isConnected == isConnected;
  }

  @override
  int get hashCode => Object.hash(deviceAddress, deviceName, isConnected);
}

/// Represents a BLE device found during a scan.
@immutable
class BleDiscoveredDevice {
  /// The MAC address of the discovered BLE device.
  final String deviceAddress;

  /// The advertised name of the BLE device.
  final String deviceName;

  /// Creates a representation of a discovered BLE device.
  const BleDiscoveredDevice({
    required this.deviceAddress,
    required this.deviceName,
  });

  /// Creates a [BleDiscoveredDevice] instance from a map (typically from platform channel).
  factory BleDiscoveredDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleDiscoveredDevice(
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      deviceName: (map['deviceName'] as String?)?.isNotEmpty ?? false
          ? map['deviceName'] as String
          : 'Unknown Device',
    );
  }

  /// Converts the [BleDiscoveredDevice] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'deviceName': deviceName,
    };
  }

  @override
  String toString() {
    return 'BleDiscoveredDevice(deviceAddress: $deviceAddress, deviceName: $deviceName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BleDiscoveredDevice &&
        other.deviceAddress == deviceAddress &&
        other.deviceName == deviceName;
  }

  @override
  int get hashCode => Object.hash(deviceAddress, deviceName);
}

/// Represents data received from a connected BLE device via a characteristic.
@immutable
class BleReceivedData {
  /// The MAC address of the BLE device from which data was received.
  final String deviceAddress;

  /// The UUID of the GATT characteristic that sent the data.
  final String characteristicUuid;

  /// The raw byte data received from the characteristic.
  final Uint8List data;

  /// Creates a representation of received BLE data.
  const BleReceivedData({
    required this.deviceAddress,
    required this.characteristicUuid,
    required this.data,
  });

  /// Creates a [BleReceivedData] instance from a map (typically from platform channel).
  factory BleReceivedData.fromMap(Map<dynamic, dynamic> map) {
    return BleReceivedData(
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      characteristicUuid:
          map['characteristicUuid'] as String? ?? 'Unknown UUID',
      data: map['data'] as Uint8List? ?? Uint8List(0),
    );
  }

  /// Converts the [BleReceivedData] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'characteristicUuid': characteristicUuid,
      'data': data,
    };
  }

  @override
  String toString() {
    final dataSummary = data.length > 16
        ? '${data.sublist(0, 8)}... (${data.length} bytes)'
        : data.toString();
    return 'BleReceivedData(deviceAddress: $deviceAddress, characteristicUuid: $characteristicUuid, data: $dataSummary)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BleReceivedData &&
        other.deviceAddress == deviceAddress &&
        other.characteristicUuid == characteristicUuid &&
        listEquals(other.data, data);
  }

  @override
  int get hashCode =>
      Object.hash(deviceAddress, characteristicUuid, Object.hashAll(data));
}
