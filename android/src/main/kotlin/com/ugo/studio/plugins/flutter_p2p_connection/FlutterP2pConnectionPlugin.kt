package com.ugo.studio.plugins.flutter_p2p_connection

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
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
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.Collections
import java.util.concurrent.atomic.AtomicReference // Added for thread-safe network reference

/** FlutterP2pConnectionPlugin using LocalOnlyHotspot and client connection logic */
class FlutterP2pConnectionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, DefaultLifecycleObserver {

    companion object {
        private const val TAG = "FlutterP2pConnection"
        private const val METHOD_CHANNEL_NAME = "flutter_p2p_connection"
        private const val CLIENT_STATE_EVENT_CHANNEL_NAME = "flutter_p2p_connection_clientState"
        private const val LOCATION_PERMISSION_REQUEST_CODE = 2468
        private const val MIN_HOTSPOT_API_LEVEL = Build.VERSION_CODES.O // API 26 for LocalOnlyHotspot
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var clientStateEventChannel: EventChannel

    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var activityLifecycle: Lifecycle? = null

    private lateinit var wifiManager: WifiManager
    private lateinit var connectivityManager: ConnectivityManager
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var hotspotCallback: WifiManager.LocalOnlyHotspotCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Holds *host's* hotspot info (cached)
    private var hotspotInfoData: Map<String, Any?>? = null

    // Event Sink for the new client connection state channel
    private var clientStateEventSink: EventChannel.EventSink? = null

    // For API 29+ ephemeral client connection via WifiNetworkSpecifier
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    // Keep track of the current network for info fetching (thread-safe)
    private val currentNetworkRef = AtomicReference<Network?>()
    private var api29ConnectedSsid: String? = null // Store SSID for API 29+ connections

    // For legacy client connection state tracking
    private var legacyConnectedSsid: String? = null
    private var legacyNetworkId: Int = -1

    private var isInitialized = false

    // --- FlutterPlugin Implementation ---

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        clientStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, CLIENT_STATE_EVENT_CHANNEL_NAME)
        clientStateEventChannel.setStreamHandler(clientStateStreamHandler)

        Log.d(TAG, "Plugin attached to engine.")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        clientStateEventChannel.setStreamHandler(null)
        activityLifecycle?.removeObserver(this)
        stopHotspotInternal()
        disconnectClientInternal()
        Log.d(TAG, "Plugin detached from engine.")
    }

    // --- ActivityAware Implementation ---
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityLifecycle = binding.lifecycle as Lifecycle
        activityLifecycle?.addObserver(this)
        Log.d(TAG, "Plugin attached to activity.")
    }
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        Log.d(TAG, "Plugin detached from activity for config changes.")
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        Log.d(TAG, "Plugin reattached to activity for config changes.")
    }
    override fun onDetachedFromActivity() {
        Log.d(TAG, "Plugin detached from activity.")
        activityLifecycle?.removeObserver(this)
        activity = null
        activityLifecycle = null
    }
    // --- DefaultLifecycleObserver Implementation ---
    override fun onResume(owner: LifecycleOwner) { Log.d(TAG, "Activity Resumed (Lifecycle)") }
    override fun onPause(owner: LifecycleOwner) { Log.d(TAG, "Activity Paused (Lifecycle)") }

    // --- MethodCallHandler Implementation ---
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        // Handle methods that don't require initialization first
        when (call.method) {
            "getPlatformVersion" -> { result.success("${Build.VERSION.RELEASE}"); return }
            "getPlatformModel" -> { result.success("${Build.MODEL}"); return }
            "initialize" -> { initializeHotspotComponents(result); return }
        }
        // All other methods require plugin initialization
        if (!isInitialized && call.method !in listOf("checkP2pPermissions", "askP2pPermissions", "connectToHotspot", "disconnectFromHotspot", "checkLocationEnabled", "enableLocationServices", "checkWifiEnabled", "enableWifiServices")) {
            result.error("NOT_INITIALIZED", "Plugin not initialized. Call initialize() first.", null)
            return
        }

        try {
            when (call.method) {
                "dispose" -> disposeHotspotComponents(result)
                // --- Host Methods ---
                "createHotspot" -> createHotspot(result)
                "removeHotspot" -> removeHotspot(result)
                "requestHotspotInfo" -> requestHotspotInfo(result)
                // --- Client Connection Methods ---
                "connectToHotspot" -> {
                    val ssid: String? = call.argument("ssid")
                    val password: String? = call.argument("password")
                    if (ssid.isNullOrEmpty() || password == null) {
                        result.error("INVALID_ARGS", "Missing or invalid 'ssid' or 'password' arguments for connectToHotspot", null)
                    } else {
                        connectToHotspot(result, ssid, password)
                    }
                }
                "disconnectFromHotspot" -> disconnectFromHotspot(result)
                // --- Permission ---
                "checkP2pPermissions" -> checkHotspotPermissions(result)
                "askP2pPermissions" -> askHotspotPermissions(result)
                "checkLocationEnabled" -> checkLocationEnabled(result)
                "enableLocationServices" -> enableLocationServices(result)
                "checkWifiEnabled" -> checkWifiEnabled(result)
                "enableWifiServices" -> enableWifiServices(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling method ${call.method}: ${e.message}", e)
            result.error("PLUGIN_ERROR", "Exception in method ${call.method}: ${e.message}", e.stackTraceToString())
        }
    }

    // --- Core Hotspot Logic (Host-Side) ---
    private fun initializeHotspotComponents(result: Result) {
        if (isInitialized) {
            Log.d(TAG, "Already initialized.")
            result.success(true)
            return
        }
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (wm == null || cm == null) {
            Log.e(TAG, "Failed to get WifiManager or ConnectivityManager.")
            result.error("SERVICE_UNAVAILABLE", "Required WiFi or Connectivity service not available.", null)
            return
        }
        wifiManager = wm
        connectivityManager = cm
        isInitialized = true
        Log.d(TAG, "Hotspot components initialized successfully.")
        result.success(true)
    }

    private fun disposeHotspotComponents(result: Result) {
        if (!isInitialized) {
            Log.d(TAG, "Dispose called but plugin was not initialized.")
            result.success(true)
            return
        }
        Log.d(TAG, "Disposing Hotspot Components...")
        stopHotspotInternal()
        disconnectClientInternal()
        hotspotCallback = null
        isInitialized = false
        hotspotInfoData = null
        clientStateEventSink?.success(createClientStateMap(false, null, null, null)) // Notify client disconnect
        clientStateEventSink?.endOfStream() // Close the client stream properly
        clientStateEventSink = null
        Log.d(TAG, "Hotspot components disposed.")
        result.success(true)
    }

    @RequiresApi(MIN_HOTSPOT_API_LEVEL)
    private fun createHotspot(result: Result) {
        // ... (Checks remain the same) ...
        if (Build.VERSION.SDK_INT < MIN_HOTSPOT_API_LEVEL) {
            result.error("UNSUPPORTED_OS_VERSION", "LocalOnlyHotspot requires Android 8.0 (API 26) or higher.", null)
            return
        }
        if (hotspotReservation != null) {
            Log.w(TAG, "Hotspot already active.")
            result.success(true)
            return
        }
        if (!isLocationEnabledInternal()) {
            result.error("LOCATION_DISABLED", "Location services must be enabled to start a hotspot.", null)
            return
        }
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Missing required permission (ACCESS_FINE_LOCATION) to start hotspot.", null)
            return
        }

        if (hotspotCallback == null) {
            hotspotCallback = object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                    super.onStarted(reservation)
                    if (reservation == null) {
                        Log.e(TAG, "Hotspot started callback received null reservation.")
                        hotspotInfoData = createHotspotInfoMap(false, null, null)
                        return
                    }
                    Log.d(TAG, "LocalOnlyHotspot Started.")
                    hotspotReservation = reservation
                    val config = reservation.wifiConfiguration
                    val hotspotIp = getHotspotIpAddress()
                    hotspotInfoData = createHotspotInfoMap(true, config, hotspotIp)
                }
                override fun onStopped() {
                    super.onStopped()
                    Log.d(TAG, "LocalOnlyHotspot Stopped.")
                    hotspotReservation = null
                    hotspotInfoData = createHotspotInfoMap(false, null, null)
                }
                override fun onFailed(reason: Int) {
                    super.onFailed(reason)
                    Log.e(TAG, "LocalOnlyHotspot Failed. Reason: $reason")
                    hotspotReservation = null
                    hotspotInfoData = createHotspotInfoMap(false, null, null, reason)
                }
            }
        }
        try {
            if (!isLocationEnabledInternal()) { // Double check location just before starting
                result.error("LOCATION_DISABLED", "Location services must be enabled to start a hotspot.", null)
                return
            }
            wifiManager.startLocalOnlyHotspot(hotspotCallback!!, mainHandler)
            Log.d(TAG, "Hotspot creation initiated.")
            result.success(true)
        } catch (sec: SecurityException) {
            Log.e(TAG, "SecurityException starting hotspot: ${sec.message}", sec)
            result.error("PERMISSION_DENIED", "SecurityException: ${sec.message}", null)
        } catch (e: Exception) {
            Log.e(TAG, "Exception starting hotspot: ${e.message}", e)
            result.error("HOTSPOT_START_FAILED", "Failed to initiate hotspot: ${e.message}", null)
        }
    }

    private fun removeHotspot(result: Result) {
        stopHotspotInternal()
        result.success(true)
    }

    private fun stopHotspotInternal() {
        if (hotspotReservation != null) {
            Log.d(TAG, "Stopping LocalOnlyHotspot...")
            try {
                hotspotReservation?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Exception closing hotspot reservation: ${e.message}", e)
                 if (hotspotReservation != null) {
                     hotspotReservation = null
                     hotspotInfoData = createHotspotInfoMap(false, null, null)
                }
            }
             hotspotReservation = null
        } else {
            Log.d(TAG, "Stop Hotspot called but no active reservation found.")
            if (hotspotInfoData?.get("isActive") == true) {
                 hotspotInfoData = createHotspotInfoMap(false, null, null)
            }
        }
    }

    private fun requestHotspotInfo(result: Result) {
        Log.d(TAG, "Requesting host's hotspot info (cached).")
        result.success(hotspotInfoData ?: createHotspotInfoMap(false, null, null))
    }


    // --- Client-Side Connection Methods ---

    @SuppressLint("MissingPermission")
    private fun connectToHotspot(result: Result, ssid: String, password: String) {
        if (!isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized.", null)
            return
        }
        if (!hasHotspotPermissionsInternal()) {
             result.error("PERMISSION_DENIED", "Missing required permissions (ACCESS_FINE_LOCATION and/or CHANGE_WIFI_STATE).", null)
             return
         }
         if (!isWifiEnabledInternal()) {
              result.error("WIFI_DISABLED", "Wi-Fi must be enabled to connect to a hotspot.", null)
              return
          }

        // Disconnect from any previous connection managed by this plugin first
        disconnectClientInternal()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectToHotspotApi29(result, ssid, password)
        } else {
            connectToHotspotLegacy(result, ssid, password)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectToHotspotApi29(result: Result, ssid: String, password: String) {
         try {
             Log.d(TAG, "Building WifiNetworkSpecifier for SSID: $ssid (API 29+)")
             val specifier = WifiNetworkSpecifier.Builder()
                 .setSsid(ssid)
                 .setWpa2Passphrase(password)
                 .build()
             val request = NetworkRequest.Builder()
                 .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                 .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                 .setNetworkSpecifier(specifier)
                 .build()

             // Ensure previous callback is unregistered (redundant with disconnectClientInternal, but safe)
             if (networkCallback != null) {
                 try { connectivityManager.unregisterNetworkCallback(networkCallback!!) }
                 catch (e: IllegalArgumentException) { Log.w(TAG, "NetworkCallback already unregistered?") }
             }

             networkCallback = object : ConnectivityManager.NetworkCallback() {
                 override fun onAvailable(network: Network) {
                     super.onAvailable(network)
                     currentNetworkRef.set(network)
                     api29ConnectedSsid = ssid // Store the connected SSID
                     val success = connectivityManager.bindProcessToNetwork(network)
                     Log.d(TAG, "Client connected to hotspot: $api29ConnectedSsid (Network: $network, Bound: $success)")
                     val connectionInfo = getClientConnectionInfo(network) // No need to pass SSID here
                     val hotspotIp = getHotspotIpAddress() // Host's Ip Address
                     clientStateEventSink?.success(createClientStateMap(true, connectionInfo?.get("gatewayIpAddress") as? String, hotspotIp, api29ConnectedSsid))
                 }

                 override fun onLost(network: Network) {
                     super.onLost(network)
                     Log.d(TAG, "Client lost connection to hotspot: $api29ConnectedSsid (Network: $network)")
                     if (network == currentNetworkRef.get()) {
                         connectivityManager.bindProcessToNetwork(null)
                         currentNetworkRef.set(null)
                         val lostSsid = api29ConnectedSsid // Capture SSID before clearing
                         api29ConnectedSsid = null
                         clientStateEventSink?.success(createClientStateMap(false, null, null, lostSsid))
                         networkCallback = null
                     }
                 }

                 override fun onUnavailable() {
                     super.onUnavailable()
                     Log.w(TAG, "Client connection unavailable for hotspot: $api29ConnectedSsid")
                     currentNetworkRef.set(null)
                     val unavailableSsid = api29ConnectedSsid
                     api29ConnectedSsid = null
                     clientStateEventSink?.success(createClientStateMap(false, null, null, unavailableSsid))
                 }

                 override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                    super.onLinkPropertiesChanged(network, linkProperties)
                    if (network == currentNetworkRef.get() && api29ConnectedSsid != null) {
                         Log.d(TAG, "Link properties changed for $api29ConnectedSsid: $linkProperties")
                         val gatewayIp = getGatewayIpFromLinkProperties(linkProperties)
                         val hotspotIp = getHotspotIpAddress()
                         // Resend state with potentially updated gateway IP
                         clientStateEventSink?.success(createClientStateMap(true, gatewayIp, hotspotIp, api29ConnectedSsid))
                     }
                 }
             }

             Log.d(TAG, "Requesting network connection to $ssid...")
             connectivityManager.requestNetwork(request, networkCallback!!)
             result.success(true)

         } catch (ex: Exception) {
             Log.e(TAG, "Error connecting with WifiNetworkSpecifier: ${ex.message}", ex)
             clientStateEventSink?.success(createClientStateMap(false, null, null, ssid)) // Report failure for the requested SSID
             result.error("CONNECT_ERROR_API29", "Error connecting (API 29+): ${ex.message}", null)
             networkCallback = null
             currentNetworkRef.set(null)
             api29ConnectedSsid = null
         }
     }


    @SuppressLint("MissingPermission", "Deprecated")
    private fun connectToHotspotLegacy(result: Result, ssid: String, password: String) {
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
                      val gatewayIp = getLegacyGatewayIpAddress()
                      val hotspotIp = getHotspotIpAddress()
                      clientStateEventSink?.success(createClientStateMap(true, gatewayIp, hotspotIp, ssid))
                      result.success(true)
                      return
                  } else {
                       Log.d(TAG, "Found network $ssid but state is $supplicantState. Will proceed with connection attempt.")
                       // May need to remove old config if stuck
                       wifiManager.removeNetwork(currentWifiInfo.networkId)
                       wifiManager.saveConfiguration()
                  }
             }


            val config = WifiConfiguration().apply {
                SSID = "\"$ssid\""
                preSharedKey = "\"$password\""
                status = WifiConfiguration.Status.ENABLED
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                priority = 40 // Example priority
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
            }

            Log.d(TAG, "Using network config for $ssid, NetID: $legacyNetworkId. Enabling...")

            wifiManager.disconnect()

            val enabled = wifiManager.enableNetwork(legacyNetworkId, true) // true = attempt to connect
            if (!enabled) {
                 Log.e(TAG, "Failed to enable network $ssid (NetID: $legacyNetworkId)")
                 // Don't remove if it was pre-existing and we just failed to enable
                 if (wifiManager.configuredNetworks?.any{ it.networkId == legacyNetworkId} == true){
                     Log.w(TAG, "Enable failed, but network config still exists. Will not remove.")
                 } else {
                     wifiManager.removeNetwork(legacyNetworkId)
                     wifiManager.saveConfiguration()
                 }
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
            mainHandler.postDelayed({
                 val gatewayIp = getLegacyGatewayIpAddress()
                 val hotspotIp = getHotspotIpAddress()
                  // Verify connection state again using connectionInfo before sending event
                  val verifyInfo = wifiManager.connectionInfo
                  val verifySsid = verifyInfo?.ssid?.removePrefix("\"")?.removeSuffix("\"")
                  val verifyState = verifyInfo?.supplicantState

                 if (legacyConnectedSsid == ssid && verifySsid == ssid && verifyState == android.net.wifi.SupplicantState.COMPLETED) {
                    Log.d(TAG, "Confirmed legacy connection established to $ssid. Gateway: $gatewayIp")
                    clientStateEventSink?.success(createClientStateMap(true, gatewayIp, hotspotIp, ssid))
                 } else {
                     Log.w(TAG,"Legacy connection to $ssid not confirmed after delay. Current SSID: $verifySsid, State: $verifyState")
                     // Optional: Send disconnect state if confirmation fails
                     // if (legacyConnectedSsid == ssid) { // Only if we were still expecting this connection
                     //    clientStateEventSink?.success(createClientStateMap(false, null, null, ssid))
                     //    legacyConnectedSsid = null // Update state
                     //    legacyNetworkId = -1
                     // }
                 }
            }, 4000) // Increased delay slightly

            result.success(true)

        } catch (ex: Exception) {
            Log.e(TAG, "Error in legacy connection: ${ex.message}", ex)
            clientStateEventSink?.success(createClientStateMap(false, null, null, ssid))
            if (legacyNetworkId != -1) {
                // Avoid removing network if it might be used by others, only if we added it and failed.
                // This logic is tricky. For simplicity, maybe just disable it.
                // wifiManager.removeNetwork(legacyNetworkId)
                // wifiManager.saveConfiguration()
            }
            legacyNetworkId = -1
            legacyConnectedSsid = null
            result.error("LEGACY_CONNECT_ERROR", "Error connecting in legacy mode: ${ex.message}", null)
        }
    }

    private fun disconnectFromHotspot(result: Result) {
        disconnectClientInternal()
        result.success(true)
    }

    /** Internal disconnect function */
    private fun disconnectClientInternal() {
        Log.d(TAG, "disconnectClientInternal called.")
        var previouslyConnectedSsid: String? = null

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
                     clientStateEventSink?.success(createClientStateMap(false, null, null, previouslyConnectedSsid))
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
                     wifiManager.removeNetwork(legacyNetworkId)
                     wifiManager.saveConfiguration() // Persist removal
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
                      clientStateEventSink?.success(createClientStateMap(false, null, null, previouslyConnectedSsid))
                 } else {
                      Log.d(TAG,"Legacy disconnect: No active SSID state to clear.")
                 }
            }
        }
    }


    // --- Permission and Service Checks ---
    // ... (checkHotspotPermissions, askHotspotPermissions, Location checks remain the same) ...
     private fun hasHotspotPermissionsInternal(): Boolean {
         val fineLocationGranted = ContextCompat.checkSelfPermission(
             applicationContext, Manifest.permission.ACCESS_FINE_LOCATION
         ) == PackageManager.PERMISSION_GRANTED
         val changeWifiStateGranted = ContextCompat.checkSelfPermission(
             applicationContext, Manifest.permission.CHANGE_WIFI_STATE
         ) == PackageManager.PERMISSION_GRANTED

         var nearbyWifiGranted = true // Assume true for older APIs
         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
              // Check if the app targets API 31+
              val targetsApi31OrHigher = applicationContext.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.S
              if (targetsApi31OrHigher) {
                   nearbyWifiGranted = ContextCompat.checkSelfPermission(
                       applicationContext, Manifest.permission.NEARBY_WIFI_DEVICES
                   ) == PackageManager.PERMISSION_GRANTED
              }
          }

         return fineLocationGranted && changeWifiStateGranted && nearbyWifiGranted
     }
     private fun checkHotspotPermissions(result: Result) {
         Log.d(TAG, "Checking Permissions (FINE_LOCATION, CHANGE_WIFI_STATE, NEARBY_WIFI_DEVICES if needed).")
         result.success(hasHotspotPermissionsInternal())
     }
     private fun askHotspotPermissions(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to request permissions", null)
            return
        }
        val permissionsToRequest = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.CHANGE_WIFI_STATE) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(Manifest.permission.CHANGE_WIFI_STATE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val targetsApi31OrHigher = applicationContext.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.S
            if (targetsApi31OrHigher && ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                 permissionsToRequest.add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }

        if (permissionsToRequest.isEmpty()) {
            Log.d(TAG, "Permissions already granted.")
            result.success(true)
            return
        }
        Log.d(TAG, "Requesting permissions: ${permissionsToRequest.joinToString()}")
        ActivityCompat.requestPermissions(
            currentActivity,
            permissionsToRequest.toTypedArray(),
            LOCATION_PERMISSION_REQUEST_CODE
        )
        result.success(true) // Indicate request was made
     }

    private fun isLocationEnabledInternal(): Boolean {
        val locationManager = applicationContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        return if (locationManager == null) {
            Log.w(TAG, "Location manager service not available for check.")
            false
        } else {
            try {
                locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            } catch (e: Exception) {
                Log.e(TAG, "Error checking location provider status", e)
                false
            }
        }
    }
    private fun checkLocationEnabled(result: Result) { result.success(isLocationEnabledInternal()) }
    private fun enableLocationServices(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to open settings", null)
            return
        }
        try {
            currentActivity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error opening location settings: ${e.message}", e)
            result.error("SETTINGS_ERROR", "Could not open location settings.", e.message)
        }
    }
    private fun isWifiEnabledInternal(): Boolean {
         // Try-catch block for added safety, especially during initialization phases
         try {
             if (!this::wifiManager.isInitialized) {
                 val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                 return wm?.isWifiEnabled ?: false
             }
             return wifiManager.isWifiEnabled
         } catch (e: Exception) {
             Log.e(TAG, "Error checking Wi-Fi enabled state: ${e.message}", e)
             return false // Assume false if error occurs
         }
     }

    private fun checkWifiEnabled(result: Result) {
         result.success(isWifiEnabledInternal())
     }

    @SuppressLint("NewApi")
    private fun enableWifiServices(result: Result) {
         val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to open settings/panel", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
                 panelIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) // Add this flag if calling from non-Activity context potentially
                currentActivity.startActivity(panelIntent)
            } else {
                @Suppress("DEPRECATION")
                currentActivity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error opening Wi-Fi settings/panel: ${e.message}", e)
            result.error("SETTINGS_ERROR", "Could not open Wi-Fi settings/panel.", e.message)
        }
    }


    // --- Data Serialization and Helpers ---

    // Host's Hotspot Info Map
    private fun createHotspotInfoMap(isActive: Boolean, config: WifiConfiguration?, ipAddress: String?, failureReason: Int? = null): Map<String, Any?> {
        return mapOf(
            "isActive" to isActive,
            "ssid" to config?.SSID?.removePrefix("\"")?.removeSuffix("\""),
            "preSharedKey" to config?.preSharedKey?.removePrefix("\"")?.removeSuffix("\""),
            "hostIpAddress" to ipAddress,
            "failureReason" to failureReason
        )
    }

    // Client's Connection State Map
    private fun createClientStateMap(isActive: Boolean, gatewayIpAddress: String?, ipAddress: String?, connectedSsid: String?): Map<String, Any?> {
        return mapOf(
            "isActive" to isActive,
            "gatewayIpAddress" to gatewayIpAddress,
            "hostIpAddress" to ipAddress, // Include host IP here too
            "ssid" to connectedSsid?.removePrefix("\"")?.removeSuffix("\"") // Ensure SSID is cleaned
        )
    }

    // Helper to get client connection details (like gateway IP) using Network object
    private fun getClientConnectionInfo(network: Network?): Map<String, Any?>? {
         if (network == null) return null
         try {
             val linkProperties = connectivityManager.getLinkProperties(network) ?: return null
             val gatewayIp = getGatewayIpFromLinkProperties(linkProperties)
             // val clientIp = getClientIpFromLinkProperties(linkProperties) // Can add if needed
             return mapOf(
                 "gatewayIpAddress" to gatewayIp
                 // "clientIpAddress" to clientIp
             )
         } catch (e: Exception) {
             Log.e(TAG, "Error getting client connection info: ${e.message}", e)
             return null
         }
     }
     // Helper to extract Gateway IP from LinkProperties
     private fun getGatewayIpFromLinkProperties(linkProperties: LinkProperties?): String? {
          if (linkProperties == null) return null
          // Prioritize default route
         linkProperties.routes?.forEach { routeInfo ->
             if (routeInfo.isDefaultRoute && routeInfo.gateway != null) {
                 val gwAddress = routeInfo.gateway?.hostAddress
                 Log.d(TAG,"Found gateway IP (default route): $gwAddress")
                 return gwAddress
             }
         }
          // Fallback: Look for the first IPv4 address on the interface that isn't the client's own IP
          // and assume the .1 address in that subnet is the gateway (common but not guaranteed)
          var clientIp: InetAddress? = null
          linkProperties.linkAddresses.forEach { linkAddress ->
              if (linkAddress.address is Inet4Address && !linkAddress.address.isLoopbackAddress) {
                  clientIp = linkAddress.address // Find the client's likely IP first
                  return@forEach // Found one, stop iterating link addresses for client IP
              }
          }

          if (clientIp != null) {
              val clientIpString = clientIp?.hostAddress
              Log.d(TAG, "Client's likely IP: $clientIpString")
              val parts = clientIpString?.split(".")
              if (parts?.size == 4) {
                  val potentialGateway = "${parts[0]}.${parts[1]}.${parts[2]}.1"
                  Log.w(TAG, "Could not find default route gateway. Guessing gateway: $potentialGateway")
                  return potentialGateway // Fallback guess
              }
          }

         Log.w(TAG, "Could not determine gateway IP from LinkProperties.")
         return null
     }

    // Helper to get Gateway IP in Legacy mode
    @SuppressLint("Deprecated")
    private fun getLegacyGatewayIpAddress(): String? {
        try {
            val dhcpInfo = wifiManager.dhcpInfo ?: return null
            val gatewayInt = dhcpInfo.gateway
            if (gatewayInt == 0) return null
            val ipBytes = byteArrayOf(
                (gatewayInt and 0xff).toByte(),
                (gatewayInt shr 8 and 0xff).toByte(),
                (gatewayInt shr 16 and 0xff).toByte(),
                (gatewayInt shr 24 and 0xff).toByte()
            )
             val gatewayAddress = InetAddress.getByAddress(ipBytes).hostAddress
             Log.d(TAG, "Legacy gateway IP: $gatewayAddress")
            return gatewayAddress
        } catch (e: Exception) {
            Log.e(TAG, "Error getting legacy gateway IP: ${e.message}", e)
            return null
        }
    }


    // Helper to find the Host's IP address when acting as hotspot
    private fun getHotspotIpAddress(): String? {
        var potentialIp : String? = null
        try {
            val interfaces: List<NetworkInterface> = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                if (!intf.isUp || intf.isLoopback || intf.isVirtual) continue // Skip down, loopback, virtual

                // Prioritize interfaces named 'ap' or 'wlan' containing typical hotspot IPs
                val isPotentialHotspotIntf = intf.name.contains("ap", ignoreCase = true) || intf.name.contains("wlan", ignoreCase = true)

                val addresses: List<InetAddress> = Collections.list(intf.inetAddresses)
                for (addr in addresses) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        val ip = addr.hostAddress ?: continue

                        // Common hotspot IPs (192.168.43.1 for tethering, 192.168.49.1 for LOHS)
                        if (ip == "192.168.43.1" || ip == "192.168.49.1") {
                             Log.d(TAG, "Found common hotspot IP: $ip on interface ${intf.name}")
                            return ip // Return immediately if common IP found
                        }

                        // Store the first 192.168.* IP found on a potential hotspot interface as a fallback
                        if (isPotentialHotspotIntf && ip.startsWith("192.168.") && potentialIp == null) {
                             Log.d(TAG, "Found potential hotspot range IP: $ip on interface ${intf.name}")
                             potentialIp = ip
                         }
                    }
                }
            }
        } catch (ex: Exception) {
            Log.e(TAG, "Exception while getting Hotspot IP address: $ex")
        }

         if(potentialIp != null) {
             Log.d(TAG, "Using fallback potential hotspot IP: $potentialIp")
             return potentialIp
         }

        Log.w(TAG, "Could not determine hotspot IP address.")
        return null
    }


    // --- EventChannel Stream Handler (Client State Handler) ---
    private val clientStateStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            Log.d(TAG, "ClientState StreamHandler: onListen")
            clientStateEventSink = events

            // Send initial state based on current tracked status
            val initialState: Map<String, Any?>
            val hotspotIp = getHotspotIpAddress() // Get current host IP when listener attaches

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                 val currentNetwork = currentNetworkRef.get()
                 if (currentNetwork != null && api29ConnectedSsid != null) {
                      val connInfo = getClientConnectionInfo(currentNetwork)
                      initialState = createClientStateMap(true, connInfo?.get("gatewayIpAddress") as? String, hotspotIp, api29ConnectedSsid)
                  } else {
                      initialState = createClientStateMap(false, null, hotspotIp, null) // Report host IP even if disconnected
                  }
            } else {
                 // Check legacy state
                 if (legacyConnectedSsid != null) {
                     // Verify with current connection info if possible
                     val verifyInfo = wifiManager.connectionInfo
                     val verifySsid = verifyInfo?.ssid?.removePrefix("\"")?.removeSuffix("\"")
                     val verifyState = verifyInfo?.supplicantState
                     if(legacyConnectedSsid == verifySsid && verifyState == android.net.wifi.SupplicantState.COMPLETED) {
                         val gatewayIp = getLegacyGatewayIpAddress()
                         initialState = createClientStateMap(true, gatewayIp, hotspotIp, legacyConnectedSsid)
                     } else {
                          // State mismatch, report disconnected
                           Log.w(TAG, "onListen: Legacy state mismatch. Expected $legacyConnectedSsid, got $verifySsid ($verifyState). Reporting disconnected.")
                           initialState = createClientStateMap(false, null, hotspotIp, legacyConnectedSsid) // Keep last known SSID? Or null?
                           // Clear potentially stale state
                           // legacyConnectedSsid = null
                           // legacyNetworkId = -1
                     }
                 } else {
                      initialState = createClientStateMap(false, null, hotspotIp, null)
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