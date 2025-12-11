import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';

class BleScanPage extends StatefulWidget {
  const BleScanPage({super.key});

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> {
  final BleTrackingService _bleService = BleTrackingService();
  bool _scanning = false;

  static const _targetPrefix = 'GPS-Tracker-';

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    // Lascia lo scan attivo solo se ci sono altre pagine che ascoltano; qui lo fermiamo.
    _bleService.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _scanning = true);
    await _bleService.startScan(nameFilters: const [_targetPrefix]);
    setState(() => _scanning = false);
  }

  Future<void> _connect(String deviceId) async {
    final ok = await _bleService.connect(deviceId);
    if (ok && mounted) {
      Navigator.of(context).pop(deviceId);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connessione fallita'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scansione BLE'),
        backgroundColor: kBgColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning)
            const LinearProgressIndicator(
              minHeight: 2,
              valueColor: AlwaysStoppedAnimation(kBrandColor),
            ),
          Expanded(
            child: StreamBuilder<Map<String, BleDeviceSnapshot>>(
              stream: _bleService.deviceStream,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? {};
                final filtered = devices.values
                    .where((d) =>
                        d.name.startsWith(_targetPrefix) ||
                        d.id.startsWith(_targetPrefix))
                    .toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nessun dispositivo GPS-Tracker-F10N trovato.\nAccendilo e riprova.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMutedColor),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final d = filtered[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color.fromRGBO(255, 255, 255, 0.04),
                        border: Border.all(color: kLineColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bluetooth, color: kBrandColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name.isNotEmpty ? d.name : d.id,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'RSSI: ${d.rssi ?? '-'}',
                                  style: const TextStyle(
                                    color: kMutedColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _connect(d.id),
                            child: const Text('Connetti'),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemCount: filtered.length,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
