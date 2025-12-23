import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_tracking_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import 'connect_devices_page.dart';
import 'custom_circuits_page.dart';
import 'gps_wait_page.dart';

class NewPostPage extends StatefulWidget {
  static const routeName = '/new';

  const NewPostPage({super.key});

  @override
  State<NewPostPage> createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage> {
  final BleTrackingService _bleService = BleTrackingService();
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceSub;

  @override
  void initState() {
    super.initState();
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
  }

  @override
  void dispose() {
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
    // Ascolta lo stream dei dispositivi per trovare quello connesso
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

    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // HEADER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Nuova attività',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                const PulseChip(
                  label: Text('AUTO LAP'),
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
          ),

          // BODY
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CARD 1 — Sorgente Tracking
                    _buildTrackingSourceCard(isUsingBleDevice),

                    const SizedBox(height: 18),

                    // MAIN BUTTON — Inizia Registrazione
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GpsWaitPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_circle_outline, size: 24),
                        label: const Text(
                          'Inizia sessione',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // CUSTOM CIRCUITS
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CustomCircuitsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.alt_route_outlined, size: 22),
                        label: const Text(
                          'Circuiti Custom',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kBrandColor,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          side: const BorderSide(color: kBrandColor, width: 2),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingSourceCard(bool isUsingBleDevice) {
    if (isUsingBleDevice) {
      // Card per dispositivo BLE connesso
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              kBrandColor.withAlpha(30),
              kBrandColor.withAlpha(15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kBrandColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: kBrandColor.withAlpha(60),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(60),
                        kBrandColor.withAlpha(40),
                      ],
                    ),
                    border: Border.all(color: kBrandColor, width: 2),
                  ),
                  child: const Icon(
                    Icons.bluetooth_connected,
                    color: kBrandColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sorgente tracking',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _connectedDeviceName ?? _connectedDeviceId ?? '',
                        style: const TextStyle(
                          color: kFgColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConnectDevicesPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings, color: kBrandColor),
                  tooltip: 'Gestisci dispositivi',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.black.withAlpha(80),
                border: Border.all(
                  color: kBrandColor.withAlpha(100),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.speed,
                          label: 'Frequenza',
                          value: '15 Hz',
                          color: kBrandColor,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: kLineColor,
                      ),
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.my_location,
                          label: 'Precisione',
                          value: '<1 m',
                          color: kBrandColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.satellite_alt,
                          label: 'Affidabilità',
                          value: 'Alta',
                          color: kBrandColor,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: kLineColor,
                      ),
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.timer,
                          label: 'Latenza',
                          value: '<50 ms',
                          color: kBrandColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: kBrandColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'GPS professionale ad alta precisione pronto',
                    style: TextStyle(
                      color: kFgColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Card per GPS del cellulare
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1C1C1E),
              const Color(0xFF151515),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kLineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 12,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kMutedColor.withAlpha(40),
                    border: Border.all(color: kLineColor, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.phone_iphone,
                    color: kMutedColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sorgente tracking',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'GPS del cellulare',
                        style: TextStyle(
                          color: kFgColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF0f1116),
                border: Border.all(color: kLineColor),
              ),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.speed,
                          label: 'Frequenza',
                          value: '1 Hz',
                          color: kMutedColor,
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: VerticalDivider(
                          color: kLineColor,
                          width: 1,
                          thickness: 1,
                        ),
                      ),
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.my_location,
                          label: 'Precisione',
                          value: '5-8 m',
                          color: kMutedColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.satellite_alt,
                          label: 'Affidabilità',
                          value: 'Media',
                          color: kMutedColor,
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: VerticalDivider(
                          color: kLineColor,
                          width: 1,
                          thickness: 1,
                        ),
                      ),
                      Expanded(
                        child: _SpecItem(
                          icon: Icons.sensors,
                          label: 'IMU',
                          value: 'Attivo',
                          color: kMutedColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: kBrandColor.withAlpha(20),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: kBrandColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Per migliori prestazioni, collega un dispositivo GPS esterno',
                      style: TextStyle(
                        color: kFgColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConnectDevicesPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.bluetooth_searching, size: 18),
                label: const Text(
                  'Collega dispositivo tracking',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kBrandColor,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: const BorderSide(color: kBrandColor, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _SpecItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: kMutedColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
