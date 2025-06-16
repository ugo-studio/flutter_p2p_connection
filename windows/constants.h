#pragma once
#include <string>

namespace Constants {
    const std::string TAG = "FlutterP2pConnection";

    // Method Channel
    const std::string METHOD_CHANNEL_NAME = "flutter_p2p_connection";

    // Event Channels
    const std::string CLIENT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_clientState";
    const std::string HOTSPOT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_hotspotState";
    const std::string BLE_SCAN_RESULT_EVENT_CHANNEL_NAME = "flutter_p2p_connection_bleScanResult";
    const std::string BLE_CONNECTION_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_bleConnectionState";
    const std::string BLE_RECEIVED_DATA_EVENT_CHANNEL_NAME = "flutter_p2p_connection_bleReceivedData";

    // BLE UUIDs
    const std::string BLE_CREDENTIAL_SERVICE_UUID = "0f0540bd-4a04-46d0-b90d-b0447453ec3a";
    const std::string BLE_SSID_CHARACTERISTIC_UUID = "7a374008-fc31-4476-be4d-1b3347233f00";
    const std::string BLE_PSK_CHARACTERISTIC_UUID = "81a5ec62-a8b1-48b0-b533-938636a57ba4";
}