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

  List<WifiP2pDevice> discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    p2p = FlutterP2pConnectionClient();
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
    var storageGranted = await p2p.utilities.askStoragePermission();
    var p2pGranted = await p2p.utilities.askP2pPermissions();
    snack("Storage permission: $storageGranted\n\nP2p permission: $p2pGranted");
  }

  void enableWifi() async {
    var wifiEnabled = await p2p.utilities.enableWifiServices();
    snack("enabling wifi: $wifiEnabled");
  }

  void enableLocation() async {
    var locationEnabled = await p2p.utilities.enableLocationServices();
    snack("enabling location: $locationEnabled");
  }

  void startDiscovery() async {
    try {
      await p2p.startPeerDiscovery((devices) {
        setState(() {
          discoveredDevices = devices;
        });
      });
      snack("started discovery");
    } catch (e) {
      snack("failed to start discovery: $e");
    }

    setState(() {});
  }

  void stopDiscovery() async {
    try {
      await p2p.stopPeerDiscovery();
      snack("stopped discovery");
    } catch (e) {
      snack("failed to stop discovery: $e");
    }

    discoveredDevices.clear();
    setState(() {});
  }

  void connect(int index) async {
    try {
      var device = discoveredDevices[index];
      await p2p.connect(device);
      snack("connected");
    } catch (e) {
      snack("failed to connect: $e");
    }
    setState(() {});
  }

  void disconnect() async {
    try {
      await p2p.disconnect();
      snack("disconnected");
    } catch (e) {
      snack("failed to disconnect: $e");
    }

    discoveredDevices.clear();
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
            const SizedBox(height: 30),

            // Group services
            p2p.isDiscovering
                ? ElevatedButton(
                    onPressed: stopDiscovery,
                    child: const Text(
                      "stop discovery",
                      style: TextStyle(color: Colors.orange),
                    ),
                  )
                : ElevatedButton(
                    onPressed: startDiscovery,
                    child: const Text(
                      "start discovery",
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
            const SizedBox(height: 30),

            // list discovered devices
            SizedBox(
              height: 100,
              width: MediaQuery.of(context).size.width,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: discoveredDevices.length,
                itemBuilder: (context, index) => Center(
                  child: Container(
                    width: 200,
                    height: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 223, 223, 223),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(discoveredDevices[index].deviceName),
                        p2p.isConnected
                            ? ElevatedButton(
                                onPressed: disconnect,
                                child: const Text('disconnect'),
                              )
                            : ElevatedButton(
                                onPressed: () => connect(index),
                                child: const Text('connect'),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//  Text(
//                 "IP: ${wifiP2PInfo == null ? "null" : wifiP2PInfo?.groupOwnerAddress}"),
//             wifiP2PInfo != null
//                 ? Text(
//                     "connected: ${wifiP2PInfo?.isConnected}, isGroupOwner: ${wifiP2PInfo?.isGroupOwner}, groupFormed: ${wifiP2PInfo?.groupFormed}, groupOwnerAddress: ${wifiP2PInfo?.groupOwnerAddress}, clients: ${wifiP2PInfo?.clients}")
//                 : const SizedBox.shrink(),
//             const SizedBox(height: 10),
//             const Text("PEERS:"),
//             SizedBox(
//               height: 100,
//               width: MediaQuery.of(context).size.width,
//               child: ListView.builder(
//                 scrollDirection: Axis.horizontal,
//                 itemCount: peersList.length,
//                 itemBuilder: (context, index) => Center(
//                   child: GestureDetector(
//                     onTap: () {
//                       showDialog(
//                         context: context,
//                         builder: (context) => Center(
//                           child: AlertDialog(
//                             content: SizedBox(
//                               height: 200,
//                               child: Column(
//                                 mainAxisAlignment: MainAxisAlignment.center,
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text("name: ${peersList[index].deviceName}"),
//                                   Text(
//                                       "address: ${peersList[index].deviceAddress}"),
//                                   Text(
//                                       "isGroupOwner: ${peersList[index].isGroupOwner}"),
//                                   Text(
//                                       "isServiceDiscoveryCapable: ${peersList[index].isServiceDiscoveryCapable}"),
//                                   Text(
//                                       "primaryDeviceType: ${peersList[index].primaryDeviceType}"),
//                                   Text(
//                                       "secondaryDeviceType: ${peersList[index].secondaryDeviceType}"),
//                                   Text("status: ${peersList[index].status}"),
//                                 ],
//                               ),
//                             ),
//                             actions: [
//                               TextButton(
//                                 onPressed: () async {
//                                   Navigator.of(context).pop();
//                                   bool? bo = await p2p
//                                       .connect(peersList[index].deviceAddress);
//                                   snack("connected: $bo");
//                                 },
//                                 child: const Text("connect"),
//                               ),
//                               TextButton(
//                                 onPressed: () async {
//                                   Navigator.of(context).pop();
//                                   await p2p.disconnect();
//                                   snack("disconnected");
//                                 },
//                                 child: const Text("disconnect"),
//                               ),
//                             ],
//                           ),
//                         ),
//                       );
//                     },
//                     child: Container(
//                       height: 80,
//                       width: 80,
//                       decoration: BoxDecoration(
//                         color: Colors.grey,
//                         borderRadius: BorderRadius.circular(50),
//                       ),
//                       child: Center(
//                         child: Text(
//                           peersList[index]
//                               .deviceName
//                               .toString()
//                               .characters
//                               .first
//                               .toUpperCase(),
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 30,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),

//             // storage servcies
//             ElevatedButton(
//               onPressed: () async {
//                 snack(await p2p.askStoragePermission()
//                     ? "granted"
//                     : "denied");
//               },
//               child: const Text("ask storage permission"),
//             ),

//             // location services
//             ElevatedButton(
//               onPressed: () async {
//                 snack(await p2p.askLocationPermissions()
//                     ? "enabled"
//                     : "disabled");
//               },
//               child: const Text(
//                 "ask location permission",
//               ),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 print(await p2p.enableLocationServices());
//               },
//               child: const Text("enable location"),
//             ),

//             // wifi services
//             ElevatedButton(
//               onPressed: () async {
//                 print(await p2p.enableWifiServices());
//               },
//               child: const Text("enable wifi"),
//             ),

//             // group services
//             ElevatedButton(
//               onPressed: () async {
//                 bool? created = await p2p.createGroup();
//                 snack("created group: $created");
//               },
//               child: const Text("create group"),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 bool? removed = await p2p.removeGroup();
//                 snack("removed group: $removed");
//               },
//               child: const Text("remove group"),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 String? ip = await p2p.getIPAddress();
//                 snack("ip: $ip");
//               },
//               child: const Text("get ip"),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 bool? discovering = await p2p.startPeerDiscovery();
//                 snack("started discovery $discovering");
//               },
//               child: const Text("start peer discovery"),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 bool? stopped = await p2p.startPeerDiscovery();
//                 snack("stopped discovering $stopped");
//               },
//               child: const Text("stop peer discovery"),
//             ),
