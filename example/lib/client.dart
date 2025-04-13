import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/classes.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  late FlutterP2pConnectionClient p2p;
  late StreamSubscription<HotspotClientState> hotspotStateStream;

  HotspotClientState? hotspotInfo;

  @override
  void initState() {
    super.initState();
    p2p = FlutterP2pConnectionClient()..initialize();

    hotspotStateStream = p2p.streamHotspotClientState().listen((info) {
      setState(() {
        hotspotInfo = info;
      });
    });
  }

  @override
  void dispose() {
    p2p.dispose();
    hotspotStateStream.cancel();
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
    snack("Storage permission: $storageGranted\n\nP2p permission: $p2pGranted");
  }

  void enableWifi() async {
    var wifiEnabled = await p2p.enableWifiServices();
    snack("enabling wifi: $wifiEnabled");
  }

  void enableLocation() async {
    var locationEnabled = await p2p.enableLocationServices();
    snack("enabling location: $locationEnabled");
  }

  void connect() async {
    try {
      var ssid = 'AndroidShare_1281';
      var password = 'j66nmwj9gn7x262';

      await p2p.connectToHotspot(ssid, password);
      snack("connected");
    } catch (e) {
      snack("failed to connect: $e");
    }
  }

  void disconnect() async {
    try {
      await p2p.disconnectFromHotspot();
      snack("disconnected");
    } catch (e) {
      snack("failed to disconnect: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
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
            const SizedBox(height: 30),

            // Group services
            hotspotInfo?.isActive == true
                ? ElevatedButton(
                    onPressed: disconnect,
                    child: const Text(
                      "disconnect",
                      style: TextStyle(color: Colors.orange),
                    ),
                  )
                : ElevatedButton(
                    onPressed: connect,
                    child: const Text(
                      "connect",
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
            const SizedBox(height: 30),

            ///
          ],
        ),
      ),
    );
  }
}
