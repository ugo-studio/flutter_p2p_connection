package com.ugo.studio.plugins.flutter_p2p_connection

import android.os.Build
import java.util.UUID

object Constants {
    const val TAG = "FlutterP2pConnection"

    // Method Channel
    const val METHOD_CHANNEL_NAME = "flutter_p2p_connection"

    // Event Channels
    const val CLIENT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_clientState"
    const val HOTSPOT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_hotspotState"
    const val BLE_SCAN_RESULT_EVENT_CHANNEL_NAME = "flutter_p2p_connection_bleScanResult" 
    const val BLE_CONNECTION_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_bleConnectionState" 
    const val BLE_RECEIVED_DATA_EVENT_CHANNEL_NAME = "flutter_p2p_connection_bleReceivedData" 

    // Permission Request Codes 
    const val LOCATION_PERMISSION_REQUEST_CODE = 2468
    // const val ENABLE_BLUETOOTH_REQUEST_CODE = 2469 // Keep if used internally by ServiceManager

    // API Level Checks
    const val MIN_HOTSPOT_API_LEVEL = Build.VERSION_CODES.O

    // BLE Specific
    // Generate a unique UUID for your application's service
    val BLE_CREDENTIAL_SERVICE_UUID: UUID = UUID.fromString("0f0540bd-4a04-46d0-b90d-b0447453ec3a") 
    val BLE_SSID_CHARACTERISTIC_UUID: UUID = UUID.fromString("7a374008-fc31-4476-be4d-1b3347233f00") 
    val BLE_PSK_CHARACTERISTIC_UUID: UUID = UUID.fromString("81a5ec62-a8b1-48b0-b533-938636a57ba4") 

}