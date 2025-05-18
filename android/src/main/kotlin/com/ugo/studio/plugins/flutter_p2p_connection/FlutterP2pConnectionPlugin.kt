package com.ugo.studio.plugins.flutter_p2p_connection

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
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

// Keep qualified imports
import com.ugo.studio.plugins.flutter_p2p_connection.Constants
import com.ugo.studio.plugins.flutter_p2p_connection.ClientManager
import com.ugo.studio.plugins.flutter_p2p_connection.HostManager
import com.ugo.studio.plugins.flutter_p2p_connection.PermissionsManager
import com.ugo.studio.plugins.flutter_p2p_connection.ServiceManager
import com.ugo.studio.plugins.flutter_p2p_connection.BleManager // Import BleManager

/** FlutterP2pConnectionPlugin Orchestrator */
class FlutterP2pConnectionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, DefaultLifecycleObserver {

    private val TAG = Constants.TAG

    // Method Channel
    private lateinit var methodChannel: MethodChannel

    // Event Channels
    private lateinit var clientStateEventChannel: EventChannel
    private lateinit var hotspotStateEventChannel: EventChannel
    private lateinit var bleScanResultEventChannel: EventChannel 
    private lateinit var bleConnectionStateEventChannel: EventChannel 
    private lateinit var bleReceivedDataEventChannel: EventChannel 


    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var activityLifecycle: Lifecycle? = null

    // System Services
    private lateinit var wifiManager: WifiManager
    private lateinit var connectivityManager: ConnectivityManager
    private var bluetoothAdapter: BluetoothAdapter? = null // Can be null if not supported

    private val mainHandler = Handler(Looper.getMainLooper())

    // Managers
    private lateinit var permissionsManager: PermissionsManager
    private lateinit var serviceManager: ServiceManager
    private lateinit var hostManager: HostManager
    private lateinit var clientManager: ClientManager
    private lateinit var bleManager: BleManager 

    private var isInitialized = false

    // --- FlutterPlugin Implementation ---

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, Constants.METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        // Setup Event Channels
        clientStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.CLIENT_STATE_EVENT_CHANNEL_NAME)
        hotspotStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.HOTSPOT_STATE_EVENT_CHANNEL_NAME)
        bleScanResultEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.BLE_SCAN_RESULT_EVENT_CHANNEL_NAME) 
        bleConnectionStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.BLE_CONNECTION_STATE_EVENT_CHANNEL_NAME) 
        bleReceivedDataEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.BLE_RECEIVED_DATA_EVENT_CHANNEL_NAME) 


        Log.d(TAG, "Plugin attached to engine.")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "Plugin detached from engine.")
        methodChannel.setMethodCallHandler(null)
        // Nullify stream handlers - BleManager handles its sinks internally on dispose
        clientStateEventChannel.setStreamHandler(null)
        hotspotStateEventChannel.setStreamHandler(null)
        bleScanResultEventChannel.setStreamHandler(null) 
        bleConnectionStateEventChannel.setStreamHandler(null) 
        bleReceivedDataEventChannel.setStreamHandler(null) 

        disposeManagers() // Clean up resources
        activityLifecycle?.removeObserver(this)
        activity = null
        activityLifecycle = null
        isInitialized = false
    }

    // --- ActivityAware Implementation ---
    // No changes needed here unless BleManager needs direct activity access,
    // which it currently doesn't. It gets context and managers via constructor.
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityLifecycle = binding.lifecycle as Lifecycle?
        activityLifecycle?.addObserver(this)
        if (isInitialized || this::permissionsManager.isInitialized) { // Update if already initialized or minimally initialized
            permissionsManager.updateActivity(activity)
            serviceManager.updateActivity(activity)
            // bleManager doesn't need direct activity access currently
        }
        Log.d(TAG, "Plugin attached to activity.")
    }
     override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        if (isInitialized || this::permissionsManager.isInitialized) {
            permissionsManager.updateActivity(null)
            serviceManager.updateActivity(null)
        }
        Log.d(TAG, "Plugin detached from activity for config changes.")
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
         if (isInitialized || this::permissionsManager.isInitialized) {
            permissionsManager.updateActivity(activity)
            serviceManager.updateActivity(activity)
        }
        Log.d(TAG, "Plugin reattached to activity for config changes.")
    }
    override fun onDetachedFromActivity() {
        Log.d(TAG, "Plugin detached from activity.")
        activityLifecycle?.removeObserver(this)
        if (isInitialized || this::permissionsManager.isInitialized) {
            permissionsManager.updateActivity(null)
            serviceManager.updateActivity(null)
        }
        activity = null
        activityLifecycle = null
    }


    // --- DefaultLifecycleObserver Implementation ---
    override fun onResume(owner: LifecycleOwner) { Log.d(TAG, "Activity Resumed (Lifecycle)") }
    override fun onPause(owner: LifecycleOwner) { Log.d(TAG, "Activity Paused (Lifecycle)") }

    // --- MethodCallHandler Implementation ---
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        // Log.d(TAG, "Method call received: ${call.method}")

        when (call.method) {
            "getPlatformVersion" -> { result.success("${Build.VERSION.RELEASE}"); return }
            "getPlatformModel" -> { result.success("${Build.MODEL}"); return }
            "initialize" -> { 
                val serviceUuid: String? = call.argument("serviceUuid") // Optional UUID for BLE
                initialize(result, serviceUuid); 
                return 
            }
            // Permission/Service checks might need minimal init
            "checkP2pPermissions", "askP2pPermissions",
            "checkLocationEnabled", "enableLocationServices",
            "checkWifiEnabled", "enableWifiServices",
            "checkBluetoothEnabled", "enableBluetoothServices" -> {
                 if (!this::permissionsManager.isInitialized) {
                    initializeMinimalManagersForChecks()
                 }
                 if (!this::permissionsManager.isInitialized) { // Check again after attempt
                      result.error("INIT_ERROR", "Could not initialize managers for checks", null)
                      return
                 }
                 // Fall through
            }
        }

        // Check if initialized for methods requiring full setup
        if (!isInitialized) {
             // Allow certain methods even if not fully initialized
             val allowedBeforeInit = listOf(
                 "connectToHotspot", "disconnectFromHotspot", // Already handled
                 "checkP2pPermissions", "askP2pPermissions",
                 "checkLocationEnabled", "enableLocationServices",
                 "checkWifiEnabled", "enableWifiServices",
                 "checkBluetoothEnabled", "enableBluetoothServices"
                 // Add BLE methods that might only need minimal init (e.g., check BT state)
             )
            if (call.method !in allowedBeforeInit) {
                result.error("NOT_INITIALIZED", "Plugin not initialized. Call initialize() first for method ${call.method}.", null)
                Log.w(TAG, "Method call ${call.method} rejected: Not Initialized")
                return
            }
            // Ensure required manager exists even if not fully initialized
            if (call.method in listOf("connectToHotspot", "disconnectFromHotspot") && !this::clientManager.isInitialized) {
                 result.error("NOT_INITIALIZED", "Client Manager not ready for ${call.method}.", null); return
            }
             // Add similar checks for BleManager if needed for specific early calls
             if (call.method.startsWith("ble") && !this::bleManager.isInitialized) {
                  result.error("NOT_INITIALIZED", "BLE Manager not ready for ${call.method}.", null); return
             }
        }

        try {
            when (call.method) {
                // --- Core ---
                "dispose" -> dispose(result)
                // --- Host Methods ---
                "createHotspot" -> {
                    if (Build.VERSION.SDK_INT < Constants.MIN_HOTSPOT_API_LEVEL) {
                        result.error("UNSUPPORTED_OS_VERSION", "LocalOnlyHotspot requires Android 8.0 (API 26) or higher.", null)
                        return
                    }
                    if (!permissionsManager.hasP2pPermissions()) {
                         result.error("PERMISSION_DENIED", "Missing required P2P permissions.", null)
                         return
                    }
                    hostManager.createHotspot(result)
                }
                "removeHotspot" -> hostManager.removeHotspot(result)
                // --- Client Connection Methods ---
                "connectToHotspot" -> {
                    val ssid: String? = call.argument("ssid")
                    val psk: String? = call.argument("psk")
                    if (ssid.isNullOrEmpty() || psk == null) {
                        result.error("INVALID_ARGS", "Missing or invalid 'ssid' or 'psk' arguments", null)
                    } else if (!permissionsManager.hasP2pPermissions()) {
                         result.error("PERMISSION_DENIED", "Missing required P2P permissions.", null)
                    }
                     else {
                        clientManager.connectToHotspot(result, ssid, psk)
                    }
                }
                "disconnectFromHotspot" -> clientManager.disconnectFromHotspot(result)
                // --- Permission ---
                "checkP2pPermissions" -> permissionsManager.checkP2pPermissions(result)
                "askP2pPermissions" -> permissionsManager.askP2pPermissions(result)
                // --- Services ---
                "checkLocationEnabled" -> serviceManager.checkLocationEnabled(result)
                "enableLocationServices" -> serviceManager.enableLocationServices(result)
                "checkWifiEnabled" -> serviceManager.checkWifiEnabled(result)
                "enableWifiServices" -> serviceManager.enableWifiServices(result)
                "checkBluetoothEnabled" -> serviceManager.checkBluetoothEnabled(result)
                "enableBluetoothServices" -> serviceManager.enableBluetoothServices(result)

                // --- BLE Methods ---
                "ble#startAdvertising" -> {
                     val ssid: String? = call.argument("ssid")
                     val psk: String? = call.argument("psk")
                     if (ssid == null || psk == null) {
                         result.error("INVALID_ARGS", "Missing 'ssid' or 'psk' argument for ble#startAdvertising", null)
                     } else {
                         bleManager.startBleAdvertising(result, ssid, psk)
                     }
                }
                "ble#stopAdvertising" -> bleManager.stopBleAdvertising(result)
                "ble#startScan" -> bleManager.startBleScan(result)
                "ble#stopScan" -> bleManager.stopBleScan(result)
                "ble#connect" -> {
                     val deviceAddress: String? = call.argument("deviceAddress")
                     if (deviceAddress == null) {
                          result.error("INVALID_ARGS", "Missing 'deviceAddress' argument for ble#connect", null)
                     } else {
                          bleManager.connectBleDevice(result, deviceAddress)
                     }
                 }
                 "ble#disconnect" -> {
                      val deviceAddress: String? = call.argument("deviceAddress")
                     if (deviceAddress == null) {
                          result.error("INVALID_ARGS", "Missing 'deviceAddress' argument for ble#disconnect", null)
                     } else {
                         bleManager.disconnectBleDevice(result, deviceAddress)
                     }
                 }
                // Add methods for writing characteristics if needed
                // "ble#writeCharacteristic" -> { ... }

                // Unknown method
                else -> {
                    Log.w(TAG, "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling method ${call.method}: ${e.message}", e)
            result.error("PLUGIN_ERROR", "Exception in method ${call.method}: ${e.message}", e.stackTraceToString())
        }
    }

    // --- Initialization and Disposal ---

    private fun initialize(result: Result, serviceUuid: String?) {
        if (isInitialized) {
            Log.d(TAG, "Already initialized.")
            result.success(true)
            return
        }

        Log.d(TAG, "Initializing Plugin...")
        try {
            // Get System Services
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            // Use BluetoothManager to get the adapter - more robust
            val btm = applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

            if (wm == null || cm == null ) { // btm can be null if BT not supported
                Log.e(TAG, "Failed to get WifiManager or ConnectivityManager.")
                result.error("SERVICE_UNAVAILABLE", "Required WiFi or Connectivity service not available.", null)
                return
            }
            wifiManager = wm
            connectivityManager = cm
            bluetoothAdapter = btm?.adapter // Assign adapter (can be null)

            if (bluetoothAdapter == null) {
                Log.w(TAG, "Bluetooth is not supported on this device.")
                // Decide if this is an error or just a warning
                // result.error("BLUETOOTH_UNSUPPORTED", "Bluetooth not supported on this device.", null)
                // return
            }

            // Initialize Managers
            permissionsManager = PermissionsManager(applicationContext)
            permissionsManager.updateActivity(activity)

            serviceManager = ServiceManager(applicationContext, permissionsManager, bluetoothAdapter) // Pass adapter
            serviceManager.updateActivity(activity)

            hostManager = HostManager(applicationContext, wifiManager, serviceManager, mainHandler)
            hostManager.initialize()

            clientManager = ClientManager(wifiManager, connectivityManager, permissionsManager, serviceManager, mainHandler)
            clientManager.initialize()

            // Initialize BleManager - MUST come after Permissions/Service Manager
            bleManager = BleManager(applicationContext, bluetoothAdapter, serviceUuid, permissionsManager, serviceManager, mainHandler)
            bleManager.initialize()


            // Set EventChannel Stream Handlers
            clientStateEventChannel.setStreamHandler(clientManager.clientStateStreamHandler)
            hotspotStateEventChannel.setStreamHandler(hostManager.hotspotStateStreamHandler)
            // Set BLE Stream Handlers
            bleScanResultEventChannel.setStreamHandler(bleManager.scanResultStreamHandler)
            bleConnectionStateEventChannel.setStreamHandler(bleManager.connectionStateStreamHandler)
            bleReceivedDataEventChannel.setStreamHandler(bleManager.receivedDataStreamHandler)


            isInitialized = true
            Log.d(TAG, "Plugin initialized successfully.")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "Error during initialization: ${e.message}", e)
            isInitialized = false
            result.error("INITIALIZATION_FAILED", "Plugin initialization failed: ${e.message}", null)
        }
    }

     private fun initializeMinimalManagersForChecks() {
         if (this::permissionsManager.isInitialized) return

         try {
             permissionsManager = PermissionsManager(applicationContext)
             permissionsManager.updateActivity(activity)
              // Also get adapter minimally if needed for BT checks
             if (bluetoothAdapter == null) {
                  val btm = applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                  bluetoothAdapter = btm?.adapter
             }
             serviceManager = ServiceManager(applicationContext, permissionsManager, bluetoothAdapter) // Pass adapter
             serviceManager.updateActivity(activity)
              Log.d(TAG, "Minimal managers initialized for checks.")
         } catch (e: Exception) {
              Log.e(TAG, "Failed to initialize minimal managers: ${e.message}", e)
         }
     }

    private fun dispose(result: Result) {
        Log.d(TAG, "Dispose called.")
        disposeManagers()
        isInitialized = false
        result.success(true)
    }

    private fun disposeManagers() {
        // Check based on a core manager like permissionsManager
        if (!this::permissionsManager.isInitialized) {
             Log.d(TAG, "Dispose called but managers were not initialized.")
             return
        }
        Log.d(TAG, "Disposing Managers...")
        // Dispose in reverse order of creation (optional, but good practice)
        if (this::bleManager.isInitialized) bleManager.dispose()
        if (this::clientManager.isInitialized) clientManager.dispose()
        if (this::hostManager.isInitialized) hostManager.dispose()
        // ServiceManager and PermissionsManager don't have explicit dispose methods currently

        Log.d(TAG, "Managers disposed.")
    }
}