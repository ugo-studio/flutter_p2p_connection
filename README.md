# flutter_p2p_connection

A p2p wifi direct plugin.

## Getting Started

### Required permissions

Add these permissions to AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```

### Request Permissions

```dart
// check if location permission is granted
FlutterP2pConnection().checkLocationPermission();

// request location permission
FlutterP2pConnection().askLocationPermission();

// check if location is enabled
FlutterP2pConnection().checkLocationEnabled();

// enable location
FlutterP2pConnection().enableLocationServices();

// check if wifi is enabled
FlutterP2pConnection().checkWifiEnabled();

// enable wifi
FlutterP2pConnection().enableWifiServices();
```

### Register / unregister from WiFi events

To receive notifications for connection changes or device changes (peers discovered etc.) you have
to subscribe to the wifiEvents and register the plugin to the native events.

```dart
class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final _flutterP2pConnectionPlugin = FlutterP2pConnection();

  StreamSubscription<WifiP2PInfo>? _streamWifiInfo;
  StreamSubscription<List<DiscoveredPeers>>? _streamPeers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flutterP2pConnectionPlugin.unregister();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flutterP2pConnectionPlugin.register();
    } else if (state == AppLifecycleState.resumed) {
      _flutterP2pConnectionPlugin.unregister();
    }
  }

  void _init() async {
    await _flutterP2pConnectionPlugin.initialize();
    await _flutterP2pConnectionPlugin.register();
    _streamWifiInfo = _flutterP2pConnectionPlugin.streamWifiP2PInfo().listen((event) {
        // Handle changes of the connection
    });
    _streamPeers = _flutterP2pConnectionPlugin.streamPeers().listen((event) {
        // Handle discovered peers
    });
  }
}
```

### Create Group

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();

_flutterP2pConnectionPlugin.createGroup();
```

### Remove Group

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();

_flutterP2pConnectionPlugin.removeGroup();
```

### Discover devices

After you subscribed to the events, enable wifi and location with `FlutterP2pConnection().enableWifiServices()` and `FlutterP2pConnection().enableLocationServices()` method, then call the `FlutterP2pConnection().discover()` to discover peers. To stop discovery call the `FlutterP2pConnection().stopDiscovery()` method.

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();
List<DiscoveredPeers> peers = [];

void _init() async {

  /// ...

  _streamPeers = _flutterP2pConnectionPlugin.streamPeers().listen((event) {
    if (peers != event) {
        setState(() {
            peers = event;
        });
    }
  });

  /// ...
}

void discover() {
  _flutterP2pConnectionPlugin.discover();
}

void stopDiscovery() {
  _flutterP2pConnectionPlugin.stopDiscovery();
}
```

### Connect to a device

Call `FlutterP2pConnection().connect(deviceAddress);` and listen to the `FlutterP2pConnection().streamWifiP2PInfo`

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();
 WifiP2PInfo? wifiP2PInfo;
 List<DiscoveredPeers> peers = [];

 void _init() async {
    // ...

    _streamWifiInfo = _flutterP2pConnectionPlugin.streamWifiP2PInfo().listen((event) {
        if (wifiP2PInfo != event) {
            setState(() {
                wifiP2PInfo = event;
            });
        }
    });

    // ...
  }

  void connect() async {
    await _flutterP2pConnectionPlugin.connect(peers[0].deviceAddress);
  }
```

### Disconnect from current P2P group

Call `FlutterP2pConnection().removeGroup()`

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();

void _disconnect() async {
  _flutterP2pConnectionPlugin.removeGroup();
}
```

### Transferring data between devices

After you are connected to a device you can transfer data async in both directions (client -> host, host -> client).

On the host:

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();
WifiP2PInfo? wifiP2PInfo;

// create a socket
Future startSocket() async {
  if (wifiP2PInfo != null) {
    await _flutterP2pConnectionPlugin.startSocket(
      groupOwnerAddress: wifiP2PInfo!.groupOwnerAddress!,
      onConnect: (address) {
        print("opened a socket at: $address");
      },
      onRequest: (req) async {
        // handle message from client
        print(req);
      },
    );
  }
}
```

On the client:

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();
WifiP2PInfo? wifiP2PInfo;

// Connect to socket
Future connectToSocket() async {
  if (wifiP2PInfo != null) {
    await _flutterP2pConnectionPlugin.connectToSocket(
      groupOwnerAddress: wifiP2PInfo!.groupOwnerAddress!,
      onConnect: (address) {
        print("connected to socket: $address");
      },
      onRequest: (req) async {
        // handle message from server
        print(req);
      },
    );
  }
}
```

Transfer String:

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();

_flutterP2pConnectionPlugin.sendStringToSocket("message");
```

To close socket call:

```dart
final _flutterP2pConnectionPlugin = FlutterP2pConnection();

_flutterP2pConnectionPlugin.closeSocket();
```
