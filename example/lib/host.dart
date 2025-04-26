import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection_example/qr/qr_image_page.dart';

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  late FlutterP2pConnection p2p;

  StreamSubscription<HotspotHostState>? hotspotStateSubscription;
  StreamSubscription<List<String>>? clientListStream;

  HotspotHostState? hotspotState;

  @override
  void initState() {
    super.initState();

    p2p = FlutterP2pConnection();
    p2p.host.initialize().whenComplete(() {
      hotspotStateSubscription = p2p.host.streamHotspotState().listen((state) {
        setState(() {
          hotspotState = state;
        });
      });
    });
  }

  @override
  void dispose() {
    p2p.host.dispose();
    hotspotStateSubscription?.cancel();
    clientListStream?.cancel();
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

  void createGroup() async {
    try {
      await p2p.host.createGroup();
      snack("created group");
    } catch (e) {
      snack("failed to create group: $e");
    }
    setState(() {});
  }

  void removeGroup() async {
    try {
      await p2p.host.removeGroup();
      snack("removed group");
    } catch (e) {
      snack("failed to remove group: $e");
    }
    setState(() {});
  }

  void shareHotspotWithQrcode() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QrImagePage(
          hotspotState: hotspotState,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host'),
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

              // hotspot services
              p2p.host.isGroupCreated
                  ? ElevatedButton(
                      onPressed: removeGroup,
                      child: const Text(
                        "remove group",
                        style: TextStyle(color: Colors.red),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: createGroup,
                      child: const Text(
                        "create group",
                        style: TextStyle(color: Colors.green),
                      ),
                    ),
              const SizedBox(height: 30),

              // hotspot creds share methods
              p2p.host.isGroupCreated
                  ? ElevatedButton(
                      onPressed: shareHotspotWithQrcode,
                      child: const Text(
                        "share hotspot creds via qrcode",
                        style: TextStyle(color: Colors.black),
                      ),
                    )
                  : const SizedBox.shrink(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
