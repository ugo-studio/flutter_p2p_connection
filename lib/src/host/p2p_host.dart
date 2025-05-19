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
import '../transport/host/transport_host.dart';

/// The [FlutterP2pHost] class facilitates creating and managing a
/// Wi-Fi Direct group (acting as a hotspot host) for P2P connections.
///
/// It allows initializing the host, creating a group (optionally advertising
/// credentials via BLE), removing the group, listening for state changes,
/// and sending/receiving data via the underlying P2P transport layer.
class FlutterP2pHost extends FlutterP2pConnectionBase {
  bool _isGroupCreated = false;
  bool _isBleAdvertising = false;
  P2pTransportHost? _p2pTransport;
  HotspotHostState? _lastKnownHotspotState;

  /// Constructor for [FlutterP2pHost].
  ///
  /// [serviceUuid] is an optional custom UUID for the BLE service.
  ///               If null, a default UUID is used.
  /// [bondingRequired] optional bonding by BLE service.
  /// [encryptionRequired] optional encryption by BLE service.
  /// [username] is an optional custom user name for device.
  FlutterP2pHost({
    super.serviceUuid,
    super.bondingRequired,
    super.encryptionRequired,
    super.username,
  });

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
      bondingRequired: bondingRequired,
      encryptionRequired: encryptionRequired,
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
      defaultPort: defaultP2pTransportPort,
      username: username ??
          await FlutterP2pConnectionPlatform.instance.getPlatformModel(),
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
