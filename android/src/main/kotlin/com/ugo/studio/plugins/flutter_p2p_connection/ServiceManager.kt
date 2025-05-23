package com.ugo.studio.plugins.flutter_p2p_connection

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Log

import com.ugo.studio.plugins.flutter_p2p_connection.Constants
import com.ugo.studio.plugins.flutter_p2p_connection.PermissionsManager
import io.flutter.plugin.common.MethodChannel

class ServiceManager(
    private val applicationContext: Context,
    private val permissionsManager: PermissionsManager, // Inject PermissionsManager
    private val bluetoothAdapter: BluetoothAdapter? // Inject adapter instance (can be null)
) {
    private var activity: Activity? = null
    private val TAG = Constants.TAG

    // Lazy initialization for managers that don't need injection
    private val wifiManager: WifiManager by lazy {
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }
    private val locationManager: LocationManager by lazy {
        applicationContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    }

    fun updateActivity(activity: Activity?) {
        this.activity = activity
    }

    // --- Location ---
    fun isLocationEnabled(): Boolean {
        return try {
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking location provider status", e)
            false
        }
    }

    fun checkLocationEnabled(result: MethodChannel.Result) {
        result.success(isLocationEnabled())
    }

    fun enableLocationServices(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to open location settings", null)
            return
        }
        try {
            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            // intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) // Add only if necessary
            currentActivity.startActivity(intent)
            result.success(true) // Indicate settings were opened
        } catch (e: Exception) {
            Log.e(TAG, "Error opening location settings: ${e.message}", e)
            result.error("SETTINGS_ERROR", "Could not open location settings.", e.message)
        }
    }

    // --- Wi-Fi ---
    fun isWifiEnabled(): Boolean {
         return try {
            wifiManager.isWifiEnabled
        } catch (e: Exception) {
           Log.e(TAG, "Error checking Wi-Fi enabled state: ${e.message}", e)
           return false // Assume false if error occurs
        }
    }

    fun checkWifiEnabled(result: MethodChannel.Result) {
        result.success(isWifiEnabled())
    }

    @SuppressLint("NewApi") // For Settings.Panel
    fun enableWifiServices(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to open Wi-Fi settings/panel", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
                // panelIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) // Add only if necessary
                currentActivity.startActivity(panelIntent)
            } else {
                // For older OS, go to general Wi-Fi settings
                val settingsIntent = Intent(Settings.ACTION_WIFI_SETTINGS)
                // settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) // Add only if necessary
                currentActivity.startActivity(settingsIntent)
            }
            result.success(true) // Indicate settings/panel was opened
        } catch (e: Exception) {
            Log.e(TAG, "Error opening Wi-Fi settings/panel: ${e.message}", e)
            result.error("SETTINGS_ERROR", "Could not open Wi-Fi settings/panel.", e.message)
        }
    }

    // --- Bluetooth ---
    @SuppressLint("MissingPermission") // Permission check is done internally via helper
    fun isBluetoothEnabled(): Boolean {
        // Use the injected adapter instance
        val adapter = bluetoothAdapter ?: return false // Device doesn't support Bluetooth
        if (!permissionsManager.hasBluetoothConnectPermission()) { // Check needed permission (API 31+)
             Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to check Bluetooth state (API 31+ requirement). Returning false.")
             return false
        }
        return try {
            adapter.isEnabled
        } catch (e: SecurityException) { // Catch specific SecurityException
            Log.e(TAG, "SecurityException checking Bluetooth state: ${e.message}", e)
            false
        } catch (e: Exception) { // Catch general exceptions
            Log.e(TAG, "Error checking Bluetooth enabled state: ${e.message}", e)
            false
        }
    }

    fun checkBluetoothEnabled(result: MethodChannel.Result) {
        result.success(isBluetoothEnabled()) // Calls the updated isBluetoothEnabled
    }

    @SuppressLint("MissingPermission") // Permission check is done internally for state, intent launch relies on system UI
    fun enableBluetoothServices(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity is not available to request Bluetooth enable", null)
            return
        }
        // Use the injected adapter instance
        val adapter = bluetoothAdapter
        if (adapter == null) {
             result.error("BLUETOOTH_UNAVAILABLE", "Device does not support Bluetooth.", null)
             return
        }

        // Check permission before checking state (as isEnabled requires it on S+)
        if (!permissionsManager.hasBluetoothConnectPermission()) { // Check needed permission (API 31+)
             result.error("PERMISSION_DENIED", "Missing BLUETOOTH_CONNECT permission (needed for check/enable on API 31+).", null)
             return
        }

        // Check if already enabled (now uses the potentially permitted isEnabled call)
        if (adapter.isEnabled) {
            Log.d(TAG, "Bluetooth is already enabled.")
            result.success(true) // Indicate it's already enabled
            return
        }

        // Create intent to request Bluetooth enable
        val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
        try {
            // Launching ACTION_REQUEST_ENABLE implicitly uses BLUETOOTH_CONNECT on API 31+
            // if the permission is declared in the manifest. No separate runtime check needed *here*.
            currentActivity.startActivity(enableBtIntent)
            // You usually don't need the result code from this intent; you check the adapter state again later if needed.
            result.success(true) // Indicate the request intent was successfully launched
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException launching Bluetooth enable intent: ${e.message}", e)
            result.error("PERMISSION_ERROR", "Could not launch Bluetooth enable request due to permission issue (check manifest?).", e.message)
        }
        catch (e: Exception) {
             Log.e(TAG, "Error launching Bluetooth enable intent: ${e.message}", e)
             result.error("INTENT_ERROR", "Could not launch Bluetooth enable request.", e.message)
        }
    }
}