import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'flutter_p2p_connection_platform_interface.dart';

class FlutterP2pConnection {
  final int _port = 4045;
  final int _code = 4045;
  HttpServer? _server;
  final List<WebSocket?> _sockets = [];

  Future<String?> _myIPAddress() async {
    List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: true,
    );
    List<NetworkInterface> addr = interfaces
        .where((e) => e.addresses.first.address.indexOf('192.') == 0)
        .toList();

    if (addr.isNotEmpty) {
      return addr.first.addresses.first.address;
    } else {
      return null;
    }
  }

  Future<String?> getPlatformVersion() {
    return FlutterP2pConnectionPlatform.instance.getPlatformVersion();
  }

  Future<bool?> initialize() {
    return FlutterP2pConnectionPlatform.instance.initialize();
  }

  Future<bool?> discover() {
    return FlutterP2pConnectionPlatform.instance.discover();
  }

  Future<bool?> stopDiscovery() {
    return FlutterP2pConnectionPlatform.instance.stopDiscovery();
  }

  Future<bool?> connect(String address) {
    return FlutterP2pConnectionPlatform.instance.connect(address);
  }

  // Future<bool?> disconnect() {
  //   return FlutterP2pConnectionPlatform.instance.disconnect();
  // }

  Future<List<DiscoveredPeers>> fetchPeers() async {
    List<String>? list =
        await FlutterP2pConnectionPlatform.instance.fetchPeers();
    if (list == null) return [];
    List<DiscoveredPeers>? peers = [];
    for (String p in list) {
      Map<String, dynamic>? json = jsonDecode(p);
      if (json != null) {
        peers.add(
          DiscoveredPeers(
            deviceName: json["deviceName"],
            deviceAddress: json["deviceAddress"],
            isGroupOwner: json["isGroupOwner"],
            isServiceDiscoveryCapable: json["isServiceDiscoveryCapable"],
            primaryDeviceType: json["primaryDeviceType"],
            secondaryDeviceType: json["secondaryDeviceType"],
            status: json["status"],
          ),
        );
      }
    }
    return peers;
  }

  Stream<List<DiscoveredPeers>> streamPeers() {
    const peersChannel = EventChannel("flutter_p2p_connection_foundPeers");
    return peersChannel.receiveBroadcastStream().map((peers) {
      List<DiscoveredPeers> p = [];
      if (peers == null) return p;
      for (var obj in peers) {
        Map<String, dynamic>? json = jsonDecode(obj);
        if (json != null) {
          p.add(
            DiscoveredPeers(
              deviceName: json["deviceName"],
              deviceAddress: json["deviceAddress"],
              isGroupOwner: json["isGroupOwner"],
              isServiceDiscoveryCapable: json["isServiceDiscoveryCapable"],
              primaryDeviceType: json["primaryDeviceType"],
              secondaryDeviceType: json["secondaryDeviceType"],
              status: json["status"],
            ),
          );
        }
      }
      return p;
    });
  }

  Stream<WifiP2PInfo> streamWifiP2PInfo() {
    const peersChannel = EventChannel("flutter_p2p_connection_connectedPeers");
    return peersChannel.receiveBroadcastStream().map((peers) {
      if (peers == "null") {
        return const WifiP2PInfo(
          isConnected: false,
          isGroupOwner: false,
          groupOwnerAddress: null,
          groupFormed: false,
          clients: [],
        );
      }
      Map<String, dynamic>? json = jsonDecode(peers);
      if (json != null) {
        List<Client> clients = [];
        if ((json["clients"] as List).isNotEmpty) {
          for (var i in json["clients"]) {
            Map<String, dynamic> client = (i as Map<String, dynamic>);
            clients.add(Client(
              deviceName: client["deviceName"],
              deviceAddress: client["deviceAddress"],
              isGroupOwner: client["isGroupOwner"],
              isServiceDiscoveryCapable: client["isServiceDiscoveryCapable"],
              primaryDeviceType: client["primaryDeviceType"],
              secondaryDeviceType: client["secondaryDeviceType"],
              status: client["status"],
            ));
          }
        }
        return WifiP2PInfo(
          isConnected: json["isConnected"],
          isGroupOwner: json["isGroupOwner"],
          groupOwnerAddress: json["groupOwnerAddress"],
          groupFormed: json["groupFormed"],
          clients: clients,
        );
      } else {
        return const WifiP2PInfo(
          isConnected: false,
          isGroupOwner: false,
          groupOwnerAddress: null,
          groupFormed: false,
          clients: [],
        );
      }
    });
  }

  Future<bool?> register() {
    return FlutterP2pConnectionPlatform.instance.resume();
  }

  Future<bool?> unregister() {
    return FlutterP2pConnectionPlatform.instance.pause();
  }

  Future<bool?> createGroup() {
    return FlutterP2pConnectionPlatform.instance.createGroup();
  }

  Future<bool?> removeGroup() {
    return FlutterP2pConnectionPlatform.instance.removeGroup();
  }

  Future<WifiP2PGroupInfo?> groupInfo() async {
    String? gi = await FlutterP2pConnectionPlatform.instance
        .groupInfo()
        .timeout(const Duration(seconds: 1), onTimeout: () => null);
    if (gi == null) return null;
    Map<String, dynamic>? json = jsonDecode(gi);
    if (json == null) return null;
    List<Client> clients = [];
    if ((json["clients"] as List).isNotEmpty) {
      for (var i in json["clients"]) {
        Map<String, dynamic> client = (i as Map<String, dynamic>);
        clients.add(Client(
          deviceName: client["deviceName"],
          deviceAddress: client["deviceAddress"],
          isGroupOwner: client["isGroupOwner"],
          isServiceDiscoveryCapable: client["isServiceDiscoveryCapable"],
          primaryDeviceType: client["primaryDeviceType"],
          secondaryDeviceType: client["secondaryDeviceType"],
          status: client["status"],
        ));
      }
    }
    return WifiP2PGroupInfo(
      isGroupOwner: json["isGroupOwner"],
      passPhrase: json["passPhrase"],
      groupNetworkName: json["groupNetworkName"],
      clients: clients,
    );
  }

  Future<bool> startSocket({
    required String groupOwnerAddress,
    required void Function(String address) onConnect,
    required void Function(dynamic) onRequest,
  }) async {
    try {
      closeSocket();
      groupOwnerAddress = groupOwnerAddress.replaceFirst("/", "");
      HttpServer httpServer = await HttpServer.bind(
        groupOwnerAddress,
        _port,
        shared: true,
      );
      httpServer.listen(
        (req) async {
          if (req.uri.path == '/ws') {
            WebSocket socketServer = await WebSocketTransformer.upgrade(req);
            _sockets.add(socketServer);
            socketServer.listen(
              onRequest,
              cancelOnError: true,
              onDone: () {
                debugPrint("FlutterP2pConnection: Closed Socket!");
                socketServer.close(_code);
                _sockets.removeWhere(
                    (e) => e == null ? true : e.closeCode == _code);
              },
            );
            onConnect("${httpServer.address.address}:${httpServer.port}");
            debugPrint("FlutterP2pConnection: A device connected to Socket!");
          } else if (req.uri.path == '/file') {}
        },
        cancelOnError: true,
        onError: (error, stack) {},
        onDone: () {
          closeSocket();
        },
      );
      _server = httpServer;
      debugPrint("FlutterP2pConnection: Opened a Socket!");
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectToSocket({
    required String groupOwnerAddress,
    required void Function(String address) onConnect,
    required void Function(dynamic) onRequest,
  }) async {
    try {
      closeSocket();
      if (groupOwnerAddress.isNotEmpty) {
        groupOwnerAddress = groupOwnerAddress.replaceFirst("/", "");
        WebSocket socket =
            await WebSocket.connect('ws://$groupOwnerAddress:$_port/ws');
        _sockets.add(socket);
        debugPrint(
            "FlutterP2pConnection: Connected to Socket: $groupOwnerAddress:$_port");
        socket.listen(
          onRequest,
          cancelOnError: true,
          onDone: () {
            debugPrint("FlutterP2pConnection: Closed Socket!");
            socket.close(_code);
            _sockets
                .removeWhere((e) => e == null ? true : e.closeCode == _code);
          },
        );
        HttpServer httpServer = await HttpServer.bind(
          (await _myIPAddress()) ?? "0.0.0.0",
          _port,
          shared: true,
        );
        httpServer.listen(
          (req) async {
            if (req.uri.path == '/file') {}
          },
          cancelOnError: true,
          onError: (error, stack) {},
          onDone: () {
            closeSocket();
          },
        );
        _server = httpServer;
        onConnect("$groupOwnerAddress:$_port");
        return true;
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  bool sendStringToSocket(String string) {
    try {
      for (WebSocket? socket in _sockets) {
        if (socket != null) {
          socket.add(string);
        }
      }
      return true;
    } catch (e) {
      debugPrint("FlutterP2pConnection: Tranfer error: $e");
      return false;
    }
  }

  bool closeSocket() {
    try {
      if (_server != null) _server?.close();
      for (WebSocket? socket in _sockets) {
        if (socket != null) {
          socket.close(_code);
        }
      }
      _sockets.clear();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool?> checkLocationPermission() {
    return FlutterP2pConnectionPlatform.instance.checkLocationPermission();
  }

  Future<bool?> askLocationPermission() async {
    if (await FlutterP2pConnectionPlatform.instance.checkLocationPermission() ==
        false) {
      return FlutterP2pConnectionPlatform.instance.askLocationPermission();
    } else {
      return true;
    }
  }

  Future<bool?> checkLocationEnabled() {
    return FlutterP2pConnectionPlatform.instance.checkLocationEnabled();
  }

  Future<bool?> checkGpsEnabled() {
    return FlutterP2pConnectionPlatform.instance.checkGpsEnabled();
  }

  Future<bool?> enableLocationServices() {
    return FlutterP2pConnectionPlatform.instance.enableLocationServices();
  }

  Future<bool?> checkWifiEnabled() {
    return FlutterP2pConnectionPlatform.instance.checkWifiEnabled();
  }

  Future<bool?> enableWifiServices() {
    return FlutterP2pConnectionPlatform.instance.enableWifiServices();
  }
}

class DiscoveredPeers {
  final String deviceName;
  final String deviceAddress;
  final bool isGroupOwner;
  final bool isServiceDiscoveryCapable;
  final String primaryDeviceType;
  final String secondaryDeviceType;
  final int status;
  const DiscoveredPeers({
    required this.deviceName,
    required this.deviceAddress,
    required this.isGroupOwner,
    required this.isServiceDiscoveryCapable,
    required this.primaryDeviceType,
    required this.secondaryDeviceType,
    required this.status,
  });
}

class Client {
  final String deviceName;
  final String deviceAddress;
  final bool isGroupOwner;
  final bool isServiceDiscoveryCapable;
  final String primaryDeviceType;
  final String secondaryDeviceType;
  final int status;
  const Client({
    required this.deviceName,
    required this.deviceAddress,
    required this.isGroupOwner,
    required this.isServiceDiscoveryCapable,
    required this.primaryDeviceType,
    required this.secondaryDeviceType,
    required this.status,
  });
}

class WifiP2PGroupInfo {
  final bool isGroupOwner;
  final String passPhrase;
  final String groupNetworkName;
  final List<Client> clients;
  const WifiP2PGroupInfo({
    required this.isGroupOwner,
    required this.passPhrase,
    required this.groupNetworkName,
    required this.clients,
  });
}

class WifiP2PInfo {
  final bool isConnected;
  final bool isGroupOwner;
  final String? groupOwnerAddress;
  final bool groupFormed;
  final List<Client> clients;
  const WifiP2PInfo({
    required this.isConnected,
    required this.isGroupOwner,
    required this.groupOwnerAddress,
    required this.groupFormed,
    required this.clients,
  });
}
