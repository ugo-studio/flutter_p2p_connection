import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  late FlutterP2pConnectionHost p2p;

  @override
  void initState() {
    super.initState();
    p2p = FlutterP2pConnectionHost();
    p2p.initialize();
  }

  @override
  void dispose() {
    p2p.dispose();
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

  void createHotspot() async {
    try {
      await p2p.createHotspot();
      snack("created hotspot");
    } catch (e) {
      snack("failed to create hotspot: $e");
    }
    setState(() {});
  }

  void removeHotspot() async {
    try {
      await p2p.removeHotspot();
      snack("removed hotspot");
    } catch (e) {
      snack("failed to remove hotspot: $e");
    }
    setState(() {});
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
            ElevatedButton(
              onPressed: () async {
                // StreamSubscription<HotspotInfo>? listener =
                //     p2p.streamHotspotInfo().listen(
                //   (info) {
                //     print((info.hostIpAddress));
                //     print((info.ssid));
                //     print((info.preSharedKey));
                //     print((info.isActive));
                //   },
                // );

                // await Future.delayed(Duration(seconds: 10));
                // listener.cancel();

                var info = await p2p.requestHotspotInfo();
                if (info != null) {
                  print((info.hostIpAddress));
                  print((info.ssid));
                  print((info.preSharedKey));
                  print((info.isActive));
                }
              },
              child: const Text("get network info"),
            ),
            const SizedBox(height: 30),

            // Group services
            p2p.groupCreated
                ? ElevatedButton(
                    onPressed: removeHotspot,
                    child: const Text(
                      "remove hotspot",
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                : ElevatedButton(
                    onPressed: createHotspot,
                    child: const Text(
                      "create hotspot",
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
