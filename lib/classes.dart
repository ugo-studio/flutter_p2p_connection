import 'package:dio/dio.dart';

enum WifiP2pDeviceStatus { connected, invited, failed, available, unavailable }

class WifiP2pDevice {
  final String deviceName;
  final String deviceAddress;
  final WifiP2pDeviceStatus status;
  final bool? isGroupOwner;
  final bool? isServiceDiscoveryCapable;
  final String? primaryDeviceType;
  final String? secondaryDeviceType;
  const WifiP2pDevice({
    required this.deviceName,
    required this.deviceAddress,
    required this.status,
    required this.isGroupOwner,
    required this.isServiceDiscoveryCapable,
    this.primaryDeviceType,
    this.secondaryDeviceType,
  });
}

class WifiP2pConnectionInfo {
  final bool isConnected;
  final bool isGroupOwner;
  final bool groupFormed;
  final String groupOwnerAddress;
  final List<WifiP2pDevice> clients;
  final WifiP2pDevice? owner;
  const WifiP2pConnectionInfo({
    required this.isConnected,
    required this.isGroupOwner,
    required this.groupFormed,
    required this.groupOwnerAddress,
    required this.clients,
    this.owner,
  });
}

class WifiP2pGroupInfo {
  final bool isGroupOwner;
  final String? passPhrase;
  final String groupNetworkName;
  final WifiP2pDevice owner;
  final List<WifiP2pDevice> clients;
  const WifiP2pGroupInfo({
    required this.isGroupOwner,
    required this.passPhrase,
    required this.groupNetworkName,
    required this.owner,
    required this.clients,
  });
}

class WifiP2pClient {
  final String deviceName;
  final String? userName;
  final String? imageUrl;
  WifiP2pClient({
    required this.deviceName,
    required this.userName,
    required this.imageUrl,
  });
}
