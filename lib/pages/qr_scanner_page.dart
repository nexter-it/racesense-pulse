import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

import '../theme.dart';
import 'live_timing_dashboard_page.dart';

/// Pagina per la scansione del QR code - RaceChrono Pro Style
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _isProcessing = false;
  String? _lastScannedCode;
  bool _flashOn = false;
  bool _cameraReady = false;

  // Animazione pulsante scanner
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller?.pauseCamera();
    }
    controller?.resumeCamera();
  }

  @override
  void dispose() {
    controller?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool _isValidDeviceId(String value) {
    final hexIdRegex = RegExp(r'^[0-9A-Fa-f]{12}$');
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return hexIdRegex.hasMatch(value) || macRegex.hasMatch(value);
  }

  String _normalizeDeviceId(String id) {
    return id.replaceAll(':', '').replaceAll('-', '').toUpperCase();
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
      _cameraReady = true;
    });

    controller.scannedDataStream.listen((scanData) {
      if (_isProcessing) return;

      final String? rawValue = scanData.code;
      if (rawValue == null || rawValue.isEmpty) return;
      if (_lastScannedCode == rawValue) return;
      _lastScannedCode = rawValue;

      final trimmedValue = rawValue.trim();

      if (_isValidDeviceId(trimmedValue)) {
        setState(() => _isProcessing = true);
        controller.pauseCamera();

        final normalizedId = _normalizeDeviceId(trimmedValue);

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LiveTimingDashboardPage(deviceId: normalizedId),
          ),
        );
      } else {
        _showInvalidCodeSnackbar(trimmedValue);
      }
    });
  }

  void _showInvalidCodeSnackbar(String code) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Invalid code: $code',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.withAlpha(220),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _lastScannedCode = null);
    });
  }

  void _toggleFlash() async {
    await controller?.toggleFlash();
    final flash = await controller?.getFlashStatus();
    setState(() => _flashOn = flash ?? false);
  }

  void _flipCamera() async {
    await controller?.flipCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildScannerArea()),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          // Title
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE TIMING',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Scan device QR code',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Flash toggle
          if (_cameraReady)
            GestureDetector(
              onTap: _toggleFlash,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _flashOn
                      ? kBrandColor.withAlpha(30)
                      : Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _flashOn
                        ? kBrandColor.withAlpha(100)
                        : Colors.white.withAlpha(20),
                  ),
                ),
                child: Icon(
                  _flashOn ? Icons.flash_on : Icons.flash_off,
                  color: _flashOn ? kBrandColor : Colors.white.withAlpha(150),
                  size: 20,
                ),
              ),
            ),
          const SizedBox(width: 10),
          // Flip camera
          if (_cameraReady)
            GestureDetector(
              onTap: _flipCamera,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Icon(
                  Icons.cameraswitch,
                  color: Colors.white.withAlpha(150),
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScannerArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Spacer(flex: 1),

          // Scanner container
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: kBrandColor.withAlpha(
                          (100 * _pulseAnimation.value).toInt()),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandColor
                            .withAlpha((40 * _pulseAnimation.value).toInt()),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      children: [
                        // QR Scanner
                        QRView(
                          key: qrKey,
                          onQRViewCreated: _onQRViewCreated,
                          overlay: QrScannerOverlayShape(
                            borderColor: kBrandColor,
                            borderRadius: 16,
                            borderLength: 40,
                            borderWidth: 4,
                            cutOutSize:
                                MediaQuery.of(context).size.width * 0.5,
                            overlayColor: const Color(0xFF0A0A0A).withAlpha(220),
                          ),
                        ),

                        // Scanning indicator
                        if (!_isProcessing && _cameraReady)
                          Positioned(
                            bottom: 20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(180),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white.withAlpha(30)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: kBrandColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: kBrandColor.withAlpha(150),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'SCANNING',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(200),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Processing overlay
                        if (_isProcessing)
                          Container(
                            color: const Color(0xFF0A0A0A).withAlpha(240),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: kBrandColor.withAlpha(20),
                                      border: Border.all(
                                          color: kBrandColor.withAlpha(60)),
                                    ),
                                    child: const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        color: kBrandColor,
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'CONNECTING',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Loading live data...',
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(100),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Info row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Row(
              children: [
                // Format info
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.qr_code_2,
                        color: kBrandColor.withAlpha(180),
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'FORMAT',
                        style: TextStyle(
                          color: Colors.white.withAlpha(100),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '12-char HEX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Colors.white.withAlpha(15),
                ),
                // Example
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.tag,
                        color: kPulseColor.withAlpha(180),
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'EXAMPLE',
                        style: TextStyle(
                          color: Colors.white.withAlpha(100),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '043758187A5F',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: kBrandColor.withAlpha(10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBrandColor.withAlpha(40)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: kBrandColor.withAlpha(180),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Find the QR code on your Racesense GPS device',
                    style: TextStyle(
                      color: Colors.white.withAlpha(180),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
