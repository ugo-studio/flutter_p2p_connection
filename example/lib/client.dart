import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:flutter_p2p_connection_example/qr/scanner_page.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final TextEditingController textEditingController = TextEditingController();
  late FlutterP2pClient p2p;

  StreamSubscription<HotspotClientState>? hotspotStateSubscription;
  StreamSubscription<List<P2pClientInfo>>? clientListStream;
  StreamSubscription<String>? textMessageStream;

  HotspotClientState? hotspotState;
  List<BleDiscoveredDevice> discoveredDevices = [];
  List<P2pClientInfo> clientList = [];

  @override
  void initState() {
    super.initState();

    p2p = FlutterP2pClient();
    p2p.initialize().whenComplete(() {
      hotspotStateSubscription = p2p.streamHotspotState().listen((state) {
        setState(() {
          hotspotState = state;
        });
      });
    });
  }

  @override
  void dispose() {
    p2p.dispose();
    textEditingController.dispose();
    hotspotStateSubscription?.cancel();
    clientListStream?.cancel();
    textMessageStream?.cancel();
    super.dispose();
  }

  void snack(String msg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          msg,
        ),
      ),
    );
  }

  void askRequiredPermission() async {
    var storageGranted = await p2p.askStoragePermission();
    var p2pGranted = await p2p.askP2pPermissions();
    var bleGranted = await p2p.askBluetoothPermissions();
    snack(
        "Storage permission: $storageGranted\n\nP2p permission: $p2pGranted\n\nBluetooth permission: $bleGranted");
  }

  void enableWifi() async {
    var wifiEnabled = await p2p.enableWifiServices();
    snack("enabling wifi: $wifiEnabled");
  }

  void enableLocation() async {
    var locationEnabled = await p2p.enableLocationServices();
    snack("enabling location: $locationEnabled");
  }

  void enableBluetooth() async {
    var bluetoothEnabled = await p2p.enableBluetoothServices();
    snack("enabling bluetooth: $bluetoothEnabled");
  }

  void startPeerDiscovery() async {
    await p2p.startScan((devices) {
      setState(() {
        discoveredDevices = devices;
      });
    });
    snack('started peer discovery');
  }

  void connectWithDevice(int index) async {
    var device = discoveredDevices[index];
    await p2p.connectWithDevice(device);
    clientListStream = p2p.streamClientList().listen((list) {
      setState(() {
        clientList = list;
      });
    });
    textMessageStream = p2p.streamReceivedTextMessages().listen((data) {
      snack('Received message: $data');
    });
    snack('connected to ${device.deviceAddress}');
    setState(() {
      discoveredDevices.clear();
    });
  }

  void connectWithCredentials(ssid, preSharedKey) async {
    try {
      await p2p.connectWithCredentials(ssid, preSharedKey);
      clientListStream = p2p.streamClientList().listen((list) {
        setState(() {
          clientList = list;
        });
      });
      textMessageStream = p2p.streamReceivedTextMessages().listen((data) {
        snack('Received message: $data');
      });
      snack("connected");
    } catch (e) {
      snack("failed to connect: $e");
    }
  }

  void disconnect() async {
    clientListStream?.cancel();
    await p2p.disconnect();
    snack("disconnected");
  }

  void sendMessage() async {
    var text = textEditingController.text;
    if (text.isEmpty) return;
    await p2p.broadcastText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ask required permissions
              ElevatedButton(
                onPressed: askRequiredPermission,
                child: const Text("ask required permissions"),
              ),

              // Enable required services
              ElevatedButton(
                onPressed: enableWifi,
                child: const Text("enable wifi"),
              ),
              ElevatedButton(
                onPressed: enableLocation,
                child: const Text("enable location"),
              ),
              ElevatedButton(
                onPressed: enableBluetooth,
                child: const Text("enable bluetooth"),
              ),
              const SizedBox(height: 30),

              // hotspot creds share methods
              ElevatedButton(
                onPressed: startPeerDiscovery,
                child: const Text(
                  "start bluetooth peer discovery",
                  style: TextStyle(color: Colors.blue),
                ),
              ),
              const Text('OR'),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScannerPage(
                        onScanned: connectWithCredentials,
                      ),
                    ),
                  );
                },
                child: const Text(
                  "scan qrcode and connect",
                  style: TextStyle(color: Colors.black),
                ),
              ),
              const SizedBox(height: 30),

              // hotspot disconect
              hotspotState?.isActive == true
                  ? ElevatedButton(
                      onPressed: disconnect,
                      child: const Text(
                        "disconnect",
                        style: TextStyle(color: Colors.orange),
                      ),
                    )
                  : const SizedBox.shrink(),
              const SizedBox(height: 30),

              // display scan result
              discoveredDevices.isNotEmpty
                  ? Center(
                      child: Column(
                        children: [
                          const Text("Discovered devices:"),
                          SizedBox(
                            width: double.infinity,
                            height: 200,
                            child: ListView.builder(
                              itemCount: discoveredDevices.length,
                              itemBuilder: (context, index) => ListTile(
                                title:
                                    Text(discoveredDevices[index].deviceName),
                                subtitle: Text(
                                    discoveredDevices[index].deviceAddress),
                                trailing: ElevatedButton(
                                  onPressed: () => connectWithDevice(index),
                                  child: const Text("connect"),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),

              // display client list
              Text(
                  "Connected devices (${clientList.isEmpty ? 'empty' : clientList.length}):"),
              SizedBox(
                width: double.infinity,
                height: 200,
                child: ListView.builder(
                  itemCount: clientList.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(clientList[index].username),
                    subtitle: Text('isHost: ${clientList[index].isHost}'),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              const Text("Send messages:"),
              TextField(
                controller: textEditingController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  hintText: 'Enter your message here',
                ),
              ),
              ElevatedButton(onPressed: sendMessage, child: const Text('send'))
            ],
          ),
        ),
      ),
    );
  }
}
