import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

class QrImagePage extends StatefulWidget {
  final HotspotHostState? hotspotState;
  const QrImagePage({
    super.key,
    required this.hotspotState,
  });

  @override
  State<QrImagePage> createState() => _QrImagePageState();
}

class _QrImagePageState extends State<QrImagePage> {
  QrImage? qrImage;

  @override
  void initState() {
    super.initState();

    String? ssid = widget.hotspotState?.ssid;
    String? preSharedKey = widget.hotspotState?.preSharedKey;

    // generate qrcode
    if (ssid != null && preSharedKey != null) {
      QrCode qrCode = QrCode(8, QrErrorCorrectLevel.H);
      qrCode.addData(jsonEncode({'ssid': ssid, 'preSharedKey': preSharedKey}));
      qrImage = QrImage(qrCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('qr image'),
      ),
      body: Center(
        child: qrImage != null
            ? SizedBox(
                width: 300,
                child: PrettyQrView(qrImage: qrImage!),
              )
            : const Text("no qr code"),
      ),
    );
  }
}
