import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'; // For debugPrint

enum SocketMessagetype { chat, fileInfo, clientList, decodeError, unknown }

/// A simple message class that can be serialized to/from JSON.
/// It includes basic fields: [senderId] (identifies the sender, e.g., client hashcode or 'server'),
/// [type] (application-defined message type), and [payload] (the actual data).
/// Optionally, it can include a list of clients (useful for broadcasting the client list).
@immutable
class SocketMessage {
  /// Identifier for the sender (e.g., client hashcode, 'server', or a custom ID).
  final String senderId;

  /// Application-defined type for the message (e.g., 'chat', 'fileInfo', 'clientList').
  final SocketMessagetype type;

  /// The actual content/data of the message. Can be any JSON-encodable object.
  /// For binary data, consider Base64 encoding it into a string here, or use a different transport mechanism.
  final dynamic payload;

  /// Optional list of client identifiers, typically used by the server to inform clients about connections.
  final List<String>? clients;

  const SocketMessage({
    required this.senderId,
    required this.type,
    required this.payload,
    this.clients,
  });

  /// Deserialize a SocketMessage instance from a JSON map.
  factory SocketMessage.fromJson(Map<String, dynamic> json) {
    return SocketMessage(
      senderId: json['senderId'] as String? ?? 'unknown',
      type: json['type'] as SocketMessagetype? ?? SocketMessagetype.unknown,
      payload: json['payload'], // Keep payload as dynamic
      clients:
          json['clients'] != null ? List<String>.from(json['clients']) : null,
    );
  }

  /// Deserialize a SocketMessage instance from a JSON string.
  factory SocketMessage.fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return SocketMessage.fromJson(jsonMap);
    } catch (e) {
      debugPrint("Error decoding SocketMessage from string: $e");
      // Return a default error message or rethrow, depending on desired handling
      return SocketMessage(
        senderId: 'error',
        type: SocketMessagetype.decodeError,
        payload: jsonString,
      );
    }
  }

  /// Serialize the SocketMessage instance to a JSON map.
  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'type': type,
        'payload': payload, // Assumes payload is JSON-encodable
        if (clients != null) 'clients': clients,
      };

  /// Serialize the SocketMessage instance to a JSON string.
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
    return 'SocketMessage(senderId: $senderId, type: $type, payload: $payloadSummary, clients: $clients)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SocketMessage &&
        other.senderId == senderId &&
        other.type == type &&
        // Note: Deep equality check for payload might be needed if it's complex
        other.payload == payload &&
        listEquals(other.clients, clients);
  }

  @override
  int get hashCode =>
      Object.hash(senderId, type, payload, Object.hashAll(clients ?? []));
}

/// The host class for P2P transport using WebSockets.
///
/// It creates a WebSocket server on the specified [hostIp] and attempts to bind
/// starting from [defaultPort], trying subsequent ports if the default is busy.
/// It manages connected clients and facilitates broadcasting messages.
class P2pTransportHost {
  final String hostIp;
  final int defaultPort;
  HttpServer? _server;
  int? _portInUse;

  /// Map storing connected clients, using their hash code string as the key.
  final Map<String, WebSocket> _clients = {};

  /// Stream controller for broadcasting received messages from clients.
  final StreamController<SocketMessage> _receivedMessagesController =
      StreamController<SocketMessage>.broadcast();

  /// Stream controller for broadcasting client connection/disconnection events.
  /// Emits the current list of client IDs.
  final StreamController<List<String>> _clientListController =
      StreamController<List<String>>.broadcast();

  /// Public stream of messages received from any connected client.
  Stream<SocketMessage> get receivedMessages =>
      _receivedMessagesController.stream;

  /// Public stream emitting the updated list of connected client IDs whenever a
  /// client connects or disconnects.
  Stream<List<String>> get clientListStream => _clientListController.stream;

  /// The actual port the server is listening on after successful binding.
  /// Null if the server is not running.
  int? get portInUse => _portInUse;

  P2pTransportHost({required this.hostIp, required this.defaultPort});

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
        _server = await HttpServer.bind(hostIp, port);
        _portInUse = port;
        debugPrint("P2P Transport Host: Server started on $hostIp:$_portInUse");
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
            _handleClientConnect(websocket);
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
  void _handleClientConnect(WebSocket client) {
    final clientId = client.hashCode.toString();
    debugPrint("P2P Transport Host: Client connected: $clientId");
    _clients[clientId] = client;

    // Notify listeners about the updated client list.
    _broadcastClientListUpdate();

    // Listen for messages coming from this specific client.
    client.listen(
      (data) {
        try {
          // Assume data is a JSON string representing SocketMessage
          final message = SocketMessage.fromJsonString(data as String);
          // Add the received message to the public stream.
          if (message.type == SocketMessagetype.chat ||
              message.type == SocketMessagetype.fileInfo) {
            _receivedMessagesController.add(message);
          }
          debugPrint(
              "P2P Transport Host: Received from $clientId: ${message.type}");
        } catch (e) {
          debugPrint(
              "P2P Transport Host: Error parsing message from $clientId: $e\nData: $data");
          // Optionally send an error back to the client or just log it.
        }
      },
      onDone: () {
        debugPrint("P2P Transport Host: Client disconnected: $clientId");
        _clients.remove(clientId);
        // Notify listeners about the updated client list.
        _broadcastClientListUpdate();
      },
      onError: (error) {
        debugPrint(
            "P2P Transport Host: Error on client socket $clientId: $error");
        // Assume error means disconnection.
        _clients.remove(clientId);
        _broadcastClientListUpdate();
        // Ensure socket is closed if possible
        client.close().catchError((_) => null);
      },
      cancelOnError: true, // Close the stream on error
    );
  }

  /// Sends the current list of client IDs to the client list stream controller.
  void _broadcastClientListUpdate() {
    final currentClientIds = _clients.keys.toList();
    _clientListController.add(currentClientIds);
    debugPrint(
        "P2P Transport Host: Broadcasting client list update: $currentClientIds");
    //  send this list as a SocketMessage to all clients
    broadcast(SocketMessage(
      senderId: 'server',
      type: SocketMessagetype.clientList,
      payload: currentClientIds,
    ));
  }

  /// Broadcasts a [message] to all connected clients.
  ///
  /// - [message]: The [SocketMessage] to send.
  /// - [excludeClientId]: Optional ID of a client to exclude from the broadcast (e.g., the original sender).
  Future<void> broadcast(SocketMessage message,
      {String? excludeClientId}) async {
    if (_server == null) {
      debugPrint("P2P Transport Host: Cannot broadcast, server not running.");
      return;
    }
    final msgString = message.toJsonString();
    int sentCount = 0;
    _clients.forEach((clientId, client) {
      if (clientId != excludeClientId && client.readyState == WebSocket.open) {
        try {
          client.add(msgString);
          sentCount++;
        } catch (e) {
          debugPrint(
              "P2P Transport Host: Error sending broadcast to $clientId: $e");
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
  /// - [message]: The [SocketMessage] to send.
  ///
  /// Returns `true` if the client was found and message was sent, `false` otherwise.
  Future<bool> sendToClient(String clientId, SocketMessage message) async {
    if (_server == null) {
      debugPrint("P2P Transport Host: Cannot send, server not running.");
      return false;
    }
    final client = _clients[clientId];
    if (client != null && client.readyState == WebSocket.open) {
      try {
        client.add(message.toJsonString());
        debugPrint(
            "P2P Transport Host: Sent message type '${message.type}' to $clientId.");
        return true;
      } catch (e) {
        debugPrint(
            "P2P Transport Host: Error sending direct message to $clientId: $e");
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
    await _receivedMessagesController.close();
    await _clientListController.close();

    // Close all client connections
    for (var client in _clients.values) {
      await client.close().catchError((e) {
        debugPrint("P2P Transport Host: Error closing client socket: $e");
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
  WebSocket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false; // Flag to prevent concurrent connection attempts
  StreamSubscription? _socketSubscription;

  /// Stream controller for broadcasting messages received from the server.
  final StreamController<SocketMessage> _receivedMessagesController =
      StreamController<SocketMessage>.broadcast();

  /// Stream controller for broadcasting client connection/disconnection events.
  /// Emits the current list of client IDs.
  final StreamController<List<String>> _clientListController =
      StreamController<List<String>>.broadcast();

  /// Public stream of messages received from the server.
  Stream<SocketMessage> get receivedMessages =>
      _receivedMessagesController.stream;

  /// Public stream emitting the updated list of connected client IDs whenever a
  /// client connects or disconnects.
  Stream<List<String>> get clientListStream => _clientListController.stream;

  /// Returns `true` if the client is currently connected to the server.
  bool get isConnected => _isConnected && _socket?.readyState == WebSocket.open;

  P2pTransportClient({required this.hostIp, required this.defaultPort});

  /// Attempts to connect to the host WebSocket server.
  ///
  /// Tries to connect to [hostIp] starting at [defaultPort], incrementing the port
  /// up to 10 times if the connection fails.
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
      final url = "ws://$hostIp:$port";
      try {
        debugPrint("P2P Transport Client: Attempting to connect to $url...");
        // Add a timeout to WebSocket.connect to prevent indefinite hangs
        tempSocket =
            await WebSocket.connect(url).timeout(const Duration(seconds: 3));
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
      (data) {
        try {
          // Assume data is a JSON string representing SocketMessage
          final message = SocketMessage.fromJsonString(data as String);
          // Add the received message to the public stream.
          if (message.type == SocketMessagetype.clientList) {
            _clientListController.add(message.payload as List<String>);
          } else if (message.type == SocketMessagetype.chat ||
              message.type == SocketMessagetype.fileInfo) {
            _receivedMessagesController.add(message);
          }
          debugPrint(
              "P2P Transport Client: Received from server: ${message.type}");
        } catch (e) {
          debugPrint(
              "P2P Transport Client: Error parsing server message: $e\nData: $data");
        }
      },
      onDone: () {
        debugPrint("P2P Transport Client: Disconnected from server.");
        _isConnected = false;
        _socket = null;
        _socketSubscription = null;
        // Optionally add a disconnected state to the stream or a separate callback
      },
      onError: (error) {
        debugPrint("P2P Transport Client: Socket error: $error");
        _isConnected = false;
        _socket = null;
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
  Future<bool> send(SocketMessage message) async {
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

    // Close stream controller if it's no longer needed (depends on lifecycle)
    // If the client instance can be reused, don't close it here.
    // If dispose() is the final cleanup, close it there.
    // await _receivedMessagesController.close(); // Close here if client instance is discarded after disconnect

    debugPrint("P2P Transport Client: Disconnected.");
  }

  /// Cleans up resources, including closing the stream controller. Call this
  /// when the client instance is permanently disposed.
  Future<void> dispose() async {
    await disconnect(); // Ensure disconnected
    await _receivedMessagesController.close(); // Close the stream controller
    debugPrint("P2P Transport Client: Disposed.");
  }
}
