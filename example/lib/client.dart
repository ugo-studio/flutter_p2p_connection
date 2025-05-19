import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_p2p_connection_example/qr/scanner_page.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final TextEditingController textEditingController = TextEditingController();
  late FlutterP2pClient p2pInterface;

  StreamSubscription<HotspotClientState>? hotspotStateStream;
  StreamSubscription<String>? receivedTextStream;

  HotspotClientState? hotspotState;
  List<BleDiscoveredDevice> discoveredDevices = [];
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    p2pInterface = FlutterP2pClient();
    p2pInterface.initialize().whenComplete(() {
      hotspotStateStream = p2pInterface.streamHotspotState().listen((state) {
        setState(() {
          hotspotState = state;
        });
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

  void startPeerDiscovery() async {
    if (_isDiscovering) {
      snack('Already discovering peers.');
      return;
    }
    setState(() {
      _isDiscovering = true;
      discoveredDevices.clear();
    });
    snack('Starting peer discovery...');
    try {
      await p2pInterface.startScan(
        (devices) {
          setState(() {
            discoveredDevices = devices;
          });
        },
        onDone: () {
          setState(() {
            _isDiscovering = false;
          });
          snack('Peer discovery finished.');
        },
        onError: (error) {
          setState(() {
            _isDiscovering = false;
          });
          snack('Peer discovery error: $error');
        },
      );
    } catch (e) {
      setState(() {
        _isDiscovering = false;
      });
      snack('Failed to start peer discovery: $e');
    }
  }

  void connectWithDevice(BleDiscoveredDevice device) async {
    snack('Connecting to ${device.deviceName}...');
    try {
      await p2pInterface.connectWithDevice(device);
      snack('Connected to ${device.deviceName}');
      setState(() {
        discoveredDevices.clear();
        _isDiscovering = false;
      });
    } catch (e) {
      snack('Failed to connect: $e');
    }
  }

  void connectWithCredentials(String ssid, String preSharedKey) async {
    snack('Connecting with credentials...');
    try {
      await p2pInterface.connectWithCredentials(ssid, preSharedKey);
      snack("Connected to $ssid");
    } catch (e) {
      snack("Failed to connect: $e");
    }
  }

  void disconnect() async {
    snack('Disconnecting...');
    await p2pInterface.disconnect();
    snack("Disconnected");
    setState(() {});
  }

  void sendMessage() async {
    var text = textEditingController.text;
    if (text.isEmpty) {
      snack('Enter a message to send.');
      return;
    }
    if (!(hotspotState?.isActive == true)) {
      snack('Not connected to any host.');
      return;
    }
    await p2pInterface.broadcastText(text);
    textEditingController.clear();
    snack('Message sent.');
  }

  void sendFile() async {
    if (!(hotspotState?.isActive == true)) {
      snack('Not connected to any host.');
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
    bool isConnected = hotspotState?.isActive == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Client'),
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
            _buildSection(
              "Connection Status",
              [
                Text(
                  isConnected
                      ? "Connected to: ${hotspotState?.hostSsid ?? 'Unknown'}"
                      : "Not Connected",
                  style: TextStyle(
                      color: isConnected ? Colors.green : Colors.red,
                      fontSize: 16),
                ),
                if (isConnected && hotspotState?.hostGatewayIpAddress != null)
                  Text("Host IP: ${hotspotState!.hostGatewayIpAddress!}"),
                if (isConnected && hotspotState?.hostIpAddress != null)
                  Text("My IP: ${hotspotState!.hostIpAddress!}"),
              ],
            ),
            _buildSection(
              "Connect to Host",
              [
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                    ElevatedButton.icon(
                      icon: _isDiscovering
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.bluetooth_searching),
                      label: Text(_isDiscovering
                          ? "Discovering... (${discoveredDevices.length})"
                          : "Discover (BLE)"),
                      onPressed: !isConnected && !_isDiscovering
                          ? startPeerDiscovery
                          : null,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text("Scan QR"),
                      onPressed: !isConnected
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ScannerPage(
                                    onScanned: connectWithCredentials,
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                    if (isConnected)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.link_off),
                        label: const Text("Disconnect"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange),
                        onPressed: disconnect,
                      ),
                  ],
                ),
              ],
            ),
            if (discoveredDevices.isNotEmpty && !isConnected)
              _buildSection(
                "Discovered Hosts",
                [
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      itemCount: discoveredDevices.length,
                      itemBuilder: (context, index) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(discoveredDevices[index].deviceName),
                          subtitle:
                              Text(discoveredDevices[index].deviceAddress),
                          trailing: ElevatedButton(
                            onPressed: () =>
                                connectWithDevice(discoveredDevices[index]),
                            child: const Text("Connect"),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            _buildSection(
              "Participants",
              [
                StreamBuilder<List<P2pClientInfo>>(
                  stream: p2pInterface.streamClientList(),
                  builder: (context, snapshot) {
                    var clientList = snapshot.data ?? [];
                    if (clientList.isEmpty) {
                      return const Text("No other participants yet.");
                    }
                    return SizedBox(
                      height: 100,
                      child: ListView.builder(
                        itemCount: clientList.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(clientList[index].username),
                          subtitle: Text('Host: ${clientList[index].isHost}'),
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
                  enabled: isConnected,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Send Text'),
                  onPressed: isConnected ? sendMessage : null,
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
                  onPressed: isConnected ? sendFile : null,
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
                                    receiverInfo = p2pInterface.clientList
                                        .firstWhere((c) => c.id == id);
                                  } catch (_) {}
                                  var name = receiverInfo?.username ??
                                      id.substring(0, min(8, id.length));
                                  var percent =
                                      file.getProgressPercent(id).round();
                                  return Text(
                                      "$name: ${file.state.name}, $percent%");
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
          ],
        ),
      ),
    );
  }
}
