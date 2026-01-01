import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ble_tracking_service.dart';
import '../theme.dart';
import 'connect_devices_page.dart';
import 'custom_circuits_page.dart';
import 'gps_wait_page.dart';
import 'official_circuits_page.dart';
import 'qr_scanner_page.dart';
import 'grand_prix_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class NewPostPage extends StatefulWidget {
  static const routeName = '/new';

  const NewPostPage({super.key});

  @override
  State<NewPostPage> createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage>
    with SingleTickerProviderStateMixin {
  final BleTrackingService _bleService = BleTrackingService();
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceSub;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bleDeviceSub?.cancel();
    super.dispose();
  }

  void _syncConnectedDeviceFromService() {
    final connectedIds = _bleService.getConnectedDeviceIds();
    if (connectedIds.isEmpty) return;
    final id = connectedIds.first;
    final snap = _bleService.getSnapshot(id);
    _connectedDeviceId = id;
    _connectedDeviceName = snap?.name ?? id;
  }

  void _listenBleConnectionChanges() {
    _bleDeviceSub?.cancel();
    _bleDeviceSub = _bleService.deviceStream.listen((devices) {
      final connected = devices.values.firstWhere(
        (d) => d.isConnected,
        orElse: () => BleDeviceSnapshot(
          id: '',
          name: '',
          rssi: null,
          isConnected: false,
        ),
      );

      if (mounted) {
        setState(() {
          if (connected.isConnected) {
            _connectedDeviceId = connected.id;
            _connectedDeviceName = connected.name;
          } else {
            _connectedDeviceId = null;
            _connectedDeviceName = null;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUsingBleDevice = _connectedDeviceId != null;

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // GPS Source Card - Most important visual
                  _buildGpsSourceCard(isUsingBleDevice),
                  const SizedBox(height: 24),

                  // Main Start Button
                  _buildStartButton(),
                  const SizedBox(height: 28),

                  // Section: Other Options
                  _buildSectionHeader('Altre opzioni'),
                  const SizedBox(height: 14),

                  // Options Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildOptionCard(
                          icon: Icons.edit_road,
                          title: 'Circuiti Custom',
                          subtitle: 'Crea o gestisci tracciati',
                          color: kBrandColor,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CustomCircuitsPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOptionCard(
                          icon: Icons.qr_code_scanner,
                          title: 'Live Timing',
                          subtitle: 'Scansiona QR evento',
                          color: kPulseColor,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const QrScannerPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Gran Premio Button
                  _buildOptionCard(
                    icon: Icons.emoji_events,
                    title: 'Gran Premio',
                    subtitle: 'Gareggia con fino a 20 piloti',
                    color: Colors.amber,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const GrandPrixPage(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // Official Circuits Button
                  _buildOptionCard(
                    icon: Icons.stadium_rounded,
                    title: 'Circuiti Ufficiali',
                    subtitle: 'Autodromi con linea S/F verificata',
                    color: const Color(0xFF29B6F6),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OfficialCircuitsPage(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Info tip
                  _buildInfoTip(),
                ],
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
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(40),
                  kBrandColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.add_circle_outline, color: kBrandColor, size: 26),
            ),
          ),
          const SizedBox(width: 14),
          // Title
          const Expanded(
            child: Text(
              'Nuova Attività',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: kFgColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          // Auto Lap badge
          // Container(
          //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          //   decoration: BoxDecoration(
          //     borderRadius: BorderRadius.circular(10),
          //     gradient: LinearGradient(
          //       colors: [
          //         kPulseColor.withAlpha(30),
          //         kPulseColor.withAlpha(15),
          //       ],
          //     ),
          //     border: Border.all(color: kPulseColor.withAlpha(80)),
          //   ),
          //   child: Row(
          //     mainAxisSize: MainAxisSize.min,
          //     children: [
          //       Icon(Icons.flag_outlined, color: kPulseColor, size: 14),
          //       const SizedBox(width: 6),
          //       Text(
          //         'AUTO LAP',
          //         style: TextStyle(
          //           fontSize: 10,
          //           fontWeight: FontWeight.w900,
          //           color: kPulseColor,
          //           letterSpacing: 0.5,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildGpsSourceCard(bool isUsingBleDevice) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConnectDevicesPage()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: isUsingBleDevice
                ? [
                    kBrandColor.withAlpha(25),
                    kBrandColor.withAlpha(10),
                  ]
                : [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isUsingBleDevice ? kBrandColor.withAlpha(120) : _kBorderColor,
            width: isUsingBleDevice ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isUsingBleDevice
                  ? kBrandColor.withAlpha(40)
                  : Colors.black.withAlpha(80),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Large icon with status indicator
                  Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                colors: isUsingBleDevice
                                    ? [
                                        kBrandColor.withAlpha(
                                            (40 + 20 * _pulseController.value).toInt()),
                                        kBrandColor.withAlpha(20),
                                      ]
                                    : [
                                        Colors.white.withAlpha(12),
                                        Colors.white.withAlpha(6),
                                      ],
                              ),
                              border: Border.all(
                                color: isUsingBleDevice
                                    ? kBrandColor.withAlpha(100)
                                    : _kBorderColor,
                                width: 2,
                              ),
                              boxShadow: isUsingBleDevice
                                  ? [
                                      BoxShadow(
                                        color: kBrandColor.withAlpha(
                                            (30 + 30 * _pulseController.value).toInt()),
                                        blurRadius: 16,
                                        spreadRadius: 2 * _pulseController.value,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Icon(
                                isUsingBleDevice
                                    ? Icons.bluetooth_connected
                                    : Icons.smartphone,
                                color: isUsingBleDevice ? kBrandColor : kMutedColor,
                                size: 32,
                              ),
                            ),
                          );
                        },
                      ),
                      // Connection indicator dot
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kBgColor,
                            border: Border.all(
                              color: isUsingBleDevice ? kBrandColor : kMutedColor,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isUsingBleDevice ? kBrandColor : kMutedColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SORGENTE GPS',
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isUsingBleDevice
                              ? (_connectedDeviceName ?? 'GPS Professionale')
                              : 'GPS del telefono',
                          style: TextStyle(
                            color: kFgColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isUsingBleDevice
                                ? kBrandColor.withAlpha(25)
                                : kMutedColor.withAlpha(20),
                            border: Border.all(
                              color: isUsingBleDevice
                                  ? kBrandColor.withAlpha(80)
                                  : kMutedColor.withAlpha(60),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isUsingBleDevice
                                    ? Icons.check_circle
                                    : Icons.info_outline,
                                color: isUsingBleDevice ? kBrandColor : kMutedColor,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isUsingBleDevice
                                    ? 'Connesso • Alta precisione'
                                    : 'Precisione standard',
                                style: TextStyle(
                                  color:
                                      isUsingBleDevice ? kBrandColor : kMutedColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(8),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: isUsingBleDevice ? kBrandColor : kMutedColor,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            // Specs footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(4),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(
                    color: isUsingBleDevice
                        ? kBrandColor.withAlpha(40)
                        : _kBorderColor,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSpecBadge(
                    icon: Icons.speed,
                    label: 'Frequenza',
                    value: isUsingBleDevice ? '15 Hz' : '1 Hz',
                    color: isUsingBleDevice ? kBrandColor : kMutedColor,
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: _kBorderColor,
                  ),
                  _buildSpecBadge(
                    icon: Icons.gps_fixed,
                    label: 'Precisione',
                    value: isUsingBleDevice ? '<1 m' : '5-8 m',
                    color: isUsingBleDevice ? kBrandColor : kMutedColor,
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: _kBorderColor,
                  ),
                  _buildSpecBadge(
                    icon: Icons.satellite_alt,
                    label: 'Affidabilità',
                    value: isUsingBleDevice ? 'Alta' : 'Media',
                    color: isUsingBleDevice ? kBrandColor : kMutedColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: kMutedColor,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GpsWaitPage()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [kBrandColor, kBrandColor.withAlpha(220)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: kBrandColor.withAlpha(80),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withAlpha(30),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'Inizia Sessione',
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
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
          title.toUpperCase(),
          style: TextStyle(
            color: kMutedColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    color.withAlpha(35),
                    color.withAlpha(15),
                  ],
                ),
                border: Border.all(color: color.withAlpha(80)),
              ),
              child: Center(
                child: Icon(icon, color: color, size: 24),
              ),
            ),
            const SizedBox(height: 14),
            // Title
            Text(
              title,
              style: const TextStyle(
                color: kFgColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            // Subtitle
            Text(
              subtitle,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Arrow row
            Row(
              children: [
                Text(
                  'Apri',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, color: color, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTip() {
    final isUsingBleDevice = _connectedDeviceId != null;

    if (isUsingBleDevice) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: kBrandColor.withAlpha(12),
          border: Border.all(color: kBrandColor.withAlpha(50)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kBrandColor.withAlpha(20),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Icon(Icons.rocket_launch, color: kBrandColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pronto per la pista!',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'GPS professionale connesso. Massima precisione garantita.',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConnectDevicesPage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kBrandColor.withAlpha(60)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(30),
                    kBrandColor.withAlpha(15),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Icon(Icons.tips_and_updates, color: kBrandColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vuoi più precisione?',
                    style: TextStyle(
                      color: kFgColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Collega un GPS tracker professionale per tempi più accurati.',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, color: kBrandColor, size: 22),
          ],
        ),
      ),
    );
  }
}
