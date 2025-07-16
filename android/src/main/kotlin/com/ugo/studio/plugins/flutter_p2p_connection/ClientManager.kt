package com.ugo.studio.plugins.flutter_p2p_connection

import android.annotation.SuppressLint
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference

import com.ugo.studio.plugins.flutter_p2p_connection.Constants
import com.ugo.studio.plugins.flutter_p2p_connection.DataUtils
import com.ugo.studio.plugins.flutter_p2p_connection.PermissionsManager
import com.ugo.studio.plugins.flutter_p2p_connection.ServiceManager
import io.flutter.plugin.common.MethodChannel


class ClientManager(
    private val wifiManager: WifiManager,
    private val connectivityManager: ConnectivityManager,
    private val permissionsManager: PermissionsManager, // Inject PermissionsManager
    private val serviceManager: ServiceManager,       // Inject ServiceManager
    private val mainHandler: Handler
) {
    private val TAG = Constants.TAG

    private var clientStateEventSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val currentNetworkRef = AtomicReference<Network?>()
    private var api29ConnectedSsid: String? = null
    private var legacyConnectedSsid: String? = null
    private var legacyNetworkId: Int = -1

    fun initialize() {
        Log.d(TAG, "ClientManager initialized")
    }

    @SuppressLint("MissingPermission")
    fun connectToHotspot(result: MethodChannel.Result, ssid: String, psk: String) {
        // Permissions checked by main plugin before calling
        // Use injected serviceManager for checks
        if (!serviceManager.isWifiEnabled()) {
            result.error("WIFI_DISABLED", "Wi-Fi must be enabled to connect to a hotspot.", null)
            return
        }

        // Disconnect from any previous connection managed by this plugin first
        disconnectClientInternal()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectToHotspotApi29(result, ssid, psk)
        } else {
            connectToHotspotLegacy(result, ssid, psk)
        }
    }

    fun disconnectFromHotspot(result: MethodChannel.Result) {
        disconnectClientInternal()
        result.success(true)
    }

    fun disconnectClientInternal() {
        Log.d(TAG, "disconnectClientInternal called.")
        var previouslyConnectedSsid: String? = null
        var needsUpdate = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            previouslyConnectedSsid = api29ConnectedSsid // Capture before clearing
            try {
                if (networkCallback != null) {
                    Log.d(TAG, "Unregistering network callback (API 29+)")
                    connectivityManager.unregisterNetworkCallback(networkCallback!!)
                     if (currentNetworkRef.get() != null) {
                          try { connectivityManager.bindProcessToNetwork(null) }
                           catch (e: Exception) { Log.e(TAG, "Error unbinding process: ${e.message}")}
                     }
                }
            } catch (ex: Exception) {
                Log.e(TAG, "Error unregistering network callback: ${ex.message}", ex)
            } finally {
                // Ensure state is cleared regardless of exceptions
                if (networkCallback != null || currentNetworkRef.get() != null || api29ConnectedSsid != null) {
                    networkCallback = null
                    currentNetworkRef.set(null)
                    api29ConnectedSsid = null
                    needsUpdate = true // We cleared state, so an update is needed
                } else {
                    Log.d(TAG,"API 29+ disconnect: No active callback, network, or SSID state to clear.")
                }
             }
        } else {
            // Legacy disconnect
            previouslyConnectedSsid = legacyConnectedSsid // Capture before clearing
            try {
                if (legacyNetworkId != -1) {
                    Log.d(TAG, "Disabling and removing legacy network: $legacyConnectedSsid (NetID: $legacyNetworkId)")
                    wifiManager.disableNetwork(legacyNetworkId) // Disable first
                    // Be cautious removing networks you didn't definitively add or if others might use them
                    // wifiManager.removeNetwork(legacyNetworkId)
                    // wifiManager.saveConfiguration() // Persist removal
                    wifiManager.disconnect() // Explicitly disconnect if needed
                } else if (legacyConnectedSsid != null) {
                    // If connected but not via managed ID, just disconnect
                    Log.d(TAG,"Disconnecting from legacy network $legacyConnectedSsid (no managed NetID).")
                    wifiManager.disconnect()
                }
            } catch (ex: Exception) {
                Log.e(TAG, "Error in legacy disconnect steps: ${ex.message}", ex)
            } finally {
                // Ensure state is cleared
                if (legacyConnectedSsid != null) {
                    legacyNetworkId = -1
                    legacyConnectedSsid = null
                    needsUpdate = true // We cleared state, so an update is needed
                } else {
                    Log.d(TAG,"Legacy disconnect: No active SSID state to clear.")
                }
            }
        }
        // Send update only if state actually changed
        if (needsUpdate) {
            mainHandler.post {
                clientStateEventSink?.success(DataUtils.createClientStateMap(false, null, null, previouslyConnectedSsid))
            }
         }
    }


    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectToHotspotApi29(result: MethodChannel.Result, ssid: String, psk: String) {
        try {
            Log.d(TAG, "Building WifiNetworkSpecifier for SSID: $ssid (API 29+)")
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(psk)
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                // Don't strictly require INTERNET capability removed if the hotspot might provide it
                 .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()

            // Ensure previous callback is unregistered
            if (networkCallback != null) {
                try { connectivityManager.unregisterNetworkCallback(networkCallback!!) }
                catch (e: IllegalArgumentException) { Log.w(TAG, "NetworkCallback already unregistered?") }
                networkCallback = null // Explicitly nullify
                currentNetworkRef.set(null)
                api29ConnectedSsid = null
            }

            networkCallback = createApi29NetworkCallback(ssid) // Create new callback

            Log.d(TAG, "Requesting network connection to $ssid...")
            connectivityManager.requestNetwork(request, networkCallback!!)
            result.success(true)

         } catch (ex: Exception) {
            Log.e(TAG, "Error connecting with WifiNetworkSpecifier: ${ex.message}", ex)
            mainHandler.post { // Ensure thread safety for sink
                clientStateEventSink?.success(DataUtils.createClientStateMap(false, null, null, ssid)) // Report failure for the requested SSID
            }
            result.error("CONNECT_ERROR_API29", "Error connecting (API 29+): ${ex.message}", null)
            networkCallback = null
            currentNetworkRef.set(null)
            api29ConnectedSsid = null
         }
     }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun createApi29NetworkCallback(ssidForCallback: String): ConnectivityManager.NetworkCallback {
        return object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                super.onAvailable(network)
                // Prevent race condition if a disconnect happened quickly
                if (networkCallback != this) {
                     Log.w(TAG, "onAvailable: Network callback is stale, ignoring. Network: $network")
                     return
                }
                currentNetworkRef.set(network)
                api29ConnectedSsid = ssidForCallback // Store the connected SSID
                val success = connectivityManager.bindProcessToNetwork(network)
                Log.d(TAG, "Client connected to hotspot: $api29ConnectedSsid (Network: $network, Bound: $success)")

                mainHandler.post {
                    val connectionInfo = DataUtils.getClientConnectionInfo(connectivityManager, network)
                    val gatewayIp = connectionInfo?.get("gatewayIpAddress") as? String
                    // For client, the host IP is the gateway IP
                    clientStateEventSink?.success(DataUtils.createClientStateMap(true, gatewayIp, gatewayIp, api29ConnectedSsid))
                }
            }

            override fun onLost(network: Network) {
                super.onLost(network)
                 Log.d(TAG, "Client lost connection to hotspot: $api29ConnectedSsid (Network: $network)")
                // Check if the lost network is the one we were tracking *and* the callback is current
                 if (network == currentNetworkRef.get() && networkCallback == this) {
                    connectivityManager.bindProcessToNetwork(null)
                    currentNetworkRef.set(null)
                    val lostSsid = api29ConnectedSsid
                    api29ConnectedSsid = null
                    // Don't nullify networkCallback here, let disconnectClientInternal handle it
                    mainHandler.post {
                        clientStateEventSink?.success(DataUtils.createClientStateMap(false, null, null, lostSsid))
                    }
                } else {
                     Log.w(TAG, "onLost: Ignoring stale or irrelevant network loss. Current ref: ${currentNetworkRef.get()}, Lost: $network")
                 }
            }

             override fun onUnavailable() {
                super.onUnavailable()
                // Check if the callback instance is still the active one
                if (networkCallback != this) {
                     Log.w(TAG, "onUnavailable: Network callback is stale, ignoring.")
                     return
                }
                Log.w(TAG, "Client connection unavailable for hotspot: $api29ConnectedSsid")
                currentNetworkRef.set(null) // Ensure network ref is cleared
                val unavailableSsid = api29ConnectedSsid
                api29ConnectedSsid = null
                // Don't nullify networkCallback here, let disconnectClientInternal handle it
                mainHandler.post {
                    clientStateEventSink?.success(DataUtils.createClientStateMap(false, null, null, unavailableSsid))
                 }
             }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
               super.onLinkPropertiesChanged(network, linkProperties)
                // Check if the callback instance is still the active one and network matches
                if (networkCallback == this && network == currentNetworkRef.get() && api29ConnectedSsid != null) {
                    Log.d(TAG, "Link properties changed for $api29ConnectedSsid: $linkProperties")
                    mainHandler.post {
                        val gatewayIp = DataUtils.getGatewayIpFromLinkProperties(linkProperties)
                        // For client, the host IP is the gateway IP
                        clientStateEventSink?.success(DataUtils.createClientStateMap(true, gatewayIp, gatewayIp, api29ConnectedSsid))
                    }
                }
            }
        }
    }


    @SuppressLint("MissingPermission", "Deprecated")
    private fun connectToHotspotLegacy(result: MethodChannel.Result, ssid: String, psk: String) {
        try {
            Log.d(TAG, "Building legacy WifiConfiguration for SSID: $ssid (API < 29)")

            // Check if already connected to this SSID (maybe manually) - safer check
             val currentWifiInfo = wifiManager.connectionInfo
             val currentSsid = currentWifiInfo?.ssid?.removePrefix("\"")?.removeSuffix("\"")
             if (currentWifiInfo != null && currentSsid == ssid && currentWifiInfo.networkId != -1) {
                  // Check supplicant state for better accuracy
                  val supplicantState = currentWifiInfo.supplicantState
                  if (supplicantState == android.net.wifi.SupplicantState.COMPLETED) {
                    Log.d(TAG,"Already connected to $ssid (Legacy check). Assuming connected.")
                    legacyConnectedSsid = ssid
                    legacyNetworkId = currentWifiInfo.networkId
                    mainHandler.post { // Ensure thread safety for sink
                        val gatewayIp = DataUtils.getLegacyGatewayIpAddress(wifiManager)
                        // For client, the host IP is the gateway IP
                        clientStateEventSink?.success(DataUtils.createClientStateMap(true, gatewayIp, gatewayIp, ssid))
                    }
                    result.success(true)
                    return
                  } else {
                    Log.d(TAG, "Found network $ssid but state is $supplicantState. Will proceed with connection attempt.")
                    // May need to remove old config if stuck - be careful with this
                    // wifiManager.removeNetwork(currentWifiInfo.networkId)
                    // wifiManager.saveConfiguration()
                  }
             }


            val config = WifiConfiguration().apply {
                SSID = "\"$ssid\""
                preSharedKey = "\"$psk\""
                status = WifiConfiguration.Status.ENABLED
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                priority = 40 // Higher priority for this network
            }

            legacyNetworkId = wifiManager.addNetwork(config)
            if (legacyNetworkId == -1) {
                // Maybe the config already exists? Try finding it.
                val existingConfigs = wifiManager.configuredNetworks
                val existingConfig = existingConfigs?.firstOrNull { it.SSID == "\"$ssid\"" }
                if (existingConfig != null) {
                    Log.w(TAG, "Network config for $ssid already existed. Using NetID: ${existingConfig.networkId}")
                    legacyNetworkId = existingConfig.networkId
                } else {
                    Log.e(TAG, "Failed to add network configuration for $ssid")
                    result.error("NETWORK_ADD_FAILED", "Failed to add network configuration (Legacy)", null)
                    return
                }
            } else {
                 // Save config only if we successfully added it
                 wifiManager.saveConfiguration()
            }

            Log.d(TAG, "Using network config for $ssid, NetID: $legacyNetworkId. Enabling...")

            wifiManager.disconnect() // Disconnect from current network

            val enabled = wifiManager.enableNetwork(legacyNetworkId, true) // true = attempt to connect
            if (!enabled) {
                Log.e(TAG, "Failed to enable network $ssid (NetID: $legacyNetworkId)")
                 // Don't remove pre-existing networks, maybe remove if we added it and failed?
                // if (wifiManager.configuredNetworks?.any{ it.networkId == legacyNetworkId} == true){
                //     Log.w(TAG, "Enable failed, but network config still exists. Will not remove.")
                // } else {
                //     wifiManager.removeNetwork(legacyNetworkId)
                //     wifiManager.saveConfiguration()
                // }
                legacyNetworkId = -1
                result.error("NETWORK_ENABLE_FAILED", "Failed to enable network $ssid (Legacy)", null)
                return
             }

            // Reconnect might not be necessary if enableNetwork's second param is true, but can help sometimes
             val reconnected = wifiManager.reconnect()
             if (!reconnected) {
                Log.w(TAG, "Reconnect command failed for $ssid, but connection might still establish.")
             } else {
                Log.d(TAG, "Reconnect command sent for $ssid.")
             }

            legacyConnectedSsid = ssid
            // Use a delayed check to see if connection succeeded
            mainHandler.postDelayed({
                verifyLegacyConnection(ssid)
            }, 5000) // Increased delay slightly more

            result.success(true) // Report success for initiating the connection attempt

        } catch (ex: Exception) {
            Log.e(TAG, "Error in legacy connection: ${ex.message}", ex)
            mainHandler.post { // Ensure thread safety for sink
                clientStateEventSink?.success(DataUtils.createClientStateMap(false, null, null, ssid))
            }
            // Clean up state if error occurred during connection attempt
            if (legacyNetworkId != -1) {
                // Maybe disable but avoid removing if unsure
                 wifiManager.disableNetwork(legacyNetworkId)
                // wifiManager.removeNetwork(legacyNetworkId)
                // wifiManager.saveConfiguration()
            }
            legacyNetworkId = -1
            legacyConnectedSsid = null
            result.error("LEGACY_CONNECT_ERROR", "Error connecting in legacy mode: ${ex.message}", null)
        }
    }

    @SuppressLint("MissingPermission", "Deprecated")
    private fun verifyLegacyConnection(expectedSsid: String) {
        // Check if we are still supposed to be connected to this SSID
        if (legacyConnectedSsid != expectedSsid) {
            Log.d(TAG, "verifyLegacyConnection: No longer expecting connection to $expectedSsid (current expected: $legacyConnectedSsid). Skipping check.")
            return
        }

        val gatewayIp = DataUtils.getLegacyGatewayIpAddress(wifiManager)
        // For client, the host IP is the gateway IP
        val hostIp = gatewayIp
        // Verify connection state again using connectionInfo before sending event
        val verifyInfo = wifiManager.connectionInfo
        val verifySsid = verifyInfo?.ssid?.removePrefix("\"")?.removeSuffix("\"")
        val verifyState = verifyInfo?.supplicantState

         if (verifySsid == expectedSsid && verifyState == android.net.wifi.SupplicantState.COMPLETED) {
            Log.d(TAG, "Confirmed legacy connection established to $expectedSsid. Gateway: $gatewayIp")
            // Send success state if not already sent or if state changed (e.g., IP obtained)
            clientStateEventSink?.success(DataUtils.createClientStateMap(true, gatewayIp, hostIp, expectedSsid))
         } else {
            Log.w(TAG,"Legacy connection to $expectedSsid not confirmed after delay. Current SSID: $verifySsid, State: $verifyState")
            // Send disconnect state if confirmation fails
            clientStateEventSink?.success(DataUtils.createClientStateMap(false, null, null, expectedSsid))
            // Update internal state as disconnected
            legacyConnectedSsid = null
            legacyNetworkId = -1
         }
    }

    fun dispose() {
        Log.d(TAG, "Disposing ClientManager...")
        disconnectClientInternal() // Ensure cleanup
        clientStateEventSink?.endOfStream()
        clientStateEventSink = null
        Log.d(TAG, "ClientManager disposed.")
    }


    // --- EventChannel Stream Handler (Client State Handler) ---
    val clientStateStreamHandler = object : EventChannel.StreamHandler {
        @SuppressLint("MissingPermission", "Deprecated") // For legacy wifiManager calls
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            Log.d(TAG, "ClientState StreamHandler: onListen")
            clientStateEventSink = events

            // Send initial state based on current tracked status
            val initialState: Map<String, Any?>

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val currentNetwork = currentNetworkRef.get()
                if (currentNetwork != null && api29ConnectedSsid != null) {
                    val connInfo = DataUtils.getClientConnectionInfo(connectivityManager, currentNetwork)
                    val gatewayIp = connInfo?.get("gatewayIpAddress") as? String
                    // For client, the host IP is the gateway IP
                    initialState = DataUtils.createClientStateMap(true, gatewayIp, gatewayIp, api29ConnectedSsid)
                } else {
                    initialState = DataUtils.createClientStateMap(false, null, null, null)
                }
            } else {
                // Check legacy state carefully
                if (legacyConnectedSsid != null) {
                    // Verify with current connection info if possible
                    val verifyInfo = wifiManager.connectionInfo // Requires ACCESS_FINE_LOCATION potentially
                    val verifySsid = verifyInfo?.ssid?.removePrefix("\"")?.removeSuffix("\"")
                    val verifyState = verifyInfo?.supplicantState
                    if(legacyConnectedSsid == verifySsid && verifyState == android.net.wifi.SupplicantState.COMPLETED) {
                        val gatewayIp = DataUtils.getLegacyGatewayIpAddress(wifiManager)
                        // For client, the host IP is the gateway IP
                        initialState = DataUtils.createClientStateMap(true, gatewayIp, gatewayIp, legacyConnectedSsid)
                    } else {
                        // State mismatch, report disconnected
                        Log.w(TAG, "onListen: Legacy state mismatch. Expected $legacyConnectedSsid, got $verifySsid ($verifyState). Reporting disconnected.")
                        initialState = DataUtils.createClientStateMap(false, null, null, legacyConnectedSsid) // Keep last known SSID?
                        // Clean up potentially stale state if mismatch detected on listen
                        // legacyConnectedSsid = null
                        // legacyNetworkId = -1
                    }
                } else {
                    initialState = DataUtils.createClientStateMap(false, null, null, null)
                }
            }
            Log.d(TAG, "ClientState StreamHandler: Sending initial state: $initialState")
            clientStateEventSink?.success(initialState)
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "ClientState StreamHandler: onCancel")
            clientStateEventSink = null
        }
    }
}