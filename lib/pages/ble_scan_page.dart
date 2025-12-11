import 'package:flutter/material.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';

class BleScanPage extends StatefulWidget {
  final Set<String> existingDeviceIds;

  const BleScanPage({super.key, this.existingDeviceIds = const {}});

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

  Future<void> _connect(String deviceId, String deviceName) async {
    final ok = await _bleService.connect(deviceId);
    if (ok && mounted) {
      Navigator.of(context).pop({'id': deviceId, 'name': deviceName});
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
      body: PulseBackground(
        withTopPadding: false,
        child: Column(
          children: [
            // Premium header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scansione dispositivi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: kFgColor,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cerca dispositivi GPS-Tracker nelle vicinanze',
                          style: TextStyle(
                            fontSize: 12,
                            color: kMutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          kBrandColor.withAlpha(40),
                          kBrandColor.withAlpha(20),
                        ],
                      ),
                      border: Border.all(color: kBrandColor, width: 1.5),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _scanning ? Icons.stop : Icons.refresh,
                        color: kBrandColor,
                        size: 22,
                      ),
                      onPressed: _scanning ? null : _startScan,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
            // Scanning indicator
            if (_scanning)
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor.withAlpha(200),
                      kBrandColor,
                      kBrandColor.withAlpha(200),
                    ],
                  ),
                ),
                child: const LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.transparent),
                  backgroundColor: Colors.transparent,
                ),
              ),
            // Body
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
                                    kPulseColor.withAlpha(40),
                                    kPulseColor.withAlpha(20),
                                  ],
                                ),
                                border: Border.all(
                                    color: kPulseColor.withAlpha(100),
                                    width: 2),
                              ),
                              child: Icon(
                                _scanning
                                    ? Icons.bluetooth_searching
                                    : Icons.bluetooth_disabled,
                                size: 48,
                                color: kPulseColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _scanning
                                  ? 'Ricerca in corso...'
                                  : 'Nessun dispositivo trovato',
                              style: const TextStyle(
                                color: kFgColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Accendi il tuo GPS-Tracker e assicurati\nche sia nelle vicinanze',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: kMutedColor, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final d = filtered[index];
                      final rssiStrength = (d.rssi ?? -100) + 100;
                      final signalQuality = rssiStrength.clamp(0, 100) / 100;
                      return Container(
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
                          border: Border.all(color: kBrandColor.withAlpha(100)),
                          boxShadow: [
                            BoxShadow(
                              color: kBrandColor.withAlpha(40),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    kBrandColor.withAlpha(40),
                                    kBrandColor.withAlpha(20),
                                  ],
                                ),
                                border:
                                    Border.all(color: kBrandColor, width: 1.5),
                              ),
                              child: const Icon(
                                Icons.bluetooth,
                                color: kBrandColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.name.isNotEmpty ? d.name : d.id,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: kFgColor,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      // Container(
                                      //   padding: const EdgeInsets.symmetric(
                                      //       horizontal: 10, vertical: 4),
                                      //   decoration: BoxDecoration(
                                      //     borderRadius: BorderRadius.circular(8),
                                      //     gradient: LinearGradient(
                                      //       colors: [
                                      //         kBrandColor.withAlpha(30),
                                      //         kBrandColor.withAlpha(20),
                                      //       ],
                                      //     ),
                                      //     border: Border.all(
                                      //       color: kBrandColor.withAlpha(100),
                                      //     ),
                                      //   ),
                                      //   child: Text(
                                      //     'RSSI: ${d.rssi ?? '-'} dBm',
                                      //     style: const TextStyle(
                                      //       color: kBrandColor,
                                      //       fontSize: 11,
                                      //       fontWeight: FontWeight.w700,
                                      //     ),
                                      //   ),
                                      // ),
                                      const SizedBox(width: 8),
                                      // Signal strength indicator
                                      ...List.generate(4, (i) {
                                        final isActive =
                                            signalQuality >= (i + 1) / 4;
                                        return Container(
                                          margin:
                                              const EdgeInsets.only(right: 2),
                                          width: 4,
                                          height: 8 + (i * 3.0),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? kBrandColor
                                                : kMutedColor.withAlpha(80),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBrandColor,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _connect(d.id, d.name),
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text(
                                'Connetti',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: filtered.length,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
