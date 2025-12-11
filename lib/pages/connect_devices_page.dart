import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/ble_tracking_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
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
      appBar: AppBar(
        title: const Text('Collega dispositivi'),
        backgroundColor: kBgColor,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDevice,
        label: const Text('Aggiungi dispositivo'),
        icon: const Icon(Icons.add),
        backgroundColor: kBrandColor,
      ),
      body: _loading
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
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nessun dispositivo collegato.\nAggiungine uno con il pulsante in basso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMutedColor),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [
                              Color.fromRGBO(255, 255, 255, 0.06),
                              Color.fromRGBO(255, 255, 255, 0.03),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: connected ? kBrandColor : kLineColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              connected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth_searching,
                              color: connected ? kBrandColor : kMutedColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    id,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    visible
                                        ? (connected
                                            ? 'Connesso'
                                            : 'Rilevato, non connesso')
                                        : 'Non rilevato',
                                    style: TextStyle(
                                      color: connected
                                          ? kBrandColor
                                          : (visible
                                              ? kPulseColor
                                              : kMutedColor),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (visible)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: Colors.white.withOpacity(0.05),
                                  border: Border.all(
                                      color: connected
                                          ? kBrandColor
                                          : kLineColor),
                                ),
                                child: Text(
                                  snap?.rssi != null
                                      ? 'RSSI ${snap!.rssi} dBm'
                                      : 'RSSI --',
                                  style: TextStyle(
                                    color:
                                        connected ? kBrandColor : kMutedColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    connected ? kErrorColor : kBrandColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                              onPressed: () {
                                if (connected) {
                                  _bleService.disconnect(id);
                                } else {
                                  _bleService.connect(id);
                                }
                              },
                              child: Text(
                                connected ? 'Disconnetti' : 'Connetti',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemCount: _devices.length,
                );
              },
            ),
    );
  }
}
