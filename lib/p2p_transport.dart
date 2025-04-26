import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart'; // For debugPrint

enum P2pMessageType {
  chat,
  fileInfo,
  clientList,
  decodeError,
  unknown,
}

/// Holds information about a connected client or the host.
@immutable
class P2pClientInfo {
  final String
      id; // Unique identifier (hashcode for clients, 'server' for host)
  final String username; // User-defined name
  final bool isHost; // True if this represents the host/server

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
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is P2pClientInfo &&
        other.id == id &&
        other.username == username &&
        other.isHost == isHost;
  }

  @override
  int get hashCode => Object.hash(id, username, isHost);
}

/// A simple message class that can be serialized to/from JSON.
/// It includes basic fields: [senderId] (identifies the sender, e.g., client hashcode or 'server'),
/// [type] (application-defined message type), and [payload] (the actual data).
/// Optionally, it can include a list of [P2pClientInfo] objects (useful for broadcasting the client list).
@immutable
class P2pMessage {
  /// Identifier for the sender (e.g., client hashcode, 'server', or a custom ID).
  final String senderId;

  /// Application-defined type for the message (e.g., 'chat', 'fileInfo', 'clientList').
  final P2pMessageType type;

  /// The actual content/data of the message. Can be any JSON-encodable object.
  /// For binary data, consider Base64 encoding it into a string here, or use a different transport mechanism.
  final dynamic payload;

  /// Optional list of client information objects, typically used by the server to inform clients about connections.
  final List<P2pClientInfo>? clients;

  const P2pMessage({
    required this.senderId,
    required this.type,
    required this.payload,
    this.clients, // Updated type
  });

  /// Deserialize a P2pMessage instance from a JSON map.
  factory P2pMessage.fromJson(Map<String, dynamic> json) {
    return P2pMessage(
      senderId: json['senderId'] as String? ?? 'unknown',
      type: P2pMessageType.values.firstWhere(
          (e) => e.name == json['type'], // Use name for robust serialization
          orElse: () => P2pMessageType.unknown),
      payload: json['payload'], // Keep payload as dynamic
      clients: json['clients'] != null
          ? (json['clients'] as List<dynamic>)
              .map((clientJson) =>
                  P2pClientInfo.fromJson(clientJson as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// Deserialize a P2pMessage instance from a JSON string.
  factory P2pMessage.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return P2pMessage.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding P2pMessage from string: $e");
      // Return a default error message or rethrow, depending on desired handling
      return P2pMessage(
        senderId: 'error',
        type: P2pMessageType.decodeError,
        payload: jsonString,
      );
    }
  }

  /// Serialize the P2pMessage instance to a JSON map.
  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'type': type.name, // Use name for robust serialization
        'payload': payload, // Assumes payload is JSON-encodable
        if (clients != null)
          'clients': clients!
              .map((c) => c.toJson())
              .toList(), // Serialize P2pClientInfo list
      };

  /// Serialize the P2pMessage instance to a JSON string.
  String toJsonString() {
    return jsonEncode(toJson());
  }

  @override
  String toString() {
    // Limit payload length in toString for readability
    String payloadSummary = payload.toString();
    if (payloadSummary.length > 100) {
      payloadSummary = '${payloadSummary.substring(0, 97)}...';
    }
    // Limit clients list length in toString
    String clientsSummary = clients != null
        ? (clients!.length > 3
            ? '${clients!.sublist(0, 3)}... (${clients!.length} total)'
            : clients.toString())
        : 'null';
    return 'P2pMessage(senderId: $senderId, type: $type, payload: $payloadSummary, clients: $clientsSummary)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is P2pMessage &&
        other.senderId == senderId &&
        other.type == type &&
        // Note: Deep equality check for payload might be needed if it's complex
        other.payload == payload &&
        listEquals(other.clients,
            clients); // listEquals works for lists of objects with ==
  }

  @override
  int get hashCode => Object.hash(
      senderId, type, payload, Object.hashAll(clients ?? [])); // Hash the list
}

/// The host class for P2P transport using WebSockets.
///
/// It creates a WebSocket server on the specified [hostIp] and attempts to bind
/// starting from [defaultPort], trying subsequent ports if the default is busy.
/// It manages connected clients and facilitates broadcasting messages.
class P2pTransportHost {
  final int defaultPort;
  final String username; // Host's username
  HttpServer? _server;
  int? _portInUse;

  /// Map storing connected clients, using their hash code string as the key, along with their info.
  final Map<String, ({WebSocket socket, P2pClientInfo info})> _clients = {};

  /// Stream controller for broadcasting received messages from clients.
  final StreamController<P2pMessage> _receivedMessagesController =
      StreamController<P2pMessage>.broadcast();

  /// Stream controller for broadcasting client connection/disconnection events.
  /// Emits the current list of [P2pClientInfo] objects.
  final StreamController<List<P2pClientInfo>> _clientListController =
      StreamController<List<P2pClientInfo>>.broadcast();

  /// Public stream of messages received from any connected client.
  Stream<P2pMessage> get receivedMessages => _receivedMessagesController.stream;

  /// Public stream emitting the updated list of connected client information whenever a
  /// client connects or disconnects. Includes the host.
  Stream<List<P2pClientInfo>> get clientListStream =>
      _clientListController.stream;

  /// The actual port the server is listening on after successful binding.
  /// Null if the server is not running.
  int? get portInUse => _portInUse;

  /// Public list of the connected client IDs (excluding the host).
  List<String> get clientList => _clients.keys.toList();

  P2pTransportHost({required this.defaultPort, required this.username});

  /// Starts the WebSocket server.
  ///
  /// Tries to bind to [hostIp] starting at [defaultPort], incrementing the port
  /// up to 10 times if the port is already in use.
  ///
  /// Throws an [Exception] if unable to bind to any port in the range.
  Future<void> start() async {
    if (_server != null) {
      debugPrint("Server already running on $_portInUse.");
      return;
    }

    int attempts = 0;
    int port = defaultPort;
    while (attempts < 10) {
      try {
        InternetAddress hostIp = InternetAddress.anyIPv4;

        _server = await HttpServer.bind(hostIp, port);
        _portInUse = port;
        debugPrint(
            "P2P Transport Host: Server started on ${hostIp.address}:$_portInUse");
        break; // Success
      } on SocketException catch (e) {
        if (e.osError?.errorCode ==
                98 || // Address already in use (Linux/macOS)
            e.osError?.errorCode == 48 || // Address already in use (Windows)
            e.message.contains('errno = 98') || // Fallback check
            e.message.contains('errno = 48')) {
          debugPrint(
              "P2P Transport Host: Port $port is in use, trying next port...");
          port++;
          attempts++;
        } else {
          debugPrint("P2P Transport Host: Error binding server: $e");
          rethrow; // Rethrow unexpected socket errors
        }
      } catch (e) {
        debugPrint("P2P Transport Host: Unexpected error starting server: $e");
        rethrow; // Rethrow other unexpected errors
      }
    }

    if (_server == null) {
      throw Exception(
          "P2P Transport Host: Could not bind to any port in the range $defaultPort-${port - 1}.");
    }

    // Listen for incoming HTTP requests to upgrade to WebSocket.
    _server!.listen(
      (HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            WebSocket websocket = await WebSocketTransformer.upgrade(request);
            _handleClientConnect(
                websocket, request); // Pass request to get query params
          } catch (e) {
            debugPrint("P2P Transport Host: Error upgrading WebSocket: $e");
          }
        } else {
          // Respond with error if not a WebSocket upgrade request.
          request.response
            ..statusCode = HttpStatus.upgradeRequired
            ..headers.add('Connection', 'Upgrade')
            ..headers.add('Upgrade', 'websocket')
            ..write("WebSocket connections only")
            ..close();
        }
      },
      onError: (error) {
        debugPrint("P2P Transport Host: Server listen error: $error");
        // Consider stopping the server or attempting recovery here
      },
      onDone: () {
        debugPrint("P2P Transport Host: Server stopped listening.");
        _portInUse = null;
      },
    );
  }

  /// Handles a new client WebSocket connection.
  void _handleClientConnect(WebSocket client, HttpRequest request) {
    // Extract user info from query parameters (fallback to default)
    final clientId =
        request.uri.queryParameters['id'] ?? client.hashCode.toString();
    final clientUsername =
        request.uri.queryParameters['username'] ?? 'User_$clientId';

    final clientInfo =
        P2pClientInfo(id: clientId, username: clientUsername, isHost: false);

    debugPrint(
        "P2P Transport Host: Client connected: ${clientInfo.username} (ID: $clientId)");

    // Store both the socket and the client info
    _clients[clientId] = (socket: client, info: clientInfo);

    // Notify listeners about the updated client list.
    _broadcastClientListUpdate();

    // Listen for messages coming from this specific client.
    client.listen(
      (data) {
        try {
          // Assume data is a JSON string representing P2pMessage
          final message = P2pMessage.fromJsonString(data as String);
          // Add the received message to the public stream.
          if (message.type == P2pMessageType.chat ||
              message.type == P2pMessageType.fileInfo) {
            _receivedMessagesController.add(message);
          }
          debugPrint(
              "P2P Transport Host: Received from ${clientInfo.username} ($clientId): ${message.type}");
        } catch (e) {
          debugPrint(
              "P2P Transport Host: Error parsing message from ${clientInfo.username} ($clientId): $e\nData: $data");
          // Optionally send an error back to the client or just log it.
        }
      },
      onDone: () {
        debugPrint(
            "P2P Transport Host: Client disconnected: ${clientInfo.username} ($clientId)");
        _clients.remove(clientId);
        // Notify listeners about the updated client list.
        _broadcastClientListUpdate();
      },
      onError: (error) {
        debugPrint(
            "P2P Transport Host: Error on client socket ${clientInfo.username} ($clientId): $error");
        // Assume error means disconnection.
        _clients.remove(clientId);
        _broadcastClientListUpdate();
        // Ensure socket is closed if possible
        client.close().catchError((_) => null);
      },
      cancelOnError: true, // Close the stream on error
    );
  }

  /// Sends the current list of client info (including host) to the client list stream controller and broadcasts it.
  void _broadcastClientListUpdate() {
    // Create the list including the host
    final hostInfo =
        P2pClientInfo(id: 'server', username: username, isHost: true);
    final clientListWithoutHost = _clients.values.map((c) => c.info);
    final currentP2pClientInfoList = [hostInfo, ...clientListWithoutHost];

    _clientListController.add(clientListWithoutHost
        .toList()); // Don't need host in the client list consumed by the host
    debugPrint(
        "P2P Transport Host: Broadcasting client list update: ${currentP2pClientInfoList.map((c) => c.username).toList()}");
    // Send this list as a P2pMessage to all clients
    broadcast(P2pMessage(
      senderId: 'server',
      type: P2pMessageType.clientList,
      payload: null, // Payload not needed, using the 'clients' field
      clients: currentP2pClientInfoList,
    ));
  }

  /// Broadcasts a [message] to all connected clients.
  ///
  /// - [message]: The [P2pMessage] to send.
  /// - [excludeClientId]: Optional ID of a client to exclude from the broadcast (e.g., the original sender).
  Future<void> broadcast(P2pMessage message, {String? excludeClientId}) async {
    if (_server == null) {
      debugPrint("P2P Transport Host: Cannot broadcast, server not running.");
      return;
    }
    final msgString = message.toJsonString();
    int sentCount = 0;
    _clients.forEach((clientId, clientData) {
      if (clientId != excludeClientId &&
          clientData.socket.readyState == WebSocket.open) {
        try {
          clientData.socket.add(msgString);
          sentCount++;
        } catch (e) {
          debugPrint(
              "P2P Transport Host: Error sending broadcast to ${clientData.info.username} ($clientId): $e");
          // Consider removing client if sending fails repeatedly
        }
      }
    });
    debugPrint(
        "P2P Transport Host: Broadcast message type '${message.type}' to $sentCount clients.");
  }

  /// Sends a [message] to a specific client identified by [clientId].
  ///
  /// - [clientId]: The target client's ID (its hash code string).
  /// - [message]: The [P2pMessage] to send.
  ///
  /// Returns `true` if the client was found and message was sent, `false` otherwise.
  Future<bool> sendToClient(String clientId, P2pMessage message) async {
    if (_server == null) {
      debugPrint("P2P Transport Host: Cannot send, server not running.");
      return false;
    }
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
    } else {
      debugPrint("P2P Transport Host: Client $clientId not found or not open.");
      return false;
    }
  }

  /// Stops the WebSocket server, closes all client connections, and closes streams.
  Future<void> stop() async {
    debugPrint("P2P Transport Host: Stopping server...");
    // Close stream controllers first to prevent adding events during shutdown
    // Check if controllers are closed before closing them
    if (!_receivedMessagesController.isClosed) {
      await _receivedMessagesController.close();
    }
    if (!_clientListController.isClosed) {
      await _clientListController.close();
    }

    // Close all client connections
    for (var clientData in _clients.values) {
      await clientData.socket.close().catchError((e) {
        debugPrint(
            "P2P Transport Host: Error closing client socket for ${clientData.info.username}: $e");
      });
    }
    _clients.clear();

    // Close the server itself
    await _server?.close(force: true);
    _server = null;
    _portInUse = null;
    debugPrint("P2P Transport Host: Server stopped.");
  }
}

/// The client class for P2P transport using WebSockets.
///
/// It attempts to establish a connection to the server at [hostIp], starting
/// from [defaultPort] and trying subsequent ports if the connection fails.
class P2pTransportClient {
  final String hostIp;
  final int defaultPort;
  final String username; // Client's username
  final String _clientId = const Uuid().v4(); // Client's random id
  WebSocket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false; // Flag to prevent concurrent connection attempts
  StreamSubscription? _socketSubscription;
  List<P2pClientInfo> _clientList = []; // Store the client info list

  /// Stream controller for broadcasting messages received from the server.
  final StreamController<P2pMessage> _receivedMessagesController =
      StreamController<P2pMessage>.broadcast();

  /// Stream controller for broadcasting client connection/disconnection events.
  /// Emits the current list of [P2pClientInfo] objects.
  final StreamController<List<P2pClientInfo>> _clientListController =
      StreamController<List<P2pClientInfo>>.broadcast();

  /// Public stream of messages received from the server.
  Stream<P2pMessage> get receivedMessages => _receivedMessagesController.stream;

  /// Public stream emitting the updated list of connected client information whenever a
  /// client connects or disconnects (as reported by the server). Includes the host.
  Stream<List<P2pClientInfo>> get clientListStream =>
      _clientListController.stream;

  /// Returns `true` if the client is currently connected to the server.
  bool get isConnected => _isConnected && _socket?.readyState == WebSocket.open;

  /// Public list of the connected clients (including host) as last reported by the server.
  List<P2pClientInfo> get clientList => _clientList;

  P2pTransportClient(
      {required this.hostIp,
      required this.defaultPort,
      required this.username});

  /// Attempts to connect to the host WebSocket server.
  ///
  /// Tries to connect to [hostIp] starting at [defaultPort], incrementing the port
  /// up to 10 times if the connection fails. Includes the client's [username]
  /// in the connection URL query parameters.
  ///
  /// Throws an [Exception] if unable to connect to any port in the range.
  Future<void> connect() async {
    if (isConnected || _isConnecting) {
      debugPrint("P2P Transport Client: Already connected or connecting.");
      return;
    }
    _isConnecting = true;

    int attempts = 0;
    int port = defaultPort;
    WebSocket? tempSocket;

    while (attempts < 10 && tempSocket == null) {
      // Add clientId and username to websocket url query parameters
      final url = Uri.parse(
          "ws://$hostIp:$port/connect?id=${Uri.encodeComponent(_clientId)}&username=${Uri.encodeComponent(username)}");

      try {
        debugPrint("P2P Transport Client: Attempting to connect to $url...");
        // Add a timeout to WebSocket.connect to prevent indefinite hangs
        tempSocket = await WebSocket.connect(url.toString())
            .timeout(const Duration(seconds: 6));
        debugPrint("P2P Transport Client: Connected to server at $url");
      } on TimeoutException {
        debugPrint(
            "P2P Transport Client: Connection attempt to $url timed out.");
        port++;
        attempts++;
      } on SocketException catch (e) {
        debugPrint(
            "P2P Transport Client: SocketException connecting to $url: ${e.message}. Trying next port...");
        port++;
        attempts++;
      } catch (e) {
        debugPrint(
            "P2P Transport Client: Error connecting to $url: $e. Trying next port...");
        port++;
        attempts++;
        // Rethrow if it's not a connection error? Maybe not, just keep trying.
      }
    }

    _isConnecting = false; // Finished connection attempts

    if (tempSocket == null) {
      throw Exception(
          "P2P Transport Client: Could not connect to server on any port in the range $defaultPort-${port - 1}.");
    }

    _socket = tempSocket;
    _isConnected = true;

    // Cancel any previous subscription before starting a new one
    await _socketSubscription?.cancel();

    // Listen for messages from the server.
    _socketSubscription = _socket!.listen(
      (data) async {
        try {
          // Assume data is a JSON string representing P2pMessage
          final message = P2pMessage.fromJsonString(data as String);
          // Add the received message to the public stream.
          if (message.type == P2pMessageType.clientList) {
            // Delay before updating client list
            await Future.delayed(const Duration(milliseconds: 800));
            // Store the received client list and notify listeners
            _clientList = message.clients ?? [];
            _clientList.removeWhere(
                (client) => client.id == _clientId); // Remove self from list
            _clientListController.add(_clientList);
            debugPrint(
                "P2P Transport Client: Updated client list: ${_clientList.map((c) => c.username).toList()}");
          } else if (message.type == P2pMessageType.chat ||
              message.type == P2pMessageType.fileInfo) {
            _receivedMessagesController.add(message);
            debugPrint(
                "P2P Transport Client: Received from server: ${message.type}");
          }
        } catch (e) {
          debugPrint(
              "P2P Transport Client: Error parsing server message: $e\nData: $data");
        }
      },
      onDone: () {
        debugPrint("P2P Transport Client: Disconnected from server.");
        _isConnected = false;
        _socket = null;
        _clientList = []; // Clear client list on disconnect
        if (!_clientListController.isClosed) {
          _clientListController.add(_clientList); // Notify UI
        }
        _socketSubscription = null;
        // Optionally add a disconnected state to the stream or a separate callback
      },
      onError: (error) {
        debugPrint("P2P Transport Client: Socket error: $error");
        _isConnected = false;
        _socket = null;
        _clientList = []; // Clear client list on error
        if (!_clientListController.isClosed) {
          _clientListController.add(_clientList); // Notify UI
        }
        _socketSubscription = null;
        // Optionally add an error state to the stream
      },
      cancelOnError: true, // Close stream on error
    );

    debugPrint(
        'P2P Transport Client: Connection established and listener set up.');
  }

  /// Sends a [message] to the host server.
  ///
  /// Returns `true` if the message was sent, `false` if the socket is not connected.
  Future<bool> send(P2pMessage message) async {
    if (isConnected) {
      try {
        _socket!.add(message.toJsonString());
        debugPrint(
            "P2P Transport Client: Sent message type '${message.type}' to server.");
        return true;
      } catch (e) {
        debugPrint("P2P Transport Client: Error sending message: $e");
        // Consider attempting to reconnect or marking as disconnected
        _isConnected = false;
        await disconnect(); // Attempt cleanup
        return false;
      }
    } else {
      debugPrint(
          "P2P Transport Client: Cannot send message, socket not connected.");
      return false;
    }
  }

  /// Disconnects from the host server and closes streams.
  Future<void> disconnect() async {
    debugPrint("P2P Transport Client: Disconnecting...");
    // Cancel listener first
    await _socketSubscription?.cancel();
    _socketSubscription = null;

    // Close socket
    await _socket?.close().catchError((e) {
      debugPrint("P2P Transport Client: Error closing socket: $e");
    });
    _socket = null;
    _isConnected = false;

    // Clear client list and notify
    _clientList.clear();
    if (!_clientListController.isClosed) {
      _clientListController.add(_clientList); // Notify UI
    }

    debugPrint("P2P Transport Client: Disconnected.");
  }

  /// Cleans up resources, including closing the stream controllers. Call this
  /// when the client instance is permanently disposed.
  Future<void> dispose() async {
    await disconnect(); // Ensure disconnected
    // Close stream controllers if not already closed
    if (!_receivedMessagesController.isClosed) {
      await _receivedMessagesController.close();
    }
    if (!_clientListController.isClosed) {
      await _clientListController.close(); // Close the client list controller
    }
    debugPrint("P2P Transport Client: Disposed.");
  }
}
