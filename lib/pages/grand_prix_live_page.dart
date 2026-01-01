import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../services/ble_tracking_service.dart';
import '../services/lap_detection_service.dart';
import '../services/grand_prix_service.dart';
import '../services/track_service.dart';
import 'grand_prix_statistics_page.dart';

/// Grand Prix Live Page - AIM MXS Style
///
/// Modalità multiplayer con sync Firebase Realtime Database.
/// Ogni pilota fa il proprio formation lap e i tempi vengono sincronizzati.
class GrandPrixLivePage extends StatefulWidget {
  final String lobbyCode;

  const GrandPrixLivePage({super.key, required this.lobbyCode});

  @override
  State<GrandPrixLivePage> createState() => _GrandPrixLivePageState();
}

class _GrandPrixLivePageState extends State<GrandPrixLivePage> {
  // ============================================================
  // STATE
  // ============================================================

  bool _recording = false; // Diventerà true dopo il formation lap
  bool _sessionFinished = false;

  // Timer sessione
  final Stopwatch _sessionWatch = Stopwatch();
  Timer? _uiTimer;

  // GPS grezzo (fonte di verità per post-processing)
  final List<Position> _gpsTrack = [];
  Position? _lastPosition;

  // Lap detection live (best-effort)
  final LapDetectionService _lapDetection = LapDetectionService();
  final List<Duration> _laps = [];
  Duration? _bestLap;
  Duration? _previousLap;

  // Delta live GPS-based (stile AIM)
  // Salva i punti GPS con il tempo per il best lap
  List<_LapGpsPoint> _bestLapGpsPoints = [];
  // Punti GPS del giro corrente
  final List<_LapGpsPoint> _currentLapGpsPoints = [];
  // Delta live calcolato (in secondi, negativo = più veloce)
  double? _liveDelta;

  // Telemetria real-time
  double _currentSpeedKmh = 0.0;
  double _gForceX = 0.0;
  double _gForceY = 0.0;
  double _gForceMagnitude = 1.0;

  // Dati storici per recap
  final List<double> _speedHistory = [];
  final List<double> _gForceHistory = [];
  final List<double> _gpsAccuracyHistory = [];
  final List<Duration> _timeHistory = [];

  // IMU buffer per calcolo G-force
  final List<_ImuSample> _imuBuffer = [];
  double? _prevSpeedMs;
  DateTime? _prevSpeedTime;

  // Subscriptions
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSub;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceStreamSub;

  // BLE GPS
  final BleTrackingService _bleService = BleTrackingService();
  String? _connectedBleDeviceId;
  bool _isUsingBleGps = false;

  // Formation lap - timer parte dopo primo passaggio linea S/F
  bool _timerStarted = false;

  // Mappa
  final MapController _mapController = MapController();
  List<LatLng> _displayPath = [];

  // ============================================================
  // GRAND PRIX SPECIFIC
  // ============================================================

  final GrandPrixService _grandPrixService = GrandPrixService();
  final TrackService _trackService = TrackService();
  TrackDefinition? _trackDefinition;
  bool _isHost = false;
  bool _sessionFinishedByHost = false;
  Timer? _syncTimer;

  // Stats per sync Firebase
  double _maxSpeed = 0.0;
  double _minSpeed = double.infinity;
  double _maxGForce = 0.0;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    // Forza orientamento landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadLobbyAndStart();
  }

  Future<void> _loadLobbyAndStart() async {
    // Check if host
    final isHost = await _grandPrixService.isHost(widget.lobbyCode);

    // Get lobby data
    final lobbyData = await _grandPrixService.getLobbyData(widget.lobbyCode);
    if (lobbyData == null || lobbyData['trackId'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore caricamento lobby')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    // Load track definition
    final trackId = lobbyData['trackId'] as String;
    final trackWithMetadata = await _trackService.getTrackById(trackId);

    if (trackWithMetadata == null || !mounted) return;

    setState(() {
      _isHost = isHost;
      _trackDefinition = trackWithMetadata.trackDefinition;
    });

    // Initialize lap detection
    if (_trackDefinition != null) {
      _lapDetection.initializeWithFinishLine(
        _trackDefinition!.finishLineStart!,
        _trackDefinition!.finishLineEnd!,
      );
      _lapDetection.onLapCompleted = _onLapCompleted;
    }

    // Watch lobby for host stop command
    _watchLobbyStatus();

    // Start session
    _startSession();
  }

  void _watchLobbyStatus() {
    _grandPrixService.watchLobby(widget.lobbyCode).listen((event) {
      if (!event.snapshot.exists || !mounted) return;

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final status = data['status'];

      if (status == 'finished' && !_sessionFinishedByHost) {
        _sessionFinishedByHost = true;
        _finishSession();
      }
    });
  }

  @override
  void dispose() {
    // Ripristina orientamento normale
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _stopAllStreams();
    _sessionWatch.stop();
    _uiTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // SESSION CONTROL
  // ============================================================

  void _startSession() {
    // Lap detection già inizializzato in _loadLobbyAndStart()

    // Timer UI (aggiorna ogni 50ms per precisione)
    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _recording) {
        setState(() {});
      }
    });

    // Sync Firebase timer (ogni 1 secondo)
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recording) {
        _syncDataToFirebase();
      }
    });

    // Controlla BLE GPS
    _syncBleDeviceFromService();
    _listenBleConnectionChanges();

    // Avvia GPS e sensori
    _startGpsStream();
    _startAccelerometer();
  }

  /// Sincronizza dati live su Firebase per statistiche finali
  void _syncDataToFirebase() async {
    if (!_recording) return;

    await _grandPrixService.updateLiveData(widget.lobbyCode, {
      'currentLap': _laps.length + 1,
      'lapTimes': _laps.map((d) => d.inMilliseconds).toList(),
      'bestLap': _bestLap?.inMilliseconds,
      'maxSpeed': _maxSpeed,
      'minSpeed': _minSpeed == double.infinity ? 0.0 : _minSpeed,
      'maxGForce': _maxGForce,
      'totalLaps': _laps.length,
      'isFormationLap': _lapDetection.inFormationLap,
    });
  }

  void _syncBleDeviceFromService() {
    final connectedIds = _bleService.getConnectedDeviceIds();
    if (connectedIds.isNotEmpty) {
      _connectedBleDeviceId = connectedIds.first;
      _isUsingBleGps = true;
      _listenBleGps();
    }
  }

  void _listenBleConnectionChanges() {
    _bleDeviceStreamSub = _bleService.deviceStream.listen((devices) {
      final connected = devices.values.firstWhere(
        (d) => d.isConnected,
        orElse: () => BleDeviceSnapshot(
          id: '',
          name: '',
          rssi: null,
          isConnected: false,
        ),
      );

      if (mounted) {
        setState(() {
          if (connected.isConnected) {
            _connectedBleDeviceId = connected.id;
            _isUsingBleGps = true;
            _listenBleGps();
            _gpsSub?.cancel();
            _gpsSub = null;
          } else {
            _connectedBleDeviceId = null;
            _isUsingBleGps = false;
            _bleGpsSub?.cancel();
            _bleGpsSub = null;
            _startGpsStream();
          }
        });
      }
    });
  }

  void _startGpsStream() {
    if (_isUsingBleGps || _gpsSub != null) return;

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // GPS grezzo completo
      ),
    ).listen((position) {
      // Sostituisce timestamp con DateTime.now() per precisione ai microsecondi
      // (il timestamp del Geolocator può avere precisione ridotta su alcune piattaforme)
      final precisePosition = Position(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(), // ⭐ Precisione ai microsecondi come BLE GPS
        accuracy: position.accuracy,
        altitude: position.altitude,
        altitudeAccuracy: position.altitudeAccuracy,
        heading: position.heading,
        headingAccuracy: position.headingAccuracy,
        speed: position.speed,
        speedAccuracy: position.speedAccuracy,
      );
      _onGpsData(precisePosition);
    });
  }

  void _listenBleGps() {
    _bleGpsSub = _bleService.gpsStream.listen((gpsData) {
      if (_connectedBleDeviceId != null) {
        final data = gpsData[_connectedBleDeviceId!];
        // IMPORTANTE: Rimuovi il check _recording per permettere il lap detection durante formation lap
        if (data != null && mounted) {
          // Converti BLE GPS data in Position
          final position = Position(
            latitude: data.position.latitude,
            longitude: data.position.longitude,
            timestamp: DateTime.now(),
            accuracy: 5.0, // BLE GPS tipicamente ha accuratezza ~5m
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: (data.speed ?? 0.0) / 3.6, // km/h → m/s
            speedAccuracy: 0.0,
          );
          _onGpsData(position);
        }
      }
    });
  }

  void _startAccelerometer() {
    _accelSub = userAccelerometerEvents.listen((event) {
      if (!_recording) return;

      _imuBuffer.add(_ImuSample(
        time: _sessionWatch.elapsed,
        x: event.x,
        y: event.y,
        z: event.z,
      ));

      // Mantieni buffer ultimi 2 secondi
      final cutoff = _sessionWatch.elapsed - const Duration(seconds: 2);
      _imuBuffer.removeWhere((s) => s.time < cutoff);
    });
  }

  void _stopAllStreams() {
    _gpsSub?.cancel();
    _bleGpsSub?.cancel();
    _accelSub?.cancel();
    _bleDeviceStreamSub?.cancel();
  }

  // ============================================================
  // GPS DATA PROCESSING
  // ============================================================

  void _onGpsData(Position pos) {
    // Calcola velocità PRIMA del check _recording (necessario per telemetria live)
    final speedKmh = pos.speed * 3.6;
    _currentSpeedKmh = speedKmh;

    // Traccia max/min speed per Firebase sync (solo se sta registrando)
    if (_recording) {
      if (speedKmh > _maxSpeed) _maxSpeed = speedKmh;
      if (speedKmh < _minSpeed) _minSpeed = speedKmh;
    }

    // Calcola G-force (fusione IMU + GPS)
    final gForce = _calculateGForce(pos);
    _gForceMagnitude = gForce.abs();
    if (gForce >= 0) {
      _gForceX = gForce;
      _gForceY = 0.0;
    } else {
      _gForceX = 0.0;
      _gForceY = gForce.abs();
    }

    // Traccia max G-force per Firebase sync (solo se sta registrando)
    if (_recording && _gForceMagnitude > _maxGForce) {
      _maxGForce = _gForceMagnitude;
    }

    // IMPORTANTE: Sempre processare GPS per lap detection
    // ANCHE durante formation lap, altrimenti non può rilevare il passaggio!
    if (_trackDefinition != null) {
      final wasInFormationLap = _lapDetection.inFormationLap;
      _lapDetection.processGpsPoint(pos);

      // Debug: Log stato formation lap
      if (wasInFormationLap) {
        print('📍 GPS durante formation lap: ${pos.latitude}, ${pos.longitude}, inFormationLap dopo process: ${_lapDetection.inFormationLap}');
      }

      // Se abbiamo completato il formation lap, avvia timer e registrazione
      if (wasInFormationLap && !_lapDetection.inFormationLap && !_timerStarted) {
        _sessionWatch.start();
        _timerStarted = true;
        _recording = true;
        print('✓✓✓ Timer e registrazione avviati dopo formation lap ✓✓✓');
        print('✓✓✓ _recording = $_recording, _timerStarted = $_timerStarted ✓✓✓');
      }
    }

    // Salva GPS grezzo e storia SOLO se _recording è true (dopo formation lap)
    if (_recording) {
      _gpsTrack.add(pos);
      _lastPosition = pos;
      print('📊 GPS salvato in _gpsTrack: totale ${_gpsTrack.length} punti');

      // Aggiorna display path per mappa
      _displayPath.add(LatLng(pos.latitude, pos.longitude));
      if (_displayPath.length > 500) {
        _displayPath = _displayPath.sublist(_displayPath.length - 500);
      }

      // Salva storia per recap
      _speedHistory.add(speedKmh);
      _gForceHistory.add(gForce);
      _gpsAccuracyHistory.add(pos.accuracy);
      _timeHistory.add(_sessionWatch.elapsed);
    }

    // Salva punto GPS per delta live (solo se il timer è partito e non siamo in formation lap)
    if (_trackDefinition != null && _timerStarted && !_lapDetection.inFormationLap) {
      final currentLapTime = _lapDetection.currentLapTime;
      if (currentLapTime != null) {
        _currentLapGpsPoints.add(_LapGpsPoint(
          position: LatLng(pos.latitude, pos.longitude),
          lapTime: currentLapTime,
        ));

        // Calcola delta live se abbiamo un best lap con punti GPS
        if (_bestLapGpsPoints.isNotEmpty) {
          _liveDelta = _calculateLiveDelta(
            LatLng(pos.latitude, pos.longitude),
            currentLapTime,
          );
        }
      }
    }

    // Nessun circuito: avvia timer subito
    if (_trackDefinition == null && !_timerStarted) {
      _sessionWatch.start();
      _timerStarted = true;
    }

    setState(() {});
  }

  double _calculateGForce(Position pos) {
    final speedMs = pos.speed;

    // Calcola accelerazione da GPS (delta velocità)
    double accelFromSpeed = 0.0;
    if (_prevSpeedMs != null && _prevSpeedTime != null) {
      final dt = pos.timestamp!.difference(_prevSpeedTime!).inMilliseconds / 1000.0;
      if (dt > 0) {
        final deltaSpeed = speedMs - _prevSpeedMs!;
        accelFromSpeed = (deltaSpeed / dt) / 9.81; // G
      }
    }

    _prevSpeedMs = speedMs;
    _prevSpeedTime = pos.timestamp;

    // Calcola G-force medio da IMU (ultimi 600ms)
    final imuG = _averageImuG(windowMs: 600);

    // Fusione: 70% IMU, 30% GPS
    final sign = accelFromSpeed >= 0 ? 1.0 : -1.0;
    final fused = 0.7 * imuG * sign + 0.3 * accelFromSpeed;
    return fused.clamp(-2.5, 2.5);
  }

  double _averageImuG({required int windowMs}) {
    if (_imuBuffer.isEmpty) return 0.0;

    final cutoff = _sessionWatch.elapsed - Duration(milliseconds: windowMs);
    final samples = _imuBuffer.where((s) => s.time >= cutoff).toList();

    if (samples.isEmpty) return 0.0;

    double sumX = 0.0;
    for (final s in samples) {
      sumX += s.x;
    }

    return (sumX / samples.length) / 9.81;
  }

  void _onLapCompleted(Duration lapTime) {
    _laps.add(lapTime);
    _previousLap = lapTime;

    // Aggiorna best lap e salva i punti GPS se è il nuovo best
    final isNewBest = _bestLap == null || lapTime < _bestLap!;
    if (isNewBest) {
      _bestLap = lapTime;
      // Salva i punti GPS del giro appena completato come riferimento per il delta
      _bestLapGpsPoints = List.from(_currentLapGpsPoints);
      print('✓ Nuovo best lap! Salvati ${_bestLapGpsPoints.length} punti GPS per delta');
    }

    // Reset punti GPS per il prossimo giro
    _currentLapGpsPoints.clear();
    _liveDelta = null;

    print('✓ Lap completato: ${_formatLap(lapTime)} (best: ${_formatLap(_bestLap!)})');

    // Sync immediato a Firebase dopo ogni giro completato
    _syncDataToFirebase();

    setState(() {});
  }

  /// Calcola il delta live basato sulla posizione GPS
  /// Trova il punto più vicino nel best lap e confronta i tempi
  double? _calculateLiveDelta(LatLng currentPosition, Duration currentLapTime) {
    if (_bestLapGpsPoints.isEmpty) return null;

    // Trova il punto nel best lap più vicino alla posizione attuale
    double minDistance = double.infinity;
    _LapGpsPoint? closestPoint;

    final currentPoint = _LapGpsPoint(
      position: currentPosition,
      lapTime: currentLapTime,
    );

    for (final bestPoint in _bestLapGpsPoints) {
      final dist = currentPoint.distanceTo(bestPoint);
      if (dist < minDistance) {
        minDistance = dist;
        closestPoint = bestPoint;
      }
    }

    // Se il punto più vicino è troppo lontano (>50m), non calcolare delta
    // Questo può succedere se il pilota taglia o sbaglia percorso
    if (closestPoint == null || minDistance > 50) {
      return null;
    }

    // Delta = tempo corrente - tempo del best lap allo stesso punto
    // Negativo = più veloce, Positivo = più lento
    final deltaMs = currentLapTime.inMilliseconds - closestPoint.lapTime.inMilliseconds;
    return deltaMs / 1000.0;
  }

  // ============================================================
  // SESSION END
  // ============================================================

  Future<void> _finishSession() async {
    if (_sessionFinished) return;

    setState(() {
      _recording = false;
      _sessionFinished = true;
    });

    _sessionWatch.stop();
    _stopAllStreams();

    // Debug: Log dati finali
    print('🏁 Sessione Gran Prix terminata:');
    print('   GPS Track: ${_gpsTrack.length} punti');
    print('   Speed History: ${_speedHistory.length} punti');
    print('   GForce History: ${_gForceHistory.length} punti');
    print('   Laps: ${_laps.length}');
    print('   Recording: $_recording');
    print('   Timer Started: $_timerStarted');

    // Naviga a pagina statistiche Gran Prix
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GrandPrixStatisticsPage(
          lobbyCode: widget.lobbyCode,
        ),
      ),
    );
  }

  // ============================================================
  // FORMATTING
  // ============================================================

  String _formatLap(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  String _formatCurrentLapTime() {
    final currentLap = _lapDetection.currentLapTime;
    if (currentLap == null) {
      return '0:00.00';
    }
    final minutes = currentLap.inMinutes;
    final seconds = currentLap.inSeconds % 60;
    final hundredths = (currentLap.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }

  String _formatSessionTime() {
    if (!_timerStarted) return '0:00.00';

    final elapsed = _sessionWatch.elapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final hundredths = (elapsed.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }

  String _formatLapPrecise(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final thousandths = d.inMilliseconds % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${thousandths.toString().padLeft(3, '0')}';
  }

  // ============================================================
  // UI - AIM MXS Style (Landscape)
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        children: [
          _buildAIMDisplay(),
          // Formation lap banner
          if (_trackDefinition != null && _lapDetection.inFormationLap)
            _buildFormationLapBanner(),
        ],
      ),
    );
  }

  /// Layout principale stile AIM MXS - Layout orizzontale
  Widget _buildAIMDisplay() {
    final hasTrack = _trackDefinition != null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A0A0A),
            Color(0xFF000000),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              // Top bar - Status e info
              _buildTopBar(),
              const SizedBox(height: 8),
              // Main display - Layout AIM
              Expanded(
                child: Row(
                  children: [
                    // LEFT - Current Lap Time (GIGANTE)
                    Expanded(
                      flex: 5,
                      child: _buildCurrentLapPanel(hasTrack),
                    ),
                    const SizedBox(width: 12),
                    // RIGHT - Delta, Best, Last
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          // DELTA LIVE - Prominente
                          Expanded(
                            flex: 5,
                            child: _buildDeltaPanel(hasTrack),
                          ),
                          const SizedBox(height: 8),
                          // BEST e LAST
                          Expanded(
                            flex: 4,
                            child: Row(
                              children: [
                                Expanded(child: _buildBestLapPanel()),
                                const SizedBox(width: 8),
                                Expanded(child: _buildLastLapPanel()),
                              ],
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
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          // Lap counter
          if (_trackDefinition != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Text(
                    'LAP',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_laps.length + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          // END Session button (solo per host)
          if (_isHost)
            GestureDetector(
              onTap: () async {
                // Host ferma la sessione per tutti
                await _grandPrixService.stopSession(widget.lobbyCode);
                // _finishSession verrà chiamato automaticamente da _watchLobbyStatus
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.stop_rounded, color: Colors.red, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'END',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isHost) const SizedBox(width: 16),
          // BLE indicator
          if (_isUsingBleGps)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: kBrandColor.withAlpha(100)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_connected, color: kBrandColor, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'GPS PRO',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          // Track name
          if (_trackDefinition != null)
            Text(
              _trackDefinition!.name.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white.withAlpha(100),
                letterSpacing: 1,
              ),
            ),
          const SizedBox(width: 16),
          // Speed
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Text(
                  '${_currentSpeedKmh.toInt()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'km/h',
                  style: TextStyle(
                    color: Colors.white.withAlpha(80),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Panel CURRENT LAP - Il più grande, stile AIM
  Widget _buildCurrentLapPanel(bool hasTrack) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withAlpha(8),
            Colors.white.withAlpha(4),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Stack(
        children: [
          // Background pattern (grid effect like AIM)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _GridPatternPainter(),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Label
                Text(
                  hasTrack ? 'CURRENT LAP' : 'SESSION TIME',
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                const Spacer(),
                // TEMPO GIGANTE
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    hasTrack ? _formatCurrentLapTime() : _formatSessionTime(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                // G-Force bar compatta
                _buildCompactGForceBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactGForceBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'G',
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          // Brake bar
          Container(
            width: 60,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withAlpha(15),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: (_gForceY / 1.0).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Accel bar
          Container(
            width: 60,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withAlpha(15),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (_gForceX / 1.0).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _gForceMagnitude.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Panel DELTA LIVE - Stile AIM con barra grafica
  Widget _buildDeltaPanel(bool hasTrack) {
    if (!hasTrack || _bestLap == null || _laps.isEmpty) {
      // No delta disponibile - mostra placeholder
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'DELTA',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '---',
                style: TextStyle(
                  color: Colors.white.withAlpha(60),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              // Barra vuota placeholder
              _buildDeltaBarPlaceholder(),
            ],
          ),
        ),
      );
    }

    final currentLap = _lapDetection.currentLapTime;
    // Usa il delta GPS-based se disponibile, altrimenti mostra placeholder
    if (currentLap == null || _liveDelta == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'DELTA',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '---',
                style: TextStyle(
                  color: Colors.white.withAlpha(60),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              _buildDeltaBarPlaceholder(),
            ],
          ),
        ),
      );
    }

    // Usa il delta live GPS-based (calcolato in _onGpsData)
    final deltaSeconds = _liveDelta!;
    final isNegative = deltaSeconds < 0; // Ahead of best (faster)
    final isPositive = deltaSeconds > 0; // Behind best (slower)

    // Colore del valore numerico
    final Color valueColor;
    if (isNegative) {
      valueColor = const Color(0xFF00E676); // Verde brillante
    } else if (isPositive) {
      valueColor = const Color(0xFFFF5252); // Rosso brillante
    } else {
      valueColor = Colors.white;
    }

    final deltaString = isNegative
        ? '-${deltaSeconds.abs().toStringAsFixed(3)}'
        : '+${deltaSeconds.toStringAsFixed(3)}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Label DELTA
            Text(
              'DELTA',
              style: TextStyle(
                color: Colors.white.withAlpha(120),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 4),
            // Valore numerico (più piccolo)
            Text(
              deltaString,
              style: TextStyle(
                color: valueColor,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            // Barra grafica AIM style
            _buildDeltaBar(deltaSeconds),
          ],
        ),
      ),
    );
  }

  /// Barra placeholder quando non c'è delta
  Widget _buildDeltaBarPlaceholder() {
    return Column(
      children: [
        // Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '−',
              style: TextStyle(
                color: Colors.white.withAlpha(40),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '+',
              style: TextStyle(
                color: Colors.white.withAlpha(40),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Barra vuota
        Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withAlpha(10),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
        ),
      ],
    );
  }

  /// Barra grafica delta stile AIM
  /// - Centro = on pace (0)
  /// - Sinistra = più veloce (negativo, verde)
  /// - Destra = più lento (positivo, rosso)
  Widget _buildDeltaBar(double deltaSeconds) {
    // Limita il delta a ±5 secondi per la visualizzazione
    const maxDelta = 5.0;
    final clampedDelta = deltaSeconds.clamp(-maxDelta, maxDelta);

    // Calcola la posizione dell'indicatore (0.0 = sinistra, 1.0 = destra)
    // Centro (0.5) = on pace
    // < 0.5 = più veloce (verde)
    // > 0.5 = più lento (rosso)
    final indicatorPosition = 0.5 + (clampedDelta / maxDelta) * 0.5;

    return Column(
      children: [
        // Labels - e +
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '−',
              style: TextStyle(
                color: const Color(0xFF00E676).withAlpha(200),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '+',
              style: TextStyle(
                color: const Color(0xFFFF5252).withAlpha(200),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Barra con gradiente e indicatore
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final indicatorX = barWidth * indicatorPosition;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Sfondo barra con gradiente
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF00C853), // Verde a sinistra (più veloce)
                        Color(0xFF1A1A1A), // Neutro al centro
                        Color(0xFFD50000), // Rosso a destra (più lento)
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                ),
                // Linea centrale (on pace)
                Positioned(
                  left: barWidth / 2 - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.white.withAlpha(60),
                  ),
                ),
                // Indicatore triangolare
                Positioned(
                  left: indicatorX - 10,
                  top: -8,
                  child: CustomPaint(
                    size: const Size(20, 12),
                    painter: _TriangleIndicatorPainter(
                      color: Colors.white,
                    ),
                  ),
                ),
                // Indicatore linea verticale
                Positioned(
                  left: indicatorX - 2,
                  top: 0,
                  child: Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withAlpha(150),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        // Scala numerica
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '-5s',
              style: TextStyle(
                color: Colors.white.withAlpha(60),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '0',
              style: TextStyle(
                color: Colors.white.withAlpha(80),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '+5s',
              style: TextStyle(
                color: Colors.white.withAlpha(60),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Panel BEST LAP
  Widget _buildBestLapPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.withAlpha(30),
            Colors.purple.withAlpha(15),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emoji_events,
                  color: Colors.purple.withAlpha(200),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'BEST',
                  style: TextStyle(
                    color: Colors.purple.withAlpha(200),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _bestLap != null ? _formatLapPrecise(_bestLap!) : '--:--.---',
                style: TextStyle(
                  color: Colors.purple.shade200,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  /// Panel LAST LAP
  Widget _buildLastLapPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'LAST',
              style: TextStyle(
                color: Colors.white.withAlpha(120),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _previousLap != null ? _formatLapPrecise(_previousLap!) : '--:--.---',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormationLapBanner() {
    return Positioned(
      bottom: 20,
      left: 80,
      right: 80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withAlpha(240),
              Colors.orange.withAlpha(200),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withAlpha(80),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.flag_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 16),
            const Text(
              'FORMATION LAP - Cross finish line to start',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HELPER CLASSES
// ============================================================

class _ImuSample {
  final Duration time;
  final double x;
  final double y;
  final double z;

  _ImuSample({
    required this.time,
    required this.x,
    required this.y,
    required this.z,
  });
}

/// Punto GPS con tempo del giro per calcolo delta live
class _LapGpsPoint {
  final LatLng position;
  final Duration lapTime; // Tempo dall'inizio del giro

  _LapGpsPoint({
    required this.position,
    required this.lapTime,
  });

  /// Calcola la distanza in metri da un altro punto
  double distanceTo(_LapGpsPoint other) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, position, other.position);
  }
}

/// Painter per effetto griglia stile AIM
class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1;

    const spacing = 30.0;

    // Linee verticali
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Linee orizzontali
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter per indicatore triangolare della barra delta
class _TriangleIndicatorPainter extends CustomPainter {
  final Color color;

  _TriangleIndicatorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = ui.Path()
      ..moveTo(size.width / 2, size.height) // Punta in basso
      ..lineTo(0, 0) // Angolo superiore sinistro
      ..lineTo(size.width, 0) // Angolo superiore destro
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
