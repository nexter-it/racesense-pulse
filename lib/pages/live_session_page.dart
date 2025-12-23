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
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Mappa (opzionale)
            _buildMap(),

            // Dashboard sovrapposta
            Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildDashboard()),
                _buildBottomControls(),
              ],
            ),

            // Banner formation lap
            if (widget.trackDefinition != null && _lapDetection.inFormationLap)
              _buildFormationLapBanner(),

            // Banner post-processing
            if (widget.trackDefinition != null && !_lapDetection.inFormationLap)
              _buildPostProcessingBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_displayPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _displayPath.last,
          initialZoom: 17.0,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.racesense.pulse',
          ),
          if (_displayPath.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _displayPath,
                  strokeWidth: 4,
                  color: kBrandColor,
                ),
              ],
            ),
          if (_displayPath.isNotEmpty)
            MarkerLayer(
              markers: [
                Marker(
                  point: _displayPath.last,
                  width: 16,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBrandColor,
                      boxShadow: [
                        BoxShadow(
                          color: kBrandColor.withAlpha(128),
                          blurRadius: 16,
                          spreadRadius: 4,
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kBgColor.withAlpha(240),
        border: const Border(bottom: BorderSide(color: kLineColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, color: Colors.red, size: 12),
          const SizedBox(width: 8),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          if (_isUsingBleGps)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: kBrandColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.bluetooth_connected, color: kBrandColor, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'BLE GPS',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          Text(
            _formatSessionTime(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: kFgColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kBgColor.withAlpha(240),
            kBgColor.withAlpha(200),
          ],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Velocità - MOLTO PIÙ GRANDE
          Text(
            _currentSpeedKmh.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 130,
              fontWeight: FontWeight.w900,
              color: kFgColor,
              height: 0.9,
              letterSpacing: -4,
            ),
          ),
          const Text(
            'km/h',
            style: TextStyle(
              fontSize: 24,
              color: kMutedColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: 24),

          // Lap info
          if (widget.trackDefinition != null) ...[
            _buildLapInfo(),
            const SizedBox(height: 24),
          ],

          // G-Force
          _buildGForceIndicator(),

          const Spacer(),

          // Tempo totale sessione (invece di stats GPS)
          _buildSessionTime(),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLapInfo() {
    final currentLap = _lapDetection.currentLapTime;

    return Column(
      children: [
        // LAP NUMBER - Più grande
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'LAP ',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            Text(
              '${_laps.length + 1}',
              style: const TextStyle(
                color: kBrandColor,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // CURRENT LAP TIME - MOLTO PIÙ GRANDE
        Text(
          currentLap != null ? _formatLap(currentLap) : '0:00.0',
          style: const TextStyle(
            color: kFgColor,
            fontSize: 56,
            fontWeight: FontWeight.w900,
            height: 1.0,
            letterSpacing: -1,
          ),
        ),
        const Text(
          'TEMPO CORRENTE',
          style: TextStyle(
            color: kMutedColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),

        const SizedBox(height: 20),

        // BEST LAP - Più prominente
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                Colors.green.withAlpha(30),
                Colors.green.withAlpha(10),
              ],
            ),
            border: Border.all(color: Colors.green.withAlpha(100), width: 1.5),
          ),
          child: Column(
            children: [
              const Text(
                'TEMPO MIGLIORE',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _bestLap != null ? _formatLap(_bestLap!) : '---',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),

        // Delta e Previous (più piccoli, secondari)
        if (_previousLap != null) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous lap
              Column(
                children: [
                  const Text(
                    'PRECEDENTE',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatLap(_previousLap!),
                    style: const TextStyle(
                      color: kFgColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                width: 1,
                height: 30,
                color: kLineColor,
              ),

              // Delta
              Column(
                children: [
                  const Text(
                    'DELTA',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDelta(),
                    style: TextStyle(
                      color: _formatDelta().startsWith('+') ? Colors.red : Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildGForceIndicator() {
    return Column(
      children: [
        const Text(
          'G-FORCE',
          style: TextStyle(
            color: kMutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Decel (braking)
            Container(
              width: 60,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: kLineColor,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 60 * (_gForceY / 2.5).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.red,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              _gForceMagnitude.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: kFgColor,
              ),
            ),
            const SizedBox(width: 16),
            // Accel
            Container(
              width: 60,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: kLineColor,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 60 * (_gForceX / 2.5).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSessionTime() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, 0.08),
            Color.fromRGBO(255, 255, 255, 0.04),
          ],
        ),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Tempo totale
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.timer_outlined, color: kBrandColor, size: 22),
                const SizedBox(height: 6),
                const Text(
                  'DURATA TOTALE',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatSessionTime(),
                  style: const TextStyle(
                    color: kFgColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          Container(width: 1, height: 50, color: kLineColor),

          // Numero giri completati
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.flag, color: kBrandColor, size: 22),
                const SizedBox(height: 6),
                const Text(
                  'GIRI COMPLETATI',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _laps.length.toString(),
                  style: const TextStyle(
                    color: kFgColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kBgColor.withAlpha(240),
        border: const Border(top: BorderSide(color: kLineColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _finishSession,
              icon: const Icon(Icons.stop),
              label: const Text(
                'TERMINA SESSIONE',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kErrorColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormationLapBanner() {
    return Positioned(
      top: 80,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withAlpha(220),
              Colors.orange.withAlpha(180),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange, width: 2),
        ),
        child: Row(
          children: const [
            Icon(Icons.flag, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Passa dalla linea del via per iniziare',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostProcessingBanner() {
    return Positioned(
      bottom: 90,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kBrandColor.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBrandColor.withAlpha(100)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.info_outline, color: kBrandColor, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tempi giro finali dopo elaborazione',
                style: TextStyle(
                  color: kBrandColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
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
