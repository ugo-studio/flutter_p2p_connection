import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../flutter_p2p_connection_platform_interface.dart';
import '../common/p2p_constants.dart';
import '../common/p2p_connection_base.dart';
import '../models/p2p_connection_models.dart';
import '../transport/common/transport_data_models.dart';
import '../transport/common/transport_enums.dart';
import '../transport/common/transport_file_models.dart';
import '../transport/client/transport_client.dart';

/// The [FlutterP2pClient] class facilitates discovering and connecting
/// to a P2P host (Wi-Fi Direct group).
///
/// It allows initializing the client, scanning for hosts via BLE, connecting
/// to a discovered host (either via BLE data exchange or directly with credentials),
/// disconnecting, listening for connection state changes, and sending/receiving
/// data via the underlying P2P transport layer.
class FlutterP2pClient extends FlutterP2pConnectionBase {
  bool _isScanning = false;
  P2pTransportClient? _p2pTransport;
  HotspotClientState? _lastKnownClientState; // To store client's IP in group

  StreamSubscription<List<BleDiscoveredDevice>>? _scanStreamSub;
  Timer? _scanTimer;

  /// Constructor for [FlutterP2pClient].
  ///
  /// [serviceUuid] is an optional custom UUID for the BLE service.
  ///               If null, a default UUID is used.
  /// [bondingRequired] optional bonding by BLE service.
  /// [encryptionRequired] optional encryption by BLE service.
  /// [username] is an optional custom user name for the device.
  FlutterP2pClient({
    super.serviceUuid,
    super.bondingRequired,
    super.encryptionRequired,
    super.username,
  });

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
  Future<void> initialize() async {
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
      bondingRequired: bondingRequired,
      encryptionRequired: encryptionRequired,
    );
  }

  /// Disposes of the P2P connection client resources and cleans up connections.
  ///
  /// This method should be called when the client functionality is no longer needed
  /// to release system resources.
  Future<void> dispose() async {
    await _p2pTransport?.dispose().catchError(
        (e) => debugPrint("Client: Error disposing transport in dispose: $e"));
    _p2pTransport = null;
    _lastKnownClientState = null;
    await stopScan().catchError(
        (e) => debugPrint("Client: Error stopping scan in dispose: $e"));
    await disconnect().catchError(
        (e) => debugPrint("Client: Error disconnecting in dispose: $e"));
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
      defaultPort: defaultP2pTransportPort,
      defaultFilePort: defaultP2pTransportClientFileServerPort,
      username: username ??
          await FlutterP2pConnectionPlatform.instance.getPlatformModel(),
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
