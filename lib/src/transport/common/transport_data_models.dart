import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'transport_enums.dart';

/// Represents information about a P2P client.
@immutable
class P2pClientInfo {
  /// Unique identifier for the client.
  final String id;

  /// Username of the client.
  final String username;

  /// Flag indicating if this client is the host of the P2P session.
  final bool isHost;

  /// Creates a [P2pClientInfo] instance.
  const P2pClientInfo(
      {required this.id, required this.username, required this.isHost});

  /// Creates a [P2pClientInfo] instance from a JSON map.
  factory P2pClientInfo.fromJson(Map<String, dynamic> json) {
    return P2pClientInfo(
      id: json['id'] as String? ?? 'unknown_id',
      username: json['username'] as String? ?? 'Unknown User',
      isHost: json['isHost'] as bool? ?? false,
    );
  }

  /// Converts this [P2pClientInfo] instance to a JSON map.
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

/// Represents information about a file being shared in the P2P network.
@immutable
class P2pFileInfo {
  /// Unique identifier for the file.
  final String id;

  /// Name of the file.
  final String name;

  /// Size of the file in bytes.
  final int size;

  /// ID of the client sending the file.
  final String senderId;

  /// IP address of the host serving the file.
  final String senderHostIp;

  /// Port number on which the file is being served.
  final int senderPort;

  /// Additional metadata associated with the file.
  final Map<String, dynamic> metadata;

  /// Creates a [P2pFileInfo] instance.
  const P2pFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.senderId,
    required this.senderHostIp,
    required this.senderPort,
    this.metadata = const {},
  });

  /// Creates a [P2pFileInfo] instance from a JSON map.
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

  /// Converts this [P2pFileInfo] instance to a JSON map.
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

/// Represents the payload of a P2P message, containing text and/or file information.
@immutable
class P2pMessagePayload {
  /// The text content of the message.
  final String text;

  /// A list of files included in the message.
  final List<P2pFileInfo> files;

  /// Creates a [P2pMessagePayload] instance.
  const P2pMessagePayload({this.text = '', this.files = const []});

  /// Creates a [P2pMessagePayload] instance from a JSON map.
  factory P2pMessagePayload.fromJson(Map<String, dynamic> json) {
    return P2pMessagePayload(
      text: json['text'] as String? ?? '',
      files: (json['files'] as List<dynamic>? ?? [])
          .map((fileJson) =>
              P2pFileInfo.fromJson(fileJson as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Creates a [P2pMessagePayload] instance from a JSON string.
  factory P2pMessagePayload.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pMessagePayload.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pMessagePayload from string: $e");
      rethrow;
    }
  }

  /// Converts this [P2pMessagePayload] instance to a JSON map.
  Map<String, dynamic> toJson() => {
        'text': text,
        'files': files.map((f) => f.toJson()).toList(),
      };

  /// Converts this [P2pMessagePayload] instance to a JSON string.
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

/// Represents an update on the progress of a file download.
@immutable
class P2pFileProgressUpdate {
  /// The ID of the file whose download progress is being updated.
  final String fileId;

  /// The ID of the client receiving the file.
  final String receiverId;

  /// The number of bytes downloaded so far.
  final int bytesDownloaded;

  /// The state of the file.
  final ReceivableFileState fileState;

  /// Creates a [P2pFileProgressUpdate] instance.
  const P2pFileProgressUpdate({
    required this.fileId,
    required this.receiverId,
    required this.bytesDownloaded,
    required this.fileState,
  });

  /// Creates a [P2pFileProgressUpdate] instance from a JSON map.
  factory P2pFileProgressUpdate.fromJson(Map<String, dynamic> json) {
    return P2pFileProgressUpdate(
      fileId: json['fileId'] as String? ?? '',
      receiverId: json['receiverId'] as String? ?? '',
      bytesDownloaded: json['bytesDownloaded'] as int? ?? 0,
      fileState: ReceivableFileState.values.firstWhere(
        (e) => e.name == json['fileState'],
      ),
    );
  }

  /// Creates a [P2pFileProgressUpdate] instance from a JSON string.
  factory P2pFileProgressUpdate.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pFileProgressUpdate.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pFileProgressUpdate from string: $e");
      rethrow;
    }
  }

  /// Converts this [P2pFileProgressUpdate] instance to a JSON map.
  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'receiverId': receiverId,
        'bytesDownloaded': bytesDownloaded,
        'fileState': fileState.name,
      };

  /// Converts this [P2pFileProgressUpdate] instance to a JSON string.
  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() =>
      'P2pFileProgressUpdate(fileId: $fileId, receiver: $receiverId, bytes: $bytesDownloaded, fileState: $fileState)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is P2pFileProgressUpdate &&
          runtimeType == other.runtimeType &&
          fileId == other.fileId &&
          receiverId == other.receiverId &&
          bytesDownloaded == other.bytesDownloaded &&
          fileState == fileState;
  @override
  int get hashCode => Object.hash(fileId, receiverId, bytesDownloaded, fileState);
}

/// Represents a generic P2P message exchanged between clients.
@immutable
class P2pMessage {
  /// The ID of the client sending the message.
  final String senderId;

  /// The type of the message.
  final P2pMessageType type;

  /// The payload of the message, which can be [P2pMessagePayload] or [P2pFileProgressUpdate], or null.
  final dynamic payload;

  /// A list of clients targeted by or relevant to this message.
  /// For [P2pMessageType.clientList], this contains the full list of clients.
  /// For [P2pMessageType.payload] or [P2pMessageType.fileProgressUpdate], this lists the intended recipients.
  final List<P2pClientInfo> clients;

  /// Creates a [P2pMessage] instance.
  const P2pMessage({
    required this.senderId,
    required this.type,
    this.payload,
    this.clients = const [],
  });

  /// Creates a [P2pMessage] instance from a JSON map.
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

  /// Creates a [P2pMessage] instance from a JSON string.
  factory P2pMessage.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pMessage.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pMessage from string: $e");
      rethrow;
    }
  }

  /// Converts this [P2pMessage] instance to a JSON map.
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

  /// Converts this [P2pMessage] instance to a JSON string.
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
