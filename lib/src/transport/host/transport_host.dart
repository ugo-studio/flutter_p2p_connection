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

/// Manages the P2P host server, handling client connections and message broadcasting.
///
/// The host listens for incoming WebSocket connections from clients and facilitates
/// message exchange and file sharing within the P2P group. It also serves files
/// requested by clients.
class P2pTransportHost with FileRequestServerMixin {
  /// The default port to attempt to bind the server to.
  final int defaultPort;

  /// The username of the host.
  final String username;

  /// Unique ID for this host instance.
  final String hostId = const Uuid().v4();
  HttpServer? _server;
  int? _portInUse;
  final Map<String, ({WebSocket socket, P2pClientInfo info})> _clients = {};
  final Map<String, HostedFileInfo> _hostedFiles = {};
  final Map<String, ReceivableFileInfo> _receivableFiles = {};
  final StreamController<String> _receivedTextController =
      StreamController<String>.broadcast();

  static const String _logPrefix = "P2P Transport Host";

  @override
  Map<String, HostedFileInfo> get hostedFiles => _hostedFiles;
  @override
  String get transportUsername => username;

  /// A stream of received text messages from clients.
  Stream<String> get receivedTextStream => _receivedTextController.stream;

  /// The actual port the server is listening on, or null if not started.
  int? get portInUse => _portInUse;

  /// A list of currently connected clients.
  List<P2pClientInfo> get clientList =>
      _clients.values.map((cl) => cl.info).toList();

  /// A list of files currently being hosted by this server.
  List<HostedFileInfo> get hostedFileInfos => _hostedFiles.values.toList();

  /// A list of files that this host has been informed about and can download.
  List<ReceivableFileInfo> get receivableFileInfos =>
      _receivableFiles.values.toList();

  /// Creates a [P2pTransportHost] instance.
  ///
  /// [defaultPort] is the initial port to try for the server. If occupied, it will try subsequent ports.
  /// [username] is the display name for this host.
  P2pTransportHost({required this.defaultPort, required this.username});

  /// Starts the P2P host server.
  ///
  /// Tries to bind to [defaultPort] and subsequent ports if necessary.
  /// Throws an exception if a port cannot be bound after several attempts.
  Future<void> start() async {
    if (_server != null) return;
    int attempts = 0;
    int port = defaultPort;
    while (attempts < 10) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _portInUse = port;
        debugPrint(
            "$_logPrefix [$username]: Server started on port $_portInUse");
        break;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 ||
            e.osError?.errorCode == 48 ||
            e.message.contains('errno = 98') ||
            e.message.contains('errno = 48')) {
          debugPrint(
              "$_logPrefix [$username]: Port $port in use, trying next...");
          port++;
          attempts++;
        } else {
          debugPrint("$_logPrefix [$username]: Error binding server: $e");
          rethrow;
        }
      } catch (e) {
        debugPrint(
            "$_logPrefix [$username]: Unexpected error starting server: $e");
        rethrow;
      }
    }
    if (_server == null) {
      throw Exception(
          "$_logPrefix [$username]: Could not bind to any port in the range $defaultPort-${port - 1}.");
    }

    _server!.listen(
      (HttpRequest request) async {
        final path = request.requestedUri.path;
        debugPrint("$_logPrefix [$username]: Received request for $path");
        if (path == '/connect' &&
            WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            WebSocket websocket = await WebSocketTransformer.upgrade(request);
            _handleClientConnect(websocket, request);
          } catch (e) {
            debugPrint(
                "$_logPrefix [$username]: Error upgrading WebSocket: $e");
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('WebSocket upgrade failed.');
            await request.response.close();
          }
        } else if (path == '/file') {
          await handleFileRequest(request);
        } else {
          debugPrint(
              "$_logPrefix [$username]: Invalid request type for ${request.uri}");
          request.response
            ..statusCode = HttpStatus.notFound
            ..write("Resource not found.")
            ..close();
        }
      },
      onError: (error) {
        debugPrint("$_logPrefix [$username]: Server listen error: $error");
      },
      onDone: () {
        debugPrint("$_logPrefix [$username]: Server stopped listening.");
        _portInUse = null;
      },
    );
  }

  void _handleClientConnect(WebSocket client, HttpRequest request) {
    final clientId =
        request.uri.queryParameters['id'] ?? client.hashCode.toString();
    final clientUsername =
        request.uri.queryParameters['username'] ?? 'User_$clientId';
    final clientInfo =
        P2pClientInfo(id: clientId, username: clientUsername, isHost: false);
    _clients[clientId] = (socket: client, info: clientInfo);
    _broadcastClientListUpdate();

    client.listen(
      (data) {
        try {
          final message = P2pMessage.fromJsonString(data as String);
          switch (message.type) {
            case P2pMessageType.payload:
              if (message.payload is P2pMessagePayload) {
                final payload = message.payload as P2pMessagePayload;
                bool hostIsRecipient =
                    message.clients.any((c) => c.id == hostId);
                if (hostIsRecipient) {
                  if (payload.files.isNotEmpty) {
                    for (var fileInfo in payload.files) {
                      if (_receivableFiles.containsKey(fileInfo.id)) {
                        debugPrint(
                            "$_logPrefix [$username]: Received duplicate file info for ID ${fileInfo.id} from ${clientInfo.username}, ignoring.");
                        continue;
                      }
                      _receivableFiles[fileInfo.id] =
                          ReceivableFileInfo(info: fileInfo);
                      debugPrint(
                          "$_logPrefix [$username]: Added receivable file: ${fileInfo.name} (ID: ${fileInfo.id}) from ${clientInfo.username}");
                    }
                  }
                  if (payload.text.isNotEmpty &&
                      !_receivedTextController.isClosed) {
                    _receivedTextController.add(payload.text);
                  }
                }
                final recipientClientIds = message.clients
                    .where((c) => c.id != hostId)
                    .map((c) => c.id)
                    .toList();
                if (recipientClientIds.isNotEmpty) {
                  broadcast(message, includeClientIds: recipientClientIds);
                }
                debugPrint(
                    "$_logPrefix [$username]: Received payload from ${clientInfo.username} ($clientId) targeting ${message.clients.length} recipients.");
              } else {
                debugPrint(
                    "$_logPrefix [$username]: Received payload message with incorrect payload type from $clientId");
              }
              break;
            case P2pMessageType.fileProgressUpdate:
              if (message.payload is P2pFileProgressUpdate) {
                bool hostIsRecipient =
                    message.clients.any((c) => c.id == hostId);
                if (hostIsRecipient) {
                  _handleFileProgressUpdate(
                      message.payload as P2pFileProgressUpdate);
                }
                final recipientClientIds = message.clients
                    .where((c) => c.id != hostId)
                    .map((c) => c.id)
                    .toList();
                if (recipientClientIds.isNotEmpty) {
                  broadcast(message, includeClientIds: recipientClientIds);
                }
              } else {
                debugPrint(
                    "$_logPrefix [$username]: Received fileProgressUpdate message with incorrect payload type from $clientId");
              }
              break;
            case P2pMessageType.clientList:
              debugPrint(
                  "$_logPrefix [$username]: Received unexpected clientList message from $clientId");
              break;
            case P2pMessageType.unknown:
              debugPrint(
                  "$_logPrefix [$username]: Received unknown message type from $clientId");
              break;
          }
        } catch (e, s) {
          debugPrint(
              "$_logPrefix [$username]: Error parsing message from ${clientInfo.username} ($clientId): $e\nStack: $s\nData: $data");
        }
      },
      onDone: () {
        debugPrint(
            "$_logPrefix [$username]: Client disconnected: ${clientInfo.username} ($clientId)");
        _clients.remove(clientId);
        _broadcastClientListUpdate();
      },
      onError: (error) {
        debugPrint(
            "$_logPrefix [$username]: Error on client socket ${clientInfo.username} ($clientId): $error");
        _clients.remove(clientId);
        _broadcastClientListUpdate();
        client.close().catchError((_) {});
      },
      cancelOnError: true,
    );
  }

  void _handleFileProgressUpdate(P2pFileProgressUpdate progressUpdate) {
    final fileInfo = _hostedFiles[progressUpdate.fileId];
    if (fileInfo != null) {
      if (fileInfo.receiverIds.contains(progressUpdate.receiverId)) {
        fileInfo.updateProgress(
            progressUpdate.receiverId, progressUpdate.bytesDownloaded);
        debugPrint(
            "$_logPrefix [$username]: Progress update for ${fileInfo.info.name} from ${progressUpdate.receiverId}: ${progressUpdate.bytesDownloaded}/${fileInfo.info.size} bytes.");
      } else {
        debugPrint(
            "$_logPrefix [$username]: Received progress update from non-recipient ${progressUpdate.receiverId} for file ${progressUpdate.fileId}");
      }
    } else {
      debugPrint(
          "$_logPrefix [$username]: Received progress update for unknown/unhosted file ID: ${progressUpdate.fileId}");
    }
  }

  void _broadcastClientListUpdate() {
    final hostInfo =
        P2pClientInfo(id: hostId, username: username, isHost: true);
    final clientListInfo = _clients.values.map((c) => c.info).toList();
    final fullListWithHost = [hostInfo, ...clientListInfo];
    broadcast(P2pMessage(
      senderId: hostId,
      type: P2pMessageType.clientList,
      clients: fullListWithHost,
      payload: null,
    ));
    debugPrint(
        "$_logPrefix [$username]: Broadcasting client list update: ${fullListWithHost.map((c) => c.username).toList()}");
  }

  /// Shares a file with specified recipients or all connected clients.
  ///
  /// [file] is the file to be shared.
  /// [actualSenderIp] is the IP address that clients should use to download the file. This is typically the host's LAN IP.
  /// [recipients] is an optional list of clients to share the file with. If null, shares with all connected clients.
  /// Returns [P2pFileInfo] for the shared file, or null if sharing fails.
  Future<P2pFileInfo?> shareFile(File file,
      {required String actualSenderIp, List<P2pClientInfo>? recipients}) async {
    if (_server == null || _portInUse == null) {
      debugPrint(
          "$_logPrefix [$username]: Cannot share file, server not running.");
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
      senderId: hostId,
      senderHostIp: actualSenderIp, // Use provided IP
      senderPort: _portInUse!,
      metadata: {'shared_at': DateTime.now().toIso8601String()},
    );

    final targetClients =
        recipients ?? _clients.values.map((c) => c.info).toList();
    final recipientIds = targetClients.map((c) => c.id).toList();

    _hostedFiles[fileId] = HostedFileInfo(
        info: fileInfo, localPath: file.path, recipientIds: recipientIds);
    debugPrint(
        "$_logPrefix [$username]: Hosting file '${fileInfo.name}' (ID: $fileId, IP: $actualSenderIp) for ${recipientIds.length} recipients.");

    final payload = P2pMessagePayload(files: [fileInfo]);
    final message = P2pMessage(
        senderId: hostId,
        type: P2pMessageType.payload,
        payload: payload,
        clients: targetClients);
    await broadcast(message, includeClientIds: recipientIds);
    return fileInfo;
  }

  /// Downloads a file identified by [fileId] to the [saveDirectory].
  ///
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
    bool? deleteOnError = true, // Default to true
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
        'http://${fileInfo.senderHostIp}:${fileInfo.senderPort}/file?id=$fileId&receiverId=$hostId');
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
        // final body = await response.stream.bytesToString(); // Avoid reading large error bodies
        // debugPrint("$_logPrefix [$username]: Server error body: $body");
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
                  fileId, fileInfo.senderId, bytesReceived);
              lastReportedBytes = bytesReceived;
            }
          }
        }
      }

      progressUpdateTimer = Timer.periodic(
          const Duration(milliseconds: 500), (_) => reportProgress());

      await for (var chunk in response.stream) {
        fileSink.add(chunk);
        bytesReceived += chunk.length;
        // reportProgress(); // Reporting in timer is often smoother
      }

      await fileSink.flush();
      await fileSink.close();
      fileSink = null; // Mark as closed
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
      String fileId, String originalSenderId, int bytesDownloaded) async {
    final progressPayload = P2pFileProgressUpdate(
        fileId: fileId, receiverId: hostId, bytesDownloaded: bytesDownloaded);
    final message = P2pMessage(
        senderId: hostId,
        type: P2pMessageType.fileProgressUpdate,
        payload: progressPayload,
        clients: [
          P2pClientInfo(
              id: originalSenderId, username: "unknown", isHost: false)
        ]); // Only need ID for target
    await sendToClient(originalSenderId, message);
  }

  /// Broadcasts a [P2pMessage] to connected clients.
  ///
  /// [message] is the message to broadcast.
  /// [excludeClientIds] an optional list of client IDs to exclude from the broadcast.
  /// [includeClientIds] an optional list of client IDs to include in the broadcast (sends only to these).
  /// Cannot specify both [excludeClientIds] and [includeClientIds].
  Future<void> broadcast(P2pMessage message,
      {List<String>? excludeClientIds, List<String>? includeClientIds}) async {
    if (_server == null) return;
    if (excludeClientIds != null && includeClientIds != null) {
      debugPrint(
          "$_logPrefix [$username]: Cannot specify both include and exclude client IDs.");
      return;
    }
    final msgString = message.toJsonString();
    int sentCount = 0;
    _clients.forEach((clientId, clientData) {
      bool shouldSend =
          (excludeClientIds == null || !excludeClientIds.contains(clientId)) &&
              (includeClientIds == null || includeClientIds.contains(clientId));
      if (shouldSend && clientData.socket.readyState == WebSocket.open) {
        try {
          clientData.socket.add(msgString);
          sentCount++;
        } catch (e) {
          debugPrint(
              "$_logPrefix [$username]: Error sending broadcast to ${clientData.info.username} ($clientId): $e");
        }
      }
    });
    if (sentCount > 0 && message.type != P2pMessageType.fileProgressUpdate) {
      // Avoid spamming for progress
      debugPrint(
          "$_logPrefix [$username]: Sent message type '${message.type}' to $sentCount clients.");
    }
  }

  /// Sends a [P2pMessage] to a specific client.
  ///
  /// [clientId] is the ID of the target client.
  /// [message] is the message to send.
  /// Returns true if the message was sent successfully, false otherwise.
  Future<bool> sendToClient(String clientId, P2pMessage message) async {
    if (_server == null) return false;
    final clientData = _clients[clientId];
    if (clientData != null && clientData.socket.readyState == WebSocket.open) {
      try {
        clientData.socket.add(message.toJsonString());
        if (message.type != P2pMessageType.fileProgressUpdate) {
          debugPrint(
              "$_logPrefix [$username]: Sent message type '${message.type}' to ${clientData.info.username} ($clientId).");
        }
        return true;
      } catch (e) {
        debugPrint(
            "$_logPrefix [$username]: Error sending direct message to ${clientData.info.username} ($clientId): $e");
        return false;
      }
    }
    return false;
  }

  /// Stops the P2P host server and disconnects all clients.
  Future<void> stop() async {
    debugPrint("$_logPrefix [$username]: Stopping server...");
    await _receivedTextController.close();
    for (var clientData in _clients.values) {
      await clientData.socket.close().catchError((_) {});
    }
    _clients.clear();
    _hostedFiles.clear();
    _receivableFiles.clear();
    await _server?.close(force: true);
    _server = null;
    _portInUse = null;
    debugPrint("$_logPrefix [$username]: Server stopped.");
  }
}
