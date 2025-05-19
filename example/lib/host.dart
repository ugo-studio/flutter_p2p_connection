import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection_example/qr/qr_image_page.dart';

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final TextEditingController textEditingController = TextEditingController();
  late FlutterP2pHost p2pInterface;

  StreamSubscription<HotspotHostState>? hotspotStateStream;
  StreamSubscription<String>? receivedTextStream;

  HotspotHostState? hotspotState;

  @override
  void initState() {
    super.initState();
    p2pInterface = FlutterP2pHost();
    p2pInterface.initialize().whenComplete(() {
      hotspotStateStream = p2pInterface.streamHotspotState().listen((state) {
        setState(() {
          hotspotState = state;
        });
        if (state.isActive && state.ssid != null) {
          snack('Hotspot Active: ${state.ssid}');
        } else if (!state.isActive && hotspotState?.isActive == true) {
          snack('Hotspot Inactive. Reason: ${state.failureReason}');
        }
      });
      receivedTextStream = p2pInterface.streamReceivedTexts().listen((text) {
        snack('Received text: $text');
      });
    });
  }

  @override
  void dispose() {
    p2pInterface.dispose();
    textEditingController.dispose();
    hotspotStateStream?.cancel();
    receivedTextStream?.cancel();
    super.dispose();
  }

  void snack(String msg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(msg),
      ),
    );
  }

  void _showPermissionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Permissions & Services"),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    askRequiredPermission();
                  },
                  child: const Text("Request Permissions"),
                ),
                const Divider(),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    enableWifi();
                  },
                  child: const Text("Enable Wi-Fi"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    enableLocation();
                  },
                  child: const Text("Enable Location"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    enableBluetooth();
                  },
                  child: const Text("Enable Bluetooth"),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void askRequiredPermission() async {
    var storageGranted = await p2pInterface.askStoragePermission();
    var p2pGranted = await p2pInterface.askP2pPermissions();
    var bleGranted = await p2pInterface.askBluetoothPermissions();
    snack("Storage: $storageGranted, P2P: $p2pGranted, Bluetooth: $bleGranted");
  }

  void enableWifi() async {
    var wifiEnabled = await p2pInterface.enableWifiServices();
    snack("Wi-Fi enabled: $wifiEnabled");
  }

  void enableLocation() async {
    var locationEnabled = await p2pInterface.enableLocationServices();
    snack("Location enabled: $locationEnabled");
  }

  void enableBluetooth() async {
    var bluetoothEnabled = await p2pInterface.enableBluetoothServices();
    snack("Bluetooth enabled: $bluetoothEnabled");
  }

  void createGroup() async {
    snack("Creating group...");
    try {
      await p2pInterface.createGroup();
      snack("Group created. Advertising: ${p2pInterface.isAdvertising}");
    } catch (e) {
      snack("Failed to create group: $e");
    }
    setState(() {});
  }

  void removeGroup() async {
    snack("Removing group...");
    try {
      await p2pInterface.removeGroup();
      snack("Group removed.");
    } catch (e) {
      snack("Failed to remove group: $e");
    }
    setState(() {});
  }

  void shareHotspotWithQrcode() async {
    if (hotspotState == null || !hotspotState!.isActive) {
      snack("Hotspot is not active.");
      return;
    }
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
    if (text.isEmpty) {
      snack('Enter a message to send.');
      return;
    }
    if (!p2pInterface.isGroupCreated) {
      snack('Group not created.');
      return;
    }
    await p2pInterface.broadcastText(text);
    textEditingController.clear();
    snack('Message sent.');
  }

  void sendFile() async {
    if (!p2pInterface.isGroupCreated) {
      snack('Group not created.');
      return;
    }
    String? path = await FilesystemPicker.open(
      context: context,
      title: 'Select file to send',
      fsType: FilesystemType.file,
      rootDirectory: Directory('/storage/emulated/0/'),
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );

    if (path != null) {
      File file = File(path);
      p2pInterface.broadcastFile(file);
      snack("Sending file: ${file.path.split('/').last}");
    } else {
      snack("File selection canceled.");
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isGroupActive =
        p2pInterface.isGroupCreated && hotspotState?.isActive == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Host'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_applications),
            onPressed: _showPermissionsDialog,
            tooltip: "Permissions & Services",
          )
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            _buildSection("Hotspot Control", [
              if (isGroupActive) ...[
                Text("Status: Active",
                    style: const TextStyle(color: Colors.green, fontSize: 16)),
                if (hotspotState?.ssid != null)
                  Text("SSID: ${hotspotState!.ssid!}"),
                if (hotspotState?.preSharedKey != null)
                  Text("Password: ${hotspotState!.preSharedKey!}"),
                if (hotspotState?.hostIpAddress != null)
                  Text("Host IP: ${hotspotState!.hostIpAddress!}"),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code),
                      label: const Text("Share QR"),
                      onPressed: shareHotspotWithQrcode,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text("Remove Group"),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: removeGroup,
                    ),
                  ],
                )
              ] else ...[
                Text(
                    "Status: ${p2pInterface.isGroupCreated ? (hotspotState?.isActive == false ? 'Inactive (Error: ${hotspotState?.failureReason})' : 'Creating...') : 'Not Created'}",
                    style: const TextStyle(color: Colors.orange, fontSize: 16)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text("Create Group"),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: createGroup,
                ),
              ],
            ]),
            _buildSection(
              "Connected Clients",
              [
                StreamBuilder<List<P2pClientInfo>>(
                  stream: p2pInterface.streamClientList(),
                  builder: (context, snapshot) {
                    var clientList = snapshot.data ?? [];
                    clientList = clientList
                        .where((c) => !c.isHost)
                        .toList(); // Exclude host itself
                    if (clientList.isEmpty) {
                      return const Text("No clients connected yet.");
                    }
                    return SizedBox(
                      height: 150,
                      child: ListView.builder(
                        itemCount: clientList.length,
                        itemBuilder: (context, index) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(clientList[index].username),
                            subtitle: Text(clientList[index].id),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            _buildSection(
              "Send Message",
              [
                TextField(
                  controller: textEditingController,
                  decoration: const InputDecoration(hintText: 'Enter message'),
                  enabled: isGroupActive,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Send Text'),
                  onPressed: isGroupActive ? sendMessage : null,
                ),
              ],
            ),
            _buildSection(
              "Send File",
              [
                ElevatedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Select & Send File'),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: isGroupActive ? sendFile : null,
                ),
              ],
            ),
            _buildSection(
              "Sent Files Status",
              [
                StreamBuilder<List<HostedFileInfo>>(
                  stream: p2pInterface.streamSentFilesInfo(),
                  builder: (context, snapshot) {
                    var sentFiles = snapshot.data ?? [];
                    if (sentFiles.isEmpty) {
                      return const Text("No files sent yet.");
                    }
                    return SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: sentFiles.length,
                        itemBuilder: (context, index) {
                          var file = sentFiles[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(file.info.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: file.receiverIds.map((id) {
                                  P2pClientInfo? receiverInfo;
                                  try {
                                    // Get client list from stream, not directly from p2pInterface property for consistency
                                    final currentClients = p2pInterface
                                        .clientList; // Assuming this is kept up-to-date or use another stream
                                    receiverInfo = currentClients
                                        .where((c) => c.id == id)
                                        .firstOrNull;
                                  } catch (_) {}
                                  var name = receiverInfo?.username ??
                                      id.substring(0, min(8, id.length));
                                  var percent =
                                      file.getProgressPercent(id).round();
                                  return Text("$name: $percent%");
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
            _buildSection(
              "Received Files",
              [
                StreamBuilder<List<ReceivableFileInfo>>(
                  stream: p2pInterface.streamReceivedFilesInfo(),
                  builder: (context, snapshot) {
                    var receivedFiles = snapshot.data ?? [];
                    if (receivedFiles.isEmpty) {
                      return const Text("No files received yet.");
                    }
                    return SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: receivedFiles.length,
                        itemBuilder: (context, index) {
                          var file = receivedFiles[index];
                          var percent = file.downloadProgressPercent.round();
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(file.info.name),
                              subtitle:
                                  Text("Status: ${file.state.name}, $percent%"),
                              trailing: file.state == ReceivableFileState.idle
                                  ? ElevatedButton(
                                      onPressed: () async {
                                        snack(
                                            "Downloading ${file.info.name}...");
                                        var downloaded =
                                            await p2pInterface.downloadFile(
                                                file.info.id,
                                                '/storage/emulated/0/Download/');
                                        snack(
                                            "${file.info.name} download: $downloaded");
                                      },
                                      child: const Text('Download'),
                                    )
                                  : (file.state ==
                                          ReceivableFileState.downloading
                                      ? const CircularProgressIndicator()
                                      : (file.state ==
                                              ReceivableFileState.completed
                                          ? const Icon(Icons.check_circle,
                                              color: Colors.green)
                                          : const Icon(Icons.error,
                                              color: Colors.red))),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
