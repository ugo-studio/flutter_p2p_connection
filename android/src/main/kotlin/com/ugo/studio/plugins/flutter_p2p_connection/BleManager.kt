package com.ugo.studio.plugins.flutter_p2p_connection

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private val discoveredDevicesMap = ConcurrentHashMap<String, Map<String, Any>>()
    private var connectingDeviceAddress: String? = null // To track device for bonding

    // UUIDs
    private val serviceUuid: UUID = Constants.BLE_CREDENTIAL_SERVICE_UUID
    private val ssidCharacteristicUuid: UUID = Constants.BLE_SSID_CHARACTERISTIC_UUID
    private val pskCharacteristicUuid: UUID = Constants.BLE_PSK_CHARACTERISTIC_UUID

    // Event Sinks
    var scanResultSink: EventChannel.EventSink? = null
    var connectionStateSink: EventChannel.EventSink? = null
    var receivedDataSink: EventChannel.EventSink? = null


    private val bondStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            if (BluetoothDevice.ACTION_BOND_STATE_CHANGED == action) {
                val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                val previousBondState = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.ERROR)

                if (device?.address == connectingDeviceAddress) {
                    Log.d(TAG, "Bond state changed for ${device?.address}: ${bondStateToString(previousBondState)} -> ${bondStateToString(bondState)}")
                    when (bondState) {
                        BluetoothDevice.BOND_BONDED -> {
                            Log.i(TAG, "Device ${device?.address} bonded. Discovering services.")
                            // Ensure clientGatt is still valid and connected to this device
                            if (clientGatt != null && clientGatt?.device?.address == device?.address) {
                                mainHandler.post { // Ensure GATT operations on main thread if required by stack, or on GATT callback thread
                                   if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                                       if (clientGatt?.discoverServices() == false) {
                                           Log.e(TAG,"GATT Client: Failed to initiate service discovery post-bonding for ${device?.address}")
                                           clientGatt?.disconnect()
                                       }
                                   } else {
                                        Log.e(TAG, "Missing BLUETOOTH_CONNECT to discover services post-bonding. Disconnecting.")
                                        clientGatt?.disconnect()
                                   }
                                }
                            } else {
                                Log.w(TAG, "clientGatt is null or for a different device. Cannot discover services for ${device?.address}")
                            }
                            // Unregister here as bonding for this attempt is complete (success)
                            // unregisterBondStateReceiver() // Or manage unregistration more globally if needed
                        }
                        BluetoothDevice.BOND_NONE -> {
                            Log.w(TAG, "Device ${device?.address} bonding failed or removed.")
                            // Handle bonding failure, perhaps disconnect
                            clientGatt?.disconnect()
                            // Unregister here as bonding for this attempt is complete (failure)
                            // unregisterBondStateReceiver()
                        }
                        BluetoothDevice.BOND_BONDING -> {
                            Log.d(TAG, "Device ${device?.address} is bonding...")
                        }
                    }
                }
            }
        }
    }

    private fun bondStateToString(bondState: Int): String {
        return when (bondState) {
            BluetoothDevice.BOND_NONE -> "BOND_NONE"
            BluetoothDevice.BOND_BONDING -> "BOND_BONDING"
            BluetoothDevice.BOND_BONDED -> "BOND_BONDED"
            BluetoothDevice.ERROR -> "ERROR"
            else -> "UNKNOWN ($bondState)"
        }
    }

    private fun registerBondStateReceiver() {
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        try {
            context.registerReceiver(bondStateReceiver, filter)
            Log.d(TAG, "Bond state receiver registered.")
        } catch (e: Exception) {
            Log.e(TAG, "Error registering bond state receiver: ${e.message}", e)
        }
    }

    private fun unregisterBondStateReceiver() {
        try {
            context.unregisterReceiver(bondStateReceiver)
            Log.d(TAG, "Bond state receiver unregistered.")
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Bond state receiver not registered or already unregistered.")
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering bond state receiver: ${e.message}", e)
        }
    }


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
        stopBleAdvertising(null)
        stopBleScan(null)
        closeGattServer()
        disconnectAllClients() // This will also handle unregistering bond receiver if clientGatt is active
        unregisterBondStateReceiver() // Ensure it's unregistered if no active clientGatt
        connectingDeviceAddress = null
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) {
            Log.w(TAG, "Missing BLUETOOTH_ADVERTISE permission")
            result?.error("PERMISSION_DENIED", "Missing Bluetooth Advertise permission.", null)
            return
        }
        if (isAdvertising) {
            Log.w(TAG, "Advertising already active.")
            result?.success(true)
            return
        }
        if (bluetoothLeAdvertiser == null) {
            bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            if (bluetoothLeAdvertiser == null) {
                Log.e(TAG, "BLE Advertiser is null, cannot start advertising.")
                result?.error("BLE_ERROR", "BLE Advertiser not available.", null)
                return
            }
        }

        setupGattServer(ssid, psk) { success ->
            if (success) {
                val settings = AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                    .setConnectable(true)
                    .build()

                val advertiseData = AdvertiseData.Builder()
                    .setIncludeDeviceName(false)
                    .addServiceUuid(ParcelUuid(serviceUuid))
                    .build()

                val scanResponseData = AdvertiseData.Builder()
                    .setIncludeDeviceName(true)
                    .build()

                bluetoothLeAdvertiser?.startAdvertising(settings, advertiseData, scanResponseData, advertiseCallback)
                Log.d(TAG, "BLE Advertising start requested.")
                result?.success(true)
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
            result?.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) {
            Log.w(TAG, "Missing BLUETOOTH_ADVERTISE permission to stop")
        }
        if (bluetoothLeAdvertiser == null) {
            Log.e(TAG, "BLE Advertiser is null, cannot stop advertising (already stopped?).")
            result?.success(true)
            return
        }

        bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        isAdvertising = false
        closeGattServer()
        Log.d(TAG, "BLE Advertising stop requested.")
        result?.success(true)
    }

    fun startBleScan(result: Result?) {
         Log.d(TAG, "Attempting to start BLE scan")
         if (!serviceManager.isBluetoothEnabled()) {
             Log.w(TAG, "Cannot scan, Bluetooth is disabled.")
             result?.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled.", null)
             return
         }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_SCAN)) {
            Log.w(TAG, "Missing BLUETOOTH_SCAN permission")
            result?.error("PERMISSION_DENIED", "Missing Bluetooth Scan permission.", null)
            return
        }
        if (!permissionsManager.hasP2pPermissions()) {
            Log.w(TAG, "P2P/Location permission potentially required for BLE scan might be missing.")
        }
        if (isScanning) {
            Log.w(TAG, "Scanning already active.")
            result?.success(true)
            return
        }
        if (bluetoothLeScanner == null) {
            bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
            if (bluetoothLeScanner == null) {
                Log.e(TAG, "BLE Scanner is null, cannot start scan.")
                result?.error("BLE_ERROR", "BLE Scanner not available.", null)
                return
            }
        }

        discoveredDevicesMap.clear()
        sendScanResultListUpdate()

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
            result?.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_SCAN)) {
            Log.w(TAG, "Missing BLUETOOTH_SCAN permission to stop")
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            result.error("PERMISSION_DENIED", "Missing Bluetooth Connect permission.", null)
            return
        }
        val device = bluetoothAdapter?.getRemoteDevice(deviceAddress)
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device with address $deviceAddress not found or invalid.", null)
            return
        }

        clientGatt?.close() // Close any existing client connection
        clientGatt = null
        connectingDeviceAddress = deviceAddress // Set before connecting
        registerBondStateReceiver() // Register to listen for bond changes for this device

        stopBleScan(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            clientGatt = device.connectGatt(context, false, gattClientCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            clientGatt = device.connectGatt(context, false, gattClientCallback)
        }
        if(clientGatt == null){
            Log.e(TAG, "connectGatt returned null for $deviceAddress")
            connectingDeviceAddress = null // Clear if connection init failed
            unregisterBondStateReceiver() // Unregister if connection init failed
            result.error("CONNECTION_FAILED", "Failed to initiate GATT connection.", null)
        } else {
            Log.d(TAG, "GATT connection initiated to $deviceAddress...")
            result.success(true)
        }
    }

    fun disconnectBleDevice(result: Result, deviceAddress: String) {
        Log.d(TAG, "Attempting to disconnect from BLE device: $deviceAddress")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            result.error("PERMISSION_DENIED", "Missing Bluetooth Connect permission.", null)
            return
        }
        if (clientGatt == null || clientGatt?.device?.address != deviceAddress) {
            Log.w(TAG, "Not connected to device $deviceAddress or clientGatt is null.")
            if (connectingDeviceAddress == deviceAddress) { // If we were trying to connect to this
                connectingDeviceAddress = null
                unregisterBondStateReceiver()
            }
            result.success(true)
            return
        }

        clientGatt?.disconnect() // Disconnection and close handled in gattClientCallback
        // connectingDeviceAddress will be cleared and receiver unregistered in callback or if it was this device
        if (connectingDeviceAddress == deviceAddress) {
             // It will be cleared in callback, but for safety if callback is missed for some reason for this specific call
             // connectingDeviceAddress = null;
             // unregisterBondStateReceiver(); // this is handled in gattClientCallback's disconnect path
        }
        Log.d(TAG, "GATT disconnect requested for $deviceAddress")
        result.success(true)
    }

    // --- Helper Methods ---

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun setupGattServer(ssid: String, psk: String, callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
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

        closeGattServer()

        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        if (gattServer == null) {
            Log.e(TAG, "Unable to open GATT server.")
            callback(false)
            return
        }

        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val ssidCharacteristic = BluetoothGattCharacteristic(
            ssidCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
        )
        ssidCharacteristic.value = ssid.toByteArray(Charsets.UTF_8)
        val pskCharacteristic = BluetoothGattCharacteristic(
            pskCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
        )
        pskCharacteristic.value = psk.toByteArray(Charsets.UTF_8)

        service.addCharacteristic(ssidCharacteristic)
        service.addCharacteristic(pskCharacteristic)

        val serviceAdded = gattServer?.addService(service) ?: false
        if (serviceAdded) {
            Log.d(TAG, "GATT Server setup successful, service added($serviceUuid).")
            callback(true)
        } else {
            Log.e(TAG, "Failed to add service($serviceUuid) to GATT server.")
            closeGattServer()
            callback(false)
        }
    }

    private fun closeGattServer() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to close GATT server.")
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to disconnect clients.")
            return
        }
        val devicesToDisconnect = ArrayList(connectedDevices.values)
        Log.d(TAG, "Disconnecting ${devicesToDisconnect.size} connected GATT clients.")
        devicesToDisconnect.forEach { device ->
            gattServer?.cancelConnection(device)
        }
        connectedDevices.clear()

        if(clientGatt != null) {
            clientGatt?.disconnect() // Actual close in callback
            // clientGatt = null; // Nullified in callback
            // connectingDeviceAddress = null; // Nullified in callback
            // unregisterBondStateReceiver(); // Unregistered in callback
        }
    }

    private fun sendConnectionStateUpdate(device: BluetoothDevice, isConnected: Boolean) {
        mainHandler.post {
            val canAccessName = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
            val deviceName = if (canAccessName) device.name ?: "unknown" else "Protected"
            val deviceAddress = device.address

            val stateMap = mapOf(
                "deviceAddress" to deviceAddress,
                "deviceName" to deviceName,
                "isConnected" to isConnected
            )
            try {
                connectionStateSink?.success(stateMap)
                Log.d(TAG, "Sent connection state update: ${deviceAddress} -> $isConnected")
            } catch (e: Exception) {
                 Log.e(TAG, "Error sending connection state update: ${e.message}", e)
            }
        }
    }

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
                "data" to data
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
            closeGattServer()
        }
    }

    private val bleScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            result?.device?.let { device ->
                val canAccessName = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
                if (canAccessName) {
                    val deviceAddress = device.address
                    val deviceName = if (canAccessName) device.name ?: "Unknown" else "Protected"

                    val resultMap = mapOf(
                        "deviceAddress" to deviceAddress,
                        "deviceName" to deviceName,
                    )
                    val updated = discoveredDevicesMap.put(deviceAddress, resultMap) != resultMap
                    if (updated) {
                        Log.d(TAG,"BLE Device Found/Updated: $deviceAddress ($deviceName) RSSI: ${result.rssi}")
                        sendScanResultListUpdate()
                    } else {
                        // 'if' must have both main and 'else' branches if used as an expression
                    }
                } else {
                    Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to get name for scan result on Android 12+")
                }
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            super.onBatchScanResults(results)
            var listChanged = false
             results?.forEach { result ->
                 result.device?.let { device ->
                    val canAccessName = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
                    if (canAccessName) {
                        val deviceAddress = device.address
                        val deviceName = if (canAccessName) device.name ?: "Unknown" else "Protected"

                        val resultMap = mapOf(
                        "deviceAddress" to deviceAddress,
                        "deviceName" to deviceName,
                        )
                        if (discoveredDevicesMap.put(deviceAddress, resultMap) != resultMap) {
                            listChanged = true
                            Log.d(TAG,"BLE Device Found/Updated (Batch): $deviceAddress ($deviceName) RSSI: ${result.rssi}")
                        }
                    } else {
                        Log.w(TAG, "Missing BLUETOOTH_CONNECT permission to get name for batch scan result on Android 12+")
                    }
                }
            }
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
    }


    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            if (device == null) return

            val canAccessName = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
            val deviceName = if (canAccessName) device.name ?: "Unknown" else "Protected"
            val deviceAddress = device.address

            if (status == BluetoothGatt.GATT_SUCCESS) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.i(TAG, "GATT Server: Device Connected - $deviceName ($deviceAddress)")
                        connectedDevices[deviceAddress] = device
                        sendConnectionStateUpdate(device, true)
                        // Server requests bond if device is not bonded
                        if(device.bondState == BluetoothDevice.BOND_NONE) {
                            Log.d(TAG, "GATT Server: Requesting bond with $deviceAddress. Current bond state: ${bondStateToString(device.bondState)}")
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                                if (device.createBond()) {
                                    Log.d(TAG, "GATT Server: createBond initiated for $deviceAddress")
                                } else {
                                    Log.e(TAG, "GATT Server: createBond failed for $deviceAddress")
                                }
                            } else {
                                Log.e(TAG, "Missing BLUETOOTH_CONNECT permission to create bond on server side.")
                            }
                        } else {
                             Log.d(TAG, "GATT Server: Device $deviceAddress already bonded or bonding. State: ${bondStateToString(device.bondState)}")
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
                connectedDevices.remove(deviceAddress)
                sendConnectionStateUpdate(device, false)
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
            val currentBondStateOnServer = device.bondState // Get current bond state
            Log.d(TAG, "GATT Server: Read request for Characteristic $charUuid from $deviceAddress (Offset: $offset, BondState: ${bondStateToString(currentBondStateOnServer)})")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                Log.e(TAG, "Missing BLUETOOTH_CONNECT permission for GATT server read response.")
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null)
                return
            }

            if (charUuid == ssidCharacteristicUuid || charUuid == pskCharacteristicUuid) {
                if (currentBondStateOnServer != BluetoothDevice.BOND_BONDED) {
                    Log.w(TAG, "GATT Server: Denying read for $charUuid from $deviceAddress due to insufficient auth. BondState: ${bondStateToString(currentBondStateOnServer)}, Client probably expected BONDED.")
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null)
                    return
                }
                val value = characteristic.value
                val responseValue = if (value != null && offset < value.size) {
                    value.copyOfRange(offset, value.size)
                } else {
                    byteArrayOf()
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
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
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
                closeGattServer()
            }
        }
    }


    private val gattClientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            val device = gatt?.device ?: return
            val deviceAddress = device.address

            val canAccessName = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
            val deviceName = if (canAccessName) device.name ?: "Unknown" else "Protected"

            if (status == BluetoothGatt.GATT_SUCCESS) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.i(TAG, "GATT Client: Connected to $deviceName ($deviceAddress). Current bond state: ${bondStateToString(device.bondState)}")
                        clientGatt = gatt
                        sendConnectionStateUpdate(device, true)

                        if (device.bondState == BluetoothDevice.BOND_BONDED) {
                            Log.d(TAG, "GATT Client: Device already bonded. Discovering services for $deviceAddress...")
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                                if (!gatt.discoverServices()) {
                                    Log.e(TAG,"GATT Client: Failed to initiate service discovery for $deviceAddress")
                                    gatt.disconnect()
                                }
                            } else {
                                Log.e(TAG, "Missing BLUETOOTH_CONNECT to discover services. Disconnecting.")
                                gatt.disconnect()
                            }
                        } else {
                            // Server will initiate bond if device.bondState == BluetoothDevice.BOND_NONE.
                            // Client (this code) should have already registered bondStateReceiver.
                            // Service discovery will be triggered by the bondStateReceiver when BOND_BONDED.
                            Log.i(TAG, "GATT Client: Device not bonded ($deviceAddress). Waiting for bonding process to complete. Bond state: ${bondStateToString(device.bondState)}")
                            if (device.bondState == BluetoothDevice.BOND_NONE) {
                                // Optionally, client can also initiate bonding if server doesn't.
                                // However, in this setup, the server is expected to initiate.
                                // Log.d(TAG, "GATT Client: Device is BOND_NONE. Server should initiate. Client can also try: device.createBond()")
                                // if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                                //    device.createBond()
                                // }
                            }
                        }
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.i(TAG, "GATT Client: Disconnected from $deviceName ($deviceAddress)")
                        sendConnectionStateUpdate(device, false)
                        if (device.address == connectingDeviceAddress) {
                            unregisterBondStateReceiver()
                            connectingDeviceAddress = null
                        }
                        gatt.close()
                        if (clientGatt == gatt) {
                            clientGatt = null
                        }
                    }
                }
            } else {
                Log.e(TAG,"GATT Client: Connection state error for $deviceName ($deviceAddress). Status: $status, NewState: $newState")
                sendConnectionStateUpdate(device, false)
                if (device.address == connectingDeviceAddress) {
                    unregisterBondStateReceiver()
                    connectingDeviceAddress = null
                }
                gatt.close()
                if (clientGatt == gatt) {
                    clientGatt = null
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            val device = gatt?.device ?: return
            val deviceAddress = device.address
            Log.d(TAG, "GATT Client: Services discovered for $deviceAddress with status: $status. Bond state: ${bondStateToString(device.bondState)}")

            if (status == BluetoothGatt.GATT_SUCCESS) {
                // Unregister receiver here as successful discovery (implies bonding succeeded earlier)
                if (device.address == connectingDeviceAddress) {
                    // unregisterBondStateReceiver() // Keep it registered until disconnection for subsequent bond changes if any, or unregister earlier.
                    // For this specific flow, if services are discovered, bonding was successful.
                    // Let's unregister it when the "connectingDeviceAddress" is cleared on disconnect.
                }

                Log.d(TAG, "Listing all discovered services for $deviceAddress:")
                gatt.services?.forEachIndexed { index, service ->
                    Log.d(TAG, "  Service [${index}]: ${service.uuid}")
                    service.characteristics?.forEachIndexed { charIndex, characteristic ->
                        Log.d(TAG, "    Characteristic [${charIndex}]: ${characteristic.uuid}")
                    }
                }

                Log.d(TAG, "Attempting to get service: '$serviceUuid'")
                val credentialService = gatt.getService(serviceUuid)
                if (credentialService == null) {
                    Log.e(TAG, "GATT Client: Credential service ($serviceUuid) not found on $deviceAddress.")
                    gatt.disconnect()
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
                    val notFound = mutableListOf<String>()
                    if (ssidChar == null) notFound.add("SSID ($ssidCharacteristicUuid)")
                    if (pskChar == null) notFound.add("PSK ($pskCharacteristicUuid)")
                    Log.e(TAG, "GATT Client: Following characteristics not found: ${notFound.joinToString()}. Service has ${credentialService.characteristics.size} characteristics.")
                    credentialService.characteristics.forEach { Log.d(TAG, "  Available char: ${it.uuid}") }
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
            value: ByteArray,
            status: Int
        ) {
            val device = gatt.device ?: return
            val charUuid = characteristic.uuid

            Log.d(TAG, "GATT Client: Read char $charUuid status $status. Current bond state: ${bondStateToString(device.bondState)}")
            if (status == BluetoothGatt.GATT_SUCCESS) {
                sendReceivedDataUpdate(device, charUuid, value)

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
                    gatt.disconnect() // Disconnect after reading both characteristics
                }
            } else if (status == BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION && device.bondState == BluetoothDevice.BOND_BONDED) {
                Log.w(TAG, "GATT Client: Read failed with GATT_INSUFFICIENT_AUTHENTICATION for $charUuid even though client sees bonded. Consider a retry or re-pairing if persistent.")
                // OPTIONALLY: Implement a single retry mechanism here after a short delay.
                // For example:
                // if (!characteristic.getBooleanExtra("read_retried", false)) { // Crude way to mark retry
                //    Log.d(TAG, "Retrying read for $charUuid after a short delay.");
                //    characteristic.putExtra("read_retried", true); // Mark it
                //    mainHandler.postDelayed({
                //        if (clientGatt == gatt && gatt.device.address == device.address) { // Still connected to same device
                //            gatt.readCharacteristic(characteristic)
                //        }
                //    }, 300) // 300ms delay
                //    return // Don't disconnect yet
                // }
                gatt.disconnect() // If retry is not implemented or fails, disconnect
            } else {
                Log.e(TAG, "GATT Client: Characteristic read failed for $charUuid with status $status. Bond state: ${bondStateToString(device.bondState)}")
                gatt.disconnect()
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
                    onCharacteristicRead(gatt, characteristic, characteristic.value ?: byteArrayOf(), status)
                }
            }
        }
    }
}