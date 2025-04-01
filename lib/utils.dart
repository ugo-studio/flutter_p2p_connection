import 'dart:io';

Future<String?> getIpAddress() async {
  List<NetworkInterface> interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: true,
  );
  List<NetworkInterface> addr = interfaces
      .where((e) => e.addresses.first.address.indexOf('192.') == 0)
      .toList();

  // print(interfaces.map((e) => e.addresses.first.address).toList());

  if (addr.isNotEmpty) {
    return addr.first.addresses.first.address;
  } else {
    return null;
  }
}

Stream<String?> streamIpAddress() async* {
  String? ip;
  while (ip == null) {
    await Future.delayed(const Duration(milliseconds: 100));
    ip = await getIpAddress();
    yield ip;
  }
}
