package com.ugo.studio.plugins.flutter_p2p_connection

import android.content.Context
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.EventChannel

import com.ugo.studio.plugins.flutter_p2p_connection.Constants
import com.ugo.studio.plugins.flutter_p2p_connection.DataUtils
import com.ugo.studio.plugins.flutter_p2p_connection.ServiceManager
import io.flutter.plugin.common.MethodChannel


class HostManager(
    private val applicationContext: Context,
    private val wifiManager: WifiManager,
    private val serviceManager: ServiceManager, // Inject ServiceManager
    private val mainHandler: Handler
) {
    private val TAG = Constants.TAG

    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var hotspotCallback: WifiManager.LocalOnlyHotspotCallback? = null
    private var hotspotInfoData: Map<String, Any?>? = null
    private var hotspotStateEventSink: EventChannel.EventSink? = null

    fun initialize() {
        Log.d(TAG, "HostManager initialized")
    }

    @RequiresApi(Constants.MIN_HOTSPOT_API_LEVEL)
    fun createHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Constants.MIN_HOTSPOT_API_LEVEL) {
            result.error("UNSUPPORTED_OS_VERSION", "LocalOnlyHotspot requires Android 8.0 (API 26) or higher.", null)
            return
        }
        if (hotspotReservation != null) {
            Log.w(TAG, "Hotspot already active.")
            // Re-send current state in case listener attached after hotspot started
            mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData ?: DataUtils.createHotspotInfoMap(false, null, null)) }
            result.success(true)
            return
        }
        // Use injected serviceManager for checks
        if (!serviceManager.isLocationEnabled()) {
            result.error("LOCATION_DISABLED", "Location services must be enabled to start a hotspot.", null)
            return
        }
        // Permission check is implicitly handled by the main plugin before calling this

        if (hotspotCallback == null) {
            hotspotCallback = createHotspotCallback()
        }

        try {
            // Double check location just before starting
            if (!serviceManager.isLocationEnabled()) {
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

    fun removeHotspot(result: MethodChannel.Result) {
        stopHotspotInternal() // This function now handles sending the update
        result.success(true)
    }

    fun stopHotspotInternal() {
        val wasActive = hotspotReservation != null || hotspotInfoData?.get("isActive") == true
        var needsStateUpdate = false // Flag to track if state actually changed from active to inactive

        if (hotspotReservation != null) {
            Log.d(TAG, "Stopping LocalOnlyHotspot...")
             try {
                 // Attempt to close the reservation. This *should* trigger the onStopped callback,
                 // but we don't rely on it for the immediate state update anymore.
                hotspotReservation?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Exception closing hotspot reservation: ${e.message}", e)
                 // Even if close fails, we mark the state as stopped.
            } finally {
                 // Set reservation to null unconditionally after attempting close
                 hotspotReservation = null
                 if (wasActive) {
                     needsStateUpdate = true // Mark that we need to update the state to inactive
                 }
             }
        } else {
            Log.d(TAG, "Stop Hotspot called but no active reservation found.")
            // If it was cached as active but reservation is null (inconsistent state), mark for update.
            if (wasActive) {
                needsStateUpdate = true
            }
        }

        // Ensure the state is updated to inactive and event sent if the hotspot *was* active
        // and its current cached state might not yet reflect 'inactive'.
        if (needsStateUpdate && hotspotInfoData?.get("isActive") != false) {
            Log.d(TAG, "stopHotspotInternal: Updating state to inactive and sending event.")
            hotspotInfoData = DataUtils.createHotspotInfoMap(false, null, null)
            // Send update via EventChannel on the main thread
            mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData!!) }
        } else if (needsStateUpdate) {
             // This case means it was active, we attempted to stop, but the state was already inactive (perhaps callback race). Log it.
             Log.d(TAG, "stopHotspotInternal: Attempted stop, but state was already inactive. No event sent from here.")
        } else {
             Log.d(TAG, "stopHotspotInternal: Hotspot was not active or already stopped. No state change needed.")
        }
    }

    @RequiresApi(Constants.MIN_HOTSPOT_API_LEVEL)
    private fun createHotspotCallback(): WifiManager.LocalOnlyHotspotCallback {
        return object : WifiManager.LocalOnlyHotspotCallback() {
            override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                super.onStarted(reservation)
                if (reservation == null) {
                    Log.e(TAG, "Hotspot started callback received null reservation.")
                    hotspotInfoData = DataUtils.createHotspotInfoMap(false, null, null)
                    mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData!!) }
                    return
                }
                Log.d(TAG, "LocalOnlyHotspot Started.")
                hotspotReservation = reservation
                val config = reservation.wifiConfiguration
                
                // Try to get IP immediately, then retry after a delay if needed
                val initialHotspotIp = DataUtils.getHostIpAddress()
                if (initialHotspotIp == null) {
                    Log.d(TAG, "Hotspot IP not immediately available, retrying after delay...")
                    mainHandler.postDelayed({
                        var finalHotspotIp = DataUtils.getHostIpAddress()
                        if (finalHotspotIp == null) {
                            // Final fallback - use the common LocalOnlyHotspot IP
                            finalHotspotIp = "192.168.49.1"
                            Log.w(TAG, "Using fallback LocalOnlyHotspot IP: $finalHotspotIp")
                        }
                        hotspotInfoData = DataUtils.createHotspotInfoMap(true, config, finalHotspotIp)
                        mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData!!) }
                    }, 500) // 500ms delay for interface to be created
                } else {
                    hotspotInfoData = DataUtils.createHotspotInfoMap(true, config, initialHotspotIp)
                    mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData!!) }
                }
            }
            override fun onStopped() {
                super.onStopped()
                Log.d(TAG, "LocalOnlyHotspot Stopped Callback Triggered.")
                // Check if the state wasn't already updated by stopHotspotInternal
                if (hotspotInfoData?.get("isActive") != false) {
                    Log.w(TAG, "onStopped: Updating state to inactive (might be redundant).")
                    hotspotReservation = null // Ensure reservation is cleared if callback occurs later
                    hotspotInfoData = DataUtils.createHotspotInfoMap(false, null, null)
                    mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData!!) }
                } else {
                    Log.d(TAG, "onStopped: State already inactive, likely updated by stopHotspotInternal.")
                }
            }
            override fun onFailed(reason: Int) {
                super.onFailed(reason)
                Log.e(TAG, "LocalOnlyHotspot Failed. Reason: $reason")
                hotspotReservation = null
                hotspotInfoData = DataUtils.createHotspotInfoMap(false, null, null, reason)
                mainHandler.post { hotspotStateEventSink?.success(hotspotInfoData!!) }
            }
        }
    }

    fun dispose() {
        Log.d(TAG, "Disposing HostManager...")
        stopHotspotInternal()
        hotspotCallback = null
        hotspotInfoData = null
        hotspotStateEventSink?.endOfStream()
        hotspotStateEventSink = null
        Log.d(TAG, "HostManager disposed.")
    }

    // --- EventChannel Stream Handler (Hotspot State Handler) ---
    val hotspotStateStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            Log.d(TAG, "HotspotState StreamHandler: onListen")
            hotspotStateEventSink = events
            // Send the current cached state immediately when a listener attaches
            val currentState = hotspotInfoData ?: DataUtils.createHotspotInfoMap(
                false,
                null,
                DataUtils.getHostIpAddress() // Get current host IP if available
            )
            Log.d(TAG, "HotspotState StreamHandler: Sending initial state: $currentState")
            hotspotStateEventSink?.success(currentState)
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "HotspotState StreamHandler: onCancel")
            hotspotStateEventSink = null
        }
    }
}