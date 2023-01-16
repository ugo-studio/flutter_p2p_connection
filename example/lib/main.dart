import 'dart:io';

import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final TextEditingController msgText = TextEditingController();
  final _flutterP2pConnectionPlugin = FlutterP2pConnection();
  List<DiscoveredPeers> peers = [];
  WifiP2PInfo? wifiP2PInfo;
  StreamSubscription<WifiP2PInfo>? _streamWifiInfo;
  StreamSubscription<List<DiscoveredPeers>>? _streamPeers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flutterP2pConnectionPlugin.unregister();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flutterP2pConnectionPlugin.unregister();
    } else if (state == AppLifecycleState.resumed) {
      _flutterP2pConnectionPlugin.register();
    }
  }

  void _init() async {
    await _flutterP2pConnectionPlugin.initialize();
    await _flutterP2pConnectionPlugin.register();
    _streamWifiInfo =
        _flutterP2pConnectionPlugin.streamWifiP2PInfo().listen((event) {
      setState(() {
        wifiP2PInfo = event;
      });
    });
    _streamPeers = _flutterP2pConnectionPlugin.streamPeers().listen((event) {
      setState(() {
        peers = event;
      });
    });
  }

  Future startSocket() async {
    if (wifiP2PInfo != null) {
      bool started = await _flutterP2pConnectionPlugin.startSocket(
        groupOwnerAddress: wifiP2PInfo!.groupOwnerAddress,
        downloadPath: "/storage/emulated/0/Download/",
        maxConcurrentDownloads: 2,
        deleteOnError: true,
        onConnect: (name, address) {
          snack("$name connected to socket with address: $address");
        },
        transferUpdate: (transfer) {
          if (transfer.completed) {
            snack(
                "${transfer.failed ? "failed to ${transfer.receiving ? "receive" : "send"}" : transfer.receiving ? "received" : "sent"}: ${transfer.filename}");
          }
          print(
              "ID: ${transfer.id}, FILENAME: ${transfer.filename}, PATH: ${transfer.path}, COUNT: ${transfer.count}, TOTAL: ${transfer.total}, COMPLETED: ${transfer.completed}, FAILED: ${transfer.failed}, RECEIVING: ${transfer.receiving}");
        },
        receiveString: (req) async {
          snack(req);
        },
      );
      snack("open socket: $started");
    }
  }

  Future connectToSocket() async {
    if (wifiP2PInfo != null) {
      await _flutterP2pConnectionPlugin.connectToSocket(
        groupOwnerAddress: wifiP2PInfo!.groupOwnerAddress,
        downloadPath: "/storage/emulated/0/Download/",
        maxConcurrentDownloads: 3,
        deleteOnError: true,
        onConnect: (address) {
          snack("connected to socket: $address");
        },
        transferUpdate: (transfer) {
          // if (transfer.count == 0) transfer.cancelToken?.cancel();
          if (transfer.completed) {
            snack(
                "${transfer.failed ? "failed to ${transfer.receiving ? "receive" : "send"}" : transfer.receiving ? "received" : "sent"}: ${transfer.filename}");
          }
          print(
              "ID: ${transfer.id}, FILENAME: ${transfer.filename}, PATH: ${transfer.path}, COUNT: ${transfer.count}, TOTAL: ${transfer.total}, COMPLETED: ${transfer.completed}, FAILED: ${transfer.failed}, RECEIVING: ${transfer.receiving}");
        },
        receiveString: (req) async {
          snack(req);
        },
      );
    }
  }

  Future closeSocketConnection() async {
    bool closed = _flutterP2pConnectionPlugin.closeSocket();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "closed: $closed",
        ),
      ),
    );
  }

  Future sendMessage() async {
    _flutterP2pConnectionPlugin.sendStringToSocket(msgText.text);
  }

  Future sendFile(bool phone) async {
    String? filePath = await FilesystemPicker.open(
      context: context,
      rootDirectory: Directory(phone ? "/storage/emulated/0/" : "/storage/"),
      fsType: FilesystemType.file,
      fileTileSelectMode: FileTileSelectMode.wholeTile,
      showGoUp: true,
      folderIconColor: Colors.blue,
    );
    if (filePath == null) return;
    List<TransferUpdate>? updates =
        await _flutterP2pConnectionPlugin.sendFiletoSocket(
      [
        filePath,
        // "/storage/emulated/0/Download/Likee_7100105253123033459.mp4",
        // "/storage/0E64-4628/Download/Adele-Set-Fire-To-The-Rain-via-Naijafinix.com_.mp3",
        // "/storage/0E64-4628/Flutter SDK/p2p_plugin.apk",
        // "/storage/emulated/0/Download/03 Omah Lay - Godly (NetNaija.com).mp3",
        // "/storage/0E64-4628/Download/Adele-Set-Fire-To-The-Rain-via-Naijafinix.com_.mp3",
      ],
    );
    print(updates);
  }

  void snack(String msg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          msg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter p2p connection plugin'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
                "IP: ${wifiP2PInfo == null ? "null" : wifiP2PInfo?.groupOwnerAddress}"),
            wifiP2PInfo != null
                ? Text(
                    "connected: ${wifiP2PInfo?.isConnected}, isGroupOwner: ${wifiP2PInfo?.isGroupOwner}, groupFormed: ${wifiP2PInfo?.groupFormed}, groupOwnerAddress: ${wifiP2PInfo?.groupOwnerAddress}, clients: ${wifiP2PInfo?.clients}")
                : const SizedBox.shrink(),
            const SizedBox(height: 10),
            const Text("PEERS:"),
            SizedBox(
              height: 100,
              width: MediaQuery.of(context).size.width,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: peers.length,
                itemBuilder: (context, index) => Center(
                  child: GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => Center(
                          child: AlertDialog(
                            content: SizedBox(
                              height: 200,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("name: ${peers[index].deviceName}"),
                                  Text(
                                      "address: ${peers[index].deviceAddress}"),
                                  Text(
                                      "isGroupOwner: ${peers[index].isGroupOwner}"),
                                  Text(
                                      "isServiceDiscoveryCapable: ${peers[index].isServiceDiscoveryCapable}"),
                                  Text(
                                      "primaryDeviceType: ${peers[index].primaryDeviceType}"),
                                  Text(
                                      "secondaryDeviceType: ${peers[index].secondaryDeviceType}"),
                                  Text("status: ${peers[index].status}"),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  bool? bo = await _flutterP2pConnectionPlugin
                                      .connect(peers[index].deviceAddress);
                                  snack("connected: $bo");
                                },
                                child: const Text("connect"),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Center(
                        child: Text(
                          peers[index]
                              .deviceName
                              .toString()
                              .characters
                              .first
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                snack((await _flutterP2pConnectionPlugin.checkLocationEnabled())
                    ? "enabled"
                    : "diabled");
              },
              child: const Text("check location enabled"),
            ),
            ElevatedButton(
              onPressed: () async {
                snack((await _flutterP2pConnectionPlugin.checkWifiEnabled())
                    ? "enabled"
                    : "diabled");
              },
              child: const Text("check wifi enabled"),
            ),
            ElevatedButton(
              onPressed: () async {
                print(
                    await _flutterP2pConnectionPlugin.askLocationPermission());
              },
              child: const Text("ask location permission"),
            ),
            ElevatedButton(
              onPressed: () async {
                print(await _flutterP2pConnectionPlugin.askStoragePermission());
              },
              child: const Text("ask storage permission"),
            ),
            ElevatedButton(
              onPressed: () async {
                print(
                    await _flutterP2pConnectionPlugin.enableLocationServices());
              },
              child: const Text("enable location"),
            ),
            ElevatedButton(
              onPressed: () async {
                print(await _flutterP2pConnectionPlugin.enableWifiServices());
              },
              child: const Text("enable wifi"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? created = await _flutterP2pConnectionPlugin.createGroup();
                snack("created group: $created");
              },
              child: const Text("create group"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? removed = await _flutterP2pConnectionPlugin.removeGroup();
                snack("removed group: $removed");
              },
              child: const Text("remove group/disconnect"),
            ),
            ElevatedButton(
              onPressed: () async {
                var info = await _flutterP2pConnectionPlugin.groupInfo();
                showDialog(
                  context: context,
                  builder: (context) => Center(
                    child: Dialog(
                      child: SizedBox(
                        height: 200,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  "groupNetworkName: ${info?.groupNetworkName}"),
                              Text("passPhrase: ${info?.passPhrase}"),
                              Text("isGroupOwner: ${info?.isGroupOwner}"),
                              Text("clients: ${info?.clients}"),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text("get group info"),
            ),
            ElevatedButton(
              onPressed: () async {
                String? ip = await _flutterP2pConnectionPlugin.getIPAddress();
                snack("ip: $ip");
              },
              child: const Text("get ip"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? discovering =
                    await _flutterP2pConnectionPlugin.discover();
                snack("discovering $discovering");
              },
              child: const Text("discover"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? stopped =
                    await _flutterP2pConnectionPlugin.stopDiscovery();
                snack("stopped discovering $stopped");
              },
              child: const Text("stop discovery"),
            ),
            ElevatedButton(
              onPressed: () async {
                startSocket();
              },
              child: const Text("open a socket"),
            ),
            ElevatedButton(
              onPressed: () async {
                connectToSocket();
              },
              child: const Text("connect to socket"),
            ),
            ElevatedButton(
              onPressed: () async {
                closeSocketConnection();
              },
              child: const Text("close socket"),
            ),
            TextField(
              controller: msgText,
              decoration: const InputDecoration(
                hintText: "message",
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                sendMessage();
              },
              child: const Text("send msg"),
            ),
            ElevatedButton(
              onPressed: () async {
                sendFile(true);
              },
              child: const Text("send File from phone"),
            ),
            ElevatedButton(
              onPressed: () async {
                sendFile(false);
              },
              child: const Text("send File"),
            ),
          ],
        ),
      ),
    );
  }
}
