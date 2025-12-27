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
import '../services/ble_tracking_service.dart';
import '../services/lap_detection_service.dart';
import 'session_recap_page.dart';

/// Live Session Page - RaceChrono Pro Style
///
/// Registrazione GPS grezzo + lap counting live best-effort.
/// Post-processing per tempi precisi a fine sessione.
class LiveSessionPage extends StatefulWidget {
  final TrackDefinition? trackDefinition;

  const LiveSessionPage({super.key, this.trackDefinition});

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> {
  // ============================================================
  // STATE
  // ============================================================

  bool _recording = true;
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
  // LIFECYCLE
  // ============================================================

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

  // ============================================================
  // SESSION CONTROL
  // ============================================================

  void _startSession() {
    // Inizializza lap detection se abbiamo un circuito pre-tracciato
    if (widget.trackDefinition != null) {
      _lapDetection.initializeWithFinishLine(
        widget.trackDefinition!.finishLineStart,
        widget.trackDefinition!.finishLineEnd,
      );
      print('✓ Lap detection inizializzato: ${widget.trackDefinition!.name}');
    } else {
      print('⚠️ Nessun circuito pre-tracciato - solo registrazione GPS');
    }

    // Setup lap detection callback
    _lapDetection.onLapCompleted = _onLapCompleted;

    // Timer UI (aggiorna ogni 100ms)
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _recording) {
        setState(() {});
      }
    });

    // Controlla BLE GPS
    _syncBleDeviceFromService();
    _listenBleConnectionChanges();

    // Avvia GPS e sensori
    _startGpsStream();
    _startAccelerometer();
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
    ).listen(_onGpsData);
  }

  void _listenBleGps() {
    _bleGpsSub = _bleService.gpsStream.listen((gpsData) {
      if (_connectedBleDeviceId != null) {
        final data = gpsData[_connectedBleDeviceId!];
        if (data != null && mounted && _recording) {
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
    if (!_recording) return;

    // Salva GPS grezzo
    _gpsTrack.add(pos);
    _lastPosition = pos;

    // Aggiorna display path per mappa
    _displayPath.add(LatLng(pos.latitude, pos.longitude));
    if (_displayPath.length > 500) {
      _displayPath = _displayPath.sublist(_displayPath.length - 500);
    }

    // Calcola velocità
    final speedKmh = pos.speed * 3.6;
    _currentSpeedKmh = speedKmh;

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

    // Salva storia per recap
    _speedHistory.add(speedKmh);
    _gForceHistory.add(gForce);
    _gpsAccuracyHistory.add(pos.accuracy);
    _timeHistory.add(_sessionWatch.elapsed);

    // Lap detection live (best-effort)
    if (widget.trackDefinition != null) {
      final wasInFormationLap = _lapDetection.inFormationLap;
      final crossed = _lapDetection.processGpsPoint(pos);

      // Se abbiamo completato il formation lap, avvia timer
      if (wasInFormationLap && !_lapDetection.inFormationLap && !_timerStarted) {
        _sessionWatch.start();
        _timerStarted = true;
        print('✓ Timer avviato dopo formation lap');
      }
    } else {
      // Nessun circuito: avvia timer subito
      if (!_timerStarted) {
        _sessionWatch.start();
        _timerStarted = true;
      }
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

    // Aggiorna best lap
    if (_bestLap == null || lapTime < _bestLap!) {
      _bestLap = lapTime;
    }

    print('✓ Lap completato: ${_formatLap(lapTime)} (best: ${_formatLap(_bestLap!)})');
    setState(() {});
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

    // Naviga a recap
    if (!mounted) return;

    // Crea smoothPath da gpsTrack per visualizzazione mappa
    final smoothPath = _gpsTrack
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionRecapPage(
          gpsTrack: _gpsTrack,
          smoothPath: smoothPath,
          laps: _laps,
          bestLap: _bestLap,
          totalDuration: _sessionWatch.elapsed,
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

  // ============================================================
  // FORMATTING
  // ============================================================

  String _formatLap(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  String _formatDelta() {
    if (_previousLap == null || _bestLap == null || _laps.length <= 1) {
      return '---';
    }

    Duration referenceTime;
    if (_previousLap == _bestLap) {
      // Best lap appena fatto: confronta con secondo miglior tempo
      final otherLaps = _laps.sublist(0, _laps.length - 1);
      if (otherLaps.isEmpty) return '---';
      referenceTime = otherLaps.reduce((a, b) => a < b ? a : b);
    } else {
      referenceTime = _bestLap!;
    }

    final diffSeconds = (_previousLap!.inMilliseconds - referenceTime.inMilliseconds) / 1000.0;
    final sign = diffSeconds > 0 ? '+' : '';
    return '$sign${diffSeconds.toStringAsFixed(1)}';
  }

  String _formatSessionTime() {
    if (!_timerStarted) return '0:00';

    final elapsed = _sessionWatch.elapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // UI - RaceChrono Pro Style
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Stack(
          children: [
            // Main dashboard
            Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildMainDisplay()),
                _buildGForceBar(),
                _buildStopButton(),
              ],
            ),

            // Banner formation lap
            if (widget.trackDefinition != null && _lapDetection.inFormationLap)
              _buildFormationLapBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Recording indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.withAlpha(150)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'REC',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // BLE indicator
          if (_isUsingBleGps)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kBrandColor.withAlpha(100)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_connected, color: kBrandColor, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'GPS',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          // Session time
          Text(
            _formatSessionTime(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white.withAlpha(150),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainDisplay() {
    final currentLap = _lapDetection.currentLapTime;
    final hasTrack = widget.trackDefinition != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // LAP NUMBER - prominent
          if (hasTrack)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LAP',
                    style: TextStyle(
                      color: Colors.white.withAlpha(100),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_laps.length + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(flex: 1),

          // CURRENT LAP TIME - MASSIVE
          if (hasTrack) ...[
            Text(
              currentLap != null ? _formatLapPrecise(currentLap) : '0:00.00',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'CURRENT LAP',
              style: TextStyle(
                color: Colors.white.withAlpha(80),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ] else ...[
            // No track - show session timer big
            Text(
              _formatSessionTime(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'SESSION TIME',
              style: TextStyle(
                color: Colors.white.withAlpha(80),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],

          const Spacer(flex: 1),

          // DELTA TIME - prominent when available
          if (hasTrack && _bestLap != null && currentLap != null)
            _buildLiveDelta(currentLap),

          if (hasTrack) const SizedBox(height: 24),

          // LAST LAP & BEST LAP - side by side
          if (hasTrack) _buildLapComparison(),

          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _buildLiveDelta(Duration currentLap) {
    // Calculate live delta against best lap
    final deltaMs = currentLap.inMilliseconds - _bestLap!.inMilliseconds;
    final deltaSeconds = deltaMs / 1000.0;
    final isAhead = deltaMs < 0;

    // Only show delta if we have meaningful data
    if (_laps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: isAhead
            ? Colors.green.withAlpha(25)
            : Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAhead
              ? Colors.green.withAlpha(80)
              : Colors.red.withAlpha(80),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'DELTA',
            style: TextStyle(
              color: (isAhead ? Colors.green : Colors.red).withAlpha(180),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${isAhead ? '-' : '+'}${deltaSeconds.abs().toStringAsFixed(2)}',
            style: TextStyle(
              color: isAhead ? Colors.green : Colors.red,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapComparison() {
    return Row(
      children: [
        // LAST LAP
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Column(
              children: [
                Text(
                  'LAST LAP',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _previousLap != null ? _formatLapPrecise(_previousLap!) : '--:--.--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (_previousLap != null && _bestLap != null && _laps.length > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    _formatDelta(),
                    style: TextStyle(
                      color: _formatDelta().startsWith('+')
                          ? Colors.red.withAlpha(200)
                          : Colors.green.withAlpha(200),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // BEST LAP
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.purple.withAlpha(20),
                  Colors.purple.withAlpha(10),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withAlpha(60)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.emoji_events,
                      color: Colors.purple.withAlpha(180),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'BEST LAP',
                      style: TextStyle(
                        color: Colors.purple.withAlpha(200),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _bestLap != null ? _formatLapPrecise(_bestLap!) : '--:--.--',
                  style: TextStyle(
                    color: Colors.purple.shade200,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGForceBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'G-FORCE',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              Text(
                _gForceMagnitude.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // BRAKE indicator
              Text(
                'BRAKE',
                style: TextStyle(
                  color: Colors.red.withAlpha(150),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              // Decel bar (right to left)
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.white.withAlpha(15),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: (_gForceY / 2.5).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.withAlpha(180),
                              Colors.red,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withAlpha(100),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Accel bar (left to right)
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.white.withAlpha(15),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (_gForceX / 2.5).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            colors: [
                              Colors.green,
                              Colors.green.withAlpha(180),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withAlpha(100),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ACCEL indicator
              Text(
                'ACCEL',
                style: TextStyle(
                  color: Colors.green.withAlpha(150),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStopButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _finishSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.withAlpha(30),
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.withAlpha(150), width: 1.5),
            ),
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stop_rounded, size: 22),
              SizedBox(width: 10),
              Text(
                'END SESSION',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormationLapBanner() {
    return Positioned(
      top: 80,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withAlpha(220),
              Colors.orange.withAlpha(180),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withAlpha(50),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.flag_rounded, color: Colors.white, size: 22),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Cross the start/finish line to begin timing',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLapPrecise(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final hundredths = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
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
