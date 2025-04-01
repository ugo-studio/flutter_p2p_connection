// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class P2pTransport {
  final String ip;
  final int port;
  final String name;
  final bool isHost;

  // Servers
  HttpServer? _httpServer;
  WebSocketChannel? _wsChannel;

  // Host-specific properties
  final List<WebSocketChannel> _connectedClients = [];
  final Map<String, String> _clientNames = {};

  // File transfer properties
  final Map<String, String> _fileIdToPath = {};
  final Uuid _uuid = Uuid();

  P2pTransport({
    required this.ip,
    this.port = 8080,
    required this.name,
    required this.isHost,
  });

  Future<void> start() async {
    // Always start an HTTP server for file transfers
    await _startHttpServer();

    if (isHost) {
      await _startAsHost();
    } else {
      await _startAsClient();
    }
  }

  Future<void> _startHttpServer() async {
    _httpServer = await HttpServer.bind(ip, port + 1, shared: true);
    print('HTTP server running on $ip:${port + 1}');

    _httpServer!.listen((HttpRequest request) async {
      if (request.uri.path.startsWith('/file/')) {
        await _handleFileRequest(request);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
      }
    });
  }

  Future<void> _handleFileRequest(HttpRequest request) async {
    final fileId = request.uri.pathSegments.last;
    final filePath = _fileIdToPath[fileId];

    if (filePath == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found')
        ..close();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found')
        ..close();
      return;
    }

    request.response.headers.contentType = ContentType.binary;
    request.response.headers.add('Content-Disposition',
        'attachment; filename="${filePath.split("/").last}"');

    await file.openRead().pipe(request.response);
  }

  Future<void> _startAsHost() async {
    // Create WebSocket server for connections
    final server = await HttpServer.bind(ip, port, shared: true);
    print('WebSocket server running on $ip:$port');

    server.listen((HttpRequest request) {
      if (request.uri.path == '/connect') {
        // Get client name from query parameters
        final clientName = request.uri.queryParameters['name'] ?? 'Unknown';

        WebSocketTransformer.upgrade(request).then((WebSocket webSocket) {
          final channel = IOWebSocketChannel(webSocket);
          _connectedClients.add(channel);

          // Store client name
          _clientNames[channel.hashCode.toString()] = clientName;

          print('Client connected: $clientName');

          // Send welcome message
          _sendMessage(channel, {
            'type': 'system',
            'message': 'Welcome to the server, $clientName',
          });

          // Broadcast new client joined
          _broadcastMessage({
            'type': 'system',
            'message': '$clientName joined the chat',
            'sender': 'system',
          }, except: channel);

          channel.stream.listen(
            (message) => _handleClientMessage(channel, message),
            onDone: () => _handleClientDisconnect(channel),
            onError: (error) => print('Error: $error'),
          );
        });
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
      }
    });
  }

  void _handleClientMessage(WebSocketChannel channel, dynamic message) {
    final Map<String, dynamic> data = jsonDecode(message);
    final clientName = _clientNames[channel.hashCode.toString()] ?? 'Unknown';

    // Add sender information
    data['sender'] = clientName;

    // Process the message
    print('Message from $clientName: ${data['message']}');

    // Broadcast the message to all clients
    _broadcastMessage(data);
  }

  void _handleClientDisconnect(WebSocketChannel channel) {
    final clientName = _clientNames[channel.hashCode.toString()] ?? 'Unknown';
    _connectedClients.remove(channel);
    _clientNames.remove(channel.hashCode.toString());

    print('Client disconnected: $clientName');

    // Broadcast client left
    _broadcastMessage({
      'type': 'system',
      'message': '$clientName left the chat',
      'sender': 'system',
    });
  }

  void _broadcastMessage(Map<String, dynamic> data,
      {WebSocketChannel? except}) {
    final messageStr = jsonEncode(data);

    for (var client in _connectedClients) {
      if (except != null && client == except) continue;
      _sendMessage(client, data);
    }
  }

  Future<void> _startAsClient() async {
    // Connect to host
    final uri = Uri.parse('ws://${ip}:$port/connect?name=$name');
    final wsUrl = uri.toString();
    print(wsUrl);

    try {
      final socket = await WebSocket.connect(wsUrl);
      _wsChannel = IOWebSocketChannel(socket);

      print('Connected to host at $wsUrl');

      _wsChannel!.stream.listen(
        _handleHostMessage,
        onDone: () => print('Disconnected from host'),
        onError: (error) => print('Error: $error'),
      );
    } catch (e) {
      print('Failed to connect to host: $e');
      rethrow;
    }
  }

  void _handleHostMessage(dynamic message) {
    final Map<String, dynamic> data = jsonDecode(message);

    if (data['type'] == 'file') {
      print('File received: ${data['filename']}');
      // Handle file info, can download later
    } else {
      print('Message: ${data['message']} from ${data['sender']}');
    }
  }

  // Send text message
  void sendTextMessage(String message) {
    final data = {
      'type': 'text',
      'message': message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (isHost) {
      // Host broadcasts the message to all clients
      data['sender'] = name;
      _broadcastMessage(data);
    } else if (_wsChannel != null) {
      // Client sends message to host
      _sendMessage(_wsChannel!, data);
    }
  }

  // Share file
  Future<void> shareFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print('File not found: $filePath');
      return;
    }

    final filename = filePath.split('/').last;
    final fileSize = await file.length();
    final fileId = _uuid.v4();

    // Store file path with ID
    _fileIdToPath[fileId] = filePath;

    final fileData = {
      'type': 'file',
      'fileId': fileId,
      'filename': filename,
      'fileSize': fileSize,
      'url': 'http://$ip:${port + 1}/file/$fileId',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sender': name,
    };

    if (isHost) {
      // Host broadcasts file info to all clients
      _broadcastMessage(fileData);
    } else if (_wsChannel != null) {
      // Client sends file info to host
      _sendMessage(_wsChannel!, fileData);
    }
  }

  // Download a file
  Future<void> downloadFile(String url, String savePath) async {
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      final file = File(savePath);
      final sink = file.openWrite();
      await response.pipe(sink);

      print('File downloaded to $savePath');
    } catch (e) {
      print('Error downloading file: $e');
    }
  }

  void _sendMessage(WebSocketChannel channel, Map<String, dynamic> data) {
    channel.sink.add(jsonEncode(data));
  }

  Future<void> stop() async {
    if (isHost) {
      for (var client in _connectedClients) {
        client.sink.close();
      }
      _connectedClients.clear();
      _clientNames.clear();
    } else if (_wsChannel != null) {
      _wsChannel!.sink.close();
    }

    await _httpServer?.close();
    print('P2P transport stopped');
  }
}
