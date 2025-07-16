import 'dart:io';

Future<String?> getLocalIpAddress() async {
  try {
    // Get a list of all network interfaces
    // Setting includeLoopback to false filters out the loopback interface (127.0.0.1)
    // Setting internetAddressType to InternetAddressType.IPv4 ensures we only get IPv4 addresses
    final interfaces = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.IPv4);

    for (var interface in interfaces) {
      // The addresses property of a NetworkInterface object is a list of InternetAddress objects.
      for (var addr in interface.addresses) {
        // A non-loopback IPv4 address is a good candidate for the local network IP
        if (addr.address.startsWith('192.168.')) {
          return addr.address;
        }
      }
    }
  } catch (_) {}
  return null;
}
