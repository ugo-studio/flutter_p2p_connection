package com.ugo.studio.plugins.flutter_p2p_connection

import android.os.Build

object Constants {
    const val TAG = "FlutterP2pConnection"
    const val METHOD_CHANNEL_NAME = "flutter_p2p_connection"
    const val CLIENT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_clientState"
    const val HOTSPOT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_hotspotState"
    const val LOCATION_PERMISSION_REQUEST_CODE = 2468
    // const val ENABLE_BLUETOOTH_REQUEST_CODE = 2469
    const val MIN_HOTSPOT_API_LEVEL = Build.VERSION_CODES.O
}