# flutter_p2p_connection

A Flutter plugin for seamless peer-to-peer (P2P) communication on Android using Wi-Fi Direct and Bluetooth Low Energy (BLE). This plugin provides a robust and easy-to-use API for device discovery, connection management, and high-speed data transfer (text and files) between devices in a P2P group.

## Overview

The `flutter_p2p_connection` plugin abstracts the complexities of native Android Wi-Fi Direct and BLE APIs, offering a streamlined experience for Flutter developers. It enables you to build applications with powerful P2P capabilities, such as local multiplayer gaming, file sharing, and collaborative experiences, without requiring an internet connection.

The plugin provides two primary roles:

-   **Host:** Creates a Wi-Fi Direct group (hotspot), manages connected clients, and broadcasts data.
-   **Client:** Discovers nearby hosts using BLE or connects directly using known credentials (e.g., via QR code), and exchanges data.

## Platform Support

Currently, this plugin officially supports **Android**. Support for other platforms like **iOS, Windows, macOS, and Linux** is planned for future releases.

## Features

-   **Wi-Fi Direct Group Management:** Easily create and manage Wi-Fi Direct groups (host mode).
-   **Flexible Discovery & Connection:**
    -   **BLE-based Discovery:** Clients can discover hosts advertising their Wi-Fi credentials via BLE for a seamless user experience.
    -   **Direct Credential Connection:** Clients can connect directly to a host using its SSID and Pre-Shared Key (PSK), which can be shared via QR codes or other manual methods.
-   **High-Speed Data Transfer:**
    -   **Text Messaging:** Broadcast text messages to all peers or send them to specific clients.
    -   **File Transfer:** Share files from the host to clients or from a client to other peers (via the host).
    -   **Progress Tracking:** Monitor file transfer progress with real-time updates.
    -   **Ranged Downloads:** Support for resumable and partial file downloads.
-   **Real-time State Updates:** Utilize streams to get real-time updates on hotspot status, client connection status, and the list of connected clients.
-   **Built-in Permission Handling:** Helper methods are included to simplify checking and requesting necessary Android permissions.
-   **Customizable BLE Service:** Option to use a custom BLE service UUID for more specific advertising and scanning.

## Getting Started

### 1. Installation

Add `flutter_p2p_connection` to your project's `pubspec.yaml` file:

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
            ...
        </activity>
        ...
    </application>
</manifest>
```

**Important Notes on Permissions:**

-   **Runtime Permissions:** This plugin provides helper methods for requesting these permissions at runtime.
-   **Location for Scanning:** On many Android versions, `ACCESS_FINE_LOCATION` is required to perform Wi-Fi and BLE scans, even if your app doesn't use the location data directly.
-   `NEARBY_WIFI_DEVICES`: For Android 13+, this permission allows Wi-Fi device discovery without requiring location if `usesPermissionFlags="neverForLocation"` is set.
-   `BLUETOOTH_SCAN` with `neverForLocation`: If your app uses BLE scan results to derive physical location, you **must not** include `android:usesPermissionFlags="neverForLocation"`.
-   **Storage:** `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` are broad permissions. For Android 10+ (API 29+), consider migrating to Scoped Storage for better user privacy if applicable to your use case. `android:requestLegacyExternalStorage="true"` is a temporary workaround.

### 3. Basic Usage

This plugin offers two main classes for P2P interaction:

-   `FlutterP2pHost`: To create a Wi-Fi Direct group and act as the "server".
-   `FlutterP2pClient`: To discover and connect to a host.

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
    await p2pInterface.askStoragePermission();
  }
  // P2P (Wi-Fi Direct related permissions for creating/connecting to groups)
  if (!await p2pInterface.checkP2pPermissions()) {
    await p2pInterface.askP2pPermissions();
  }
  // Bluetooth (for BLE discovery and connection)
  if (!await p2pInterface.checkBluetoothPermissions()) {
    await p2pInterface.askBluetoothPermissions();
  }
}

// --- Check and Enable Services ---
Future<void> checkAndEnableServices() async {
  // Wi-Fi
  if (!await p2pInterface.checkWifiEnabled()) {
    await p2pInterface.enableWifiServices();
  }
  // Location (often needed for scanning)
  if (!await p2pInterface.checkLocationEnabled()) {
    await p2pInterface.enableLocationServices();
  }
  // Bluetooth (if using BLE features)
  if (!await p2pInterface.checkBluetoothEnabled()) {
    await p2pInterface.enableBluetoothServices();
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

class MyHostWidget extends StatefulWidget {
  // ...
}

class _MyHostWidgetState extends State<MyHostWidget> {
  final _host = FlutterP2pHost();
  // ... other state variables

  @override
  void initState() {
    super.initState();
    _initializeHost();
  }

  Future<void> _initializeHost() async {
    await _host.initialize();
    // ... listen to streams
  }

  Future<void> _createGroupAndAdvertise() async {
    await checkAndRequestPermissions();
    await checkAndEnableServices();
    final state = await _host.createGroup(advertise: true);
    // ...
  }

  Future<void> _removeGroup() async {
    await _host.removeGroup();
  }

  Future<void> _broadcastTextMessage(String message) async {
    await _host.broadcastText(message);
  }

  Future<void> _shareFileWithClients(File fileToShare) async {
    await _host.broadcastFile(fileToShare);
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  // ... UI to call these methods
}
```

#### 3.3. Client Role (`FlutterP2pClient`)

The client discovers hosts (via BLE or manual input) and connects to a chosen host.

```dart
import 'dart:io';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class MyClientWidget extends StatefulWidget {
  // ...
}

class _MyClientWidgetState extends State<MyClientWidget> {
  final _client = FlutterP2pClient();
  // ... other state variables

  @override
  void initState() {
    super.initState();
    _initializeClient();
  }

  Future<void> _initializeClient() async {
    await _client.initialize();
    // ... listen to streams
  }

  Future<void> _startDiscoveryViaBLE() async {
    await checkAndRequestPermissions();
    await checkAndEnableServices();
    await _client.startScan((devices) {
      // ... update UI with discovered devices
    });
  }

  Future<void> _stopDiscovery() async {
    await _client.stopScan();
  }

  Future<void> _connectToDiscoveredHost(BleDiscoveredDevice device) async {
    await _client.connectWithDevice(device);
  }

  Future<void> _connectToHostWithCredentials(String ssid, String psk) async {
    await checkAndRequestPermissions();
    await checkAndEnableServices();
    await _client.connectWithCredentials(ssid, psk);
  }

  Future<void> _disconnectFromHost() async {
    await _client.disconnect();
  }

  Future<void> _sendTextToGroup(String message) async {
    await _client.broadcastText(message);
  }

  Future<void> _shareFileWithGroup(File fileToShare) async {
    await _client.broadcastFile(fileToShare);
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  // ... UI to call these methods
}
```

#### 3.4. Downloading Shared Files (Host and Client)

Both the host and clients can download files that have been shared with them by other peers in the P2P group.

1.  **Listen for Receivable Files:** Subscribe to the `streamReceivedFilesInfo()` stream. This stream emits a `List<ReceivableFileInfo>` whenever new files are announced by other peers or when the status of existing receivable files changes.

2.  **Initiate a Download:** Once a `ReceivableFileInfo` is available, you can initiate the download using the `downloadFile()` method, which is available on both `FlutterP2pHost` and `FlutterP2pClient` instances.

```dart
// In your UI, when a user taps a "Download" button for a specific `ReceivableFileInfo`:
Future<void> startDownload(ReceivableFileInfo receivableFile, String targetDirectory) async {
  // _p2pInstance can be either a FlutterP2pHost or FlutterP2pClient
  await _p2pInstance.downloadFile(
    receivableFile.info.id,
    targetDirectory,
    onProgress: (progress) {
      // Update UI with download progress
      print('Downloading ${progress.progressPercent.toStringAsFixed(2)}%');
    },
  );
}
```

## API Reference

### `FlutterP2pHost`

Manages the creation and operation of a P2P group.

-   `Future<void> initialize()`: Initializes the host.
-   `Future<void> dispose()`: Releases resources.
-   `Future<HotspotHostState> createGroup({bool advertise = true, Duration timeout})`: Creates a Wi-Fi Direct group.
-   `Future<void> removeGroup()`: Removes the group.
-   `Future<void> broadcastText(String text, {List<String>? excludeClientIds})`: Sends a text message to all clients.
-   `Future<bool> sendTextToClient(String text, String clientId)`: Sends a text message to a specific client.
-   `Future<P2pFileInfo?> broadcastFile(File file, {List<String>? excludeClientIds})`: Shares a file with all clients.
-   `Future<P2pFileInfo?> sendFileToClient(File file, String clientId)`: Shares a file with a specific client.
-   `Future<bool> downloadFile(String fileId, String saveDirectory, { ... })`: Downloads a file.
-   `Stream<HotspotHostState> streamHotspotState()`: Stream of hotspot state updates.
-   `Stream<List<P2pClientInfo>> streamClientList()`: Stream of connected clients.
-   `Stream<String> streamReceivedTexts()`: Stream of received text messages.
-   `Stream<List<HostedFileInfo>> streamSentFilesInfo()`: Stream of sent file statuses.
-   `Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo()`: Stream of receivable file statuses.

### `FlutterP2pClient`

Manages discovery of and connection to a P2P host.

-   `Future<void> initialize()`: Initializes the client.
-   `Future<void> dispose()`: Releases resources.
-   `Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(void Function(List<BleDiscoveredDevice>)? onData, { ... })`: Starts scanning for hosts via BLE.
-   `Future<void> stopScan()`: Stops the BLE scan.
-   `Future<void> connectWithDevice(BleDiscoveredDevice device, {Duration timeout})`: Connects to a host discovered via BLE.
-   `Future<void> connectWithCredentials(String ssid, String psk, {Duration timeout})`: Connects to a host using credentials.
-   `Future<void> disconnect()`: Disconnects from the host.
-   `Future<void> broadcastText(String text, {String? excludeClientId})`: Sends a text message to the group.
-   `Future<bool> sendTextToClient(String text, String clientId)`: Sends a text message to a specific client.
-   `Future<P2pFileInfo?> broadcastFile(File file, {List<String>? excludeClientIds})`: Shares a file with the group.
-   `Future<P2pFileInfo?> sendFileToClient(File file, String clientId)`: Shares a file with a specific client.
-   `Future<bool> downloadFile(String fileId, String saveDirectory, { ... })`: Downloads a file.
-   `Stream<HotspotClientState> streamHotspotState()`: Stream of client connection state updates.
-   `Stream<List<P2pClientInfo>> streamClientList()`: Stream of participants in the group.
-   `Stream<String> streamReceivedTexts()`: Stream of received text messages.
-   `Stream<List<HostedFileInfo>> streamSentFilesInfo()`: Stream of sent file statuses.
-   `Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo()`: Stream of receivable file statuses.

## Data Models

The plugin uses several data models to represent states and information:

-   **`HotspotHostState`**: Information about the host's Wi-Fi Direct group (SSID, PSK, host's IP in the group, active status, failure reason).
-   **`HotspotClientState`**: Information about the client's connection to a host (host's SSID, host's gateway IP, client's own IP in the group, active status).
-   **`BleDiscoveredDevice`**: Details of a BLE device found during scanning (name, MAC address).
-   **`P2pClientInfo`**: Represents a participant (host or client) in the P2P group (unique ID, username, whether it's the host).
-   **`P2pFileInfo`**: Metadata for a shared file (unique ID, name, size, sender's ID, sender's IP and port for download).
-   **`HostedFileInfo`**: Tracks a file being shared by the local device. Includes the `P2pFileInfo` and download progress for each recipient.
-   **`ReceivableFileInfo`**: Tracks a file that the local device has been informed about and can download. Includes the `P2pFileInfo`, current download state (`ReceivableFileState`), and download progress percentage.
-   **`FileDownloadProgressUpdate`**: Provides progress updates during a file download (file ID, percentage, bytes downloaded, total size, save path).

## Streams for Real-time Updates

Both `FlutterP2pHost` and `FlutterP2pClient` provide streams to listen for events:

-   **`streamHotspotState()`**: Emits `HotspotHostState` (on Host) or `HotspotClientState` (on Client) updates.
-   **`streamClientList()`**: Emits `List<P2pClientInfo>` whenever the list of participants in the P2P group changes.
-   **`streamReceivedTexts()`**: Emits `String` messages received from other peers.
-   **`streamSentFilesInfo()`**: Emits `List<HostedFileInfo>`, providing the status of files currently being shared by the local device.
-   **`streamReceivedFilesInfo()`**: Emits `List<ReceivableFileInfo>`, listing files that the local device can download.

## Migration Guide v3+ (from older versions)

If you are migrating from a version of this plugin before `v3.0.0`:

1.  **Class Structure:** The single `FlutterP2pConnection` class is removed. You must now use `FlutterP2pHost` for host-side operations and `FlutterP2pClient` for client-side operations.
2.  **Initialization and Disposal:** Both `FlutterP2pHost().initialize()` and `FlutterP2pClient().initialize()` must be called before any other methods. Call `dispose()` on your instance when it's no longer needed.
3.  **Permissions:** The plugin now uses the `permission_handler` package internally. Use the helper methods like `askP2pPermissions()`.
4.  **Wi-Fi Direct Operations:** Methods like `register()`, `unregister()`, `streamWifiP2PInfo()`, `createGroup()`, `removeGroup()`, and `groupInfo()` have been replaced or moved to the new `FlutterP2pHost` and `FlutterP2pClient` classes.
5.  **Discovery:** `discover()` and `stopDiscovery()` are replaced by `FlutterP2pClient().startScan()` and `FlutterP2pClient().stopScan()`.
6.  **Connecting:** `connect()` is replaced by `FlutterP2pClient().connectWithDevice()` (for BLE discovery) and `FlutterP2pClient().connectWithCredentials()` (for manual connection).
7.  **Data Transfer:** The old socket-based methods are removed. Use the new simplified API for text and file transfers (`broadcastText`, `broadcastFile`, `downloadFile`, etc.).

## Troubleshooting

-   **Permissions Not Granted:** Double-check `AndroidManifest.xml` and ensure you request permissions at runtime.
-   **Services Disabled:** Use the plugin's helper methods (`enableWifiServices()`, etc.) to prompt users to enable Wi-Fi, Bluetooth, and Location services.
-   **BLE Issues:** Verify BLE support on the device, ensure Bluetooth is on, and check that the `serviceUuid` matches between host and client if you are using a custom one.
-   **Group Creation Failure:** Inspect the `HotspotHostState.failureReason` from the `streamHotspotState()`.
-   **Connection Timeouts:** Adjust the `timeout` parameters in methods like `createGroup`, `startScan`, and `connectWithDevice`.
-   **Check `adb logcat`:** For in-depth debugging, monitor the Android system logs using `adb logcat`.

## Troubleshooting

-   **Permissions Not Granted:** Double-check `AndroidManifest.xml` and ensure you request permissions at runtime.
-   **Services Disabled:** Use the plugin's helper methods (`enableWifiServices()`, etc.) to prompt users to enable Wi-Fi, Bluetooth, and Location services.
-   **BLE Issues:** Verify BLE support on the device, ensure Bluetooth is on, and check that the `serviceUuid` matches between host and client if you are using a custom one.
-   **Group Creation Failure:** Inspect the `HotspotHostState.failureReason` from the `streamHotspotState()`.
-   **Connection Timeouts:** Adjust the `timeout` parameters in methods like `createGroup`, `startScan`, and `connectWithDevice`.
-   **Check `adb logcat`:** For in-depth debugging, monitor the Android system logs using `adb logcat`.

## Contributions

Contributions, bug reports, and feature requests are welcome! Please feel free to open an issue or submit a pull request on the plugin's GitHub repository.
