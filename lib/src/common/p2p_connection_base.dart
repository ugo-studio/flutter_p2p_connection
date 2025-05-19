import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../flutter_p2p_connection_platform_interface.dart';

/// Base class for common P2P connection functionalities.
///
/// This class provides access to:
/// - Utility methods for checking and requesting permissions and enabling services
///   (Location, Wi-Fi, Bluetooth) required for P2P operations.
/// - Device information like the model.
class FlutterP2pConnectionBase {
  /// Optional custom UUID for the BLE service. If null, a default UUID is used.
  final String? serviceUuid;

  /// Optional bonding by BLE service
  final bool? bondingRequired;

  /// Optional encryption by BLE service
  final bool? encryptionRequired;

  /// Constructor for [FlutterP2pConnectionBase].
  const FlutterP2pConnectionBase({
    this.serviceUuid,
    this.bondingRequired,
    this.encryptionRequired,
  });

  /// Retrieves the model identifier of the current device.
  ///
  /// Useful for debugging or tailoring behavior based on the device.
  /// Returns a [Future] completing with the device model string.
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  /// Checks if location services are currently enabled on the device.
  ///
  /// Location is often required for Wi-Fi and BLE scanning on Android.
  /// Returns a [Future] completing with `true` if location is enabled, `false` otherwise.
  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();

  /// Attempts to guide the user to system settings to enable location services.
  ///
  /// This typically opens the device's location settings screen.
  /// After the user potentially enables the service, it re-checks the status.
  /// Returns a [Future] completing with `true` if location is enabled after the
  /// attempt, `false` otherwise. Note that the user can choose not to enable it.
  Future<bool> enableLocationServices() async {
    await FlutterP2pConnectionPlatform.instance.enableLocationServices();
    return await checkLocationEnabled();
  }

  /// Checks if Wi-Fi is currently enabled on the device.
  ///
  /// Wi-Fi is essential for Wi-Fi Direct P2P connections.
  /// Returns a [Future] completing with `true` if Wi-Fi is enabled, `false` otherwise.
  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();

  /// Attempts to guide the user to system settings to enable Wi-Fi.
  ///
  /// This typically opens the device's Wi-Fi settings screen.
  /// After the user potentially enables Wi-Fi, it re-checks the status.
  /// Returns a [Future] completing with `true` if Wi-Fi is enabled after the
  /// attempt, `false` otherwise.
  Future<bool> enableWifiServices() async {
    await FlutterP2pConnectionPlatform.instance.enableWifiServices();
    return await checkWifiEnabled();
  }

  /// Checks if Bluetooth is currently enabled on the device.
  ///
  /// Bluetooth is required for BLE discovery (scanning and advertising).
  /// Returns a [Future] completing with `true` if Bluetooth is enabled, `false` otherwise.
  Future<bool> checkBluetoothEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkBluetoothEnabled();

  /// Attempts to guide the user to system settings to enable Bluetooth.
  ///
  /// This typically opens the device's Bluetooth settings screen.
  /// After the user potentially enables Bluetooth, it re-checks the status.
  /// Returns a [Future] completing with `true` if Bluetooth is enabled after the
  /// attempt, `false` otherwise.
  Future<bool> enableBluetoothServices() async {
    await FlutterP2pConnectionPlatform.instance.enableBluetoothServices();
    return await checkBluetoothEnabled();
  }

  /// Checks if all necessary Bluetooth permissions are granted.
  ///
  /// Returns a [Future] completing with `true` if all required Bluetooth permissions are granted, `false` otherwise.
  Future<bool> checkBluetoothPermissions() async {
    final List<Permission> permissions = [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];
    for (final perm in permissions) {
      final status = await perm.status;
      if (!status.isGranted && !status.isLimited) {
        debugPrint("Permission missing: $perm status: $status");
        return false;
      }
    }
    return true;
  }

  /// Requests necessary Bluetooth and associated Location permissions from the user.
  ///
  /// Uses the `permission_handler` package to request permissions for scanning,
  /// connecting, advertising, and location (often needed for scanning).
  /// Returns a [Future] completing with `true` if all requested permissions are granted, `false` otherwise.
  Future<bool> askBluetoothPermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();
    return await checkBluetoothPermissions();
  }

  /// Checks if all necessary P2P (Wi-Fi Direct) permissions are granted.
  ///
  /// Returns a [Future] completing with `true` if all required P2P permissions are granted, `false` otherwise.
  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();

  /// Requests necessary P2P (Wi-Fi Direct) permissions from the user.
  ///
  /// Returns a [Future] completing with `true` if the permissions are granted after the request, `false` otherwise.
  Future<bool> askP2pPermissions() async {
    await FlutterP2pConnectionPlatform.instance.askP2pPermissions();
    return await checkP2pPermissions();
  }

  /// Checks if the necessary storage permissions are granted for file transfer.
  ///
  /// **Note:** Storage permission requirements have changed significantly in recent Android versions.
  /// Returns a [Future] completing with `true` if `Permission.storage` is granted, `false` otherwise.
  Future<bool> checkStoragePermission() async {
    // Consider Scoped Storage for Android 10+
    return await Permission.storage.isGranted;
  }

  /// Requests storage permission(s) from the user, primarily for file transfer.
  ///
  /// Returns a [Future] completing with `true` if `Permission.storage` is granted after the request, `false` otherwise.
  Future<bool> askStoragePermission() async {
    // Consider Scoped Storage for Android 10+
    final status = await Permission.storage.request();
    return status.isGranted;
  }
}
