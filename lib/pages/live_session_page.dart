import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../widgets/pulse_background.dart';
import '../services/ble_tracking_service.dart';
import 'session_recap_page.dart';

// Helper class per risultato intersezione segmenti
class _IntersectionResult {
  final double t; // Parametro lungo il primo segmento (traiettoria GPS)
  final double u; // Parametro lungo il secondo segmento (linea finish)

  _IntersectionResult({required this.t, required this.u});
}

class LiveSessionPage extends StatefulWidget {
  final TrackDefinition? trackDefinition;

  const LiveSessionPage({super.key, this.trackDefinition});

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> {
  // 🔧 Toggle simulatore GPS (true = usa simulatore, false = usa GPS reale)
  static const bool _useGpsSimulator = false;

  // 🗺️ Toggle mappa visibile (true = mostra mappa, false = solo dashboard)
  static const bool _viewMap = false; // Abilita solo per test

  // Stato sessione
  bool _recording = true;
  bool _sessionFinished = false;

  // Timer
  final Stopwatch _sessionWatch = Stopwatch();
  Timer? _uiTimer;

  // Dati GPS (per disegno / recap)
  final List<Position> _gpsTrack = [];
  List<LatLng> _smoothPath = [];
  Position? _lastGpsPos;

  // Sistema di coordinate locali (metri)
  double? _originLat;
  double? _originLon;
  double? _metersPerDegLat;
  double? _metersPerDegLon;

  // Traccia locale per detection (metri, smoothed)
  Offset? _lastLocalSmoothed;
  Duration? _lastSampleTime;

  // Finish line (lat/lon + locale in metri)
  Position? _finishLineStart;
  Position? _finishLineEnd;
  Offset? _finishLineStartLocal;
  Offset? _finishLineEndLocal;
  bool _finishLineConfiguredFromTrack = false;

  // Parametri "gate" del traguardo (in metri, in coordinate locali)
  Offset?
      _finishDirUnit; // Versore lungo la linea di arrivo (ORA radiale verso il centro)
  Offset? _finishNormalUnit; // Versore normale (per distanza firmata)
  double _finishLength = 0.0; // Lunghezza del segmento di arrivo originario

  // Larghezza metà-gate (perpendicolare alla linea) in metri
  // Ampiato per tollerare campionamenti lenti (1-5 Hz) a velocità elevate.
  final double _gateHalfWidth = 25.0; // es. ±25m dalla linea
  // Estensione lungo la linea oltre il segmento base (metri)
  final double _gateHalfLength = 70.0; // es. 70m prima e 70m dopo

  // Dati giri
  final List<Duration> _laps = [];
  Duration _lastLapMark = Duration.zero;
  Duration? _bestLap;
  Duration? _previousLap;

  // Dati real-time per UI
  double _currentSpeedKph = 0.0;
  double _gForceX = 0.0;
  double _gForceY = 0.0;
  double _gForceMagnitude = 1.0;
  String _gpsStatus = 'Inizializzazione GPS...';
  double? _prevSpeedMs;

  // Dati storici per grafici
  final List<double> _speedHistory = [];
  final List<double> _gForceHistory = []; // fused accel/decel (g)
  final List<double> _gpsAccuracyHistory = [];
  final List<Duration> _timeHistory = [];
  final List<_ImuSample> _imuBuffer = [];

  // Subscriptions
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSub;

  // BLE GPS tracking
  final BleTrackingService _bleService = BleTrackingService();
  String? _connectedBleDeviceId;
  bool _isUsingBleGps = false;

  // 🔁 Timer simulatore GPS
  Timer? _simTimer;
  double _simAngleRad = 0.0;
  Offset? _simLastLocal;
  DateTime? _simLastTime;

  // Mappa
  final MapController _mapController = MapController();
  double _currentZoom = 18.0;

  // Colori stile RaceChrono
  static const Color _rcBlue = Color(0xFF0044FF);
  static const Color _rcGreen = Color(0xFF00B050);

  // Formatta lap in stile "1:36.9"
  String _formatLapBig(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100; // 0..9
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  // Delta stile "+0.3" / "-0.1"
  String _formatDeltaBig() {
    if (_previousLap == null || _bestLap == null) return '---';

    final diffSeconds =
        (_previousLap!.inMilliseconds - _bestLap!.inMilliseconds) / 1000.0;
    final sign = diffSeconds > 0 ? '+' : '';
    return '$sign${diffSeconds.toStringAsFixed(1)}';
  }

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _stopAllStreams();
    _sessionWatch.stop();
    _uiTimer?.cancel();
    super.dispose();
  }

  // Punto del tracciato simulato in coordinate locali (metri)
  // angle: angolo corrente nel giro [0, 2π)
  // lapIndex: indice del giro (0,1,2,...) per variare leggermente la traiettoria
  Offset _simulateTrackPoint(double angle, int lapIndex) {
    const double baseRadius = 80.0; // raggio medio del circuito

    // Piccola variazione di raggio per giro (±4m al massimo, periodica ogni 5 giri)
    final int patternIndex = lapIndex % 5; // 0..4
    final double radialOffset = (patternIndex - 2) * 2.0; // -4, -2, 0, 2, 4

    final double radius = baseRadius + radialOffset;

    // Direzione radiale (dal centro verso l'esterno)
    final Offset radialDir = Offset(math.cos(angle), math.sin(angle));

    // Direzione normale (per chicane/laterali)
    final Offset normalDir = Offset(-math.sin(angle), math.cos(angle));

    // Chicane: offset laterale sinusoidale (max ±12m) diverso per giro
    final double chicaneAmp = 12.0;
    final double chicaneFreq = 2.0; // 2 "onde" per giro
    final double lapPhase = lapIndex * 0.7; // fase diversa per ogni giro
    final double chicaneOffset =
        chicaneAmp * math.sin(chicaneFreq * angle + lapPhase);

    // Punto finale = raggio variato + chicane laterale
    final Offset basePoint = radialDir * radius;
    final Offset chicane = normalDir * chicaneOffset;

    return basePoint + chicane;
  }

  // ============================================================
  // INIZIO SESSIONE
  // ============================================================
  void _startSession() {
    _sessionWatch.start();

    // Timer UI per aggiornare il cronometro
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _recording) {
        setState(() {});
      }
    });

    // Controlla se c'è un dispositivo BLE GPS connesso
    _checkBleGpsDevice();

    // GPS: usa simulatore, BLE (se disponibile), o GPS cellulare
    if (_useGpsSimulator) {
      _startGpsSimulator();
    } else if (_isUsingBleGps) {
      _startBleGpsStream();
    } else {
      _startGpsStream();
    }

    // Inizio IMU stream (solo per G-force display)
    _startImuStream();
  }

  void _checkBleGpsDevice() {
    // Verifica se c'è un dispositivo BLE connesso
    _bleService.deviceStream.listen((devices) {
      final connected = devices.values.firstWhere(
        (d) => d.isConnected,
        orElse: () => BleDeviceSnapshot(
          id: '',
          name: '',
          rssi: null,
          isConnected: false,
        ),
      );

      if (connected.isConnected && !_isUsingBleGps) {
        // Dispositivo BLE trovato, passa all'uso del GPS BLE
        setState(() {
          _connectedBleDeviceId = connected.id;
          _isUsingBleGps = true;
        });
        // Ferma il GPS cellulare e inizia quello BLE
        _gpsSub?.cancel();
        _startBleGpsStream();
      } else if (!connected.isConnected && _isUsingBleGps) {
        // Dispositivo BLE disconnesso, torna al GPS cellulare
        setState(() {
          _connectedBleDeviceId = null;
          _isUsingBleGps = false;
        });
        // Ferma il GPS BLE e inizia quello cellulare
        _bleGpsSub?.cancel();
        if (!_useGpsSimulator) {
          _startGpsStream();
        }
      }
    });
  }

  void _startGpsStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onGpsData,
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _gpsStatus = 'Errore GPS: $e';
        });
      },
    );
  }

  void _startBleGpsStream() {
    _bleGpsSub?.cancel();
    _bleGpsSub = _bleService.gpsStream.listen((gpsDataMap) {
      if (_connectedBleDeviceId != null) {
        final gpsData = gpsDataMap[_connectedBleDeviceId!];
        if (gpsData != null) {
          // Converti GpsData BLE in Position per compatibilità
          final position = _bleGpsDataToPosition(gpsData);
          _onGpsData(position);
        }
      }
    });
  }

  Position _bleGpsDataToPosition(GpsData gpsData) {
    return Position(
      longitude: gpsData.position.longitude,
      latitude: gpsData.position.latitude,
      timestamp: DateTime.now(),
      accuracy: _calculateAccuracyFromFix(gpsData.fix, gpsData.satellites),
      altitude: 0.0,
      altitudeAccuracy: 3.0,
      heading: 0.0,
      headingAccuracy: 1.0,
      speed: gpsData.speed ?? 0.0,
      speedAccuracy: 0.5,
      floor: null,
      isMocked: false,
    );
  }

  double _calculateAccuracyFromFix(int? fix, int? satellites) {
    // Stima l'accuratezza in base al fix e ai satelliti
    // Fix 0 = no fix, Fix 1 = GPS fix, Fix 2+ = differenziale/RTK
    if (fix == null || fix == 0) return 50.0;
    if (satellites == null || satellites < 4) return 30.0;

    // Con GPS BLE a 15Hz e buon fix, l'accuratezza è molto migliore
    if (fix >= 2 && satellites >= 10) return 1.0; // RTK/Differenziale
    if (satellites >= 8) return 2.5;
    if (satellites >= 6) return 5.0;
    return 10.0;
  }

  // ============================================================
  // SIMULATORE GPS
  // ============================================================
  void _initLocalOriginForSimulatorIfNeeded() {
    if (_originLat != null &&
        _originLon != null &&
        _metersPerDegLat != null &&
        _metersPerDegLon != null) {
      return;
    }

    // Punto di origine (stessa zona della mappa iniziale)
    _originLat = 41.9028; // Roma
    _originLon = 12.4964;

    final latRad = _originLat! * math.pi / 180.0;

    _metersPerDegLat = 111132.92 -
        559.82 * math.cos(2 * latRad) +
        1.175 * math.cos(4 * latRad) -
        0.0023 * math.cos(6 * latRad);

    _metersPerDegLon = 111412.84 * math.cos(latRad) -
        93.5 * math.cos(3 * latRad) +
        0.118 * math.cos(5 * latRad);
  }

  LatLng _localToLatLng(Offset local) {
    if (_originLat == null ||
        _originLon == null ||
        _metersPerDegLat == null ||
        _metersPerDegLon == null) {
      // fallback (non dovrebbe succedere col simulatore)
      return const LatLng(41.9028, 12.4964);
    }

    final dLat = local.dy / _metersPerDegLat!;
    final dLon = local.dx / _metersPerDegLon!;

    return LatLng(_originLat! + dLat, _originLon! + dLon);
  }

  void _startGpsSimulator() {
    _initLocalOriginForSimulatorIfNeeded();

    // Parametri temporali del simulatore
    const double lapTimeSeconds = 40.0; // tempo giro simulato
    const double dtSeconds = 0.2; // step temporale simulazione (5 Hz)
    final double angularVel = 2 * math.pi / lapTimeSeconds; // rad/s

    _simTimer?.cancel();
    _simAngleRad = 0.0;
    _simLastLocal = null;
    _simLastTime = null;

    _simTimer = Timer.periodic(
      Duration(milliseconds: (dtSeconds * 1000).round()),
      (_) {
        final now = DateTime.now();

        // Avanza "angolo totale" (include tutti i giri)
        _simAngleRad += angularVel * dtSeconds;

        // Angolo relativo nel giro corrente
        final double twoPi = 2 * math.pi;
        final double lapAngle = _simAngleRad % twoPi;

        // Indice del giro (0,1,2,...) per variare la traiettoria
        final int lapIndex = (_simAngleRad / twoPi).floor();

        // Posizione locale "tipo circuito" con variazioni per giro
        final Offset local = _simulateTrackPoint(lapAngle, lapIndex);

        // Calcolo velocità approssimata
        double speedMs = 0.0;
        if (_simLastLocal != null && _simLastTime != null) {
          final dx = local.dx - _simLastLocal!.dx;
          final dy = local.dy - _simLastLocal!.dy;
          final dist = math.sqrt(dx * dx + dy * dy);
          final dt = now.difference(_simLastTime!).inMilliseconds / 1000.0;
          if (dt > 0) {
            speedMs = dist / dt;
          }
        }

        _simLastLocal = local;
        _simLastTime = now;

        // Conversione in lat/lon
        final latLng = _localToLatLng(local);

        // Position finta
        final simulatedPos = Position(
          longitude: latLng.longitude,
          latitude: latLng.latitude,
          timestamp: now,
          accuracy: 3.0,
          altitude: 0.0,
          altitudeAccuracy: 3.0,
          heading: 0.0,
          headingAccuracy: 1.0,
          speed: speedMs,
          speedAccuracy: 0.5,
          floor: null,
          isMocked: true,
        );

        _onGpsData(simulatedPos);
      },
    );
  }

  void _startImuStream() {
    // Leggi accelerometro per G-force (solo display)
    _accelSub =
        userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      if (!mounted || !_recording) return;

      final now = DateTime.now();
      final sample = _ImuSample(
        now,
        event.x,
        event.y,
        event.z,
      );
      _imuBuffer.add(sample);
      if (_imuBuffer.length > 500) {
        _imuBuffer.removeRange(0, _imuBuffer.length - 400);
      }

      final mag =
          math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      setState(() {
        _gForceX = event.x / 9.81;
        _gForceY = event.y / 9.81;
        _gForceMagnitude = mag / 9.81;
      });
    });
  }

  // ============================================================
  // SISTEMA DI COORDINATE LOCALI (metri)
  // ============================================================
  void _initLocalOriginIfNeeded(Position pos) {
    if (_originLat != null && _originLon != null) return;

    _originLat = pos.latitude;
    _originLon = pos.longitude;

    final latRad = _originLat! * math.pi / 180.0;

    // Approssimazione standard per metri per grado
    _metersPerDegLat = 111132.92 -
        559.82 * math.cos(2 * latRad) +
        1.175 * math.cos(4 * latRad) -
        0.0023 * math.cos(6 * latRad);

    _metersPerDegLon = 111412.84 * math.cos(latRad) -
        93.5 * math.cos(3 * latRad) +
        0.118 * math.cos(5 * latRad);
  }

  Offset _toLocalMeters(Position p) {
    if (_originLat == null || _originLon == null) {
      _initLocalOriginIfNeeded(p);
    }

    final dLat = p.latitude - _originLat!;
    final dLon = p.longitude - _originLon!;

    final x = dLon * (_metersPerDegLon ?? 0.0); // est
    final y = dLat * (_metersPerDegLat ?? 0.0); // nord

    return Offset(x, y);
  }

  // Smoothing semplice (EMA) per detection
  Offset _smoothLocal(Offset newLocal) {
    const alpha = 0.3; // 0..1 (più alto = meno smoothing)
    if (_lastLocalSmoothed == null) {
      _lastLocalSmoothed = newLocal;
    } else {
      _lastLocalSmoothed = Offset(
        _lastLocalSmoothed!.dx + alpha * (newLocal.dx - _lastLocalSmoothed!.dx),
        _lastLocalSmoothed!.dy + alpha * (newLocal.dy - _lastLocalSmoothed!.dy),
      );
    }
    return _lastLocalSmoothed!;
  }

  double _averageImuG({int windowMs = 600}) {
    if (_imuBuffer.isEmpty) return 0.0;
    final cutoff = DateTime.now().subtract(Duration(milliseconds: windowMs));
    final recent =
        _imuBuffer.where((s) => s.timestamp.isAfter(cutoff)).toList();
    if (recent.isEmpty) return 0.0;
    final sum = recent.fold<double>(0.0, (acc, s) => acc + s.magnitude);
    return (sum / recent.length) / 9.81;
  }

  double _computeFusedLongitudinalG(
    double currentSpeedMs,
    Duration? prevSampleTime,
    Duration nowT,
  ) {
    final double deltaSpeed =
        _prevSpeedMs != null ? currentSpeedMs - _prevSpeedMs! : 0.0;
    final double dtSeconds = prevSampleTime != null
        ? (nowT - prevSampleTime).inMilliseconds / 1000.0
        : 0.0;

    final double accelFromSpeed =
        dtSeconds > 0 ? (deltaSpeed / dtSeconds) / 9.81 : 0.0;
    final double imuG = _averageImuG(windowMs: 600);
    final double sign = deltaSpeed >= 0 ? 1.0 : -1.0;

    final double fused = 0.7 * imuG * sign + 0.3 * accelFromSpeed;
    return fused.clamp(-2.5, 2.5);
  }

  Position _positionFromLatLng(LatLng point) {
    return Position(
      longitude: point.longitude,
      latitude: point.latitude,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0.0,
      altitudeAccuracy: 1.0,
      heading: 0.0,
      headingAccuracy: 1.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      floor: null,
      isMocked: true,
    );
  }

  void _configureFinishLineFromTrackIfNeeded() {
    if (_finishLineConfiguredFromTrack) return;
    if (widget.trackDefinition == null) return;
    if (_originLat == null || _originLon == null) return;

    final track = widget.trackDefinition!;

    final startPos = _positionFromLatLng(track.finishLineStart);
    final endPos = _positionFromLatLng(track.finishLineEnd);

    final startLocal = _toLocalMeters(startPos);
    final endLocal = _toLocalMeters(endPos);

    final dir = endLocal - startLocal;
    final length = dir.distance;
    if (length < 0.5) {
      return;
    }

    final dirUnit = Offset(dir.dx / length, dir.dy / length);
    final normalUnit = Offset(-dirUnit.dy, dirUnit.dx);

    // IMPORTANTE: Estendi la linea di traguardo per creare un gate più largo
    // Questo è necessario per rilevare il passaggio con GPS a bassa frequenza (1-5 Hz)
    // Estendiamo la linea lungo la direzione della linea stessa
    const double extensionMeters = 50.0; // Estende di 50m per lato
    final Offset extendedStart = startLocal - (dirUnit * extensionMeters);
    final Offset extendedEnd = endLocal + (dirUnit * extensionMeters);
    final double extendedLength = (extendedEnd - extendedStart).distance;

    _finishLineStart = startPos;
    _finishLineEnd = endPos;
    _finishLineStartLocal = extendedStart; // Usa la linea estesa
    _finishLineEndLocal = extendedEnd;     // Usa la linea estesa
    _finishDirUnit = dirUnit;
    _finishNormalUnit = normalUnit;
    _finishLength = extendedLength;         // Usa la lunghezza estesa
    _finishLineConfiguredFromTrack = true;

    print('✓ Finish line configurata da circuito tracciato (estesa a ${extendedLength.toStringAsFixed(1)}m)');
  }

  // ============================================================
  // GESTIONE DATI GPS (reali o simulati)
  // ============================================================
  void _onGpsData(Position pos) {
    if (!_recording) return;

    final nowT = _sessionWatch.elapsed;

    // Coordinate locali in metri
    _initLocalOriginIfNeeded(pos);
    _configureFinishLineFromTrackIfNeeded();
    final localRaw = _toLocalMeters(pos);

    // Salvo i valori precedenti PRIMA di aggiornare lo smoothing
    final prevLocalSmoothed = _lastLocalSmoothed;
    final prevSampleTime = _lastSampleTime;

    // Smoothing per detection
    final localSmoothed = _smoothLocal(localRaw);

    // Salva posizione per mappa/recap
    _gpsTrack.add(pos);

    // Definisci finish line dopo un po' di punti (per stimare il centro)
    if (_gpsTrack.length == 20 && _finishLineStart == null) {
      _defineFinishLine();
    }

    // Controlla se abbiamo attraversato il traguardo (in coordinate locali, smoothed)
    if (_finishLineStartLocal != null &&
        _finishLineEndLocal != null &&
        _finishDirUnit != null &&
        _finishNormalUnit != null &&
        prevLocalSmoothed != null &&
        prevSampleTime != null) {
      _checkLapCrossing(prevLocalSmoothed, localSmoothed, prevSampleTime, nowT);
    }

    // Aggiorna velocità corrente
    _currentSpeedKph = pos.speed * 3.6; // m/s -> km/h

    // Fusione IMU + delta velocità per ottenere accel/decel lungo traiettoria
    final fusedLongG = _computeFusedLongitudinalG(
      pos.speed,
      prevSampleTime,
      nowT,
    );

    // Salva dati storici per grafici
    _speedHistory.add(_currentSpeedKph);
    _gForceHistory.add(fusedLongG);
    _gpsAccuracyHistory.add(pos.accuracy);
    _timeHistory.add(nowT);
    _prevSpeedMs = pos.speed;

    // Ricalcola smooth path per disegno su mappa
    if (_gpsTrack.length >= 2) {
      _smoothPath = _createSmoothPath();

      // Centra mappa sulla posizione corrente (solo se la mappa è visibile)
      if (_viewMap) {
        try {
          final lastPos = _gpsTrack.last;
          _mapController.move(
            LatLng(lastPos.latitude, lastPos.longitude),
            _currentZoom,
          );
        } catch (e) {
          // Mappa non ancora renderizzata, ignora
        }
      }
    }

    setState(() {
      if (_useGpsSimulator) {
        _gpsStatus = 'GPS simulato';
      } else if (_isUsingBleGps) {
        _gpsStatus = 'BLE GPS 15Hz: ${pos.accuracy.toStringAsFixed(1)}m';
      } else {
        _gpsStatus = 'GPS cellulare 1Hz: ${pos.accuracy.toStringAsFixed(1)}m';
      }
    });

    _lastGpsPos = pos;
    _lastSampleTime = nowT;
    _lastLocalSmoothed = localSmoothed;
  }

  // ============================================================
  // FINISH LINE VIRTUALE + GATE (radiale, non tangente)
  // ============================================================
  void _defineFinishLine() {
    if (_finishLineConfiguredFromTrack || widget.trackDefinition != null) {
      return;
    }
    if (_gpsTrack.length < 5 || _originLat == null || _originLon == null)
      return;

    // Salva comunque start/end GPS "logici"
    _finishLineStart = _gpsTrack[0];
    _finishLineEnd = _gpsTrack[1];

    // Calcola i primi N punti in coordinate locali per stimare il centro del tracciato
    const int numForCenter = 20;
    final int n = math.min(numForCenter, _gpsTrack.length);

    final List<Offset> locals = [];
    for (int i = 0; i < n; i++) {
      locals.add(_toLocalMeters(_gpsTrack[i]));
    }

    if (locals.isEmpty) return;

    // Centro approssimato del tracciato
    Offset center = Offset.zero;
    for (final p in locals) {
      center = Offset(center.dx + p.dx, center.dy + p.dy);
    }
    center = Offset(center.dx / locals.length, center.dy / locals.length);

    // Punto di passaggio della finish (primo punto registrato)
    final Offset p0 = locals.first;

    // Direzione radiale dal centro verso p0 (questa è la direzione della linea di gara)
    Offset radial = p0 - center;
    final double radialLen = radial.distance;

    if (radialLen < 1.0) {
      // fallback: se per qualche motivo centro ~ p0, usa i primi due punti come direzione
      final Offset p1 = locals.length > 1 ? locals[1] : p0 + const Offset(1, 0);
      radial = p1 - p0;
    }

    final double lineLen = radial.distance;
    if (lineLen < 1.0) return;

    final Offset lineDir = Offset(radial.dx / lineLen, radial.dy / lineLen);
    final Offset lineNormal = Offset(-lineDir.dy, lineDir.dx); // perpendicolare

    _finishDirUnit = lineDir; // la linea del traguardo è radiale
    _finishNormalUnit = lineNormal;

    // Definisci un piccolo segmento base centrato vicino a p0 lungo la direzione radiale
    const double baseHalfLength = 2.0; // 4m totali attorno a p0
    final Offset s = p0 - lineDir * baseHalfLength;
    final Offset e = p0 + lineDir * baseHalfLength;

    _finishLineStartLocal = s;
    _finishLineEndLocal = e;
    _finishLength = (e - s).distance;

    print('✓ Finish line (gate radiale) definita in metri');
  }

  // Signed distance dalla linea del traguardo (metri, +/− a seconda del lato)
  double _signedDistanceToFinish(Offset p) {
    if (_finishLineStartLocal == null || _finishNormalUnit == null) return 0.0;
    final v = p - _finishLineStartLocal!;
    return v.dx * _finishNormalUnit!.dx + v.dy * _finishNormalUnit!.dy;
  }

  // Proiezione di p lungo la linea del traguardo (0 all'inizio, cresce lungo la linea)
  double _projectionOnFinish(Offset p) {
    if (_finishLineStartLocal == null || _finishDirUnit == null) return 0.0;
    final v = p - _finishLineStartLocal!;
    return v.dx * _finishDirUnit!.dx + v.dy * _finishDirUnit!.dy;
  }

  // ============================================================
  // RILEVAMENTO GIRI (gate + intersezione geometrica + interpolazione tempo)
  // ============================================================
  void _checkLapCrossing(
    Offset prevLocal,
    Offset currentLocal,
    Duration prevTime,
    Duration currentTime,
  ) {
    if (_finishLineStartLocal == null ||
        _finishLineEndLocal == null ||
        _finishDirUnit == null ||
        _finishNormalUnit == null) {
      return;
    }

    // 1. GATE VALIDATION - Verifica che almeno un punto sia nel gate
    final prevDist = _signedDistanceToFinish(prevLocal);
    final curDist = _signedDistanceToFinish(currentLocal);

    final prevProj = _projectionOnFinish(prevLocal);
    final curProj = _projectionOnFinish(currentLocal);

    final double minProj = math.min(prevProj, curProj);
    final double maxProj = math.max(prevProj, curProj);

    final double gateStart = -_gateHalfLength;
    final double gateEnd = _finishLength + _gateHalfLength;

    // Se entrambi i punti sono completamente fuori dal gate longitudinale, scarta
    if (maxProj < gateStart || minProj > gateEnd) {
      return;
    }

    // Verifica che almeno un punto sia nel gate trasversale
    final prevInGate = prevDist.abs() <= _gateHalfWidth;
    final curInGate = curDist.abs() <= _gateHalfWidth;

    if (!prevInGate && !curInGate) {
      // Entrambi lontani dalla linea, scarta
      return;
    }

    // 2. SEGMENT INTERSECTION - Verifica intersezione geometrica
    final intersection = _segmentIntersection(
      prevLocal,
      currentLocal,
      _finishLineStartLocal!,
      _finishLineEndLocal!,
    );

    if (intersection != null) {
      // Crossing geometrico verificato!
      final t = intersection.t; // Parametro 0..1 lungo prev->curr
      final crossingTime = _interpolateTime(prevTime, currentTime, t);

      if (_canMarkLap(crossingTime)) {
        _registerLapAtTime(crossingTime);
      }
      return;
    }

    // 3. FALLBACK - Cambio di segno (per robustezza con jitter GPS)
    // Usa questo solo se segment intersection fallisce per errori numerici
    final sameSide = prevDist * curDist > 0;
    if (!sameSide) {
      // I punti sono su lati opposti, calcola t dove distanza = 0
      final denom = prevDist - curDist;
      if (denom.abs() < 1e-6) {
        return;
      }

      final double t = prevDist / denom;
      if (t >= 0.0 && t <= 1.0) {
        final crossingTime = _interpolateTime(prevTime, currentTime, t);

        if (_canMarkLap(crossingTime)) {
          _registerLapAtTime(crossingTime);
        }
      }
    }
  }

  // Calcola intersezione tra segmento traiettoria GPS e linea di finish
  // Returns null se non c'è intersezione valida, altrimenti parametri t e u
  _IntersectionResult? _segmentIntersection(
    Offset p1,
    Offset p2, // Segmento traiettoria GPS
    Offset q1,
    Offset q2, // Segmento linea di finish
  ) {
    // Parametric equations:
    // P(t) = p1 + t(p2-p1), t ∈ [0,1]  (traiettoria GPS)
    // Q(u) = q1 + u(q2-q1), u ∈ [0,1]  (linea finish)
    // Risolviamo: P(t) = Q(u)

    final r = p2 - p1; // Direzione traiettoria
    final s = q2 - q1; // Direzione linea finish
    final qp = q1 - p1; // Vettore da p1 a q1

    final rxs = _cross2D(r, s);

    // Paralleli o coincidenti
    if (rxs.abs() < 1e-10) {
      return null;
    }

    final u = _cross2D(qp, r) / rxs;
    final t = _cross2D(qp, s) / rxs;

    // Intersezione valida solo se entrambi i parametri sono in [0,1]
    if (t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0) {
      return _IntersectionResult(t: t, u: u);
    }

    return null;
  }

  // Prodotto vettoriale 2D (restituisce lo scalare z)
  double _cross2D(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  bool _canMarkLap(Duration time) {
    // Min 10s dall'inizio sessione per evitare falsi positivi iniziali
    if (time.inSeconds <= 10) return false;
    // Rispetta il minimo tempo tra giri (per evitare doppi conteggi da jitter)
    const minLap = Duration(seconds: 20);
    if (time - _lastLapMark < minLap) return false;
    return true;
  }

  // Interpolazione temporale tra due sample
  Duration _interpolateTime(Duration t1, Duration t2, double alpha) {
    alpha = alpha.clamp(0.0, 1.0);
    final ms1 = t1.inMilliseconds;
    final ms2 = t2.inMilliseconds;
    final diff = ms2 - ms1;
    final interpMs = (ms1 + diff * alpha).round();
    return Duration(milliseconds: interpMs);
  }

  // Registra un giro sapendo l'istante esatto (Duration) del crossing
  void _registerLapAtTime(Duration crossingTime) {
    final lapTime = crossingTime - _lastLapMark;

    // Ignora giri troppo corti (< 20 sec, ulteriore sicurezza)
    if (lapTime.inSeconds < 20) return;

    setState(() {
      _laps.add(lapTime);
      _previousLap = lapTime;
      _lastLapMark = crossingTime;

      // Aggiorna best lap
      if (_bestLap == null || lapTime < _bestLap!) {
        _bestLap = lapTime;
      }
    });

    print('✓ Giro ${_laps.length}: ${_formatDuration(lapTime)}');
  }

  // ============================================================
  // SMOOTH PATH CON CUBIC SPLINE (solo per disegno mappa)
  // ============================================================
  List<LatLng> _createSmoothPath() {
    if (_gpsTrack.length < 3) {
      // Non abbastanza punti per spline, usa punti raw
      return _gpsTrack.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }

    try {
      // Estrai lat/lon
      final lats = _gpsTrack.map((p) => p.latitude).toList();
      final lons = _gpsTrack.map((p) => p.longitude).toList();

      // Parametro t (indice dei punti)
      final tGps = List.generate(_gpsTrack.length, (i) => i.toDouble());

      // Genera 10 punti interpolati tra ogni coppia di GPS
      final pointsPerGps = 10;
      final tSmooth = <double>[];
      for (int i = 0; i < _gpsTrack.length - 1; i++) {
        for (int j = 0; j < pointsPerGps; j++) {
          tSmooth.add(i + j / pointsPerGps);
        }
      }
      tSmooth.add((_gpsTrack.length - 1).toDouble()); // Ultimo punto

      // Cubic spline interpolation (Catmull-Rom semplificata)
      final smoothLats = _cubicInterpolate(tGps, lats, tSmooth);
      final smoothLons = _cubicInterpolate(tGps, lons, tSmooth);

      // Crea path smooth
      final smoothPath = <LatLng>[];
      for (int i = 0; i < smoothLats.length; i++) {
        smoothPath.add(LatLng(smoothLats[i], smoothLons[i]));
      }

      return smoothPath;
    } catch (e) {
      print('Errore spline: $e');
      return _gpsTrack.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }
  }

  // Cubic interpolation semplificata (Catmull-Rom)
  List<double> _cubicInterpolate(
    List<double> x,
    List<double> y,
    List<double> xNew,
  ) {
    final result = <double>[];

    for (final xi in xNew) {
      // Trova i 4 punti vicini per interpolazione cubica
      int i1 = xi.floor().clamp(0, x.length - 1);
      int i0 = (i1 - 1).clamp(0, x.length - 1);
      int i2 = (i1 + 1).clamp(0, x.length - 1);
      int i3 = (i2 + 1).clamp(0, x.length - 1);

      final t = xi - i1;

      // Catmull-Rom spline
      final v0 = y[i0];
      final v1 = y[i1];
      final v2 = y[i2];
      final v3 = y[i3];

      final a = -0.5 * v0 + 1.5 * v1 - 1.5 * v2 + 0.5 * v3;
      final b = v0 - 2.5 * v1 + 2.0 * v2 - 0.5 * v3;
      final c = -0.5 * v0 + 0.5 * v2;
      final d = v1;

      final value = a * t * t * t + b * t * t + c * t + d;
      result.add(value);
    }

    return result;
  }

  // ============================================================
  // STOP SESSIONE
  // ============================================================
  void _stopSession() {
    if (_sessionFinished) return;

    setState(() {
      _recording = false;
      _sessionFinished = true;
      _gpsStatus = 'Sessione terminata';
    });

    _sessionWatch.stop();
    _stopAllStreams();

    // Vai alla pagina di recap
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionRecapPage(
          gpsTrack: _gpsTrack,
          smoothPath: _smoothPath,
          laps: _laps,
          totalDuration: _sessionWatch.elapsed,
          bestLap: _bestLap,
          speedHistory: _speedHistory,
          gForceHistory: _gForceHistory,
          gpsAccuracyHistory: _gpsAccuracyHistory,
          timeHistory: _timeHistory,
          trackDefinition: widget.trackDefinition,
        ),
      ),
    );
  }

  void _stopAllStreams() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _bleGpsSub?.cancel();
    _bleGpsSub = null;
    _uiTimer?.cancel();
    _uiTimer = null;

    _simTimer?.cancel();
    _simTimer = null;
  }

  // ============================================================
  // UTILITY
  // ============================================================
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  String _formatDelta() {
    if (_previousLap == null || _bestLap == null) return '---';

    final deltaMs = _previousLap!.inMilliseconds - _bestLap!.inMilliseconds;
    final sign = deltaMs >= 0 ? '+' : '';
    return '$sign${(deltaMs / 1000).toStringAsFixed(2)}';
  }

  Duration _getCurrentLapTime() {
    return _sessionWatch.elapsed - _lastLapMark;
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _rcBlue,
      body: SafeArea(
        child: Column(
          children: [
            // Barra LIVE + stato GPS + STOP
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kLiveColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.fiber_manual_record,
                            size: 12, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Badge sorgente GPS
                  if (_isUsingBleGps)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            kBrandColor.withOpacity(0.3),
                            kBrandColor.withOpacity(0.2),
                          ],
                        ),
                        border: Border.all(color: kBrandColor, width: 1.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bluetooth_connected,
                              size: 11, color: kBrandColor),
                          SizedBox(width: 4),
                          Text(
                            '15Hz',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: kBrandColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.smartphone, size: 11, color: Colors.white70),
                          SizedBox(width: 4),
                          Text(
                            '1Hz',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _gpsStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _stopSession,
                    icon: const Icon(Icons.stop_circle, size: 32),
                    color: kErrorColor,
                  ),
                ],
              ),
            ),

            // Area principale stile RaceChrono
            Expanded(
              child: _buildRacechronoLayout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kLiveColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.fiber_manual_record,
                      size: 12, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _gpsStatus,
              style: const TextStyle(
                fontSize: 13,
                color: kMutedColor,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _stopSession,
              icon: const Icon(Icons.stop_circle, size: 32),
              color: kErrorColor,
            ),
          ],
        ),
      ),
    );
  }

  // Costruisce i 4 vertici del gate in lat/lon per mostrarlo a schermo
  List<LatLng> _buildGatePolygonLatLngs() {
    if (_finishLineStartLocal == null ||
        _finishDirUnit == null ||
        _finishNormalUnit == null) {
      return [];
    }

    final s = _finishLineStartLocal!;
    final dir = _finishDirUnit!;
    final norm = _finishNormalUnit!;

    final gateStart = -_gateHalfLength;
    final gateEnd = _finishLength + _gateHalfLength;

    final p1 = s + dir * gateStart + norm * _gateHalfWidth;
    final p2 = s + dir * gateEnd + norm * _gateHalfWidth;
    final p3 = s + dir * gateEnd - norm * _gateHalfWidth;
    final p4 = s + dir * gateStart - norm * _gateHalfWidth;

    return [
      _localToLatLng(p1),
      _localToLatLng(p2),
      _localToLatLng(p3),
      _localToLatLng(p4),
    ];
  }

  Widget _buildMap() {
    final gatePolygon = _buildGatePolygonLatLngs();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
        bottom: Radius.circular(24),
      ),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(41.9028, 12.4964),
          initialZoom: 18.0,
          onPositionChanged: (position, hasGesture) {
            if (hasGesture && position.zoom != null) {
              _currentZoom = position.zoom!;
            }
          },
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom |
                InteractiveFlag.drag |
                InteractiveFlag.doubleTapZoom,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.racesense.pulse',
          ),
          // Smooth path (verde)
          if (_smoothPath.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _smoothPath,
                  strokeWidth: 4.0,
                  color: kBrandColor,
                ),
              ],
            ),
          // Gate del traguardo (area considerata per il giro)
          if (gatePolygon.isNotEmpty)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: gatePolygon,
                  color: kPulseColor.withOpacity(0.2),
                  borderColor: kPulseColor,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
          // GPS raw (punti rossi)
          if (_gpsTrack.isNotEmpty)
            MarkerLayer(
              markers: _gpsTrack.map((pos) {
                return Marker(
                  point: LatLng(pos.latitude, pos.longitude),
                  width: 8,
                  height: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }).toList(),
            ),
          // Posizione corrente (grande)
          if (_lastGpsPos != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_lastGpsPos!.latitude, _lastGpsPos!.longitude),
                  width: 15,
                  height: 15,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kPulseColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: kPulseColor.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRacechronoLayout() {
    // Indici giri
    final int bestIndex = (_bestLap != null && _laps.isNotEmpty)
        ? _laps.indexOf(_bestLap!) + 1
        : 0;
    final int lastIndex = _laps.isNotEmpty ? _laps.length : 0;
    final int currentIndex = _laps.length + 1;

    final String bestTime =
        _bestLap != null ? _formatLapBig(_bestLap!) : '--:--.-';
    final String lastTime =
        _previousLap != null ? _formatLapBig(_previousLap!) : '--:--.-';
    final String currentTime = _formatLapBig(_getCurrentLapTime());

    return Column(
      children: [
        // Parte blu (Best / Previous / Current + metriche secondarie)
        Expanded(
          child: Container(
            width: double.infinity,
            color: _rcBlue,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLapRow(
                        label: 'Best',
                        index: bestIndex,
                        time: bestTime,
                      ),
                      _buildLapRow(
                        label: 'Previous',
                        index: lastIndex,
                        time: lastTime,
                      ),
                      _buildLapRow(
                        label: 'Current',
                        index: currentIndex,
                        time: currentTime,
                        highlight: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Riga metriche secondarie (speed / g / laps)
                _buildSecondaryRow(),
              ],
            ),
          ),
        ),

        // Barra verde per il delta
        _buildDeltaBar(),
      ],
    );
  }

  Widget _buildLapRow({
    required String label,
    required int index,
    required String time,
    bool highlight = false,
  }) {
    final TextStyle labelStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.white.withOpacity(0.9),
    );

    final TextStyle indexStyle = TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w700,
      color: Colors.white.withOpacity(0.9),
      height: 1.0,
    );

    final TextStyle timeStyle = TextStyle(
      fontSize: highlight ? 72 : 64,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      height: 1.0,
      letterSpacing: -2,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Numero giro a sinistra
        SizedBox(
          width: 48,
          child: Center(
            child: Text(
              index > 0 ? '$index' : '',
              style: indexStyle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Label + tempo
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: labelStyle),
              const SizedBox(height: 4),
              Text(time, style: timeStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSmallMetric(
          title: 'Speed',
          value: '${_currentSpeedKph.toStringAsFixed(0)}',
          unit: 'km/h',
        ),
        _buildSmallMetric(
          title: 'G-Force',
          value: _gForceMagnitude.toStringAsFixed(2),
          unit: 'g',
        ),
        _buildSmallMetric(
          title: 'Laps',
          value: '${_laps.length}',
          unit: '',
        ),
      ],
    );
  }

  Widget _buildSmallMetric({
    required String title,
    required String value,
    required String unit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.0,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDeltaBar() {
    final deltaStr = _formatDeltaBig();

    // delta negativo = più veloce → sfondo verde, positivo = rosso
    Color borderColor = Colors.white;
    Color backgroundColor = _rcGreen;

    if (deltaStr.startsWith('-')) {
      backgroundColor = _rcGreen;
      borderColor = Colors.white;
    } else if (deltaStr.startsWith('+')) {
      backgroundColor = Colors.redAccent;
      borderColor = Colors.redAccent.shade100;
    }

    return Container(
      height: 140,
      width: double.infinity,
      color: backgroundColor,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 4),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            deltaStr,
            style: const TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.0,
              letterSpacing: -4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDataCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0f1a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1a2332),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.4),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImuSample {
  final DateTime timestamp;
  final double ax;
  final double ay;
  final double az;

  _ImuSample(this.timestamp, this.ax, this.ay, this.az);

  double get magnitude => math.sqrt(ax * ax + ay * ay + az * az);
}
