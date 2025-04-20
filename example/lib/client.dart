import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection_example/qr/scanner_page.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  late FlutterP2pConnection p2p;
  late StreamSubscription<HotspotClientState> hotspotStateSubscription;

  HotspotClientState? hotspotState;
  List<BleFoundDevice> foundDevices = [];

  @override
  void initState() {
    super.initState();

    p2p = FlutterP2pConnection();
    p2p.client.initialize().whenComplete(() {
      hotspotStateSubscription =
          p2p.client.onHotspotStateChanged().listen((state) {
        setState(() {
          hotspotState = state;
        });
      });
    });
  }

  @override
  void dispose() {
    p2p.client.dispose();
    hotspotStateSubscription.cancel();
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

  void scanQrcodeAndConnect() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerPage(
          onScanned: (ssid, preSharedKey) async {
            try {
              await p2p.client.connectToHotspot(ssid, preSharedKey);
              snack("connected");
            } catch (e) {
              snack("failed to connect: $e");
            }
          },
        ),
      ),
    );
  }

  void disconnect() async {
    await p2p.client.disconnectFromHotspot();
    snack("disconnected");
  }

  void startPeerDiscovery() async {
    await p2p.client.startScan((devices) {
      setState(() {
        foundDevices = devices;
      });
    });
    snack('started peer discovery');
  }

  void connectToBleDevice(int index) async {
    var device = foundDevices[index];
    await p2p.client.connectToFoundDevice(device.deviceAddress);
    snack('connected to ${device.deviceAddress}');

    setState(() {
      foundDevices = [];
    });
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
                onPressed: scanQrcodeAndConnect,
                child: const Text(
                  "scan qrcode and connect",
                  style: TextStyle(color: Colors.black),
                ),
              ),
              const Text('OR'),
              ElevatedButton(
                onPressed: startPeerDiscovery,
                child: const Text(
                  "start bluetooth peer discovery",
                  style: TextStyle(color: Colors.blue),
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
              SizedBox(
                width: double.infinity,
                height: 200,
                child: ListView.builder(
                  itemCount: foundDevices.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(foundDevices[index].deviceName),
                    subtitle: Text(foundDevices[index].deviceAddress),
                    trailing: ElevatedButton(
                      onPressed: () => connectToBleDevice(index),
                      child: const Text("connect"),
                    ),
                  ),
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
