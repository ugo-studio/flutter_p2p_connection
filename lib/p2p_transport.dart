import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // For min

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http; // For client download
import 'package:path/path.dart' as p; // For basename
import 'package:uuid/uuid.dart';

// --- Enums and Basic Info Classes ---

enum P2pMessageType {
  payload,
  clientList,
  fileProgressUpdate,
  unknown,
}

enum ReceivableFileState {
  idle,
  downloading,
  completed,
  error,
}

@immutable
class P2pClientInfo {
  final String id;
  final String username;
  final bool isHost;

  const P2pClientInfo(
      {required this.id, required this.username, required this.isHost});

  factory P2pClientInfo.fromJson(Map<String, dynamic> json) {
    return P2pClientInfo(
      id: json['id'] as String? ?? 'unknown_id',
      username: json['username'] as String? ?? 'Unknown User',
      isHost: json['isHost'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'isHost': isHost,
      };

  @override
  String toString() =>
      'P2pClientInfo(id: $id, username: $username, isHost: $isHost)';
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2pClientInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          username == other.username &&
          isHost == other.isHost;
  @override
  int get hashCode => Object.hash(id, username, isHost);
}

@immutable
class P2pFileInfo {
  final String id;
  final String name;
  final int size;
  final String senderId;
  final String senderHostIp;
  final int senderPort;
  final Map<String, dynamic> metadata;

  const P2pFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.senderId,
    required this.senderHostIp,
    required this.senderPort,
    this.metadata = const {},
  });

  factory P2pFileInfo.fromJson(Map<String, dynamic> json) {
    return P2pFileInfo(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'unknown_file',
      size: json['size'] as int? ?? 0,
      senderId: json['senderId'] as String? ?? 'unknown_sender',
      senderHostIp: json['senderHostIp'] as String? ?? '',
      senderPort: json['senderPort'] as int? ?? 0,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'senderId': senderId,
        'senderHostIp': senderHostIp,
        'senderPort': senderPort,
        'metadata': metadata,
      };

  @override
  String toString() =>
      'P2pFileInfo(id: $id, name: $name, size: $size, sender: $senderId @ $senderHostIp:$senderPort)';
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2pFileInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          size == other.size &&
          senderId == other.senderId &&
          senderHostIp == other.senderHostIp &&
          senderPort == other.senderPort &&
          mapEquals(metadata, other.metadata);
  @override
  int get hashCode =>
      Object.hash(id, name, size, senderId, senderHostIp, senderPort, metadata);
}

@immutable
class P2pMessagePayload {
  final String text;
  final List<P2pFileInfo> files;

  const P2pMessagePayload({this.text = '', this.files = const []});

  factory P2pMessagePayload.fromJson(Map<String, dynamic> json) {
    return P2pMessagePayload(
      text: json['text'] as String? ?? '',
      files: (json['files'] as List<dynamic>? ?? [])
          .map((fileJson) =>
              P2pFileInfo.fromJson(fileJson as Map<String, dynamic>))
          .toList(),
    );
  }

  factory P2pMessagePayload.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pMessagePayload.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pMessagePayload from string: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'files': files.map((f) => f.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() {
    String textSummary =
        text.length > 50 ? '${text.substring(0, 47)}...' : text;
    String filesSummary = files.length > 2
        ? '${files.sublist(0, 2).map((f) => f.name)}... (${files.length} total)'
        : files.map((f) => f.name).toString();
    return 'P2pMessagePayload(text: "$textSummary", files: $filesSummary)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2pMessagePayload &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          listEquals(files, other.files);
  @override
  int get hashCode => Object.hash(text, Object.hashAll(files));
}

@immutable
class P2pFileProgressUpdate {
  final String fileId;
  final String receiverId;
  final int bytesDownloaded;

  const P2pFileProgressUpdate({
    required this.fileId,
    required this.receiverId,
    required this.bytesDownloaded,
  });

  factory P2pFileProgressUpdate.fromJson(Map<String, dynamic> json) {
    return P2pFileProgressUpdate(
      fileId: json['fileId'] as String? ?? '',
      receiverId: json['receiverId'] as String? ?? '',
      bytesDownloaded: json['bytesDownloaded'] as int? ?? 0,
    );
  }

  factory P2pFileProgressUpdate.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pFileProgressUpdate.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pFileProgressUpdate from string: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'receiverId': receiverId,
        'bytesDownloaded': bytesDownloaded,
      };

  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() =>
      'P2pFileProgressUpdate(fileId: $fileId, receiver: $receiverId, bytes: $bytesDownloaded)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2pFileProgressUpdate &&
          runtimeType == other.runtimeType &&
          fileId == other.fileId &&
          receiverId == other.receiverId &&
          bytesDownloaded == other.bytesDownloaded;
  @override
  int get hashCode => Object.hash(fileId, receiverId, bytesDownloaded);
}

@immutable
class P2pMessage {
  final String senderId;
  final P2pMessageType type;
  final dynamic payload;
  final List<P2pClientInfo> clients;

  const P2pMessage({
    required this.senderId,
    required this.type,
    this.payload,
    this.clients = const [],
  });

  factory P2pMessage.fromJson(Map<String, dynamic> json) {
    final type = P2pMessageType.values.firstWhere((e) => e.name == json['type'],
        orElse: () => P2pMessageType.unknown);
    dynamic payloadData;
    if (json['payload'] != null) {
      if (type == P2pMessageType.payload) {
        payloadData =
            P2pMessagePayload.fromJson(json['payload'] as Map<String, dynamic>);
      } else if (type == P2pMessageType.fileProgressUpdate) {
        payloadData = P2pFileProgressUpdate.fromJson(
            json['payload'] as Map<String, dynamic>);
      }
    }

    return P2pMessage(
      senderId: json['senderId'] as String? ?? 'unknown',
      type: type,
      payload: payloadData,
      clients: (json['clients'] as List<dynamic>? ?? [])
          .map((clientJson) =>
              P2pClientInfo.fromJson(clientJson as Map<String, dynamic>))
          .toList(),
    );
  }

  factory P2pMessage.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pMessage.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pMessage from string: $e");
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'type': type.name,
        'payload': switch (payload) {
          P2pMessagePayload p => p.toJson(),
          P2pFileProgressUpdate p => p.toJson(),
          _ => null,
        },
        'clients': clients.map((c) => c.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() {
    String clientsSummary = clients.length > 3
        ? '${clients.sublist(0, 3).map((c) => c.username)}... (${clients.length} total)'
        : clients.map((c) => c.username).toString();
    return 'P2pMessage(senderId: $senderId, type: $type, payload: $payload, clients: $clientsSummary)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2pMessage &&
          runtimeType == other.runtimeType &&
          senderId == other.senderId &&
          type == other.type &&
          payload == other.payload &&
          listEquals(clients, other.clients);
  @override
  int get hashCode =>
      Object.hash(senderId, type, payload, Object.hashAll(clients));
}

class HostedFileInfo {
  final P2pFileInfo info;
  final String localPath;
  final Map<String, int> _downloadProgressBytes;

  List<String> get receiverIds => _downloadProgressBytes.keys.toList();

  HostedFileInfo({
    required this.info,
    required this.localPath,
    required List<String> recipientIds,
  }) : _downloadProgressBytes = {for (var id in recipientIds) id: 0};

  double getProgressPercent(String receiverId) {
    final bytes = _downloadProgressBytes[receiverId];
    if (info.size == 0 || bytes == null) return 0.0;
    return (bytes / info.size) * 100.0;
  }

  void updateProgress(String receiverId, int bytes) {
    final currentBytes = _downloadProgressBytes[receiverId] ?? 0;
    if (bytes > currentBytes) {
      _downloadProgressBytes[receiverId] = bytes;
    }
  }
}

class ReceivableFileInfo {
  final P2pFileInfo info;
  ReceivableFileState state;
  double downloadProgressPercent;
  String? savePath;

  ReceivableFileInfo({
    required this.info,
    this.state = ReceivableFileState.idle,
    this.downloadProgressPercent = 0.0,
    this.savePath,
  });
}

class FileDownloadProgressUpdate {
  final String fileId;
  final double progressPercent;
  final int bytesDownloaded;
  final int totalSize;
  final String savePath;

  FileDownloadProgressUpdate({
    required this.fileId,
    required this.progressPercent,
    required this.bytesDownloaded,
    required this.totalSize,
    required this.savePath,
  });

  @override
  String toString() =>
      'FileDownloadProgressUpdate(fileId: $fileId, progress: ${progressPercent.toStringAsFixed(1)}%, path: $savePath)';
}

mixin FileRequestServerMixin {
  Map<String, HostedFileInfo> get hostedFiles;
  String get transportUsername; // For logging prefix
  static const String _logPrefixBase = "P2P FileServer";

  Future<void> handleFileRequest(HttpRequest request) async {
    final logPrefix = "$_logPrefixBase [$transportUsername]";
    final fileId = request.uri.queryParameters['id'];

    if (fileId == null || fileId.isEmpty) {
      debugPrint("$logPrefix: File request missing ID.");
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('File ID parameter is required.')
        ..close();
      return;
    }

    final hostedFile = hostedFiles[fileId];
    if (hostedFile == null) {
      debugPrint(
          "$logPrefix: Requested file ID not found or not hosted: $fileId");
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found or access denied.')
        ..close();
      return;
    }

    final filePath = hostedFile.localPath;
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint(
          "$logPrefix: Hosted file path not found on disk: $filePath (ID: $fileId)");
      hostedFiles.remove(fileId);
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('File data is unavailable.')
        ..close();
      return;
    }

    final fileStat = await file.stat();
    final totalSize = fileStat.size;
    final response = request.response;

    response.headers.contentType = ContentType.binary;
    response.headers.add(HttpHeaders.contentDisposition,
        'attachment; filename="${Uri.encodeComponent(hostedFile.info.name)}"');
    response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int rangeStart = 0;
    int? rangeEnd;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final rangeValues = rangeHeader.substring(6).split('-');
        rangeStart = int.parse(rangeValues[0]);
        if (rangeValues[1].isNotEmpty) {
          rangeEnd = int.parse(rangeValues[1]);
        }

        if (rangeStart < 0 ||
            rangeStart >= totalSize ||
            (rangeEnd != null &&
                (rangeEnd < rangeStart || rangeEnd >= totalSize))) {
          throw const FormatException('Invalid range');
        }
        rangeEnd ??= totalSize - 1;
        final rangeLength = (rangeEnd - rangeStart) + 1;

        debugPrint(
            "$logPrefix: Serving range $rangeStart-$rangeEnd (length $rangeLength) for file $fileId");
        response.statusCode = HttpStatus.partialContent;
        response.headers.contentLength = rangeLength;
        response.headers.add(HttpHeaders.contentRangeHeader,
            'bytes $rangeStart-$rangeEnd/$totalSize');
        final stream = file.openRead(rangeStart, rangeEnd + 1);
        await response.addStream(stream);
      } catch (e) {
        debugPrint("$logPrefix: Invalid Range header '$rangeHeader': $e");
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.add(HttpHeaders.contentRangeHeader, 'bytes */$totalSize')
          ..write('Invalid byte range requested.')
          ..close();
        return;
      }
    } else {
      debugPrint(
          "$logPrefix: Serving full file $fileId (${hostedFile.info.name})");
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = totalSize;
      final stream = file.openRead();
      await response.addStream(stream);
    }

    try {
      await response.close();
      debugPrint("$logPrefix: Finished sending file/range for $fileId.");
    } catch (e) {
      debugPrint("$logPrefix: Error closing response stream for $fileId: $e");
    }
  }
}

class P2pTransportHost with FileRequestServerMixin {
  final int defaultPort;
  final String username;
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

  Stream<String> get receivedTextStream => _receivedTextController.stream;
  int? get portInUse => _portInUse;
  List<P2pClientInfo> get clientList =>
      _clients.values.map((cl) => cl.info).toList();
  List<HostedFileInfo> get hostedFileInfos => _hostedFiles.values.toList();
  List<ReceivableFileInfo> get receivableFileInfos =>
      _receivableFiles.values.toList();

  P2pTransportHost({required this.defaultPort, required this.username});

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
            _sendProgressUpdateToServer(
                fileId, fileInfo.senderId, bytesReceived);
            lastReportedBytes = bytesReceived;
          }
        }
      }

      progressUpdateTimer = Timer.periodic(
          const Duration(milliseconds: 500), (_) => reportProgress());

      await for (var chunk in response.stream) {
        fileSink.add(chunk);
        bytesReceived += chunk.length;
        // reportProgress();
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

class P2pTransportClient with FileRequestServerMixin {
  final String hostIp;
  final int defaultPort;
  final int defaultFilePort;
  final String username;
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

  @override
  Map<String, HostedFileInfo> get hostedFiles => _hostedFiles;
  @override
  String get transportUsername => username;

  bool get isConnected => _isConnected && _socket?.readyState == WebSocket.open;
  List<P2pClientInfo> get clientList => _clientList;
  int? get fileServerPort => _fileServerPortInUse;
  List<HostedFileInfo> get hostedFileInfos => _hostedFiles.values.toList();
  List<ReceivableFileInfo> get receivableFileInfos =>
      _receivableFiles.values.toList();
  Stream<String> get receivedTextStream => _receivedTextController.stream;

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
        _fileServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
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

  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
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
            .timeout(const Duration(seconds: 10)); // Increased timeout
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
    _isConnecting = false;

    if (tempSocket == null) {
      await _stopFileServer();
      throw Exception(
          "$_logPrefix [$username]: Could not connect to WebSocket server at $hostIp on any port in range $defaultPort-${port - 1}.");
    }

    _socket = tempSocket;
    _isConnected = true;
    await _socketSubscription?.cancel();
    _socketSubscription = _socket!.listen(
      (data) async {
        try {
          final message = P2pMessage.fromJsonString(data as String);
          P2pClientInfo? senderInfo = _clientList.firstWhere(
              (c) => c.id == message.senderId,
              orElse: () => P2pClientInfo(
                  id: message.senderId,
                  username: 'Unknown Sender',
                  isHost: message.senderId == 'server'));

          switch (message.type) {
            case P2pMessageType.clientList:
              _clientList = List<P2pClientInfo>.from(message.clients);
              _clientList.removeWhere((client) =>
                  client.id == clientId); // Host sends full list, remove self
              debugPrint(
                  "$_logPrefix [$username]: Updated client list: ${_clientList.map((c) => c.username).toList()}");
              break;
            case P2pMessageType.payload:
              if (message.payload is P2pMessagePayload) {
                final payload = message.payload as P2pMessagePayload;
                debugPrint(
                    "$_logPrefix [$username]: Received payload from ${senderInfo.username} (${senderInfo.id})");
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
      onDone: () {
        debugPrint(
            "$_logPrefix [$username]: WebSocket disconnected from server.");
        _handleDisconnect();
      },
      onError: (error) {
        debugPrint("$_logPrefix [$username]: WebSocket error: $error");
        _handleDisconnect();
      },
      cancelOnError: true,
    );
    debugPrint(
        '$_logPrefix [$username]: Connection established and listener set up.');
  }

  Future<void> _handleDisconnect() async {
    _isConnected = false;
    _socket = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _clientList = [];
    await _stopFileServer();
    // _receivableFiles.clear(); // Optional: clear pending/received files on disconnect
    debugPrint("$_logPrefix [$username]: Cleaned up after disconnect.");
  }

  void _handleFileProgressUpdate(P2pFileProgressUpdate progressUpdate) {
    final fileInfo = _hostedFiles[progressUpdate.fileId];
    if (fileInfo != null) {
      if (fileInfo.receiverIds.contains(progressUpdate.receiverId)) {
        fileInfo.updateProgress(
            progressUpdate.receiverId, progressUpdate.bytesDownloaded);
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
      senderHostIp: actualSenderIp, // Use provided client's IP in group
      senderPort: _fileServerPortInUse!,
      metadata: {'shared_at': DateTime.now().toIso8601String()},
    );

    final List<P2pClientInfo> targetClients = recipients ??
        _clientList
            .where((c) => c.id != clientId)
            .toList(); // Send to all *others* by default
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
        'http://${fileInfo.senderHostIp}:${fileInfo.senderPort}/file?id=$fileId&receiverId=$clientId');
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
            // Send progress less frequently or based on significant change
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
        // Reporting progress inside the loop can be very frequent.
        // Consider moving it to the timer or only reporting on larger byte changes.
        // For now, keeping it, but the timer also calls it.
        // reportProgress();
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
      String fileId, String originalSenderId, int bytesDownloaded) async {
    if (!isConnected) return;
    final progressPayload = P2pFileProgressUpdate(
        fileId: fileId, receiverId: clientId, bytesDownloaded: bytesDownloaded);
    // Target only the original sender
    final P2pClientInfo? targetSender =
        _clientList.where((c) => c.id == originalSenderId).firstOrNull;
    if (targetSender == null) return;

    final message = P2pMessage(
        senderId: clientId,
        type: P2pMessageType.fileProgressUpdate,
        payload: progressPayload,
        clients: [targetSender]);
    await send(message);
  }

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
        debugPrint("$_logPrefix [$username]: Error sending message: $e");
        await _handleDisconnect();
        return false;
      }
    } else {
      debugPrint(
          "$_logPrefix [$username]: Cannot send message, socket not connected.");
      return false;
    }
  }

  Future<void> disconnect() async {
    debugPrint("$_logPrefix [$username]: Disconnecting...");
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close().catchError((_) {});
    await _handleDisconnect();
    debugPrint("$_logPrefix [$username]: Disconnected.");
  }

  Future<void> dispose() async {
    debugPrint("$_logPrefix [$username]: Disposing...");
    await disconnect();
    await _receivedTextController.close();
    _receivableFiles.clear();
    debugPrint("$_logPrefix [$username]: Disposed.");
  }
}
