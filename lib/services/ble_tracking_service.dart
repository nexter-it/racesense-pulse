import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';

class BleDeviceSnapshot {
  final String id;
  final String name;
  final int? rssi;
  final bool isConnected;

  BleDeviceSnapshot({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isConnected,
  });
}

class GpsData {
  final LatLng position;
  final int? satellites;
  final int? fix;
  final double? speed;
  final int? battery;

  GpsData({
    required this.position,
    this.satellites,
    this.fix,
    this.speed,
    this.battery,
  });
}

/// Gestione BLE centralizzata, condivisa tra tutte le pagine.
class BleTrackingService {
  BleTrackingService._internal();
  static final BleTrackingService _instance = BleTrackingService._internal();
  factory BleTrackingService() => _instance;

  final Map<String, ScanResult> _lastScans = {};
  final Map<String, BluetoothDevice> _connected = {};
  final Map<String, BluetoothCharacteristic> _notifiers = {};
  final Map<String, GpsData> _lastGpsData = {};

  StreamSubscription<List<ScanResult>>? _scanSub;
  final StreamController<Map<String, BleDeviceSnapshot>> _scanController =
      StreamController.broadcast();
  final StreamController<Map<String, GpsData>> _gpsController =
      StreamController.broadcast();

  /// Stream con lo stato di tutti i dispositivi visti/collegati.
  Stream<Map<String, BleDeviceSnapshot>> get deviceStream =>
      _scanController.stream;
  Stream<Map<String, GpsData>> get gpsStream => _gpsController.stream;

  bool get isScanning => _scanSub != null;

  Future<void> startScan({List<String>? nameFilters}) async {
    // Evita chiamate su piattaforme non supportate (es. web/desktop non configurati)
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (_scanSub != null) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // ignoriamo warning "already stopped"
    }
    _lastScans.clear();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (nameFilters != null && nameFilters.isNotEmpty) {
          final match = nameFilters.any(
            (f) =>
                r.device.platformName.startsWith(f) ||
                r.advertisementData.advName.startsWith(f),
          );
          if (!match) continue;
        }
        _lastScans[r.device.remoteId.str] = r;
      }
      _pushSnapshot();
    });
    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (_) {
      // MissingPluginException o altre: chiudi lo stream e esci
      await stopScan();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // già fermato o plugin non disponibile
    }
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<bool> connect(String deviceId) async {
    final result = _lastScans[deviceId];
    final device = result?.device ?? BluetoothDevice.fromId(deviceId);

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 8));
      _connected[deviceId] = device;
      _listenConnection(deviceId, device);
      await _subscribePosition(device);
      _pushSnapshot();

      // opzionale: sottoscrivi allo stato per tenere traccia delle disconnessioni
      device.connectionState.listen((state) {
        if (state != BluetoothConnectionState.connected) {
          _connected.remove(deviceId);
          _pushSnapshot();
        }
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect(String deviceId) async {
    final device = _connected[deviceId];
    try {
      await _notifiers[deviceId]?.setNotifyValue(false);
    } catch (_) {}
    _notifiers.remove(deviceId);
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _connected.remove(deviceId);
    _pushSnapshot();
  }

  bool isConnected(String deviceId) => _connected.containsKey(deviceId);

  BleDeviceSnapshot? getSnapshot(String deviceId) {
    final scan = _lastScans[deviceId];
    return BleDeviceSnapshot(
      id: deviceId,
      name: scan?.device.platformName ?? deviceId,
      rssi: scan?.rssi,
      isConnected: isConnected(deviceId),
    );
  }

  void _listenConnection(String id, BluetoothDevice device) {
    device.connectionState.listen((state) {
      if (state != BluetoothConnectionState.connected) {
        _connected.remove(id);
        _notifiers.remove(id);
        _pushSnapshot();
      }
    });
  }

  Future<void> _subscribePosition(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid.toString().toLowerCase() ==
            '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
        orElse: () => throw Exception('service not found'),
      );
      final characteristic = service.characteristics.firstWhere(
        (c) => c.characteristicUuid.toString().toLowerCase() ==
            'beb5483e-36e1-4688-b7f5-ea07361b26a8',
        orElse: () => throw Exception('char not found'),
      );
      _notifiers[device.remoteId.str] = characteristic;
      await characteristic.setNotifyValue(true);
      characteristic.lastValueStream.listen((event) {
        final text = utf8.decode(event, allowMalformed: true);
        _parsePosition(device.remoteId.str, text);
      });
    } catch (_) {
      // ignora se non trova il servizio
    }
  }

  void _parsePosition(String deviceId, String text) {
    final parts = text.split('/');
    if (parts.length < 10) return; // Need all 10 fields: id/lat/lon/sat/fix/speed/datetime/tms/bat/sig

    final lat = double.tryParse(parts[1].replaceAll('+', ''));
    final lon = double.tryParse(parts[2].replaceAll('+', ''));
    if (lat == null || lon == null) return;

    final sat = int.tryParse(parts[3]);
    final fix = int.tryParse(parts[4]);
    final speed = double.tryParse(parts[5]);
    final bat = int.tryParse(parts[8]);

    final gpsData = GpsData(
      position: LatLng(lat, lon),
      satellites: sat,
      fix: fix,
      speed: speed,
      battery: bat,
    );

    _lastGpsData[deviceId] = gpsData;
    _gpsController.add(Map<String, GpsData>.from(_lastGpsData));
  }

  void _pushSnapshot() {
    final map = <String, BleDeviceSnapshot>{};
    for (final entry in _lastScans.entries) {
      map[entry.key] = BleDeviceSnapshot(
        id: entry.key,
        name: entry.value.device.platformName,
        rssi: entry.value.rssi,
        isConnected: isConnected(entry.key),
      );
    }
    for (final id in _connected.keys) {
      map.putIfAbsent(
          id,
          () => BleDeviceSnapshot(
                id: id,
                name: _connected[id]?.platformName ?? id,
                rssi: null,
                isConnected: true,
              ));
    }
    _scanController.add(map);
  }

  Future<void> dispose() async {
    await stopScan();
    await _scanController.close();
  }
}
