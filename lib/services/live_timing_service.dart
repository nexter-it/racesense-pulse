import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../models/live_driver_model.dart';
import '../models/live_race_model.dart';

/// Servizio per la gestione dei dati live da Firebase Realtime Database
class LiveTimingService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  StreamSubscription<DatabaseEvent>? _raceSubscription;
  StreamSubscription<DatabaseEvent>? _driverSubscription;

  final _raceController = StreamController<LiveRaceModel?>.broadcast();
  final _driverController = StreamController<LiveDriverModel?>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Stream per i dati della gara
  Stream<LiveRaceModel?> get raceStream => _raceController.stream;

  /// Stream per i dati del driver
  Stream<LiveDriverModel?> get driverStream => _driverController.stream;

  /// Stream per lo stato della connessione
  Stream<bool> get connectionStream => _connectionController.stream;

  LiveRaceModel? _lastRaceData;
  LiveDriverModel? _lastDriverData;
  bool _isConnected = false;
  bool _disposed = false;

  LiveRaceModel? get lastRaceData => _lastRaceData;
  LiveDriverModel? get lastDriverData => _lastDriverData;
  bool get isConnected => _isConnected;

  /// Normalizza un device ID per Firebase
  /// Input: "043758187A5F" o "04:37:58:18:7A:5F" o "04-37-58-18-7A-5F"
  /// Output: "043758187A5F" (12 caratteri hex uppercase, senza separatori)
  String _toFirebaseKey(String deviceId) {
    // Rimuove eventuali separatori (: o -) e converte in uppercase
    return deviceId.replaceAll(':', '').replaceAll('-', '').toUpperCase();
  }

  /// Inizia ad ascoltare i dati di un driver specifico
  Future<void> startListening(String deviceId) async {
    await stopListening();

    final firebaseKey = _toFirebaseKey(deviceId);
    // print('🔴 [LiveTiming] Avvio ascolto per device: $deviceId -> Firebase key: $firebaseKey');

    // Ascolta i dati della gara
    final raceRef = _database.ref('live/race');
    // print('🔴 [LiveTiming] Sottoscrizione a: live/race');

    _raceSubscription = raceRef.onValue.listen(
      (event) {
        if (_disposed) return;
        // print('🔴 [LiveTiming] Evento race ricevuto - exists: ${event.snapshot.exists}');
        if (event.snapshot.exists && event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          // print('🔴 [LiveTiming] Race status: ${data['status']}');
          _lastRaceData = LiveRaceModel.fromMap(data);
          if (!_disposed) _raceController.add(_lastRaceData);
          _updateConnectionStatus(true);
        } else {
          // print('🔴 [LiveTiming] Nessun dato race');
          _lastRaceData = null;
          if (!_disposed) _raceController.add(null);
          _updateConnectionStatus(false);
        }
      },
      onError: (error) {
        if (_disposed) return;
        // print('🔴 [LiveTiming] ERRORE race stream: $error');
        if (!_disposed) _raceController.addError(error);
        _updateConnectionStatus(false);
      },
    );

    // Ascolta i dati del driver specifico
    final driverPath = 'live/drivers/$firebaseKey';
    final driverRef = _database.ref(driverPath);
    // print('🔴 [LiveTiming] Sottoscrizione a: $driverPath');

    _driverSubscription = driverRef.onValue.listen(
      (event) {
        if (_disposed) return;
        // print('🔴 [LiveTiming] Evento driver ricevuto - exists: ${event.snapshot.exists}');
        if (event.snapshot.exists && event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          // print('🔴 [LiveTiming] Driver: ${data['fullName']}, lap: ${data['lapCount']}');
          _lastDriverData = LiveDriverModel.fromMap(data);
          if (!_disposed) _driverController.add(_lastDriverData);
          _updateConnectionStatus(true);
        } else {
          // print('🔴 [LiveTiming] Nessun dato driver per $firebaseKey');
          _lastDriverData = null;
          if (!_disposed) _driverController.add(null);
        }
      },
      onError: (error) {
        if (_disposed) return;
        // print('🔴 [LiveTiming] ERRORE driver stream: $error');
        if (!_disposed) _driverController.addError(error);
      },
    );
  }

  /// Verifica se esiste una gara attiva
  Future<bool> checkRaceExists() async {
    // print('🔴 [LiveTiming] Verifica esistenza gara...');
    try {
      final snapshot = await _database.ref('live').get();
      // print('🔴 [LiveTiming] Gara exists: ${snapshot.exists}');
      return snapshot.exists;
    } catch (e) {
      // print('🔴 [LiveTiming] ERRORE verifica gara: $e');
      rethrow;
    }
  }

  /// Verifica se esiste un driver con l'ID specificato
  Future<bool> checkDriverExists(String deviceId) async {
    final firebaseKey = _toFirebaseKey(deviceId);
    // print('🔴 [LiveTiming] Verifica esistenza driver: $firebaseKey');
    try {
      final snapshot = await _database.ref('live/drivers/$firebaseKey').get();
      // print('🔴 [LiveTiming] Driver exists: ${snapshot.exists}');
      return snapshot.exists;
    } catch (e) {
      // print('🔴 [LiveTiming] ERRORE verifica driver: $e');
      rethrow;
    }
  }

  /// Ottiene i dati attuali della gara (one-shot)
  Future<LiveRaceModel?> getRaceData() async {
    // print('🔴 [LiveTiming] Fetch one-shot race data...');
    try {
      final snapshot = await _database.ref('live/race').get();
      if (snapshot.exists && snapshot.value != null) {
        // print('🔴 [LiveTiming] Race data ottenuti');
        return LiveRaceModel.fromMap(snapshot.value as Map<dynamic, dynamic>);
      }
      // print('🔴 [LiveTiming] Nessun race data');
      return null;
    } catch (e) {
      // print('🔴 [LiveTiming] ERRORE fetch race: $e');
      rethrow;
    }
  }

  /// Ottiene i dati attuali del driver (one-shot)
  Future<LiveDriverModel?> getDriverData(String deviceId) async {
    final firebaseKey = _toFirebaseKey(deviceId);
    // print('🔴 [LiveTiming] Fetch one-shot driver data: $firebaseKey');
    try {
      final snapshot = await _database.ref('live/drivers/$firebaseKey').get();
      if (snapshot.exists && snapshot.value != null) {
        // print('🔴 [LiveTiming] Driver data ottenuti');
        return LiveDriverModel.fromMap(snapshot.value as Map<dynamic, dynamic>);
      }
      // print('🔴 [LiveTiming] Nessun driver data');
      return null;
    } catch (e) {
      // print('🔴 [LiveTiming] ERRORE fetch driver: $e');
      rethrow;
    }
  }

  void _updateConnectionStatus(bool connected) {
    if (_disposed) return;
    if (_isConnected != connected) {
      // print('🔴 [LiveTiming] Connessione: $connected');
      _isConnected = connected;
      if (!_disposed) _connectionController.add(connected);
    }
  }

  /// Ferma l'ascolto
  Future<void> stopListening() async {
    // print('🔴 [LiveTiming] Stop listening');
    await _raceSubscription?.cancel();
    await _driverSubscription?.cancel();
    _raceSubscription = null;
    _driverSubscription = null;
    _lastRaceData = null;
    _lastDriverData = null;
    _updateConnectionStatus(false);
  }

  /// Pulisce le risorse
  void dispose() {
    // print('🔴 [LiveTiming] Dispose');
    _disposed = true;
    _raceSubscription?.cancel();
    _driverSubscription?.cancel();
    _raceSubscription = null;
    _driverSubscription = null;
    _raceController.close();
    _driverController.close();
    _connectionController.close();
  }
}
