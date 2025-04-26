package com.ugo.studio.plugins.flutter_p2p_connection

import android.annotation.SuppressLint
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.Collections

import com.ugo.studio.plugins.flutter_p2p_connection.Constants

object DataUtils {
    private const val TAG = Constants.TAG // Use constant

    // Host's Hotspot Info Map
    fun createHotspotInfoMap(isActive: Boolean, config: WifiConfiguration?, ipAddress: String?, failureReason: Int? = null): Map<String, Any?> {
        return mapOf(
            "isActive" to isActive,
            "ssid" to config?.SSID?.removePrefix("\"")?.removeSuffix("\""),
            "preSharedKey" to config?.preSharedKey?.removePrefix("\"")?.removeSuffix("\""),
            "hostIpAddress" to ipAddress,
            "failureReason" to failureReason
        )
    }

    // Client's Connection State Map
    fun createClientStateMap(isActive: Boolean, gatewayIpAddress: String?, ipAddress: String?, connectedSsid: String?): Map<String, Any?> {
        return mapOf(
            "isActive" to isActive,
            "hostGatewayIpAddress" to gatewayIpAddress,
            "hostIpAddress" to ipAddress, // Include host IP here too
            "hostSsid" to connectedSsid?.removePrefix("\"")?.removeSuffix("\"") // Ensure SSID is cleaned
        )
    }

    // Helper to get client connection details (like gateway IP) using Network object
    fun getClientConnectionInfo(connectivityManager: ConnectivityManager, network: Network?): Map<String, Any?>? {
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
     fun getGatewayIpFromLinkProperties(linkProperties: LinkProperties?): String? {
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
    fun getLegacyGatewayIpAddress(wifiManager: WifiManager): String? {
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


    // Helper to find the Host's IP address when acting as hotspot or Client's view of it
    fun getHostIpAddress(): String? {
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
            Log.e(TAG, "Exception while getting Host IP address: $ex")
        }

         if(potentialIp != null) {
            Log.d(TAG, "Using fallback potential host IP: $potentialIp")
            return potentialIp
         }

        Log.w(TAG, "Could not determine host IP address.")
        return null
    }
}