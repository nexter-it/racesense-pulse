import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class BleScanPage extends StatefulWidget {
  final Set<String> existingDeviceIds;

  const BleScanPage({super.key, this.existingDeviceIds = const {}});

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage>
    with SingleTickerProviderStateMixin {
  final BleTrackingService _bleService = BleTrackingService();

  static const _targetPrefix = 'GPS-';

  bool get _scanning => _bleService.isScanning;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _startScan();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bleService.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _bleService.startScan(
      nameFilters: const [_targetPrefix],
      continuous: true,
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _connect(String deviceId, String deviceName) async {
    if (!mounted) return;

    HapticFeedback.mediumImpact();

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: _kCardStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(kBrandColor),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connessione in corso...',
                style: TextStyle(
                  color: kFgColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                deviceName,
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final ok = await _bleService.connect(deviceId, autoReconnect: true);

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    if (ok) {
      Navigator.of(context).pop({'id': deviceId, 'name': deviceName});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connessione fallita. Riprova.'),
          backgroundColor: kErrorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            // Scanning indicator
            if (_scanning) _buildScanningIndicator(),
            Expanded(
              child: StreamBuilder<Map<String, BleDeviceSnapshot>>(
                stream: _bleService.deviceStream,
                builder: (context, snapshot) {
                  final devices = snapshot.data ?? {};
                  final filtered = devices.values
                      .where((d) =>
                          (d.name.startsWith(_targetPrefix) ||
                              d.id.startsWith(_targetPrefix)) &&
                          !widget.existingDeviceIds.contains(d.id))
                      .toList();
                  if (filtered.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildDevicesList(filtered);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgColor, const Color(0xFF121212)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(Icons.close, color: kFgColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(40),
                  kBrandColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kBrandColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.bluetooth_searching, color: kBrandColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scansione Dispositivi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cerca dispositivi GPS-Tracker',
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Refresh button
          GestureDetector(
            onTap: _scanning ? null : _startScan,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: Icon(
                _scanning ? Icons.stop : Icons.refresh,
                color: kBrandColor,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          height: 3,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kBrandColor.withAlpha((100 + 155 * _pulseController.value).toInt()),
                kBrandColor,
                kBrandColor.withAlpha((100 + 155 * (1 - _pulseController.value)).toInt()),
              ],
              stops: [
                0,
                _pulseController.value,
                1,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated scanning icon
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (_scanning ? kPulseColor : kMutedColor)
                            .withAlpha((30 + 30 * _pulseController.value).toInt()),
                        (_scanning ? kPulseColor : kMutedColor).withAlpha(10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kCardStart,
                      border: Border.all(
                        color: (_scanning ? kPulseColor : kMutedColor).withAlpha(80),
                        width: 2,
                      ),
                      boxShadow: _scanning
                          ? [
                              BoxShadow(
                                color: kPulseColor
                                    .withAlpha((40 + 40 * _pulseController.value).toInt()),
                                blurRadius: 20,
                                spreadRadius: 5 * _pulseController.value,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _scanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                      color: _scanning ? kPulseColor : kMutedColor,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              _scanning ? 'Ricerca in corso...' : 'Nessun dispositivo trovato',
              style: const TextStyle(
                color: kFgColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Accendi il tuo GPS-Tracker e assicurati\nche sia nelle vicinanze',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Tips card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [_kCardStart, _kCardEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _kBorderColor),
              ),
              child: Column(
                children: [
                  _buildTip(Icons.power_settings_new, 'Verifica che il dispositivo sia acceso'),
                  const SizedBox(height: 10),
                  _buildTip(Icons.bluetooth, 'Abilita il Bluetooth sul telefono'),
                  const SizedBox(height: 10),
                  _buildTip(Icons.location_on, 'Consenti l\'accesso alla posizione'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kBrandColor.withAlpha(15),
            border: Border.all(color: kBrandColor.withAlpha(40)),
          ),
          child: Icon(icon, color: kBrandColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevicesList(List<BleDeviceSnapshot> devices) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildFoundHeader(devices.length);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildDeviceCard(devices[index - 1]),
        );
      },
    );
  }

  Widget _buildFoundHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: kBrandColor,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Dispositivi trovati',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kBrandColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBrandColor.withAlpha(60)),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: kBrandColor,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BleDeviceSnapshot device) {
    final rssiStrength = (device.rssi ?? -100) + 100;
    final signalQuality = rssiStrength.clamp(0, 100) / 100;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kBrandColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: kBrandColor.withAlpha(30),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Bluetooth icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: Center(
                child: Icon(Icons.bluetooth, color: kBrandColor, size: 26),
              ),
            ),
            const SizedBox(width: 14),
            // Device info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name.isNotEmpty ? device.name : device.id,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: kFgColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Signal strength indicator
                      ...List.generate(4, (i) {
                        final isActive = signalQuality >= (i + 1) / 4;
                        return Container(
                          margin: const EdgeInsets.only(right: 3),
                          width: 5,
                          height: 8 + (i * 3.5),
                          decoration: BoxDecoration(
                            color: isActive ? kBrandColor : kMutedColor.withAlpha(60),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kBrandColor.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kBrandColor.withAlpha(40)),
                        ),
                        child: Text(
                          'Disponibile',
                          style: TextStyle(
                            color: kBrandColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Connect button
            GestureDetector(
              onTap: () => _connect(device.id, device.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [kBrandColor, kBrandColor.withAlpha(200)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withAlpha(50),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.link, color: Colors.black, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Connetti',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
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
  }
}
