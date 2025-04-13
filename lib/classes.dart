class HotspotInfo {
  final bool isActive;
  final String? ssid;
  final String? preSharedKey;
  final String? hostIpAddress;
  final int? failureReason;

  HotspotInfo({
    required this.isActive,
    this.ssid,
    this.preSharedKey,
    this.hostIpAddress,
    this.failureReason,
  });

  factory HotspotInfo.fromMap(Map<dynamic, dynamic> map) {
    return HotspotInfo(
      isActive: map['isActive'] as bool,
      ssid: map['ssid'] as String?,
      preSharedKey: map['preSharedKey'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
      failureReason: map['failureReason'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'ssid': ssid,
      'preSharedKey': preSharedKey,
      'hostIpAddress': hostIpAddress,
      'failureReason': failureReason,
    };
  }
}

class HotspotClientState {
  final bool isActive;
  final String? ssid;
  final String? gatewayIpAddress;
  final String? hostIpAddress;

  HotspotClientState({
    required this.isActive,
    this.ssid,
    this.gatewayIpAddress,
    this.hostIpAddress,
  });

  factory HotspotClientState.fromMap(Map<dynamic, dynamic> map) {
    return HotspotClientState(
      isActive: map['isActive'] as bool,
      ssid: map['ssid'] as String?,
      gatewayIpAddress: map['gatewayIpAddress'] as String?,
      hostIpAddress: map['hostIpAddress'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isActive': isActive,
      'ssid': ssid,
      'gatewayIpAddress': gatewayIpAddress,
      'hostIpAddress': hostIpAddress,
    };
  }
}
