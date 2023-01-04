import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:permission_handler/permission_handler.dart';

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
  String myIpAddress = "unkown";
  WifiP2PInfo wifiP2PInfo = const WifiP2PInfo(
    groupFormed: false,
    groupOwnerAddress: null,
    isConnected: false,
    isGroupOwner: false,
    clients: [],
  );
  StreamSubscription<WifiP2PInfo>? _streamWifiInfo;
  StreamSubscription<List<DiscoveredPeers>>? _streamPeers;

  WebSocket? socket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _register();
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
      print(">>>> pause");
      _flutterP2pConnectionPlugin.register();
    } else if (state == AppLifecycleState.resumed) {
      print(">>>> resume");
      _flutterP2pConnectionPlugin.unregister();
    }
  }

  void _register() async {
    await _flutterP2pConnectionPlugin.initialize();
    await _flutterP2pConnectionPlugin.register();
    _streamWifiInfo =
        _flutterP2pConnectionPlugin.streamWifiP2PInfo().listen((event) {
      if (wifiP2PInfo != event) {
        setState(() {
          wifiP2PInfo = event;
        });
      }
    });
    _streamPeers = _flutterP2pConnectionPlugin.streamPeers().listen((event) {
      if (peers != event) {
        setState(() {
          peers = event;
        });
      }
    });
  }

  Future startServer() async {
    await _flutterP2pConnectionPlugin.startServer(
      ip: wifiP2PInfo.groupOwnerAddress!,
      onStarted: (server) {},
      onConnect: (socket) {
        socket = socket;
      },
      onRequest: (req) async {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              req,
            ),
          ),
        );
        print(req);
      },
    );
  }

  Future connectToServer() async {
    socket = await _flutterP2pConnectionPlugin.connectToServer(
      ip: wifiP2PInfo.groupOwnerAddress!,
      onStarted: (address) {},
      onRequest: (req) async {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              req,
            ),
          ),
        );
        print(req);
      },
    );
  }

  Future closeConnection() async {
    if (socket != null) {
      socket?.close();
      socket = null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "closed",
        ),
      ),
    );
    setState(() {});
  }

  Future sendMessage() async {
    try {
      if (socket != null) {
        socket?.add(msgText.text.trim());
      }
    } catch (_) {}
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
            Text("IP: ${wifiP2PInfo.groupOwnerAddress}"),
            Text(
                "connected: ${wifiP2PInfo.isConnected}, isGroupOwner: ${wifiP2PInfo.isGroupOwner}, groupFormed: ${wifiP2PInfo.groupFormed}, groupOwnerAddress: ${wifiP2PInfo.groupOwnerAddress}, clients: ${wifiP2PInfo.clients}"),
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
                            content: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("name: ${peers[index].deviceName}"),
                                Text("address: ${peers[index].deviceAddress}"),
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
                await Permission.location.request();
                print(await Permission.location.status);
              },
              child: const Text("ask location permission"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? created = await _flutterP2pConnectionPlugin.createGroup();
                print(created);
              },
              child: const Text("create group"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? removed = await _flutterP2pConnectionPlugin.removeGroup();
                print(removed);
              },
              child: const Text("remove group/disconnect"),
            ),
            ElevatedButton(
              onPressed: () async {
                var info = await _flutterP2pConnectionPlugin.groupInfo();
                print(info);
              },
              child: const Text("get group info"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? discovering =
                    await _flutterP2pConnectionPlugin.discover();
                print("discovering $discovering");
              },
              child: const Text("discover"),
            ),
            ElevatedButton(
              onPressed: () async {
                bool? stopped =
                    await _flutterP2pConnectionPlugin.stopDiscovery();
                print("stopped $stopped");
              },
              child: const Text("stop discovery"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (peers.isNotEmpty) {
                  bool? bo = await _flutterP2pConnectionPlugin
                      .connect(peers.first.deviceAddress);
                  print(bo);
                }
              },
              child: const Text("connect"),
            ),
            ElevatedButton(
              onPressed: () async {
                startServer();
              },
              child: const Text("open a socket"),
            ),
            ElevatedButton(
              onPressed: () async {
                connectToServer();
              },
              child: const Text("connect to socket"),
            ),
            ElevatedButton(
              onPressed: () async {
                closeConnection();
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
          ],
        ),
      ),
    );
  }
}

Future<String?> myLocalIp() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: true,
  );
  List<NetworkInterface> networkInterface = interfaces
      .where((e) => e.addresses.first.address.startsWith("192."))
      .toList();
  if (networkInterface.isNotEmpty) {
    String ip = networkInterface.first.addresses.first.address;
    return ip;
  } else {
    return null;
  }
}
