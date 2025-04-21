package com.ugo.studio.plugins.flutter_p2p_connection

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.*
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*
import java.util.concurrent.ConcurrentHashMap // Use thread-safe map

import com.ugo.studio.plugins.flutter_p2p_connection.Constants

@SuppressLint("MissingPermission") // Permissions checked before use
class BleManager(
    private val context: Context,
    private val bluetoothAdapter: BluetoothAdapter?, // Can be null if BT not supported
    private val permissionsManager: PermissionsManager,
    private val serviceManager: ServiceManager,
    private val mainHandler: Handler
) {
    private val TAG = Constants.TAG + "_Ble"

    // BLE Components
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var gattServer: BluetoothGattServer? = null
    private var clientGatt: BluetoothGatt? = null // For client role

    // State
    private var isAdvertising = false
    private var isScanning = false
    private val connectedDevices = mutableMapOf<String, BluetoothDevice>() // MAC -> Device
    // Store scan results (Address -> Scan Result Map) - Use ConcurrentHashMap for thread safety
    private val discoveredDevicesMap = ConcurrentHashMap<String, Map<String, Any>>()

    // UUIDs
    private val serviceUuid: UUID = Constants.BLE_CREDENTIAL_SERVICE_UUID
    private val ssidCharacteristicUuid: UUID = Constants.BLE_SSID_CHARACTERISTIC_UUID
    private val pskCharacteristicUuid: UUID = Constants.BLE_PSK_CHARACTERISTIC_UUID

    // Event Sinks (initialized via stream handlers)
    var scanResultSink: EventChannel.EventSink? = null
    var connectionStateSink: EventChannel.EventSink? = null
    var receivedDataSink: EventChannel.EventSink? = null

    // --- Initialization and Cleanup ---

    fun initialize() {
        if (bluetoothAdapter?.isEnabled == true) {
            bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
            bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
            Log.d(TAG, "BLE components initialized. Advertiser: $bluetoothLeAdvertiser, Scanner: $bluetoothLeScanner")
        } else {
            Log.w(TAG, "Bluetooth adapter not enabled or not available, BLE components not initialized.")
        }
    }

    fun dispose() {
        Log.d(TAG, "Disposing BleManager")
        stopBleAdvertising(null) // Stop advertising if active
        stopBleScan(null) // Stop scanning if active
        closeGattServer()
        disconnectAllClients()
        // Nullify sinks to prevent further events
        scanResultSink = null
        connectionStateSink = null
        receivedDataSink = null
        discoveredDevicesMap.clear()
    }

    // --- Stream Handlers ---

    val scanResultStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            Log.d(TAG, "ScanResult Stream Listener Attached")
            scanResultSink = events
            // Optionally send the current list immediately upon listen
            sendScanResultListUpdate()
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "ScanResult Stream Listener Detached")
            scanResultSink = null
        }
    }

    val connectionStateStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            Log.d(TAG, "ConnectionState Stream Listener Attached")
            connectionStateSink = events
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "ConnectionState Stream Listener Detached")
            connectionStateSink = null
        }
    }

    val receivedDataStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            Log.d(TAG, "ReceivedData Stream Listener Attached")
            receivedDataSink = events
        }

        override fun onCancel(arguments: Any?) {
            Log.d(TAG, "ReceivedData Stream Listener Detached")
            receivedDataSink = null
        }
    }


    // --- Public Methods (Called from Plugin) ---

    fun startBleAdvertising(result: Result?, ssid: String, psk: String) {
        Log.d(TAG, "Attempting to start BLE advertising")
         if (!serviceManager.isBluetoothEnabled()) {
             Log.w(TAG, "Cannot advertise, Bluetooth is disabled.")
             result?.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled.", null)
             return
         }
        if (!hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) {
            Log.w(TAG, "Missing BLUETOOTH_ADVERTISE permission")
            result?.error("PERMISSION_DENIED", "Missing Bluetooth Advertise permission.", null)
            return
        }
        if (isAdvertising) {
            Log.w(TAG, "Advertising already active.")
            result?.success(true) // Indicate it's (already) running
            return
        }
        if (bluetoothLeAdvertiser == null) {
            bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser // Try again
            if (bluetoothLeAdvertiser == null) {
                Log.e(TAG, "BLE Advertiser is null, cannot start advertising.")
                result?.error("BLE_ERROR", "BLE Advertiser not available.", null)
                return
            }
        }

        // Setup GATT Server first to be ready for connections
        setupGattServer(ssid, psk) { success ->
            if (success) {
                val settings = AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                    .setConnectable(true) // Important: Make it connectable
                    .build()

                val data = AdvertiseData.Builder()
                    .setIncludeDeviceName(false) // Usually better not to include name for privacy/size
                    .addServiceUuid(ParcelUuid(serviceUuid)) // Advertise our custom service
                    .build()

                bluetoothLeAdvertiser?.startAdvertising(settings, data, advertiseCallback)
                Log.d(TAG, "BLE Advertising start requested.")
                result?.success(true) // Indicate request was made
                // Actual start confirmation in advertiseCallback
            } else {
                 Log.e(TAG, "Failed to setup GATT Server, cannot start advertising.")
                 result?.error("GATT_ERROR", "Failed to setup GATT server.", null)
            }
        }
    }

    fun stopBleAdvertising(result: Result?) {
        Log.d(TAG, "Attempting to stop BLE advertising")
        if (!isAdvertising) {
            Log.w(TAG, "Not currently advertising.")
            result?.success(true) // Indicate it's stopped
            return
        }
        if (!hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) {
            Log.w(TAG, "Missing BLUETOOTH_ADVERTISE permission to stop")
            // Continue attempt anyway
        }
         if (bluetoothLeAdvertiser == null) {
             Log.e(TAG, "BLE Advertiser is null, cannot stop advertising (already stopped?).")
             result?.success(true)
             return
         }

        bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        isAdvertising = false // Assume stop will succeed, callback confirms
        closeGattServer() // Close server when advertising stops
        Log.d(TAG, "BLE Advertising stop requested.")
        result?.success(true) // Indicate stop was requested
    }

    fun startBleScan(result: Result?) {
         Log.d(TAG, "Attempting to start BLE scan")
         if (!serviceManager.isBluetoothEnabled()) {
             Log.w(TAG, "Cannot scan, Bluetooth is disabled.")
             result?.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled.", null)
             return
         }
        if (!hasPermission(Manifest.permission.BLUETOOTH_SCAN)) {
            Log.w(TAG, "Missing BLUETOOTH_SCAN permission")
            result?.error("PERMISSION_DENIED", "Missing Bluetooth Scan permission.", null)
            return
        }
        if (!permissionsManager.hasP2pPermissions()) { // Assuming this checks location if needed
            Log.w(TAG, "P2P/Location permission potentially required for BLE scan might be missing.")
            // Consider if this should be an error
        }
        if (isScanning) {
            Log.w(TAG, "Scanning already active.")
            result?.success(true) // Indicate it's (already) running
            return
        }
        if (bluetoothLeScanner == null) {
            bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner // Try again
            if (bluetoothLeScanner == null) {
                Log.e(TAG, "BLE Scanner is null, cannot start scan.")
                result?.error("BLE_ERROR", "BLE Scanner not available.", null)
                return
            }
        }

        // Clear previous results when starting a new scan
        discoveredDevicesMap.clear()
        sendScanResultListUpdate() // Send empty list initially

        // Scan specifically for our service UUID
        val scanFilters = listOf(
            ScanFilter.Builder().setServiceUuid(ParcelUuid(serviceUuid)).build()
        )
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        bluetoothLeScanner?.startScan(scanFilters, scanSettings, bleScanCallback)
        isScanning = true
        Log.d(TAG, "BLE Scan started for service: $serviceUuid")
        result?.success(true)
    }

    fun stopBleScan(result: Result?) {
        Log.d(TAG, "Attempting to stop BLE scan")
        if (!isScanning) {
            Log.w(TAG, "Not currently scanning.")
            result?.success(true) // Indicate it's stopped
            return
        }
        if (!hasPermission(Manifest.permission.BLUETOOTH_SCAN)) {
            Log.w(TAG, "Missing BLUETOOTH_SCAN permission to stop")
            // Continue attempt anyway
        }
         if (bluetoothLeScanner == null) {
             Log.e(TAG, "BLE Scanner is null, cannot stop scan (already stopped?).")
              result?.success(true)
              return
         }

        bluetoothLeScanner?.stopScan(bleScanCallback)
        isScanning = false
        Log.d(TAG, "BLE Scan stop requested.")
        result?.success(true)
    }

    fun connectBleDevice(result: Result, deviceAddress: String) {
        Log.d(TAG, "Attempting to connect to BLE device: $deviceAddress")
        if (!serviceManager.isBluetoothEnabled()) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled.", null)
            return
        }
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            result.error("PERMISSION_DENIED", "Missing Bluetooth Connect permission.", null)
            return
        }
        val device = bluetoothAdapter?.getRemoteDevice(deviceAddress)
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device with address $deviceAddress not found or invalid.", null)
            return
        }

        // Disconnect previous client connection if any
        clientGatt?.close()
        clientGatt = null

        // Connect GATT client
        stopBleScan(null) // Stop scanning before connecting
        clientGatt = device.connectGatt(context, false, gattClientCallback) // autoConnect = false for direct attempt
        if(clientGatt == null){
            Log.e(TAG, "connectGatt returned null for $deviceAddress")
            result.error("CONNECTION_FAILED", "Failed to initiate GATT connection.", null)
        } else {
            Log.d(TAG, "GATT connection initiated to $deviceAddress...")
            result.success(true) // Indicate request was made
            // Connection success/failure handled asynchronously
        }
    }

    fun disconnectBleDevice(result: Result, deviceAddress: String) {
        Log.d(TAG, "Attempting to disconnect from BLE device: $deviceAddress")
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            result.error("PERMISSION_DENIED", "Missing Bluetooth Connect permission.", null)
            return
        }
        if (clientGatt == null || clientGatt?.device?.address != deviceAddress) {
            Log.w(TAG, "Not connected to device $deviceAddress or clientGatt is null.")
            result.success(true) // Indicate it's already disconnected or wasn't connected
            return
        }

        clientGatt?.disconnect()
        // Close is handled in the onConnectionStateChange callback after disconnect event
        Log.d(TAG, "GATT disconnect requested for $deviceAddress")
        result.success(true) // Indicate disconnect was requested
    }

    // --- Helper Methods ---

    private fun hasPermission(permission: String): Boolean {
        // Simplified check relying on PermissionsManager for complex logic if needed elsewhere
        // This is basic check, assumes PermissionsManager handles the API level differences
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun setupGattServer(ssid: String, psk: String, callback: (Boolean) -> Unit) {
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            Log.e(TAG, "Missing BLUETOOTH_CONNECT permission for GATT server.")
            callback(false)
            return
        }
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
        if (bluetoothManager == null) {
            Log.e(TAG, "BluetoothManager not available")
            callback(false)
            return
        }

        closeGattServer() // Close existing server if any

        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        if (gattServer == null) {
            Log.e(TAG, "Unable to open GATT server.")
            callback(false)
            return
        }

        // Define Service
        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        // Define SSID Characteristic
        val ssidCharacteristic = BluetoothGattCharacteristic(
            ssidCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ, // Client can read
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED_MITM // Require bonding/encryption
        )
        ssidCharacteristic.value = ssid.toByteArray(Charsets.UTF_8) // Set initial value

        // Define PSK Characteristic
        val pskCharacteristic = BluetoothGattCharacteristic(
            pskCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ, // Client can read
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED_MITM // Require bonding/encryption
        )
        pskCharacteristic.value = psk.toByteArray(Charsets.UTF_8) // Set initial value


        // Add characteristics to service
        service.addCharacteristic(ssidCharacteristic)
        service.addCharacteristic(pskCharacteristic)

        // Add service to server
        val serviceAdded = gattServer?.addService(service) ?: false
        if (serviceAdded) {
            Log.d(TAG, "GATT Server setup successful, service added.")
            callback(true)
        } else {
            Log.e(TAG, "Failed to add service to GATT server.")
            closeGattServer()
            callback(false)
        }
    }

    private fun closeGattServer() {
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to close GATT server.")
            // Attempt closing anyway
        }
        if (gattServer != null) {
            try {
            gattServer?.close()
            } catch (e: Exception) {
                Log.e(TAG,"Error closing GATT server: ${e.message}")
            }
            gattServer = null
            connectedDevices.clear()
            Log.d(TAG, "GATT Server closed.")
        }
    }

    private fun disconnectAllClients() {
        if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to disconnect clients.")
            return
        }
        val devicesToDisconnect = ArrayList(connectedDevices.values) // Copy to avoid concurrent modification
        Log.d(TAG, "Disconnecting ${devicesToDisconnect.size} connected GATT clients.")
        devicesToDisconnect.forEach { device ->
            gattServer?.cancelConnection(device)
        }
        connectedDevices.clear() // Clear map after requesting cancellation

        // Also close client-side connection if active
        if(clientGatt != null) {
            clientGatt?.disconnect()
            // close is handled in callback
        }
    }

    private fun sendConnectionStateUpdate(device: BluetoothDevice, isConnected: Boolean) {
        mainHandler.post {
            val stateMap = mapOf(
                "deviceAddress" to device.address,
                // Check permission before accessing name on S+
                "deviceName" to if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) (device.name ?: "Unknown") else "Unknown",
                "isConnected" to isConnected
            )
            try {
                connectionStateSink?.success(stateMap)
                Log.d(TAG, "Sent connection state update: ${device.address} -> $isConnected")
            } catch (e: Exception) {
                 Log.e(TAG, "Error sending connection state update: ${e.message}", e)
            }
        }
    }

    // New method to send the entire list of discovered devices
    private fun sendScanResultListUpdate() {
        mainHandler.post {
            val resultsList = ArrayList(discoveredDevicesMap.values)
            try {
                scanResultSink?.success(resultsList)
                Log.d(TAG, "Sent scan result list update. Count: ${resultsList.size}")
            } catch (e: Exception) {
                 Log.e(TAG, "Error sending scan result list update: ${e.message}", e)
            }
        }
    }

    private fun sendReceivedDataUpdate(device: BluetoothDevice, characteristicUuid: UUID, data: ByteArray) {
        mainHandler.post {
            val dataMap = mapOf(
                "deviceAddress" to device.address,
                "characteristicUuid" to characteristicUuid.toString(),
                "data" to data // Send as byte array (Uint8List in Flutter)
            )
             try {
                receivedDataSink?.success(dataMap)
                Log.d(TAG, "Sent received data update: ${device.address} / $characteristicUuid")
            } catch (e: Exception) {
                 Log.e(TAG, "Error sending received data update: ${e.message}", e)
            }
        }
    }

    // --- Callbacks ---

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            isAdvertising = true
            Log.i(TAG, "BLE Advertising Started Successfully.")
        }

        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            isAdvertising = false
            val reason = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data Too Large"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too Many Advertisers"
                ADVERTISE_FAILED_ALREADY_STARTED -> "Already Started"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal Error"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature Unsupported"
                else -> "Unknown Error ($errorCode)"
            }
            Log.e(TAG, "BLE Advertising Failed: $reason")
            closeGattServer() // Ensure server is closed if advertising failed
        }
    }

    private val bleScanCallback = object : ScanCallback() {
        // No longer need foundDevices set here, use discoveredDevicesMap

        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            result?.device?.let { device ->
                 if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) { // Needed for name/address access on S+
                    val deviceAddress = device.address
                    val deviceName = device.name ?: "Unknown"
                    val rssi = result.rssi

                    val resultMap = mapOf(
                        "deviceAddress" to deviceAddress,
                        "deviceName" to deviceName,
                        "rssi" to rssi
                    )

                    // Add or update the device in the map
                    val updated = discoveredDevicesMap.put(deviceAddress, resultMap) != resultMap
                    if(updated) {
                        Log.d(TAG,"BLE Device Found/Updated: $deviceAddress ($deviceName)")
                        // Send the updated list to Flutter
                        sendScanResultListUpdate()
                    } else {
                        // Skip, not updated
                    }

                 } else {
                      Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to process scan result on Android 12+")
                 }
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            super.onBatchScanResults(results)
            var listChanged = false
             results?.forEach { result ->
                 result.device?.let { device ->
                    if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                        val deviceAddress = device.address
                        val deviceName = device.name ?: "Unknown"
                        val rssi = result.rssi

                         val resultMap = mapOf(
                            "deviceAddress" to deviceAddress,
                            "deviceName" to deviceName,
                            "rssi" to rssi
                         )

                         if (discoveredDevicesMap.put(deviceAddress, resultMap) != resultMap) {
                            listChanged = true
                             Log.d(TAG,"BLE Device Found/Updated (Batch): $deviceAddress ($deviceName) RSSI: $rssi")
                         }
                    } else {
                        Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to process batch scan result on Android 12+")
                    }
                }
            }
            // If any device in the batch caused a change, send the full list
            if (listChanged) {
                sendScanResultListUpdate()
            }
        }

        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            isScanning = false
            Log.e(TAG, "BLE Scan Failed: $errorCode")
            mainHandler.post {
                 try {
                     scanResultSink?.error("SCAN_FAILED", "BLE Scan Failed: $errorCode", null)
                 } catch (e: Exception) {
                     Log.e(TAG, "Error sending scan failed event: ${e.message}", e)
                 }
            }
        }

        // No longer need resetFoundDevices
    }


    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
             if (device == null) return

             val deviceAddress = device.address
             val deviceName = if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) device.name ?: "Unknown" else "Protected"

            if (status == BluetoothGatt.GATT_SUCCESS) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.i(TAG, "GATT Server: Device Connected - $deviceName ($deviceAddress)")
                        connectedDevices[deviceAddress] = device
                        sendConnectionStateUpdate(device, true)
                        if(device.bondState == BluetoothDevice.BOND_NONE) {
                            Log.d(TAG, "Requesting bond with $deviceAddress")
                            // Check permission before createBond
                            if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                                device.createBond()
                            } else {
                                Log.e(TAG, "Missing BLUETOOTH_CONNECT permission to create bond.")
                                // Handle situation - perhaps disconnect?
                            }
                        }
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.i(TAG, "GATT Server: Device Disconnected - $deviceName ($deviceAddress)")
                        connectedDevices.remove(deviceAddress)
                        sendConnectionStateUpdate(device, false)
                    }
                }
            } else {
                 Log.e(TAG,"GATT Server: Connection state change error for $deviceName ($deviceAddress). Status: $status, NewState: $newState")
                 connectedDevices.remove(deviceAddress) // Remove if connection failed or errored out
                 sendConnectionStateUpdate(device, false) // Report disconnection on error
            }
        }

        override fun onCharacteristicReadRequest(device: BluetoothDevice?, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic?) {
            super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
            if (device == null || characteristic == null || gattServer == null) {
                 gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH, offset, null)
                 return
            }
             val deviceAddress = device.address
             val charUuid = characteristic.uuid

             Log.d(TAG,"GATT Server: Read request for Characteristic $charUuid from $deviceAddress (Offset: $offset)")

              if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                  Log.e(TAG, "Missing BLUETOOTH_CONNECT permission for GATT server read response.")
                  gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null)
                  return
              }

            // Check if the requested characteristic is one of ours
            if (charUuid == ssidCharacteristicUuid || charUuid == pskCharacteristicUuid) {
                 if (device.bondState != BluetoothDevice.BOND_BONDED) {
                     Log.w(TAG, "GATT Server: Denying read request for $charUuid from unbonded device $deviceAddress")
                     gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null)
                     return
                 }

                // Respond with the characteristic's current value
                val value = characteristic.value
                 val responseValue = if (value != null && offset < value.size) {
                     value.copyOfRange(offset, value.size)
                 } else {
                     byteArrayOf() // Send empty array if offset invalid or value null
                 }

                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, responseValue)
                Log.d(TAG, "GATT Server: Sent response for $charUuid to $deviceAddress")
            } else {
                Log.w(TAG, "GATT Server: Read request for unknown/unreadable characteristic $charUuid from $deviceAddress")
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_READ_NOT_PERMITTED, offset, null)
            }
        }

         override fun onCharacteristicWriteRequest(device: BluetoothDevice?, requestId: Int, characteristic: BluetoothGattCharacteristic?, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?) {
             super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
             Log.w(TAG, "GATT Server: Received unexpected write request for ${characteristic?.uuid} from ${device?.address}. Denying.")
             if (responseNeeded && device != null && gattServer != null) {
                if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                     gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_WRITE_NOT_PERMITTED, offset, null)
                }
             }
         }

         override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            super.onServiceAdded(status, service)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "GATT Server: Service ${service?.uuid} added successfully.")
            } else {
                Log.e(TAG, "GATT Server: Failed to add service ${service?.uuid}, status: $status")
                 closeGattServer() // Clean up if service add fails
            }
        }
    }


    private val gattClientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            val device = gatt?.device ?: return
            val deviceAddress = device.address
            val deviceName = if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) device.name ?: "Unknown" else "Protected"

            if (status == BluetoothGatt.GATT_SUCCESS) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.i(TAG, "GATT Client: Connected to $deviceName ($deviceAddress)")
                        clientGatt = gatt // Store the connected gatt instance
                        sendConnectionStateUpdate(device, true)
                        if (hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                            Log.d(TAG, "GATT Client: Discovering services for $deviceAddress...")
                            if (!gatt.discoverServices()) {
                                Log.e(TAG,"GATT Client: Failed to initiate service discovery for $deviceAddress")
                                gatt.disconnect()
                            }
                        } else {
                            Log.e(TAG, "Missing BLUETOOTH_CONNECT to discover services. Disconnecting.")
                            gatt.disconnect()
                        }
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.i(TAG, "GATT Client: Disconnected from $deviceName ($deviceAddress)")
                        sendConnectionStateUpdate(device, false)
                        gatt.close() // Close GATT client resources after disconnection
                        if (clientGatt == gatt) { // Ensure we only nullify if it's the current one
                            clientGatt = null
                        }
                    }
                }
            } else {
                Log.e(TAG,"GATT Client: Connection state error for $deviceName ($deviceAddress). Status: $status, NewState: $newState")
                sendConnectionStateUpdate(device, false) // Report disconnect on error
                gatt.close()
                if (clientGatt == gatt) {
                    clientGatt = null
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            val device = gatt?.device ?: return
            val deviceAddress = device.address
            Log.d(TAG, "GATT Client: Services discovered for $deviceAddress with status $status")

            if (status == BluetoothGatt.GATT_SUCCESS) {
                val credentialService = gatt.getService(serviceUuid)
                if (credentialService == null) {
                    Log.e(TAG, "GATT Client: Credential service ($serviceUuid) not found on $deviceAddress.")
                    gatt.disconnect() // Disconnect if service not found
                    return
                }

                val ssidChar = credentialService.getCharacteristic(ssidCharacteristicUuid)
                val pskChar = credentialService.getCharacteristic(pskCharacteristicUuid)

                if (ssidChar != null && pskChar != null) {
                    Log.d(TAG, "GATT Client: Found SSID and PSK characteristics. Reading SSID...")
                    if (!gatt.readCharacteristic(ssidChar)) {
                        Log.e(TAG, "GATT Client: Failed to initiate read for SSID characteristic.")
                        gatt.disconnect()
                    }
                } else {
                    Log.e(TAG, "GATT Client: SSID ($ssidCharacteristicUuid) or PSK ($pskCharacteristicUuid) characteristic not found.")
                    gatt.disconnect()
                }
            } else {
                Log.w(TAG, "GATT Client: Service discovery failed for $deviceAddress with status $status")
                gatt.disconnect()
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray, // New value Tiramisu+
            status: Int
        ) {
            val device = gatt.device ?: return
            val charUuid = characteristic.uuid

            Log.d(TAG, "GATT Client: Read char $charUuid status $status")
            if (status == BluetoothGatt.GATT_SUCCESS) {
                sendReceivedDataUpdate(device, charUuid, value) // Send raw data to Flutter

                if (charUuid == ssidCharacteristicUuid) {
                    Log.d(TAG, "GATT Client: Read SSID successful. Reading PSK...")
                    val pskChar = gatt.getService(serviceUuid)?.getCharacteristic(pskCharacteristicUuid)
                    if (pskChar != null) {
                        if (!gatt.readCharacteristic(pskChar)) {
                            Log.e(TAG, "GATT Client: Failed to initiate read for PSK characteristic.")
                            gatt.disconnect()
                        }
                    } else {
                        Log.e(TAG, "GATT Client: PSK characteristic not found after reading SSID.")
                        gatt.disconnect()
                    }
                } else if (charUuid == pskCharacteristicUuid) {
                    Log.i(TAG, "GATT Client: Read PSK successful. Credentials received.")
                    // Optional: Automatically disconnect after reading PSK?
                    gatt.disconnect()
                }

            } else {
                Log.e(TAG, "GATT Client: Characteristic read failed for $charUuid with status $status")
                gatt.disconnect() // Disconnect on read failure
            }
        }

        @Deprecated("Use onCharacteristicRead with ByteArray value instead")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt?,
            characteristic: BluetoothGattCharacteristic?,
            status: Int
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                if (characteristic != null && gatt != null) {
                    // Use characteristic.value for legacy callback data
                    onCharacteristicRead(gatt, characteristic, characteristic.value ?: byteArrayOf(), status)
                }
            }
        }
    }

}