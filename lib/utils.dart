// import 'package:flutter/foundation.dart';
// import 'package:network_info_plus/network_info_plus.dart';

// Future<String?> getIpAddress() async {
//   List<NetworkInterface> interfaces = await NetworkInterface.list(
//     type: InternetAddressType.IPv4,
//     includeLinkLocal: true,
//   );
//   List<NetworkInterface> addr = interfaces
//       .where((e) => e.addresses.first.address.indexOf('192.') == 0)
//       .toList();

//   // print(interfaces.map((e) => e.addresses.first.address).toList());

//   if (addr.isNotEmpty) {
//     return addr.first.addresses.first.address;
//   } else {
//     return null;
//   }
// }

// Stream<String?> streamIpAddress() async* {
//   String? ip;
//   while (ip == null) {
//     await Future.delayed(const Duration(milliseconds: 100));
//     ip = await getIpAddress();
//     yield ip;
//   }
// }

// class WifiNetworkInfo {
//   String? hostIp;
//   String? bssid;
//   WifiNetworkInfo({required this.hostIp, required this.bssid});
//   bool hasInfo() {
//     return hostIp != null && bssid != null;
//   }
// }

// Future<WifiNetworkInfo> getWifiNetworkInfo() async {
//   final networkInfo = NetworkInfo();

//   String? hostIp;
//   String? bssid;

//   try {
//     hostIp = await networkInfo.getWifiIP();
//     bssid = await networkInfo.getWifiBSSID();

//     print(hostIp);
//     print(bssid);
//   } catch (e) {
//     debugPrint("Error getting network info: $e");
//   }
//   return WifiNetworkInfo(hostIp: hostIp, bssid: bssid);
// }

// Stream<WifiNetworkInfo> streamWifiNetworkInfo() async* {
//   WifiNetworkInfo info = WifiNetworkInfo(hostIp: null, bssid: null);

//   while (info.hasInfo() == false) {
//     await Future.delayed(const Duration(milliseconds: 100));

//     info = await getWifiNetworkInfo();
//     yield info;
//   }
// }
