import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
  late FlutterP2pClient flutterP2P;

  StreamSubscription<HotspotClientState>? hotspotStateStream;
  StreamSubscription<P2pMessagePayload>? payloadStream;

  HotspotClientState? hotspotState;
  List<BleDiscoveredDevice> discoveredDevices = [];

  @override
  void initState() {
    super.initState();

    flutterP2P = FlutterP2pClient();
    flutterP2P.initialize().whenComplete(() {
      hotspotStateStream = flutterP2P.streamHotspotState().listen((state) {
        setState(() {
          hotspotState = state;
        });
      });
      payloadStream = flutterP2P.streamReceivedPayloads().listen((payload) {
        if (payload.text.isNotEmpty) {
          snack('Received text message: ${payload.text}');
        }

        if (payload.files.isNotEmpty) {
          print(payload.files);
          snack('Received ${payload.files.length} files');
        }
      });
    });
  }

  @override
  void dispose() {
    flutterP2P.dispose();
    textEditingController.dispose();
    hotspotStateStream?.cancel();
    payloadStream?.cancel();
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
    var storageGranted = await flutterP2P.askStoragePermission();
    var p2pGranted = await flutterP2P.askP2pPermissions();
    var bleGranted = await flutterP2P.askBluetoothPermissions();
    snack(
        "Storage permission: $storageGranted\n\nP2p permission: $p2pGranted\n\nBluetooth permission: $bleGranted");
  }

  void enableWifi() async {
    var wifiEnabled = await flutterP2P.enableWifiServices();
    snack("enabling wifi: $wifiEnabled");
  }

  void enableLocation() async {
    var locationEnabled = await flutterP2P.enableLocationServices();
    snack("enabling location: $locationEnabled");
  }

  void enableBluetooth() async {
    var bluetoothEnabled = await flutterP2P.enableBluetoothServices();
    snack("enabling bluetooth: $bluetoothEnabled");
  }

  void startPeerDiscovery() async {
    await flutterP2P.startScan((devices) {
      setState(() {
        discoveredDevices = devices;
      });
    });
    snack('started peer discovery');
  }

  void connectWithDevice(int index) async {
    var device = discoveredDevices[index];
    await flutterP2P.connectWithDevice(device);
    snack('connected to ${device.deviceAddress}');
    setState(() {
      discoveredDevices.clear();
    });
  }

  void connectWithCredentials(ssid, preSharedKey) async {
    try {
      await flutterP2P.connectWithCredentials(ssid, preSharedKey);
      snack("connected");
    } catch (e) {
      snack("failed to connect: $e");
    }
  }

  void disconnect() async {
    await flutterP2P.disconnect();
    snack("disconnected");
  }

  void sendMessage() async {
    var text = textEditingController.text;
    if (text.isEmpty) return;
    await flutterP2P.broadcastText(text);
  }

  void sendFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      flutterP2P.broadcastFile(file);
      snack("file sent to clients");
    } else {
      snack("user canceled file picker");
    }
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
              StreamBuilder(
                stream: flutterP2P.streamClientList(),
                builder: (context, snapshot) {
                  var clientList = snapshot.data ?? [];
                  return Center(
                    child: Column(
                      children: [
                        Text(
                            "Connected devices (${clientList.isEmpty ? 'empty' : clientList.length}):"),
                        SizedBox(
                          width: double.infinity,
                          height: 200,
                          child: ListView.builder(
                            itemCount: clientList.length,
                            itemBuilder: (context, index) => ListTile(
                              title: Text(clientList[index].username),
                              subtitle:
                                  Text('isHost: ${clientList[index].isHost}'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),

              // send messages
              const Text("Send text messages:"),
              TextField(
                controller: textEditingController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  hintText: 'Enter your message here',
                ),
              ),
              ElevatedButton(
                onPressed: sendMessage,
                child: const Text('Send Text'),
              ),
              const SizedBox(height: 30),

              // Send File
              ElevatedButton(
                onPressed: sendFile,
                child: const Text(
                  "Send file",
                  style: TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
