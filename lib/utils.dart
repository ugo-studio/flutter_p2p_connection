import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';

Future<String?> findLocalIPv4Address() async {
  final NetworkInfo networkInfo = NetworkInfo();

  try {
    // Get the Wi-Fi IP address
    // Note: This specifically asks for the Wi-Fi IP.
    // If not connected to Wi-Fi, it might return null or throw.
    String? wifiIPv4 = await networkInfo.getWifiIP();
    if (wifiIPv4 == null) {
      debugPrint('Not connected to Wi-Fi or IP not available.');
      return null; // Exit early if not connected to Wi-Fi
    }
    return wifiIPv4;
  } on PlatformException catch (e) {
    debugPrint('Failed to get Wi-Fi IP: ${e.message}');
    return null; // Exit early on platform exception
  } catch (e) {
    debugPrint('An unexpected error occurred when getting Wi-Fi IP: $e');
    return null; // Exit early on other errors
  }
}

// Future<String?> findLocalIPv4Address() async {
//   String? localIp;
//   try {
//     // List all network interfaces, excluding loopback, filtering for IPv4
//     // includeLinkLocal: true might be needed on some systems if the primary IP is link-local
//     List<NetworkInterface> interfaces = await NetworkInterface.list(
//         includeLoopback: false, type: InternetAddressType.IPv4);

//     // Iterate over interfaces
//     for (var interface in interfaces) {
//       print(
//           'Interface: ${interface.name}'); // e.g., "Wi-Fi", "Ethernet", "en0", "wlan0"
//       // Iterate over addresses associated with the interface
//       for (var addr in interface.addresses) {
//         // Check if it's an IPv4 address and not loopback (already filtered by type, but good practice)
//         if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
//           print('  Found IPv4 address: ${addr.address}');
//           // Often, the first one found is the primary local network IP
//           // You could add more logic here to prefer interfaces named like "Wi-Fi" or "wlan" if needed,
//           // but names vary significantly across OSes (e.g., 'en0' on macOS can be Wi-Fi).
//           localIp ??= addr.address;
//           print(localIp);
//         }
//       }
//       // Optional: break outer loop if IP found
//       // if (localIp != null) break;
//     }
//   } catch (e) {
//     print('Error retrieving network interfaces: $e');
//     return null; // Return null on error
//   }

//   if (localIp == null) {
//     print('Could not find a non-loopback IPv4 address.');
//   }
//   return localIp; // Return the found IP or null
// }