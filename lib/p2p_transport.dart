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
  payload, // General data, now includes file info
  clientList,
  fileProgressUpdate, // New type for reporting download progress
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

// --- File Information Class ---
@immutable
class P2pFileInfo {
  final String id; // Unique ID for this file transfer instance
  final String name; // Original filename
  final int size; // File size in bytes
  final String senderId; // ID of the client/host initiating the share
  final String senderHostIp; // IP address of the device serving the file
  final int senderPort; // Port of the HTTP server serving the file
  final Map<String, dynamic> metadata; // For future use (e.g., checksum)

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
      id: json['id'] as String? ?? const Uuid().v4(), // Should not be null
      name: json['name'] as String? ?? 'unknown_file',
      size: json['size'] as int? ?? 0,
      senderId: json['senderId'] as String? ?? 'unknown_sender',
      senderHostIp: json['senderHostIp'] as String? ?? '',
      senderPort: json['senderPort'] as int? ?? 0,
      metadata: Map<String, dynamic>.from(
          json['metadata'] as Map? ?? {}), // Ensure it's a map
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
          mapEquals(metadata, other.metadata); // Use mapEquals for metadata
  @override
  int get hashCode =>
      Object.hash(id, name, size, senderId, senderHostIp, senderPort, metadata);
}

// --- Payload now carries P2pFileInfo ---
@immutable
class P2pMessagePayload {
  final String text; // Optional text message
  final List<P2pFileInfo> files; // List of files being shared in this message

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

// --- File Progress Update Payload ---
@immutable
class P2pFileProgressUpdate {
  final String fileId; // Which file is being updated
  final String receiverId; // Who is downloading
  final int bytesDownloaded; // How many bytes they have downloaded so far

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

// --- P2pMessage now handles different payload types ---
@immutable
class P2pMessage {
  final String senderId;
  final P2pMessageType type;
  final dynamic
      payload; // Can be P2pMessagePayload or P2pFileProgressUpdate or null
  final List<P2pClientInfo> clients; // Target recipients for payload messages

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
      // Add other types here if needed
    }

    return P2pMessage(
      senderId: json['senderId'] as String? ?? 'unknown',
      type: type,
      payload: payloadData, // Deserialize based on type
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
          // Use pattern matching for serialization
          P2pMessagePayload p => p.toJson(),
          P2pFileProgressUpdate p => p.toJson(),
          _ => null, // Handle null or other types
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
          payload == other.payload && // Assumes payload types have ==
          listEquals(clients, other.clients);
  @override
  int get hashCode =>
      Object.hash(senderId, type, payload, Object.hashAll(clients));
}

// --- Helper Class: To track sent file state ---
class HostedFileInfo {
  final P2pFileInfo info;
  final String localPath;
  // Map: Receiver ID -> bytes downloaded
  final Map<String, int> downloadProgressBytes;

  HostedFileInfo({
    required this.info,
    required this.localPath,
    required List<String> recipientIds,
  }) : downloadProgressBytes = {
          for (var id in recipientIds) id: 0
        }; // Initialize progress for all recipients

  // Calculate percentage for a specific receiver
  double getProgressPercent(String receiverId) {
    final bytes = downloadProgressBytes[receiverId];
    if (info.size == 0 || bytes == null) return 0.0;
    return (bytes / info.size) * 100.0;
  }

  // Update progress and return true if changed significantly
  void updateProgress(String receiverId, int bytes) {
    final currentBytes = downloadProgressBytes[receiverId] ?? 0;
    // Only update if it's forward progress
    if (bytes > currentBytes) {
      downloadProgressBytes[receiverId] = bytes;
    }
  }
}

// --- Helper Class: To track received file state ---
class ReceivableFileInfo {
  final P2pFileInfo info;
  ReceivableFileState state;
  double downloadProgressPercent; // Percentage 0-100
  String? savePath; // Where the file is being/was saved

  ReceivableFileInfo({
    required this.info,
    this.state = ReceivableFileState.idle,
    this.downloadProgressPercent = 0.0,
    this.savePath,
  });
}

// --- New Event Class for Sender Progress Updates ---
class FileShareProgressUpdate {
  final String fileId;
  final String receiverId;
  final double progressPercent; // 0-100
  final int bytesDownloaded;
  final int totalSize;

  FileShareProgressUpdate({
    required this.fileId,
    required this.receiverId,
    required this.progressPercent,
    required this.bytesDownloaded,
    required this.totalSize,
  });

  @override
  String toString() =>
      'FileShareProgressUpdate(fileId: $fileId, receiver: $receiverId, progress: ${progressPercent.toStringAsFixed(1)}%)';
}

// --- New Event Class for Receiver Progress Updates ---
class FileDownloadProgressUpdate {
  final String fileId;
  final double progressPercent; // 0-100
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

// --- P2pTransportHost ---
class P2pTransportHost {
  final int defaultPort;
  final String username;
  final String hostId = const Uuid().v4();
  HttpServer? _server;
  int? _portInUse;
  final Map<String, ({WebSocket socket, P2pClientInfo info})> _clients = {};

  // Map: File ID -> HostedFileInfo
  final Map<String, HostedFileInfo> _hostedFiles = {};
  // Map: File ID -> ReceivableFileInfo
  final Map<String, ReceivableFileInfo> _receivableFiles = {};

  final StreamController<P2pMessagePayload> _receivedPayloadsController =
      StreamController<P2pMessagePayload>.broadcast();

  Stream<P2pMessagePayload> get receivedPayloadsStream =>
      _receivedPayloadsController.stream;

  int? get portInUse => _portInUse;
  List<P2pClientInfo> get clientList =>
      _clients.values.map((cl) => cl.info).toList();
  // Expose hosted file infos (read-only)
  List<HostedFileInfo> get hostedFileInfos => _hostedFiles.values.toList();
  // Expose receivable file infos (read-only)
  List<ReceivableFileInfo> get receivableFileInfos =>
      _receivableFiles.values.toList();

  P2pTransportHost({required this.defaultPort, required this.username});

  Future<void> start() async {
    if (_server != null) return;
    int attempts = 0;
    int port = defaultPort;
    while (attempts < 10) {
      try {
        // // Determine a reliable host IP (might need platform-specific logic for robust discovery)
        // // Using anyIPv4 for binding, but need a specific IP for P2pFileInfo
        // final interfaces = await NetworkInterface.list(
        //     includeLoopback: false, type: InternetAddressType.IPv4);
        // final hostIp = interfaces.isNotEmpty
        //     ? interfaces.first.addresses.first.address
        //     : InternetAddress.anyIPv4.address; // Fallback needed
        // debugPrint("P2P Transport Host: Attempting to bind to $hostIp:$port");

        _server = await HttpServer.bind(
            InternetAddress.anyIPv4, port); // Bind to anyIPv4
        _portInUse = port;
        debugPrint("P2P Transport Host: Server started on port $_portInUse");
        break;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 ||
            e.osError?.errorCode == 48 ||
            e.message.contains('errno = 98') ||
            e.message.contains('errno = 48')) {
          debugPrint("P2P Transport Host: Port $port in use, trying next...");
          port++;
          attempts++;
        } else {
          debugPrint("P2P Transport Host: Error binding server: $e");
          rethrow;
        }
      } catch (e) {
        debugPrint("P2P Transport Host: Unexpected error starting server: $e");
        rethrow;
      }
    }
    if (_server == null) {
      throw Exception(
          "P2P Transport Host: Could not bind to any port in the range $defaultPort-${port - 1}.");
    }

    _server!.listen(
      (HttpRequest request) async {
        final path = request.requestedUri.path;
        debugPrint("P2P Transport Host: Received request for $path");
        if (path == '/connect' &&
            WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            WebSocket websocket = await WebSocketTransformer.upgrade(request);
            _handleClientConnect(websocket, request);
          } catch (e) {
            debugPrint("P2P Transport Host: Error upgrading WebSocket: $e");
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('WebSocket upgrade failed.');
            await request.response.close();
          }
        } else if (path == '/file') {
          await _handleFileRequest(request);
        } else {
          debugPrint(
              "P2P Transport Host: Invalid request type for ${request.uri}");
          request.response
            ..statusCode = HttpStatus.notFound
            ..write("Resource not found.")
            ..close();
        }
      },
      onError: (error) {
        debugPrint("P2P Transport Host: Server listen error: $error");
      },
      onDone: () {
        debugPrint("P2P Transport Host: Server stopped listening.");
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

          // Handle different message types
          switch (message.type) {
            case P2pMessageType.payload:
              if (message.payload is P2pMessagePayload) {
                final payload = message.payload as P2pMessagePayload;
                // Check if host is a recipient
                bool hostIsRecipient =
                    message.clients.any((c) => c.id == hostId);

                if (hostIsRecipient) {
                  // Process received files
                  // Add files to receivable list if any
                  if (payload.files.isNotEmpty) {
                    for (var fileInfo in payload.files) {
                      if (_receivableFiles.containsKey(fileInfo.id)) {
                        debugPrint(
                            "P2P Transport Client [$username]: Received duplicate file info for ID ${fileInfo.id}, ignoring.");
                        continue;
                      }
                      _receivableFiles[fileInfo.id] =
                          ReceivableFileInfo(info: fileInfo);
                      debugPrint(
                          "P2P Transport Client [$username]: Added receivable file: ${fileInfo.name} (ID: ${fileInfo.id}) from ${clientInfo.username}");
                    }
                  }

                  // Forward the text/general payload part to the application stream
                  if (!_receivedPayloadsController.isClosed) {
                    _receivedPayloadsController.add(payload);
                  }
                }

                // Relay message to other targeted clients
                final recipientClientIds = message.clients
                    .where((c) => c.id != hostId)
                    .map((c) => c.id)
                    .toList();
                if (recipientClientIds.isNotEmpty) {
                  broadcast(message,
                      includeClientIds:
                          recipientClientIds); // Only send to specified clients
                }

                debugPrint(
                    "P2P Transport Host: Received payload from ${clientInfo.username} ($clientId) targeting ${message.clients.length} recipients.");
              } else {
                debugPrint(
                    "P2P Transport Host: Received payload message with incorrect payload type from $clientId");
              }
              break;
            case P2pMessageType.fileProgressUpdate:
              if (message.payload is P2pFileProgressUpdate) {
                // Check if host is a recipient
                bool hostIsRecipient =
                    message.clients.any((c) => c.id == hostId);

                if (hostIsRecipient) {
                  _handleFileProgressUpdate(
                      message.payload as P2pFileProgressUpdate);
                }

                // Relay message to other targeted clients
                final recipientClientIds = message.clients
                    .where((c) => c.id != hostId)
                    .map((c) => c.id)
                    .toList();
                if (recipientClientIds.isNotEmpty) {
                  broadcast(message,
                      includeClientIds:
                          recipientClientIds); // Only send to specified clients
                }
              } else {
                debugPrint(
                    "P2P Transport Host: Received fileProgressUpdate message with incorrect payload type from $clientId");
              }
              break;
            case P2pMessageType.clientList:
              // Clients shouldn't send client lists, ignore.
              debugPrint(
                  "P2P Transport Host: Received unexpected clientList message from $clientId");
              break;
            case P2pMessageType.unknown:
              debugPrint(
                  "P2P Transport Host: Received unknown message type from $clientId");
              break;
          }
        } catch (e, s) {
          debugPrint(
              "P2P Transport Host: Error parsing message from ${clientInfo.username} ($clientId): $e\nStack: $s\nData: $data");
        }
      },
      onDone: () {
        debugPrint(
            "P2P Transport Host: Client disconnected: ${clientInfo.username} ($clientId)");
        _clients.remove(clientId);
        // // Remove files hosted by this client if they disconnect
        // _receivableFiles.removeWhere((_, rf) => rf.info.senderId == clientId);
        _broadcastClientListUpdate();
      },
      onError: (error) {
        debugPrint(
            "P2P Transport Host: Error on client socket ${clientInfo.username} ($clientId): $error");
        _clients.remove(clientId);
        _broadcastClientListUpdate();
        client.close().catchError((_) => null);
      },
      cancelOnError: true,
    );
  }

  // --- Handle Progress Updates ---
  void _handleFileProgressUpdate(P2pFileProgressUpdate progressUpdate) {
    final fileInfo = _hostedFiles[progressUpdate.fileId];
    if (fileInfo != null) {
      // Ensure the update is from a valid receiver for this file
      if (fileInfo.downloadProgressBytes
          .containsKey(progressUpdate.receiverId)) {
        fileInfo.updateProgress(
            progressUpdate.receiverId, progressUpdate.bytesDownloaded);
        debugPrint(
            "P2P Transport Host: Progress update for ${fileInfo.info.name} from ${progressUpdate.receiverId}: ${progressUpdate.bytesDownloaded}/${fileInfo.info.size} bytes.");
      } else {
        debugPrint(
            "P2P Transport Host: Received progress update from non-recipient ${progressUpdate.receiverId} for file ${progressUpdate.fileId}");
      }
    } else {
      debugPrint(
          "P2P Transport Host: Received progress update for unknown/unhosted file ID: ${progressUpdate.fileId}");
      // Maybe the file was removed? Or this is an old update.
    }
  }

  void _broadcastClientListUpdate() {
    final hostInfo =
        P2pClientInfo(id: hostId, username: username, isHost: true);
    final clientListInfo = _clients.values.map((c) => c.info).toList();
    final fullListWithHost = [hostInfo, ...clientListInfo];

    // Broadcast the full list to all connected clients
    broadcast(P2pMessage(
      senderId: hostId,
      type: P2pMessageType.clientList,
      clients: fullListWithHost, // Send the complete client list
      payload: null, // No payload needed for client list type
    ));
    debugPrint(
        "P2P Transport Host: Broadcasting client list update: ${fullListWithHost.map((c) => c.username).toList()}");
  }

  // --- Handle File Requests by ID and Range ---
  Future<void> _handleFileRequest(HttpRequest request) async {
    final fileId = request.uri.queryParameters['id'];
    // Optional: could use receiverId for logging/tracking active downloads server-side
    // final receiverId = request.uri.queryParameters['receiverId'];

    if (fileId == null || fileId.isEmpty) {
      debugPrint("P2P Transport Host: File request missing ID.");
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('File ID parameter is required.')
        ..close();
      return;
    }

    final hostedFile = _hostedFiles[fileId];
    if (hostedFile == null) {
      debugPrint(
          "P2P Transport Host: Requested file ID not found or not hosted: $fileId");
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
          "P2P Transport Host: Hosted file path not found on disk: $filePath (ID: $fileId)");
      _hostedFiles.remove(fileId); // Clean up broken entry
      request.response
        ..statusCode = HttpStatus.internalServerError // Or Not Found
        ..write('File data is unavailable.')
        ..close();
      return;
    }

    final fileStat = await file.stat();
    final totalSize = fileStat.size;
    final response = request.response;

    // Default headers
    response.headers.contentType = ContentType.binary;
    response.headers.add(HttpHeaders.contentDisposition,
        'attachment; filename="${Uri.encodeComponent(hostedFile.info.name)}"'); // Use original name
    response.headers
        .add(HttpHeaders.acceptRangesHeader, 'bytes'); // Indicate range support

    // Check for Range header
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int rangeStart = 0;
    int? rangeEnd; // Inclusive end

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final rangeValues = rangeHeader.substring(6).split('-');
        rangeStart = int.parse(rangeValues[0]);
        if (rangeValues[1].isNotEmpty) {
          rangeEnd = int.parse(rangeValues[1]);
        }

        // Validate range
        if (rangeStart < 0 ||
            rangeStart >= totalSize ||
            (rangeEnd != null &&
                (rangeEnd < rangeStart || rangeEnd >= totalSize))) {
          throw const FormatException('Invalid range');
        }

        // Adjust end range if requesting 'bytes=1000-'
        rangeEnd ??= totalSize - 1;

        final rangeLength = (rangeEnd - rangeStart) + 1;

        debugPrint(
            "P2P Transport Host: Serving range $rangeStart-$rangeEnd (length $rangeLength) for file $fileId");

        response.statusCode = HttpStatus.partialContent;
        response.headers.contentLength = rangeLength;
        response.headers.add(HttpHeaders.contentRangeHeader,
            'bytes $rangeStart-$rangeEnd/$totalSize');

        // Stream the specified range
        final stream = file.openRead(
            rangeStart, rangeEnd + 1); // openRead end is exclusive
        await response.addStream(stream);
      } catch (e) {
        debugPrint(
            "P2P Transport Host: Invalid Range header '$rangeHeader': $e");
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.add(HttpHeaders.contentRangeHeader,
              'bytes */$totalSize') // Indicate valid range is 0 to totalSize-1
          ..write('Invalid byte range requested.')
          ..close();
        return; // Stop processing
      }
    } else {
      debugPrint(
          "P2P Transport Host: Serving full file $fileId (${hostedFile.info.name})");
      // Serve the full file
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = totalSize;
      final stream = file.openRead();
      await response.addStream(stream);
    }

    try {
      await response.close();
      debugPrint(
          "P2P Transport Host: Finished sending file/range for $fileId.");
    } catch (e) {
      // Client might have disconnected during transfer
      debugPrint(
          "P2P Transport Host: Error closing response stream for $fileId: $e");
    }
  }

  // --- Method to Share a File ---
  Future<P2pFileInfo?> shareFile(File file,
      {List<P2pClientInfo>? recipients}) async {
    if (_server == null || _portInUse == null) {
      debugPrint("P2P Transport Host: Cannot share file, server not running.");
      return null;
    }

    if (!await file.exists()) {
      debugPrint(
          "P2P Transport Host: Cannot share file, path does not exist: ${file.path}");
      return null;
    }

    final fileStat = await file.stat();
    final fileId = const Uuid().v4();
    final fileName = p.basename(file.path); // Get filename from path

    // --- Determine Host IP ---
    // This needs to be a specific IP reachable by clients or '0.0.0.0'
    String? reachableHostIp;
    try {
      // Prioritize non-loopback IPv4 addresses
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      if (interfaces.isNotEmpty) {
        reachableHostIp = interfaces.first.addresses.first.address;
      } else {
        // Fallback: Try loopback if no others found (for local testing)
        final loopback = await NetworkInterface.list(
            includeLoopback: true, type: InternetAddressType.IPv4);
        if (loopback.isNotEmpty) {
          reachableHostIp = loopback.first.addresses.first.address;
        }
      }
    } catch (e) {
      debugPrint("P2P Transport Host: Error getting network interfaces: $e");
    }
    // Last resort fallback
    reachableHostIp ??=
        _server?.address.address ?? InternetAddress.anyIPv4.address;
    // --- End Determine Host IP ---

    final fileInfo = P2pFileInfo(
      id: fileId,
      name: fileName,
      size: fileStat.size,
      senderId: hostId, // Host is the sender
      senderHostIp: reachableHostIp, // Use the determined IP
      senderPort: _portInUse!,
      metadata: {'shared_at': DateTime.now().toIso8601String()},
    );

    // Determine recipients: if null, send to all; otherwise, use the list
    final targetClients =
        recipients ?? _clients.values.map((c) => c.info).toList();
    final recipientIds = targetClients.map((c) => c.id).toList();

    // Store the file locally for serving
    _hostedFiles[fileId] = HostedFileInfo(
      info: fileInfo,
      localPath: file.path,
      recipientIds: recipientIds, // Track intended recipients
    );
    debugPrint(
        "P2P Transport Host: Hosting file '${fileInfo.name}' (ID: $fileId) for ${recipientIds.length} recipients.");

    // Create the message
    final payload = P2pMessagePayload(files: [fileInfo]);
    final message = P2pMessage(
      senderId: hostId,
      type: P2pMessageType.payload,
      payload: payload,
      clients: targetClients, // Target specific clients
    );

    // Send the message only to the specified recipients
    await broadcast(message, includeClientIds: recipientIds);

    return fileInfo; // Return info for potential local UI use
  }

  // --- Download a file ---
  Future<bool> downloadFile(
    String fileId,
    String saveDirectory, {
    String? customFileName,
    Function(FileDownloadProgressUpdate)? onProgress, // Callback for progress
    // Optional range parameters (for resuming/chunking in the future)
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final receivable = _receivableFiles[fileId];
    if (receivable == null) {
      debugPrint(
          "P2P Transport Host: Cannot download file, ID not found in receivable list: $fileId");
      return false;
    }

    final fileInfo = receivable.info;
    final url = Uri.parse(
        'http://${fileInfo.senderHostIp}:${fileInfo.senderPort}/file?id=$fileId&receiverId=$hostId'); // Include receiverId
    final finalFileName = customFileName ?? fileInfo.name;
    final savePath = p.join(saveDirectory, finalFileName);
    receivable.savePath = savePath; // Store where we are saving it

    // Set as downloading
    receivable.state = ReceivableFileState.downloading;
    debugPrint(
        "P2P Transport Host: Starting download for '${fileInfo.name}' (ID: $fileId) from $url to $savePath");

    // Ensure directory exists
    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint(
          "P2P Transport Host: Error creating save directory '$saveDirectory': $e");
      receivable.state = ReceivableFileState.error;
      return false;
    }

    final client = http.Client();
    int totalBytes = fileInfo.size;
    int bytesReceived = 0;
    IOSink? fileSink; // Use IOSink for more control

    try {
      final request = http.Request('GET', url);
      // --- Add Range Header if specified ---
      bool isRangeRequest = false;
      if (rangeStart != null) {
        String rangeValue = 'bytes=$rangeStart-';
        if (rangeEnd != null) {
          rangeValue += rangeEnd.toString();
        }
        request.headers[HttpHeaders.rangeHeader] = rangeValue;
        isRangeRequest = true;
        debugPrint(
            "P2P Transport Host: Requesting range: ${request.headers[HttpHeaders.rangeHeader]}");
        // If resuming, bytesReceived should start from rangeStart
        bytesReceived = rangeStart;
      }
      // --- End Range Header ---

      final response = await client.send(request);

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        debugPrint(
            "P2P Transport Host: Download failed for $fileId. Server responded with status ${response.statusCode}");
        receivable.state = ReceivableFileState.error;
        final body = await response.stream.bytesToString();
        debugPrint("P2P Transport Host: Server error body: $body");
        return false;
      }

      // Adjust totalBytes if it's a range request and Content-Range is present
      final contentRange = response.headers[HttpHeaders.contentRangeHeader];
      if (contentRange != null && contentRange.contains('/')) {
        try {
          totalBytes = int.parse(contentRange.split('/').last);
          // Update the stored size if the server reports a different one (maybe?)
          // receivable.info = receivable.info.copyWith(size: totalBytes); // Need copyWith in P2pFileInfo
        } catch (e) {
          debugPrint(
              "P2P Transport Host: Could not parse total size from Content-Range: $contentRange");
          // Keep original size as fallback
        }
      } else if (isRangeRequest) {
        debugPrint(
            "P2P Transport Host: Range request successful but Content-Range header missing or invalid.");
        // Cannot reliably track progress percentage without total size
      }

      // Open file sink. Use append mode if resuming (isRangeRequest and rangeStart > 0)
      // IMPORTANT: For robust resume, you'd need to check if the file exists and its size matches rangeStart.
      // For simplicity here, we just append if it's a range request starting > 0.
      final fileMode = (isRangeRequest && rangeStart! > 0)
          ? FileMode.writeOnlyAppend
          : FileMode.writeOnly;
      final file = File(savePath);
      fileSink = file.openWrite(mode: fileMode);

      // Timer for periodic progress updates to avoid spamming
      Timer? progressUpdateTimer;
      int lastReportedBytes = bytesReceived;

      // Function to report progress
      void reportProgress() {
        if (totalBytes > 0) {
          double percent = (bytesReceived / totalBytes) * 100.0;
          // Clamp percentage between 0 and 100
          percent = max(0.0, min(100.0, percent));
          receivable.downloadProgressPercent = percent;

          final updateData = FileDownloadProgressUpdate(
            fileId: fileId,
            progressPercent: percent,
            bytesDownloaded: bytesReceived,
            totalSize: totalBytes,
            savePath: savePath,
          );

          onProgress?.call(updateData); // Call the callback

          // Send progress update back to the original sender via WebSocket
          // Send updates less frequently (e.g., every 5% or every 500ms)
          if (bytesReceived > lastReportedBytes) {
            //&& (percent % 5 < 0.5 || bytesReceived == totalBytes)) { // Example throttling
            _sendProgressUpdateToServer(
                fileId, fileInfo.senderId, bytesReceived);
            lastReportedBytes = bytesReceived;
          }
        }
      }

      // Start periodic reporting
      progressUpdateTimer = Timer.periodic(
          const Duration(milliseconds: 500), (_) => reportProgress());

      await response.stream.listen(
        (List<int> chunk) {
          fileSink?.add(chunk);
          bytesReceived += chunk.length;
          reportProgress(); // Report after each chunk for now
        },
        onDone: () async {
          debugPrint(
              "P2P Transport Host: Download stream finished for $fileId.");
          await fileSink?.flush();
          await fileSink?.close();
          progressUpdateTimer?.cancel();
          reportProgress(); // Ensure final progress (100%) is reported
          debugPrint(
              "P2P Transport Host: Download complete for $fileId. Saved to $savePath");
        },
        onError: (e) {
          debugPrint(
              "P2P Transport Host: Error during download stream for $fileId: $e");
          receivable.state = ReceivableFileState.error;
          progressUpdateTimer?.cancel();
          fileSink?.close().catchError((_) {}); // Try to close sink on error
          // Set error state?
        },
        cancelOnError: true,
      ).asFuture(); // Wait for the stream listener to complete or error out

      // Check final size if not a range request?
      if (!isRangeRequest) {
        final savedFileStat = await File(savePath).stat();
        if (savedFileStat.size != totalBytes) {
          debugPrint(
              "P2P Transport Host: Warning: Final file size (${savedFileStat.size}) does not match expected size ($totalBytes) for $fileId");
        }
      }
    } catch (e, s) {
      debugPrint(
          "P2P Transport Host: Error downloading file $fileId: $e\nStack: $s");
      receivable.state = ReceivableFileState.error;
      await fileSink
          ?.close()
          .catchError((_) {}); // Ensure sink is closed on error
      // Clean up partially downloaded file
      // ignore: body_might_complete_normally_catch_error
      await File(savePath).delete().catchError((_) async {});
      return false;
    } finally {
      client.close();
    }

    receivable.state = ReceivableFileState.completed;
    return true; // Assume success if no exceptions were thrown and stream completed
  }

  // Helper to send progress update message to the file sender
  Future<void> _sendProgressUpdateToServer(
      String fileId, String originalSenderId, int bytesDownloaded) async {
    final progressPayload = P2pFileProgressUpdate(
      fileId: fileId,
      receiverId: hostId, // This is the receiver reporting progress
      bytesDownloaded: bytesDownloaded,
    );

    final message = P2pMessage(
      senderId: hostId,
      type: P2pMessageType.fileProgressUpdate,
      payload: progressPayload,
    );

    // Send the progress update to the sender
    debugPrint(
        "P2P Transport Host: Sending progress update: $bytesDownloaded bytes for $fileId");
    await sendToClient(originalSenderId, message);
  }

  /// Broadcasts a [message] to clients.
  /// Can specify EITHER [excludeClientIds] OR [includeClientIds].
  Future<void> broadcast(P2pMessage message,
      {List<String>? excludeClientIds, List<String>? includeClientIds}) async {
    if (_server == null) return;
    if (excludeClientIds != null && includeClientIds != null) {
      debugPrint(
          "P2P Transport Host: Cannot specify both include and exclude client IDs for broadcast.");
      return;
    }

    final msgString = message.toJsonString();
    int sentCount = 0;
    _clients.forEach((clientId, clientData) {
      bool shouldSend = true;
      if (excludeClientIds?.contains(clientId) == true) {
        shouldSend = false;
      }
      if (includeClientIds != null && !includeClientIds.contains(clientId)) {
        shouldSend = false;
      }

      if (shouldSend && clientData.socket.readyState == WebSocket.open) {
        try {
          clientData.socket.add(msgString);
          sentCount++;
        } catch (e) {
          debugPrint(
              "P2P Transport Host: Error sending broadcast to ${clientData.info.username} ($clientId): $e");
        }
      }
    });
    if (sentCount > 0) {
      debugPrint(
          "P2P Transport Host: Sent message type '${message.type}' to $sentCount clients.");
    }
  }

  Future<bool> sendToClient(String clientId, P2pMessage message) async {
    // This might be less used now with targeted broadcasts, but keep it
    if (_server == null) return false;
    final clientData = _clients[clientId];
    if (clientData != null && clientData.socket.readyState == WebSocket.open) {
      try {
        clientData.socket.add(message.toJsonString());
        debugPrint(
            "P2P Transport Host: Sent message type '${message.type}' to ${clientData.info.username} ($clientId).");
        return true;
      } catch (e) {
        debugPrint(
            "P2P Transport Host: Error sending direct message to ${clientData.info.username} ($clientId): $e");
        return false;
      }
    }
    return false;
  }

  Future<void> stop() async {
    debugPrint("P2P Transport Host: Stopping server...");
    await _receivedPayloadsController.close();

    for (var clientData in _clients.values) {
      await clientData.socket.close().catchError((_) {});
    }
    _clients.clear();
    _hostedFiles.clear(); // Clear hosted files on stop

    await _server?.close(force: true);
    _server = null;
    _portInUse = null;
    debugPrint("P2P Transport Host: Server stopped.");
  }
}

// --- P2pTransportClient ---
class P2pTransportClient {
  final String hostIp;
  final int defaultPort; // WebSocket server port
  final int defaultFilePort; // Port for THIS client's file server
  final String username;
  final String clientId = const Uuid().v4();
  WebSocket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;
  StreamSubscription? _socketSubscription;
  List<P2pClientInfo> _clientList = [];

  // --- Client-Side File Server ---
  HttpServer? _fileServer;
  int? _fileServerPortInUse;
  // Map: File ID -> HostedFileInfo (for files THIS client shares)
  final Map<String, HostedFileInfo> _hostedFiles = {};
  // --- End Client-Side File Server ---

  // --- File Receiving State ---
  // Map: File ID -> ReceivableFileInfo
  final Map<String, ReceivableFileInfo> _receivableFiles = {};
  // --- End File Receiving State ---

  final StreamController<P2pMessagePayload> _receivedPayloadsController =
      StreamController<P2pMessagePayload>.broadcast();

  bool get isConnected => _isConnected && _socket?.readyState == WebSocket.open;
  List<P2pClientInfo> get clientList => _clientList;
  int? get fileServerPort => _fileServerPortInUse; // Expose file server port
  List<HostedFileInfo> get hostedFileInfos => _hostedFiles.values.toList();
  List<ReceivableFileInfo> get receivableFileInfos =>
      _receivableFiles.values.toList();

  Stream<P2pMessagePayload> get receivedPayloadsStream =>
      _receivedPayloadsController.stream;

  P2pTransportClient({
    required this.hostIp,
    required this.defaultPort,
    required this.defaultFilePort, // Need default port for file server
    required this.username,
  });

  // --- Start the client's dedicated file server ---
  Future<bool> _startFileServer() async {
    if (_fileServer != null) {
      debugPrint(
          "P2P Transport Client [$username]: File server already running on $_fileServerPortInUse.");
      return true;
    }

    int attempts = 0;
    int port = defaultFilePort;
    while (attempts < 10) {
      try {
        // Use anyIPv4 for binding
        _fileServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _fileServerPortInUse = port;
        debugPrint(
            "P2P Transport Client [$username]: File server started on port $_fileServerPortInUse");

        _fileServer!.listen(
          (HttpRequest request) async {
            final path = request.requestedUri.path;
            debugPrint(
                "P2P Transport Client [$username]: File server received request for $path");
            if (path == '/file') {
              await _handleFileRequest(
                  request); // Use the same handler logic as host
            } else {
              debugPrint(
                  "P2P Transport Client [$username]: File server received invalid request ${request.method} ${request.uri}");
              request.response
                ..statusCode = HttpStatus.notFound // Or MethodNotAllowed
                ..write("Resource not found.")
                ..close();
            }
          },
          onError: (error) {
            debugPrint(
                "P2P Transport Client [$username]: File server error: $error");
            // Consider attempting to restart?
          },
          onDone: () {
            debugPrint(
                "P2P Transport Client [$username]: File server stopped listening.");
            _fileServerPortInUse = null;
          },
        );
        return true; // Success
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 ||
            e.osError?.errorCode == 48 ||
            e.message.contains('errno = 98') ||
            e.message.contains('errno = 48')) {
          debugPrint(
              "P2P Transport Client [$username]: File server port $port in use, trying next...");
          port++;
          attempts++;
        } else {
          debugPrint(
              "P2P Transport Client [$username]: Error binding file server: $e");
          return false; // Failed to bind
        }
      } catch (e) {
        debugPrint(
            "P2P Transport Client [$username]: Unexpected error starting file server: $e");
        return false; // Failed for other reason
      }
    }
    debugPrint(
        "P2P Transport Client [$username]: Could not bind file server to any port in range $defaultFilePort-${port - 1}.");
    return false; // Failed after retries
  }

  // --- Stop the client's file server ---
  Future<void> _stopFileServer() async {
    if (_fileServer != null) {
      debugPrint("P2P Transport Client [$username]: Stopping file server...");
      await _fileServer?.close(force: true);
      _fileServer = null;
      _fileServerPortInUse = null;
      _hostedFiles.clear(); // Clear files hosted by this client
      debugPrint("P2P Transport Client [$username]: File server stopped.");
    }
  }

  // --- Share the same file handling logic as Host ---
  // (Copied and adapted slightly for client context)
  Future<void> _handleFileRequest(HttpRequest request) async {
    final fileId = request.uri.queryParameters['id'];
    if (fileId == null || fileId.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('File ID parameter is required.')
        ..close();
      return;
    }
    final hostedFile =
        _hostedFiles[fileId]; // Check files hosted by THIS client
    if (hostedFile == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found or access denied.')
        ..close();
      return;
    }
    final filePath = hostedFile.localPath;
    final file = File(filePath);
    if (!await file.exists()) {
      _hostedFiles.remove(fileId); // Clean up
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
    bool isRangeRequest = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final rangeValues = rangeHeader.substring(6).split('-');
        rangeStart = int.parse(rangeValues[0]);
        if (rangeValues[1].isNotEmpty) rangeEnd = int.parse(rangeValues[1]);
        if (rangeStart < 0 ||
            rangeStart >= totalSize ||
            (rangeEnd != null &&
                (rangeEnd < rangeStart || rangeEnd >= totalSize))) {
          throw const FormatException('Invalid range');
        }
        rangeEnd ??= totalSize - 1;
        isRangeRequest = true;
      } catch (e) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.add(HttpHeaders.contentRangeHeader, 'bytes */$totalSize')
          ..write('Invalid byte range requested.')
          ..close();
        return;
      }
    }

    if (isRangeRequest) {
      final rangeLength = (rangeEnd! - rangeStart) + 1;
      response.statusCode = HttpStatus.partialContent;
      response.headers.contentLength = rangeLength;
      response.headers.add(HttpHeaders.contentRangeHeader,
          'bytes $rangeStart-$rangeEnd/$totalSize');
      final stream = file.openRead(rangeStart, rangeEnd + 1);
      await response.addStream(stream);
    } else {
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = totalSize;
      final stream = file.openRead();
      await response.addStream(stream);
    }
    try {
      await response.close();
    } catch (e) {
      debugPrint(
          "P2P Transport Client [$username]: Error closing file response stream for $fileId: $e");
    }
  }

  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;

    // --- Start file server BEFORE connecting to WebSocket ---
    // So we can report the file server port during connection
    bool fileServerStarted = await _startFileServer();
    if (!fileServerStarted) {
      _isConnecting = false;
      throw Exception(
          "P2P Transport Client [$username]: Failed to start local file server. Cannot connect.");
    }
    // --- End Start File Server ---

    int attempts = 0;
    int port = defaultPort;
    WebSocket? tempSocket;

    while (attempts < 10 && tempSocket == null) {
      // Include file server port in connection URL
      final url = Uri.parse(
          "ws://$hostIp:$port/connect?id=${Uri.encodeComponent(clientId)}&username=${Uri.encodeComponent(username)}&filePort=$_fileServerPortInUse");

      try {
        debugPrint(
            "P2P Transport Client [$username]: Attempting WebSocket connect to $url...");
        tempSocket = await WebSocket.connect(url.toString())
            .timeout(const Duration(seconds: 6));
        debugPrint(
            "P2P Transport Client [$username]: WebSocket connected to $url");
      } on TimeoutException {
        debugPrint(
            "P2P Transport Client [$username]: Connection attempt to $url timed out.");
        port++;
        attempts++;
      } on SocketException catch (e) {
        debugPrint(
            "P2P Transport Client [$username]: SocketException connecting to $url: ${e.message}. Trying next...");
        port++;
        attempts++;
      } catch (e) {
        debugPrint(
            "P2P Transport Client [$username]: Error connecting to $url: $e. Trying next...");
        port++;
        attempts++;
      }
    }

    _isConnecting = false;

    if (tempSocket == null) {
      await _stopFileServer(); // Stop file server if WebSocket connection failed
      throw Exception(
          "P2P Transport Client [$username]: Could not connect to WebSocket server at $hostIp on any port in range $defaultPort-${port - 1}.");
    }

    _socket = tempSocket;
    _isConnected = true;
    await _socketSubscription?.cancel();

    _socketSubscription = _socket!.listen(
      (data) async {
        try {
          final message = P2pMessage.fromJsonString(data as String);
          P2pClientInfo senderInfo = _clientList.firstWhere(
              (c) => c.id == message.senderId,
              orElse: () => P2pClientInfo(
                  id: message.senderId,
                  username: 'Unknown Sender',
                  isHost: message.senderId ==
                      'server')); // Handle sender not in list yet?

          switch (message.type) {
            case P2pMessageType.clientList:
              // Update local client list (excluding self)
              final List<P2pClientInfo> receivedList =
                  List<P2pClientInfo>.from(message.clients);
              receivedList.removeWhere(
                  (client) => client.id == clientId); // Remove self
              _clientList = receivedList;
              debugPrint(
                  "P2P Transport Client [$username]: Updated client list: ${_clientList.map((c) => c.username).toList()}");
              break;

            case P2pMessageType.payload:
              if (message.payload is P2pMessagePayload) {
                final payload = message.payload as P2pMessagePayload;
                debugPrint(
                    "P2P Transport Client [$username]: Received payload from ${senderInfo.username} (${senderInfo.id})");

                // Process received files
                if (payload.files.isNotEmpty) {
                  for (var fileInfo in payload.files) {
                    if (_receivableFiles.containsKey(fileInfo.id)) {
                      debugPrint(
                          "P2P Transport Client [$username]: Received duplicate file info for ID ${fileInfo.id}, ignoring.");
                      continue;
                    }
                    _receivableFiles[fileInfo.id] =
                        ReceivableFileInfo(info: fileInfo);
                    debugPrint(
                        "P2P Transport Client [$username]: Added receivable file: ${fileInfo.name} (ID: ${fileInfo.id}) from ${senderInfo.username}");
                  }
                }

                // Forward the text/general payload part to the application stream
                if (!_receivedPayloadsController.isClosed) {
                  _receivedPayloadsController.add(payload);
                }
              } else {
                debugPrint(
                    "P2P Transport Client [$username]: Received payload message with incorrect payload type.");
              }
              break;

            case P2pMessageType.fileProgressUpdate:
              // This client receives progress updates for files *it* is sharing
              if (message.payload is P2pFileProgressUpdate) {
                _handleFileProgressUpdate(
                    message.payload as P2pFileProgressUpdate);
              } else {
                debugPrint(
                    "P2P Transport Client [$username]: Received fileProgressUpdate message with incorrect payload type.");
              }
              break;

            case P2pMessageType.unknown:
              debugPrint(
                  "P2P Transport Client [$username]: Received unknown message type from ${senderInfo.username}");
              break;
          }
        } catch (e, s) {
          debugPrint(
              "P2P Transport Client [$username]: Error parsing server message: $e\nStack: $s\nData: $data");
        }
      },
      onDone: () {
        debugPrint(
            "P2P Transport Client [$username]: WebSocket disconnected from server.");
        _handleDisconnect();
      },
      onError: (error) {
        debugPrint("P2P Transport Client [$username]: WebSocket error: $error");
        _handleDisconnect(); // Treat error as disconnect
      },
      cancelOnError: true,
    );

    debugPrint(
        'P2P Transport Client [$username]: Connection established and listener set up.');
  }

  // Common logic for handling disconnection or socket error
  Future<void> _handleDisconnect() async {
    _isConnected = false;
    _socket = null; // Already closed or errored
    await _socketSubscription?.cancel();
    _socketSubscription = null;

    _clientList = []; // Clear client list
    // Stop the file server when disconnected from the main host
    await _stopFileServer();
    // Clear receivable files? Or keep them? Decide based on desired behavior.
    // _receivableFiles.clear();
    // if (!_downloadProgressController.isClosed) { /* Notify UI about cleared downloads? */ }
    debugPrint(
        "P2P Transport Client [$username]: Cleaned up after disconnect.");
  }

  // --- Handle received progress updates (for files shared BY THIS client) ---
  void _handleFileProgressUpdate(P2pFileProgressUpdate progressUpdate) {
    final fileInfo = _hostedFiles[progressUpdate.fileId];
    if (fileInfo != null) {
      if (fileInfo.downloadProgressBytes
          .containsKey(progressUpdate.receiverId)) {
        fileInfo.updateProgress(
            progressUpdate.receiverId, progressUpdate.bytesDownloaded);
        debugPrint(
            "P2P Transport Client [$username]: Progress update for shared file ${fileInfo.info.name} from ${progressUpdate.receiverId}: ${progressUpdate.bytesDownloaded}/${fileInfo.info.size} bytes.");
      } else {
        debugPrint(
            "P2P Transport Client [$username]: Received progress update from non-recipient ${progressUpdate.receiverId} for file ${progressUpdate.fileId}");
      }
    } else {
      debugPrint(
          "P2P Transport Client [$username]: Received progress update for unknown/unhosted file ID: ${progressUpdate.fileId}");
    }
  }

  // --- Share a file from the client ---
  Future<P2pFileInfo?> shareFile(File file,
      {List<P2pClientInfo>? recipients}) async {
    if (!isConnected) {
      debugPrint(
          "P2P Transport Client [$username]: Cannot share file, not connected to host.");
      return null;
    }
    if (_fileServer == null || _fileServerPortInUse == null) {
      debugPrint(
          "P2P Transport Client [$username]: Cannot share file, local file server is not running.");
      return null;
    }

    if (!await file.exists()) {
      debugPrint(
          "P2P Transport Client [$username]: Cannot share file, path does not exist: ${file.path}");
      return null;
    }

    final fileStat = await file.stat();
    final fileId = const Uuid().v4();
    final fileName = p.basename(file.path);

    // --- Determine Client's Reachable IP ---
    // This is tricky. We need an IP the *other* clients/host can reach.
    String? reachableClientIp;
    try {
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      if (interfaces.isNotEmpty) {
        reachableClientIp = interfaces.first.addresses.first.address;
      } else {
        final loopback = await NetworkInterface.list(
            includeLoopback: true, type: InternetAddressType.IPv4);
        if (loopback.isNotEmpty) {
          reachableClientIp = loopback.first.addresses.first.address;
        }
      }
    } catch (e) {
      debugPrint(
          "P2P Transport Client [$username]: Error getting network interfaces: $e");
    }
    reachableClientIp ??=
        InternetAddress.anyIPv4.address; // Fallback ip address
    // --- End Determine Client's IP ---

    final fileInfo = P2pFileInfo(
        id: fileId,
        name: fileName,
        size: fileStat.size,
        senderId: clientId, // This client is the sender
        senderHostIp: reachableClientIp, // Use this client's IP
        senderPort: _fileServerPortInUse!, // Use this client's file server port
        metadata: {'shared_at': DateTime.now().toIso8601String()});

    // Determine recipients: if null, send to *all* others (including host)
    final List<P2pClientInfo> targetClients;
    if (recipients == null) {
      // Send to everyone currently known (host + other clients)
      targetClients = List.from(_clientList); // Makes a copy
    } else {
      targetClients = recipients;
    }
    final recipientIds = targetClients.map((c) => c.id).toList();

    // Store locally for serving via this client's HTTP server
    _hostedFiles[fileId] = HostedFileInfo(
      info: fileInfo,
      localPath: file.path,
      recipientIds: recipientIds, // Track intended recipients
    );
    debugPrint(
        "P2P Transport Client [$username]: Hosting file '${fileInfo.name}' (ID: $fileId) for ${recipientIds.length} recipients.");

    // Create the message payload
    final payload = P2pMessagePayload(files: [fileInfo]);
    final message = P2pMessage(
      senderId: clientId,
      type: P2pMessageType.payload,
      payload: payload,
      clients:
          targetClients, // IMPORTANT: Tell the host who should receive this
    );

    // Send the message TO THE HOST, which will relay it to the target clients
    bool sent = await send(message);

    return sent ? fileInfo : null;
  }

  // --- Download a file ---
  Future<bool> downloadFile(
    String fileId,
    String saveDirectory, {
    String? customFileName,
    Function(FileDownloadProgressUpdate)? onProgress, // Callback for progress
    // Optional range parameters (for resuming/chunking in the future)
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final receivable = _receivableFiles[fileId];
    if (receivable == null) {
      debugPrint(
          "P2P Transport Client [$username]: Cannot download file, ID not found in receivable list: $fileId");
      return false;
    }

    final fileInfo = receivable.info;
    final url = Uri.parse(
        'http://${fileInfo.senderHostIp}:${fileInfo.senderPort}/file?id=$fileId&receiverId=$clientId'); // Include receiverId
    final finalFileName = customFileName ?? fileInfo.name;
    final savePath = p.join(saveDirectory, finalFileName);
    receivable.savePath = savePath; // Store where we are saving it

    // Set as downloading
    receivable.state = ReceivableFileState.downloading;
    debugPrint(
        "P2P Transport Client [$username]: Starting download for '${fileInfo.name}' (ID: $fileId) from $url to $savePath");

    // Ensure directory exists
    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint(
          "P2P Transport Client [$username]: Error creating save directory '$saveDirectory': $e");
      receivable.state = ReceivableFileState.error;
      return false;
    }

    final client = http.Client();
    int totalBytes = fileInfo.size;
    int bytesReceived = 0;
    IOSink? fileSink; // Use IOSink for more control

    try {
      final request = http.Request('GET', url);
      // --- Add Range Header if specified ---
      bool isRangeRequest = false;
      if (rangeStart != null) {
        String rangeValue = 'bytes=$rangeStart-';
        if (rangeEnd != null) {
          rangeValue += rangeEnd.toString();
        }
        request.headers[HttpHeaders.rangeHeader] = rangeValue;
        isRangeRequest = true;
        debugPrint(
            "P2P Transport Client [$username]: Requesting range: ${request.headers[HttpHeaders.rangeHeader]}");
        // If resuming, bytesReceived should start from rangeStart
        bytesReceived = rangeStart;
      }
      // --- End Range Header ---

      final response = await client.send(request);

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        debugPrint(
            "P2P Transport Client [$username]: Download failed for $fileId. Server responded with status ${response.statusCode}");
        receivable.state = ReceivableFileState.error;
        final body = await response.stream.bytesToString();
        debugPrint(
            "P2P Transport Client [$username]: Server error body: $body");
        return false;
      }

      // Adjust totalBytes if it's a range request and Content-Range is present
      final contentRange = response.headers[HttpHeaders.contentRangeHeader];
      if (contentRange != null && contentRange.contains('/')) {
        try {
          totalBytes = int.parse(contentRange.split('/').last);
          // Update the stored size if the server reports a different one (maybe?)
          // receivable.info = receivable.info.copyWith(size: totalBytes); // Need copyWith in P2pFileInfo
        } catch (e) {
          debugPrint(
              "P2P Transport Client [$username]: Could not parse total size from Content-Range: $contentRange");
          // Keep original size as fallback
        }
      } else if (isRangeRequest) {
        debugPrint(
            "P2P Transport Client [$username]: Range request successful but Content-Range header missing or invalid.");
        // Cannot reliably track progress percentage without total size
      }

      // Open file sink. Use append mode if resuming (isRangeRequest and rangeStart > 0)
      // IMPORTANT: For robust resume, you'd need to check if the file exists and its size matches rangeStart.
      // For simplicity here, we just append if it's a range request starting > 0.
      final fileMode = (isRangeRequest && rangeStart! > 0)
          ? FileMode.writeOnlyAppend
          : FileMode.writeOnly;
      final file = File(savePath);
      fileSink = file.openWrite(mode: fileMode);

      // Timer for periodic progress updates to avoid spamming
      Timer? progressUpdateTimer;
      int lastReportedBytes = bytesReceived;

      // Function to report progress
      void reportProgress() {
        if (totalBytes > 0) {
          double percent = (bytesReceived / totalBytes) * 100.0;
          // Clamp percentage between 0 and 100
          percent = max(0.0, min(100.0, percent));
          receivable.downloadProgressPercent = percent;

          final updateData = FileDownloadProgressUpdate(
            fileId: fileId,
            progressPercent: percent,
            bytesDownloaded: bytesReceived,
            totalSize: totalBytes,
            savePath: savePath,
          );

          onProgress?.call(updateData); // Call the callback

          // Send progress update back to the original sender via WebSocket
          // Send updates less frequently (e.g., every 5% or every 500ms)
          if (bytesReceived > lastReportedBytes) {
            //&& (percent % 5 < 0.5 || bytesReceived == totalBytes)) { // Example throttling
            _sendProgressUpdateToServer(
                fileId, fileInfo.senderId, bytesReceived);
            lastReportedBytes = bytesReceived;
          }
        }
      }

      // Start periodic reporting
      progressUpdateTimer = Timer.periodic(
          const Duration(milliseconds: 500), (_) => reportProgress());

      await response.stream.listen(
        (List<int> chunk) {
          fileSink?.add(chunk);
          bytesReceived += chunk.length;
          reportProgress(); // Report after each chunk for now
        },
        onDone: () async {
          debugPrint(
              "P2P Transport Client [$username]: Download stream finished for $fileId.");
          await fileSink?.flush();
          await fileSink?.close();
          progressUpdateTimer?.cancel();
          reportProgress(); // Ensure final progress (100%) is reported
          debugPrint(
              "P2P Transport Client [$username]: Download complete for $fileId. Saved to $savePath");
        },
        onError: (e) {
          debugPrint(
              "P2P Transport Client [$username]: Error during download stream for $fileId: $e");
          receivable.state = ReceivableFileState.error;
          progressUpdateTimer?.cancel();
          fileSink?.close().catchError((_) {}); // Try to close sink on error
          // Set error state?
        },
        cancelOnError: true,
      ).asFuture(); // Wait for the stream listener to complete or error out

      // Check final size if not a range request?
      if (!isRangeRequest) {
        final savedFileStat = await File(savePath).stat();
        if (savedFileStat.size != totalBytes) {
          debugPrint(
              "P2P Transport Client [$username]: Warning: Final file size (${savedFileStat.size}) does not match expected size ($totalBytes) for $fileId");
        }
      }
    } catch (e, s) {
      debugPrint(
          "P2P Transport Client [$username]: Error downloading file $fileId: $e\nStack: $s");
      await fileSink
          ?.close()
          .catchError((_) {}); // Ensure sink is closed on error
      // Clean up partially downloaded file
      // ignore: body_might_complete_normally_catch_error
      await File(savePath).delete().catchError((_) async {});
      return false;
    } finally {
      client.close();
    }

    receivable.state = ReceivableFileState.completed;
    return true; // Assume success if no exceptions were thrown and stream completed
  }

  // Helper to send progress update message to the file sender
  Future<void> _sendProgressUpdateToServer(
      String fileId, String originalSenderId, int bytesDownloaded) async {
    if (!isConnected) return;

    final progressPayload = P2pFileProgressUpdate(
      fileId: fileId,
      receiverId: clientId, // This client is the receiver reporting progress
      bytesDownloaded: bytesDownloaded,
    );

    final message = P2pMessage(
      senderId: clientId,
      type: P2pMessageType.fileProgressUpdate,
      payload: progressPayload,
      clients: _clientList.where((cl) => cl.id == originalSenderId).toList(),
    );

    // Send the progress update to the sender
    debugPrint(
        "P2P Transport Client [$username]: Sending progress update: $bytesDownloaded bytes for $fileId");
    await send(message);
  }

  /// Sends a [message] TO THE HOST server. The host relays messages to other clients.
  Future<bool> send(P2pMessage message) async {
    if (isConnected && _socket != null) {
      try {
        _socket!.add(message.toJsonString());
        // Avoid logging overly verbose messages like progress updates frequently
        if (message.type != P2pMessageType.fileProgressUpdate) {
          debugPrint(
              "P2P Transport Client [$username]: Sent message type '${message.type}' to host.");
        }
        return true;
      } catch (e) {
        debugPrint(
            "P2P Transport Client [$username]: Error sending message: $e");
        // Consider attempting to reconnect or marking as disconnected
        await _handleDisconnect(); // Treat send error as disconnect
        return false;
      }
    } else {
      debugPrint(
          "P2P Transport Client [$username]: Cannot send message, socket not connected.");
      return false;
    }
  }

  Future<void> disconnect() async {
    debugPrint("P2P Transport Client [$username]: Disconnecting...");
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close().catchError((_) {}); // Ignore errors on close
    await _handleDisconnect(); // Perform cleanup
    debugPrint("P2P Transport Client [$username]: Disconnected.");
  }

  Future<void> dispose() async {
    debugPrint("P2P Transport Client [$username]: Disposing...");
    await disconnect(); // Ensure disconnected and file server stopped

    // Close stream controllers
    await _receivedPayloadsController.close();

    debugPrint("P2P Transport Client [$username]: Disposed.");
  }
}
