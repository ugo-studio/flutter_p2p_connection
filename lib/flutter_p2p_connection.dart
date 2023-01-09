import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:mime_type/mime_type.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';

class FlutterP2pConnection {
  final int _port = 4045;
  final int _code = 4045;
  int _maxDownloads = 2;
  final String _fileTransferCode = "~~&&^^>><<{|MeSsAgEs|}>><<^^&&~~";
  final String _groupSeparation = "~~&&^^>><<{||||}>><<^^&&~~";
  final List<WebSocket?> _sockets = [];
  final List<FutureDownload> _futureDownloads = [];
  final Dio dio = Dio();
  String _ipAddress = '';
  String _as = '';
  HttpServer? _server;

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
    required String downloadPath,
    int maxConcurrentDownloads = 2,
    required void Function(String, String) onConnect,
    required void Function(TransferUpdate transfer) transferUpdate,
    required void Function(dynamic) onRequest,
  }) async {
    if (_server != null) return true;
    try {
      closeSocket();
      _maxDownloads = maxConcurrentDownloads;
      groupOwnerAddress = groupOwnerAddress.replaceFirst("/", "");
      _ipAddress = groupOwnerAddress;
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
              (event) {
                // SHARE TO CLIENTS
                for (WebSocket? socket in _sockets) {
                  if (socket != null) {
                    socket.add(event);
                  }
                }
                if (event.toString().startsWith(_fileTransferCode)) {
                  // ADD TO FUTURE DOWNLOADS
                  for (String msg in Uri.decodeComponent(event.toString())
                      .split(_groupSeparation)) {
                    _futureDownloads.add(
                      FutureDownload(
                        url: msg.toString().replaceFirst(_fileTransferCode, ""),
                        downloading: false,
                        id: Random().nextInt(10000),
                      ),
                    );
                  }
                } else {
                  // RECEIVE MESSAGE
                  onRequest(event
                      .toString()
                      .substring(event.toString().indexOf('@') + 1));
                }
              },
              cancelOnError: true,
              onDone: () {
                debugPrint("FlutterP2pConnection: Closed Socket!");
                socketServer.close(_code);
                _sockets.removeWhere(
                    (e) => e == null ? true : e.closeCode == _code);
              },
            );
            onConnect("${req.uri.queryParameters['as']}",
                "${req.uri.queryParameters['ip']}:$_port");
            debugPrint(
                "FlutterP2pConnection: ${req.uri.queryParameters['as']} connected to Socket!");

            // HANDLE FILE REQUEST
          } else if (req.uri.path == '/file' && req.uri.hasQuery) {
            _handleFileRequest(req, transferUpdate);
          }
        },
        cancelOnError: true,
        onError: (error, stack) {},
        onDone: () {
          closeSocket();
        },
      );
      _server = httpServer;
      debugPrint("FlutterP2pConnection: Opened a Socket!");
      _listenThenDownload(transferUpdate, downloadPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectToSocket({
    required String groupOwnerAddress,
    String? as,
    int maxConcurrentDownloads = 2,
    required String downloadPath,
    required void Function(String address) onConnect,
    required void Function(TransferUpdate transfer) transferUpdate,
    required void Function(dynamic) onRequest,
  }) async {
    if (_server != null) return true;
    try {
      closeSocket();
      _maxDownloads = maxConcurrentDownloads;
      _ipAddress = (await _myIPAddress()) ?? "0.0.0.0";
      _as = as ??
          await FlutterP2pConnectionPlatform.instance.getPlatformModel() ??
          (Random().nextInt(5000) + 1000).toString();
      if (groupOwnerAddress.isNotEmpty) {
        groupOwnerAddress = groupOwnerAddress.replaceFirst("/", "");
        HttpServer httpServer = await HttpServer.bind(
          _ipAddress,
          _port,
          shared: true,
        );
        httpServer.listen(
          (req) async {
            // HANDLE FILE REQUEST
            if (req.uri.path == '/file' && req.uri.hasQuery) {
              _handleFileRequest(req, transferUpdate);
            }
          },
          cancelOnError: true,
          onError: (error, stack) {},
          onDone: () {
            closeSocket();
          },
        );
        _server = httpServer;
        WebSocket socket = await WebSocket.connect(
            'ws://$groupOwnerAddress:$_port/ws?as=$_as&ip=$_ipAddress');
        _sockets.add(socket);
        debugPrint(
            "FlutterP2pConnection: Connected to Socket: $groupOwnerAddress:$_port");
        socket.listen(
          (event) {
            if (event.toString().startsWith(_fileTransferCode)) {
              // ADD TO FUTURE DOWNLOADS
              for (String msg in Uri.decodeComponent(event.toString())
                  .split(_groupSeparation)) {
                String url = msg.toString().replaceFirst(_fileTransferCode, "");
                if (!(Uri.decodeComponent(url)
                    .startsWith("http://$_ipAddress:$_port/"))) {
                  _futureDownloads.add(
                    FutureDownload(
                      url: url,
                      downloading: false,
                      id: Random().nextInt(10000),
                    ),
                  );
                }
              }
            } else if (event.toString().split("@").first !=
                _ipAddress.split(".").last) {
              // RECEIVE MESSGAE
              onRequest(event
                  .toString()
                  .substring(event.toString().indexOf('@') + 1));
            }
          },
          cancelOnError: true,
          onDone: () {
            closeSocket();
          },
        );
        onConnect("$groupOwnerAddress:$_port");
        _listenThenDownload(transferUpdate, downloadPath);
        return true;
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  void _listenThenDownload(
    void Function(TransferUpdate) transferUpdate,
    String downloadPath,
  ) async {
    while (_server != null) {
      await Future.delayed(const Duration(seconds: 2));
      if (_futureDownloads.isNotEmpty) {
        if (_futureDownloads.where((i) => i.downloading == true).isEmpty) {
          if (_futureDownloads.length <= _maxDownloads) {
            for (int i = 0; i < _futureDownloads.length; i++) {
              _futureDownloads[i].downloading = true;
              FutureDownload download = _futureDownloads[i];
              _downloadFile(
                download.url,
                transferUpdate,
                downloadPath,
                () {
                  _futureDownloads.removeWhere((i) => i.id == download.id);
                },
              );
            }
          } else {
            for (int i = 0; i < _maxDownloads; i++) {
              _futureDownloads[i].downloading = true;
              FutureDownload download = _futureDownloads[i];
              _downloadFile(
                download.url,
                transferUpdate,
                downloadPath,
                () {
                  _futureDownloads.removeWhere((i) => i.id == download.id);
                },
              );
            }
          }
        }
      }
    }
  }

  Future _handleFileRequest(
    HttpRequest req,
    void Function(TransferUpdate) transferUpdate,
  ) async {
    String path = Uri.decodeComponent(req.uri.queryParameters['path'] ?? "");
    File file = File(path);
    List m = (mime(path.split("/").last) ?? "text/plain").split("/");
    String filename = path.split("/").last;
    int count = 0;
    try {
      if (path.isEmpty) {
        req.response
          ..addError(const HttpException("not found"))
          ..close();
        transferUpdate(
          TransferUpdate(
            filename: filename,
            path: path,
            count: count,
            total: await file.length(),
            completed: true,
            failed: true,
            receiving: false,
          ),
        );
      } else {
        req.response
          ..headers.contentType = ContentType(m.first, m.last)
          ..headers.contentLength = await file.length()
          ..addStream(
            _fileStream(
              file: file,
              filename: filename,
              transferUpdate: transferUpdate,
              updateCount: (c) => count = c,
            ),
          ).whenComplete(() async {
            req.response.close();
            transferUpdate(
              TransferUpdate(
                filename: filename,
                path: path,
                count: count,
                total: await file.length(),
                completed: true,
                failed: false,
                receiving: false,
              ),
            );
          });
      }
    } catch (_) {
      req.response
        ..addError(const HttpException("not found"))
        ..close();
      transferUpdate(
        TransferUpdate(
          filename: filename,
          path: path,
          count: count,
          total: await file.length(),
          completed: true,
          failed: true,
          receiving: false,
        ),
      );
    }
  }

  Stream<List<int>> _fileStream({
    required File file,
    required String filename,
    required void Function(TransferUpdate) transferUpdate,
    required void Function(int) updateCount,
  }) async* {
    int total = await file.length();
    int count = 0;
    await for (List<int> chip in file.openRead()) {
      count += (chip as Uint8List).lengthInBytes;
      updateCount(count);
      //update transfer
      transferUpdate(
        TransferUpdate(
          filename: filename,
          path: file.path,
          count: count,
          total: total,
          completed: false,
          failed: false,
          receiving: false,
        ),
      );
      yield chip;
      if (count == total) break;
    }
  }

  Future _downloadFile(
    String url,
    void Function(TransferUpdate) transferUpdate,
    String downloadPath,
    void Function() done,
  ) async {
    if (Uri.decodeComponent(url).startsWith("http://$_ipAddress:$_port/")) {
      done();
      return;
    }
    String filename =
        await _setName(Uri.decodeComponent(url).split("/").last, downloadPath);
    int count = 0;
    int total = 0;
    try {
      dio.download(
        url,
        "$downloadPath$filename",
        // deleteOnError: true,
        onReceiveProgress: (c, t) {
          count = c;
          total = t;
          transferUpdate(
            TransferUpdate(
              filename: filename,
              path: "$downloadPath$filename",
              count: count,
              total: total,
              completed: false,
              failed: false,
              receiving: true,
            ),
          );
        },
      ).whenComplete(
        () {
          transferUpdate(
            TransferUpdate(
              filename: filename,
              path: "$downloadPath$filename",
              count: count,
              total: total,
              completed: true,
              failed: false,
              receiving: true,
            ),
          );
          done();
        },
      );
    } catch (_) {
      transferUpdate(
        TransferUpdate(
          filename: filename,
          path: "$downloadPath$filename",
          count: count,
          total: total,
          completed: true,
          failed: true,
          receiving: true,
        ),
      );
      done();
    }
  }

  Future<String> _setName(String name, String path) async {
    try {
      if (!(await File(path + name).exists())) return name;
      int number = 1;
      String ext = name.substring(name.lastIndexOf("."));
      while (true) {
        String newName = name.replaceFirst(ext, "($number)$ext");
        if (!(await File(path + newName).exists())) return newName;
        number++;
      }
    } catch (_) {
      return name;
    }
  }

  bool sendStringToSocket(String string) {
    try {
      for (WebSocket? socket in _sockets) {
        if (socket != null) {
          socket.add("${_ipAddress.split(".").last}@$string");
        }
      }
      return true;
    } catch (e) {
      debugPrint("FlutterP2pConnection: Tranfer error: $e");
      return false;
    }
  }

  Future<bool> sendFiletoSocket(List<String> paths) async {
    try {
      List<String> donotexist =
          paths.where((path) => (File(path).existsSync()) == false).toList();
      if (donotexist.isNotEmpty) return false;
      for (WebSocket? socket in _sockets) {
        if (socket != null) {
          String msg = '';
          for (int i = 0; i < paths.length; i++) {
            msg +=
                "${_fileTransferCode}http://$_ipAddress:$_port/file?path=${Uri.encodeComponent(paths[i])}";
            if (i < paths.length - 1) msg += _groupSeparation;
          }
          socket.add(msg);
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
      _server = null;
      _sockets.clear();
      _futureDownloads.clear();
      _ipAddress = '';
      _as = '';
      debugPrint("FlutterP2pConnection: Closed Socket!");
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool?> checkLocationPermission() {
    return FlutterP2pConnectionPlatform.instance.checkLocationPermission();
  }

  Future<bool?> askLocationPermission() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) return true;
    return false;
  }

  Future<bool?> checkLocationEnabled() {
    return FlutterP2pConnectionPlatform.instance.checkLocationEnabled();
  }

  // Future<bool?> checkGpsEnabled() {
  //   return FlutterP2pConnectionPlatform.instance.checkGpsEnabled();
  // }

  Future<bool?> enableLocationServices() {
    return FlutterP2pConnectionPlatform.instance.enableLocationServices();
  }

  Future<bool?> checkWifiEnabled() {
    return FlutterP2pConnectionPlatform.instance.checkWifiEnabled();
  }

  Future<bool?> enableWifiServices() {
    return FlutterP2pConnectionPlatform.instance.enableWifiServices();
  }

  Future<bool?> checkStoragePermission() async {
    PermissionStatus status = await Permission.storage.status;
    if (status.isGranted) return true;
    return false;
  }

  Future<bool?> askStoragePermission() async {
    PermissionStatus status = await Permission.storage.request();
    if (status.isGranted) return true;
    return false;
  }

  Future<bool?> askStorageAndLocationPermission() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.storage,
    ].request();
    if ((statuses[Permission.location] as PermissionStatus).isGranted &&
        (statuses[Permission.storage] as PermissionStatus).isGranted) {
      return true;
    }
    return false;
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

class TransferUpdate {
  final String filename;
  final String path;
  final int count;
  final int total;
  final bool completed;
  final bool failed;
  final bool receiving;
  TransferUpdate({
    required this.filename,
    required this.path,
    required this.count,
    required this.total,
    required this.completed,
    required this.failed,
    required this.receiving,
  });
}

class FutureDownload {
  String url;
  bool downloading;
  int id;
  FutureDownload({
    required this.url,
    required this.downloading,
    required this.id,
  });
}
