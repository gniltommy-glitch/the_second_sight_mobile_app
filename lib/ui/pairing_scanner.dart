import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PairingScanner extends StatefulWidget {
  const PairingScanner({super.key});
  @override
  State<PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<PairingScanner> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool delivered = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét QR cấu hình kính')),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        if (delivered) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value == null) continue;
          delivered = true;
          Navigator.of(context).pop(value);
          break;
        }
      },
      errorBuilder: (context, error) => const Center(
        child: Text(
          'Không mở được camera. Cấp quyền camera hoặc dùng Dán cấu hình.',
        ),
      ),
    ),
  );
}
