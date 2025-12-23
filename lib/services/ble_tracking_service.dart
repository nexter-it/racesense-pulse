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
  BleTrackingService._internal() {
    // Inizializza listener per stato Bluetooth
    _initBluetoothStateListener();
  }
  static final BleTrackingService _instance = BleTrackingService._internal();
  factory BleTrackingService() => _instance;

  final Map<String, ScanResult> _lastScans = {};
  final Map<String, BluetoothDevice> _connected = {};
  final Map<String, BluetoothCharacteristic> _notifiers = {};
  final Map<String, GpsData> _lastGpsData = {};
  final Map<String, StreamSubscription<BluetoothConnectionState>>
      _connectionListeners = {};

  // Cache dei dispositivi scansionati per evitare che scompaiano quando lo scan si ferma
  final Map<String, BleDeviceSnapshot> _deviceCache = {};

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSub;
  Timer? _scanRestartTimer;

  late final StreamController<Map<String, BleDeviceSnapshot>> _scanController =
      StreamController.broadcast();
  late final StreamController<Map<String, GpsData>> _gpsController =
      StreamController.broadcast();

  late final Stream<Map<String, BleDeviceSnapshot>> _deviceStream =
      Stream<Map<String, BleDeviceSnapshot>>.multi(
    (controller) {
      // Un broadcast StreamController non invia automaticamente l'ultimo valore
      // ai nuovi listener: inviamo sempre lo snapshot corrente all'iscrizione.
      controller.add(_buildSnapshot());
      final sub = _scanController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () => sub.cancel();
    },
    isBroadcast: true,
  );

  late final Stream<Map<String, GpsData>> _gpsStream =
      Stream<Map<String, GpsData>>.multi(
    (controller) {
      controller.add(Map<String, GpsData>.from(_lastGpsData));
      final sub = _gpsController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () => sub.cancel();
    },
    isBroadcast: true,
  );

  bool _isScanning = false;
  bool _shouldKeepScanning = false;
  List<String>? _currentNameFilters;

  /// Stream con lo stato di tutti i dispositivi visti/collegati.
  Stream<Map<String, BleDeviceSnapshot>> get deviceStream => _deviceStream;
  Stream<Map<String, GpsData>> get gpsStream => _gpsStream;

  bool get isScanning => _isScanning;

  /// Inizializza listener per stato Bluetooth
  void _initBluetoothStateListener() {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    try {
      _bluetoothStateSub = FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on && _shouldKeepScanning) {
          // Bluetooth riattivato, riprendi scan
          _startScanInternal();
        } else if (state != BluetoothAdapterState.on) {
          // Bluetooth spento, ferma scan
          _stopScanInternal();
        }
      });
    } catch (e) {
      print('⚠️ Errore inizializzazione listener Bluetooth: $e');
    }
  }

  /// Avvia scan continuo con auto-restart
  Future<void> startScan(
      {List<String>? nameFilters, bool continuous = true}) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    _currentNameFilters = nameFilters;
    _shouldKeepScanning = continuous;

    await _startScanInternal();

    // Se richiesto scan continuo, configura auto-restart ogni 10 secondi
    if (continuous) {
      _scanRestartTimer?.cancel();
      _scanRestartTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_shouldKeepScanning && !_isScanning) {
          _startScanInternal();
        }
      });
    }
  }

  Future<void> _startScanInternal() async {
    if (_isScanning) return;

    try {
      // Ferma scan precedenti
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    try {
      _isScanning = true;

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          // Filtra per nome se specificato
          if (_currentNameFilters != null && _currentNameFilters!.isNotEmpty) {
            final match = _currentNameFilters!.any(
              (f) =>
                  r.device.platformName.startsWith(f) ||
                  r.advertisementData.advName.startsWith(f),
            );
            if (!match) continue;
          }

          _lastScans[r.device.remoteId.str] = r;

          // Aggiorna cache
          _deviceCache[r.device.remoteId.str] = BleDeviceSnapshot(
            id: r.device.remoteId.str,
            name: r.device.platformName,
            rssi: r.rssi,
            isConnected: isConnected(r.device.remoteId.str),
          );
        }
        _pushSnapshot();
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      print('✓ BLE scan avviato');
    } catch (e) {
      print('⚠️ Errore avvio scan BLE: $e');
      _isScanning = false;
      await _stopScanInternal();
    }
  }

  Future<void> _stopScanInternal() async {
    _isScanning = false;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> stopScan() async {
    _shouldKeepScanning = false;
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    await _stopScanInternal();
  }

  /// Connette a un dispositivo BLE con auto-reconnect
  Future<bool> connect(String deviceId, {bool autoReconnect = true}) async {
    // Verifica se già connesso
    if (_connected.containsKey(deviceId)) {
      final device = _connected[deviceId]!;
      final state = await device.connectionState.first;
      if (state == BluetoothConnectionState.connected) {
        print('✓ Dispositivo $deviceId già connesso');
        // Forza un refresh UI: questo ramo veniva spesso chiamato dal pulsante
        // "Connetti" quando la UI era rimasta indietro.
        _pushSnapshot();
        return true;
      }
    }

    final result = _lastScans[deviceId];
    final device = result?.device ?? BluetoothDevice.fromId(deviceId);

    try {
      // Cancella listener precedente se esiste
      await _connectionListeners[deviceId]?.cancel();

      print('🔄 Connessione a $deviceId...');

      // Prova a disconnettere prima (cleanup di connessioni zombie)
      try {
        await device.disconnect();
      } catch (_) {}

      // Connetti con timeout
      // NOTA: Non usiamo autoConnect perché incompatibile con MTU configuration
      await device.connect(
        timeout: const Duration(seconds: 10),
      );

      _connected[deviceId] = device;

      // Setup listener per stato connessione
      _connectionListeners[deviceId] = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          print('✓ Dispositivo $deviceId connesso');
          _pushSnapshot();
        } else if (state == BluetoothConnectionState.disconnected) {
          print('⚠️ Dispositivo $deviceId disconnesso');
          _connected.remove(deviceId);
          _notifiers.remove(deviceId);
          _pushSnapshot();

          // Auto-reconnect se abilitato
          if (autoReconnect && _lastScans.containsKey(deviceId)) {
            print('🔄 Tentativo auto-reconnect a $deviceId...');
            Future.delayed(const Duration(seconds: 2), () {
              connect(deviceId, autoReconnect: true);
            });
          }
        }
      });

      // Sottoscrivi a notifiche GPS
      await _subscribePosition(device);

      _pushSnapshot();
      print('✓ Connessione completata: $deviceId');

      return true;
    } catch (e) {
      print('❌ Errore connessione a $deviceId: $e');
      _connected.remove(deviceId);
      _notifiers.remove(deviceId);
      _pushSnapshot();
      return false;
    }
  }

  /// Disconnette un dispositivo BLE
  Future<void> disconnect(String deviceId) async {
    print('🔌 Disconnessione da $deviceId...');

    final device = _connected[deviceId];

    // Cancella listener
    await _connectionListeners[deviceId]?.cancel();
    _connectionListeners.remove(deviceId);

    // Disabilita notifiche
    try {
      await _notifiers[deviceId]?.setNotifyValue(false);
    } catch (_) {}
    _notifiers.remove(deviceId);

    // Disconnetti device
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }

    _connected.remove(deviceId);
    _lastGpsData.remove(deviceId);
    _pushSnapshot();

    print('✓ Disconnesso da $deviceId');
  }

  bool isConnected(String deviceId) => _connected.containsKey(deviceId);

  /// Restituisce lo snapshot di un dispositivo dalla cache o scan
  BleDeviceSnapshot? getSnapshot(String deviceId) {
    // Prova cache prima
    if (_deviceCache.containsKey(deviceId)) {
      final cached = _deviceCache[deviceId]!;
      return BleDeviceSnapshot(
        id: cached.id,
        name: cached.name,
        rssi: cached.rssi,
        isConnected: isConnected(deviceId),
      );
    }

    // Fallback su scan
    final scan = _lastScans[deviceId];
    if (scan != null) {
      return BleDeviceSnapshot(
        id: deviceId,
        name: scan.device.platformName,
        rssi: scan.rssi,
        isConnected: isConnected(deviceId),
      );
    }

    return null;
  }

  /// Ottiene tutti i dispositivi connessi
  List<String> getConnectedDeviceIds() => _connected.keys.toList();

  Future<void> _subscribePosition(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) =>
            s.serviceUuid.toString().toLowerCase() ==
            '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
        orElse: () => throw Exception('service not found'),
      );
      final characteristic = service.characteristics.firstWhere(
        (c) =>
            c.characteristicUuid.toString().toLowerCase() ==
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
    if (parts.length < 10)
      return; // Need all 10 fields: id/lat/lon/sat/fix/speed/datetime/tms/bat/sig

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
    _pushGpsSnapshot();
  }

  void _pushGpsSnapshot() {
    if (_gpsController.isClosed) return;
    _gpsController.add(Map<String, GpsData>.from(_lastGpsData));
  }

  Map<String, BleDeviceSnapshot> _buildSnapshot() {
    final map = <String, BleDeviceSnapshot>{};

    // Aggiungi dispositivi dalla cache (mantiene dispositivi visibili anche quando scan è fermo)
    for (final entry in _deviceCache.entries) {
      map[entry.key] = BleDeviceSnapshot(
        id: entry.key,
        name: entry.value.name,
        rssi: entry.value.rssi,
        isConnected: isConnected(entry.key),
      );
    }

    // Aggiungi dispositivi da scan attivo (aggiorna RSSI)
    for (final entry in _lastScans.entries) {
      map[entry.key] = BleDeviceSnapshot(
        id: entry.key,
        name: entry.value.device.platformName,
        rssi: entry.value.rssi,
        isConnected: isConnected(entry.key),
      );
    }

    // Assicurati che tutti i dispositivi connessi siano nella lista
    for (final id in _connected.keys) {
      map.putIfAbsent(
        id,
        () => BleDeviceSnapshot(
          id: id,
          // Preferisci un nome già noto (cache/scan) per non lasciare vuoto in iOS
          // quando il device è stato creato con `BluetoothDevice.fromId`.
          name: _deviceCache[id]?.name ??
              _lastScans[id]?.device.platformName ??
              _connected[id]?.platformName ??
              id,
          rssi: _lastScans[id]?.rssi,
          isConnected: true,
        ),
      );
    }

    return map;
  }

  void _pushSnapshot() {
    if (_scanController.isClosed) return;
    _scanController.add(_buildSnapshot());
  }

  Future<void> dispose() async {
    await stopScan();
    _scanRestartTimer?.cancel();
    await _bluetoothStateSub?.cancel();

    // Disconnetti tutti i dispositivi
    for (final deviceId in _connected.keys.toList()) {
      await disconnect(deviceId);
    }

    await _scanController.close();
    await _gpsController.close();
  }
}
