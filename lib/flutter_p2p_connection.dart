import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';

const int _defaultP2pTransportPort = 3456;
const int _defaultP2pTransportClientFileServerPort = 4567;

class _FlutterP2pConnection {
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();

  Future<bool> enableLocationServices() async {
    await FlutterP2pConnectionPlatform.instance.enableLocationServices();
    return await checkLocationEnabled();
  }

  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();

  Future<bool> enableWifiServices() async {
    await FlutterP2pConnectionPlatform.instance.enableWifiServices();
    return await checkWifiEnabled();
  }

  Future<bool> checkBluetoothEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkBluetoothEnabled();

  Future<bool> enableBluetoothServices() async {
    await FlutterP2pConnectionPlatform.instance.enableBluetoothServices();
    return await checkBluetoothEnabled();
  }

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

  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();

  Future<bool> askP2pPermissions() async {
    await FlutterP2pConnectionPlatform.instance.askP2pPermissions();
    return await checkP2pPermissions();
  }

  Future<bool> checkStoragePermission() async {
    // Consider Scoped Storage for Android 10+
    return await Permission.storage.isGranted;
  }

  Future<bool> askStoragePermission() async {
    // Consider Scoped Storage for Android 10+
    final status = await Permission.storage.request();
    return status.isGranted;
  }
}

class FlutterP2pHost extends _FlutterP2pConnection {
  bool _isGroupCreated = false;
  bool _isBleAdvertising = false;
  P2pTransportHost? _p2pTransport;
  HotspotHostState? _lastKnownHotspotState; // To store the latest state

  bool get isGroupCreated => _isGroupCreated;
  bool get isAdvertising => _isBleAdvertising;
  List<P2pClientInfo> get clientList => _p2pTransport?.clientList ?? [];

  Future<void> initialize() async {
    _p2pTransport = null;
    _lastKnownHotspotState = null;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

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

  Stream<List<P2pClientInfo>> streamClientList() async* {
    while (true) {
      yield _p2pTransport?.clientList ?? [];
      await Future.delayed(const Duration(seconds: 1));
    }
  }

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

  Stream<List<HostedFileInfo>> streamSentFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.hostedFileInfos ?? [];
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.receivableFileInfos ?? [];
      await Future.delayed(const Duration(seconds: 1));
    }
  }

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

class FlutterP2pClient extends _FlutterP2pConnection {
  bool _isScanning = false;
  P2pTransportClient? _p2pTransport;
  HotspotClientState? _lastKnownClientState; // To store client's IP in group

  StreamSubscription<List<BleDiscoveredDevice>>? _scanStreamSub;
  Timer? _scanTimer;

  bool get isScanning => _isScanning;
  bool get isConnected => _p2pTransport?.isConnected ?? false;
  List<P2pClientInfo> get clientList => _p2pTransport?.clientList ?? [];

  Future<void> initialize({String? clientId}) async {
    await _p2pTransport?.dispose();
    _p2pTransport = null;
    _lastKnownClientState = null;
    _scanStreamSub?.cancel();
    _scanStreamSub = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

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
          if (!completer.isCompleted)
            completer.completeError(
                Exception('Client: Error receiving BLE data: $error'));
        },
        onDone: () {
          if (!completer.isCompleted)
            completer.completeError(Exception(
                'Client: BLE data stream ended before receiving credentials.'));
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

  Stream<List<P2pClientInfo>> streamClientList() async* {
    while (true) {
      yield _p2pTransport?.clientList ?? [];
      await Future.delayed(const Duration(seconds: 1));
    }
  }

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

  Future<bool> sendTextToClient(String text, String clientId) async {
    final transport = _p2pTransport;
    if (transport == null || !transport.isConnected) {
      throw StateError(
          'Client: P2P transport is not connected. Cannot send data.');
    }
    final targetClient = transport.clientList.firstWhere(
        (c) => c.id == clientId,
        orElse: () => P2pClientInfo(
            id: "null",
            username: "null",
            isHost: false)); // Find the client info
    if (targetClient.id == "null") {
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

  Stream<List<HostedFileInfo>> streamSentFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.hostedFileInfos ?? [];
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo() async* {
    while (true) {
      yield _p2pTransport?.receivableFileInfos ?? [];
      await Future.delayed(const Duration(seconds: 1));
    }
  }

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

@immutable
class HotspotHostState {
  final bool isActive;
  final String? ssid;
  final String? preSharedKey;
  final String? hostIpAddress;
  final int? failureReason;

  const HotspotHostState({
    required this.isActive,
    this.ssid,
    this.preSharedKey,
    this.hostIpAddress,
    this.failureReason,
  });

  factory HotspotHostState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotHostState(
      isActive: map['isActive'] as bool? ?? false,
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

@immutable
class HotspotClientState {
  final bool isActive;
  final String? hostSsid;
  final String?
      hostGatewayIpAddress; // Host's Gateway IP (for WebSocket connection)
  final String?
      hostIpAddress; // Client's own IP in the P2P group (for its file server)

  const HotspotClientState({
    required this.isActive,
    this.hostSsid,
    this.hostGatewayIpAddress,
    this.hostIpAddress,
  });

  factory HotspotClientState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotClientState(
      isActive: map['isActive'] as bool? ?? false,
      hostSsid: map['hostSsid'] as String?,
      hostGatewayIpAddress: map['hostGatewayIpAddress'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
    );
  }

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

@immutable
class BleConnectionState {
  final String deviceAddress;
  final String deviceName;
  final bool isConnected;

  const BleConnectionState({
    required this.deviceAddress,
    required this.deviceName,
    required this.isConnected,
  });

  factory BleConnectionState.fromMap(Map<dynamic, dynamic> map) {
    return BleConnectionState(
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      deviceName: map['deviceName'] as String? ?? 'Unknown Name',
      isConnected: map['isConnected'] as bool? ?? false,
    );
  }

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

@immutable
class BleDiscoveredDevice {
  final String deviceAddress;
  final String deviceName;

  const BleDiscoveredDevice({
    required this.deviceAddress,
    required this.deviceName,
  });

  factory BleDiscoveredDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleDiscoveredDevice(
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      deviceName: (map['deviceName'] as String?)?.isNotEmpty ?? false
          ? map['deviceName'] as String
          : 'Unknown Device',
    );
  }

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

@immutable
class BleReceivedData {
  final String deviceAddress;
  final String characteristicUuid;
  final Uint8List data;

  const BleReceivedData({
    required this.deviceAddress,
    required this.characteristicUuid,
    required this.data,
  });

  factory BleReceivedData.fromMap(Map<dynamic, dynamic> map) {
    return BleReceivedData(
      deviceAddress: map['deviceAddress'] as String? ?? 'Unknown Address',
      characteristicUuid:
          map['characteristicUuid'] as String? ?? 'Unknown UUID',
      data: map['data'] as Uint8List? ?? Uint8List(0),
    );
  }

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
