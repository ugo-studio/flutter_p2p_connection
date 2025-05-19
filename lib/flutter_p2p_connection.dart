/// A Flutter plugin for establishing peer-to-peer connections
/// using Wi-Fi Direct (Group Owner/Hotspot) and BLE for discovery and credential exchange.
///
/// This library provides classes to act as a P2P host (`FlutterP2pHost`)
/// or a P2P client (`FlutterP2pClient`), along with necessary data models
/// for managing connection states, discovered devices, and data transfer.
library flutter_p2p_connection;

// Export common P2P functionalities (Host and Client)
export 'src/host/p2p_host.dart' show FlutterP2pHost;
export 'src/client/p2p_client.dart' show FlutterP2pClient;

// Export data models related to P2P connection states and BLE
export 'src/models/p2p_connection_models.dart'
    show
        HotspotHostState,
        HotspotClientState,
        BleConnectionState,
        BleDiscoveredDevice,
        BleReceivedData;

// Export data models and enums related to the P2P transport layer
export 'src/transport/common/transport_enums.dart'
    show P2pMessageType, ReceivableFileState;
export 'src/transport/common/transport_data_models.dart'
    show
        P2pClientInfo,
        P2pFileInfo,
        P2pMessagePayload,
        P2pFileProgressUpdate,
        P2pMessage;
export 'src/transport/common/transport_file_models.dart'
    show HostedFileInfo, ReceivableFileInfo, FileDownloadProgressUpdate;
