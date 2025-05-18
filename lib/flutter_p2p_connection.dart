import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';

/// Default port for the P2P transport layer if not specified otherwise.
const int _defaultP2pTransportPort = 3456;

/// Default port for the client's file server in the P2P transport layer.
const int _defaultP2pTransportClientFileServerPort = 4567;

/// Base class for common P2P connection functionalities.
///
/// This class provides access to:
/// - Utility methods for checking and requesting permissions and enabling services
///   (Location, Wi-Fi, Bluetooth) required for P2P operations.
/// - Device information like the model.
class _FlutterP2pConnection {
  /// Optional custom UUID for the BLE service. If null, a default UUID is used.
  final String? serviceUuid;

  /// Constructor for [_FlutterP2pConnection].
  const _FlutterP2pConnection({this.serviceUuid});

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

/// The [FlutterP2pHost] class facilitates creating and managing a
/// Wi-Fi Direct group (acting as a hotspot host) for P2P connections.
///
/// It allows initializing the host, creating a group (optionally advertising
/// credentials via BLE), removing the group, listening for state changes,
/// and sending/receiving data via the underlying [P2pTransportHost].
class FlutterP2pHost extends _FlutterP2pConnection {
  bool _isGroupCreated = false;
  bool _isBleAdvertising = false;
  P2pTransportHost? _p2pTransport;
  HotspotHostState? _lastKnownHotspotState;

  /// Constructor for [FlutterP2pHost].
  ///
  /// [serviceUuid] is an optional custom UUID for the BLE service.
  /// If null, a default UUID is used.
  FlutterP2pHost({super.serviceUuid});

  /// Returns `true` if a Wi-Fi Direct group has been successfully created.
  bool get isGroupCreated => _isGroupCreated;

  /// Returns `true` if the host is currently advertising hotspot credentials via BLE.
  bool get isAdvertising => _isBleAdvertising;

  /// Gets the current list of connected clients.
  List<P2pClientInfo> get clientList => _p2pTransport?.clientList ?? [];

  /// Gets the list of files currently hosted by this host.
  List<HostedFileInfo> get hostedFileInfos =>
      _p2pTransport?.hostedFileInfos ?? [];

  /// Gets the list of files that this host can receive/download.
  List<ReceivableFileInfo> get receivableFileInfos =>
      _p2pTransport?.receivableFileInfos ?? [];

  /// Initializes the P2P connection host resources on the native platform.
  ///
  /// This method must be called before any other host operations.
  Future<void> initialize() async {
    _p2pTransport = null;
    _lastKnownHotspotState = null;
    await FlutterP2pConnectionPlatform.instance.initialize(
      serviceUuid: serviceUuid,
    );
  }

  /// Disposes of the P2P connection host resources and cleans up connections.
  ///
  /// This method should be called when the host functionality is no longer needed
  /// to release system resources.
  Future<void> dispose() async {
    try {
      await removeGroup();
    } catch (e) {
      debugPrint("FlutterP2pHost: Error during removeGroup in dispose: $e");
    }
    await FlutterP2pConnectionPlatform.instance.dispose();
    _lastKnownHotspotState = null;
    debugPrint("FlutterP2pHost disposed.");
  }

  /// Creates a Wi-Fi Direct group (hotspot) and starts the P2P transport layer.
  ///
  /// Optionally advertises hotspot credentials via BLE.
  ///
  /// - [advertise]: If `true` (default), starts BLE advertising with hotspot credentials.
  /// - [timeout]: Duration to wait for the hotspot to become active with an IP address.
  ///   Defaults to 60 seconds.
  ///
  /// Returns a [Future] completing with the [HotspotHostState] containing
  /// connection details (SSID, PSK, IP address).
  /// Throws an [Exception] or [TimeoutException] on failure.
  Future<HotspotHostState> createGroup({
    bool advertise = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_p2pTransport != null) {
      await _p2pTransport!.stop().catchError((e) {
        debugPrint('Host: Error stopping previous P2P transport: $e');
      });
    }
    _p2pTransport = null;
    _lastKnownHotspotState = null;

    await FlutterP2pConnectionPlatform.instance.createHotspot();
    _isGroupCreated = true;
    debugPrint("Host: Native hotspot creation initiated.");

    HotspotHostState state;
    try {
      state = await streamHotspotState().firstWhere((s) {
        if (s.isActive &&
            s.ssid != null &&
            s.preSharedKey != null &&
            s.hostIpAddress != null) {
          _lastKnownHotspotState = s; // Store the valid state
          return true;
        }
        return false;
      }).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
              'Host: Timed out after $timeout waiting for active hotspot state with IP.');
        },
      );
      debugPrint("Host: Received active state with IP: $state");
    } catch (e) {
      debugPrint("Host: Error waiting for hotspot state: $e");
      await removeGroup().catchError((removeError) => debugPrint(
          "Host: Error during cleanup after state acquisition failure: $removeError"));
      rethrow;
    }

    if (advertise) {
      try {
        await FlutterP2pConnectionPlatform.instance.startBleAdvertising(
          state.ssid!,
          state.preSharedKey!,
        );
        _isBleAdvertising = true;
        debugPrint("Host: BLE advertising started.");
      } catch (e) {
        debugPrint('Host: Failed to start BLE advertising: $e');
        _isBleAdvertising = false;
        await removeGroup().catchError((removeError) => debugPrint(
            "Host: Error during cleanup after BLE advertising failure: $removeError"));
        throw Exception(
            'Host: Failed to start BLE advertising, which was requested: $e');
      }
    } else {
      _isBleAdvertising = false;
    }

    _p2pTransport = P2pTransportHost(
      defaultPort: _defaultP2pTransportPort,
      username: await FlutterP2pConnectionPlatform.instance.getPlatformModel(),
    );
    try {
      await _p2pTransport!.start();
    } catch (e) {
      debugPrint('Host: Failed to start P2P Transport: $e');
      await removeGroup().catchError((removeError) => debugPrint(
          "Host: Error during cleanup after P2P transport start failure: $removeError"));
      throw Exception('Host: Failed to start P2P Transport: $e');
    }
    return state;
  }

  /// Removes the currently active Wi-Fi Direct group (hotspot).
  ///
  /// This stops BLE advertising (if active), stops the P2P transport layer,
  /// and tears down the native hotspot group.
  Future<void> removeGroup() async {
    debugPrint("Host: Removing group...");
    if (_isBleAdvertising) {
      await FlutterP2pConnectionPlatform.instance
          .stopBleAdvertising()
          .catchError((e) {
        debugPrint('Host: Error stopping BLE advertising: $e');
      });
      _isBleAdvertising = false;
    }

    await _p2pTransport?.stop().catchError((e) {
      debugPrint('Host: Error stopping P2P transport: $e');
    });
    _p2pTransport = null;

    if (_isGroupCreated) {
      await FlutterP2pConnectionPlatform.instance
          .removeHotspot()
          .catchError((e) {
        debugPrint('Host: Error removing hotspot group natively: $e');
      });
      _isGroupCreated = false;
    }
    _lastKnownHotspotState = null;
    debugPrint("Host: Group removal process finished.");
  }

  /// Provides a stream of [HotspotHostState] updates from the platform.
  ///
  /// Listen to this stream to receive real-time information about the host's
  /// hotspot status, including whether it's active, its SSID, PSK, IP address,
  /// and any failure reasons.
  Stream<HotspotHostState> streamHotspotState() {
    return FlutterP2pConnectionPlatform.instance
        .streamHotspotInfo()
        .map((state) {
      if (state.isActive && state.hostIpAddress != null) {
        _lastKnownHotspotState = state; // Keep track of the latest good state
      } else if (!state.isActive && _lastKnownHotspotState?.isActive == true) {
        // If it becomes inactive, clear our known good IP.
        // _lastKnownHotspotState = state; // Store the inactive state
      }
      return state;
    });
  }

  /// Provides a stream that emits the updated list of connected [P2pClientInfo]s
  /// periodically.
  Stream<List<P2pClientInfo>> streamClientList() async* {
    while (true) {
      yield _p2pTransport?.clientList ?? [];
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Broadcasts a [String] message to all connected clients.
  ///
  /// - [text]: The message to send.
  /// - [excludeClientIds]: Optional list of client IDs to exclude from the broadcast.
  /// Throws a [StateError] if the P2P transport is not active.
  Future<void> broadcastText(String text,
      {List<String>? excludeClientIds}) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      throw StateError(
          'Host: P2P transport is not active. Ensure createGroup() was called successfully.');
    }
    var message = P2pMessage(
      senderId: transport.hostId,
      type: P2pMessageType.payload,
      payload: P2pMessagePayload(text: text),
    );
    await transport.broadcast(message, excludeClientIds: excludeClientIds);
  }

  /// Sends a [String] message to a specific client.
  ///
  /// - [text]: The message to send.
  /// - [clientId]: The ID of the target client.
  /// Returns `true` if the message was sent successfully, `false` otherwise.
  /// Throws a [StateError] if the P2P transport is not active.
  Future<bool> sendTextToClient(String text, String clientId) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      throw StateError(
          'Host: P2P transport is not active. Ensure createGroup() was called successfully.');
    }
    var message = P2pMessage(
      senderId: transport.hostId,
      type: P2pMessageType.payload,
      payload: P2pMessagePayload(text: text),
    );
    return await transport.sendToClient(clientId, message);
  }

  /// Broadcasts a [File] to all connected clients (or a subset).
  ///
  /// - [file]: The [File] to send.
  /// - [excludeClientIds]: Optional list of client IDs to exclude from receiving the file.
  /// Returns a [Future] completing with [P2pFileInfo] if the file sharing is initiated,
  /// or `null` on failure.
  /// Throws a [StateError] if P2P transport is not active or host IP is unknown.
  Future<P2pFileInfo?> broadcastFile(File file,
      {List<String>? excludeClientIds}) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      throw StateError(
          'Host: P2P transport is not active for broadcasting file.');
    }
    if (_lastKnownHotspotState?.hostIpAddress == null) {
      throw StateError('Host: Host IP address is unknown. Cannot share file.');
    }
    var recipients = excludeClientIds == null || excludeClientIds.isEmpty
        ? null
        : transport.clientList
            .where((client) => !excludeClientIds.contains(client.id))
            .toList();
    return await transport.shareFile(file,
        actualSenderIp: _lastKnownHotspotState!.hostIpAddress!,
        recipients: recipients);
  }

  /// Sends a [File] to a specific client.
  ///
  /// - [file]: The [File] to send.
  /// - [clientId]: The ID of the target client.
  /// Returns a [Future] completing with [P2pFileInfo] if the file sharing is initiated,
  /// or `null` if the client is not found or on failure.
  /// Throws a [StateError] if P2P transport is not active or host IP is unknown.
  Future<P2pFileInfo?> sendFileToClient(File file, String clientId) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      throw StateError('Host: P2P transport is not active for sending file.');
    }
    if (_lastKnownHotspotState?.hostIpAddress == null) {
      throw StateError('Host: Host IP address is unknown. Cannot share file.');
    }
    var recipients =
        transport.clientList.where((client) => client.id == clientId).toList();
    if (recipients.isEmpty) {
      debugPrint("Host: Client $clientId not found for sending file.");
      return null;
    }
    return await transport.shareFile(file,
        actualSenderIp: _lastKnownHotspotState!.hostIpAddress!,
        recipients: recipients);
  }

  /// Provides a stream of text messages received from clients.
  /// Waits for the P2P transport to be initialized if it's not already.
  Stream<String> streamReceivedTexts() async* {
    // Yield immediately if transport is already available
    if (_p2pTransport != null) {
      yield* _p2pTransport!.receivedTextStream;
      return; // Important to exit after yielding from existing stream
    }
    // Wait for transport to be initialized
    while (_p2pTransport == null) {
      await Future.delayed(const Duration(milliseconds: 100)); // Shorter delay
    }
    yield* _p2pTransport!.receivedTextStream;
  }

  /// Provides a stream that periodically emits the list of [HostedFileInfo]
  /// representing files shared by this host and their sending status.
  Stream<List<HostedFileInfo>> streamSentFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.hostedFileInfos ?? [];
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Provides a stream that periodically emits the list of [ReceivableFileInfo]
  /// representing files that this host has been informed about and can download.
  Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.receivableFileInfos ?? [];
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Downloads a file that this host has been informed about.
  ///
  /// - [fileId]: The unique ID of the file to download (from [ReceivableFileInfo.info.id]).
  /// - [saveDirectory]: The directory path where the downloaded file should be saved.
  /// - [customFileName]: Optional custom name for the saved file. If null, uses the original name.
  /// - [deleteOnError]: If `true` (default), deletes partially downloaded file on error.
  /// - [onProgress]: Optional callback to receive [FileDownloadProgressUpdate]s.
  /// - [rangeStart]: Optional start byte for ranged download (for resuming).
  /// - [rangeEnd]: Optional end byte for ranged download.
  ///
  /// Returns a [Future] completing with `true` if the download is successful,
  /// `false` otherwise.
  /// Throws a [StateError] if the P2P transport is not active.
  Future<bool> downloadFile(
    String fileId,
    String saveDirectory, {
    String? customFileName,
    bool? deleteOnError,
    Function(FileDownloadProgressUpdate)? onProgress,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      throw StateError(
          'Host: P2P transport is not active. Ensure createGroup() was called successfully.');
    }
    // Host typically doesn't download from clients unless it's a specific feature
    // For now, assume it's downloading a file it previously received info about.
    return await transport.downloadFile(
      fileId,
      saveDirectory,
      customFileName: customFileName,
      deleteOnError: deleteOnError,
      onProgress: onProgress,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }
}

/// The [FlutterP2pClient] class facilitates discovering and connecting
/// to a P2P host (Wi-Fi Direct group).
///
/// It allows initializing the client, scanning for hosts via BLE, connecting
/// to a discovered host (either via BLE data exchange or directly with credentials),
/// disconnecting, listening for connection state changes, and sending/receiving
/// data via the underlying [P2pTransportClient].
class FlutterP2pClient extends _FlutterP2pConnection {
  bool _isScanning = false;
  P2pTransportClient? _p2pTransport;
  HotspotClientState? _lastKnownClientState; // To store client's IP in group

  StreamSubscription<List<BleDiscoveredDevice>>? _scanStreamSub;
  Timer? _scanTimer;

  /// Constructor for [FlutterP2pClient].
  ///
  /// [serviceUuid] is an optional custom UUID for the BLE service.
  /// If null, a default UUID is used.
  FlutterP2pClient({super.serviceUuid});

  /// Returns `true` if the client is currently scanning for BLE devices.
  bool get isScanning => _isScanning;

  /// Returns `true` if the client's P2P transport layer is connected to the host.
  bool get isConnected => _p2pTransport?.isConnected ?? false;

  /// Gets the current list of clients in the P2P group (including self and host).
  List<P2pClientInfo> get clientList => _p2pTransport?.clientList ?? [];

  /// Gets the list of files currently hosted by this client.
  List<HostedFileInfo> get hostedFileInfos =>
      _p2pTransport?.hostedFileInfos ?? [];

  /// Gets the list of files that this client can receive/download.
  List<ReceivableFileInfo> get receivableFileInfos =>
      _p2pTransport?.receivableFileInfos ?? [];

  /// Initializes the P2P connection client resources on the native platform.
  Future<void> initialize({String? serviceUuid}) async {
    try {
      await _p2pTransport?.dispose();
    } catch (_) {}
    _p2pTransport = null;
    _lastKnownClientState = null;
    _scanStreamSub?.cancel();
    _scanStreamSub = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    await FlutterP2pConnectionPlatform.instance.initialize(
      serviceUuid: serviceUuid,
    );
  }

  /// Disposes of the P2P connection client resources and cleans up connections.
  ///
  /// This method should be called when the client functionality is no longer needed
  /// to release system resources.
  Future<void> dispose() async {
    await stopScan().catchError(
        (e) => debugPrint("Client: Error stopping scan in dispose: $e"));
    await disconnect().catchError(
        (e) => debugPrint("Client: Error disconnecting in dispose: $e"));
    await _p2pTransport?.dispose().catchError(
        (e) => debugPrint("Client: Error disposing transport in dispose: $e"));
    _p2pTransport = null;
    _lastKnownClientState = null;
    await FlutterP2pConnectionPlatform.instance.dispose();
    debugPrint("FlutterP2pClient disposed.");
  }

  /// Starts scanning for nearby BLE devices advertising P2P host credentials.
  ///
  /// Listens to the BLE scan results stream and calls the [onData] callback
  /// whenever new devices are found. The scan automatically stops after the
  /// specified [timeout] duration (default 15 seconds) or if [stopScan] is called.
  ///
  /// - [onData]: Callback function invoked with a list of [BleDiscoveredDevice] found.
  /// - [onError]: Optional callback for handling errors during the scan stream.
  /// - [onDone]: Optional callback invoked when the scan stream is closed (e.g., timeout or manual stop).
  /// - [cancelOnError]: If `true`, the stream subscription cancels on the first error.
  /// - [timeout]: Duration after which the scan will automatically stop. Defaults to 15 seconds.
  ///
  /// Returns a [Future] completing with the [StreamSubscription] for the scan results.
  /// Throws an exception if starting the native BLE scan fails.
  Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(
    void Function(List<BleDiscoveredDevice>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_isScanning) {
      await stopScan();
    }
    debugPrint("Client: Starting BLE scan...");
    _isScanning = true;

    _scanStreamSub =
        FlutterP2pConnectionPlatform.instance.streamBleScanResult().listen(
      (devices) {
        if (_isScanning) onData?.call(devices);
      },
      onError: (error) {
        debugPrint("Client: BLE Scan stream error: $error");
        onError?.call(error);
        if (cancelOnError ?? false) {
          stopScan(); // This will also set _isScanning to false and clean up
        }
      },
      onDone: () {
        debugPrint("Client: BLE Scan stream done (completed or cancelled).");
        // This onDone is critical. It means the stream is finished.
        // We must ensure our state reflects this.
        _isScanning = false; // Mark as not scanning
        _scanTimer?.cancel();
        _scanTimer = null;
        // The native scan should be stopped by the platform when the stream ends,
        // or by our explicit call in stopScan if we initiated the end.
        // Call user's onDone.
        onDone?.call();
        _scanStreamSub = null; // Clear the subscription reference
      },
      cancelOnError: cancelOnError,
    );

    _scanTimer = Timer(timeout, () {
      debugPrint("Client: Scan timeout reached. Stopping scan.");
      onDone?.call();
      stopScan(); // This will cancel the stream and trigger its onDone.
    });

    try {
      await FlutterP2pConnectionPlatform.instance.startBleScan();
      debugPrint("Client: Native BLE scan started successfully.");
      return _scanStreamSub!;
    } catch (e) {
      debugPrint('Client: Failed to start native BLE scan: $e');
      _isScanning = false; // Failed to start
      _scanTimer?.cancel();
      _scanTimer = null;
      // Attempt to cancel the subscription, which should call its onDone for cleanup
      await _scanStreamSub?.cancel();
      _scanStreamSub = null;
      rethrow;
    }
  }

  /// Stops the ongoing BLE scan if one is active.
  Future<void> stopScan() async {
    if (!_isScanning && _scanStreamSub == null && _scanTimer == null) {
      return; // Already stopped or not properly started
    }
    debugPrint("Client: Attempting to stop BLE scan...");

    _isScanning = false; // Set our intent to stop

    _scanTimer?.cancel();
    _scanTimer = null;

    if (_scanStreamSub != null) {
      await _scanStreamSub!
          .cancel(); // This should trigger the onDone of the stream listener
      _scanStreamSub = null;
    } else {
      // If stream sub is null but we thought we were scanning, or timer was active.
      // This case might happen if startScan failed after _isScanning=true but before sub was assigned.
      // Or if stopScan is called multiple times.
      // Ensure native scan is stopped if no Dart stream to cancel.
      debugPrint(
          "Client: No active scan stream subscription to cancel, ensuring native scan is stopped.");
      await FlutterP2pConnectionPlatform.instance.stopBleScan().catchError((e) {
        debugPrint(
            'Client: Error stopping BLE scan natively during explicit stopScan (no stream sub): $e');
      });
    }
    debugPrint("Client: BLE scan stop process finished.");
  }

  /// Connects to a BLE device, retrieves hotspot credentials, and then connects to the Wi-Fi hotspot.
  ///
  /// 1. Connects to the specified BLE device.
  /// 2. Listens for SSID and PSK data sent over BLE characteristics.
  /// 3. Disconnects from the BLE device.
  /// 4. Calls [connectWithCredentials] with the retrieved credentials.
  ///
  /// - [device]: The [BleDiscoveredDevice] to connect to.
  /// - [timeout]: Duration to wait for credentials via BLE and for Wi-Fi connection.
  ///   Defaults to 20 seconds for BLE credential exchange.
  ///
  /// Throws an [Exception] or [TimeoutException] if any step fails, including
  /// BLE connection, credential reception, or Wi-Fi hotspot connection.
  Future<void> connectWithDevice(
    BleDiscoveredDevice device, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    String deviceAddress = device.deviceAddress;
    debugPrint("Client: Connecting to BLE device $deviceAddress...");
    await FlutterP2pConnectionPlatform.instance.connectBleDevice(deviceAddress);
    debugPrint("Client: Connected to BLE device $deviceAddress.");

    String? ssid;
    String? psk;
    StreamSubscription<BleReceivedData>? bleDataSub;
    final completer = Completer<void>();

    try {
      bleDataSub =
          FlutterP2pConnectionPlatform.instance.streamBleReceivedData().listen(
        (evt) {
          if (evt.deviceAddress == deviceAddress) {
            String value = String.fromCharCodes(evt.data);
            if (ssid == null) {
              ssid = value;
              debugPrint("Client: Received SSID via BLE: $ssid");
            } else if (psk == null) {
              psk = value;
              debugPrint("Client: Received PSK via BLE (not logging value)");
              if (!completer.isCompleted) completer.complete();
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(
                Exception('Client: Error receiving BLE data: $error'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(Exception(
                'Client: BLE data stream ended before receiving credentials.'));
          }
        },
      );

      await completer.future.timeout(timeout, onTimeout: () {
        throw TimeoutException(
            'Client: Timed out waiting for hotspot credentials via BLE after $timeout.');
      });

      if (ssid == null || psk == null) {
        throw Exception(
            'Client: Failed to receive valid hotspot SSID and PSK via BLE.');
      }

      debugPrint("Client: Attempting to connect to hotspot: $ssid");
      await connectWithCredentials(ssid!, psk!);
      debugPrint("Client: Successfully connected to hotspot: $ssid");
    } catch (e) {
      debugPrint("Client: Error during connectWithDevice: $e");
      rethrow;
    } finally {
      await bleDataSub?.cancel();
      await FlutterP2pConnectionPlatform.instance
          .disconnectBleDevice(deviceAddress)
          .catchError((e) {
        debugPrint(
            'Client: Error disconnecting from BLE device $deviceAddress: $e');
      });
      debugPrint("Client: Disconnected from BLE device $deviceAddress.");
    }
  }

  /// Connects directly to a Wi-Fi Direct hotspot using provided credentials and initializes the P2P transport client.
  ///
  /// 1. Initiates the native platform connection to the hotspot using SSID and PSK.
  /// 2. Waits for the [HotspotClientState] stream to confirm an active connection
  ///    with valid gateway and client IP addresses.
  /// 3. Initializes and connects the [P2pTransportClient] to the host's gateway IP.
  ///
  /// - [ssid]: The Service Set Identifier (network name) of the hotspot.
  /// - [psk]: The Pre-Shared Key (password) for the hotspot.
  /// - [timeout]: Duration to wait for successful Wi-Fi connection state confirmation.
  ///   Defaults to 60 seconds.
  ///
  /// Throws an [Exception] or [TimeoutException] if the connection confirmation
  /// fails or if the P2P transport connection fails.
  Future<void> connectWithCredentials(
    String ssid,
    String psk, {
    Duration timeout =
        const Duration(seconds: 60), // Increased default for Wi-Fi connection
  }) async {
    debugPrint("Client: Connecting to hotspot '$ssid'...");
    await _p2pTransport?.disconnect().catchError((e) {
      debugPrint('Client: Error disconnecting previous P2P transport: $e');
    });
    await _p2pTransport?.dispose();
    _p2pTransport = null;
    _lastKnownClientState = null;

    await FlutterP2pConnectionPlatform.instance.connectToHotspot(ssid, psk);
    debugPrint("Client: Native connectToHotspot initiated for '$ssid'.");

    HotspotClientState state;
    try {
      state = await streamHotspotState().firstWhere((s) {
        if (s.isActive &&
            s.hostSsid == ssid &&
            s.hostGatewayIpAddress != null &&
            s.hostIpAddress != null) {
          _lastKnownClientState = s; // Store the valid state
          return true;
        }
        return false;
      }).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
              'Client: Timed out after $timeout waiting for active connection state with gateway and client IP.');
        },
      );
      debugPrint("Client: Received active connection state: $state");
    } catch (e) {
      debugPrint("Client: Error waiting for connection state: $e");
      await disconnect().catchError((disconnectError) => debugPrint(
          "Client: Error during cleanup after connection state failure: $disconnectError"));
      rethrow;
    }

    _p2pTransport = P2pTransportClient(
      hostIp: state.hostGatewayIpAddress!,
      defaultPort: _defaultP2pTransportPort,
      defaultFilePort: _defaultP2pTransportClientFileServerPort,
      username: await FlutterP2pConnectionPlatform.instance.getPlatformModel(),
    );
    try {
      await _p2pTransport!.connect();
    } catch (e) {
      debugPrint('Client: Failed to connect P2P Transport: $e');
      await disconnect().catchError((disconnectError) => debugPrint(
          "Client: Error during cleanup after P2P transport connection failure: $disconnectError"));
      throw Exception('Client: Failed to connect P2P Transport: $e');
    }
  }

  /// Disconnects from the currently connected Wi-Fi Direct hotspot and stops the transport layer.
  ///
  /// This disconnects and disposes the [P2pTransportClient] first, then triggers the native
  /// platform disconnection from the hotspot.
  Future<void> disconnect() async {
    debugPrint("Client: Disconnecting from hotspot...");
    await _p2pTransport?.disconnect().catchError((e) {
      debugPrint('Client: Error disconnecting P2P transport: $e');
    });
    await _p2pTransport?.dispose().catchError((e) {
      debugPrint('Client: Error disposing P2P transport: $e');
    });
    _p2pTransport = null;
    _lastKnownClientState = null;

    await FlutterP2pConnectionPlatform.instance
        .disconnectFromHotspot()
        .catchError((e) {
      debugPrint('Client: Error disconnecting from hotspot natively: $e');
    });
    debugPrint("Client: Native hotspot disconnection process finished.");
  }

  /// Provides a stream of [HotspotClientState] updates from the platform.
  ///
  /// Listen to this stream to receive real-time information about the client's
  /// connection status to a hotspot, including whether it's connected, the
  /// host's SSID, and IP address details (gateway and client IP).
  Stream<HotspotClientState> streamHotspotState() {
    return FlutterP2pConnectionPlatform.instance
        .streamHotspotClientState()
        .map((state) {
      if (state.isActive &&
          state.hostGatewayIpAddress != null &&
          state.hostIpAddress != null) {
        _lastKnownClientState = state; // Keep track of the latest good state
      } else if (!state.isActive && _lastKnownClientState?.isActive == true) {
        // If it becomes inactive, clear our known good state.
        // _lastKnownClientState = state; // Store the inactive state
      }
      return state;
    });
  }

  /// Provides a stream that periodically emits the updated list of connected [P2pClientInfo]s
  /// in the P2P group.
  Stream<List<P2pClientInfo>> streamClientList() async* {
    while (true) {
      yield _p2pTransport?.clientList ?? [];
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Broadcasts a [String] message to other clients in the group (excluding self).
  ///
  /// - [text]: The message to send.
  /// - [excludeClientId]: Optional ID of another client to also exclude.
  /// Throws a [StateError] if the P2P transport is not connected.
  Future<void> broadcastText(String text, {String? excludeClientId}) async {
    final transport = _p2pTransport;
    if (transport == null || !transport.isConnected) {
      throw StateError(
          'Client: P2P transport is not connected. Cannot broadcast data.');
    }
    var message = P2pMessage(
      senderId: transport.clientId,
      type: P2pMessageType.payload,
      payload: P2pMessagePayload(text: text),
      clients: transport.clientList
          .where((client) =>
              client.id != excludeClientId && client.id != transport.clientId)
          .toList(), // Exclude self and optionally another
    );
    await transport.send(message);
  }

  /// Sends a [String] message to a specific client in the group.
  ///
  /// - [text]: The message to send.
  /// - [clientId]: The ID of the target client.
  /// Returns `true` if the message was sent successfully, `false` otherwise (e.g., client not found).
  /// Throws a [StateError] if the P2P transport is not connected.
  Future<bool> sendTextToClient(String text, String clientId) async {
    final transport = _p2pTransport;
    if (transport == null || !transport.isConnected) {
      throw StateError(
          'Client: P2P transport is not connected. Cannot send data.');
    }
    final targetClient = transport.clientList
        .where((c) => c.id == clientId)
        .firstOrNull; // Find the client info
    if (targetClient == null) {
      debugPrint("Client: Target client $clientId not found in client list.");
      return false;
    }
    var message = P2pMessage(
      senderId: transport.clientId,
      type: P2pMessageType.payload,
      payload: P2pMessagePayload(text: text),
      clients: [targetClient], // Target only the specific client
    );
    return await transport.send(message);
  }

  /// Broadcasts a [File] to other clients in the group (excluding self).
  ///
  /// - [file]: The [File] to send.
  /// - [excludeClientIds]: Optional list of client IDs to also exclude from receiving the file.
  /// Returns a [Future] completing with [P2pFileInfo] if the file sharing is initiated,
  /// or `null` on failure.
  /// Throws a [StateError] if P2P transport is not connected or client IP is unknown.
  Future<P2pFileInfo?> broadcastFile(File file,
      {List<String>? excludeClientIds}) async {
    final transport = _p2pTransport;
    if (transport == null || !transport.isConnected) {
      throw StateError(
          'Client: P2P transport is not connected for broadcasting file.');
    }
    if (_lastKnownClientState?.hostIpAddress == null) {
      // This is client's own IP in group
      throw StateError(
          'Client: Client IP address in group is unknown. Cannot share file.');
    }

    var recipients = transport.clientList
        .where((client) =>
            client.id != transport.clientId &&
            (excludeClientIds == null || !excludeClientIds.contains(client.id)))
        .toList();
    return await transport.shareFile(file,
        actualSenderIp: _lastKnownClientState!.hostIpAddress!,
        recipients: recipients);
  }

  /// Sends a [File] to a specific client in the group.
  ///
  /// - [file]: The [File] to send.
  /// - [clientId]: The ID of the target client.
  /// Returns a [Future] completing with [P2pFileInfo] if the file sharing is initiated,
  /// or `null` if the client is not found or on failure.
  /// Throws a [StateError] if P2P transport is not connected or client IP is unknown.
  Future<P2pFileInfo?> sendFileToClient(File file, String clientId) async {
    final transport = _p2pTransport;
    if (transport == null || !transport.isConnected) {
      throw StateError(
          'Client: P2P transport is not connected for sending file.');
    }
    if (_lastKnownClientState?.hostIpAddress == null) {
      // This is client's own IP in group
      throw StateError(
          'Client: Client IP address in group is unknown. Cannot share file.');
    }
    var recipients =
        transport.clientList.where((client) => client.id == clientId).toList();
    if (recipients.isEmpty) {
      debugPrint("Client: Target client $clientId not found for sending file.");
      return null;
    }
    return await transport.shareFile(file,
        actualSenderIp: _lastKnownClientState!.hostIpAddress!,
        recipients: recipients);
  }

  /// Provides a stream of text messages received from the host or other clients.
  /// Waits for the P2P transport to be initialized if it's not already.
  Stream<String> streamReceivedTexts() async* {
    if (_p2pTransport != null) {
      yield* _p2pTransport!.receivedTextStream;
      return;
    }
    while (_p2pTransport == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    yield* _p2pTransport!.receivedTextStream;
  }

  /// Provides a stream that periodically emits the list of [HostedFileInfo]
  /// representing files shared by this client and their sending status.
  Stream<List<HostedFileInfo>> streamSentFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.hostedFileInfos ?? [];
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Provides a stream that periodically emits the list of [ReceivableFileInfo]
  /// representing files that this client has been informed about and can download.
  Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.receivableFileInfos ?? [];
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Downloads a file that this client has been informed about.
  ///
  /// - [fileId]: The unique ID of the file to download (from [ReceivableFileInfo.info.id]).
  /// - [saveDirectory]: The directory path where the downloaded file should be saved.
  /// - [customFileName]: Optional custom name for the saved file. If null, uses the original name.
  /// - [deleteOnError]: If `true` (default), deletes partially downloaded file on error.
  /// - [onProgress]: Optional callback to receive [FileDownloadProgressUpdate]s.
  /// - [rangeStart]: Optional start byte for ranged download (for resuming).
  /// - [rangeEnd]: Optional end byte for ranged download.
  ///
  /// Returns a [Future] completing with `true` if the download is successful,
  /// `false` otherwise.
  /// Throws a [StateError] if the P2P transport is not connected.
  Future<bool> downloadFile(
    String fileId,
    String saveDirectory, {
    String? customFileName,
    bool? deleteOnError,
    Function(FileDownloadProgressUpdate)? onProgress,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final transport = _p2pTransport;
    if (transport == null || !transport.isConnected) {
      throw StateError(
          'Client: P2P transport is not connected. Cannot download file.');
    }
    return await transport.downloadFile(
      fileId,
      saveDirectory,
      customFileName: customFileName,
      deleteOnError: deleteOnError,
      onProgress: onProgress,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }
}

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
