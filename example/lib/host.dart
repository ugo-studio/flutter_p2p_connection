import 'dart:async';
import 'dart:io';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:flutter_p2p_connection_example/qr/qr_image_page.dart';

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final TextEditingController textEditingController = TextEditingController();
  late FlutterP2pHost flutterP2P;

  StreamSubscription<HotspotHostState>? hotspotStateStream;
  StreamSubscription<String>? receivedTextStream;

  HotspotHostState? hotspotState;

  @override
  void initState() {
    super.initState();

    flutterP2P = FlutterP2pHost();
    flutterP2P.initialize().whenComplete(() {
      hotspotStateStream = flutterP2P.streamHotspotState().listen((state) {
        setState(() {
          hotspotState = state;
        });
      });
      receivedTextStream = flutterP2P.streamReceivedTexts().listen((text) {
        snack('Received text message: ${text}');
      });
    });
  }

  @override
  void dispose() {
    flutterP2P.dispose();
    textEditingController.dispose();
    hotspotStateStream?.cancel();
    receivedTextStream?.cancel();
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

  void createGroup() async {
    try {
      await flutterP2P.createGroup();
      snack("created group");
    } catch (e) {
      snack("failed to create group: $e");
    }
    setState(() {});
  }

  void removeGroup() async {
    try {
      await flutterP2P.removeGroup();
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

  void sendMessage() async {
    var text = textEditingController.text;
    if (text.isNotEmpty) {
      await flutterP2P.broadcastText(text);
    }
  }

  void sendFile() async {
    String? path = await FilesystemPicker.open(
      context: context,
      title: 'Select file',
      fsType: FilesystemType.file,
      rootDirectory: Directory('/storage/emulated/0/'),
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );

    if (path != null) {
      File file = File(path);
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
              flutterP2P.isGroupCreated
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
              flutterP2P.isGroupCreated
                  ? ElevatedButton(
                      onPressed: shareHotspotWithQrcode,
                      child: const Text(
                        "share hotspot creds via qrcode",
                        style: TextStyle(color: Colors.black),
                      ),
                    )
                  : const SizedBox.shrink(),
              const SizedBox(height: 30),

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

              // display sent files
              StreamBuilder(
                stream: flutterP2P.streamSentFilesInfo(),
                builder: (context, snapshot) {
                  var sentFiles = snapshot.data ?? [];
                  return Center(
                    child: Column(
                      children: [
                        Text(
                            "Sent files (${sentFiles.isEmpty ? 'empty' : sentFiles.length}):"),
                        SizedBox(
                          width: double.infinity,
                          height: 200,
                          child: ListView.builder(
                            itemCount: sentFiles.length,
                            itemBuilder: (context, index) {
                              var file = sentFiles[index];
                              var receiverIds = file.receiverIds;

                              return ListTile(
                                title: Text(file.info.name),
                                subtitle: SizedBox(
                                  width: MediaQuery.of(context).size.width,
                                  height: 200,
                                  child: ListView.builder(
                                    itemCount: receiverIds.length,
                                    itemBuilder: (context, index) {
                                      var id = receiverIds[index];
                                      var percent =
                                          file.getProgressPercent(id).round();
                                      return Text("$id = $percent%");
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),

              // display received files
              StreamBuilder(
                stream: flutterP2P.streamReceivedFilesInfo(),
                builder: (context, snapshot) {
                  var receivedFiles = snapshot.data ?? [];
                  return Center(
                    child: Column(
                      children: [
                        Text(
                            "Received files (${receivedFiles.isEmpty ? 'empty' : receivedFiles.length}):"),
                        SizedBox(
                          width: double.infinity,
                          height: 200,
                          child: ListView.builder(
                            itemCount: receivedFiles.length,
                            itemBuilder: (context, index) {
                              var file = receivedFiles[index];
                              var percent =
                                  file.downloadProgressPercent.round();

                              return ListTile(
                                title: Text(file.info.name),
                                subtitle:
                                    Text("state: ${file.state}, $percent%"),
                                trailing: file.state == ReceivableFileState.idle
                                    ? ElevatedButton(
                                        onPressed: () async {
                                          var downloaded =
                                              await flutterP2P.downloadFile(
                                                  file.info.id,
                                                  '/storage/emulated/0/Download/');
                                          snack("Download file: $downloaded");
                                        },
                                        child: Text('download'),
                                      )
                                    : SizedBox.shrink(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
