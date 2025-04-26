import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/p2p_transport.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_p2p_connection_platform_interface.dart';

// Default port for the custom P2P transport layer if not specified otherwise.
const int _defaultP2pTransportPort = 3434;

/// The [FlutterP2pConnectionHost] class facilitates creating and managing a
/// Wi-Fi Direct group (acting as a hotspot host) for P2P connections.
///
/// It allows initializing the host, creating a group (optionally advertising
/// credentials via BLE), removing the group, listening for state changes,
/// and sending/receiving data via the underlying [P2pTransportHost].
class FlutterP2pConnectionHost {
  // Internal state flags
  bool _isGroupCreated = false;
  bool _isBleAdvertising = false;
  // Instance of the transport layer handler for the host.
  P2pTransportHost? _p2pTransport;

  /// Returns `true` if a Wi-Fi Direct group has been successfully created.
  bool get isGroupCreated => _isGroupCreated;

  /// Returns `true` if the host is currently advertising hotspot credentials via BLE.
  bool get isAdvertising => _isBleAdvertising;

  /// Initializes the P2P connection host resources on the native platform.
  ///
  /// This method must be called before any other host operations.
  /// It prepares the underlying platform-specific components.
  Future<void> initialize() async {
    _p2pTransport = null; // Ensure transport is reset on initialize
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes of the P2P connection host resources and cleans up connections.
  ///
  /// This method should be called when the host functionality is no longer needed
  /// to release system resources. It attempts to remove any active group and stop
  /// the transport layer first.
  Future<void> dispose() async {
    // Ensure the group is removed (which stops transport) before disposing platform resources.
    await removeGroup().catchError((_) => null);
    await FlutterP2pConnectionPlatform.instance.dispose();
    debugPrint("FlutterP2pConnectionHost disposed.");
  }

  /// Creates a Wi-Fi Direct group (hotspot) for P2P connections and starts the transport layer.
  ///
  /// After successful creation, it retrieves the hotspot's [HotspotHostState]
  /// containing the SSID, Pre-Shared Key (PSK), and the host's IP address.
  /// It then initializes and starts the [P2pTransportHost] on the obtained IP address.
  ///
  /// By default (`advertise = true`), it also starts advertising these credentials
  /// via Bluetooth Low Energy (BLE) to allow clients to discover and connect.
  ///
  /// Throws an [Exception] or [TimeoutException] if the hotspot credentials (SSID/PSK/IP) cannot be
  /// obtained within the timeout period.
  ///
  /// - [advertise]: If `true`, starts BLE advertising with the hotspot credentials.
  ///                Defaults to `true`.
  /// - [timeout]: Duration to wait for hotspot state confirmation (including IP). Defaults to 15 seconds.
  ///
  /// Returns a [Future] completing with the [HotspotHostState] containing
  /// connection details (SSID, PSK, IP address).
  Future<HotspotHostState> createGroup({
    bool advertise = true,
    Duration timeout = const Duration(seconds: 60), // Increased timeout
  }) async {
    // Stop any existing transport first
    await _p2pTransport?.stop().catchError((e) {
      debugPrint('Error stopping previous P2P transport: $e');
    });
    _p2pTransport = null;

    // Initiate hotspot creation on the native side.
    await FlutterP2pConnectionPlatform.instance.createHotspot();
    _isGroupCreated = true;
    debugPrint("Host: Native hotspot creation initiated.");

    // Wait for the hotspot state update containing valid credentials.
    HotspotHostState state;
    try {
      debugPrint("Host: Waiting for active state...");
      state = await streamHotspotState()
          .firstWhere((s) =>
              s.isActive && // Ensure group is active
              s.ssid != null &&
              s.preSharedKey != null)
          .timeout(
        timeout,
        onTimeout: () {
          // Throw a specific exception on timeout
          throw TimeoutException(
              'Host: Timed out after $timeout waiting for active hotspot state.');
        },
      );
      debugPrint("Host: Received active state: $state");
    } catch (e) {
      debugPrint("Host: Error waiting for hotspot state: $e");
      // Cleanup if state acquisition failed
      await removeGroup().catchError((_) => null);
      rethrow; // Propagate the error (could be TimeoutException or stream error)
    }

    // Start BLE advertising if requested and credentials are valid.
    if (advertise) {
      try {
        await FlutterP2pConnectionPlatform.instance.startBleAdvertising(
          state.ssid!,
          state.preSharedKey!,
        );
        _isBleAdvertising = true;
        debugPrint("Host: BLE advertising started.");
      } catch (e) {
        // If advertising fails, log it but don't necessarily fail the group creation.
        debugPrint('Host: Failed to start BLE advertising: $e');
        _isBleAdvertising = false;
        // Cleanup if state acquisition failed
        await removeGroup().catchError((_) => null);
        // Optionally rethrow if advertising is critical: throw Exception('Failed to start BLE advertising: $e');
      }
    } else {
      _isBleAdvertising = false;
    }

    // Create and start p2p transport stream
    // The host IP address MUST be non-null here due to the firstWhere check above.
    _p2pTransport = P2pTransportHost(
      defaultPort: _defaultP2pTransportPort,
      username: await FlutterP2pConnectionPlatform.instance.getPlatformModel(),
    );
    try {
      await _p2pTransport!.start();
    } catch (e) {
      debugPrint('Host: Failed to start P2P Transport: $e');
      // Clean up group if transport fails to start, as it's likely unusable
      await removeGroup().catchError((_) => null);
      throw Exception('Host: Failed to start P2P Transport: $e');
    }

    return state; // Return the obtained hotspot state.
  }

  /// Removes the currently active Wi-Fi Direct group (hotspot).
  ///
  /// This stops BLE advertising (if active), stops the P2P transport layer,
  /// and tears down the native hotspot group.
  Future<void> removeGroup() async {
    debugPrint("Host: Removing group...");
    // Stop BLE advertising if it was active.
    if (_isBleAdvertising) {
      await FlutterP2pConnectionPlatform.instance
          .stopBleAdvertising()
          .catchError((e) {
        // Log error but continue cleanup
        debugPrint('Host: Error stopping BLE advertising: $e');
      });
      _isBleAdvertising = false;
      debugPrint("Host: BLE advertising stopped.");
    }

    // Stop the transport layer if it exists and is running.
    await _p2pTransport?.stop().catchError((e) {
      debugPrint('Host: Error stopping P2P transport: $e');
    });
    _p2pTransport = null;
    debugPrint("Host: P2P transport stopped.");

    // Remove the hotspot on the native side if a group was created.
    if (_isGroupCreated) {
      await FlutterP2pConnectionPlatform.instance
          .removeHotspot()
          .catchError((e) {
        // Log error but update state anyway
        debugPrint('Host: Error removing hotspot group natively: $e');
      });
      _isGroupCreated = false;
      debugPrint("Host: Native hotspot removed.");
    }
    debugPrint("Host: Group removal process finished.");
  }

  /// Provides a stream of [HotspotHostState] updates from the platform.
  ///
  /// Listen to this stream to receive real-time information about the host's
  /// hotspot status, including whether it's active, its SSID, PSK, IP address,
  /// and any failure reasons.
  ///
  /// Returns a [Stream] of [HotspotHostState].
  Stream<HotspotHostState> streamHotspotState() {
    return FlutterP2pConnectionPlatform.instance.streamHotspotInfo();
  }

  /// Provides a stream of messages received from connected clients via the P2P transport layer.
  ///
  /// This stream emits [P2pMessage] objects received from any connected client.
  ///
  /// Throws an [StateError] if the P2P transport is not active or has not been initialized.
  Stream<P2pMessage> streamReceivedMessages() {
    if (_p2pTransport == null) {
      throw StateError(
          'Host: P2P transport is not active. Cannot stream data.');
    }
    return _p2pTransport!.receivedMessages;
  }

  /// Provides a stream that emits the updated list of connected [P2pClientInfo]s
  /// whenever a client connects or disconnects.
  ///
  /// Throws a [StateError] if the P2P transport is not active.
  Stream<List<P2pClientInfo>> streamClientList() {
    if (_p2pTransport == null) {
      throw StateError(
          'Host: P2P transport is not active. Cannot stream client list.');
    }
    return _p2pTransport!.clientListStream;
  }

  /// Broadcasts a [P2pMessage] to all connected clients.
  ///
  /// - [message]: The [P2pMessage] to send. The `senderId` should typically be set
  ///              to identify the host (e.g., 'server' or a host-specific ID).
  /// - [excludeClientId]: Optional ID of a client to exclude from the broadcast.
  ///
  /// Throws a [StateError] if the P2P transport is not active.
  Future<void> broadcast(P2pMessage message, {String? excludeClientId}) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      // Check if server is running
      throw StateError(
          'Host: P2P transport is not active. Cannot broadcast. Ensure createGroup() was called successfully.');
    }
    // Delegate broadcasting to the transport layer instance.
    await transport.broadcast(message, excludeClientId: excludeClientId);
  }

  /// Sends a [P2pMessage] to a specific client.
  ///
  /// - [clientId]: The ID of the target client (obtained from `streamClientList` or message `senderId`).
  /// - [message]: The [P2pMessage] to send. The `senderId` should typically be set
  ///              to identify the host (e.g., 'server' or a host-specific ID).
  ///
  /// Returns `true` if the client was found and message was sent, `false` otherwise.
  /// Throws a [StateError] if the P2P transport is not active.
  Future<bool> sendToClient(String clientId, P2pMessage message) async {
    final transport = _p2pTransport;
    if (transport == null || transport.portInUse == null) {
      // Check if server is running
      throw StateError(
          'Host: P2P transport is not active. Cannot send. Ensure createGroup() was called successfully.');
    }
    // Delegate sending to the transport layer instance.
    return await transport.sendToClient(clientId, message);
  }
}

/// The [FlutterP2pConnectionClient] class facilitates discovering and connecting
/// to a P2P host (Wi-Fi Direct group).
///
/// It allows initializing the client, scanning for hosts via BLE, connecting
/// to a discovered host (either via BLE data exchange or directly with credentials),
/// disconnecting, listening for connection state changes, and sending/receiving
/// data via the underlying [P2pTransportClient].
class FlutterP2pConnectionClient {
  // Internal state flag
  bool _isScanning = false;
  // Instance of the transport layer handler for the client.
  P2pTransportClient? _p2pTransport;
  // Store own client ID if needed, e.g., for sending messages
  String? _clientId; // Could be set based on device info or assigned by server

  /// Returns `true` if the client is currently scanning for BLE devices.
  bool get isScanning => _isScanning;

  /// Returns `true` if the client's P2P transport layer is connected to the host.
  bool get isConnected => _p2pTransport?.isConnected ?? false;

  /// Initializes the P2P connection client resources on the native platform.
  ///
  /// This method must be called before any other client operations.
  /// It prepares the underlying platform-specific components.
  Future<void> initialize({String? clientId}) async {
    _clientId = clientId ??
        "client_${DateTime.now().millisecondsSinceEpoch}"; // Example client ID
    await _p2pTransport?.dispose(); // Dispose previous transport if any
    _p2pTransport = null; // Ensure transport is reset on initialize
    await FlutterP2pConnectionPlatform.instance.initialize();
  }

  /// Disposes of the P2P connection client resources and cleans up connections.
  ///
  /// This method should be called when the client functionality is no longer needed
  /// to release system resources. It attempts to stop any active BLE scan,
  /// disconnect the transport layer, and disconnect from any active hotspot first.
  Future<void> dispose() async {
    // Ensure scanning is stopped before disposing.
    await stopScan().catchError((_) => null);
    // Ensure disconnection from hotspot (which also handles transport) before disposing.
    await disconnect().catchError((_) => null);
    // Dispose the transport explicitly if it wasn't handled by disconnect
    await _p2pTransport?.dispose().catchError((_) => null);
    _p2pTransport = null;
    await FlutterP2pConnectionPlatform.instance.dispose();
    debugPrint("FlutterP2pConnectionClient disposed.");
  }

  /// Starts scanning for nearby BLE devices advertising P2P host credentials.
  ///
  /// Listens to the BLE scan results stream and calls the [onData] callback
  /// whenever new devices are found. The scan automatically stops after the
  /// specified [timeout] duration (default 15 seconds).
  ///
  /// - [onData]: Callback function invoked with a list of [BleDiscoveredDevice] found
  ///             during the scan. Can be null if only interested in completion/error.
  /// - [onError]: Optional callback for handling errors during the scan stream.
  /// - [onDone]: Optional callback invoked when the scan stream is closed (e.g., timeout or manual stop).
  /// - [cancelOnError]: If `true`, the stream subscription cancels on the first error.
  /// - [timeout]: Duration after which the scan will automatically stop. Defaults to 15 seconds.
  ///
  /// Returns a [Future] completing with the [StreamSubscription] for the scan results.
  /// This subscription can be used to manually cancel the scan before the timeout.
  ///
  /// Throws an exception if starting the native BLE scan fails.
  Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(
    void Function(List<BleDiscoveredDevice>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_isScanning) {
      // Avoid starting multiple scans concurrently by stopping the previous one.
      await stopScan();
    }
    debugPrint("Client: Starting BLE scan...");

    StreamSubscription<List<BleDiscoveredDevice>>? streamSub;
    Timer? timer;

    // Define cleanup logic
    Future<void> cleanupScanResources() async {
      debugPrint("Client: Cleaning up scan resources...");
      timer?.cancel();
      // Check if subscription exists and hasn't been cancelled yet
      if (streamSub != null) {
        try {
          await streamSub?.cancel();
          debugPrint("Client: Scan stream subscription cancelled.");
        } catch (e) {
          debugPrint("Client: Error cancelling scan stream subscription: $e");
        }
        streamSub = null; // Ensure it's marked as cancelled
      }
      // Only stop native scan if we initiated it and it's still considered active.
      // Use a local flag to avoid race conditions with stopScan setting _isScanning
      bool wasScanning = _isScanning;
      if (wasScanning) {
        await stopScan().catchError(// stopScan sets _isScanning to false
            (e) =>
                debugPrint("Client: Error stopping scan during cleanup: $e"));
      }
      debugPrint("Client: Scan resource cleanup finished.");
    }

    // Set up the stream listener first.
    streamSub =
        FlutterP2pConnectionPlatform.instance.streamBleScanResult().listen(
      onData,
      onError: (error) {
        debugPrint("Client: BLE Scan stream error: $error");
        onError?.call(error);
        // Don't automatically cleanup here if cancelOnError is false
        if (cancelOnError ?? false) {
          cleanupScanResources();
        }
      },
      onDone: () {
        debugPrint("Client: BLE Scan stream done.");
        onDone?.call();
        cleanupScanResources(); // Cleanup when stream naturally closes
      },
      cancelOnError: cancelOnError,
    );

    // Schedule automatic stop after timeout.
    timer = Timer(timeout, cleanupScanResources); // Use the cleanup function

    // Start the native BLE scan.
    try {
      await FlutterP2pConnectionPlatform.instance.startBleScan();
      _isScanning = true;
      debugPrint("Client: Native BLE scan started.");
      return streamSub!; // Return the subscription
    } catch (e) {
      // If starting the scan fails, clean up everything immediately.
      debugPrint('Client: Failed to start BLE scan: $e');
      await cleanupScanResources();
      _isScanning = false; // Ensure state is reset
      rethrow; // Propagate the error
    }
  }

  /// Stops the ongoing BLE scan if one is active.
  Future<void> stopScan() async {
    if (_isScanning) {
      debugPrint("Client: Stopping BLE scan...");
      _isScanning = false; // Set state immediately to prevent race conditions
      await FlutterP2pConnectionPlatform.instance.stopBleScan().catchError((e) {
        debugPrint('Client: Error stopping BLE scan natively: $e');
        // State is already set to false
      });
      debugPrint("Client: BLE scan stopped.");
    }
  }

  /// Connects to a BLE device, retrieves hotspot credentials, and connects to the hotspot.
  ///
  /// 1. Connects to the specified BLE device.
  /// 2. Listens for SSID and PSK data sent over BLE characteristics.
  /// 3. Disconnects from the BLE device.
  /// 4. Calls [connectWithCredentials] with the retrieved credentials.
  ///
  /// This method assumes the target BLE device is a P2P host advertising its
  /// credentials according to a specific protocol (e.g., sending SSID then PSK
  /// as separate messages on a specific characteristic).
  ///
  /// - [device]: The [BleDiscoveredDevice] to connect to.
  /// - [timeout]: Duration to wait for credentials via BLE. Defaults to 20 seconds.
  ///
  /// Throws an [Exception] or [TimeoutException] if connecting to the BLE device fails,
  /// if credentials are not received within the timeout, or if connecting to the
  /// Wi-Fi hotspot subsequently fails.
  Future<void> connectWithDevice(
    BleDiscoveredDevice device, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    String deviceAddress = device.deviceAddress;
    debugPrint("Client: Connecting to found device $deviceAddress via BLE...");
    // Connect to the BLE device first.
    await FlutterP2pConnectionPlatform.instance.connectBleDevice(deviceAddress);
    debugPrint("Client: Connected to BLE device $deviceAddress.");

    String? ssid;
    String? psk;
    StreamSubscription<BleReceivedData>? bleDataSub;

    try {
      // Listen for data received from the BLE device (expecting SSID and PSK).
      final completer = Completer<void>();

      debugPrint("Client: Waiting for SSID and PSK via BLE...");
      bleDataSub =
          FlutterP2pConnectionPlatform.instance.streamBleReceivedData().listen(
        (evt) {
          // Basic protocol: expect SSID first, then PSK from the target device.
          if (evt.deviceAddress == deviceAddress) {
            String value = String.fromCharCodes(evt.data);
            if (ssid == null) {
              ssid = value;
              debugPrint("Client: Received SSID via BLE: $ssid");
              // Still waiting for PSK
            } else if (psk == null) {
              psk = value;
              debugPrint("Client: Received PSK via BLE"); // Don't log PSK
              // Got both, complete the future successfully
              if (!completer.isCompleted) {
                completer.complete();
              }
            }
          }
        },
        onError: (error) {
          debugPrint("Client: Error receiving BLE data: $error");
          if (!completer.isCompleted) {
            completer.completeError(
                Exception('Client: Error receiving BLE data: $error'));
          }
        },
        onDone: () {
          debugPrint("Client: BLE data stream ended prematurely.");
          if (!completer.isCompleted) {
            completer.completeError(Exception(
                'Client: BLE data stream ended before receiving both SSID and PSK.'));
          }
        },
      );

      // Wait for the completer to finish, with a timeout.
      await completer.future.timeout(timeout, onTimeout: () {
        throw TimeoutException(
            'Client: Timed out waiting for hotspot credentials via BLE after $timeout.');
      });

      // Cancel the subscription now that we have the data or timed out/errored.
      await bleDataSub.cancel();
      bleDataSub = null; // Ensure it's marked as cancelled

      // Validate received credentials.
      if (ssid == null || psk == null) {
        // This case should ideally be covered by the completer logic, but double-check.
        throw Exception(
            'Client: Failed to receive valid hotspot SSID and PSK via BLE (completer finished unexpectedly).');
      }

      // Credentials received, now connect to the Wi-Fi hotspot.
      debugPrint("Client: Attempting to connect to hotspot: $ssid");
      // Delegate to the specific hotspot connection method which handles transport init.
      await connectWithCredentials(ssid!, psk!); // Use non-null assertion
      debugPrint("Client: Successfully connected to hotspot: $ssid");
    } catch (e) {
      debugPrint("Client: Error during connectWithDevice: $e");
      rethrow; // Propagate the error
    } finally {
      // Always ensure the BLE data subscription is cancelled
      await bleDataSub?.cancel();
      // Always disconnect from the BLE device after attempting connection
      // or if an error occurred during credential exchange/hotspot connection.
      debugPrint("Client: Disconnecting from BLE device $deviceAddress...");
      await FlutterP2pConnectionPlatform.instance
          .disconnectBleDevice(deviceAddress)
          .catchError((e) {
        debugPrint(
            'Client: Error disconnecting from BLE device $deviceAddress: $e');
      });
      debugPrint("Client: Disconnected from BLE device $deviceAddress.");
    }
  }

  /// Connects directly to a Wi-Fi Direct hotspot and initializes the P2P transport client.
  ///
  /// 1. Initiates the native platform connection to the hotspot using SSID and PSK.
  /// 2. Waits for the [HotspotClientState] stream to confirm an active connection
  ///    with a valid gateway IP address.
  /// 3. Initializes and connects the [P2pTransportClient] to the host's gateway IP.
  ///
  /// - [ssid]: The Service Set Identifier (network name) of the hotspot.
  /// - [psk]: The Pre-Shared Key (password) for the hotspot.
  /// - [timeout]: Duration to wait for successful Wi-Fi connection state confirmation. Defaults to 60 seconds.
  ///
  /// Throws an [Exception] or [TimeoutException] if the connection confirmation
  /// (including obtaining the gateway IP) fails within the timeout period, or if
  /// the subsequent P2P transport connection fails.
  Future<void> connectWithCredentials(
    String ssid,
    String psk, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    debugPrint("Client: Connecting to hotspot '$ssid'...");
    // Stop any existing transport first
    await _p2pTransport?.disconnect().catchError((e) {
      debugPrint('Client: Error disconnecting previous P2P transport: $e');
    });
    await _p2pTransport?.dispose(); // Also dispose it fully
    _p2pTransport = null;

    // Initiate native connection
    await FlutterP2pConnectionPlatform.instance.connectToHotspot(ssid, psk);
    debugPrint("Client: Native connectToHotspot initiated for '$ssid'.");

    // Wait for the hotspot state update containing valid gateway IP address.
    HotspotClientState state;
    try {
      debugPrint(
          "Client: Waiting for active connection state with gateway IP...");
      state = await streamHotspotState()
          .firstWhere(
        (s) =>
            s.isActive && // Must be active
            s.hostSsid == ssid && // Must be the correct SSID
            s.hostGatewayIpAddress != null, // Gateway IP is essential
      )
          .timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
              'Client: Timed out after $timeout waiting for active connection state with gateway IP.');
        },
      );
      debugPrint("Client: Received active connection state: $state");
    } catch (e) {
      debugPrint("Client: Error waiting for connection state: $e");
      // Attempt cleanup if state acquisition failed
      await disconnect().catchError((_) => null);
      rethrow;
    }

    // Initialize and connect P2pTransportClient after successful Wi-Fi connection.
    _p2pTransport = P2pTransportClient(
      hostIp: state.hostGatewayIpAddress!, // IP is confirmed non-null here
      defaultPort: _defaultP2pTransportPort,
      username: await FlutterP2pConnectionPlatform.instance.getPlatformModel(),
    );
    try {
      await _p2pTransport!.connect();
    } catch (e) {
      debugPrint('Client: Failed to connect P2P Transport: $e');
      // Clean up Wi-Fi connection if transport fails to connect
      await disconnect().catchError((_) => null);
      await _p2pTransport?.dispose(); // Dispose transport
      _p2pTransport = null;
      throw Exception('Client: Failed to connect P2P Transport: $e');
    }
  }

  /// Disconnects from the currently connected Wi-Fi Direct hotspot and stops the transport layer.
  ///
  /// This disconnects and disposes the [P2pTransportClient] first, then triggers the native
  /// platform disconnection from the hotspot.
  Future<void> disconnect() async {
    debugPrint("Client: Disconnecting from hotspot...");
    // Disconnect and dispose the transport layer first if it exists.
    await _p2pTransport?.disconnect().catchError((e) {
      debugPrint('Client: Error disconnecting P2P transport: $e');
    });
    await _p2pTransport?.dispose().catchError((e) {
      debugPrint('Client: Error disposing P2P transport: $e');
    });
    _p2pTransport = null; // Clear the transport instance
    debugPrint("Client: P2P transport disconnected and disposed.");

    // Disconnect from the hotspot on the native side.
    await FlutterP2pConnectionPlatform.instance
        .disconnectFromHotspot()
        .catchError((e) {
      debugPrint('Client: Error disconnecting from hotspot natively: $e');
      // Consider if state needs update even on error
    });
    debugPrint("Client: Native hotspot disconnection initiated.");
  }

  /// Provides a stream of [HotspotClientState] updates from the platform.
  ///
  /// Listen to this stream to receive real-time information about the client's
  /// connection status to a hotspot, including whether it's connected, the
  /// host's SSID, and IP address details (gateway and client IP).
  ///
  /// Returns a [Stream] of [HotspotClientState].
  Stream<HotspotClientState> streamHotspotState() {
    return FlutterP2pConnectionPlatform.instance.streamHotspotClientState();
  }

  /// Provides a stream of messages received from the host via the P2P transport layer.
  ///
  /// This stream emits [P2pMessage] objects received from the connected host.
  ///
  /// Throws a [StateError] if the P2P transport is not active or has not been initialized.
  Stream<P2pMessage> streamReceivedMessages() {
    if (_p2pTransport == null) {
      throw StateError(
          'Client: P2P transport is not active. Cannot stream data.');
    }
    return _p2pTransport!.receivedMessages;
  }

  /// Provides a stream that emits the updated list of connected [P2pClientInfo]s
  /// whenever a client connects or disconnects.
  ///
  /// Throws a [StateError] if the P2P transport is not active.
  Stream<List<P2pClientInfo>> streamClientList() {
    if (_p2pTransport == null) {
      throw StateError(
          'Client: P2P transport is not active. Cannot stream client list.');
    }
    return _p2pTransport!.clientListStream;
  }

  /// Sends a message to the connected host via the P2P transport layer.
  ///
  /// - [type]: An application-defined string indicating the message type (e.g., 'chat', 'command').
  /// - [payload]: The data to send. Must be JSON-encodable.
  ///
  /// Automatically sets the `senderId` based on the client's ID.
  ///
  /// Returns `true` if the message was sent successfully, `false` otherwise (e.g., not connected).
  /// Throws a [StateError] if the P2P transport is not active or client ID is missing.
  Future<bool> send(P2pMessageType type, dynamic payload) async {
    final transport = _p2pTransport;
    final clientId = _clientId;
    if (transport == null || !transport.isConnected) {
      debugPrint('Client: P2P transport is not connected. Cannot send data.');
      throw StateError(
          'Client: P2P transport is not connected. Cannot send data.');
      // return false; // Return false instead of throwing for send failures due to state
    }
    if (clientId == null) {
      throw StateError('Client: Client ID is not set. Cannot send data.');
    }

    final message = P2pMessage(
      senderId: clientId,
      type: type,
      payload: payload,
    );

    // Delegate sending to the transport layer instance.
    return await transport.send(message);
  }
}

// ... (FlutterP2pConnection class and State/Data classes remain largely the same)
// Minor updates to state/data classes for consistency (hashCode, toString)

/// The main entry point for the Flutter P2P Connection plugin.
///
/// This class provides access to:
/// - Host functionality via the [host] property ([FlutterP2pConnectionHost]).
/// - Client functionality via the [client] property ([FlutterP2pConnectionClient]).
/// - Utility methods for checking and requesting permissions and enabling services
///   (Location, Wi-Fi, Bluetooth) required for P2P operations.
/// - Device information like the model.
class FlutterP2pConnection {
  /// Provides access to host-specific P2P operations.
  final FlutterP2pConnectionHost host = FlutterP2pConnectionHost();

  /// Provides access to client-specific P2P operations.
  final FlutterP2pConnectionClient client = FlutterP2pConnectionClient();

  /// Retrieves the model identifier of the current device.
  ///
  /// Useful for debugging or tailoring behavior based on the device.
  ///
  /// Returns a [Future] completing with the device model string.
  Future<String> getDeviceModel() =>
      FlutterP2pConnectionPlatform.instance.getPlatformModel();

  /// Checks if location services are currently enabled on the device.
  ///
  /// Location is often required for Wi-Fi and BLE scanning on Android.
  ///
  /// Returns a [Future] completing with `true` if location is enabled, `false` otherwise.
  Future<bool> checkLocationEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkLocationEnabled();

  /// Attempts to guide the user to system settings to enable location services.
  ///
  /// This typically opens the device's location settings screen.
  /// After the user potentially enables the service, it re-checks the status.
  ///
  /// Returns a [Future] completing with `true` if location is enabled after the
  /// attempt, `false` otherwise. Note that the user can choose not to enable it.
  Future<bool> enableLocationServices() async {
    await FlutterP2pConnectionPlatform.instance.enableLocationServices();
    // Re-check status after returning from settings.
    return await checkLocationEnabled();
  }

  /// Checks if Wi-Fi is currently enabled on the device.
  ///
  /// Wi-Fi is essential for Wi-Fi Direct P2P connections.
  ///
  /// Returns a [Future] completing with `true` if Wi-Fi is enabled, `false` otherwise.
  Future<bool> checkWifiEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkWifiEnabled();

  /// Attempts to guide the user to system settings to enable Wi-Fi.
  ///
  /// This typically opens the device's Wi-Fi settings screen.
  /// After the user potentially enables Wi-Fi, it re-checks the status.
  ///
  /// Returns a [Future] completing with `true` if Wi-Fi is enabled after the
  /// attempt, `false` otherwise.
  Future<bool> enableWifiServices() async {
    await FlutterP2pConnectionPlatform.instance.enableWifiServices();
    // Re-check status after returning from settings.
    return await checkWifiEnabled();
  }

  /// Checks if Bluetooth is currently enabled on the device.
  ///
  /// Bluetooth is required for BLE discovery (scanning and advertising).
  ///
  /// Returns a [Future] completing with `true` if Bluetooth is enabled, `false` otherwise.
  Future<bool> checkBluetoothEnabled() async =>
      await FlutterP2pConnectionPlatform.instance.checkBluetoothEnabled();

  /// Attempts to guide the user to system settings to enable Bluetooth.
  ///
  /// This typically opens the device's Bluetooth settings screen.
  /// After the user potentially enables Bluetooth, it re-checks the status.
  ///
  /// Returns a [Future] completing with `true` if Bluetooth is enabled after the
  /// attempt, `false` otherwise.
  Future<bool> enableBluetoothServices() async {
    await FlutterP2pConnectionPlatform.instance.enableBluetoothServices();
    // Re-check status after returning from settings.
    return await checkBluetoothEnabled();
  }

  /// Checks if all necessary Bluetooth permissions are granted.
  ///
  /// This includes permissions for connecting, scanning, and advertising,
  /// which vary depending on the Android version. Uses the `permission_handler` package.
  /// Also checks for Location permission which is often required for BLE scanning.
  ///
  /// Returns a [Future] completing with `true` if all required Bluetooth and
  /// associated Location permissions are granted, `false` otherwise.
  Future<bool> checkBluetoothPermissions() async {
    // Permissions required might vary slightly based on Android SDK level.
    // These cover common BLE operations. Android 12+ requires specific permissions.
    // Location is generally required for scanning before Android 12, and often
    // requested alongside BT permissions even on 12+ for reliability.
    final List<Permission> permissions = [
      Permission
          .locationWhenInUse, // Or Permission.location if background scan needed
      Permission.bluetoothScan, // Needed for discovering devices (Android 12+)
      Permission
          .bluetoothConnect, // Needed for connecting to devices (Android 12+)
      Permission.bluetoothAdvertise, // Needed for advertising (Android 12+)
    ];

    // On older Android versions, some permissions might not exist or be relevant.
    // permission_handler usually handles this gracefully (returns PermissionStatus.granted
    // or restricted/denied based on manifest and OS level).

    for (final perm in permissions) {
      final status = await perm.status;
      // Consider .isLimited as potentially sufficient for some use cases (e.g., location)
      if (!status.isGranted && !status.isLimited) {
        debugPrint("Permission missing: $perm status: $status");
        return false; // If any required permission is not granted, return false.
      }
    }

    // // Additionally check the basic Bluetooth permission for good measure,
    // // although the specific ones above are key on newer Android.
    // if (!(await Permission.bluetooth.status.isGranted)) {
    //   debugPrint(
    //       "Permission missing: ${Permission.bluetooth} status: ${await Permission.bluetooth.status}");
    //   return false;
    // }

    return true; // All checked permissions are granted.
  }

  /// Requests necessary Bluetooth and associated Location permissions from the user.
  ///
  /// Uses the `permission_handler` package to request permissions for scanning,
  /// connecting, advertising, and location (often needed for scanning).
  ///
  /// Returns a [Future] completing with `true` if all requested permissions
  /// are granted by the user (or were already granted), `false` otherwise.
  Future<bool> askBluetoothPermissions() async {
    // Request all potentially needed permissions at once.
    // The user will see separate dialogs if multiple are needed.
    await [
      Permission.locationWhenInUse, // Request location first or alongside BT
      Permission
          .bluetooth, // General Bluetooth permission (might be auto-granted if others are)
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    // After requesting, check if they were actually granted.
    return await checkBluetoothPermissions();
  }

  /// Checks if all necessary P2P (Wi-Fi Direct) permissions are granted.
  ///
  /// This typically includes permissions like `NEARBY_WIFI_DEVICES` (Android 13+),
  /// `ACCESS_FINE_LOCATION` (required for Wi-Fi scanning/discovery), and potentially
  /// `CHANGE_WIFI_STATE`. The exact check is handled by the platform implementation.
  ///
  /// Returns a [Future] completing with `true` if all required P2P permissions
  /// are granted, `false` otherwise.
  Future<bool> checkP2pPermissions() async =>
      await FlutterP2pConnectionPlatform.instance.checkP2pPermissions();

  /// Requests necessary P2P (Wi-Fi Direct) permissions from the user.
  ///
  /// This triggers the platform-specific permission request dialogs for permissions
  /// like `NEARBY_WIFI_DEVICES`, `ACCESS_FINE_LOCATION`, etc.
  ///
  /// Returns a [Future] completing with `true` if the permissions are granted
  /// after the request (or were already granted), `false` otherwise.
  Future<bool> askP2pPermissions() async {
    await FlutterP2pConnectionPlatform.instance.askP2pPermissions();
    // Re-check status after the request dialog.
    return await checkP2pPermissions();
  }

  /// Checks if the necessary storage permissions are granted for file transfer.
  ///
  /// **Note:** Storage permission requirements have changed significantly in recent
  /// Android versions (Scoped Storage from Android 10/11, stricter rules in 13+).
  /// Relying on `Permission.storage` is often insufficient or incorrect on modern Android.
  ///
  /// Consider using platform-specific file pickers (`file_picker` package) or
  /// MediaStore APIs instead of requesting broad storage permissions.
  /// This method provides a basic check for older compatibility but might need
  /// adjustment based on your specific file access needs and target Android SDK.
  ///
  /// Returns a [Future] completing with `true` if `Permission.storage` is granted,
  /// `false` otherwise. This might not reflect the actual ability to read/write
  /// all files on newer Android versions.
  Future<bool> checkStoragePermission() async {
    // On Android 13+, direct external storage access is highly restricted.
    // Checking Permission.storage might not be the right approach.
    // Consider checking specific media permissions (photos, videos, audio) if applicable.
    // Or using MANAGE_EXTERNAL_STORAGE (requires special Play Store approval).

    // Basic check for Permission.storage:
    if (await Permission.storage.isGranted) {
      return true;
    }

    // Example check for media permissions (Android 13+):
    // if (await Permission.photos.isGranted || await Permission.videos.isGranted || await Permission.audio.isGranted) {
    //   // If any media permission is granted, maybe that's sufficient? Depends on use case.
    //   return true;
    // }

    return false;
  }

  /// Requests storage permission(s) from the user, primarily for file transfer.
  ///
  /// Uses the `permission_handler` package. See notes in [checkStoragePermission]
  /// regarding changes in Android storage permissions and the recommended alternatives.
  ///
  /// This method requests the basic `Permission.storage`. Adapt as needed for
  /// Scoped Storage or specific media permissions.
  ///
  /// Returns a [Future] completing with `true` if `Permission.storage` is granted
  /// after the request, `false` otherwise.
  Future<bool> askStoragePermission() async {
    // Request basic storage permission.
    // On Android 11+, this might grant limited access or prompt for specific folder access.
    // On Android 13+, this might have little effect without MANAGE_EXTERNAL_STORAGE.
    final status = await Permission.storage.request();

    // Example for requesting media permissions on Android 13+:
    // Map<Permission, PermissionStatus> statuses = await [
    //   Permission.photos,
    //   Permission.videos,
    //   Permission.audio, // Request permissions relevant to your app
    // ].request();
    // return statuses.values.any((status) => status.isGranted); // Return true if any media permission granted

    return status.isGranted;
  }
}

/// Represents the state of the Wi-Fi Direct group (hotspot) created by the host.
///
/// Contains information about the hotspot's status and connection details.
@immutable
class HotspotHostState {
  /// `true` if the hotspot is currently active and ready for connections.
  final bool isActive;

  /// The Service Set Identifier (network name) of the hotspot. Null if inactive or not yet determined.
  final String? ssid;

  /// The Pre-Shared Key (password) of the hotspot. Null if inactive or not yet determined.
  final String? preSharedKey;

  /// The IP address of the host device within the created group. Null if inactive or not yet assigned.
  final String? hostIpAddress;

  /// A platform-specific code indicating the reason for failure, if [isActive] is `false`.
  /// Interpretation depends on the underlying native implementation (e.g., Android WifiP2pManager failure codes).
  final int? failureReason;

  /// Creates a representation of the host's hotspot state.
  const HotspotHostState({
    required this.isActive,
    this.ssid,
    this.preSharedKey,
    this.hostIpAddress,
    this.failureReason,
  });

  /// Creates a [HotspotHostState] instance from a map (typically from platform channel).
  factory HotspotHostState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotHostState(
      isActive: map['isActive'] as bool? ?? false, // Provide default
      ssid: map['ssid'] as String?,
      preSharedKey: map['preSharedKey'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
      failureReason: map['failureReason'] as int?,
    );
  }

  /// Converts the [HotspotHostState] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'ssid': ssid,
      'preSharedKey': preSharedKey,
      'hostIpAddress': hostIpAddress,
      'failureReason': failureReason,
    };
  }

  @override
  String toString() {
    return 'HotspotHostState(isActive: $isActive, ssid: $ssid, preSharedKey: ${preSharedKey != null ? "[set]" : "null"}, hostIpAddress: $hostIpAddress, failureReason: $failureReason)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is HotspotHostState &&
        other.isActive == isActive &&
        other.ssid == ssid &&
        other.preSharedKey == preSharedKey &&
        other.hostIpAddress == hostIpAddress &&
        other.failureReason == failureReason;
  }

  @override
  int get hashCode {
    return Object.hash(
      isActive,
      ssid,
      preSharedKey,
      hostIpAddress,
      failureReason,
    );
  }
}

/// Represents the state of the client's connection to a Wi-Fi Direct group (hotspot).
///
/// Contains information about the connection status and network details obtained from the host.
@immutable
class HotspotClientState {
  /// `true` if the client is currently connected to a hotspot.
  final bool isActive;

  /// The SSID (network name) of the hotspot the client is connected to. Null if inactive.
  final String? hostSsid;

  /// The IP address of the gateway (usually the host device) in the hotspot network. Null if inactive or not yet determined.
  final String? hostGatewayIpAddress;

  /// The IP address assigned to the client device within the hotspot network. Null if inactive or not yet assigned.
  /// Note: This field name might be slightly misleading based on common usage;
  /// it typically represents the *client's* own IP address within the P2P group.
  /// Verify with platform implementation if precise meaning is critical.
  final String?
      hostIpAddress; // Consider renaming to clientIpAddress if confirmed

  /// Creates a representation of the client's connection state.
  const HotspotClientState({
    required this.isActive,
    this.hostSsid,
    this.hostGatewayIpAddress,
    this.hostIpAddress, // Client's IP in the group
  });

  /// Creates a [HotspotClientState] instance from a map (typically from platform channel).
  factory HotspotClientState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotClientState(
      isActive: map['isActive'] as bool? ?? false, // Provide default
      hostSsid: map['hostSsid'] as String?,
      hostGatewayIpAddress: map['hostGatewayIpAddress'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?, // Client's IP
    );
  }

  /// Converts the [HotspotClientState] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'hostSsid': hostSsid,
      'hostGatewayIpAddress': hostGatewayIpAddress,
      'hostIpAddress': hostIpAddress,
    };
  }

  @override
  String toString() {
    // Use clientIpAddress in toString for clarity
    return 'HotspotClientState(isActive: $isActive, hostSsid: $hostSsid, hostGatewayIpAddress: $hostGatewayIpAddress, clientIpAddress: $hostIpAddress)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is HotspotClientState &&
        other.isActive == isActive &&
        other.hostSsid == hostSsid &&
        other.hostGatewayIpAddress == hostGatewayIpAddress &&
        other.hostIpAddress == hostIpAddress;
  }

  @override
  int get hashCode {
    return Object.hash(
      isActive,
      hostSsid,
      hostGatewayIpAddress,
      hostIpAddress,
    );
  }
}

/// Represents the connection state of a specific BLE device.
///
/// Used potentially by [FlutterP2pConnection.streamBleConnectionState] if exposed.
@immutable
class BleConnectionState {
  /// The MAC address of the BLE device.
  final String deviceAddress;

  /// The name of the BLE device (as advertised or retrieved). May be empty or default.
  final String deviceName;

  /// `true` if the client is currently connected to this BLE device.
  final bool isConnected;

  /// Creates a representation of a BLE device's connection state.
  const BleConnectionState({
    required this.deviceAddress,
    required this.deviceName,
    required this.isConnected,
  });

  /// Creates a [BleConnectionState] instance from a map (typically from platform channel).
  factory BleConnectionState.fromMap(Map<dynamic, dynamic> map) {
    return BleConnectionState(
      deviceAddress: map['deviceAddress'] as String? ??
          'Unknown Address', // Provide default
      deviceName:
          map['deviceName'] as String? ?? 'Unknown Name', // Provide default
      isConnected: map['isConnected'] as bool? ?? false, // Provide default
    );
  }

  /// Converts the [BleConnectionState] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'deviceName': deviceName,
      'isConnected': isConnected,
    };
  }

  @override
  String toString() {
    return 'BleConnectionState(deviceAddress: $deviceAddress, deviceName: $deviceName, isConnected: $isConnected)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BleConnectionState &&
        other.deviceAddress == deviceAddress &&
        other.deviceName == deviceName &&
        other.isConnected == isConnected;
  }

  @override
  int get hashCode {
    return Object.hash(deviceAddress, deviceName, isConnected);
  }
}

/// Represents a BLE device found during a scan.
///
/// Contains basic information about the discovered device.
@immutable
class BleDiscoveredDevice {
  /// The MAC address of the discovered BLE device.
  final String deviceAddress;

  /// The advertised name of the BLE device. May be empty or a default name like "Unknown Device".
  final String deviceName;

  /// The Received Signal Strength Indicator (RSSI) in dBm.
  /// Indicates the signal strength at the time of discovery (more negative means weaker signal).
  final int rssi;

  /// Creates a representation of a discovered BLE device.
  const BleDiscoveredDevice({
    required this.deviceAddress,
    required this.deviceName,
    required this.rssi,
  });

  /// Creates a [BleDiscoveredDevice] instance from a map (typically from platform channel).
  factory BleDiscoveredDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleDiscoveredDevice(
      deviceAddress: map['deviceAddress'] as String? ??
          'Unknown Address', // Provide default
      // Handle potential null or empty names from native side
      deviceName: (map['deviceName'] as String?)?.isNotEmpty ?? false
          ? map['deviceName'] as String
          : 'Unknown Device', // Provide default name
      rssi: map['rssi'] as int? ?? -100, // Provide default RSSI
    );
  }

  /// Converts the [BleDiscoveredDevice] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'deviceName': deviceName,
      'rssi': rssi,
    };
  }

  @override
  String toString() {
    return 'BleDiscoveredDevice(deviceAddress: $deviceAddress, deviceName: $deviceName, rssi: $rssi)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BleDiscoveredDevice &&
        other.deviceAddress == deviceAddress &&
        other.deviceName == deviceName &&
        other.rssi == rssi;
  }

  @override
  int get hashCode {
    return Object.hash(deviceAddress, deviceName, rssi);
  }
}

/// Represents data received from a connected BLE device via a characteristic.
///
/// Used internally during the [FlutterP2pConnectionClient.connectWithDevice] process.
@immutable
class BleReceivedData {
  /// The MAC address of the BLE device from which data was received.
  final String deviceAddress;

  /// The UUID of the GATT characteristic that sent the data (if available from platform).
  final String characteristicUuid;

  /// The raw byte data received from the characteristic.
  final Uint8List data;

  /// Creates a representation of received BLE data.
  const BleReceivedData({
    required this.deviceAddress,
    required this.characteristicUuid,
    required this.data,
  });

  /// Creates a [BleReceivedData] instance from a map (typically from platform channel).
  factory BleReceivedData.fromMap(Map<dynamic, dynamic> map) {
    return BleReceivedData(
      deviceAddress: map['deviceAddress'] as String? ??
          'Unknown Address', // Provide default
      characteristicUuid: map['characteristicUuid'] as String? ??
          'Unknown UUID', // Provide default
      // Ensure data is always a Uint8List, even if null/empty from platform
      data: map['data'] as Uint8List? ?? Uint8List(0),
    );
  }

  /// Converts the [BleReceivedData] instance to a map.
  Map<String, dynamic> toMap() {
    return {
      'deviceAddress': deviceAddress,
      'characteristicUuid': characteristicUuid,
      'data': data,
    };
  }

  @override
  String toString() {
    // Avoid printing large byte arrays directly to the console
    final dataSummary = data.length > 16
        ? '${data.sublist(0, 8)}... (${data.length} bytes)'
        : data.toString();
    return 'BleReceivedData(deviceAddress: $deviceAddress, characteristicUuid: $characteristicUuid, data: $dataSummary)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BleReceivedData &&
        other.deviceAddress == deviceAddress &&
        other.characteristicUuid == characteristicUuid &&
        listEquals(other.data, data); // Use listEquals for byte comparison
  }

  @override
  int get hashCode {
    // Combine hashes using Object.hash for better distribution
    return Object.hash(deviceAddress, characteristicUuid, Object.hashAll(data));
  }
}
