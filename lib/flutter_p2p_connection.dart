// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_p2p_connection/deserializer.dart';
import 'package:flutter_p2p_connection/transport.dart';
import 'package:flutter_p2p_connection/utils.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';
import 'classes.dart';

const _found_peers_event_channel_name = "flutter_p2p_connection_foundPeers";
const _connection_info_event_channel_name =
    "flutter_p2p_connection_connectionInfo";
const _max_group_info_pooling_time = Duration(seconds: 6);

class FlutterP2pConnectionUtilities {
  // device information
  Future<String> getPlatformVersion() =>
      FlutterP2pConnectionPlatform.instance.getPlatformVersion();
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  // p2p permissions
  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();
  Future<bool> askP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.askP2pPermissions();

  // location services
  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();
  Future<bool> enableLocationServices() async =>
      await FlutterP2pConnectionPlatform.instance.enableLocationServices();

  // wifi permissions
  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();
  Future<bool> enableWifiServices() async =>
      await FlutterP2pConnectionPlatform.instance.enableWifiServices();

  // storage permissions
  Future<bool> checkStoragePermission() async =>
      (await Permission.storage.status).isGranted;
  Future<bool> askStoragePermission() async =>
      (await Permission.storage.request()).isGranted;
}

class FlutterP2pConnectionHost {
  bool _groupCreated = false;
  P2pTransport? _p2pTransport;

  bool get groupCreated => _groupCreated;
  P2pTransport? get p2pTransport => _p2pTransport;
  FlutterP2pConnectionUtilities get utilities =>
      FlutterP2pConnectionUtilities();

  Future<void> initialize() async {
    _p2pTransport = null;
    _groupCreated = false;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  Future<void> dispose() async {
    await FlutterP2pConnectionPlatform.instance.dispose();
    await _p2pTransport?.stop();
    _p2pTransport = null;
    _groupCreated = false;
  }

  Future<P2pTransport> createGroup() async {
    await FlutterP2pConnectionPlatform.instance.createGroup();

    // Get ip address
    var ip = await streamIpAddress()
        .timeout(_max_group_info_pooling_time)
        .firstWhere((ip) => ip != null);
    if (ip == null) throw Exception('Failed to get connection ip');

    // create transport
    var transport = P2pTransport(ip: ip, isHost: true, name: "Host Device");
    await transport.start();

    _groupCreated = true;
    _p2pTransport = transport;

    return transport;
  }

  Future<void> removeGroup() async {
    await FlutterP2pConnectionPlatform.instance.removeGroup();
    await _p2pTransport?.stop();
    _p2pTransport = null;
    _groupCreated = false;
  }

  Future<WifiP2pGroupInfo?> requestGroupInfo() async {
    var info = await FlutterP2pConnectionPlatform.instance.requestGroupInfo();
    return info == null ? null : deserializeGroupInfo(Map.from(info));
  }

  // Stream<WifiP2pConnectionInfo?> streamConnectionInfo() {
  //   const infoChannel = EventChannel(_connection_info_event_channel_name);
  //   return infoChannel.receiveBroadcastStream().map((info) {
  //     return info == null ? null : deserializeConnectionInfo(Map.from(info));
  //   });
  // }

  // Future<WifiP2pConnectionInfo?> fetchConnectionInfo() async {
  //   var info =
  //       await FlutterP2pConnectionPlatform.instance.fetchConnectionInfo();
  //   return info == null ? null : deserializeConnectionInfo(Map.from(info));
  // }
}

class FlutterP2pConnectionClient {
  bool _isDiscovering = false;
  bool _isConnected = false;

  StreamSubscription<List<WifiP2pDevice>>? _discoveryStream;
  P2pTransport? _p2pTransport;

  bool get isDiscovering => _isDiscovering;
  bool get isConnected => _isConnected;
  FlutterP2pConnectionUtilities get utilities =>
      FlutterP2pConnectionUtilities();

  Future<void> initialize() async {
    _p2pTransport = null;
    _isDiscovering = false;
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  Future<void> dispose() async {
    await _discoveryStream?.cancel();
    await _p2pTransport?.stop();
    _p2pTransport = null;
    _isDiscovering = false;
    await FlutterP2pConnectionPlatform.instance.dispose();
  }

  Future<void> startPeerDiscovery(
    void Function(List<WifiP2pDevice> devices)? onData,
  ) async {
    await stopPeerDiscovery();
    _discoveryStream = _streamPeers().listen(onData);
    await FlutterP2pConnectionPlatform.instance.startPeerDiscovery();
    _isDiscovering = true;
  }

  Future<void> stopPeerDiscovery() async {
    _isDiscovering = false;
    _discoveryStream?.cancel();
    await FlutterP2pConnectionPlatform.instance.stopPeerDiscovery();
  }

  Future<P2pTransport> connect(
    WifiP2pDevice device,
  ) async {
    await FlutterP2pConnectionPlatform.instance.connect(device.deviceAddress);
    await stopPeerDiscovery();

    // Get ip address
    var ip = await streamIpAddress()
        .timeout(_max_group_info_pooling_time)
        .firstWhere((ip) => ip != null);
    if (ip == null) throw Exception('Failed to get connection ip');

    // create transport
    var transport =
        P2pTransport(ip: ip, isHost: false, name: device.deviceName);
    await transport.start();

    _isConnected = true;
    _p2pTransport = transport;

    return transport;
  }

  Future<bool> disconnect() async {
    await _p2pTransport?.stop();
    _p2pTransport = null;
    _isConnected = false;
    return FlutterP2pConnectionPlatform.instance.disconnect();
  }

  Stream<List<WifiP2pDevice>> _streamPeers() {
    const peersChannel = EventChannel(_found_peers_event_channel_name);
    return peersChannel.receiveBroadcastStream().map((list) {
      if (list == null) return [];

      List peers = List.castFrom(list);
      List<WifiP2pDevice> devices =
          peers.map((device) => deserializeDevice(Map.from(device))).toList();
      return devices;
    });
  }

  // Future<List<WifiP2pDevice>> fetchPeers() async {
  //   var peers = await FlutterP2pConnectionPlatform.instance.fetchPeers();
  //   List<WifiP2pDevice> devices =
  //       peers.map((device) => deserializeDevice(Map.from(device))).toList();
  //   return devices;
  // }
}



/* 
  static void _doNothing() {}

  Future<bool> startSocket({
    required String groupOwnerAddress,
    required String downloadPath,
    int maxConcurrentDownloads = 2,
    bool deleteOnError = true,
    required void Function(String name, String address) onConnect,
    required void Function(TransferUpdate transfer) transferUpdate,
    required void Function(dynamic req) receiveString,
    void Function() onCloseSocket = _doNothing,
  }) async {
    if (groupOwnerAddress.isEmpty) return false;
    try {
      closeSocket(notify: false);
      _maxDownloads = maxConcurrentDownloads;
      _deleteOnError = deleteOnError;
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
              (event) async {
                // SHARE TO CLIENTS
                for (WebSocket? socket in _sockets) {
                  if (socket != null) {
                    socket.add(event);
                  }
                }
                if (event.toString().startsWith(_fileTransferCode)) {
                  // ADD TO FUTURE DOWNLOADS
                  for (String msg in event.toString().split(_groupSeparation)) {
                    String url = msg.toString().split(_fileSizeSeperation).last;
                    int size = int.tryParse(msg
                            .toString()
                            .replaceFirst(_fileTransferCode, "")
                            .split(_fileSizeSeperation)
                            .first) ??
                        0;
                    int id = int.tryParse(url.split("&id=").last) ??
                        Random().nextInt(10000);
                    String filename = await _setName(
                        url
                            .split("/")
                            .last
                            .replaceFirst("&id=${url.split("&id=").last}", ""),
                        downloadPath);
                    String path = "$downloadPath$filename";
                    CancelToken token = CancelToken();

                    // UPDATE TRANSFER
                    transferUpdate(
                      TransferUpdate(
                        filename: filename,
                        path: path,
                        count: 0,
                        total: size,
                        completed: false,
                        failed: false,
                        receiving: true,
                        id: id,
                        cancelToken: token,
                      ),
                    );
                    // ADD TO FUTURES
                    _futureDownloads.add(
                      FutureDownload(
                        url: url,
                        downloading: false,
                        id: id,
                        filename: filename,
                        path: path,
                        cancelToken: token,
                      ),
                    );
                  }
                } else {
                  // RECEIVE MESSAGE
                  receiveString(event
                      .toString()
                      .substring(event.toString().indexOf('@') + 1));
                }
              },
              cancelOnError: true,
              onDone: () {
                debugPrint(
                    "FlutterP2pConnection: A Device Disconnected from Socket!");
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
          onCloseSocket();
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
    bool deleteOnError = true,
    required String downloadPath,
    required void Function(String address) onConnect,
    required void Function(TransferUpdate transfer) transferUpdate,
    required void Function(dynamic req) receiveString,
    void Function() onCloseSocket = _doNothing,
  }) async {
    if (groupOwnerAddress.isEmpty) return false;
    try {
      closeSocket(notify: false);
      _maxDownloads = maxConcurrentDownloads;
      _deleteOnError = deleteOnError;
      _ipAddress = (await getIpAddress()) ?? "0.0.0.0";
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
          (event) async {
            if (event.toString().startsWith(_fileTransferCode)) {
              // ADD TO FUTURE DOWNLOADS
              for (String msg in event.toString().split(_groupSeparation)) {
                String url = msg.toString().split(_fileSizeSeperation).last;
                int size = int.tryParse(msg
                        .toString()
                        .replaceFirst(_fileTransferCode, "")
                        .split(_fileSizeSeperation)
                        .first) ??
                    0;
                if (!(url.startsWith("http://$_ipAddress:$_port/"))) {
                  int id = int.tryParse(url.split("&id=").last) ??
                      Random().nextInt(10000);
                  String filename = await _setName(
                      url
                          .split("/")
                          .last
                          .replaceFirst("&id=${url.split("&id=").last}", ""),
                      downloadPath);
                  String path = "$downloadPath$filename";
                  CancelToken token = CancelToken();

                  // UPDATE TRANSFER
                  transferUpdate(
                    TransferUpdate(
                      filename: filename,
                      path: path,
                      count: 0,
                      total: size,
                      completed: false,
                      failed: false,
                      receiving: true,
                      id: id,
                      cancelToken: token,
                    ),
                  );
                  // ADD TO FUTURES
                  _futureDownloads.add(
                    FutureDownload(
                      url: url,
                      downloading: false,
                      id: id,
                      filename: filename,
                      path: path,
                      cancelToken: token,
                    ),
                  );
                }
              }
            } else if (event.toString().split("@").first !=
                _ipAddress.split(".").last) {
              // RECEIVE MESSGAE
              receiveString(event
                  .toString()
                  .substring(event.toString().indexOf('@') + 1));
            }
          },
          cancelOnError: true,
          onDone: () {
            closeSocket();
            onCloseSocket();
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
      await Future.delayed(const Duration(seconds: 1));
      if (_futureDownloads.isNotEmpty) {
        if (_futureDownloads.where((i) => i.downloading == true).isEmpty) {
          if (_futureDownloads.length <= _maxDownloads) {
            List<Future> futures = [];

            //ADD TO FUTURES
            for (int i = 0; i < _futureDownloads.length; i++) {
              _futureDownloads[i].downloading = true;
              futures.add(
                Future(
                  () async {
                    FutureDownload download = _futureDownloads[i];
                    await _downloadFile(
                      url: download.url,
                      transferUpdate: transferUpdate,
                      downloadPath: downloadPath,
                      done: () {
                        _futureDownloads
                            .removeWhere((i) => i.id == download.id);
                      },
                      filename: download.filename,
                      id: download.id,
                      path: download.path,
                      token: download.cancelToken,
                    );
                    return true;
                  },
                ),
              );
            }
            // RUN FUTURES
            await Future.wait(futures);
          } else {
            List<Future> futures = [];

            //ADD TO FUTURES
            for (int i = 0; i < _maxDownloads; i++) {
              _futureDownloads[i].downloading = true;
              futures.add(
                Future(
                  () async {
                    FutureDownload download = _futureDownloads[i];
                    await _downloadFile(
                      url: download.url,
                      transferUpdate: transferUpdate,
                      downloadPath: downloadPath,
                      done: () {
                        _futureDownloads
                            .removeWhere((i) => i.id == download.id);
                      },
                      filename: download.filename,
                      id: download.id,
                      path: download.path,
                      token: download.cancelToken,
                    );
                    return true;
                  },
                ),
              );
            }
            //RUN FUTURES
            await Future.wait(futures);
          }
        }
      }
    }
  }

  Future _handleFileRequest(
    HttpRequest req,
    void Function(TransferUpdate) transferUpdate,
  ) async {
    String cancel = req.uri.queryParameters['cancel'] ?? "";
    String path = (req.uri.queryParameters['path'] ?? "")
        .replaceAll(_andSymbol, "&")
        .replaceAll(_equalsSymbol, "=")
        .replaceAll(_questionSymbol, "?");
    int id = int.tryParse(req.uri.queryParameters['id'] ?? "0") ?? 0;
    File? file;
    List m = (mime(path.split("/").last) ?? "text/plain").split("/");
    String filename = path.split("/").last;
    int count = 0;
    try {
      file = File(path);
      if (cancel == "true") {
        req.response
          ..write("cancelled")
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
            id: id,
            cancelToken: null,
          ),
        );
        debugPrint("<<<<<<<<< CANCELLED >>>>>>>>> $path");
        return;
      }
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
            id: id,
            cancelToken: null,
          ),
        );
      } else {
        debugPrint("<<<<<<<<< SENDING >>>>>>>>> $path");
        req.response
          ..headers.contentType = ContentType(m.first, m.last)
          ..headers.contentLength = await file.length()
          ..addStream(
            _fileStream(
              file: file,
              filename: filename,
              id: id,
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
                total: file == null ? 0 : await file.length(),
                completed: true,
                failed: count == (file == null ? 0 : await file.length())
                    ? false
                    : true,
                receiving: false,
                id: id,
                cancelToken: null,
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
          total: file == null ? 0 : await file.length(),
          completed: true,
          failed: true,
          receiving: false,
          id: id,
          cancelToken: null,
        ),
      );
    }
  }

  Stream<List<int>> _fileStream({
    required File file,
    required String filename,
    required int id,
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
          id: id,
          cancelToken: null,
        ),
      );
      yield chip;
      if (count == total) break;
    }
  }

  Future _downloadFile({
    required String url,
    required void Function(TransferUpdate) transferUpdate,
    required String downloadPath,
    required void Function() done,
    required String filename,
    required String path,
    required int id,
    required CancelToken token,
  }) async {
    if (url.startsWith("http://$_ipAddress:$_port/")) {
      done();
      return;
    }
    if (token.isCancelled == true) {
      transferUpdate(
        TransferUpdate(
          filename: filename,
          path: path,
          count: 0,
          total: 0,
          completed: true,
          failed: true,
          receiving: true,
          id: id,
          cancelToken: token,
        ),
      );

      // send cancelled request
      await _dio.getUri(Uri.parse("$url&cancel=true"));
      debugPrint("<<<<<<<<< CANCELLED >>>>>>>>> $path");
      done();
      return;
    }
    int count = 0;
    int total = 0;
    bool failed = false;
    try {
      debugPrint("<<<<<<<<< RECEIVING >>>>>>>>> $path");
      _dio.download(
        "$url&cancel=false",
        path,
        deleteOnError: _deleteOnError,
        cancelToken: token,
        onReceiveProgress: (c, t) {
          count = c;
          total = t;
          transferUpdate(
            TransferUpdate(
              filename: filename,
              path: path,
              count: count,
              total: total,
              completed: false,
              failed: false,
              receiving: true,
              id: id,
              cancelToken: token,
            ),
          );
        },
      )
        ..onError((err, stack) async {
          failed = true;
          Future.delayed(
            const Duration(milliseconds: 500),
            () async {
              if (_deleteOnError == true) {
                if (await File(path).exists()) File(path).delete();
              }
            },
          );
          return Future.value(
              Response(requestOptions: RequestOptions(path: url)));
        })
        ..whenComplete(
          () {
            transferUpdate(
              TransferUpdate(
                filename: filename,
                path: path,
                count: count,
                total: total,
                completed: true,
                failed: failed,
                receiving: true,
                id: id,
                cancelToken: token,
              ),
            );
            done();
          },
        );
    } catch (_) {
      transferUpdate(
        TransferUpdate(
          filename: filename,
          path: path,
          count: count,
          total: total,
          completed: true,
          failed: true,
          receiving: true,
          id: id,
          cancelToken: token,
        ),
      );
      done();
    }
  }

  Future<String> _setName(String name, String path) async {
    try {
      if (!(await File(path + name).exists())) return name;
      int number = 1;
      int index = name.lastIndexOf(".");
      String ext = name.substring(index.isNegative ? name.length : index);
      while (true) {
        String newName = name.replaceFirst(ext, "($number)$ext");
        if (!(await File(path + newName).exists())) {
          await File(path + newName).create();
          return newName;
        }
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

  Future<List<TransferUpdate>?> sendFiletoSocket(List<String> paths) async {
    try {
      if (_ipAddress.isEmpty) return null;
      paths = paths.where((path) => (File(path).existsSync()) == true).toList();

      // CREATE IDS
      List<int> ids = [];
      for (var _ in paths) {
        ids.add(Random().nextInt(1000000000));
      }

      // SEND TO SOCKETS
      for (WebSocket? socket in _sockets) {
        if (socket != null) {
          String msg = '';
          for (int i = 0; i < paths.length; i++) {
            var size = await File(paths[i]).length();
            msg +=
                "$_fileTransferCode$size${_fileSizeSeperation}http://$_ipAddress:$_port/file?path=${paths[i].replaceAll("&", _andSymbol).replaceAll("=", _equalsSymbol).replaceAll("?", _questionSymbol)}&id=${ids[i]}";
            if (i < paths.length - 1) msg += _groupSeparation;
          }
          socket.add(msg);
        }
      }

      // UPDATE TRANSFERS
      List<TransferUpdate> updates = [];
      for (int i = 0; i < paths.length; i++) {
        String filename = paths[i].split("/").last;
        updates.add(
          TransferUpdate(
            filename: filename,
            path: paths[i],
            count: 0,
            total: await File(paths[i]).length(),
            completed: false,
            failed: false,
            receiving: false,
            id: ids[i],
            cancelToken: null,
          ),
        );
      }
      return updates;
    } catch (e) {
      debugPrint("FlutterP2pConnection: Tranfer error: $e");
      return null;
    }
  }

  bool closeSocket({bool notify = true}) {
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
      if (notify == true) debugPrint("FlutterP2pConnection: Closed Socket!");
      return true;
    } catch (_) {
      return false;
    }
  }
*/