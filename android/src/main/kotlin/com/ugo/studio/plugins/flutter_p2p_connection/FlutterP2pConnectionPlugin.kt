package com.ugo.studio.plugins.flutter_p2p_connection

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi // Correctly kept
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

import com.ugo.studio.plugins.flutter_p2p_connection.Constants
import com.ugo.studio.plugins.flutter_p2p_connection.ClientManager
import com.ugo.studio.plugins.flutter_p2p_connection.HostManager
import com.ugo.studio.plugins.flutter_p2p_connection.PermissionsManager
import com.ugo.studio.plugins.flutter_p2p_connection.ServiceManager

/** FlutterP2pConnectionPlugin Orchestrator */
class FlutterP2pConnectionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, DefaultLifecycleObserver {

    // Use qualified constants
    private val TAG = Constants.TAG

    private lateinit var methodChannel: MethodChannel
    private lateinit var clientStateEventChannel: EventChannel
    private lateinit var hotspotStateEventChannel: EventChannel

    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var activityLifecycle: Lifecycle? = null

    // System Services (initialized in initialize())
    private lateinit var wifiManager: WifiManager
    private lateinit var connectivityManager: ConnectivityManager
    // BluetoothAdapter might be null if not supported
    private var bluetoothAdapter: BluetoothAdapter? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Managers (initialized in initialize())
    private lateinit var permissionsManager: PermissionsManager
    private lateinit var serviceManager: ServiceManager
    private lateinit var hostManager: HostManager
    private lateinit var clientManager: ClientManager

    private var isInitialized = false

    // --- FlutterPlugin Implementation ---

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        // Use qualified constants
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, Constants.METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        // Use qualified constants
        clientStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.CLIENT_STATE_EVENT_CHANNEL_NAME)
        hotspotStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, Constants.HOTSPOT_STATE_EVENT_CHANNEL_NAME)
        // Stream handlers will be set in initialize() after managers are created

        Log.d(TAG, "Plugin attached to engine.")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "Plugin detached from engine.")
        methodChannel.setMethodCallHandler(null)
        clientStateEventChannel.setStreamHandler(null)
        hotspotStateEventChannel.setStreamHandler(null)
        disposeManagers() // Clean up resources
        activityLifecycle?.removeObserver(this)
        activity = null
        activityLifecycle = null
        isInitialized = false
    }

    // --- ActivityAware Implementation ---
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityLifecycle = binding.lifecycle as Lifecycle?
        activityLifecycle?.addObserver(this)
        if (isInitialized) {
            // Update managers with the current activity if already initialized
            permissionsManager.updateActivity(activity)
            serviceManager.updateActivity(activity)
        }
        Log.d(TAG, "Plugin attached to activity.")
    }
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        if (isInitialized) {
            permissionsManager.updateActivity(null)
            serviceManager.updateActivity(null)
        }
        Log.d(TAG, "Plugin detached from activity for config changes.")
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
         if (isInitialized) {
            permissionsManager.updateActivity(activity)
            serviceManager.updateActivity(activity)
        }
        Log.d(TAG, "Plugin reattached to activity for config changes.")
    }
    override fun onDetachedFromActivity() {
        Log.d(TAG, "Plugin detached from activity.")
        activityLifecycle?.removeObserver(this)
        if (isInitialized) {
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
        Log.d(TAG, "Method call received: ${call.method}")

        // Handle methods that don't require full initialization
        when (call.method) {
            "getPlatformVersion" -> { result.success("${Build.VERSION.RELEASE}"); return }
            "getPlatformModel" -> { result.success("${Build.MODEL}"); return }
            "initialize" -> { initialize(result); return }
            // Permissions and basic service checks can often be done before full init
            "checkP2pPermissions", "askP2pPermissions",
            "checkLocationEnabled", "enableLocationServices",
            "checkWifiEnabled", "enableWifiServices",
            "checkBluetoothEnabled", "enableBluetoothServices" -> {
                 // Initialize permission/service managers if not done yet, but don't set isInitialized=true yet
                 if (!this::permissionsManager.isInitialized) {
                    initializeMinimalManagersForChecks()
                 }
                 // Fall through to the main when block if managers are ready
                 if (!this::permissionsManager.isInitialized) {
                      result.error("INIT_ERROR", "Could not initialize managers for checks", null)
                      return
                 }
            }
        }

        // Check if initialized for methods requiring it
        if (!isInitialized) {
            // Allow connect/disconnect attempt even if not fully initialized,
            // the managers themselves will check internal state/permissions.
            if (call.method !in listOf("connectToHotspot", "disconnectFromHotspot")) {
                result.error("NOT_INITIALIZED", "Plugin not initialized. Call initialize() first for method ${call.method}.", null)
                Log.w(TAG, "Method call ${call.method} rejected: Not Initialized")
                return
            } else if (!this::clientManager.isInitialized) {
                 // For connect/disconnect, ensure client manager is at least attempted to init
                 result.error("NOT_INITIALIZED", "Plugin not initialized. Call initialize() first for method ${call.method}.", null)
                 Log.w(TAG, "Method call ${call.method} rejected: Client Manager Not Initialized")
                 return
            }
        }

        try {
            when (call.method) {
                // --- Core ---
                "dispose" -> dispose(result)
                // --- Host Methods ---
                "createHotspot" -> {
                    // Use qualified constant
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
                    val password: String? = call.argument("password")
                    if (ssid.isNullOrEmpty() || password == null) {
                        result.error("INVALID_ARGS", "Missing or invalid 'ssid' or 'password' arguments", null)
                    } else if (!permissionsManager.hasP2pPermissions()) {
                         result.error("PERMISSION_DENIED", "Missing required P2P permissions.", null)
                    }
                     else {
                        clientManager.connectToHotspot(result, ssid, password)
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

    private fun initialize(result: Result) {
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
            if (wm == null || cm == null) {
                Log.e(TAG, "Failed to get WifiManager or ConnectivityManager.")
                result.error("SERVICE_UNAVAILABLE", "Required WiFi or Connectivity service not available.", null)
                return
            }
            wifiManager = wm
            connectivityManager = cm
            bluetoothAdapter = BluetoothAdapter.getDefaultAdapter() // Can be null

            // Initialize Managers
            permissionsManager = PermissionsManager(applicationContext)
            permissionsManager.updateActivity(activity) // Pass current activity if available

            serviceManager = ServiceManager(applicationContext, permissionsManager)
            serviceManager.updateActivity(activity) // Pass current activity

            hostManager = HostManager(applicationContext, wifiManager, serviceManager, mainHandler)
            hostManager.initialize()

            clientManager = ClientManager(wifiManager, connectivityManager, permissionsManager, serviceManager, mainHandler)
            clientManager.initialize()

            // Set EventChannel Stream Handlers
            clientStateEventChannel.setStreamHandler(clientManager.clientStateStreamHandler)
            hotspotStateEventChannel.setStreamHandler(hostManager.hotspotStateStreamHandler)


            isInitialized = true
            Log.d(TAG, "Plugin initialized successfully.")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "Error during initialization: ${e.message}", e)
            isInitialized = false // Ensure state reflects failure
            result.error("INITIALIZATION_FAILED", "Plugin initialization failed: ${e.message}", null)
        }
    }

     // Minimal init for permission/service checks before full initialization
    private fun initializeMinimalManagersForChecks() {
         if (this::permissionsManager.isInitialized) return // Already done

         try {
             permissionsManager = PermissionsManager(applicationContext)
             permissionsManager.updateActivity(activity)
             serviceManager = ServiceManager(applicationContext, permissionsManager)
             serviceManager.updateActivity(activity)
              Log.d(TAG, "Minimal managers initialized for checks.")
         } catch (e: Exception) {
              Log.e(TAG, "Failed to initialize minimal managers: ${e.message}", e)
              // Don't throw error here, let the subsequent check fail
         }
     }

    private fun dispose(result: Result) {
        Log.d(TAG, "Dispose called.")
        disposeManagers()
        isInitialized = false
         // Don't explicitly close sinks here, let managers handle it in their dispose
        result.success(true)
    }

    private fun disposeManagers() {
        if (!isInitialized && !this::clientManager.isInitialized && !this::hostManager.isInitialized) {
            Log.d(TAG, "Dispose called but managers were not initialized.")
            return
        }
        Log.d(TAG, "Disposing Managers...")
        // Dispose in reverse order of creation (optional, but good practice)
        if (this::clientManager.isInitialized) clientManager.dispose()
        if (this::hostManager.isInitialized) hostManager.dispose()
        // ServiceManager and PermissionsManager don't have explicit dispose methods for now

        Log.d(TAG, "Managers disposed.")
    }
}