# Flutter P2P Connection Plugin

A Flutter plugin for establishing peer-to-peer (P2P) connections on Android devices using Wi-Fi Direct and Bluetooth Low Energy (BLE). This plugin simplifies device discovery, connection management, and data transfer (text and files) between devices in a P2P group.

## Overview

The `flutter_p2p_connection` plugin provides a high-level API to:

- **Act as a Host:** Create a Wi-Fi Direct group (hotspot), manage connected clients, and broadcast data.
- **Act as a Client:** Discover nearby hosts using BLE or connect directly using known credentials (e.g., via QR code), and exchange data.
- **Data Transfer:** Send and receive text messages and files between connected peers.
- **Permission Handling:** Includes helper methods to check and request necessary Android permissions.

This plugin abstracts the complexities of native Android Wi-Fi Direct and BLE APIs, offering a more streamlined experience for Flutter developers.

## Features

- **Wi-Fi Direct Group Management:** Create and remove Wi-Fi Direct groups (host mode).
- **Flexible Discovery & Connection:**
  - **BLE-based Discovery:** Clients can discover hosts advertising their Wi-Fi credentials via BLE.
  - **Direct Credential Connection:** Clients can connect directly to a host using its SSID and Pre-Shared Key (PSK), obtainable through manual methods like QR code scanning. This is useful when BLE is not desired or available.
- **Credential Exchange:** Securely exchange Wi-Fi credentials (SSID & PSK) over BLE (if `advertise: true` on host) or allow manual input/QR scanning.
- **Real-time State Updates:** Streams for hotspot status, client connection status, and connected client lists.
- **Text Messaging:** Broadcast text messages to all peers or send to specific clients.
- **File Transfer:**
  - Share files from host to clients or client to other peers (via host).
  - Download files with progress tracking.
  - Ranged downloads (resumable, partial) for files.
- **Built-in Permission Helpers:** Simplifies checking and asking for required Android permissions.
- **Optional Custom BLE Service UUID:** Allows for more specific BLE advertising and scanning if needed.

## Getting Started

### 1. Installation

Add `flutter_p2p_connection` to your project's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_p2p_connection: ^[latest_version]
```

Then, run `flutter pub get` in your terminal.

### 2. Android Configuration (`AndroidManifest.xml`)

Add the following permissions and features to your `android/app/src/main/AndroidManifest.xml` file:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    package="your.package.name">

    <!-- Internet for WebSocket communication -->
    <uses-permission android:name="android.permission.INTERNET" />

    <!-- Storage permissions (consider Scoped Storage for Android 10+) -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />

    <!-- Location permissions (required for Wi-Fi and BLE scanning) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

    <!-- Nearby Devices Permissions (Android 13 / API 33+) -->
    <!-- Allows scanning for nearby Wi-Fi devices without needing location permission IF this permission is granted -->
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
        android:usesPermissionFlags="neverForLocation"
        tools:targetApi="tiramisu" />

    <!-- Wi-Fi permissions -->
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />

    <!-- Network state permissions -->
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />

    <!-- Bluetooth permissions (Legacy - up to Android 11 / API 30) -->
    <uses-permission android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" />

    <!-- Bluetooth Permissions (New - Android 12 / API 31+) -->
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"
        tools:targetApi="s" />

    <!-- Add 'neverForLocation' if your app doesn't derive physical location from BLE scan results -->
    <!-- Otherwise, your app must declare ACCESS_FINE_LOCATION and obtain user consent -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation"
        tools:targetApi="s" />

    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"
        tools:targetApi="s" />

    <!-- Declare features required by the app -->
    <uses-feature android:name="android.hardware.wifi" android:required="true" />
    <uses-feature android:name="android.hardware.bluetooth" android:required="true" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />


    <application
        android:label="your_app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        <!-- For Android 10 (API 29) and above, if you need broad file access (legacy behavior) -->
        <!-- Recommended to use Scoped Storage for new projects -->
        android:requestLegacyExternalStorage="true">
        <activity
            ...>
            <!-- ... -->
        </activity>
        <!-- ... -->
    </application>
</manifest>
```

**Important Notes on Permissions:**

- **Runtime Permissions:** This plugin provides helper methods for requesting these permissions at runtime.
- **Location for Scanning:** On many Android versions, `ACCESS_FINE_LOCATION` is required to perform Wi-Fi and BLE scans, even if your app doesn't use the location data directly.
- `NEARBY_WIFI_DEVICES`: For Android 13+, this permission allows Wi-Fi device discovery without requiring location if `usesPermissionFlags="neverForLocation"` is set.
- `BLUETOOTH_SCAN` with `neverForLocation`: If your app uses BLE scan results to derive physical location, you **must not** include `android:usesPermissionFlags="neverForLocation"`.
- **Storage:** `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` are broad permissions. For Android 10+ (API 29+), consider migrating to Scoped Storage for better user privacy if applicable to your use case. `android:requestLegacyExternalStorage="true"` is a temporary workaround.

### 3. Basic Usage

This plugin offers two main classes for P2P interaction:

- `FlutterP2pHost`: To create a Wi-Fi Direct group and act as the "server".
- `FlutterP2pClient`: To discover and connect to a host.

#### 3.1. Common Setup (Permissions and Services)

Before initiating P2P operations, ensure necessary permissions are granted and services (Wi-Fi, Location, Bluetooth) are enabled.

```dart
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

// Obtain an instance (can be FlutterP2pHost or FlutterP2pClient)
// For common permission/service checks, either instance can be used.
final p2pInterface = FlutterP2pHost(); // Or FlutterP2pClient();

// --- Check and Request Permissions ---
Future<void> checkAndRequestPermissions() async {
  // Storage (for file transfer)
  if (!await p2pInterface.checkStoragePermission()) {
    final status = await p2pInterface.askStoragePermission();
    print("Storage permission status: $status");
  }
  // P2P (Wi-Fi Direct related permissions for creating/connecting to groups)
  if (!await p2pInterface.checkP2pPermissions()) {
    final status = await p2pInterface.askP2pPermissions();
     print("P2P permission status: $status");
  }
  // Bluetooth (for BLE discovery and connection)
  if (!await p2pInterface.checkBluetoothPermissions()) {
    final status = await p2pInterface.askBluetoothPermissions();
     print("Bluetooth permission status: $status");
  }
}

// --- Check and Enable Services ---
Future<void> checkAndEnableServices() async {
  // Wi-Fi
  if (!await p2pInterface.checkWifiEnabled()) {
    final status = await p2pInterface.enableWifiServices();
    print("Wi-Fi enabled: $status");
  }
  // Location (often needed for scanning)
  if (!await p2pInterface.checkLocationEnabled()) {
    final status = await p2pInterface.enableLocationServices();
     print("Location enabled: $status");
  }
  // Bluetooth (if using BLE features)
  if (!await p2pInterface.checkBluetoothEnabled()) {
    final status = await p2pInterface.enableBluetoothServices();
     print("Bluetooth enabled: $status");
  }
}

// Call these functions early in your app, e.g., in initState or before P2P operations
// await checkAndRequestPermissions();
// await checkAndEnableServices();
```

#### 3.2. Host Role (`FlutterP2pHost`)

The host creates a Wi-Fi Direct group, making itself discoverable (optionally via BLE) and allowing clients to connect.

```dart
import 'dart:io';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class MyHostWidget extends StatefulWidget { /* ... */ }

class _MyHostWidgetState extends State<MyHostWidget> {
  final FlutterP2pHost _host = FlutterP2pHost(
    // Optional: A custom UUID string for the BLE service.
    // If clients use BLE discovery with a custom UUID, it must match this.
    // serviceUuid: "YOUR_CUSTOM_SERVICE_UUID_HERE",
    //
    // Optional: If bonding is required for the BLE service. It is `false` by default.
    // bondingRequired: false,
    //
    // Optional: If encryption is required for the BLE service. It is `false` by default.
    // encryptionRequired: false,
    //
    // Optional: A custom user name for the device.
    // username: 'my custom name',
  );
  StreamSubscription<HotspotHostState>? _hostStateSubscription;
  StreamSubscription<List<P2pClientInfo>>? _clientsSubscription;
  StreamSubscription<String>? _receivedTextSubscription;
  StreamSubscription<List<HostedFileInfo>>? _sentFilesSubscription;
  StreamSubscription<List<ReceivableFileInfo>>? _receivableFilesSubscription;


  HotspotHostState? _currentHostState;

  @override
  void initState() {
    super.initState();
    _initializeHost();
  }

  Future<void> _initializeHost() async {
    // CRITICAL: Initialize before any other operations.
    await _host.initialize();

    _hostStateSubscription = _host.streamHotspotState().listen((state) {
      setState(() => _currentHostState = state);
      if (state.isActive && state.ssid != null) {
        print("Host Active: SSID=${state.ssid}, PSK=${state.preSharedKey}, IP=${state.hostIpAddress}");
        // Now clients can connect using these credentials (e.g., via QR code or BLE if advertised)
      } else if (!state.isActive && _currentHostState?.isActive == true) {
        print("Host became Inactive. Reason code: ${state.failureReason}");
      }
    });

    _clientsSubscription = _host.streamClientList().listen((clients) {
      print("Connected Clients: ${clients.map((c) => '${c.username}(${c.id.substring(0,6)})').toList()}");
    });

    _receivedTextSubscription = _host.streamReceivedTexts().listen((text) {
      print("Host received text: $text");
      // Update UI, show snackbar, etc.
    });

    _sentFilesSubscription = _host.streamSentFilesInfo().listen((files) {
      // Update UI with status of files being sent by this host
      files.forEach((hostedFile) {
        print("Host sharing file: ${hostedFile.info.name}");
        hostedFile.receiverIds.forEach((receiverId) {
          print("  To $receiverId: ${hostedFile.getProgressPercent(receiverId).toStringAsFixed(1)}%");
        });
      });
    });

    _receivableFilesSubscription = _host.streamReceivedFilesInfo().listen((files) {
        // Update UI with files available for download by this host
        // (e.g., if a client shares a file with the host)
        files.forEach((receivableFile) {
             print("Host can download: ${receivableFile.info.name} from ${receivableFile.info.senderId}, State: ${receivableFile.state}");
        });
    });
  }

  Future<void> _createGroupAndAdvertise() async {
    // Ensure permissions and services are handled first
    await checkAndRequestPermissions(); // Implement this as shown in Common Setup
    await checkAndEnableServices();   // Implement this as shown in Common Setup

    try {
      // Creates the Wi-Fi Direct group.
      // advertise: true -> Will also start BLE advertising with hotspot credentials (SSID & PSK).
      // advertise: false -> Only creates the group. Credentials must be shared manually (e.g., QR code).
      final state = await _host.createGroup(advertise: true); // Or advertise: false
      print("Group creation initiated. Advertising: ${_host.isAdvertising}");
    } catch (e) {
      print("Error creating group: $e");
    }
  }

  Future<void> _removeGroup() async {
    try {
      await _host.removeGroup();
      print("Group removed successfully.");
    } catch (e) {
      print("Error removing group: $e");
    }
  }

  Future<void> _broadcastTextMessage(String message) async {
    if (!_host.isGroupCreated || _currentHostState?.isActive != true) {
      print("Host group not active. Cannot send message.");
      return;
    }
    try {
      await _host.broadcastText(message);
      print("Message broadcasted: $message");
    } catch (e) {
      print("Error broadcasting text: $e");
    }
  }

  Future<void> _shareFileWithClients(File fileToShare) async {
    if (!_host.isGroupCreated || _currentHostState?.isActive != true) {
      print("Host group not active. Cannot share file.");
      return;
    }
    try {
      // This makes the file available for download by connected clients.
      // The actualSenderIp is crucial and should be the host's IP in the P2P group.
      // This is typically available from _currentHostState.hostIpAddress.
      P2pFileInfo? fileInfo = await _host.broadcastFile(fileToShare);
      if (fileInfo != null) {
        print("File sharing initiated: ${fileInfo.name} (ID: ${fileInfo.id})");
      } else {
        print("File sharing failed to initiate.");
      }
    } catch (e) {
      print("Error sharing file: $e");
    }
  }

  @override
  void dispose() {
    _hostStateSubscription?.cancel();
    _clientsSubscription?.cancel();
    _receivedTextSubscription?.cancel();
    _sentFilesSubscription?.cancel();
    _receivableFilesSubscription?.cancel();
    _host.dispose(); // CRITICAL: Release native resources
    super.dispose();
  }

  // ... UI to call these methods, display QR codes from _currentHostState.ssid and .preSharedKey
}
```

#### 3.3. Client Role (`FlutterP2pClient`)

The client discovers hosts (via BLE or manual input) and connects to a chosen host.

```dart
import 'dart:io';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class MyClientWidget extends StatefulWidget { /* ... */ }

class _MyClientWidgetState extends State<MyClientWidget> {
  final FlutterP2pClient _client = FlutterP2pClient(
    // Optional: If the host uses a custom BLE service UUID, specify it here for discovery.
    // serviceUuid: "YOUR_CUSTOM_SERVICE_UUID_HERE",
    //
    // Optional: If bonding is required for the BLE service. It is `false` by default.
    // bondingRequired: true,
    //
    // Optional: If encryption is required for the BLE service. It is `false` by default.
    // encryptionRequired: true,
    //
    // Optional: A custom user name for the device.
    // username: 'my custom name',
  );
  StreamSubscription<List<BleDiscoveredDevice>>? _discoverySubscription;
  StreamSubscription<HotspotClientState>? _clientStateSubscription;
  StreamSubscription<List<P2pClientInfo>>? _participantsSubscription;
  StreamSubscription<String>? _receivedTextSubscription;
  StreamSubscription<List<HostedFileInfo>>? _sentFilesSubscription;
  StreamSubscription<List<ReceivableFileInfo>>? _receivableFilesSubscription;


  HotspotClientState? _currentClientState;
  List<BleDiscoveredDevice> _discoveredHosts = [];
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _initializeClient();
  }

  Future<void> _initializeClient() async {
    // CRITICAL: Initialize before any other operations.
    await _client.initialize();

    _clientStateSubscription = _client.streamHotspotState().listen((state) {
      setState(() => _currentClientState = state);
      if (state.isActive) {
        print("Client connected to Host: ${state.hostSsid}, Gateway IP (Host's P2P IP): ${state.hostGatewayIpAddress}, My P2P IP: ${state.hostIpAddress}");
      } else if (!state.isActive && _currentClientState?.isActive == true) {
        print("Client disconnected from host.");
      }
    });

    _participantsSubscription = _client.streamClientList().listen((participants) {
      print("Participants in group: ${participants.map((p) => '${p.username}(Host: ${p.isHost})').toList()}");
    });

     _receivedTextSubscription = _client.streamReceivedTexts().listen((text) {
      print("Client received text: $text");
      // Update UI, show snackbar, etc.
    });

    _sentFilesSubscription = _client.streamSentFilesInfo().listen((files) {
      // Update UI with status of files being sent by this client
      files.forEach((hostedFile) {
        print("Client sharing file: ${hostedFile.info.name}");
         hostedFile.receiverIds.forEach((receiverId) {
          print("  To $receiverId: ${hostedFile.getProgressPercent(receiverId).toStringAsFixed(1)}%");
        });
      });
    });

    _receivableFilesSubscription = _client.streamReceivedFilesInfo().listen((files) {
        // Update UI with files available for download by this client
        files.forEach((receivableFile) {
             print("Client can download: ${receivableFile.info.name} from ${receivableFile.info.senderId}, State: ${receivableFile.state}");
        });
    });
  }

  Future<void> _startDiscoveryViaBLE() async {
    // Ensure permissions and services are handled first
    await checkAndRequestPermissions(); // Implement as shown in Common Setup
    await checkAndEnableServices();   // Implement as shown in Common Setup

    if (_isDiscovering) {
        print("Already discovering.");
        return;
    }
    setState(() {
      _isDiscovering = true;
      _discoveredHosts.clear();
    });
    try {
      _discoverySubscription = await _client.startScan(
        (devices) {
          // This callback provides a list of discovered BLE devices advertising P2P host credentials.
          setState(() => _discoveredHosts = devices);
          print("Discovered hosts: ${devices.map((d) => d.deviceName).toList()}");
        },
        onError: (error) {
          print("BLE Discovery error: $error");
          setState(() => _isDiscovering = false);
        },
        onDone: () {
          print("BLE Discovery finished or timed out.");
          setState(() => _isDiscovering = false);
        },
        timeout: const Duration(seconds: 20), // Scan for 20 seconds
      );
    } catch (e) {
      print("Error starting BLE discovery: $e");
      setState(() => _isDiscovering = false);
    }
  }

  Future<void> _stopDiscovery() async {
    await _client.stopScan();
    setState(() => _isDiscovering = false);
  }

  Future<void> _connectToDiscoveredHost(BleDiscoveredDevice device) async {
    if (_currentClientState?.isActive == true) {
      print("Already connected.");
      return;
    }
    try {
      // This connects to the BLE device to get Wi-Fi credentials, then connects to the Wi-Fi group.
      await _client.connectWithDevice(device);
      print("Connection attempt to ${device.deviceName} successful.");
      _stopDiscovery(); // Stop scanning once connection is attempted/successful
    } catch (e) {
      print("Error connecting to device ${device.deviceName}: $e");
    }
  }

  Future<void> _connectToHostWithCredentials(String ssid, String psk) async {
     if (_currentClientState?.isActive == true) {
      print("Already connected.");
      return;
    }
    // Ensure permissions and services are handled first
    await checkAndRequestPermissions();
    await checkAndEnableServices();
    try {
      // Use this if you get SSID and PSK through other means (e.g., QR code, manual input)
      await _client.connectWithCredentials(ssid, psk);
       print("Connection attempt with credentials to $ssid successful.");
    } catch (e) {
      print("Error connecting with credentials: $e");
    }
  }

  Future<void> _disconnectFromHost() async {
    try {
      await _client.disconnect();
      print("Disconnected from host.");
    } catch (e) {
      print("Error disconnecting: $e");
    }
  }

  Future<void> _sendTextToGroup(String message) async {
    if (_currentClientState?.isActive != true) {
      print("Not connected. Cannot send message.");
      return;
    }
    try {
      // Broadcasts to all other members via the host.
      // The host will relay this message.
      await _client.broadcastText(message);
      print("Client sent message to group: $message");
    } catch (e) {
      print("Error sending text from client: $e");
    }
  }

  Future<void> _shareFileWithGroup(File fileToShare) async {
     if (_currentClientState?.isActive != true) {
      print("Not connected. Cannot share file.");
      return;
    }
    try {
      // This informs the host (and potentially other clients via host relay) about the file.
      // The actualSenderIp should be the client's IP in the P2P group,
      // available from _currentClientState.hostIpAddress.
      P2pFileInfo? fileInfo = await _client.broadcastFile(fileToShare);
      if (fileInfo != null) {
        print("Client initiated file sharing: ${fileInfo.name} (ID: ${fileInfo.id})");
      } else {
        print("Client file sharing failed to initiate.");
      }
    } catch (e) {
      print("Error sharing file from client: $e");
    }
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _clientStateSubscription?.cancel();
    _participantsSubscription?.cancel();
    _receivedTextSubscription?.cancel();
    _sentFilesSubscription?.cancel();
    _receivableFilesSubscription?.cancel();
    _client.dispose(); // CRITICAL: Release native resources
    super.dispose();
  }

  // ... UI to call these methods, display discovered hosts, connection status etc.
}
```

#### 3.4. Downloading Shared Files (Host and Client)

Both the host and clients can download files that have been shared with them by other peers in the P2P group. The process involves:

1.  **Listening for Receivable Files:** Subscribe to the `streamReceivedFilesInfo()` stream. This stream emits a `List<ReceivableFileInfo>` whenever new files are announced by other peers or when the status of existing receivable files changes. Each `ReceivableFileInfo` object contains:

    - `info`: A `P2pFileInfo` object with details about the file (ID, name, size, sender).
    - `state`: A `ReceivableFileState` enum (idle, downloading, completed, error).
    - `downloadProgressPercent`: The current download progress if `state` is `downloading`.
    - `savePath`: The local path where the file is being/was saved.

2.  **Initiating a Download:** Once a `ReceivableFileInfo` is available (and its state is `idle`), you can initiate the download using the `downloadFile()` method. This method is available on both `FlutterP2pHost` and `FlutterP2pClient` instances.

**Example (can be adapted for Host or Client, `_p2pInstance` refers to your host or client object):**

```dart
// Assuming '_p2pInstance' is either your FlutterP2pHost or FlutterP2pClient instance
// and you are subscribed to `_p2pInstance.streamReceivedFilesInfo()`.

// In your UI, you might display a list of receivable files.
// When a user taps a "Download" button for a specific `ReceivableFileInfo receivableFile`:

Future<void> startDownload(ReceivableFileInfo receivableFile, String targetDirectory) async {
  if (receivableFile.state != ReceivableFileState.idle) {
    print("File '${receivableFile.info.name}' is not idle for download. Current state: ${receivableFile.state}");
    return;
  }

  // Ensure the target directory exists
  final Directory saveDir = Directory(targetDirectory);
  if (!await saveDir.exists()) {
    try {
      await saveDir.create(recursive: true);
    } catch (e) {
      print("Error creating save directory '$targetDirectory': $e");
      // Update UI to show error for this file
      return;
    }
  }

  print("Starting download for: ${receivableFile.info.name} (ID: ${receivableFile.info.id})");
  // Your UI should ideally update based on the `streamReceivedFilesInfo` stream,
  // which will reflect the change to `ReceivableFileState.downloading`.

  try {
    bool success = await _p2pInstance.downloadFile(
      receivableFile.info.id,       // The unique ID of the file to download
      targetDirectory,              // The directory to save the file in
      customFileName: null,         // Optional: provide a custom name for the saved file
      deleteOnError: true,          // Optional: if true (default), partially downloaded file is deleted on error
      onProgress: (FileDownloadProgressUpdate progress) {
        // This callback provides real-time progress updates
        print(
            "Downloading '${receivableFile.info.name}': ${progress.progressPercent.toStringAsFixed(1)}% "
            "(${progress.bytesDownloaded}/${progress.totalSize} bytes) -> ${progress.savePath}");
        // Update UI with progress.
        // Note: The `streamReceivedFilesInfo` will also reflect these progress changes.
      },
      // Optional: For resuming downloads or partial downloads
      // rangeStart: 1024, // Example: Start downloading from byte 1024
      // rangeEnd: 2048,   // Example: Download up to byte 2048 (inclusive)
    );

    if (success) {
      print("File '${receivableFile.info.name}' downloaded successfully to $targetDirectory.");
      // UI should update via `streamReceivedFilesInfo` to show 'completed' state
    } else {
      print("File '${receivableFile.info.name}' download failed.");
      // UI should update via `streamReceivedFilesInfo` to show 'error' state
    }
  } catch (e) {
    print("Exception during download of '${receivableFile.info.name}': $e");
    // UI should update via `streamReceivedFilesInfo` to show 'error' state
  }
}

// Example of how you might trigger this from a UI element:
// (Assuming `snapshot.data` from `streamReceivedFilesInfo` provides the list of receivable files)
//
// ReceivableFileInfo currentFileToDownload = snapshot.data![index];
// ElevatedButton(
//   onPressed: () => startDownload(currentFileToDownload, "/storage/emulated/0/Download/"), // Example path
//   child: Text("Download ${currentFileToDownload.info.name}"),
// )
```

**Key points for downloading files:**

- **`fileId`**: This is crucial and is obtained from the `P2pFileInfo.id` within a `ReceivableFileInfo` object (from `streamReceivedFilesInfo()`).
- **`saveDirectory`**: You must specify a valid directory path where the file will be saved. The plugin will attempt to create this directory if it doesn't exist. Ensure your app has write permissions to this location.
- **`onProgress` Callback**: Provides `FileDownloadProgressUpdate` objects, allowing you to display real-time download progress to the user (e.g., percentage, bytes transferred).
- **`streamReceivedFilesInfo()`**: This stream is your primary source for knowing which files are available and their current download status (`ReceivableFileState.idle`, `ReceivableFileState.downloading`, `ReceivableFileState.completed`, `ReceivableFileState.error`) and `downloadProgressPercent`. Your UI should react to updates from this stream to reflect the true state of downloads.
- **Ranged Downloads**: The `rangeStart` and `rangeEnd` parameters allow for partial downloads, which can be useful for implementing resumable downloads if the server supports `Range` requests (which this plugin's file server does).

### 5. Data Models

The plugin uses several data models to represent states and information:

- **`HotspotHostState`**: Information about the host's Wi-Fi Direct group (SSID, PSK, host's IP in the group, active status, failure reason). Crucial for clients to connect.
- **`HotspotClientState`**: Information about the client's connection to a host (host's SSID, host's gateway IP, client's own IP in the group, active status).
- **`BleDiscoveredDevice`**: Details of a BLE device found during scanning (name, MAC address). Used by clients to initiate connection via BLE.
- **`P2pClientInfo`**: Represents a participant (host or client) in the P2P group (unique ID, username, whether it's the host).
- **`P2pFileInfo`**: Metadata for a shared file (unique ID, name, size, sender's ID, sender's IP and port for download).
- **`HostedFileInfo`**: Tracks a file being shared by the local device. Includes the `P2pFileInfo` and download progress for each recipient.
- **`ReceivableFileInfo`**: Tracks a file that the local device has been informed about and can download. Includes the `P2pFileInfo`, current download state (`ReceivableFileState`), and download progress percentage.
- **`FileDownloadProgressUpdate`**: Provides progress updates during a file download (file ID, percentage, bytes downloaded, total size, save path).
- **Enums**:
  - `ReceivableFileState`: State of a downloadable file (idle, downloading, completed, error).

Refer to the source code or use your IDE's autocompletion to explore the detailed properties of these models.

### 6. Streams for Real-time Updates

Both `FlutterP2pHost` and `FlutterP2pClient` provide powerful streams to listen for various events and state changes:

- **`streamHotspotState()`**:
  - On **Host**: Emits `HotspotHostState` updates, providing real-time status of the created group (e.g., when it becomes active with an IP, or if it fails).
  - On **Client**: Emits `HotspotClientState` updates, indicating connection status to the host group (e.g., when connected, disconnected, or IP details change).
- **`streamClientList()`**: Emits `List<P2pClientInfo>` whenever the list of participants in the P2P group changes (e.g., a new client joins or an existing one leaves).
- **`streamReceivedTexts()`**: Emits `String` messages received from other peers in the group.
- **`streamSentFilesInfo()`**: Emits `List<HostedFileInfo>`. This stream updates periodically, providing the status of files currently being shared _by the local device_. It includes progress information for each recipient of those files.
- **`streamReceivedFilesInfo()`**: Emits `List<ReceivableFileInfo>`. This stream updates periodically, listing files that the local device has been informed about (by other peers) and _can download_. It includes the current download state and progress for each such file.

**Important:** Always remember to cancel your stream subscriptions in your widget's `dispose()` method to prevent memory leaks and unexpected behavior.

```dart
// Example:
StreamSubscription<HotspotHostState>? _hostStateSubscription;
// ...
_hostStateSubscription = _host.streamHotspotState().listen((state) { /* ... */ });
// ...
@override
void dispose() {
  _hostStateSubscription?.cancel();
  super.dispose();
}
```

## API Reference (Key Classes, Methods, and Properties)

### `FlutterP2pHost`

Manages the creation and operation of a P2P group (acting as a server/hotspot).

- **Constructor:** `FlutterP2pHost({String? serviceUuid})`
  - `serviceUuid` (Optional): A custom UUID string for the BLE service used for advertising hotspot credentials. If `null`, a default UUID is used. If clients are to discover this host via BLE using a custom UUID, they must be initialized with the same `serviceUuid`.
  - `bondingRequired` (Optional, default: false): Whether bonding is required for the BLE service.
  - `encryptionRequired` (Optional, default: false): Whether encryption is required for the BLE service.
  - `username` (Optional): A custom user name for the device.
- **Key Properties:**
  - `isGroupCreated`: `bool` - True if `createGroup()` has been called and the native group creation process has started.
  - `isAdvertising`: `bool` - True if BLE advertising of hotspot credentials is currently active (occurs if `createGroup(advertise: true)` was successful).
  - `clientList`: `List<P2pClientInfo>` - Provides a snapshot of the current list of connected clients. For real-time updates, use `streamClientList()`.
  - `hostedFileInfos`: `List<HostedFileInfo>` - Snapshot of files currently being shared by this host. Use `streamSentFilesInfo()` for real-time updates.
  - `receivableFileInfos`: `List<ReceivableFileInfo>` - Snapshot of files this host can download (shared by clients). Use `streamReceivedFilesInfo()` for real-time updates.
- **Key Methods:**
  - `Future<void> initialize()`: Initializes native P2P resources for the host. **Must be called before any other host operations.**
  - `Future<void> dispose()`: Releases all native resources, stops the group, and disconnects clients. Call when the host is no longer needed.
  - `Future<HotspotHostState> createGroup({bool advertise = true, Duration timeout = const Duration(seconds: 60)})`: Creates the Wi-Fi Direct group.
    - `advertise`: If `true` (default), starts BLE advertising with hotspot credentials (SSID, PSK) once the group is active.
    - `timeout`: Duration to wait for the group to become active and get an IP address.
  - `Future<void> removeGroup()`: Stops the Wi-Fi Direct group, BLE advertising (if active), and disconnects all clients.
  - `Future<void> broadcastText(String text, {List<String>? excludeClientIds})`: Sends a text message to all connected clients (or a subset if `excludeClientIds` is provided).
  - `Future<bool> sendTextToClient(String text, String clientId)`: Sends a text message to a specific client identified by `clientId`.
  - `Future<P2pFileInfo?> broadcastFile(File file, {List<String>? excludeClientIds})`: Initiates sharing of a `File` with all connected clients (or a subset). Returns `P2pFileInfo` if successful.
  - `Future<P2pFileInfo?> sendFileToClient(File file, String clientId)`: Initiates sharing of a `File` with a specific client.
  - `Future<bool> downloadFile(String fileId, String saveDirectory, {String? customFileName, bool? deleteOnError, Function(FileDownloadProgressUpdate)? onProgress, int? rangeStart, int? rangeEnd})`: Downloads a file that a **client has shared with this host**. The `fileId` is obtained from a `ReceivableFileInfo` object via the `streamReceivedFilesInfo()`.
  - Permission helpers: `checkStoragePermission()`, `askStoragePermission()`, `checkP2pPermissions()`, `askP2pPermissions()`, `checkBluetoothPermissions()`, `askBluetoothPermissions()`.
  - Service enablers: `checkWifiEnabled()`, `enableWifiServices()`, `checkLocationEnabled()`, `enableLocationServices()`, `checkBluetoothEnabled()`, `enableBluetoothServices()`.
  - `Future<String> getDeviceModel()`: Retrieves the model identifier of the current device.
- **Key Streams:**
  - `Stream<HotspotHostState> streamHotspotState()`
  - `Stream<List<P2pClientInfo>> streamClientList()`
  - `Stream<String> streamReceivedTexts()`
  - `Stream<List<HostedFileInfo>> streamSentFilesInfo()`
  - `Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo()`

### `FlutterP2pClient`

Manages discovery of and connection to a P2P host.

- **Constructor:** `FlutterP2pClient({String? serviceUuid})`
  - `serviceUuid` (Optional): A custom UUID string for the BLE service used for scanning for hosts. If `null`, a default UUID is used. If the host is advertising with a custom UUID, this **must match** for discovery to work.
  - `bondingRequired` (Optional, default: true): Whether bonding is required for the BLE service.
  - `encryptionRequired` (Optional, default: true): Whether encryption is required for the BLE service.
  - `username` (Optional): A custom user name for the device
- **Key Properties:**
  - `isScanning`: `bool` - True if BLE scanning for hosts is currently active.
  - `isConnected`: `bool` - True if the client is successfully connected to a host's P2P transport layer.
  - `clientList`: `List<P2pClientInfo>` - Snapshot of the current list of participants in the P2P group (including self and the host). Use `streamClientList()` for real-time updates.
  - `hostedFileInfos`: `List<HostedFileInfo>` - Snapshot of files currently being shared by this client. Use `streamSentFilesInfo()` for real-time updates.
  - `receivableFileInfos`: `List<ReceivableFileInfo>` - Snapshot of files this client can download (shared by the host or other clients). Use `streamReceivedFilesInfo()` for real-time updates.
- **Key Methods:**
  - `Future<void> initialize()`: Initializes native P2P resources for the client. **Must be called before any other client operations.**
  - `Future<void> dispose()`: Releases all native resources and disconnects from any host. Call when the client is no longer needed.
  - `Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(void Function(List<BleDiscoveredDevice>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError, Duration timeout = const Duration(seconds: 15)})`: Starts BLE scanning for hosts advertising P2P credentials.
  - `Future<void> stopScan()`: Stops an ongoing BLE scan.
  - `Future<void> connectWithDevice(BleDiscoveredDevice device, {Duration timeout = const Duration(seconds: 20)})`: Connects to a host discovered via BLE. This involves connecting to the BLE device to retrieve Wi-Fi credentials and then connecting to the Wi-Fi Direct group.
  - `Future<void> connectWithCredentials(String ssid, String psk, {Duration timeout = const Duration(seconds: 60)})`: Connects directly to a host using its known Wi-Fi `ssid` and `psk` (password). Useful if credentials are obtained via QR code or other manual means.
  - `Future<void> disconnect()`: Disconnects from the currently connected host.
  - `Future<void> broadcastText(String text, {String? excludeClientId})`: Sends a text message to other members of the group (relayed via the host).
  - `Future<bool> sendTextToClient(String text, String clientId)`: Sends a text message to a specific member of the group (relayed via the host).
  - `Future<P2pFileInfo?> broadcastFile(File file, {List<String>? excludeClientIds})`: Initiates sharing of a `File` with other members of the group (relayed via the host).
  - `Future<P2pFileInfo?> sendFileToClient(File file, String clientId)`: Initiates sharing of a `File` with a specific member (relayed via the host).
  - `Future<bool> downloadFile(String fileId, String saveDirectory, {String? customFileName, bool? deleteOnError, Function(FileDownloadProgressUpdate)? onProgress, int? rangeStart, int? rangeEnd})`: Downloads a file shared **by the host or another client** within the group. The `fileId` is obtained from a `ReceivableFileInfo` object via the `streamReceivedFilesInfo()`.
  - Permission helpers: (Same as `FlutterP2pHost`)
  - Service enablers: (Same as `FlutterP2pHost`)
  - `Future<String> getDeviceModel()`: (Same as `FlutterP2pHost`)
- **Key Streams:**
  - `Stream<HotspotClientState> streamHotspotState()`
  - `Stream<List<P2pClientInfo>> streamClientList()`
  - `Stream<String> streamReceivedTexts()`
  - `Stream<List<HostedFileInfo>> streamSentFilesInfo()`
  - `Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo()`

## Example Usage

The example app provided in the `/example` directory (`example/lib/host.dart` and `example/lib/client.dart`) demonstrates comprehensive usage of both `FlutterP2pHost` and `FlutterP2pClient`. Key functionalities showcased include:

- Requesting necessary permissions and enabling system services (Wi-Fi, Location, Bluetooth).
- **Host:** Creating a P2P group, optionally advertising credentials via BLE.
- **Host:** Displaying active hotspot information (SSID, PSK, IP) for manual sharing (e.g., via QR code).
- **Client:** Scanning for hosts via BLE.
- **Client:** Connecting to a host using discovered BLE device information.
- **Client:** Connecting to a host using credentials obtained manually (e.g., by scanning a QR code containing SSID and PSK).
- Displaying connection status and lists of connected participants for both host and client.
- Sending and receiving text messages between peers.
- Sharing files from host to clients and client to other peers.
- Downloading files with real-time progress updates.
- Monitoring the status of sent and receivable files.

It is highly recommended to review the example code for practical implementation details.

## Migration Guide v3+ (from older versions)

If you are migrating from a version of this plugin _before_ the major refactoring that introduced separate `FlutterP2pHost` and `FlutterP2pClient` classes typically versions before `v3.0.0`:

1.  **Class Structure:**

    - The single `FlutterP2pConnection` class is **removed**.
    - You **must** now use `FlutterP2pHost` for host-side operations (creating and managing a group) and `FlutterP2pClient` for client-side operations (discovering and connecting to a group).
    - Instantiate the appropriate class based on the device's intended role in the P2P interaction.

2.  **Initialization and Disposal:**

    - Both `FlutterP2pHost().initialize()` and `FlutterP2pClient().initialize()` **must** be called **before any other methods** on their respective instances. This step prepares the native P2P and BLE components.
    - It is **crucial** to call `dispose()` on your `FlutterP2pHost` or `FlutterP2pClient` instance when it's no longer needed (typically in your widget's `dispose()` method). This releases native resources, stops services, and prevents memory leaks.

3.  **Permissions:**

    - The plugin now directly uses the `permission_handler` package internally for requesting Android permissions. You no longer need to add `permission_handler` as a separate dependency in your `pubspec.yaml` _unless_ you are using its API directly for other parts of your application.
    - Utilize the convenient permission helper methods provided by both `FlutterP2pHost` and `FlutterP2pClient` (e.g., `askP2pPermissions()`, `askBluetoothPermissions()`, `askStoragePermission()`).

4.  **Wi-Fi Direct Operations (Old API vs. New):**

    - **Old:** `_flutterP2pConnectionPlugin.register()`, `_flutterP2pConnectionPlugin.unregister()`: These methods are **Removed**. Initialization and resource management are now handled by the `initialize()` and `dispose()` methods of the `FlutterP2pHost` and `FlutterP2pClient` classes. Lifecycle management for native event registration is handled internally by the plugin.
    - **Old:** `_flutterP2pConnectionPlugin.streamWifiP2PInfo()`: This stream is **Replaced**.
      - For **Host** operations: Use `_host.streamHotspotState()`, which yields `HotspotHostState` objects containing SSID, PSK, IP address, and active status of the created group.
      - For **Client** operations: Use `_client.streamHotspotState()`, which yields `HotspotClientState` objects detailing the connection status to the host group.
    - **Old:** `_flutterP2pConnectionPlugin.createGroup()`: This functionality is **Moved** to `FlutterP2pHost().createGroup()`.
    - **Old:** `_flutterP2pConnectionPlugin.removeGroup()`:
      - For **Host**: **Moved** to `FlutterP2pHost().removeGroup()`.
      - For **Client** (to disconnect from a group): **Replaced** by `FlutterP2pClient().disconnect()`.
    - **Old:** `_flutterP2pConnectionPlugin.groupInfo()`: This method is **Replaced**. The relevant group information is now available through the `HotspotHostState` (for hosts) or `HotspotClientState` (for clients) obtained from their respective `streamHotspotState()` streams.

5.  **Discovery (Old API vs. New):**

    - **Old:** `_flutterP2pConnectionPlugin.discover()`, `_flutterP2pConnectionPlugin.stopDiscovery()`: These are **Replaced** by `FlutterP2pClient().startScan(...)` and `FlutterP2pClient().stopScan()`. The new `startScan` method specifically uses BLE for discovering hosts that are advertising their P2P credentials. It requires callbacks to handle the list of discovered devices (`onData`), errors (`onError`), and scan completion (`onDone`).
    - **Old:** `_flutterP2pConnectionPlugin.streamPeers()`: This stream is **Replaced**.
      - For discovering hosts: The `onData` callback of `FlutterP2pClient().startScan()` provides the `List<BleDiscoveredDevice>`.
      - For listing all participants _after_ connecting to a group: Use `streamClientList()` available on both `FlutterP2pHost` and `FlutterP2pClient`.

6.  **Connecting to a Device (Old API vs. New):**

    - **Old:** `_flutterP2pConnectionPlugin.connect(deviceAddress)`: This method is **Replaced**. The connection process is now more explicit about the discovery method.
      - **BLE Discovery:** After discovering a host using `FlutterP2pClient().startScan()`, connect to it using `FlutterP2pClient().connectWithDevice(BleDiscoveredDevice device)`. This method handles the BLE handshake to retrieve Wi-Fi credentials and then establishes the Wi-Fi Direct connection.
      - **Manual Credentials:** If you obtain the host's SSID and PSK through other means (e.g., QR code scanned by the client, manual input), use `FlutterP2pClient().connectWithCredentials(String ssid, String psk)`.

7.  **Data Transfer (Sockets vs. New API):**
    - **Old API (socket-based):** `startSocket()`, `connectToSocket()`, `sendStringToSocket()`, `sendFiletoSocket()`, `closeSocket()`, the `transferUpdate` stream, and the `receiveString` callback are **All Removed/Replaced**.
    - **New Text Transfer API:**
      - **Host Sending:** `_host.broadcastText(message)` (to all clients) or `_host.sendTextToClient(message, clientId)` (to a specific client).
      - **Client Sending:** `_client.broadcastText(message)` (relayed via host to all others) or `_client.sendTextToClient(message, clientId)` (relayed via host to a specific peer).
      - **Receiving:** Listen to the `streamReceivedTexts()` on both `FlutterP2pHost` and `FlutterP2pClient` instances.
    - **New File Transfer API:**
      - **Host Sharing:** `_host.broadcastFile(file)` or `_host.sendFileToClient(file, clientId)`.
      - **Client Sharing:** `_client.broadcastFile(file)` or `_client.sendFileToClient(file, clientId)` (files are offered to the group via the host).
      - **Downloading Files:** Both host and client can download files offered by other peers using their respective `downloadFile(fileId, saveDirectory, ...)` methods. The `fileId` is obtained from a `ReceivableFileInfo` object (from `streamReceivedFilesInfo()`). The `downloadFile` method includes an `onProgress` callback that provides `FileDownloadProgressUpdate` objects.
      - **Monitoring Shared/Receivable Files:**
        - `streamSentFilesInfo()`: Track files being shared _by the local device_ and their send progress to recipients.
        - `streamReceivedFilesInfo()`: Discover files shared _by other peers_ that are available for the local device to download.

In summary, the plugin has evolved from a single-class, primarily Wi-Fi Direct-focused model to a more comprehensive and robust dual-class (Host/Client) architecture. This new structure leverages BLE for enhanced discovery and credential exchange (while still supporting manual credential methods) and provides a simplified, unified API for text and file transfers over an internally managed WebSocket transport layer. The previous manual socket management is no longer required.

## Troubleshooting

- **Permissions Not Granted:**
  1.  Double-check that all required permissions are correctly listed in your `AndroidManifest.xml`.
  2.  Ensure your app properly requests these permissions at runtime using the plugin's helper methods (e.g., `askP2pPermissions()`, `askBluetoothPermissions()`) or by directly using the `permission_handler` package if you prefer more granular control.
  3.  Provide clear explanations to your users why each permission is necessary.
- **Services Disabled:** Wi-Fi, Bluetooth, and Location services are essential for the plugin's functionality. Use the plugin's helper methods (e.g., `enableWifiServices()`) to prompt users to enable them if they are found to be off.
- **BLE Issues:**
  - Verify that the target device supports Bluetooth Low Energy (BLE).
  - Ensure Bluetooth is turned on in the device settings.
  - If you are using a custom `serviceUuid` for `FlutterP2pHost` and `FlutterP2pClient`, ensure the UUID string is identical on both the advertising host and the scanning client.
- **Wi-Fi Direct Group Creation Failure (Host):**
  - Inspect the `HotspotHostState.failureReason` code provided in the `streamHotspotState()` for indications of the problem.
  - Ensure no other application is currently using Wi-Fi Direct in a conflicting manner (e.g., another app acting as a group owner or engaged in a P2P connection).
  - Temporary network glitches can sometimes interfere; a retry might resolve the issue.
- **Connection Timeouts:**
  - Network conditions, physical distance between devices, and interference can affect connection stability and lead to timeouts.
  - The `timeout` parameters in methods like `createGroup`, `startScan`, `connectWithDevice`, and `connectWithCredentials` can be adjusted based on your expected environment, but excessively long timeouts can lead to poor user experience.
- **Firewall/Network Issues:** In some restrictive network environments (e.g., corporate Wi-Fi with client isolation, or VPNs), P2P connections might be blocked or hindered.
- **Device Compatibility:** Wi-Fi Direct and BLE feature implementations can have slight variations across different device manufacturers and Android OS versions. Thorough testing on a diverse range of target devices is recommended.
- **Check `adb logcat`:** For more in-depth debugging, monitor the Android system logs using `adb logcat`. Filter for tags related to the plugin (e.g., `FlutterP2PConnection`, `P2P Transport Host`, `P2P Transport Client`, `FlutterP2pPlugin`) to find error messages or diagnostic information from the native Android P2P and BLE layers.

## Contributions

Contributions, bug reports, and feature requests are highly encouraged and appreciated! Please feel free to open an issue or submit a pull request on the plugin's GitHub repository.
