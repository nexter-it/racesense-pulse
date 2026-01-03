import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ble_tracking_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import 'ble_scan_page.dart';
import 'device_check_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class ConnectDevicesPage extends StatefulWidget {
  const ConnectDevicesPage({super.key});

  @override
  State<ConnectDevicesPage> createState() => _ConnectDevicesPageState();
}

class _ConnectDevicesPageState extends State<ConnectDevicesPage> {
  final FirestoreService _firestore = FirestoreService();
  final BleTrackingService _bleService = BleTrackingService();

  Map<String, String> _devices = {}; // Map of deviceId -> deviceName
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Avvia scan continuo per mantenere aggiornata la lista
    _bleService.startScan(
      nameFilters: const ['RS-'],
      continuous: true,
    );
    _loadDevices();
    _attemptAutoReconnect();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    final devices = await _firestore.getUserDevices(uid);
    if (mounted) {
      setState(() {
        _devices = devices;
        _loading = false;
      });
    }
  }

  Future<void> _attemptAutoReconnect() async {
    await Future.delayed(const Duration(seconds: 1));

    for (final deviceId in _devices.keys) {
      if (_bleService.isConnected(deviceId)) continue;

      final snapshot = _bleService.getSnapshot(deviceId);
      if (snapshot != null && !snapshot.isConnected) {
        _bleService.connect(deviceId, autoReconnect: true);
      }
    }
  }

  Future<void> _addDevice() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => BleScanPage(existingDeviceIds: _devices.keys.toSet()),
      ),
    );
    if (result != null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _firestore.saveUserDevice(uid, result['id']!, result['name']!);
      }
      await _loadDevices();
    }
  }

  Future<void> _deleteDevice(String deviceId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _kCardStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
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
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      kErrorColor.withAlpha(30),
                      kErrorColor.withAlpha(15),
                    ],
                  ),
                  border: Border.all(color: kErrorColor.withAlpha(60)),
                ),
                child: Icon(Icons.delete_forever, color: kErrorColor, size: 28),
              ),
              const SizedBox(height: 20),
              const Text(
                'Elimina dispositivo',
                style: TextStyle(
                  color: kFgColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sei sicuro di voler rimuovere questo dispositivo dalla lista?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withAlpha(10),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: const Center(
                          child: Text(
                            'Annulla',
                            style: TextStyle(
                              color: kMutedColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              kErrorColor.withAlpha(40),
                              kErrorColor.withAlpha(20),
                            ],
                          ),
                          border: Border.all(color: kErrorColor.withAlpha(60)),
                        ),
                        child: const Center(
                          child: Text(
                            'Elimina',
                            style: TextStyle(
                              color: kErrorColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _firestore.deleteUserDevice(uid, deviceId);
      await _loadDevices();
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
            Expanded(
              child: _loading
                  ? _buildLoadingState()
                  : StreamBuilder<Map<String, BleDeviceSnapshot>>(
                      stream: _bleService.deviceStream,
                      builder: (context, snapshot) {
                        final scans = snapshot.data ?? {};
                        if (_devices.isEmpty) {
                          return _buildEmptyState();
                        }
                        return _buildDevicesList(scans);
                      },
                    ),
            ),
            _buildAddDeviceButton(),
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
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: const Icon(Icons.arrow_back, color: kBrandColor, size: 20),
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
                  kPulseColor.withAlpha(40),
                  kPulseColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kPulseColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.bluetooth, color: kPulseColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dispositivi Tracking',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kBrandColor.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.devices, size: 11, color: kBrandColor),
                      const SizedBox(width: 4),
                      Text(
                        '${_devices.length} ${_devices.length == 1 ? 'dispositivo' : 'dispositivi'}',
                        style: TextStyle(
                          fontSize: 10,
                          color: kBrandColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
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
          Text(
            'Caricamento dispositivi...',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kBrandColor.withAlpha(30),
                    kBrandColor.withAlpha(10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kCardStart,
                  border: Border.all(color: kBrandColor.withAlpha(80), width: 2),
                ),
                child: Icon(Icons.bluetooth_disabled, color: kBrandColor, size: 32),
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
            const SizedBox(height: 10),
            Text(
              'Aggiungi un dispositivo GPS-Tracker\nper iniziare a tracciare le tue sessioni',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _addDevice,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [kBrandColor, kBrandColor.withAlpha(200)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withAlpha(60),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add, color: Colors.black, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Aggiungi dispositivo',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
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

  Widget _buildDevicesList(Map<String, BleDeviceSnapshot> scans) {
    final deviceEntries = _devices.entries.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final entry = deviceEntries[index];
        return _buildDeviceCard(entry.key, entry.value, scans[entry.key]);
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: _devices.length,
    );
  }

  Widget _buildDeviceCard(String id, String name, BleDeviceSnapshot? snap) {
    final visible = snap != null;
    final connected = snap?.isConnected ?? false;
    final rssiStrength = (snap?.rssi ?? -100) + 100;
    final signalQuality = rssiStrength.clamp(0, 100) / 100;

    return GestureDetector(
      onTap: connected
          ? () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeviceCheckPage(deviceId: id),
                ),
              );
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: connected ? kBrandColor.withAlpha(150) : _kBorderColor,
            width: connected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: connected ? kBrandColor.withAlpha(40) : Colors.black.withAlpha(60),
              blurRadius: connected ? 20 : 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
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
                        colors: connected
                            ? [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)]
                            : [Colors.white.withAlpha(15), Colors.white.withAlpha(8)],
                      ),
                      border: Border.all(
                        color: connected ? kBrandColor.withAlpha(100) : _kBorderColor,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        connected ? Icons.bluetooth_connected : Icons.bluetooth,
                        color: connected ? kBrandColor : kMutedColor,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Device info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
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
                            // Status indicator
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
                                          color: kBrandColor.withAlpha(150),
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
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Signal strength
                  if (visible)
                    Row(
                      children: List.generate(4, (i) {
                        final isActive = signalQuality >= (i + 1) / 4;
                        return Container(
                          margin: const EdgeInsets.only(right: 3),
                          width: 5,
                          height: 8 + (i * 3.5),
                          decoration: BoxDecoration(
                            color: isActive
                                ? (connected ? kBrandColor : kPulseColor)
                                : kMutedColor.withAlpha(60),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                ],
              ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        if (connected) {
                          await _bleService.disconnect(id);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Connessione in corso...'),
                              backgroundColor: kBrandColor,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          final success = await _bleService.connect(id, autoReconnect: true);
                          if (mounted) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Dispositivo connesso'),
                                  backgroundColor: kBrandColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
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
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: connected
                              ? LinearGradient(
                                  colors: [kErrorColor.withAlpha(30), kErrorColor.withAlpha(15)],
                                )
                              : LinearGradient(
                                  colors: [kBrandColor, kBrandColor.withAlpha(200)],
                                ),
                          border: connected
                              ? Border.all(color: kErrorColor.withAlpha(60))
                              : null,
                          boxShadow: connected
                              ? null
                              : [
                                  BoxShadow(
                                    color: kBrandColor.withAlpha(40),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              connected ? Icons.link_off : Icons.link,
                              color: connected ? kErrorColor : Colors.black,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              connected ? 'Disconnetti' : 'Connetti',
                              style: TextStyle(
                                color: connected ? kErrorColor : Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Secondary action button
                  GestureDetector(
                    onTap: connected
                        ? () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DeviceCheckPage(deviceId: id),
                              ),
                            );
                          }
                        : () => _deleteDevice(id),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: connected
                            ? LinearGradient(
                                colors: [kBrandColor.withAlpha(30), kBrandColor.withAlpha(15)],
                              )
                            : LinearGradient(
                                colors: [kErrorColor.withAlpha(30), kErrorColor.withAlpha(15)],
                              ),
                        border: Border.all(
                          color: connected
                              ? kBrandColor.withAlpha(60)
                              : kErrorColor.withAlpha(60),
                        ),
                      ),
                      child: Icon(
                        connected ? Icons.location_on : Icons.delete_outline,
                        color: connected ? kBrandColor : kErrorColor,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddDeviceButton() {
    if (_devices.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBgColor,
        border: const Border(
          top: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: GestureDetector(
        onTap: _addDevice,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [kBrandColor, kBrandColor.withAlpha(200)],
            ),
            boxShadow: [
              BoxShadow(
                color: kBrandColor.withAlpha(60),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.add, color: Colors.black, size: 22),
              SizedBox(width: 10),
              Text(
                'Aggiungi dispositivo',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
