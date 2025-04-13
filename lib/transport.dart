import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A simple message class that can be serialized to/from JSON.
/// It includes basic fields: [sender], [type] and [content].
/// Optionally, it can include a list of clients (useful for broadcasting the client list).
class SocketMessage {
  String sender;
  String type;
  String content;
  List<String>? clients;

  SocketMessage({
    required this.sender,
    required this.type,
    required this.content,
    this.clients,
  });

  /// Deserialize a SocketMessage instance from JSON.
  factory SocketMessage.fromJson(Map<String, dynamic> json) {
    return SocketMessage(
      sender: json['sender'] ?? '',
      type: json['type'] ?? '',
      content: json['content'] ?? '',
      clients:
          json['clients'] != null ? List<String>.from(json['clients']) : null,
    );
  }

  /// Serialize the SocketMessage instance to JSON.
  Map<String, dynamic> toJson() => {
        'sender': sender,
        'type': type,
        'content': content,
        if (clients != null) 'clients': clients,
      };

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// The host class for P2P transport. It creates a WebSocket server using the
/// specified [hostIp] and [defaultPort]. If the port is already in use,
/// it increments the port number (up to 10 attempts) until it succeeds.
class P2pTransportHost {
  final String hostIp;
  final int defaultPort;
  HttpServer? _server;
  int? portInUse;
  final List<WebSocket> _clients = [];

  P2pTransportHost({required this.hostIp, required this.defaultPort});

  /// Starts the WebSocket server on the appropriate port.
  Future<void> start() async {
    int attempts = 0;
    int port = defaultPort;
    while (attempts < 10) {
      try {
        _server = await HttpServer.bind(hostIp, port);
        portInUse = port;
        print("Server started on $hostIp:$portInUse");
        break;
      } catch (e) {
        print("Port $port is in use, trying next port...");
        port++;
        attempts++;
      }
    }
    if (_server == null) {
      throw Exception("Could not bind to any port in the range.");
    }

    // Listen for incoming HTTP requests (which may be upgraded to WebSocket).
    _server!.listen((HttpRequest request) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request).then((WebSocket websocket) {
          _handleClient(websocket);
        });
      } else {
        // If not a WebSocket request, close the connection with an error code.
        request.response
          ..statusCode = HttpStatus.upgradeRequired
          ..write("WebSocket connections only")
          ..close();
      }
    });
  }

  /// Handles an individual client connection.
  void _handleClient(WebSocket client) {
    print("New client connected.");
    _clients.add(client);

    // Send the updated client list to all clients.
    _broadcastClientList();

    // Listen for messages coming from the client.
    client.listen((data) {
      try {
        // Expect the message in JSON format.
        var jsonData = jsonDecode(data);
        var message = SocketMessage.fromJson(jsonData);
        print("Received message from ${message.sender}: ${message.content}");
        // Broadcast the message to other clients (excluding the sender).
        _broadcastMessage(message, exclude: client);
      } catch (e) {
        print("Error parsing message: $e");
      }
    }, onDone: () {
      print("Client disconnected.");
      _clients.remove(client);
      _broadcastClientList();
    });
  }

  /// Broadcasts a given [message] to all connected clients.
  /// You can optionally exclude one client via [exclude] (e.g., to avoid echoing the sender).
  void _broadcastMessage(SocketMessage message, {WebSocket? exclude}) {
    var msgString = jsonEncode(message.toJson());
    for (var client in _clients) {
      if (client != exclude) {
        client.add(msgString);
      }
    }
  }

  /// Constructs and broadcasts the list of connected clients.
  /// Here, client identifiers are represented as the string value of their hash code.
  void _broadcastClientList() {
    List<String> clientAddresses =
        _clients.map((client) => client.hashCode.toString()).toList();
    SocketMessage message = SocketMessage(
      sender: "server",
      type: "clientList",
      content: "Updated client list",
      clients: clientAddresses,
    );
    _broadcastMessage(message);
  }

  /// Stops the server and clears the client list.
  Future<void> stop() async {
    await _server?.close(force: true);
    _clients.clear();
  }
}

/// The client class for P2P transport. It attempts to establish a connection
/// to the server at [hostIp] starting with the [defaultPort]. If the connection
/// is not found, it increments the port number (up to 10 attempts) until a connection is made.
class P2pTransportClient {
  final String hostIp;
  final int defaultPort;
  WebSocket? _socket;

  P2pTransportClient({required this.hostIp, required this.defaultPort});

  /// Attempts to connect to the host server.
  Future<void> connect() async {
    int attempts = 0;
    int port = defaultPort;
    bool connected = false;
    while (attempts < 10 && !connected) {
      try {
        _socket = await WebSocket.connect("ws://$hostIp:$port");
        print("Connected to server at ws://$hostIp:$port");
        connected = true;
      } catch (e) {
        print("Unable to connect at port $port. Trying next port...");
        port++;
        attempts++;
      }
    }
    if (!connected) {
      throw Exception("Could not connect to server on any port in the range.");
    }

    // Listen for messages from the server.
    _socket!.listen((data) {
      try {
        var jsonData = jsonDecode(data);
        var message = SocketMessage.fromJson(jsonData);
        _handleServerMessage(message);
      } catch (e) {
        print("Error parsing server message: $e");
      }
    }, onDone: () {
      print("Disconnected from server.");
    });
  }

  /// Handles incoming messages from the server.
  void _handleServerMessage(SocketMessage message) {
    if (message.type == "clientList") {
      print("Received updated client list: ${message.clients}");
    } else {
      print("Message from ${message.sender}: ${message.content}");
    }
  }

  /// Sends a [message] to the host server.
  void sendMessage(SocketMessage message) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(message.toJson()));
    } else {
      print("Socket not connected.");
    }
  }

  /// Disconnects from the host server.
  Future<void> disconnect() async {
    await _socket?.close();
  }
}

/// --------------------------
/// Example Usage:
/// --------------------------
///
/// void main() async {
///   // Start the host
///   var host = P2pTransportHost(hostIp: '127.0.0.1', defaultPort: 8080);
///   await host.start();
///
///   // Connect a client
///   var client = P2pTransportClient(hostIp: '127.0.0.1', defaultPort: 8080);
///   await client.connect();
///
///   // Send a message from client to host
///   var message = SocketMessage(sender: 'client1', type: 'chat', content: 'Hello, world!');
///   client.sendMessage(message);
/// }
/// 
/// // Note: To run this code in a real-world scenario, you might execute the host
/// // in one Dart isolate or process, and the client in another.
/// 
/// --------------------------

