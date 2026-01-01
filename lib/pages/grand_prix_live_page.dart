import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../models/track_definition.dart';
import '../models/grand_prix_models.dart';
import '../services/grand_prix_service.dart';
import '../services/ble_tracking_service.dart';
import '../services/lap_detection_service.dart';
import '../services/track_service.dart';
import 'grand_prix_statistics_page.dart';

class GrandPrixLivePage extends StatefulWidget {
  final String lobbyCode;

  const GrandPrixLivePage({super.key, required this.lobbyCode});

  @override
  State<GrandPrixLivePage> createState() => _GrandPrixLivePageState();
}

class _GrandPrixLivePageState extends State<GrandPrixLivePage> {
  final _grandPrixService = GrandPrixService();
  final _trackService = TrackService();
  final _bleService = BleTrackingService();
  final _lapDetection = LapDetectionService();
  final _auth = FirebaseAuth.instance;

  // Session state
  bool _recording = false;
  bool _sessionFinished = false;
  final Stopwatch _sessionWatch = Stopwatch();
  Timer? _uiTimer;
  Timer? _syncTimer;

  // GPS tracking
  final List<Position> _gpsTrack = [];
  Position? _lastPosition;

  // Lap data
  final List<Duration> _laps = [];
  Duration? _bestLap;
  Duration? _previousLap;
  int _currentLap = 0;
  bool _isFormationLap = true;

  // Telemetry
  double _currentSpeedKmh = 0.0;
  double _gForceX = 0.0;
  double _gForceY = 0.0;
  double _maxSpeed = 0.0;
  double _maxGForce = 0.0;

  // Subscriptions
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSub;
  StreamSubscription<DatabaseEvent>? _lobbySub;

  // BLE GPS
  String? _connectedBleDeviceId;
  bool _isUsingBleGps = false;

  // Lobby data
  GrandPrixLobby? _lobby;
  TrackDefinition? _trackDefinition;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadLobbyAndStart();
  }

  @override
  void dispose() {
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

  Future<void> _loadLobbyAndStart() async {
    // Check if host
    _isHost = await _grandPrixService.isHost(widget.lobbyCode);

    // Get lobby data
    final lobbyData = await _grandPrixService.getLobbyData(widget.lobbyCode);
    if (lobbyData == null || lobbyData['trackId'] == null) {
      _showError('Errore nel caricamento della lobby');
      Navigator.of(context).pop();
      return;
    }

    // Load track definition
    final trackId = lobbyData['trackId'] as String;
    final trackWithMetadata = await _trackService.getTrackById(trackId);

    if (trackWithMetadata == null) {
      _showError('Errore nel caricamento del circuito');
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _trackDefinition = trackWithMetadata.trackDefinition;
    });

    // Initialize lap detection
    _lapDetection.initializeWithFinishLine(
      trackWithMetadata.trackDefinition.finishLineStart!,
      trackWithMetadata.trackDefinition.finishLineEnd!,
    );
    _lapDetection.onLapCompleted = _onLapCompleted;

    // Watch lobby changes
    _watchLobby();

    // Start session
    _startSession();
  }

  void _watchLobby() {
    _lobbySub = _grandPrixService.watchLobby(widget.lobbyCode).listen((event) {
      if (!event.snapshot.exists) {
        if (mounted) {
          _showError('La lobby è stata chiusa');
          Navigator.of(context).pop();
        }
        return;
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final lobby = GrandPrixLobby.fromMap(widget.lobbyCode, data);

      if (mounted) {
        setState(() {
          _lobby = lobby;
        });

        // If session finished, navigate to statistics
        if (lobby.status == 'finished' && !_sessionFinished) {
          _sessionFinished = true;
          _finishSession();
        }
      }
    });
  }

  void _startSession() {
    // Start GPS and sensors
    _syncBleDevice();
    _startGpsStream();
    _startAccelerometer();

    // UI timer (50ms for precision)
    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _recording) {
        setState(() {});
      }
    });

    // Sync timer (update Realtime DB every 500ms)
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_recording) {
        _syncLiveData();
      }
    });
  }

  void _syncBleDevice() {
    final connectedIds = _bleService.getConnectedDeviceIds();
    if (connectedIds.isNotEmpty) {
      _connectedBleDeviceId = connectedIds.first;
      _isUsingBleGps = true;
      _listenBleGps();
    }
  }

  void _startGpsStream() {
    if (_isUsingBleGps) return;

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((position) {
      _processGpsPoint(position);
    });
  }

  void _listenBleGps() {
    _bleGpsSub?.cancel();
    if (_connectedBleDeviceId == null) return;

    _bleGpsSub = _bleService.gpsStream.listen((allGpsData) {
      final gpsData = allGpsData[_connectedBleDeviceId];
      if (gpsData != null) {
        final position = Position(
          latitude: gpsData.position.latitude,
          longitude: gpsData.position.longitude,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 0.0,
          heading: 0.0,
          speed: gpsData.speed ?? 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        _processGpsPoint(position);
      }
    });
  }

  void _startAccelerometer() {
    _accelSub = userAccelerometerEventStream().listen((event) {
      if (!mounted) return;

      // Calculate G-force
      final gx = event.x / 9.81;
      final gy = event.y / 9.81;
      final magnitude = math.sqrt(gx * gx + gy * gy);

      setState(() {
        _gForceX = gx.abs();
        _gForceY = gy.abs();
        if (magnitude > _maxGForce) {
          _maxGForce = magnitude;
        }
      });
    });
  }

  void _processGpsPoint(Position position) {
    if (!mounted) return;

    // Update speed
    final speedKmh = position.speed * 3.6;
    setState(() {
      _currentSpeedKmh = speedKmh;
      if (speedKmh > _maxSpeed) {
        _maxSpeed = speedKmh;
      }
    });

    // IMPORTANTE: Sempre passare i punti GPS al lap detection
    // ANCHE durante il formation lap, altrimenti non può rilevare il passaggio!
    if (_trackDefinition != null) {
      final wasInFormationLap = _isFormationLap;
      _lapDetection.processGpsPoint(position);

      // Check if formation lap completed and start recording
      if (wasInFormationLap && _lapDetection.formationLapCrossed) {
        setState(() {
          _isFormationLap = false;
          _recording = true;
        });
        _sessionWatch.start();
        print('✓ Formation lap completato, inizia registrazione');
      }
    }

    // Store GPS point only after formation lap
    if (_recording) {
      _gpsTrack.add(position);
      _lastPosition = position;
    }
  }

  void _onLapCompleted(Duration lapTime) {
    if (_isFormationLap) return; // Skip formation lap

    setState(() {
      _laps.add(lapTime);
      _previousLap = lapTime;
      _currentLap = _laps.length;

      // Update best lap
      if (_bestLap == null || lapTime < _bestLap!) {
        _bestLap = lapTime;
      }
    });

    HapticFeedback.mediumImpact();
    print('✓ Giro $_currentLap completato: ${_formatDuration(lapTime)}');
  }

  Future<void> _syncLiveData() async {
    if (_lobby == null) return;

    final data = {
      'currentLap': _currentLap,
      'lapTimes': _laps.map((d) => d.inMilliseconds / 1000.0).toList(),
      'bestLap': _bestLap != null ? _bestLap!.inMilliseconds / 1000.0 : null,
      'totalLaps': _laps.length,
      'maxSpeed': _maxSpeed,
      'maxGForce': _maxGForce,
      'isFormationLap': _isFormationLap,
    };

    await _grandPrixService.updateLiveData(widget.lobbyCode, data);
  }

  void _stopAllStreams() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _bleGpsSub?.cancel();
    _lobbySub?.cancel();
  }

  Future<void> _stopSession() async {
    if (!_isHost) {
      _showError('Solo l\'host può fermare la sessione');
      return;
    }

    HapticFeedback.heavyImpact();

    try {
      await _grandPrixService.stopSession(widget.lobbyCode);
      // Navigation handled by lobby watcher
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _finishSession() {
    _stopAllStreams();
    _sessionWatch.stop();
    _uiTimer?.cancel();
    _syncTimer?.cancel();

    // Navigate to statistics
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GrandPrixStatisticsPage(lobbyCode: widget.lobbyCode),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = d.inMilliseconds % 1000;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _buildLandscapeLayout(),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // Left panel - Main telemetry
        Expanded(
          flex: 2,
          child: Container(
            color: const Color(0xFF0A0A0A),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                Expanded(child: _buildMainTelemetry()),
              ],
            ),
          ),
        ),
        // Right panel - Lap data
        Expanded(
          flex: 1,
          child: Container(
            color: const Color(0xFF050505),
            padding: const EdgeInsets.all(12),
            child: _buildLapDataPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _trackDefinition?.name ?? 'Gran Premio',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isFormationLap ? 'FORMATION LAP' : 'IN GARA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _isFormationLap ? Colors.orange : kBrandColor,
                  ),
                ),
              ],
            ),
          ),
          if (_isHost)
            GestureDetector(
              onTap: _stopSession,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red, width: 1),
                ),
                child: const Text(
                  'STOP',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.red,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainTelemetry() {
    return Column(
      children: [
        // Speed
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBrandColor.withOpacity(0.3), width: 1),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentSpeedKmh.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w900,
                      color: kBrandColor,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'KM/H',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Timer and lap count
        Row(
          children: [
            Expanded(child: _buildTimerCard()),
            const SizedBox(width: 12),
            Expanded(child: _buildLapCountCard()),
          ],
        ),
        const SizedBox(height: 12),
        // G-force indicators
        _buildGForceIndicators(),
      ],
    );
  }

  Widget _buildTimerCard() {
    final elapsed = _sessionWatch.elapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final millis = elapsed.inMilliseconds % 1000;
    final timeStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${(millis ~/ 10).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TEMPO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kMutedColor,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: kFgColor,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapCountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GIRO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kMutedColor,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isFormationLap ? 'FL' : '$_currentLap',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _isFormationLap ? Colors.orange : kBrandColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGForceIndicators() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, color: Colors.green, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'ACCEL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kMutedColor,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (_gForceY / 1.0).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.green, Colors.lightGreenAccent],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_downward, color: Colors.red, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'BRAKE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kMutedColor,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (_gForceX / 1.0).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.orangeAccent],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLapDataPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLapTimeCard('BEST', _bestLap, kBrandColor),
        const SizedBox(height: 8),
        _buildLapTimeCard('PREV', _previousLap, Colors.purple),
        const SizedBox(height: 16),
        Expanded(child: _buildLapHistory()),
      ],
    );
  }

  Widget _buildLapTimeCard(String label, Duration? time, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kMutedColor,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time != null ? _formatDuration(time) : '--:--.---',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: time != null ? color : kMutedColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapHistory() {
    if (_laps.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
        ),
        child: Center(
          child: Text(
            'Nessun giro completato',
            style: TextStyle(
              fontSize: 12,
              color: kMutedColor,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GIRI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kMutedColor,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _laps.length,
              itemBuilder: (context, index) {
                final lapNum = _laps.length - index;
                final lapTime = _laps[_laps.length - index - 1];
                final isBest = lapTime == _bestLap;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isBest
                        ? kBrandColor.withOpacity(0.15)
                        : Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isBest
                          ? kBrandColor.withOpacity(0.5)
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$lapNum',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isBest ? kBrandColor : kMutedColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _formatDuration(lapTime),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isBest ? kBrandColor : kFgColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (isBest)
                        Icon(
                          Icons.star,
                          color: kBrandColor,
                          size: 14,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
