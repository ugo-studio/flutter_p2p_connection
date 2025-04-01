import 'package:flutter_p2p_connection/classes.dart';

WifiP2pDevice deserializeDevice(Map<String, dynamic> device) {
  WifiP2pDeviceStatus status = WifiP2pDeviceStatus.unavailable;
  switch (device['status']) {
    case 0:
      status = WifiP2pDeviceStatus.connected;
      break;
    case 1:
      status = WifiP2pDeviceStatus.invited;
      break;
    case 2:
      status = WifiP2pDeviceStatus.failed;
      break;
    case 3:
      status = WifiP2pDeviceStatus.available;
      break;
  }

  if (device.isEmpty) {
    return WifiP2pDevice(
      deviceName: '',
      deviceAddress: '',
      isGroupOwner: false,
      isServiceDiscoveryCapable: false,
      status: status,
    );
  }

  return WifiP2pDevice(
    deviceName: device['deviceName'],
    deviceAddress: device['deviceAddress'],
    primaryDeviceType: device['primaryDeviceType'],
    secondaryDeviceType: device['secondaryDeviceType'],
    isGroupOwner: device['isGroupOwner'],
    isServiceDiscoveryCapable: device['isServiceDiscoveryCapable'],
    status: status,
  );
}

WifiP2pConnectionInfo deserializeConnectionInfo(Map<String, dynamic> info) {
  return WifiP2pConnectionInfo(
      isConnected: info['isConnected'],
      groupFormed: info['groupFormed'],
      isGroupOwner: info['isGroupOwner'],
      groupOwnerAddress: info['groupOwnerAddress'],
      owner: deserializeDevice(Map.from(info['owner'])),
      clients: List.castFrom(info['clients'])
          .map((device) => deserializeDevice(Map.from(device)))
          .toList());
}

WifiP2pGroupInfo deserializeGroupInfo(Map<String, dynamic> info) {
  return WifiP2pGroupInfo(
      isGroupOwner: info['isGroupOwner'],
      passPhrase: info['passPhrase'],
      groupNetworkName: info['groupNetworkName'],
      owner: deserializeDevice(Map.from(info['owner'])),
      clients: List.castFrom(info['clients'])
          .map((device) => deserializeDevice(Map.from(device)))
          .toList());
}
