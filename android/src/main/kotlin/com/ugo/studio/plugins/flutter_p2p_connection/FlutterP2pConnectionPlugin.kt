package com.ugo.studio.plugins.flutter_p2p_connection

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ContentValues.TAG
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
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*

import com.google.gson.Gson;

/** FlutterP2pConnectionPlugin */
class FlutterP2pConnectionPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  lateinit var context: Context
  lateinit var activity: Activity
  val intentFilter = IntentFilter()
  lateinit var wifimanager: WifiP2pManager
  lateinit var wifichannel: WifiP2pManager.Channel
  var receiver: BroadcastReceiver? = null
  var EfoundPeers: MutableList<Any> = mutableListOf()
  private lateinit var CfoundPeers: EventChannel
  var EnetworkInfo: NetworkInfo? = null
  var EwifiP2pInfo: WifiP2pInfo? = null
  private lateinit var CConnectedPeers: EventChannel
  var groupClients: List<Any> = mutableListOf()

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_p2p_connection")
    channel.setMethodCallHandler(this)
    CfoundPeers = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_p2p_connection_foundPeers")
    CfoundPeers.setStreamHandler(FoundPeersHandler)
    CConnectedPeers = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_p2p_connection_connectedPeers")
    CConnectedPeers.setStreamHandler(ConnectedPeersHandler)
  }

  @RequiresApi(Build.VERSION_CODES.M)
  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    try {
      when (call.method) {
        "getPlatformVersion" -> result.success("Android: ${android.os.Build.VERSION.RELEASE}")
        "getPlatformModel" -> result.success("model: ${android.os.Build.MODEL}")
        "initialize" -> initializeWifiP2PConnections(result)
        "discover" -> discoverPeers(result)
        "stopDiscovery" -> stopPeerDiscovery(result)
        "connect" -> {
          val address: String = call.argument("address") ?: ""
          connect(result, address)
        }
        "disconnect" -> disconnect(result)
        "createGroup" -> createGroup(result)
        "removeGroup" -> removeGroup(result)
        "groupInfo" -> requestGroupInfo(result)
        "fetchPeers" -> fetchPeers(result)
        "resume" -> resume(result)
        "pause" -> pause(result)
        "checkLocationPermission" -> checkLocationPermission(result)
        "askLocationPermission" -> askLocationPermission(result)
        "checkLocationEnabled" -> checkLocationEnabled(result)
        "checkGpsEnabled" -> checkGpsEnabled(result)
        "enableLocationServices" -> enableLocationServices(result)
        "checkWifiEnabled" -> checkWifiEnabled(result)
        "enableWifiServices" -> enableWifiServices(result)
        else -> {
          result.notImplemented()
        }
      }
    } catch (e: Exception) {
      result.error("Err>>:", " ${e}", e)
    }
  }

  @RequiresApi(Build.VERSION_CODES.M)
  fun checkLocationPermission(result: Result) {
    if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
      && context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
      result.success(true);
    } else {
      result.success(false);
    }
  }

  @RequiresApi(Build.VERSION_CODES.M)
  fun askLocationPermission(result: Result) {
    val perms: Array<String> = arrayOf<String>(Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION)
    activity.requestPermissions(perms, 2468)
    result.success(true)
  }

  fun checkLocationEnabled(result: Result) {
    var lm: LocationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    result.success("${lm.isProviderEnabled(LocationManager.GPS_PROVIDER)}:${lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)}")
  }

  fun checkGpsEnabled(result: Result) {
    var lm: LocationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    result.success(lm.isProviderEnabled(LocationManager.GPS_PROVIDER) && lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER))
  }

  fun enableLocationServices(result: Result) {
    activity.startActivity(Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS))
    result.success(true)
  }

  fun checkWifiEnabled(result: Result) {
    var wm: WifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
    result.success(wm.isWifiEnabled)
  }

  fun enableWifiServices(result: Result) {
    activity.startActivity(Intent(android.provider.Settings.ACTION_WIFI_SETTINGS))
    result.success(true)
  }

  fun resume(result: Result) {
    // receiver = WiFiDirectBroadcastReceiver(wifimanager, wifichannel, activity)
    receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        // Log.d(TAG, "FlutterP2pConnection: registered receiver")
        val action: String? = intent.action
        when (action) {
          WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
            // Check to see if Wi-Fi is enabled and notify appropriate activity
            val state: Int = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
            when (state) {
              WifiP2pManager.WIFI_P2P_STATE_ENABLED -> {
                // Wifi P2P is enabled
                Log.d(TAG, "FlutterP2pConnection: state enabled, Int=${state}")
              }
              else -> {
                // Wi-Fi P2P is not enabled
                Log.d(TAG, "FlutterP2pConnection: state disabled, Int=${state}")
              }
            }
          }
          WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
            // Call WifiP2pManager.requestPeers() to get a list of current peers
            peersListener()
          }
          WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
            // Respond to new connection or disconnections
            wifimanager.requestGroupInfo(wifichannel, WifiP2pManager.GroupInfoListener { group: WifiP2pGroup? ->
            if (group != null) {
              groupClients = deviceConsolidateList(group)
              Log.d(TAG, "FlutterP2pConnection :  clients " + Gson().toJson(groupClients))
              }
            })
            val networkInfo: NetworkInfo? = intent.getParcelableExtra(WifiP2pManager.EXTRA_NETWORK_INFO)
            val wifiP2pInfo: WifiP2pInfo? = intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
            if (networkInfo != null && wifiP2pInfo != null) {
              EnetworkInfo = networkInfo
              EwifiP2pInfo = wifiP2pInfo

              val info = object {
                // methods called on object before sending through channel
                val connected : Boolean = networkInfo.isConnected
                val isGroupOwner : Boolean = wifiP2pInfo.isGroupOwner
                val groupOwnerAddress : String = if (wifiP2pInfo.groupOwnerAddress==null) "" else wifiP2pInfo.groupOwnerAddress.toString()
                val groupFormed: Boolean =  wifiP2pInfo.groupFormed
                val clients: List<Any> = groupClients
              }
              Log.d(TAG, "FlutterP2pConnection: connectionInfo=" + Gson().toJson(info))
              Log.d(TAG, "FlutterP2pConnection: connectionInfo={connected: ${networkInfo.isConnected}, isGroupOwner: ${wifiP2pInfo.isGroupOwner}, groupOwnerAddress: ${wifiP2pInfo.groupOwnerAddress}, groupFormed: ${wifiP2pInfo.groupFormed}, clients: ${groupClients}}")
            }
          }
          WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
            // Respond to this device's wifi state changing
          }
        }
      }
    }
    context.registerReceiver(receiver, intentFilter)
    //Log.d(TAG, "FlutterP2pConnection: Initialized wifi p2p connection")
    result.success(true)
  }

  fun pause(result: Result) {
    context.unregisterReceiver(receiver)
    //Log.d(TAG, "FlutterP2pConnection: paused wifi p2p connection receiver")
    result.success(true)
  }

  fun initializeWifiP2PConnections(result: Result) {
    intentFilter.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
    intentFilter.addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
    intentFilter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
    intentFilter.addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
    wifimanager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
    wifichannel = wifimanager.initialize(context, Looper.getMainLooper(), null)
    result.success(true)
  }

  fun createGroup(result: Result) {
    wifimanager.createGroup(wifichannel, object : WifiP2pManager.ActionListener {
      override fun onSuccess() {
        Log.d(TAG, "FlutterP2pConnection: Created wifi p2p group")
        result.success(true)
      }

      override fun onFailure(reasonCode: Int) {
        Log.d(TAG, "FlutterP2pConnection: failed to create group, reasonCode=${reasonCode}")
        result.success(false)
      }
    })
  }

  fun removeGroup(result: Result) {
    wifimanager.removeGroup(wifichannel, object : WifiP2pManager.ActionListener {
      override fun onSuccess() {
        Log.d(TAG, "FlutterP2pConnection: removed wifi p2p group")
        result.success(true)
      }

      override fun onFailure(reasonCode: Int) {
        Log.d(TAG, "FlutterP2pConnection: failed to remove group, reasonCode=${reasonCode}")
        result.success(false)
      }
    })
  }

  fun deviceConsolidateList(group: WifiP2pGroup) : List<Any> {
    var list : MutableList<Any> = mutableListOf()
    for (device: WifiP2pDevice in group.clientList) {
      list.add(deviceConsolidated(device))
    }
    return list
  }

  fun deviceConsolidated(device: WifiP2pDevice) : Any {
    val dev = object {
      // from https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pDevice
      val deviceName : String = device.deviceName
      val deviceAddress : String = device.deviceAddress
      val primaryDeviceType : String? = device.primaryDeviceType
      val secondaryDeviceType : String? = device.secondaryDeviceType
      val status : Int = device.status
      // methods called on object before sending through channel
      val isGroupOwner : Boolean = device.isGroupOwner()
      val isServiceDiscoveryCapable : Boolean = device.isServiceDiscoveryCapable()
      val wpsDisplaySupported : Boolean= device.wpsDisplaySupported()
      val wpsKeypadSupported : Boolean= device.wpsKeypadSupported()
      val wpsPbcSupported : Boolean= device.wpsPbcSupported()
    }
    return dev
  }

  fun requestGroupInfo(result: Result) {
    wifimanager.requestGroupInfo(wifichannel, WifiP2pManager.GroupInfoListener { group: WifiP2pGroup? ->
      if (group != null) {
        val obj = object {
          // https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pGroup
          val isGroupOwner : Boolean = group.isGroupOwner()
          val passPhrase : String? = group.passphrase
          val groupNetworkName : String = group.networkName
          val clients : List<Any> = deviceConsolidateList(group)
        }
        var json = Gson().toJson(obj)
        Log.d(TAG, "FlutterP2pConnection:  groupInfo" + json)
        result.success(json)
      }
    })
  }

  fun discoverPeers(result: Result) {
    wifimanager.discoverPeers(wifichannel, object : WifiP2pManager.ActionListener {
      override fun onSuccess() {
        Log.d(TAG, "FlutterP2pConnection: discovering wifi p2p devices")
        result.success(true);
      }
      override fun onFailure(reasonCode: Int) {
        Log.d(TAG, "FlutterP2pConnection: discovering wifi p2p devices failed, reasonCode=${reasonCode}")
        result.success(false);
      }
    })
  }

  fun stopPeerDiscovery(result: Result) {
    wifimanager.stopPeerDiscovery(wifichannel, object : WifiP2pManager.ActionListener {
      override fun onSuccess() {
        Log.d(TAG, "FlutterP2pConnection: stopped discovering wifi p2p devices")
        result.success(true);
      }
      override fun onFailure(reasonCode: Int) {
        Log.e(TAG, "FlutterP2pConnection: failed to stop discovering wifi p2p devices, reasonCode=${reasonCode}")
        Log.e(TAG, "FlutterP2pConnection: see https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pManager.ActionListener#onFailure(int) for codes")
        result.success(false);
      }
    })
  }

  fun connect(result: Result, address: String) {
    val config = WifiP2pConfig()
    config.deviceAddress = address
    config.wps.setup = WpsInfo.PBC
    wifichannel.also { wifichannel: WifiP2pManager.Channel ->
      wifimanager.connect(wifichannel, config, object : WifiP2pManager.ActionListener {
        override fun onSuccess() {
          Log.d(TAG, "FlutterP2pConnection: connected to wifi p2p device, address=${address}")
          result.success(true);
        }
        override fun onFailure(reasonCode: Int) {
          Log.e(TAG, "FlutterP2pConnection: connection to wifi p2p device failed, reasoCode=${reasonCode}")
          result.success(false);
        }
      })
    }
  }

  fun disconnect(result: Result) {
      wifimanager.cancelConnect(wifichannel, object : WifiP2pManager.ActionListener {
        override fun onSuccess() {
          Log.d(TAG, "FlutterP2pConnection disconnect from wifi p2p connection: true")
          result.success(true)
        }
        override fun onFailure(reasonCode: Int) {
          Log.e(TAG, "FlutterP2pConnection disconnect from wifi p2p connection: false, ${reasonCode}")
          result.success(false)
        }
      })
  }

  fun fetchPeers(result: Result) {
    result.success(Gson().toJson(EfoundPeers))
  }

  fun peersListener() {
    wifimanager.requestPeers(wifichannel) { peers: WifiP2pDeviceList ->
      var list: MutableList<Any> = mutableListOf()
      for (device: WifiP2pDevice in peers.deviceList) {
        list.add(deviceConsolidated(device))
      }
      EfoundPeers = list
      Log.d(TAG, "FlutterP2pConnection : Peers  " + Gson().toJson(EfoundPeers))
    }
  }

  val FoundPeersHandler = object : EventChannel.StreamHandler {
    private var handler: Handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(p0: Any?, sink: EventChannel.EventSink) {
      eventSink = sink
      var peers: String = ""
      val r: Runnable = object : Runnable {
        override fun run() {
          handler.post {
            if (peers != EfoundPeers.toString()) {
              peers = EfoundPeers.toString()
              Log.d(TAG, "FlutterP2pConnection Peers are " + Gson().toJson(EfoundPeers))
              eventSink?.success(Gson().toJson(EfoundPeers))
            }
          }
          handler.postDelayed(this, 1000)
        }
      }
      handler.postDelayed(r, 1000)
    }
    override fun onCancel(p0: Any?) {
      eventSink = null
    }
  }

  val ConnectedPeersHandler = object : EventChannel.StreamHandler {
    private var handler: Handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(p0: Any?, sink: EventChannel.EventSink) {
      eventSink = sink
      var networkinfo: NetworkInfo? = null
      var wifip2pinfo: WifiP2pInfo? = null
      val r: Runnable = object : Runnable {
        override fun run() {
          handler.post {
            val ni: NetworkInfo? = EnetworkInfo
            val wi: WifiP2pInfo? = EwifiP2pInfo
            if (ni != null && wi != null) {
              if (networkinfo != ni && wifip2pinfo != wi) {
                networkinfo = ni
                wifip2pinfo = wi

                val obj = object {
                  // https://developer.android.com/reference/android/net/wifi/p2p/WifiP2pGroup
                  // methods
                  val isConnected : Boolean = ni.isConnected
                  val isGroupOwner : Boolean = wi.isGroupOwner
                  val groupFormed : Boolean = wi.groupFormed
                  val groupOwnerAddress : String = if (wi.groupOwnerAddress == null)  "null" else wi.groupOwnerAddress.toString()
                  val clients : List<Any> = groupClients
                }
                val json = Gson().toJson(obj)
                Log.d(TAG, "FlutterP2pConnection : connected peers   " + json);
                eventSink?.success(json)
              }
            }
          }
          handler.postDelayed(this, 1000)
        }
      }
      handler.postDelayed(r, 1000)
    }
    override fun onCancel(p0: Any?) {
      eventSink = null
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    CfoundPeers.setStreamHandler(null)
    CConnectedPeers.setStreamHandler(null)
  }

   override fun onDetachedFromActivity() {
     // TODO("Not yet implemented")
   }
   override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
     activity = binding.activity
   }
   override fun onAttachedToActivity(binding: ActivityPluginBinding) {
     activity = binding.activity
   }
   override fun onDetachedFromActivityForConfigChanges() {
     // TODO("Not yet implemented")
   }
}


