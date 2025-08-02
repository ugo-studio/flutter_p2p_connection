import 'dart:async';
import 'dart:io';
import 'dart:math'; // For min

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http; // For client download
import 'package:path/path.dart' as p; // For basename
import 'package:uuid/uuid.dart';

import '../common/file_request_server_mixin.dart';
import '../common/transport_data_models.dart';
import '../common/transport_enums.dart';
import '../common/transport_file_models.dart';

/// Manages the P2P client connection to a host and local file serving.
///
/// The client connects to a P2P host (via WebSocket) and can send/receive
/// messages and files. It also runs its own HTTP server to allow other peers
/// (including the host) to download files shared by this client.
class P2pTransportClient with FileRequestServerMixin {
  /// The IP address of the P2P host server.
  final String hostIp;

  /// The default port to try connecting to the host's WebSocket server.
  final int defaultPort;

  /// The default port for this client's local file server.
  final int defaultFilePort;

  /// The username of this client.
  final String username;

  /// Unique ID for this client instance.
  final String clientId = const Uuid().v4();

  WebSocket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;
  StreamSubscription? _socketSubscription;
  List<P2pClientInfo> _clientList = [];
  HttpServer? _fileServer;
  int? _fileServerPortInUse;
  final Map<String, HostedFileInfo> _hostedFiles = {};
  final Map<String, ReceivableFileInfo> _receivableFiles = {};
  final StreamController<String> _receivedTextController =
      StreamController<String>.broadcast();

  static const String _logPrefix = "P2P Transport Client";

  // Fields for retry mechanism
  int _connectionRetryAttempts = 0;
  static const int _maxConnectionRetries = 3;
  bool _isManuallyDisconnecting = false;

  @override
  Map<String, HostedFileInfo> get hostedFiles => _hostedFiles;
  @override
  String get transportUsername => username;

  /// Returns true if the client is currently connected to the host.
  bool get isConnected => _isConnected && _socket?.readyState == WebSocket.open;

  /// A list of other clients in the P2P group, as reported by the host.
  List<P2pClientInfo> get clientList => _clientList;

  /// The port on which this client's local file server is running, or null if not started.
  int? get fileServerPort => _fileServerPortInUse;

  /// A list of files currently being hosted (shared) by this client.
  List<HostedFileInfo> get hostedFileInfos => _hostedFiles.values.toList();

  /// A list of files that this client has been informed about and can download.
  List<ReceivableFileInfo> get receivableFileInfos =>
      _receivableFiles.values.toList();

  /// A stream of received text messages from the host or other clients.
  Stream<String> get receivedTextStream => _receivedTextController.stream;

  /// Creates a [P2pTransportClient] instance.
  ///
  /// [hostIp] is the IP address of the P2P host.
  /// [defaultPort] is the port for the host's WebSocket server.
  /// [defaultFilePort] is the port for this client's local HTTP file server.
  /// [username] is the display name for this client.
  P2pTransportClient({
    required this.hostIp,
    required this.defaultPort,
    required this.defaultFilePort,
    required this.username,
  });

  Future<bool> _startFileServer() async {
    if (_fileServer != null) {
      debugPrint(
          "$_logPrefix [$username]: File server already running on $_fileServerPortInUse.");
      return true;
    }
    int attempts = 0;
    int port = defaultFilePort;
    while (attempts < 10) {
      try {
        _fileServer =
            await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
        _fileServer!.idleTimeout =
            null; // Disable idleTimeout to avoid disconnection when idle
        _fileServerPortInUse = port;
        debugPrint(
            "$_logPrefix [$username]: File server started on port $_fileServerPortInUse");
        _fileServer!.listen(
          (HttpRequest request) async {
            final path = request.requestedUri.path;
            debugPrint(
                "$_logPrefix [$username]: File server received request for $path");
            if (path == '/file') {
              await handleFileRequest(request);
            } else {
              debugPrint(
                  "$_logPrefix [$username]: File server received invalid request ${request.method} ${request.uri}");
              request.response
                ..statusCode = HttpStatus.notFound
                ..write("Resource not found.")
                ..close();
            }
          },
          onError: (error) {
            debugPrint("$_logPrefix [$username]: File server error: $error");
          },
          onDone: () {
            debugPrint(
                "$_logPrefix [$username]: File server stopped listening.");
            _fileServerPortInUse = null;
          },
        );
        return true;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 ||
            e.osError?.errorCode == 48 ||
            e.message.contains('errno = 98') ||
            e.message.contains('errno = 48')) {
          debugPrint(
              "$_logPrefix [$username]: File server port $port in use, trying next...");
          port++;
          attempts++;
        } else {
          debugPrint("$_logPrefix [$username]: Error binding file server: $e");
          return false;
        }
      } catch (e) {
        debugPrint(
            "$_logPrefix [$username]: Unexpected error starting file server: $e");
        return false;
      }
    }
    debugPrint(
        "$_logPrefix [$username]: Could not bind file server to any port in range $defaultFilePort-${port - 1}.");
    return false;
  }

  Future<void> _stopFileServer() async {
    if (_fileServer != null) {
      debugPrint("$_logPrefix [$username]: Stopping file server...");
      await _fileServer?.close(force: true);
      _fileServer = null;
      _fileServerPortInUse = null;
      _hostedFiles.clear();
      debugPrint("$_logPrefix [$username]: File server stopped.");
    }
  }

  Future<void> _cleanupConnectionState({required bool stopFileServer}) async {
    _isConnected = false;

    await _socketSubscription?.cancel();
    _socketSubscription = null;

    try {
      await _socket?.close();
    } catch (e) {
      debugPrint(
          "$_logPrefix [$username]: Error closing socket (ignoring): $e");
    }
    _socket = null;

    _clientList = [];

    if (stopFileServer) {
      await _stopFileServer();
    }
    // No explicit debugPrint here, caller will log context.
  }

  /// Connects to the P2P host server.
  ///
  /// This will first attempt to start the local file server, then establish
  /// a WebSocket connection to the host.
  /// Throws an exception if connection fails.
  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isManuallyDisconnecting =
        false; // Reset flag for new connection attempt sequence
    _isConnecting = true;

    bool fileServerStarted = await _startFileServer();
    if (!fileServerStarted) {
      _isConnecting = false;
      throw Exception(
          "$_logPrefix [$username]: Failed to start local file server. Cannot connect.");
    }

    int attempts = 0;
    int port = defaultPort;
    WebSocket? tempSocket;
    while (attempts < 10 && tempSocket == null) {
      final url = Uri.parse(
          "ws://$hostIp:$port/connect?id=${Uri.encodeComponent(clientId)}&username=${Uri.encodeComponent(username)}&filePort=$_fileServerPortInUse");
      try {
        debugPrint(
            "$_logPrefix [$username]: Attempting WebSocket connect to $url...");
        tempSocket = await WebSocket.connect(url.toString())
            .timeout(const Duration(seconds: 10));
        tempSocket.pingInterval = const Duration(
            seconds: 5); // Set ping interval to avoid disconnection when idle
        debugPrint("$_logPrefix [$username]: WebSocket connected to $url");
      } on TimeoutException {
        debugPrint(
            "$_logPrefix [$username]: Connection attempt to $url timed out.");
        port++;
        attempts++;
      } on SocketException catch (e) {
        debugPrint(
            "$_logPrefix [$username]: SocketException connecting to $url: ${e.message}. Trying next...");
        port++;
        attempts++;
      } catch (e) {
        debugPrint(
            "$_logPrefix [$username]: Error connecting to $url: $e. Trying next...");
        port++;
        attempts++;
      }
    }

    if (tempSocket == null) {
      _isConnecting = false;
      // File server remains running as per original logic of not stopping on initial connect failure
      throw Exception(
          "$_logPrefix [$username]: Could not connect to WebSocket server at $hostIp on any port in range $defaultPort-${port - 1}.");
    }

    _socket = tempSocket;
    _isConnected = true;
    _connectionRetryAttempts = 0; // Reset retries on successful new connection
    _isConnecting = false; // Mark connection phase as complete

    await _socketSubscription?.cancel();
    _socketSubscription = _socket!.listen(
      (data) async {
        try {
          final message = P2pMessage.fromJsonString(data as String);
          P2pClientInfo? senderInfo = _clientList.firstWhere(
              (c) => c.id == message.senderId,
              orElse: () => P2pClientInfo(
                  id: message.senderId,
                  username: "Unknown (${message.senderId})",
                  isHost: false));

          switch (message.type) {
            case P2pMessageType.clientList:
              _clientList = List<P2pClientInfo>.from(message.clients);
              _clientList.removeWhere((client) =>
                  client.id ==
                  clientId); // Self is included in client list, remove it
              debugPrint(
                  "$_logPrefix [$username]: Updated client list: ${_clientList.map((c) => c.username).toList()}");
              break;
            case P2pMessageType.payload:
              if (message.payload is P2pMessagePayload) {
                final payload = message.payload as P2pMessagePayload;
                debugPrint(
                    "$_logPrefix [$username]: Received payload from ${senderInfo.username}");
                if (payload.files.isNotEmpty) {
                  for (var fileInfo in payload.files) {
                    if (_receivableFiles.containsKey(fileInfo.id)) {
                      debugPrint(
                          "$_logPrefix [$username]: Received duplicate file info for ID ${fileInfo.id}, ignoring.");
                      continue;
                    }
                    _receivableFiles[fileInfo.id] =
                        ReceivableFileInfo(info: fileInfo);
                    debugPrint(
                        "$_logPrefix [$username]: Added receivable file: ${fileInfo.name} (ID: ${fileInfo.id}) from ${senderInfo.username}");
                  }
                }
                if (payload.text.isNotEmpty &&
                    !_receivedTextController.isClosed) {
                  _receivedTextController.add(payload.text);
                }
              } else {
                debugPrint(
                    "$_logPrefix [$username]: Received payload message with incorrect payload type.");
              }
              break;
            case P2pMessageType.fileProgressUpdate:
              if (message.payload is P2pFileProgressUpdate) {
                _handleFileProgressUpdate(
                    message.payload as P2pFileProgressUpdate);
              } else {
                debugPrint(
                    "$_logPrefix [$username]: Received fileProgressUpdate message with incorrect payload type.");
              }
              break;
            case P2pMessageType.unknown:
              debugPrint(
                  "$_logPrefix [$username]: Received unknown message type from ${senderInfo.username}");
              break;
          }
        } catch (e, s) {
          debugPrint(
              "$_logPrefix [$username]: Error parsing server message: $e\nStack: $s\nData: $data");
        }
      },
      onDone: () async {
        debugPrint("$_logPrefix [$username]: WebSocket disconnected (onDone).");
        if (_isManuallyDisconnecting) {
          await _cleanupConnectionState(
              stopFileServer: true); // Manual disconnect stops server
          // _isManuallyDisconnecting is reset by connect() or fully by disconnect() itself
          return;
        }

        bool wasConnected = _isConnected;
        await _cleanupConnectionState(
            stopFileServer: false); // Keep server for retry

        if (wasConnected && _connectionRetryAttempts < _maxConnectionRetries) {
          _connectionRetryAttempts++;
          debugPrint(
              "$_logPrefix [$username]: Attempting to reconnect (attempt $_connectionRetryAttempts/$_maxConnectionRetries)...");
          await Future.delayed(Duration(seconds: 1 + _connectionRetryAttempts));
          try {
            await connect();
          } catch (e) {
            debugPrint(
                "$_logPrefix [$username]: Reconnect attempt $_connectionRetryAttempts failed: $e");
            if (_connectionRetryAttempts >= _maxConnectionRetries) {
              debugPrint(
                  "$_logPrefix [$username]: Max reconnection attempts reached. Giving up. Stopping file server.");
              await _stopFileServer();
            }
          }
        } else {
          if (wasConnected) {
            debugPrint(
                "$_logPrefix [$username]: WebSocket disconnected. Max retries reached or was not supposed to retry. Stopping file server.");
            await _stopFileServer();
          } else if (_connectionRetryAttempts >= _maxConnectionRetries) {
            debugPrint(
                "$_logPrefix [$username]: Max reconnection attempts previously reached. Ensuring file server is stopped if it was started.");
            if (_fileServer != null) await _stopFileServer();
          }
        }
      },
      onError: (error) async {
        debugPrint("$_logPrefix [$username]: WebSocket error: $error");
        if (_isManuallyDisconnecting) {
          await _cleanupConnectionState(stopFileServer: true);
          return;
        }
        bool wasConnected = _isConnected;
        await _cleanupConnectionState(stopFileServer: false);

        if (wasConnected && _connectionRetryAttempts < _maxConnectionRetries) {
          _connectionRetryAttempts++;
          debugPrint(
              "$_logPrefix [$username]: Attempting to reconnect due to error (attempt $_connectionRetryAttempts/$_maxConnectionRetries)...");
          await Future.delayed(Duration(seconds: 1 + _connectionRetryAttempts));
          try {
            await connect();
          } catch (e) {
            debugPrint(
                "$_logPrefix [$username]: Reconnect attempt $_connectionRetryAttempts (due to error) failed: $e");
            if (_connectionRetryAttempts >= _maxConnectionRetries) {
              debugPrint(
                  "$_logPrefix [$username]: Max reconnection attempts reached after error. Giving up. Stopping file server.");
              await _stopFileServer();
            }
          }
        } else {
          if (wasConnected) {
            debugPrint(
                "$_logPrefix [$username]: WebSocket error. Max retries reached or not supposed to retry. Stopping file server.");
            await _stopFileServer();
          } else if (_connectionRetryAttempts >= _maxConnectionRetries) {
            debugPrint(
                "$_logPrefix [$username]: Max reconnection attempts previously reached after error. Ensuring file server is stopped.");
            if (_fileServer != null) await _stopFileServer();
          }
        }
      },
      cancelOnError: true,
    );
    debugPrint(
        '$_logPrefix [$username]: Connection established and listener set up.');
  }

  void _handleFileProgressUpdate(P2pFileProgressUpdate progressUpdate) {
    final fileInfo = _hostedFiles[progressUpdate.fileId];
    if (fileInfo != null) {
      if (fileInfo.receiverIds.contains(progressUpdate.receiverId)) {
        fileInfo.updateProgress(progressUpdate.receiverId,
            progressUpdate.bytesDownloaded, progressUpdate.fileState);
        debugPrint(
            "$_logPrefix [$username]: Progress update for shared file ${fileInfo.info.name} from ${progressUpdate.receiverId}: ${progressUpdate.bytesDownloaded}/${fileInfo.info.size} bytes.");
      } else {
        debugPrint(
            "$_logPrefix [$username]: Received progress update from non-recipient ${progressUpdate.receiverId} for file ${progressUpdate.fileId}");
      }
    } else {
      debugPrint(
          "$_logPrefix [$username]: Received progress update for unknown/unhosted file ID: ${progressUpdate.fileId}");
    }
  }

  /// Shares a file with specified recipients or all other clients in the group.
  ///
  /// The file information is sent to the host, which then relays it to the target recipients.
  /// This client must have its local file server running to serve the file.
  /// [file] is the file to be shared.
  /// [actualSenderIp] is the IP address that other peers should use to download the file from this client.
  /// [recipients] an optional list of clients to share the file with. If null, shares with all other clients known.
  /// Returns [P2pFileInfo] for the shared file, or null if sharing fails (e.g., not connected).
  Future<P2pFileInfo?> shareFile(File file,
      {required String actualSenderIp, List<P2pClientInfo>? recipients}) async {
    if (!isConnected) {
      debugPrint(
          "$_logPrefix [$username]: Cannot share file, not connected to host.");
      return null;
    }
    if (_fileServer == null || _fileServerPortInUse == null) {
      debugPrint(
          "$_logPrefix [$username]: Cannot share file, local file server is not running.");
      return null;
    }
    if (!await file.exists()) {
      debugPrint(
          "$_logPrefix [$username]: Cannot share file, path does not exist: ${file.path}");
      return null;
    }

    final fileStat = await file.stat();
    final fileId = const Uuid().v4();
    final fileName = p.basename(file.path);

    final fileInfo = P2pFileInfo(
      id: fileId,
      name: fileName,
      size: fileStat.size,
      senderId: clientId,
      senderHostIp: actualSenderIp,
      senderPort: _fileServerPortInUse!,
      metadata: {'shared_at': DateTime.now().toIso8601String()},
    );

    final List<P2pClientInfo> targetClients =
        recipients ?? _clientList.where((c) => c.id != clientId).toList();
    final recipientIds = targetClients.map((c) => c.id).toList();

    _hostedFiles[fileId] = HostedFileInfo(
        info: fileInfo, localPath: file.path, recipientIds: recipientIds);
    debugPrint(
        "$_logPrefix [$username]: Hosting file '${fileInfo.name}' (ID: $fileId, IP: $actualSenderIp) for ${recipientIds.length} recipients.");

    final payload = P2pMessagePayload(files: [fileInfo]);
    final message = P2pMessage(
        senderId: clientId,
        type: P2pMessageType.payload,
        payload: payload,
        clients: targetClients);
    bool sent = await send(message);
    return sent ? fileInfo : null;
  }

  /// Downloads a file identified by [fileId] to the [saveDirectory].
  ///
  /// This client will connect to the sender's HTTP server to download the file.
  /// [fileId] is the ID of the file to download.
  /// [saveDirectory] is the directory where the file will be saved.
  /// [customFileName] an optional name for the saved file. If null, uses the original file name.
  /// [deleteOnError] if true (default), deletes partially downloaded file on error.
  /// [onProgress] a callback function to receive [FileDownloadProgressUpdate]s.
  /// [rangeStart] optional start byte for a partial download.
  /// [rangeEnd] optional end byte for a partial download.
  /// Returns true if the download is successful, false otherwise.
  Future<bool> downloadFile(
    String fileId,
    String saveDirectory, {
    String? customFileName,
    bool? deleteOnError = true,
    Function(FileDownloadProgressUpdate)? onProgress,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final receivable = _receivableFiles[fileId];
    if (receivable == null) {
      debugPrint(
          "$_logPrefix [$username]: Cannot download file, ID not found: $fileId");
      return false;
    }

    final fileInfo = receivable.info;
    final url = Uri.parse(
        'http://${hostIp}:${fileInfo.senderPort}/file?id=$fileId&receiverId=$clientId');
    final finalFileName = customFileName ?? fileInfo.name;
    final savePath = p.join(saveDirectory, finalFileName);
    receivable.savePath = savePath;
    receivable.state = ReceivableFileState.downloading;
    debugPrint(
        "$_logPrefix [$username]: Starting download for '${fileInfo.name}' (ID: $fileId) from $url to $savePath");

    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint(
          "$_logPrefix [$username]: Error creating save directory '$saveDirectory': $e");
      receivable.state = ReceivableFileState.error;
      return false;
    }

    final client = http.Client();
    int totalBytes = fileInfo.size;
    int bytesReceived = 0;
    IOSink? fileSink;
    Timer? progressUpdateTimer;

    try {
      final request = http.Request('GET', url);
      bool isRangeRequest = false;
      if (rangeStart != null) {
        String rangeValue = 'bytes=$rangeStart-';
        if (rangeEnd != null) rangeValue += rangeEnd.toString();
        request.headers[HttpHeaders.rangeHeader] = rangeValue;
        isRangeRequest = true;
        bytesReceived = rangeStart;
      }

      final response = await client.send(request);
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        debugPrint(
            "$_logPrefix [$username]: Download failed for $fileId. Server status ${response.statusCode}");
        receivable.state = ReceivableFileState.error;
        return false;
      }

      final contentRange = response.headers[HttpHeaders.contentRangeHeader];
      if (contentRange != null && contentRange.contains('/')) {
        try {
          totalBytes = int.parse(contentRange.split('/').last);
        } catch (e) {
          debugPrint(
              "$_logPrefix [$username]: Could not parse total size from Content-Range: $contentRange");
        }
      }

      final fileMode = (isRangeRequest && rangeStart! > 0)
          ? FileMode.writeOnlyAppend
          : FileMode.writeOnly;
      final file = File(savePath);
      fileSink = file.openWrite(mode: fileMode);
      int lastReportedBytes = bytesReceived;

      void reportProgress() {
        if (totalBytes > 0) {
          double percent =
              max(0.0, min(100.0, (bytesReceived / totalBytes) * 100.0));
          receivable.downloadProgressPercent = percent;
          onProgress?.call(FileDownloadProgressUpdate(
              fileId: fileId,
              progressPercent: percent,
              bytesDownloaded: bytesReceived,
              totalSize: totalBytes,
              savePath: savePath));
          if (bytesReceived > lastReportedBytes) {
            // Report progress to server ~every 5% or on completion
            if ((percent.toInt() % 5 == 0 &&
                    percent.toInt() >
                        (lastReportedBytes / totalBytes * 100).toInt()) ||
                bytesReceived == totalBytes) {
              _sendProgressUpdateToServer(
                  fileId, fileInfo.senderId, bytesReceived, receivable.state);
              lastReportedBytes = bytesReceived;
            }
          }
        }
      }

      progressUpdateTimer = Timer.periodic(
          const Duration(milliseconds: 1000), (_) => reportProgress());

      await for (var chunk in response.stream) {
        fileSink.add(chunk);
        bytesReceived += chunk.length;
      }

      await fileSink.flush();
      await fileSink.close();
      fileSink = null;
      progressUpdateTimer.cancel();
      reportProgress(); // Final report

      if (!isRangeRequest) {
        final savedFileStat = await File(savePath).stat();
        if (savedFileStat.size != totalBytes) {
          debugPrint(
              "$_logPrefix [$username]: Warning: Final file size (${savedFileStat.size}) != expected ($totalBytes) for $fileId");
        }
      }
      receivable.state = ReceivableFileState.completed;
      debugPrint(
          "$_logPrefix [$username]: Download complete for $fileId. Saved to $savePath");
      return true;
    } catch (e, s) {
      debugPrint(
          "$_logPrefix [$username]: Error downloading file $fileId: $e\nStack: $s");
      receivable.state = ReceivableFileState.error;
      if (deleteOnError == true) {
        try {
          await File(savePath).delete();
        } catch (_) {}
      }
      return false;
    } finally {
      progressUpdateTimer?.cancel();
      try {
        await fileSink?.close();
      } catch (_) {}
      client.close();
    }
  }

  Future<void> _sendProgressUpdateToServer(
      String fileId,
      String originalSenderId,
      int bytesDownloaded,
      ReceivableFileState fileState) async {
    if (!isConnected) return;
    final progressPayload = P2pFileProgressUpdate(
      fileId: fileId,
      receiverId: clientId,
      bytesDownloaded: bytesDownloaded,
      fileState: fileState,
    );

    // Find the original sender in the current client list to send the update to.
    // If the original sender is the host, it might not be in the _clientList explicitly if _clientList only contains other clients.
    // However, P2pMessage.clients usually determines recipients, and the host will handle routing.
    // For client-to-client file sharing (if supported through host relay), originalSenderId might be another client.
    P2pClientInfo? targetClient =
        _clientList.firstWhere((c) => c.id == originalSenderId, orElse: () {
      // If not in client list, assume it might be the host or a client not currently known.
      // Create a placeholder. The host (if it's the recipient) will recognize its own ID.
      // This is a simplification; a robust system might require the host's ID explicitly.
      // For now, we assume the message `send` method targets the host, which then routes or processes.
      return P2pClientInfo(
          id: originalSenderId,
          username: "Unknown (Target for Progress)",
          isHost: false); // isHost might be true
    });

    final message = P2pMessage(
        senderId: clientId,
        type: P2pMessageType.fileProgressUpdate,
        payload: progressPayload,
        clients: [
          targetClient
        ]); // Send progress update intended for the original sender
    await send(message);
  }

  /// Sends a [P2pMessage] to the host server.
  ///
  /// [message] is the message to send.
  /// Returns true if the message was sent successfully, false if not connected or error.
  Future<bool> send(P2pMessage message) async {
    if (isConnected && _socket != null) {
      try {
        _socket!.add(message.toJsonString());
        if (message.type != P2pMessageType.fileProgressUpdate) {
          debugPrint(
              "$_logPrefix [$username]: Sent message type '${message.type}' to host.");
        }
        return true;
      } catch (e) {
        debugPrint(
            "$_logPrefix [$username]: Error sending message: $e. Connection may be compromised.");
        // Mark as not connected. The socket's onDone/onError should handle actual cleanup and retries.
        _isConnected = false;
        return false;
      }
    } else {
      debugPrint(
          "$_logPrefix [$username]: Cannot send message, socket not connected.");
      return false;
    }
  }

  /// Disconnects from the P2P host server and stops the local file server.
  Future<void> disconnect() async {
    debugPrint("$_logPrefix [$username]: Disconnecting manually...");
    _isManuallyDisconnecting = true;

    await _cleanupConnectionState(stopFileServer: true);
    _connectionRetryAttempts =
        _maxConnectionRetries; // Ensure no further retries from any lingering async operations

    debugPrint("$_logPrefix [$username]: Manually disconnected.");
    // _isManuallyDisconnecting is reset by connect() if/when it's called next.
  }

  /// Cleans up resources used by the client.
  ///
  /// This includes disconnecting from the host and closing any open streams.
  /// Should be called when the client is no longer needed.
  Future<void> dispose() async {
    debugPrint("$_logPrefix [$username]: Disposing...");
    await disconnect();
    await _receivedTextController.close();
    _receivableFiles.clear();
    debugPrint("$_logPrefix [$username]: Disposed.");
  }
}
