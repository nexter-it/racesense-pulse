import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/ble_tracking_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import 'ble_scan_page.dart';
import 'device_check_page.dart';

class ConnectDevicesPage extends StatefulWidget {
  const ConnectDevicesPage({super.key});

  @override
  State<ConnectDevicesPage> createState() => _ConnectDevicesPageState();
}

class _ConnectDevicesPageState extends State<ConnectDevicesPage> {
  final FirestoreService _firestore = FirestoreService();
  final BleTrackingService _bleService = BleTrackingService();

  List<String> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bleService.startScan(nameFilters: const ['GPS-Tracker-']);
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    final list = await _firestore.getUserDevices(uid);
    if (mounted) {
      setState(() {
        _devices = list;
        _loading = false;
      });
    }
  }

  Future<void> _addDevice() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BleScanPage(),
      ),
    );
    if (id != null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _firestore.saveUserDevice(uid, id);
      }
      await _loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PulseBackground(
        withTopPadding: false,
        child: Column(
          children: [
            // Premium header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: kLineColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: kFgColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Dispositivi tracking',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kFgColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(kBrandColor),
                      ),
                    )
                  : StreamBuilder<Map<String, BleDeviceSnapshot>>(
                      stream: _bleService.deviceStream,
                      builder: (context, snapshot) {
                        final scans = snapshot.data ?? {};
                        if (_devices.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          kBrandColor.withAlpha(40),
                                          kBrandColor.withAlpha(20),
                                        ],
                                      ),
                                      border: Border.all(color: kBrandColor.withAlpha(100), width: 2),
                                    ),
                                    child: const Icon(
                                      Icons.bluetooth_disabled,
                                      size: 48,
                                      color: kBrandColor,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'Nessun dispositivo collegato',
                                    style: TextStyle(
                                      color: kFgColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Aggiungi un dispositivo GPS-Tracker\nper iniziare a tracciare le tue sessioni',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: kMutedColor, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final id = _devices[index];
                            final snap = scans[id];
                            final visible = snap != null;
                            final connected = snap?.isConnected ?? false;
                            return InkWell(
                              onTap: connected
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => DeviceCheckPage(deviceId: id),
                                        ),
                                      )
                                  : null,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color.fromRGBO(255, 255, 255, 0.08),
                                      const Color.fromRGBO(255, 255, 255, 0.04),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(
                                    color: connected ? kBrandColor : kLineColor,
                                    width: connected ? 2 : 1,
                                  ),
                                  boxShadow: connected
                                      ? [
                                          BoxShadow(
                                            color: kBrandColor.withAlpha(60),
                                            blurRadius: 16,
                                            spreadRadius: 0,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: connected
                                                  ? [
                                                      kBrandColor.withAlpha(40),
                                                      kBrandColor.withAlpha(20),
                                                    ]
                                                  : [
                                                      Colors.white.withAlpha(20),
                                                      Colors.white.withAlpha(10),
                                                    ],
                                            ),
                                            border: Border.all(
                                              color: connected ? kBrandColor : kLineColor,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Icon(
                                            connected
                                                ? Icons.bluetooth_connected
                                                : Icons.bluetooth_searching,
                                            color: connected ? kBrandColor : kMutedColor,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                id,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16,
                                                  color: kFgColor,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: connected
                                                          ? kBrandColor
                                                          : (visible ? kPulseColor : kMutedColor),
                                                      boxShadow: connected
                                                          ? [
                                                              BoxShadow(
                                                                color: kBrandColor.withAlpha(128),
                                                                blurRadius: 8,
                                                                spreadRadius: 2,
                                                              ),
                                                            ]
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    visible
                                                        ? (connected ? 'Connesso' : 'Rilevato')
                                                        : 'Non rilevato',
                                                    style: TextStyle(
                                                      color: connected
                                                          ? kBrandColor
                                                          : (visible ? kPulseColor : kMutedColor),
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (visible)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              gradient: LinearGradient(
                                                colors: connected
                                                    ? [
                                                        kBrandColor.withAlpha(30),
                                                        kBrandColor.withAlpha(20),
                                                      ]
                                                    : [
                                                        Colors.white.withAlpha(15),
                                                        Colors.white.withAlpha(8),
                                                      ],
                                              ),
                                              border: Border.all(
                                                color: connected
                                                    ? kBrandColor.withAlpha(100)
                                                    : kLineColor,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  snap.rssi != null ? '${snap.rssi}' : '--',
                                                  style: TextStyle(
                                                    color: connected ? kBrandColor : kFgColor,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                Text(
                                                  'dBm',
                                                  style: TextStyle(
                                                    color: connected
                                                        ? kBrandColor.withAlpha(180)
                                                        : kMutedColor,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  connected ? kErrorColor : kBrandColor,
                                              foregroundColor:
                                                  connected ? Colors.white : Colors.black,
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: () {
                                              if (connected) {
                                                _bleService.disconnect(id);
                                              } else {
                                                _bleService.connect(id);
                                              }
                                            },
                                            icon: Icon(
                                              connected ? Icons.link_off : Icons.link,
                                              size: 18,
                                            ),
                                            label: Text(
                                              connected ? 'Disconnetti' : 'Connetti',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (connected) ...[
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: kBrandColor,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 14),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    DeviceCheckPage(deviceId: id),
                                              ),
                                            ),
                                            child: const Icon(Icons.location_on, size: 20),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemCount: _devices.length,
                        );
                      },
                    ),
            ),
            // Premium floating action button at bottom
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: kLineColor, width: 1),
                ),
              ),
              child: ElevatedButton.icon(
                onPressed: _addDevice,
                icon: const Icon(Icons.add, size: 22),
                label: const Text(
                  'Aggiungi dispositivo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
