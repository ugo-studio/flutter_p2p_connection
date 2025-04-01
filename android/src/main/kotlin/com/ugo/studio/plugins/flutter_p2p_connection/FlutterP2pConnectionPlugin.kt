package com.ugo.studio.plugins.flutter_p2p_connection

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.NetworkInfo
import android.net.wifi.WifiManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.*
import android.os.Build
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


import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/** FlutterP2pConnectionPlugin */
class FlutterP2pConnectionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, DefaultLifecycleObserver {

    companion object {
        private const val TAG = "FlutterP2pConnection"
        private const val METHOD_CHANNEL_NAME = "flutter_p2p_connection"
        private const val FOUND_PEERS_EVENT_CHANNEL_NAME = "flutter_p2p_connection_foundPeers"
        private const val CONNECTION_INFO_EVENT_CHANNEL_NAME = "flutter_p2p_connection_connectionInfo"
        private const val LOCATION_PERMISSION_REQUEST_CODE = 2468
        private const val DATA_REFRESH_INTERVAL_MS = 600L
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var foundPeersEventChannel: EventChannel
    private lateinit var connectionInfoEventChannel: EventChannel

    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var activityLifecycle: Lifecycle? = null // Store lifecycle reference

    private lateinit var wifiP2pManager: WifiP2pManager
    private lateinit var wifiP2pChannel: WifiP2pManager.Channel
    private var broadcastReceiver: BroadcastReceiver? = null
    private var intentFilter = IntentFilter()

    // Data holders for event channels
    private var foundPeersData: List<Map<String, Any?>> = emptyList()
    private var connectionInfoData: Map<String, Any?>? = null

    // Event sinks
    private var foundPeersEventSink: EventChannel.EventSink? = null
    private var connectionInfoEventSink: EventChannel.EventSink? = null 

    // Coroutine scopes for managing repeating tasks for each stream
    private var foundPeersScope: CoroutineScope? = null
    private var connectionInfoScope: CoroutineScope? = null

    private var isReceiverRegistered = false
    private var isInitialized = false

    // --- FlutterPlugin Implementation ---

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        foundPeersEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, FOUND_PEERS_EVENT_CHANNEL_NAME)
        foundPeersEventChannel.setStreamHandler(foundPeersStreamHandler)

        connectionInfoEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, CONNECTION_INFO_EVENT_CHANNEL_NAME) // Use renamed constant
        connectionInfoEventChannel.setStreamHandler(connectionInfoStreamHandler) // Use renamed handler

        Log.d(TAG, "Plugin attached to engine.")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        foundPeersEventChannel.setStreamHandler(null)
        connectionInfoEventChannel.setStreamHandler(null)
        // Ensure lifecycle observer is removed if somehow still attached
        activityLifecycle?.removeObserver(this)
        unregisterReceiver() // Final chance to unregister
        Log.d(TAG, "Plugin detached from engine.")
    }

    // --- ActivityAware Implementation ---

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityLifecycle = binding.lifecycle as Lifecycle // Get the lifecycle
        activityLifecycle?.addObserver(this)   // Add plugin as an observer
        Log.d(TAG, "Plugin attached to activity, lifecycle observer added.")
        // Registration will now be handled by onResume
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Activity is being destroyed/recreated due to config changes.
        // Don't unregister receiver or remove observer. Lifecycle handles this.
        activity = null
        // activityLifecycle reference might become stale, but the observer is tied to the lifecycle object itself.
        Log.d(TAG, "Plugin detached from activity for config changes.")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        // Lifecycle observer should still be attached. If lifecycle object changed,
        // the previous one would have triggered DESTROYED state anyway.
        // Re-getting lifecycle and re-adding observer might be needed in complex scenarios,
        // but often unnecessary. Keep it simple first.
        // activityLifecycle = binding.lifecycle
        // activityLifecycle?.addObserver(this) // Potentially re-add if needed
        Log.d(TAG, "Plugin reattached to activity for config changes.")
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "Plugin detached from activity.")
        activityLifecycle?.removeObserver(this) // Remove observer
        unregisterReceiver() // Ensure receiver is unregistered when activity is permanently gone
        activity = null
        activityLifecycle = null
    }

    // --- DefaultLifecycleObserver Implementation ---

    override fun onResume(owner: LifecycleOwner) {
        Log.d(TAG, "Activity Resumed (Lifecycle)")
        // Register the receiver only when the plugin is initialized and activity is resumed
        if (isInitialized) {
            registerReceiver()
        } else {
             Log.w(TAG,"Activity resumed but plugin not initialized yet. Receiver not registered.")
        }
    }

    override fun onPause(owner: LifecycleOwner) {
        Log.d(TAG, "Activity Paused (Lifecycle)")
        // Unregister the receiver when the activity is paused
        if (isInitialized) {
           unregisterReceiver()
        }
    }

    // Optional: Implement other lifecycle methods like onDestroy if needed for extra cleanup.
    override fun onDestroy(owner: LifecycleOwner) {
       Log.d(TAG, "Activity Destroyed (Lifecycle)")
       // Cleanup usually handled by onDetachedFromActivity observer removal, but can add here too
       unregisterReceiver()
    }


    // --- MethodCallHandler Implementation ---

    @RequiresApi(Build.VERSION_CODES.M) // Base requirement for runtime permissions
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "getPlatformVersion" -> result.success("${Build.VERSION.RELEASE}")
                "getPlatformModel" -> result.success("${Build.MODEL}")
                "initialize" -> initializeWifiP2PConnections(result)
                "dispose" -> disposeWifiP2PConnections(result)
                "createGroup" -> createGroup(result)
                "removeGroup" -> removeGroup(result)
                "requestGroupInfo" -> requestGroupInfo(result)
                "startPeerDiscovery" -> startPeerDiscovery(result) // Renamed from discover for clarity
                "stopPeerDiscovery" -> stopPeerDiscovery(result)
                "connect" -> {
                    val address: String? = call.argument("address")
                    if (address.isNullOrEmpty()) {
                        result.error("INVALID_ARGS", "Missing or empty 'address' argument for connect", null)
                    } else {
                        connect(result, address)
                    }
                }
                "disconnect" -> disconnect(result)
                "checkP2pPermissions" -> checkP2pPermissions(result)
                "askP2pPermissions" -> askP2pPermissions(result)
                "checkLocationEnabled" -> checkLocationEnabled(result)
                "enableLocationServices" -> enableLocationServices(result)
                "checkWifiEnabled" -> checkWifiEnabled(result)
                "enableWifiServices" -> enableWifiServices(result)
                "fetchPeers" -> fetchPeers(result)
                "fetchConnectionInfo" -> fetchConnectionInfo(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling method ${call.method}: ${e.message}", e)
            result.error("PLUGIN_ERROR", "Exception in method ${call.method}: ${e.message}", e.stackTraceToString())
        }
    }

    // --- Core P2P Logic ---

    /**
     * Initializes WifiP2pManager, Channel, and sets up the BroadcastReceiver.
     */
    private fun initializeWifiP2PConnections(result: Result) {
        if (isInitialized) {
            Log.d(TAG, "Already initialized.")
            result.success(true) // Idempotent
            return
        }

        // --- Intent Filter Setup ---
        // Ensure filter is clean before adding actions (in case dispose wasn't called properly)
        intentFilter = IntentFilter()
        intentFilter.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        intentFilter.addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
        intentFilter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        intentFilter.addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)

        // --- Get P2P Manager ---
        val manager = applicationContext.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        if (manager == null) {
            Log.e(TAG, "Device does not support Wi-Fi Direct")
            result.error("UNSUPPORTED", "Device does not support Wi-Fi Direct", null)
            return
        }
        wifiP2pManager = manager

        // --- Initialize Channel ---
        val channel = wifiP2pManager.initialize(applicationContext, Looper.getMainLooper(), null)
        if (channel == null) {
            Log.e(TAG, "Failed to initialize WifiP2pManager channel.")
            // Clean up manager reference if channel initialization fails? Maybe not necessary.
            result.error("INITIALIZATION_ERROR", "Failed to initialize WifiP2pManager channel.", null)
            return
        }
        wifiP2pChannel = channel

        // --- Create BroadcastReceiver ---
        // Ensure no old receiver instance lingers
        broadcastReceiver = null // Clear first
        broadcastReceiver = WiFiDirectBroadcastReceiver(
            wifiP2pManager,
            wifiP2pChannel
        )

        // --- Set State and Register ---
        isInitialized = true
        // Registration will happen automatically when activity resumes via onResume
        Log.d(TAG, "Wi-Fi P2P initialized successfully.")
        result.success(true)
    }

    /**
     * Cleans up Wi-Fi P2P resources: stops discovery, disconnects, unregisters receiver, cancels timers.
     */
    private fun disposeWifiP2PConnections(result: Result) {
        if (!isInitialized) {
            Log.d(TAG, "Dispose called but plugin was not initialized.")
            result.success(true) // Nothing to dispose, report success
            return
        }

        Log.d(TAG, "Disposing Wi-Fi P2P Connections...")

        // Use a simple ActionListener for cleanup tasks where we don't need detailed results
        val cleanupActionListener = object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                // Log success, but don't call the main result here yet
                Log.v(TAG, "Async cleanup action succeeded.")
            }
            override fun onFailure(reason: Int) {
                // Log failure, but don't call the main result here yet
                Log.w(TAG, "Async cleanup action failed: ${reasonCodeToString(reason)}")
            }
        }

        // 1. Stop Peer Discovery (fire and forget style for cleanup)
        // Check if manager is initialized before using it (belt and braces)
        if (::wifiP2pManager.isInitialized) {
             Log.d(TAG, "Dispose: Stopping peer discovery...")
             wifiP2pManager.stopPeerDiscovery(wifiP2pChannel, cleanupActionListener)
        }


        // 2. Disconnect / Remove Group (fire and forget style for cleanup)
        if (::wifiP2pManager.isInitialized) {
             Log.d(TAG, "Dispose: Requesting disconnect/group removal...")
             wifiP2pManager.requestGroupInfo(wifiP2pChannel) { group ->
                if (group != null) {
                    // If in a group, remove it
                    wifiP2pManager.removeGroup(wifiP2pChannel, cleanupActionListener)
                } else {
                    // If not in a group, try cancelling any potential connection attempts
                    wifiP2pManager.cancelConnect(wifiP2pChannel, cleanupActionListener)
                }
             }
        }

        // 3. Cancel Timer Coroutines
        Log.d(TAG, "Dispose: Cancelling timer scopes...")
        foundPeersScope?.cancel()
        connectionInfoScope?.cancel()
        foundPeersScope = null
        connectionInfoScope = null

        // 4. Unregister Broadcast Receiver (Synchronous)
        Log.d(TAG, "Dispose: Unregistering receiver...")
        unregisterReceiver() // This already handles checks

        // 5. Clear Cached Data
        Log.d(TAG, "Dispose: Clearing cached data...")
        foundPeersData = emptyList()
        connectionInfoData = null
        // Optionally notify sinks that data is cleared (although they might be null now)
        // foundPeersEventSink?.success(foundPeersData)
        // connectionInfoEventSink?.success(connectionInfoData)

        // 6. Clear BroadcastReceiver reference
        broadcastReceiver = null

        // 7. Reset Initialization Flag (Do this last)
        isInitialized = false

        // Note: We don't null out wifiP2pManager or wifiP2pChannel as they are lateinit.
        // The isInitialized flag will prevent their use.

        Log.d(TAG, "Wi-Fi P2P Connections disposed.")
        result.success(true) // Report overall success of the dispose operation
    }

    /**
     * Starts peer discovery.
     */
    private fun startPeerDiscovery(result: Result) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        wifiP2pManager.discoverPeers(wifiP2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery started.")
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                Log.e(TAG, "Peer discovery failed. Reason: ${reasonCodeToString(reasonCode)}")
                result.error("DISCOVERY_FAILED", "Peer discovery failed: ${reasonCodeToString(reasonCode)}", null)
            }
        })
    }

    /**
     * Stops ongoing peer discovery.
     */
    private fun stopPeerDiscovery(result: Result) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        wifiP2pManager.stopPeerDiscovery(wifiP2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Stopped peer discovery.")
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                Log.w(TAG, "Stopping peer discovery failed (might be benign). Reason: ${reasonCodeToString(reasonCode)}")
                result.success(true) // Often okay if no discovery was active
            }
        })
    }

    /**
     * Connects to a peer with the given device address.
     */
    private fun connect(result: Result, address: String) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        val config = WifiP2pConfig().apply {
            deviceAddress = address
            wps.setup = WpsInfo.PBC
        }

        wifiP2pManager.connect(wifiP2pChannel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection initiated to $address")
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                Log.e(TAG, "Connection failed to initiate. Reason: ${reasonCodeToString(reasonCode)}")
                result.error("CONNECT_FAILED", "Connection failed to initiate: ${reasonCodeToString(reasonCode)}", null)
            }
        })
    }

    /**
     * Disconnects from the current P2P group or cancels an ongoing connection attempt.
     */
    private fun disconnect(result: Result) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        wifiP2pManager.requestGroupInfo(wifiP2pChannel) { group ->
            if (group != null) {
                removeGroupInternal(result)
            } else {
                cancelConnectInternal(result)
            }
        }
    }

    /** Helper to specifically cancel an ongoing connection attempt */
    private fun cancelConnectInternal(result: Result) {
         wifiP2pManager.cancelConnect(wifiP2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Cancelled connection attempt successfully.")
                result.success(true)
            }
            override fun onFailure(reasonCode: Int) {
                 Log.w(TAG, "Failed to cancel connection attempt. Reason: ${reasonCodeToString(reasonCode)}")
                result.success(true) // Report success as the goal (no connection) is achieved or wasn't needed.
            }
        })
    }

     /** Helper to specifically remove the current group */
    private fun removeGroupInternal(result: Result) {
        wifiP2pManager.removeGroup(wifiP2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Removed P2P group successfully.")
                 // Clear connection info after successful removal
                connectionInfoData = null
                connectionInfoEventSink?.success(null)
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                Log.e(TAG, "Failed to remove P2P group. Reason: ${reasonCodeToString(reasonCode)}")
                result.error("REMOVE_GROUP_FAILED", "Failed to remove group: ${reasonCodeToString(reasonCode)}", null)
            }
        })
    }

    /**
     * Creates a P2P group, making this device the Group Owner.
     */
    private fun createGroup(result: Result) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        wifiP2pManager.createGroup(wifiP2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Group creation initiated.")
                result.success(true)
            }

            override fun onFailure(reasonCode: Int) {
                Log.e(TAG, "Group creation failed. Reason: ${reasonCodeToString(reasonCode)}")
                result.error("CREATE_GROUP_FAILED", "Group creation failed: ${reasonCodeToString(reasonCode)}", null)
            }
        })
    }

    /**
     * Removes the P2P group (if owner) or leaves the group (if client).
     */
    private fun removeGroup(result: Result) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        removeGroupInternal(result)
    }

    /**
     * Requests current P2P group information and returns it via the result.
     */
    private fun requestGroupInfo(result: Result) {
        if (!::wifiP2pManager.isInitialized) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }
        wifiP2pManager.requestGroupInfo(wifiP2pChannel) { group: WifiP2pGroup? ->
            if (group != null) {
                val groupInfoMap = serializeGroupInfo(group)
                Log.d(TAG, "Group Info requested: $groupInfoMap")
                result.success(groupInfoMap)
            } else {
                Log.d(TAG, "Group Info requested: Not currently in a P2P group.")
                result.success(null) // Return null if not in a group
            }
        }
    }

     /**
     * Requests the list of discovered peers. Updates local cache and notifies Flutter.
     * Internal function called by receiver.
     */
    internal fun requestPeersInternal() {
        if (!::wifiP2pManager.isInitialized) {
             Log.w(TAG, "requestPeersInternal called but plugin not initialized.")
             return
         }
         // Check permissions before requesting peers (especially on Android 12+)
         if (!hasP2pPermissions()) {
            Log.w(TAG, "requestPeersInternal: Missing required P2P permissions.")
            // Optionally send an error/empty list to Flutter?
            foundPeersData = emptyList()
            foundPeersEventSink?.success(foundPeersData)
            return
         }

        wifiP2pManager.requestPeers(wifiP2pChannel) { peers: WifiP2pDeviceList? ->
            val deviceList = peers?.deviceList ?: emptyList()
            val newPeersData = deviceList.map { serializeDevice(it) }
            // Only update if data changed to avoid unnecessary sink calls
            if (foundPeersData != newPeersData) {
                 foundPeersData = newPeersData
                 Log.d(TAG, "Found Peers Updated (${foundPeersData.size}): $foundPeersData")
                 foundPeersEventSink?.success(foundPeersData)
            }
        }
    }

    /**
     * Returns the last known list of discovered peers via the result.
     * Method channel callable function.
     */
    private fun fetchPeers(result: Result) {
        Log.d(TAG, "Fetching cached peers list.")
        result.success(foundPeersData)
    }

    /**
     * Returns the last known connection info via the result.
     * Method channel callable function.
     */
     private fun fetchConnectionInfo(result: Result) {
         Log.d(TAG, "Fetching cached connection info.")
         result.success(connectionInfoData)
     }


    // --- Permission and Service Checks ---

     /** Internal check for permissions without using Result */
    private fun hasP2pPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val nearbyWifiGranted = ContextCompat.checkSelfPermission(
                applicationContext, Manifest.permission.NEARBY_WIFI_DEVICES
            ) == PackageManager.PERMISSION_GRANTED
            val fineLocationGranted = ContextCompat.checkSelfPermission(
                applicationContext, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            nearbyWifiGranted && fineLocationGranted
        } else {
            ContextCompat.checkSelfPermission(
                applicationContext, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }


    /**
     * Checks if the necessary permissions for Wi-Fi P2P are granted.
     * Method channel callable function.
     */
    private fun checkP2pPermissions(result: Result) {
        Log.d(TAG, "Checking P2P Permissions.")
        result.success(hasP2pPermissions()) // Use internal helper
    }

    /**
     * Requests the necessary permissions for Wi-Fi P2P operations from the user.
     * Method channel callable function.
     */
    private fun askP2pPermissions(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to request permissions", null)
            return
        }

        val permissionsToRequest: Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.NEARBY_WIFI_DEVICES,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        val permissionsNeeded = permissionsToRequest.filter {
            ContextCompat.checkSelfPermission(applicationContext, it) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

        if (permissionsNeeded.isEmpty()) {
            Log.d(TAG, "Permissions already granted.")
            result.success(true) // Indicate already granted or request not needed now
            return
        }

        Log.d(TAG, "Requesting permissions: ${permissionsNeeded.joinToString()}")
        ActivityCompat.requestPermissions(
            currentActivity,
            permissionsNeeded,
            LOCATION_PERMISSION_REQUEST_CODE
        )
        result.success(true) // Indicates the request dialog *was initiated*
    }

    private fun checkLocationEnabled(result: Result) {
        val locationManager = applicationContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (locationManager == null) {
            result.error("SERVICE_UNAVAILABLE", "Location manager service not available", null)
            return
        }
        var gpsEnabled = false
        var networkEnabled = false
        try {
            gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
            networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        } catch (e: Exception) {
             Log.e(TAG, "Error checking location provider status", e)
             // Default to false on error? Or return error?
             result.success(false) // Example: return false if error occurs
             return
        }
        result.success(gpsEnabled || networkEnabled)
    }

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

    private fun checkWifiEnabled(result: Result) {
        val wifiManager = applicationContext.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
         if (wifiManager == null) {
            result.error("SERVICE_UNAVAILABLE", "Wifi manager service not available", null)
            return
        }
        result.success(wifiManager.isWifiEnabled)
    }

     private fun enableWifiServices(result: Result) {
         val currentActivity = activity
         if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to open settings", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                 val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
                 currentActivity.startActivity(panelIntent)
            } else {
                 currentActivity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error opening Wi-Fi settings/panel: ${e.message}", e)
            result.error("SETTINGS_ERROR", "Could not open Wi-Fi settings/panel.", e.message)
        }
    }

    // --- Lifecycle and Receiver Management ---

    /**
     * Registers the BroadcastReceiver. Called automatically by onResume.
     */
    private fun registerReceiver() {
        // Added check: Don't register if activity is null (can happen in race conditions)
        if (!isInitialized || isReceiverRegistered || activity == null) {
             if (activity == null) Log.w(TAG, "Cannot register receiver: Activity is null.")
             if (isReceiverRegistered) Log.v(TAG, "Receiver already registered.") // Verbose log level
             if (!isInitialized) Log.w(TAG, "Cannot register receiver: Not initialized.")
            return
        }
        try {
             // Use applicationContext to register receiver for broader scope if needed,
             // but activity context is fine if receiver tied to activity lifecycle.
             // Stick with applicationContext based on previous code.
            applicationContext.registerReceiver(broadcastReceiver, intentFilter)
            isReceiverRegistered = true
            Log.d(TAG, "BroadcastReceiver registered.")
        } catch (e: Exception) {
            Log.e(TAG, "Error registering receiver: ${e.message}", e)
        }
    }

    /**
     * Unregisters the BroadcastReceiver. Called automatically by onPause.
     */
    private fun unregisterReceiver() {
        if (isInitialized && isReceiverRegistered && broadcastReceiver != null) {
            try {
                applicationContext.unregisterReceiver(broadcastReceiver)
                isReceiverRegistered = false
                Log.d(TAG, "BroadcastReceiver unregistered.")
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Receiver already unregistered or never registered? ${e.message}")
            } catch (e: Exception) {
                 Log.e(TAG, "Error unregistering receiver: ${e.message}", e)
            }
        } else {
             Log.v(TAG, "Unregister receiver skipped: " +
                     "Initialized=${::wifiP2pManager.isInitialized}, " +
                     "Registered=$isReceiverRegistered, " +
                     "ReceiverNull=${broadcastReceiver == null}")
        }
    }

    // --- Data Serialization Helpers ---

    private fun serializeDevice(device: WifiP2pDevice?): Map<String, Any?> {
        if (device == null) return emptyMap()
        // Add null checks for potentially null fields like deviceName
        return mapOf(
            "deviceName" to device.deviceName, // Can be null
            "deviceAddress" to device.deviceAddress,
            "primaryDeviceType" to device.primaryDeviceType,
            "secondaryDeviceType" to device.secondaryDeviceType,
            "status" to device.status,
            "isGroupOwner" to device.isGroupOwner,
            "isServiceDiscoveryCapable" to device.isServiceDiscoveryCapable
        )
    }

     private fun serializeGroupInfo(group: WifiP2pGroup?): Map<String, Any?> {
         if (group == null) return emptyMap()
         return mapOf(
             "isGroupOwner" to group.isGroupOwner,
             "passPhrase" to group.passphrase,
             "groupNetworkName" to group.networkName,
             "owner" to serializeDevice(group.owner),
             "clients" to group.clientList.map { serializeDevice(it) }
         )
     }

    internal fun serializeConnectionInfo(networkInfo: NetworkInfo?, p2pInfo: WifiP2pInfo?, group: WifiP2pGroup?): Map<String, Any?>? {
         // Return null if essential info is missing (e.g., not connected and no group formed)
         if (p2pInfo == null || (!p2pInfo.groupFormed && networkInfo?.isConnected != true)) {
             // If neither connected nor group formed, return null or an empty map indicating no connection
             return null // Or return mapOf("isConnected" to false, "groupFormed" to false)
         }

        val clients = group?.clientList?.map { serializeDevice(it) } ?: emptyList()
        val ownerDevice = group?.owner
        val groupOwnerAddress = p2pInfo.groupOwnerAddress?.toString() ?: ""

        val ownerDetails = if (p2pInfo.isGroupOwner) {
             mapOf(
                 // Try getting this device's name if possible? Difficult without extra call.
                 "deviceName" to "This Device (Owner)",
                 "deviceAddress" to groupOwnerAddress
             )
        } else {
             serializeDevice(ownerDevice)
        }

        return mapOf(
            "isConnected" to (networkInfo?.isConnected ?: false), // Check networkInfo state
            "isGroupOwner" to p2pInfo.isGroupOwner,
            "groupFormed" to p2pInfo.groupFormed,
            "groupOwnerAddress" to groupOwnerAddress,
            "owner" to ownerDetails,
            "clients" to clients
        )
    }

     /**
     * Updates the connection info state and notifies Flutter via EventChannel.
     * Called by the BroadcastReceiver.
     */
    internal fun updateConnectionInfoInternal(networkInfo: NetworkInfo?, p2pInfo: WifiP2pInfo?) {
        if (!::wifiP2pManager.isInitialized) return

        // Request group info to get client details
        wifiP2pManager.requestGroupInfo(wifiP2pChannel) { group ->
            val newConnectionInfo = serializeConnectionInfo(networkInfo, p2pInfo, group)

            // Update only if the data has meaningfully changed
            if (connectionInfoData != newConnectionInfo) {
                 connectionInfoData = newConnectionInfo
                 Log.d(TAG, "Connection Info Updated: $connectionInfoData")
                 // Send null if newConnectionInfo is null (disconnected state)
                 connectionInfoEventSink?.success(connectionInfoData)
            } else {
                 Log.v(TAG,"Connection info updated, but data hasn't changed.")
            }
        }
    }

    // --- EventChannel Stream Handlers ---

    private val foundPeersStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            Log.d(TAG, "FoundPeers StreamHandler: onListen - Starting periodic updates")
            foundPeersEventSink = events

            // Cancel any previous scope if somehow active
            foundPeersScope?.cancel()
            // Create a new scope bound to the Main dispatcher, suitable for UI/EventChannel updates
            // SupervisorJob ensures failure of one task doesn't cancel the scope
            foundPeersScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

            foundPeersScope?.launch {
                // Send the current list immediately before starting the loop
                try {
                    events.success(foundPeersData)
                } catch (e: Exception) {
                     Log.e(TAG, "FoundPeers Stream Initial Send Error: ${e.message}", e)
                }

                // Start the periodic refresh loop
                while (isActive) { // Loop continues as long as the scope is active
                    delay(DATA_REFRESH_INTERVAL_MS) // Wait for the interval
                    try {
                        if (!isInitialized) {
                            Log.v(TAG, "FoundPeers Timer: Skipping update, plugin not initialized.")
                            continue // Skip this iteration if not initialized
                        }
                        // 1. Trigger the peer request (this might update foundPeersData internally)
                        requestPeersInternal() // This already logs and sends *if changed*

                        // 2. Explicitly send the *current* data again every interval,
                        //    regardless of whether requestPeersInternal detected a change.
                        foundPeersEventSink?.success(foundPeersData)
                            ?: Log.w(TAG, "FoundPeers Timer: EventSink is null, cannot send peer data.")

                    } catch (e: Exception) {
                        Log.e(TAG, "FoundPeers Timer Error during update: ${e.message}", e)
                        // Decide if you want to stop the loop on error or just log and continue
                        // For now, we log and continue the loop

                        // foundPeersEventSink?.error(
                        //     "PEER_UPDATE_ERROR", // Error code
                        //     "Periodic peer update failed: ${e.message}", // Error message
                        //     e.stackTraceToString() // Error details
                        // )
                        // foundPeersScope?.cancel()
                        // Log.w(TAG, "FoundPeers Timer loop stopped due to error.")
                    }
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "FoundPeers StreamHandler: onCancel - Stopping periodic updates")
            foundPeersScope?.cancel() // Cancel the coroutine loop
            foundPeersScope = null
            foundPeersEventSink = null
        }
    }

    private val connectionInfoStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            Log.d(TAG, "ConnectionInfo StreamHandler: onListen - Starting periodic updates")
            connectionInfoEventSink = events // Use renamed sink variable

            // Cancel any previous scope
            connectionInfoScope?.cancel()
            connectionInfoScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

            connectionInfoScope?.launch {
                // Send the current connection state immediately
                try {
                    events.success(connectionInfoData) // Send current data (can be null)
                } catch (e: Exception) {
                        Log.e(TAG, "ConnectionInfo Stream Initial Send Error: ${e.message}", e)
                }

                    // Trigger an initial update check when listener attaches (optional but good)
                    fetchAndSendConnectionInfo("Initial Fetch")

                // Start the periodic refresh loop
                while (isActive) {
                    delay(DATA_REFRESH_INTERVAL_MS)
                    fetchAndSendConnectionInfo("Periodic Timer")
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "ConnectionInfo StreamHandler: onCancel - Stopping periodic updates")
            connectionInfoScope?.cancel() // Cancel the coroutine loop
            connectionInfoScope = null
            connectionInfoEventSink = null // Use renamed sink variable
        }

        // Helper function to fetch, serialize, and send connection info within the coroutine
        private suspend fun fetchAndSendConnectionInfo(logContext: String) {
            if (!isInitialized || !::wifiP2pManager.isInitialized) {
                Log.v(TAG, "ConnectionInfo Timer ($logContext): Skipping update, plugin not initialized.")
                // Optionally send null or last known state if not initialized?
                // connectionInfoEventSink?.success(connectionInfoData) // Send last known state
                return
            }
            try {
                    // Fetch connection info and group info (asynchronously if possible, but WifiP2pManager is callback-based)
                    // We'll use withContext to ensure callbacks are handled correctly if needed,
                    // although requestConnectionInfo/requestGroupInfo might work directly on Main.
                    // However, serializing might take time, so doing it off main thread is safer.
                    // Let's stick to Main for simplicity as sinks require it.

                    wifiP2pManager.requestConnectionInfo(wifiP2pChannel) { p2pInfo: WifiP2pInfo? ->
                        // Now fetch group info inside the callback
                        wifiP2pManager.requestGroupInfo(wifiP2pChannel) { group: WifiP2pGroup? ->
                            // We don't have direct access to NetworkInfo here easily, pass null
                            val currentConnectionInfo = serializeConnectionInfo(null, p2pInfo, group)

                            // Update local cache (optional, depends if you need it elsewhere)
                            // If you update here, consider thread safety if accessed from other places.
                            // connectionInfoData = currentConnectionInfo

                            // Send the latest fetched info via the sink
                            connectionInfoEventSink?.success(currentConnectionInfo)
                                ?: Log.w(TAG, "ConnectionInfo Timer ($logContext): EventSink is null, cannot send.")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "ConnectionInfo Timer ($logContext) Error during update: ${e.message}", e)
                    // Optionally send an error state or null?
                    // connectionInfoEventSink?.error("FETCH_ERROR", "Failed to fetch connection info", e.message)
            }
        }
    }

    // --- Utility ---

    private fun reasonCodeToString(reasonCode: Int): String {
        return when (reasonCode) {
            WifiP2pManager.ERROR -> "ERROR"
            WifiP2pManager.P2P_UNSUPPORTED -> "P2P_UNSUPPORTED"
            WifiP2pManager.BUSY -> "BUSY"
            WifiP2pManager.NO_SERVICE_REQUESTS -> "NO_SERVICE_REQUESTS"
            else -> "Unknown Error ($reasonCode)"
        }
    }

    // --- Inner BroadcastReceiver Class ---

    /**
     * Handles Wi-Fi Direct broadcast intents.
     * As an INNER class, it has access to FlutterP2pConnectionPlugin's members.
     */
    private inner class WiFiDirectBroadcastReceiver(
        private val manager: WifiP2pManager, // Keep manager/channel if needed for receiver actions
        private val channel: WifiP2pManager.Channel
    ) : BroadcastReceiver() {

        @Suppress("DEPRECATION")
        override fun onReceive(context: Context, intent: Intent) {
            val action: String = intent.action ?: return

            when (action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    if (state == WifiP2pManager.WIFI_P2P_STATE_ENABLED) {
                        Log.d(TAG, "Receiver: Wi-Fi P2P is enabled.")
                    } else {
                        Log.d(TAG, "Receiver: Wi-Fi P2P is disabled.")
                        // Clear local data and notify Flutter when P2P is disabled
                        foundPeersData = emptyList()
                        connectionInfoData = null // Or specific disconnected state map
                        foundPeersEventSink?.success(foundPeersData)
                        connectionInfoEventSink?.success(connectionInfoData)
                    }
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    Log.d(TAG, "Receiver: P2P peers changed.")
                    // Request the updated peer list using internal helper
                    requestPeersInternal()
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    Log.d(TAG, "Receiver: P2P connection changed.")
                    val networkInfo: NetworkInfo? = intent.getParcelableExtra(WifiP2pManager.EXTRA_NETWORK_INFO)
                    val p2pInfo: WifiP2pInfo? = intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
                    // Update connection state using internal helper
                     updateConnectionInfoInternal(networkInfo, p2pInfo)
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    val device: WifiP2pDevice? = intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    Log.d(TAG, "Receiver: This device changed: ${serializeDevice(device)}")
                    // If connection state might depend on this device's info (e.g., owner status),
                    // trigger a connection info update.
                    manager.requestConnectionInfo(channel) { info ->
                        // Need NetworkInfo too ideally, maybe cache last known?
                        // For now, just update with P2pInfo and let updateConnectionInfoInternal fetch group info
                        updateConnectionInfoInternal(null, info) // Could pass last known NetworkInfo if cached
                    }
                }
            }
        }
    } // --- End of inner class WiFiDirectBroadcastReceiver ---

} 