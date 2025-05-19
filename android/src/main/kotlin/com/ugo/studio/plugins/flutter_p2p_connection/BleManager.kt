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

    // Configuration properties
    private var bondingRequired: Boolean = false
    private var encryptionRequired: Boolean = false

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
    private var serviceUuid: UUID = Constants.BLE_CREDENTIAL_SERVICE_UUID
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
                            if (clientGatt != null && clientGatt?.device?.address == device?.address) {
                                mainHandler.post {
                                   discoverServices(clientGatt!!) // Ensure clientGatt is not null here
                                }
                            } else {
                                Log.w(TAG, "clientGatt is null or for a different device after bonding. Cannot discover services for ${device?.address}")
                            }
                        }
                        BluetoothDevice.BOND_NONE -> {
                            Log.w(TAG, "Device ${device?.address} bonding failed or removed.")
                            clientGatt?.disconnect()
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

    fun initialize(serviceUuid: String? = null, bondingRequired: Boolean? = null, encryptionRequired: Boolean? = null) {
        // Update configuration if new values are provided
        serviceUuid?.let { this.serviceUuid = UUID.fromString(it) }
        bondingRequired?.let { this.bondingRequired = it }
        encryptionRequired?.let { this.encryptionRequired = it }

        if (bluetoothAdapter?.isEnabled == true) {
            bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
            bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
            Log.d(TAG, "BLE components initialized. Advertiser: $bluetoothLeAdvertiser, Scanner: $bluetoothLeScanner. BondingRequired: ${this.bondingRequired}, EncryptionRequired: ${this.encryptionRequired}")
        } else {
            Log.w(TAG, "Bluetooth adapter not enabled or not available, BLE components not initialized.")
        }
    }

    fun dispose() {
        Log.d(TAG, "Disposing BleManager")
        stopBleAdvertising(null)
        stopBleScan(null)
        closeGattServer()
        disconnectAllClients()
        unregisterBondStateReceiver()
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

        clientGatt?.close()
        clientGatt = null
        connectingDeviceAddress = deviceAddress
        registerBondStateReceiver()

        stopBleScan(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            clientGatt = device.connectGatt(context, false, gattClientCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            clientGatt = device.connectGatt(context, false, gattClientCallback)
        }
        if(clientGatt == null){
            Log.e(TAG, "connectGatt returned null for $deviceAddress")
            connectingDeviceAddress = null
            unregisterBondStateReceiver()
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
            if (connectingDeviceAddress == deviceAddress) {
                connectingDeviceAddress = null
                unregisterBondStateReceiver()
            }
            result.success(true)
            return
        }

        clientGatt?.disconnect()
        if (connectingDeviceAddress == deviceAddress) {
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

        val readPermission = if (this.encryptionRequired) {
            Log.d(TAG, "Setting characteristics with PERMISSION_READ_ENCRYPTED")
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
        } else {
            Log.d(TAG, "Setting characteristics with PERMISSION_READ")
            BluetoothGattCharacteristic.PERMISSION_READ
        }

        val ssidCharacteristic = BluetoothGattCharacteristic(
            ssidCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ,
            readPermission
        )
        ssidCharacteristic.value = ssid.toByteArray(Charsets.UTF_8)
        val pskCharacteristic = BluetoothGattCharacteristic(
            pskCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_READ,
            readPermission
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
            clientGatt?.disconnect()
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
                // Do not try to access device.name if permission is missing to avoid SecurityException
                val deviceName = if (canAccessName) device.name ?: "Unknown" else "Protected"
                val deviceAddress = device.address

                val resultMap = mapOf(
                    "deviceAddress" to deviceAddress,
                    "deviceName" to deviceName,
                )
                val updated = discoveredDevicesMap.put(deviceAddress, resultMap) != resultMap
                if (updated) {
                    Log.d(TAG,"BLE Device Found/Updated: $deviceAddress ($deviceName) RSSI: ${result.rssi}")
                    sendScanResultListUpdate()
                }
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            super.onBatchScanResults(results)
            var listChanged = false
             results?.forEach { result ->
                 result.device?.let { device ->
                    val canAccessName = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
                    val deviceName = if (canAccessName) device.name ?: "Unknown" else "Protected"
                    val deviceAddress = device.address

                    val resultMap = mapOf(
                    "deviceAddress" to deviceAddress,
                    "deviceName" to deviceName,
                    )
                    if (discoveredDevicesMap.put(deviceAddress, resultMap) != resultMap) {
                        listChanged = true
                        Log.d(TAG,"BLE Device Found/Updated (Batch): $deviceAddress ($deviceName) RSSI: ${result.rssi}")
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

                        if (this@BleManager.bondingRequired && device.bondState == BluetoothDevice.BOND_NONE) {
                            Log.d(TAG, "GATT Server: Bonding required. Requesting bond with $deviceAddress. Current bond state: ${bondStateToString(device.bondState)}")
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                                if (device.createBond()) {
                                    Log.d(TAG, "GATT Server: createBond initiated for $deviceAddress")
                                } else {
                                    Log.e(TAG, "GATT Server: createBond failed for $deviceAddress")
                                }
                            } else {
                                Log.e(TAG, "Missing BLUETOOTH_CONNECT permission to create bond on server side.")
                            }
                        } else if (device.bondState == BluetoothDevice.BOND_NONE) {
                             Log.d(TAG, "GATT Server: Device $deviceAddress is not bonded, but bonding is not required by server config. Current bond state: ${bondStateToString(device.bondState)}")
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
                Log.e(TAG,"GATT Server: Connection state error for $deviceName ($deviceAddress). Status: $status, NewState: $newState")
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
            val currentBondStateOnServer = device.bondState
            Log.d(TAG, "GATT Server: Read request for Characteristic $charUuid from $deviceAddress (Offset: $offset, BondState: ${bondStateToString(currentBondStateOnServer)})")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
                Log.e(TAG, "Missing BLUETOOTH_CONNECT permission for GATT server read response.")
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null) // Using GATT_FAILURE as specific auth perm is for system
                return
            }

            if (charUuid == ssidCharacteristicUuid || charUuid == pskCharacteristicUuid) {
                val charRequiresEncryption = (characteristic.permissions and BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED) != 0

                if (charRequiresEncryption) {
                    if (currentBondStateOnServer != BluetoothDevice.BOND_BONDED) {
                        Log.w(TAG, "GATT Server: Denying read for $charUuid (requires encryption) from $deviceAddress. Device not bonded. BondState: ${bondStateToString(currentBondStateOnServer)}")
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null)
                        return
                    }
                    Log.d(TAG, "GATT Server: Allowing read for $charUuid (requires encryption, device bonded) from $deviceAddress.")
                } else {
                    Log.d(TAG, "GATT Server: Allowing read for $charUuid (no encryption required by char) from $deviceAddress. BondState: ${bondStateToString(currentBondStateOnServer)}")
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

    private fun discoverServices(gatt: BluetoothGatt) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            Log.d(TAG, "GATT Client: Attempting to discover services for ${gatt.device.address}")
            if (!gatt.discoverServices()) {
                Log.e(TAG,"GATT Client: Failed to initiate service discovery for ${gatt.device.address}")
                gatt.disconnect()
            }
        } else {
            Log.e(TAG, "Missing BLUETOOTH_CONNECT to discover services for ${gatt.device.address}. Disconnecting.")
            gatt.disconnect()
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
                        Log.i(TAG, "GATT Client: Connected to $deviceName ($deviceAddress). Current bond state: ${bondStateToString(device.bondState)}. BondingRequired Config: ${this@BleManager.bondingRequired}")
                        clientGatt = gatt
                        sendConnectionStateUpdate(device, true)

                        if (this@BleManager.bondingRequired) {
                            if (device.bondState == BluetoothDevice.BOND_BONDED) {
                                Log.d(TAG, "GATT Client: Bonding required and device already bonded. Discovering services for $deviceAddress...")
                                discoverServices(gatt)
                            } else {
                                Log.i(TAG, "GATT Client: Bonding required. Device not bonded ($deviceAddress). Waiting for bonding process. Bond state: ${bondStateToString(device.bondState)}")
                                if (device.bondState == BluetoothDevice.BOND_NONE) {
                                     Log.d(TAG, "GATT Client: Device is BOND_NONE. Server (if configured for bonding) should initiate. Client registered bondStateReceiver.")
                                }
                            }
                        } else {
                            Log.d(TAG, "GATT Client: Bonding not required by config. Discovering services for $deviceAddress... Bond state: ${bondStateToString(device.bondState)}")
                            discoverServices(gatt)
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
                Log.d(TAG, "Listing all discovered services for $deviceAddress:")
                gatt.services?.forEachIndexed { index, service ->
                    Log.d(TAG, "  Service [${index}]: ${service.uuid}")
                    service.characteristics?.forEachIndexed { charIndex, characteristic ->
                        Log.d(TAG, "    Characteristic [${charIndex}]: ${characteristic.uuid}, Permissions: ${characteristic.permissions}")
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
                    Log.d(TAG, "GATT Client: Found SSID (perms: ${ssidChar.permissions}) and PSK (perms: ${pskChar.permissions}) characteristics. Reading SSID...")
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

            Log.d(TAG, "GATT Client: Read char $charUuid status $status. Value: '${String(value, Charsets.UTF_8)}'. Current bond state: ${bondStateToString(device.bondState)}")
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
                    gatt.disconnect()
                }
            } else if (status == BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION || status == BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION) {
                 Log.w(TAG, "GATT Client: Read failed for $charUuid with status $status (Insufficient Auth/Encryption). Bond state: ${bondStateToString(device.bondState)}. Characteristic requires encryption: ${(characteristic.permissions and BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED) != 0}")
                 // This can happen if the characteristic requires encryption but the link is not encrypted (e.g., bonding failed or not done).
                gatt.disconnect()
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
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) { // Guard for the deprecated API
                if (characteristic != null && gatt != null) {
                     // The characteristic.value might be stale here in some cases if not updated by the stack before this callback.
                     // The new onCharacteristicRead callback is preferred.
                    onCharacteristicRead(gatt, characteristic, characteristic.value ?: byteArrayOf(), status)
                }
            }
        }
    }
}