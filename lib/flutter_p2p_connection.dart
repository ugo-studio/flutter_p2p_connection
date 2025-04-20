import 'dart:async';
import 'package:flutter/foundation.dart';
// TODO: Re-evaluate if P2pTransport is needed or remove if unused.
// import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';

/// The [FlutterP2pConnectionHost] class facilitates creating and managing a
/// Wi-Fi Direct group (acting as a hotspot host) for P2P connections.
///
/// It allows initializing the host, creating a group (optionally advertising
/// credentials via BLE), removing the group, and listening for state changes.
class FlutterP2pConnectionHost {
  // Internal state flags
  bool _isGroupCreated = false;
  bool _isBleAdvertising = false;
  // TODO: Re-evaluate if P2pTransportHost is needed or remove if unused.
  // P2pTransportHost? _p2pTransport;

  /// Returns `true` if a Wi-Fi Direct group has been successfully created.
  bool get isGroupCreated => _isGroupCreated;

  /// Returns `true` if the host is currently advertising hotspot credentials via BLE.
  bool get isAdvertising => _isBleAdvertising;

  /// Initializes the P2P connection host resources on the native platform.
  ///
  /// This method must be called before any other host operations.
  /// It prepares the underlying platform-specific components.
  Future<void> initialize() async {
    // _p2pTransport = null; // Reset transport if used
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes of the P2P connection host resources and cleans up connections.
  ///
  /// This method should be called when the host functionality is no longer needed
  /// to release system resources. It attempts to remove any active group first.
  Future<void> dispose() async {
    // Ensure the group is removed before disposing platform resources.
    // Ignore errors during removal as we are disposing anyway.
    await removeGroup().catchError((_) => null);
    await FlutterP2pConnectionPlatform.instance.dispose();
  }

  /// Creates a Wi-Fi Direct group (hotspot) for P2P connections.
  ///
  /// After successful creation, it retrieves the hotspot's [HotspotHostState]
  /// containing the SSID and Pre-Shared Key (PSK).
  ///
  /// By default (`advertise = true`), it also starts advertising these credentials
  /// via Bluetooth Low Energy (BLE) to allow clients to discover and connect.
  ///
  /// Throws an [Exception] if the hotspot credentials (SSID/PSK) cannot be
  /// obtained within the timeout period (5 seconds).
  ///
  /// - [advertise]: If `true`, starts BLE advertising with the hotspot credentials.
  ///                Defaults to `true`.
  ///
  /// Returns a [Future] completing with the [HotspotHostState] containing
  /// connection details (SSID, PSK, IP address).
  Future<HotspotHostState> createGroup({bool advertise = true}) async {
    // Initiate hotspot creation on the native side.
    await FlutterP2pConnectionPlatform.instance.createHotspot();
    _isGroupCreated = true;

    // Wait for the hotspot state update containing valid credentials.
    // Use a timeout to prevent indefinite waiting.
    final HotspotHostState state = await onHotspotStateChanged()
        .timeout(
          const Duration(seconds: 5),
          // If timeout occurs, close the stream
          onTimeout: (evt) => evt.close(),
        )
        .firstWhere(
          (state) => state.ssid != null && state.preSharedKey != null,
          // If the stream completes without valid state (e.g., error), return inactive.
          orElse: () => const HotspotHostState(isActive: false),
        );

    // Validate if we received valid hotspot credentials.
    if (state.ssid == null || state.preSharedKey == null) {
      // If credentials are missing, attempt to clean up the created group.
      await removeGroup().catchError((_) => null); // Ignore cleanup errors
      throw Exception(
          'Failed to get valid hotspot SSID and PSK after creation.');
    }

    // Start BLE advertising if requested and credentials are valid.
    if (advertise) {
      try {
        await FlutterP2pConnectionPlatform.instance.startBleAdvertising(
          state.ssid!,
          state.preSharedKey!,
        );
        _isBleAdvertising = true;
      } catch (e) {
        // If advertising fails, log it but don't necessarily fail the group creation.
        // The group itself might still be usable via other discovery methods (e.g., QR code).
        debugPrint('Failed to start BLE advertising: $e');
        _isBleAdvertising = false;
        // Optionally rethrow if advertising is critical: throw Exception('Failed to start BLE advertising: $e');
      }
    } else {
      _isBleAdvertising = false;
    }

    return state; // Return the obtained hotspot state.
  }

  /// Removes the currently active Wi-Fi Direct group (hotspot).
  ///
  /// This stops BLE advertising (if active), stops any associated transport layer
  /// (if implemented and running), and tears down the native hotspot.
  Future<void> removeGroup() async {
    // Stop BLE advertising if it was active.
    if (_isBleAdvertising) {
      await FlutterP2pConnectionPlatform.instance
          .stopBleAdvertising()
          .catchError((e) {
        // Log error but continue cleanup
        debugPrint('Error stopping BLE advertising: $e');
      });
      _isBleAdvertising = false;
    }

    // Stop the transport layer if it exists and is running.
    // TODO: Uncomment and implement if P2pTransportHost is used.
    // await _p2pTransport?.stop().catchError((e) {
    //   debugPrint('Error stopping P2P transport: $e');
    // });
    // _p2pTransport = null;

    // Remove the hotspot on the native side if a group was created.
    if (_isGroupCreated) {
      await FlutterP2pConnectionPlatform.instance
          .removeHotspot()
          .catchError((e) {
        // Log error but update state anyway
        debugPrint('Error removing hotspot group: $e');
      });
      _isGroupCreated = false;
    }
  }

  /// Provides a stream of [HotspotHostState] updates.
  ///
  /// Listen to this stream to receive real-time information about the host's
  /// hotspot status, including whether it's active, its SSID, PSK, IP address,
  /// and any failure reasons.
  ///
  /// Returns a [Stream] of [HotspotHostState].
  Stream<HotspotHostState> onHotspotStateChanged() {
    return FlutterP2pConnectionPlatform.instance.streamHotspotInfo();
  }
}

/// The [FlutterP2pConnectionClient] class facilitates discovering and connecting
/// to a P2P host (Wi-Fi Direct group).
///
/// It allows initializing the client, scanning for hosts via BLE, connecting
/// to a discovered host (either via BLE data exchange or directly with credentials),
/// disconnecting, and listening for connection state changes.
class FlutterP2pConnectionClient {
  // Internal state flag
  bool _isScanning = false;
  // TODO: Re-evaluate if P2pTransportClient is needed or remove if unused.
  // P2pTransportClient? _p2pTransport;

  /// Returns `true` if the client is currently scanning for BLE devices.
  bool get isScanning => _isScanning;

  /// Initializes the P2P connection client resources on the native platform.
  ///
  /// This method must be called before any other client operations.
  /// It prepares the underlying platform-specific components.
  Future<void> initialize() async {
    // _p2pTransport = null; // Reset transport if used
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes of the P2P connection client resources and cleans up connections.
  ///
  /// This method should be called when the client functionality is no longer needed
  /// to release system resources. It attempts to stop any active BLE scan and
  /// disconnect from any active hotspot first.
  Future<void> dispose() async {
    // Ensure scanning is stopped before disposing.
    await stopScan().catchError((_) => null);
    // Ensure disconnection from hotspot before disposing.
    await disconnectFromHotspot().catchError((_) => null);
    await FlutterP2pConnectionPlatform.instance.dispose();
  }

  /// Starts scanning for nearby BLE devices advertising P2P host credentials.
  ///
  /// Listens to the BLE scan results stream and calls the [onData] callback
  /// whenever new devices are found. The scan automatically stops after the
  /// specified [timeout] duration (default 15 seconds).
  ///
  /// - [onData]: Callback function invoked with a list of [BleFoundDevice] found
  ///             during the scan. Can be null if only interested in completion/error.
  /// - [onError]: Optional callback for handling errors during the scan stream.
  /// - [onDone]: Optional callback invoked when the scan stream is closed (e.g., timeout).
  /// - [cancelOnError]: If `true`, the stream subscription cancels on the first error.
  /// - [timeout]: Duration after which the scan will automatically stop. Defaults to 15 seconds.
  ///
  /// Returns a [Future] completing with the [StreamSubscription] for the scan results.
  /// This subscription can be used to manually cancel the scan before the timeout.
  ///
  /// Throws an exception if starting the native BLE scan fails.
  Future<StreamSubscription<List<BleFoundDevice>>> startScan(
    void Function(List<BleFoundDevice>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_isScanning) {
      // Avoid starting multiple scans concurrently.
      // Consider throwing an error or returning the existing subscription.
      // For now, just stop the previous scan.
      await stopScan();
    }

    // Set up the stream listener first.
    final streamSub =
        FlutterP2pConnectionPlatform.instance.streamBleScanResult().listen(
              onData,
              onError: onError,
              onDone: onDone,
              cancelOnError: cancelOnError,
            );

    // Schedule automatic stop after timeout.
    final timer = Timer(timeout, () async {
      // Check if the subscription is still active before cancelling/stopping
      if (!streamSub.isPaused) {
        // A simple check, might need more robust state management
        await streamSub.cancel();
        // Only stop native scan if we initiated it and it's still considered active.
        if (_isScanning) {
          await stopScan().catchError(
              (e) => debugPrint("Error stopping scan on timeout: $e"));
        }
      }
    });

    // Add cleanup for the timer when the stream is manually cancelled or finishes.
    streamSub.onDone(() {
      timer.cancel();
      // Ensure scan state is updated if stream finishes before timeout stopScan call
      if (_isScanning) {
        stopScan().catchError(
            (e) => debugPrint("Error stopping scan on stream done: $e"));
      }
    });
    streamSub.onError((error) {
      timer.cancel();
      if (_isScanning) {
        stopScan().catchError(
            (e) => debugPrint("Error stopping scan on stream error: $e"));
      }
    });

    // Start the native BLE scan.
    try {
      await FlutterP2pConnectionPlatform.instance.startBleScan();
      _isScanning = true;
      return streamSub;
    } catch (e) {
      // If starting the scan fails, clean up the stream subscription and timer.
      await streamSub.cancel();
      timer.cancel();
      _isScanning = false; // Ensure state is reset
      debugPrint('Failed to start BLE scan: $e');
      rethrow; // Propagate the error
    }
  }

  /// Stops the ongoing BLE scan if one is active.
  Future<void> stopScan() async {
    if (_isScanning) {
      await FlutterP2pConnectionPlatform.instance.stopBleScan().catchError((e) {
        debugPrint('Error stopping BLE scan natively: $e');
        // Still update the state even if native call fails
      });
      _isScanning = false;
    }
  }

  /// Connects to a BLE device discovered during a scan, retrieves hotspot
  /// credentials (SSID and PSK) exchanged over BLE characteristics, and then
  /// connects to the Wi-Fi Direct hotspot using those credentials.
  ///
  /// This method assumes the target BLE device is a P2P host advertising its
  /// credentials according to a specific protocol (e.g., writing SSID then PSK
  /// to a characteristic).
  ///
  /// - [deviceAddress]: The MAC address of the BLE device to connect to.
  ///
  /// Throws an [Exception] if connecting to the BLE device fails, if credentials
  /// are not received within the timeout (10 seconds), or if connecting to the
  /// Wi-Fi hotspot fails.
  Future<void> connectToFoundDevice(String deviceAddress) async {
    // Connect to the BLE device first.
    await FlutterP2pConnectionPlatform.instance.connectBleDevice(deviceAddress);

    String? ssid;
    String? psk;

    try {
      // Listen for data received from the BLE device (expecting SSID and PSK).
      // Use a timeout to avoid waiting indefinitely for credentials.
      await FlutterP2pConnectionPlatform.instance
          .streamBleReceivedData()
          .timeout(
        const Duration(seconds: 10),
        onTimeout: (evt) {
          // close stream
          evt.close();
          // Throw a specific error on timeout
          throw TimeoutException(
              'Timed out waiting for hotspot credentials via BLE.');
        },
      ).firstWhere(
        (evt) {
          // Basic protocol: expect SSID first, then PSK.
          // Assumes credentials are sent as separate string messages.
          // This might need adjustment based on the actual BLE protocol.
          if (evt.deviceAddress == deviceAddress) {
            String value = String.fromCharCodes(evt.data);
            if (ssid == null) {
              ssid = value;
              debugPrint("Received SSID via BLE: $ssid");
              return false; // Wait for PSK
            } else {
              psk = value;
              debugPrint("Received PSK via BLE: $psk");
              return true; // Got both, stop listening
            }
          }
          return false; // Ignore data from other devices if any
        },
        // If stream completes without finding both, throw error.
        orElse: () => throw Exception(
            'BLE data stream ended before receiving both SSID and PSK.'),
      );

      // Validate received credentials.
      if (ssid == null || psk == null) {
        throw Exception(
            'Failed to receive valid hotspot SSID and PSK via BLE.');
      }

      // Credentials received, now connect to the Wi-Fi hotspot.
      debugPrint("Attempting to connect to hotspot: $ssid");
      await connectToHotspot(ssid!, psk!);
      debugPrint("Successfully connected to hotspot: $ssid");
    } finally {
      // Always disconnect from the BLE device after attempting connection
      // or if an error occurred during credential exchange/hotspot connection.
      await FlutterP2pConnectionPlatform.instance
          .disconnectBleDevice(deviceAddress)
          .catchError((e) {
        debugPrint('Error disconnecting from BLE device $deviceAddress: $e');
      });
    }
  }

  /// Connects directly to a Wi-Fi Direct hotspot using the provided SSID and password (PSK).
  ///
  /// This is used either after obtaining credentials (e.g., via BLE or QR code)
  /// or if the credentials are known beforehand.
  ///
  /// - [ssid]: The Service Set Identifier (network name) of the hotspot.
  /// - [psk]: The Pre-Shared Key (password) for the hotspot.
  Future<void> connectToHotspot(String ssid, String psk) async {
    await FlutterP2pConnectionPlatform.instance.connectToHotspot(ssid, psk);
    // TODO: Initialize P2pTransportClient if needed after successful connection.
    // Example: _p2pTransport = P2pTransportClient(...); await _p2pTransport.connect();
  }

  /// Disconnects from the currently connected Wi-Fi Direct hotspot.
  ///
  /// Also stops any associated transport layer (if implemented and running).
  Future<void> disconnectFromHotspot() async {
    // Disconnect the transport layer first if it exists.
    // TODO: Uncomment and implement if P2pTransportClient is used.
    // await _p2pTransport?.disconnect().catchError((e) {
    //   debugPrint('Error disconnecting P2P transport: $e');
    // });
    // _p2pTransport = null;

    // Disconnect from the hotspot on the native side.
    await FlutterP2pConnectionPlatform.instance
        .disconnectFromHotspot()
        .catchError((e) {
      debugPrint('Error disconnecting from hotspot: $e');
      // Consider if state needs update even on error
    });
  }

  /// Provides a stream of [HotspotClientState] updates.
  ///
  /// Listen to this stream to receive real-time information about the client's
  /// connection status to a hotspot, including whether it's connected, the
  /// host's SSID, and IP address details.
  ///
  /// Returns a [Stream] of [HotspotClientState].
  Stream<HotspotClientState> onHotspotStateChanged() {
    return FlutterP2pConnectionPlatform.instance.streamHotspotClientState();
  }
}

/// The main entry point for the Flutter P2P Connection plugin.
///
/// This class provides access to:
/// - Host functionality via the [host] property ([FlutterP2pConnectionHost]).
/// - Client functionality via the [client] property ([FlutterP2pConnectionClient]).
/// - Utility methods for checking and requesting permissions and enabling services
///   (Location, Wi-Fi, Bluetooth) required for P2P operations.
/// - Device information like the model.
class FlutterP2pConnection {
  /// Provides access to host-specific P2P operations.
  final FlutterP2pConnectionHost host = FlutterP2pConnectionHost();

  /// Provides access to client-specific P2P operations.
  final FlutterP2pConnectionClient client = FlutterP2pConnectionClient();

  /// Retrieves the model identifier of the current device.
  ///
  /// Useful for debugging or tailoring behavior based on the device.
  ///
  /// Returns a [Future] completing with the device model string.
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  /// Checks if location services are currently enabled on the device.
  ///
  /// Location is often required for Wi-Fi and BLE scanning on Android.
  ///
  /// Returns a [Future] completing with `true` if location is enabled, `false` otherwise.
  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();

  /// Attempts to guide the user to system settings to enable location services.
  ///
  /// This typically opens the device's location settings screen.
  /// After the user potentially enables the service, it re-checks the status.
  ///
  /// Returns a [Future] completing with `true` if location is enabled after the
  /// attempt, `false` otherwise. Note that the user can choose not to enable it.
  Future<bool> enableLocationServices() async {
    await FlutterP2pConnectionPlatform.instance.enableLocationServices();
    // Re-check status after returning from settings.
    return await checkLocationEnabled();
  }

  /// Checks if Wi-Fi is currently enabled on the device.
  ///
  /// Wi-Fi is essential for Wi-Fi Direct P2P connections.
  ///
  /// Returns a [Future] completing with `true` if Wi-Fi is enabled, `false` otherwise.
  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();

  /// Attempts to guide the user to system settings to enable Wi-Fi.
  ///
  /// This typically opens the device's Wi-Fi settings screen.
  /// After the user potentially enables Wi-Fi, it re-checks the status.
  ///
  /// Returns a [Future] completing with `true` if Wi-Fi is enabled after the
  /// attempt, `false` otherwise.
  Future<bool> enableWifiServices() async {
    await FlutterP2pConnectionPlatform.instance.enableWifiServices();
    // Re-check status after returning from settings.
    return await checkWifiEnabled();
  }

  /// Checks if Bluetooth is currently enabled on the device.
  ///
  /// Bluetooth is required for BLE discovery (scanning and advertising).
  ///
  /// Returns a [Future] completing with `true` if Bluetooth is enabled, `false` otherwise.
  Future<bool> checkBluetoothEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkBluetoothEnabled();

  /// Attempts to guide the user to system settings to enable Bluetooth.
  ///
  /// This typically opens the device's Bluetooth settings screen.
  /// After the user potentially enables Bluetooth, it re-checks the status.
  ///
  /// Returns a [Future] completing with `true` if Bluetooth is enabled after the
  /// attempt, `false` otherwise.
  Future<bool> enableBluetoothServices() async {
    await FlutterP2pConnectionPlatform.instance.enableBluetoothServices();
    // Re-check status after returning from settings.
    return await checkBluetoothEnabled();
  }

  /// Checks if all necessary Bluetooth permissions are granted.
  ///
  /// This includes permissions for connecting, scanning, and advertising,
  /// which vary depending on the Android version. Uses the `permission_handler` package.
  ///
  /// Returns a [Future] completing with `true` if all required Bluetooth
  /// permissions are granted, `false` otherwise.
  Future<bool> checkBluetoothPermissions() async {
    // Permissions required might vary slightly based on Android SDK level.
    // These cover common BLE operations.
    final List<Permission> permissions = [
      Permission.bluetoothScan, // Needed for discovering devices (Android 12+)
      Permission
          .bluetoothConnect, // Needed for connecting to devices (Android 12+)
      Permission.bluetoothAdvertise, // Needed for advertising (Android 12+)
      // Consider adding Location permissions here too, as they are often
      // required for BLE scanning on older Android versions.
      // Permission.locationWhenInUse,
    ];

    for (final perm in permissions) {
      if (!(await perm.status.isGranted)) {
        return false; // If any required permission is not granted, return false.
      }
    }
    // Check location permission separately if needed for older Android versions
    // or if fine location is strictly required by the app's logic.
    // if (!(await Permission.locationWhenInUse.status.isGranted)) {
    //   return false;
    // }

    return true; // All checked permissions are granted.
  }

  /// Requests necessary Bluetooth permissions from the user.
  ///
  /// Uses the `permission_handler` package to request permissions for scanning,
  /// connecting, and advertising. Also includes the base `bluetooth` permission
  /// for broader compatibility.
  ///
  /// Returns a [Future] completing with `true` if all requested permissions
  /// are granted by the user, `false` otherwise.
  Future<bool> askBluetoothPermissions() async {
    // Request all potentially needed permissions at once.
    await [
      Permission.bluetooth, // General Bluetooth permission
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      // Request location as well, as it's often needed for BLE scans.
      // Use fine location if precise location is needed, otherwise 'when in use'.
      Permission.locationWhenInUse,
      // Permission.location, // Or Permission.location for background access if required
    ].request();

    // After requesting, check if they were actually granted.
    return await checkBluetoothPermissions();
  }

  /// Checks if all necessary P2P (Wi-Fi Direct) permissions are granted.
  ///
  /// This typically includes permissions like `NEARBY_WIFI_DEVICES` (Android 13+),
  /// `ACCESS_FINE_LOCATION` (required for Wi-Fi scanning/discovery), and potentially
  /// `CHANGE_WIFI_STATE`. The exact check is handled by the platform implementation.
  ///
  /// Returns a [Future] completing with `true` if all required P2P permissions
  /// are granted, `false` otherwise.
  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();

  /// Requests necessary P2P (Wi-Fi Direct) permissions from the user.
  ///
  /// This triggers the platform-specific permission request dialogs for permissions
  /// like `NEARBY_WIFI_DEVICES`, `ACCESS_FINE_LOCATION`, etc.
  ///
  /// Returns a [Future] completing with `true` if the permissions are granted
  /// after the request, `false` otherwise.
  Future<bool> askP2pPermissions() async {
    await FlutterP2pConnectionPlatform.instance.askP2pPermissions();
    // Re-check status after the request dialog.
    return await checkP2pPermissions();
  }

  /// Checks if the storage permission (read/write external storage) is granted.
  ///
  /// This permission might be required if the application intends to transfer files
  /// over the P2P connection. Uses the `permission_handler` package.
  /// Note: Storage permission requirements have changed significantly in recent
  /// Android versions (Scoped Storage). This check might need refinement based
  /// on specific file access needs and target Android SDK.
  ///
  /// Returns a [Future] completing with `true` if storage permission is granted,
  /// `false` otherwise.
  Future<bool> checkStoragePermission() async {
    // On Android 13+, direct external storage access is restricted.
    // Use Manage External Storage or MediaStore APIs instead.
    // For simplicity, checking basic 'storage' permission here.
    // Consider using Permission.manageExternalStorage or specific media permissions
    // (photos, videos, audio) based on actual needs.
    if (await Permission.storage.isGranted) {
      return true;
    }
    // On Android 13+, check media permissions if applicable
    // if (await Permission.photos.isGranted && await Permission.videos.isGranted) {
    //   return true;
    // }
    return false;
  }

  /// Requests storage permission from the user.
  ///
  /// Uses the `permission_handler` package. See notes in [checkStoragePermission]
  /// regarding changes in Android storage permissions.
  ///
  /// Returns a [Future] completing with `true` if the permission is granted,
  /// `false` otherwise.
  Future<bool> askStoragePermission() async {
    // Request basic storage permission. Adapt as needed for Scoped Storage.
    // Consider requesting Permission.manageExternalStorage or media permissions.
    final status = await Permission.storage.request();
    return status.isGranted;
    // Example for media permissions on Android 13+:
    // Map<Permission, PermissionStatus> statuses = await [
    //   Permission.photos,
    //   Permission.videos,
    // ].request();
    // return statuses[Permission.photos] == PermissionStatus.granted &&
    //        statuses[Permission.videos] == PermissionStatus.granted;
  }

  // TODO: Expose BLE connection state stream if needed for UI updates.
  // /// Provides a stream of [BleConnectionState] updates for connected BLE devices.
  // ///
  // /// Listen to this stream to monitor the connection status (connected/disconnected)
  // /// of individual BLE devices managed by the plugin.
  // ///
  // /// Returns a [Stream] of [BleConnectionState].
  // Stream<BleConnectionState> streamBleConnectionState() {
  //   return FlutterP2pConnectionPlatform.instance.streamBleConnectionState();
  // }
}

/// Represents the state of the Wi-Fi Direct group (hotspot) created by the host.
///
/// Contains information about the hotspot's status and connection details.
@immutable
class HotspotHostState {
  /// `true` if the hotspot is currently active and ready for connections.
  final bool isActive;

  /// The Service Set Identifier (network name) of the hotspot. Null if inactive.
  final String? ssid;

  /// The Pre-Shared Key (password) of the hotspot. Null if inactive.
  final String? preSharedKey;

  /// The IP address of the host device within the created group. Null if inactive.
  final String? hostIpAddress;

  /// A platform-specific code indicating the reason for failure, if [isActive] is `false`.
  /// Interpretation depends on the underlying native implementation (e.g., Android WifiP2pManager failure codes).
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
      isActive: map['isActive'] as bool? ?? false, // Provide default
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
    return 'HotspotHostState(isActive: $isActive, ssid: $ssid, preSharedKey: $preSharedKey, hostIpAddress: $hostIpAddress, failureReason: $failureReason)';
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
  int get hashCode {
    return isActive.hashCode ^
        ssid.hashCode ^
        preSharedKey.hashCode ^
        hostIpAddress.hashCode ^
        failureReason.hashCode;
  }
}

/// Represents the state of the client's connection to a Wi-Fi Direct group (hotspot).
///
/// Contains information about the connection status and network details obtained from the host.
@immutable
class HotspotClientState {
  /// `true` if the client is currently connected to a hotspot.
  final bool isActive;

  /// The SSID (network name) of the hotspot the client is connected to. Null if inactive.
  final String? hostSsid;

  /// The IP address of the gateway (usually the host device) in the hotspot network. Null if inactive.
  final String? hostGatewayIpAddress;

  /// The IP address assigned to the client device within the hotspot network. Null if inactive.
  /// Note: This field name might be slightly misleading; it often represents the *client's* IP, not the host's.
  /// Check platform implementation for certainty.
  final String? hostIpAddress; // TODO: Rename to clientIpAddress if confirmed

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
      isActive: map['isActive'] as bool? ?? false, // Provide default
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
    return 'HotspotClientState(isActive: $isActive, hostSsid: $hostSsid, hostGatewayIpAddress: $hostGatewayIpAddress, hostIpAddress: $hostIpAddress)';
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
  int get hashCode {
    return isActive.hashCode ^
        hostSsid.hashCode ^
        hostGatewayIpAddress.hashCode ^
        hostIpAddress.hashCode;
  }
}

/// Represents the connection state of a specific BLE device.
///
/// Used in the [FlutterP2pConnection.streamBleConnectionState] stream (if exposed).
@immutable
class BleConnectionState {
  /// The MAC address of the BLE device.
  final String deviceAddress;

  /// The name of the BLE device (as advertised or retrieved). May be empty.
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
      deviceAddress: map['deviceAddress'] as String? ??
          'Unknown Address', // Provide default
      deviceName:
          map['deviceName'] as String? ?? 'Unknown Name', // Provide default
      isConnected: map['isConnected'] as bool? ?? false, // Provide default
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
  int get hashCode {
    return deviceAddress.hashCode ^ deviceName.hashCode ^ isConnected.hashCode;
  }
}

/// Represents a BLE device found during a scan.
///
/// Contains basic information about the discovered device.
@immutable
class BleFoundDevice {
  /// The MAC address of the discovered BLE device.
  final String deviceAddress;

  /// The advertised name of the BLE device. May be empty or "Unknown".
  final String deviceName;

  /// The Received Signal Strength Indicator (RSSI) in dBm.
  /// Indicates the signal strength at the time of discovery (more negative means weaker).
  final int rssi;

  /// Creates a representation of a discovered BLE device.
  const BleFoundDevice({
    required this.deviceAddress,
    required this.deviceName,
    required this.rssi,
  });

  /// Creates a [BleFoundDevice] instance from a map (typically from platform channel).
  factory BleFoundDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleFoundDevice(
      deviceAddress: map['deviceAddress'] as String? ??
          'Unknown Address', // Provide default
      // Handle potential null or empty names from native side
      deviceName: (map['deviceName'] as String?)?.isNotEmpty ?? false
          ? map['deviceName'] as String
          : 'Unknown Device',
      rssi: map['rssi'] as int? ?? -100, // Provide default
    );
  }

  /// Converts the [BleFoundDevice] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'deviceName': deviceName,
      'rssi': rssi,
    };
  }

  @override
  String toString() {
    return 'BleFoundDevice(deviceAddress: $deviceAddress, deviceName: $deviceName, rssi: $rssi)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BleFoundDevice &&
        other.deviceAddress == deviceAddress &&
        other.deviceName == deviceName &&
        other.rssi == rssi;
  }

  @override
  int get hashCode {
    return deviceAddress.hashCode ^ deviceName.hashCode ^ rssi.hashCode;
  }
}

/// Represents data received from a connected BLE device via a characteristic.
///
/// Used in the [FlutterP2pConnectionClient.connectToFoundDevice] method's internal stream.
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
      deviceAddress: map['deviceAddress'] as String? ??
          'Unknown Address', // Provide default
      characteristicUuid: map['characteristicUuid'] as String? ??
          'Unknown UUID', // Provide default
      // Ensure data is always a Uint8List, even if null/empty from platform
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
    // Avoid printing large byte arrays directly to the console
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
        listEquals(other.data, data); // Use listEquals for byte comparison
  }

  @override
  int get hashCode {
    return deviceAddress.hashCode ^
        characteristicUuid.hashCode ^
        data.hashCode; // Default hashCode for lists might not be ideal, but sufficient here
  }
}
