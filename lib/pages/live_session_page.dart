import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../services/ble_tracking_service.dart';
import '../services/lap_detection_service.dart';
import 'session_recap_page.dart';

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

  // ✨ NUOVO SISTEMA: Rilevamento giri con microsettori
  final LapDetectionService _lapDetection = LapDetectionService();

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
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceStreamSub;

  // Formation lap - il timer parte solo dopo il primo passaggio dal via
  bool _timerStarted = false;

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
    if (_previousLap == null) return '---';

    // Se non c'è best lap o abbiamo fatto solo 1 giro, non c'è delta
    if (_bestLap == null || _laps.length <= 1) return '---';

    // Se previousLap È il best lap (appena migliorato), confronta con il secondo miglior tempo
    Duration referenceTime;
    if (_previousLap == _bestLap) {
      // Trova il secondo miglior tempo (escludendo l'ultimo giro che è il best)
      final otherLaps = _laps.sublist(0, _laps.length - 1);
      if (otherLaps.isEmpty) return '---';
      referenceTime = otherLaps.reduce((a, b) => a < b ? a : b);
    } else {
      // Usa il best lap come riferimento
      referenceTime = _bestLap!;
    }

    final diffSeconds =
        (_previousLap!.inMilliseconds - referenceTime.inMilliseconds) / 1000.0;
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
    // ⚠️ NON avviare il timer qui - parte solo dopo il formation lap
    // Il timer verrà avviato in _onGpsData quando si passa dal via

    // Timer UI per aggiornare il cronometro (ma mostra 0:00 finché non inizia)
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
    // Verifica iniziale: controlla se c'è già un dispositivo BLE connesso
    final connectedDevices = _bleService.getConnectedDeviceIds();
    if (connectedDevices.isNotEmpty && !_isUsingBleGps) {
      final deviceId = connectedDevices.first;
      print('✓ Dispositivo BLE già connesso all\'avvio: $deviceId');
      setState(() {
        _connectedBleDeviceId = deviceId;
        _isUsingBleGps = true;
      });
      _startBleGpsStream();
      return; // Non avviare GPS cellulare
    }

    // Setup listener per monitorare cambiamenti di stato dispositivi BLE
    // ⚠️ IMPORTANTE: Cancellare questo listener in dispose() per evitare memory leak
    _bleDeviceStreamSub?.cancel();
    _bleDeviceStreamSub = _bleService.deviceStream.listen((devices) {
      if (!mounted) return;

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
        // Dispositivo BLE connesso durante la sessione
        print('✓ Dispositivo BLE connesso: ${connected.id}');
        setState(() {
          _connectedBleDeviceId = connected.id;
          _isUsingBleGps = true;
        });
        // Ferma il GPS cellulare e passa al GPS BLE
        _gpsSub?.cancel();
        _startBleGpsStream();
      } else if (!connected.isConnected && _isUsingBleGps) {
        // Dispositivo BLE disconnesso, fallback a GPS cellulare
        print('⚠️ Dispositivo BLE disconnesso, fallback a GPS cellulare');
        setState(() {
          _connectedBleDeviceId = null;
          _isUsingBleGps = false;
        });
        // Ferma il GPS BLE e torna al GPS cellulare
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
    // IMPORTANTE: Il BLE GPS fornisce già la velocità in km/h
    // Convertiamo in m/s per compatibilità con Position (che usa m/s)
    final speedKmh = gpsData.speed ?? 0.0;
    final speedMs = speedKmh / 3.6; // km/h -> m/s

    return Position(
      longitude: gpsData.position.longitude,
      latitude: gpsData.position.latitude,
      timestamp: DateTime.now(),
      accuracy: _calculateAccuracyFromFix(gpsData.fix, gpsData.satellites),
      altitude: 0.0,
      altitudeAccuracy: 3.0,
      heading: 0.0,
      headingAccuracy: 1.0,
      speed: speedMs, // Ora in m/s come da standard Position
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

  // ============================================================
  // ✨ NUOVO SISTEMA: Inizializzazione microsettori
  // ============================================================
  void _initializeLapDetection() {
    if (widget.trackDefinition != null) {
      // Modalità pre-tracciato: inizializza con circuito esistente
      _lapDetection.initializeWithTrack(widget.trackDefinition!);
      print('✓ LapDetection inizializzato con circuito pre-tracciato: ${widget.trackDefinition!.name}');
    } else {
      // Modalità veloce: definisci finish line dai primi punti GPS e avvia registrazione primo giro
      if (_gpsTrack.length >= 20) {
        // Usa i primi punti per stimare il centro e creare una linea di traguardo virtuale
        final List<Offset> locals = [];
        for (int i = 0; i < math.min(20, _gpsTrack.length); i++) {
          locals.add(_toLocalMeters(_gpsTrack[i]));
        }

        // Centro approssimato del tracciato
        Offset center = Offset.zero;
        for (final p in locals) {
          center = Offset(center.dx + p.dx, center.dy + p.dy);
        }
        center = Offset(center.dx / locals.length, center.dy / locals.length);

        // Punto di passaggio della finish (primo punto registrato)
        final Offset p0 = locals.first;

        // Direzione radiale dal centro verso p0
        Offset radial = p0 - center;
        final double radialLen = radial.distance;

        if (radialLen < 1.0) {
          final Offset p1 = locals.length > 1 ? locals[1] : p0 + const Offset(1, 0);
          radial = p1 - p0;
        }

        final double lineLen = radial.distance;
        if (lineLen < 1.0) return;

        final Offset lineDir = Offset(radial.dx / lineLen, radial.dy / lineLen);

        // Definisci un segmento base centrato vicino a p0 lungo la direzione radiale
        const double baseHalfLength = 10.0; // 20m totali attorno a p0
        final Offset s = p0 - lineDir * baseHalfLength;
        final Offset e = p0 + lineDir * baseHalfLength;

        // Converti in LatLng per il servizio
        final finishLineStart = _localToLatLng(s);
        final finishLineEnd = _localToLatLng(e);

        _lapDetection.initializeQuickMode(finishLineStart, finishLineEnd);
        print('✓ LapDetection inizializzato in modalità veloce (primo giro)');
      }
    }
  }


  // ============================================================
  // GESTIONE DATI GPS (reali o simulati)
  // ============================================================
  void _onGpsData(Position pos) {
    if (!_recording) return;

    final nowT = _sessionWatch.elapsed;

    // Coordinate locali in metri (mantieni per visualizzazione mappa)
    _initLocalOriginIfNeeded(pos);
    final localRaw = _toLocalMeters(pos);

    // Salvo i valori precedenti PRIMA di aggiornare lo smoothing
    final prevSampleTime = _lastSampleTime;

    // Smoothing per detection (mantieni per retrocompatibilità)
    final localSmoothed = _smoothLocal(localRaw);

    // Salva posizione per mappa/recap
    _gpsTrack.add(pos);

    // ✨ NUOVO SISTEMA: Inizializza microsettori dopo aver raccolto alcuni punti
    if (_gpsTrack.length == 20) {
      _initializeLapDetection();
    }

    // ✨ NUOVO SISTEMA: Tracking con microsettori
    if (_gpsTrack.length >= 20) {
      // Salva lo stato del formation lap prima del processing
      final wasInFormationLap = _lapDetection.inFormationLap;

      // Calcola heading dal GPS se disponibile (altrimenti usa null)
      final vehicleHeading = pos.heading > 0 ? pos.heading : null;

      final lapCompleted = _lapDetection.processGpsPoint(pos, vehicleHeading: vehicleHeading);

      // 🏁 Avvia il timer quando il formation lap termina
      if (wasInFormationLap && !_lapDetection.inFormationLap && !_timerStarted) {
        _sessionWatch.start();
        _timerStarted = true;
        print('✓ Timer avviato dopo formation lap');
      }

      if (lapCompleted) {
        _registerLapAtTime(nowT);
      }
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
        final freq = _lapDetection.estimatedGpsFrequency;
        _gpsStatus = 'BLE GPS ${freq.toStringAsFixed(1)}Hz: ${pos.accuracy.toStringAsFixed(1)}m';
      } else {
        final freq = _lapDetection.estimatedGpsFrequency;
        _gpsStatus = 'GPS cellulare ${freq.toStringAsFixed(1)}Hz: ${pos.accuracy.toStringAsFixed(1)}m';
      }

      // Mostra info formation lap
      if (_lapDetection.inFormationLap) {
        _gpsStatus += ' (Formation Lap)';
      }
      // Mostra info microsettori se stiamo registrando primo giro
      else if (_lapDetection.isRecordingFirstLap) {
        _gpsStatus += ' (Primo giro: ${_lapDetection.lapProgress.toStringAsFixed(0)}%)';
      }
    });

    _lastGpsPos = pos;
    _lastSampleTime = nowT;
    _lastLocalSmoothed = localSmoothed;
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

      // Aggiorna best lap DOPO aver impostato previousLap
      // In questo modo _formatDeltaBig() può confrontare _previousLap con il best lap corrente
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
          usedBleDevice: _isUsingBleGps,
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

    // ⚠️ IMPORTANTE: Cancella listener BLE per evitare memory leak
    _bleDeviceStreamSub?.cancel();
    _bleDeviceStreamSub = null;
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
    if (_previousLap == null) return '---';
    if (_bestLap == null || _laps.length <= 1) return '---';

    // Se previousLap È il best lap (appena migliorato), confronta con il secondo miglior tempo
    Duration referenceTime;
    if (_previousLap == _bestLap) {
      final otherLaps = _laps.sublist(0, _laps.length - 1);
      if (otherLaps.isEmpty) return '---';
      referenceTime = otherLaps.reduce((a, b) => a < b ? a : b);
    } else {
      referenceTime = _bestLap!;
    }

    final deltaMs = _previousLap!.inMilliseconds - referenceTime.inMilliseconds;
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

            // Formation Lap Banner
            if (_lapDetection.inFormationLap)
              _buildFormationLapBanner(),

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

  Widget _buildMap() {

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

  Widget _buildFormationLapBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFA500).withOpacity(0.9),
            const Color(0xFFFF8C00).withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFA500).withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flag,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FORMATION LAP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Passa dalla linea del via per iniziare',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.arrow_forward,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
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
