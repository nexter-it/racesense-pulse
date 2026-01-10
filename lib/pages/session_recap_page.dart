import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';
import '../widgets/session_metadata_dialog.dart';
import '../services/session_service.dart';
import '../services/firestore_service.dart';
import '../models/session_model.dart';
import '../models/track_definition.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class SessionRecapPage extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<LatLng> smoothPath;
  final List<Duration> laps;
  final Duration totalDuration;
  final Duration? bestLap;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;
  final List<double> rollAngleHistory; // Storia angolo inclinazione
  final TrackDefinition? trackDefinition;
  final bool usedBleDevice;
  final String? vehicleCategory;

  const SessionRecapPage({
    super.key,
    required this.gpsTrack,
    required this.smoothPath,
    required this.laps,
    required this.totalDuration,
    this.bestLap,
    required this.speedHistory,
    required this.gForceHistory,
    required this.gpsAccuracyHistory,
    required this.timeHistory,
    required this.rollAngleHistory, // Richiesto
    this.trackDefinition,
    this.usedBleDevice = false,
    this.vehicleCategory,
  });

  @override
  State<SessionRecapPage> createState() => _SessionRecapPageState();
}

class _SessionRecapPageState extends State<SessionRecapPage>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isSaving = false;
  String? _detectedWeather;
  bool _isLoadingWeather = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rileva il meteo all'avvio
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    print('🌤️ [SessionRecap] Inizio rilevamento meteo...');
    final weather = await _detectWeather();
    print('🌤️ [SessionRecap] Meteo rilevato: $weather');
    if (mounted) {
      setState(() {
        _detectedWeather = weather;
        _isLoadingWeather = false;
        print('🌤️ [SessionRecap] Stato aggiornato - weather: $_detectedWeather, loading: $_isLoadingWeather');
      });
    } else {
      print('❌ [SessionRecap] Widget non più montato, impossibile aggiornare lo stato');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  double _calculateDistance() {
    if (widget.gpsTrack.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < widget.gpsTrack.length; i++) {
      final prev = widget.gpsTrack[i - 1];
      final curr = widget.gpsTrack[i];

      final dLat = (curr.latitude - prev.latitude) * math.pi / 180.0;
      final dLon = (curr.longitude - prev.longitude) * math.pi / 180.0;

      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(prev.latitude * math.pi / 180.0) *
              math.cos(curr.latitude * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);

      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      totalDistance += 6371000 * c;
    }

    return totalDistance / 1000;
  }

  double _getMaxSpeed() {
    if (widget.speedHistory.isEmpty) return 0;
    return widget.speedHistory.reduce(math.max);
  }

  double _getAvgSpeed() {
    if (widget.speedHistory.isEmpty) return 0;
    return widget.speedHistory.reduce((a, b) => a + b) / widget.speedHistory.length;
  }

  double _getMaxGForce() {
    if (widget.gForceHistory.isEmpty) return 0;
    return widget.gForceHistory.map((g) => g.abs()).reduce(math.max);
  }

  double _getAvgGpsAccuracy() {
    if (widget.gpsAccuracyHistory.isEmpty) return 0;
    return widget.gpsAccuracyHistory.reduce((a, b) => a + b) /
        widget.gpsAccuracyHistory.length;
  }

  int _getGpsSampleRate() {
    if (widget.timeHistory.length < 2) return 0;

    int totalIntervals = 0;
    int sumMs = 0;

    for (int i = 1; i < widget.timeHistory.length; i++) {
      final diff =
          widget.timeHistory[i].inMilliseconds - widget.timeHistory[i - 1].inMilliseconds;
      if (diff > 0 && diff < 5000) {
        sumMs += diff;
        totalIntervals++;
      }
    }

    if (totalIntervals == 0) return 0;
    final avgMs = sumMs / totalIntervals;
    return (1000 / avgMs).round();
  }

  Future<String?> _detectWeather() async {
    // Rileva meteo basandosi sulla posizione GPS della sessione
    print('🌍 [Weather] Controllo GPS track...');
    if (widget.gpsTrack.isEmpty) {
      print('❌ [Weather] GPS track vuoto');
      return null;
    }

    try {
      // Prendi la posizione centrale della sessione
      final firstPos = widget.gpsTrack.first;
      final lat = firstPos.latitude;
      final lon = firstPos.longitude;
      print('📍 [Weather] Posizione: lat=$lat, lon=$lon');

      // Usa Open-Meteo API (gratuita, senza API key)
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true';
      print('🌐 [Weather] Chiamata API: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ [Weather] Timeout dopo 5 secondi');
          return http.Response('{"error": "timeout"}', 408);
        },
      );

      print('📡 [Weather] Risposta HTTP: ${response.statusCode}');
      print('📄 [Weather] Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final currentWeather = data['current_weather'];

        print('☁️ [Weather] Current weather data: $currentWeather');

        if (currentWeather != null) {
          final weatherCode = currentWeather['weathercode'] as int;
          final temp = currentWeather['temperature'];

          print('🌡️ [Weather] Weather code: $weatherCode, Temperature: $temp°C');

          // Mappa weather code a descrizione italiana
          String weatherDesc = _weatherCodeToDescription(weatherCode);

          final result = '$weatherDesc • ${temp.round()}°C';
          print('✅ [Weather] Risultato finale: $result');
          return result;
        } else {
          print('⚠️ [Weather] current_weather è null nella risposta');
        }
      } else {
        print('❌ [Weather] Status code non 200: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      print('💥 [Weather] Errore rilevamento meteo: $e');
      print('📚 [Weather] Stack trace: $stackTrace');
    }

    print('❌ [Weather] Ritorno null');
    return null;
  }

  String _weatherCodeToDescription(int code) {
    // WMO Weather interpretation codes
    if (code == 0) return 'Sereno';
    if (code <= 3) return 'Parzialmente nuvoloso';
    if (code <= 48) return 'Nebbioso';
    if (code <= 67) return 'Piovoso';
    if (code <= 77) return 'Neve';
    if (code <= 82) return 'Pioggia intensa';
    if (code <= 86) return 'Neve intensa';
    if (code <= 99) return 'Temporale';
    return 'Variabile';
  }

  Future<void> _handleSaveSession(BuildContext context) async {
    if (_isSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showErrorSnackbar('Devi effettuare il login per salvare la sessione');
      return;
    }

    final metadata = await showDialog<SessionMetadata>(
      context: context,
      builder: (context) => SessionMetadataDialog(
        gpsTrack: widget.gpsTrack,
        trackDefinition: widget.trackDefinition,
      ),
    );

    if (metadata == null) return;

    if (!context.mounted) return;
    setState(() => _isSaving = true);

    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SaveProgressDialog(progress: progressNotifier),
    );

    try {
      // Usa il meteo già rilevato o rilevalo ora se non disponibile
      final weather = _detectedWeather ?? await _detectWeather();

      final sessionService = SessionService();
      final fsService = FirestoreService();
      final userData = await fsService.getUserData(user.uid);
      final username = userData?['username'] as String? ??
          (userData?['fullName'] as String?)
              ?.toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '') ??
          'user';
      await sessionService.saveSession(
        userId: user.uid,
        driverFullName: user.displayName ?? user.email ?? 'Pilota',
        driverUsername: username,
        trackName: metadata.trackName,
        location: metadata.location,
        locationCoords: metadata.locationCoords,
        isPublic: metadata.isPublic,
        gpsTrack: widget.gpsTrack,
        laps: widget.laps,
        totalDuration: widget.totalDuration,
        speedHistory: widget.speedHistory,
        gForceHistory: widget.gForceHistory,
        gpsAccuracyHistory: widget.gpsAccuracyHistory,
        timeHistory: widget.timeHistory,
        rollAngleHistory: widget.rollAngleHistory,
        trackDefinition: widget.trackDefinition,
        usedBleDevice: widget.usedBleDevice,
        vehicleCategory: widget.vehicleCategory,
        weather: weather,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
      );

      if (!context.mounted) return;
      Navigator.of(context).pop();

      _showSuccessSnackbar('Sessione salvata con successo!');

      await Future.delayed(const Duration(seconds: 1));
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar('Errore: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSuccessSnackbar(String message) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.black, size: 20),
            const SizedBox(width: 10),
            Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
          ],
        ),
        backgroundColor: kBrandColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: kErrorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final distance = _calculateDistance();
    final maxSpeed = _getMaxSpeed();
    final avgSpeed = _getAvgSpeed();
    final maxGForce = _getMaxGForce();
    final avgGpsAccuracy = _getAvgGpsAccuracy();
    final gpsSampleRate = _getGpsSampleRate();

    final lapModels = widget.laps.asMap().entries.map((entry) {
      final index = entry.key;
      final duration = entry.value;

      Duration lapStart = Duration.zero;
      for (int i = 0; i < index; i++) {
        lapStart += widget.laps[i];
      }
      final lapEnd = lapStart + duration;

      final lapSpeedData = <double>[];
      for (int j = 0; j < widget.timeHistory.length; j++) {
        if (widget.timeHistory[j] >= lapStart && widget.timeHistory[j] <= lapEnd) {
          if (j < widget.speedHistory.length) {
            lapSpeedData.add(widget.speedHistory[j]);
          }
        }
      }

      final avgSpeedKmh = lapSpeedData.isNotEmpty
          ? lapSpeedData.reduce((a, b) => a + b) / lapSpeedData.length
          : 0.0;
      final maxSpeedKmh =
          lapSpeedData.isNotEmpty ? lapSpeedData.reduce(math.max) : 0.0;

      return LapModel(
        lapIndex: index,
        duration: duration,
        avgSpeedKmh: avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh,
      );
    }).toList();

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  const SizedBox(height: 8),

                  // === SUCCESS BANNER ===
                  _SuccessBanner(
                    bestLap: widget.bestLap,
                    lapCount: widget.laps.length,
                    usedBleDevice: widget.usedBleDevice,
                    vehicleCategory: widget.vehicleCategory,
                    weather: _detectedWeather,
                    isLoadingWeather: _isLoadingWeather,
                  ),
                  const SizedBox(height: 16),

                  // === STATS GRID ===
                  _StatsGrid(
                    totalDuration: widget.totalDuration,
                    distance: distance,
                    lapCount: widget.laps.length,
                  ),
                  const SizedBox(height: 16),

                  // === TELEMETRIA INTERATTIVA ===
                  if (widget.gpsTrack.isNotEmpty && widget.laps.isNotEmpty)
                    _TelemetryPanel(
                      gpsTrack: widget.gpsTrack,
                      smoothPath: widget.smoothPath,
                      speedHistory: widget.speedHistory,
                      gForceHistory: widget.gForceHistory,
                      gpsAccuracyHistory: widget.gpsAccuracyHistory,
                      timeHistory: widget.timeHistory,
                      rollAngleHistory: widget.rollAngleHistory,
                      laps: widget.laps,
                    ),
                  if (widget.gpsTrack.isNotEmpty && widget.laps.isNotEmpty)
                    const SizedBox(height: 16),

                  // === TEMPI GIRI ===
                  if (widget.laps.isNotEmpty)
                    _LapTimesCard(laps: lapModels, bestLap: widget.bestLap),
                  if (widget.laps.isNotEmpty) const SizedBox(height: 16),

                  // === MAPPA ===
                  if (widget.smoothPath.isNotEmpty)
                    _MapCard(
                      fullPath: widget.smoothPath,
                      timeHistory: widget.timeHistory,
                      laps: widget.laps,
                      trackDefinition: widget.trackDefinition,
                    ),
                  if (widget.smoothPath.isNotEmpty) const SizedBox(height: 16),

                  // === DATI SESSIONE ===
                  _SessionDataCard(
                    maxSpeedKmh: maxSpeed,
                    avgSpeedKmh: avgSpeed,
                    maxGForce: maxGForce,
                    distanceKm: distance,
                  ),
                  const SizedBox(height: 16),

                  // === DATI GPS ===
                  _GpsDataCard(
                    gpsDataCount: widget.gpsTrack.length,
                    avgGpsAccuracy: avgGpsAccuracy,
                    gpsSampleRateHz: gpsSampleRate,
                    usedBleDevice: widget.usedBleDevice,
                  ),
                  const SizedBox(height: 16),

                  // === TRACK INFO ===
                  if (widget.trackDefinition != null)
                    _TrackInfoCard(trackDefinition: widget.trackDefinition!),
                  if (widget.trackDefinition != null) const SizedBox(height: 16),

                  // === SAVE BUTTON ===
                  _SaveButton(
                    isSaving: _isSaving,
                    onTap: () => _handleSaveSession(context),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    kBrandColor.withAlpha(30),
                    kBrandColor.withAlpha(15),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: const Icon(Icons.arrow_back, color: kBrandColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Riepilogo Sessione',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sessione completata con successo',
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Save button
          GestureDetector(
            onTap: _isSaving ? null : () => _handleSaveSession(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: _isSaving
                      ? [kMutedColor.withAlpha(30), kMutedColor.withAlpha(15)]
                      : [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)],
                ),
                border: Border.all(
                  color: _isSaving ? kMutedColor.withAlpha(60) : kBrandColor.withAlpha(100),
                  width: 1.5,
                ),
                boxShadow: _isSaving
                    ? null
                    : [
                        BoxShadow(
                          color: kBrandColor.withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(kMutedColor),
                      ),
                    )
                  : const Icon(Icons.save_alt, color: kBrandColor, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   SUCCESS BANNER - Hero card with best lap
============================================================ */

class _SuccessBanner extends StatelessWidget {
  final Duration? bestLap;
  final int lapCount;
  final bool usedBleDevice;
  final String? vehicleCategory;
  final String? weather;
  final bool isLoadingWeather;

  const _SuccessBanner({
    required this.bestLap,
    required this.lapCount,
    required this.usedBleDevice,
    this.vehicleCategory,
    this.weather,
    this.isLoadingWeather = false,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bestLapText = bestLap != null ? _formatDuration(bestLap!) : '--:--';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top section with checkmark
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // gradient: LinearGradient(
              //   colors: [kBrandColor.withAlpha(20), Colors.transparent],
              //   begin: Alignment.topCenter,
              //   end: Alignment.bottomCenter,
              // ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)],
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(100), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandColor.withAlpha(50),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, color: kBrandColor, size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sessione Completata!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$lapCount giri registrati',
                  style: TextStyle(
                    fontSize: 14,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Best lap highlight
          if (bestLap != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [kPulseColor.withAlpha(30), kPulseColor.withAlpha(15)],
                ),
                border: Border.all(color: kPulseColor.withAlpha(80), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kPulseColor.withAlpha(30),
                      border: Border.all(color: kPulseColor.withAlpha(60)),
                    ),
                    child: const Icon(Icons.timer, color: kPulseColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MIGLIOR GIRO',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: kPulseColor.withAlpha(200),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bestLapText,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: kPulseColor,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // GPS quality badge
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _kTileColor,
              border: Border.all(color: _kBorderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  usedBleDevice ? Icons.bluetooth_connected : Icons.gps_fixed,
                  color: usedBleDevice ? kBrandColor : kMutedColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  usedBleDevice ? 'Registrata con GPS BLE PRO (15 Hz)' : 'Registrata con GPS Telefono (1 Hz)',
                  style: TextStyle(
                    fontSize: 12,
                    color: usedBleDevice ? kBrandColor : kMutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Vehicle category and weather info
          if (vehicleCategory != null || weather != null || isLoadingWeather)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _kTileColor,
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (vehicleCategory != null) ...[
                    const Icon(
                      Icons.directions_car,
                      color: kBrandColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      vehicleCategory!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: kBrandColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (vehicleCategory != null && (weather != null || isLoadingWeather))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        width: 1,
                        height: 16,
                        color: _kBorderColor,
                      ),
                    ),
                  if (isLoadingWeather) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA726)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Rilevamento meteo...',
                      style: TextStyle(
                        fontSize: 12,
                        color: kMutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else if (weather != null) ...[
                    const Icon(
                      Icons.wb_sunny,
                      color: Color(0xFFFFA726),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      weather!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: kFgColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/* ============================================================
   STATS GRID
============================================================ */

class _StatsGrid extends StatelessWidget {
  final Duration totalDuration;
  final double distance;
  final int lapCount;

  const _StatsGrid({
    required this.totalDuration,
    required this.distance,
    required this.lapCount,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: Icons.access_time,
            value: _formatDuration(totalDuration),
            label: 'Tempo Totale',
            color: kBrandColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.route,
            value: '${distance.toStringAsFixed(1)} km',
            label: 'Distanza',
            color: const Color(0xFF00E676),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.loop,
            value: '$lapCount',
            label: 'Giri',
            color: const Color(0xFF29B6F6),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
        ),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: kFgColor, fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   TELEMETRY PANEL
============================================================ */

enum _MetricFocus { speed, gForce, rollAngle }

class _TelemetryPanel extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<LatLng> smoothPath;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;
  final List<double> rollAngleHistory;
  final List<Duration> laps;

  const _TelemetryPanel({
    required this.gpsTrack,
    required this.smoothPath,
    required this.speedHistory,
    required this.gForceHistory,
    required this.gpsAccuracyHistory,
    required this.timeHistory,
    required this.rollAngleHistory,
    required this.laps,
  });

  @override
  State<_TelemetryPanel> createState() => _TelemetryPanelState();
}

class _TelemetryPanelState extends State<_TelemetryPanel> {
  _MetricFocus _focus = _MetricFocus.speed;
  int _selectedIndex = 0;
  int _currentLap = 0;

  String _formatLap(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.timeHistory.length < 2) {
      return _buildEmptyState('Nessun dato registrato');
    }

    final laps = List<Duration>.from(widget.laps);
    if (laps.isEmpty) {
      laps.add(widget.timeHistory.last);
    }

    final int lapCount = laps.length;
    _currentLap = _currentLap.clamp(0, lapCount - 1);

    Duration lapStartTime = Duration.zero;
    for (int i = 0; i < _currentLap; i++) {
      lapStartTime += laps[i];
    }
    final Duration lapEndTime = lapStartTime + laps[_currentLap];

    final List<int> indices = [];
    for (int i = 0; i < widget.timeHistory.length; i++) {
      final t = widget.timeHistory[i];
      if (t >= lapStartTime && t <= lapEndTime) {
        indices.add(i);
      }
    }

    if (indices.length < 2) {
      return _buildEmptyState('Dati insufficienti per il giro ${_currentLap + 1}');
    }

    final int len = indices.length;
    _selectedIndex = _selectedIndex.clamp(0, len - 1);

    final baseMs = widget.timeHistory[indices.first].inMilliseconds.toDouble();
    final List<double> xs = List.generate(len, (j) {
      final idx = indices[j];
      return (widget.timeHistory[idx].inMilliseconds.toDouble() - baseMs) / 1000.0;
    });

    final List<FlSpot> speedSpots = List.generate(len, (j) {
      final idx = indices[j];
      return FlSpot(xs[j], widget.speedHistory[idx]);
    });
    final List<FlSpot> gSpots = List.generate(len, (j) {
      final idx = indices[j];
      return FlSpot(xs[j], widget.gForceHistory[idx]);
    });

    final List<FlSpot> rollSpots = List.generate(len, (j) {
      final idx = indices[j];
      return FlSpot(xs[j], widget.rollAngleHistory[idx]);
    });

    // Trova il punto di velocità massima nel giro corrente
    double maxSpeed = speedSpots.first.y;
    int maxSpeedIndex = 0;
    for (int j = 0; j < speedSpots.length; j++) {
      if (speedSpots[j].y > maxSpeed) {
        maxSpeed = speedSpots[j].y;
        maxSpeedIndex = j;
      }
    }
    final maxSpeedSpot = speedSpots[maxSpeedIndex];
    final maxSpeedGlobalIdx = indices[maxSpeedIndex];

    double minY = speedSpots.first.y;
    double maxY = speedSpots.first.y;
    for (final s in [...speedSpots, ...gSpots, ...rollSpots]) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final range = (maxY - minY).abs();
    final chartMinY = range > 0 ? minY - range * 0.1 : minY - 1;
    final chartMaxY = range > 0 ? maxY + range * 0.1 : maxY + 1;

    final cursorX = xs[_selectedIndex];
    final int globalIdx = indices[_selectedIndex];

    final List<LatLng> lapPath = indices
        .where((i) => i < widget.smoothPath.length)
        .map((i) => widget.smoothPath[i])
        .toList();
    final List<double> lapAccel = indices
        .where((i) => i < widget.gForceHistory.length)
        .map((i) => widget.gForceHistory[i])
        .toList();

    LatLng? marker;
    if (globalIdx < widget.gpsTrack.length) {
      final p = widget.gpsTrack[globalIdx];
      marker = LatLng(p.latitude, p.longitude);
    }

    final double curSpeed = widget.speedHistory[globalIdx];
    final double curG = widget.gForceHistory[globalIdx];
    final double curRoll = widget.rollAngleHistory[globalIdx];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          // Header con navigazione giri
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBrandColor.withAlpha(50)),
                  ),
                  child: const Icon(Icons.show_chart, size: 18, color: kBrandColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TELEMETRIA',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: kBrandColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Giro ${_currentLap + 1} di $lapCount • ${_formatLap(laps[_currentLap])}',
                        style: TextStyle(fontSize: 11, color: kMutedColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                _buildNavButton(Icons.chevron_left, _currentLap > 0, () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentLap--;
                    _selectedIndex = 0;
                  });
                }),
                const SizedBox(width: 8),
                _buildNavButton(Icons.chevron_right, _currentLap < lapCount - 1, () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentLap++;
                    _selectedIndex = 0;
                  });
                }),
              ],
            ),
          ),

          // Circuit track view
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CircuitView(path: lapPath, marker: marker, accelG: lapAccel),
          ),
          const SizedBox(height: 16),

          // Chart
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: xs.first,
                  maxX: xs.last,
                  minY: chartMinY,
                  maxY: chartMaxY,
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: range > 0 ? range / 4 : 1,
                    verticalInterval: (xs.last - xs.first) > 0 ? (xs.last - xs.first) / 4 : 1,
                    getDrawingHorizontalLine: (value) => FlLine(color: _kBorderColor.withAlpha(60), strokeWidth: 0.5),
                    getDrawingVerticalLine: (value) => FlLine(color: _kBorderColor.withAlpha(40), strokeWidth: 0.5),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      VerticalLine(x: cursorX, color: kBrandColor.withAlpha(180), strokeWidth: 1.5, dashArray: [6, 3]),
                    ],
                    horizontalLines: [
                      // Linea orizzontale tratteggiata per la velocità massima
                      HorizontalLine(
                        y: maxSpeed,
                        color: const Color(0xFF9C27B0).withAlpha(100),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ],
                  ),
                  showingTooltipIndicators: [
                    ShowingTooltipIndicators([
                      LineBarSpot(
                        _buildLine(speedSpots, const Color(0xFFFF4D4F), _focus == _MetricFocus.speed),
                        maxSpeedIndex,
                        maxSpeedSpot,
                      ),
                    ]),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: false,
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions || response?.lineBarSpots == null || response!.lineBarSpots!.isEmpty) return;
                      setState(() {
                        _selectedIndex = response.lineBarSpots!.first.spotIndex.clamp(0, len - 1);
                      });
                    },
                    getTouchedSpotIndicator: (barData, spotIndexes) {
                      return spotIndexes.map((i) => TouchedSpotIndicatorData(
                        const FlLine(color: Colors.transparent),
                        FlDotData(show: false),
                      )).toList();
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => const Color(0xFF9C27B0).withAlpha(220),
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          if (spot.spotIndex == maxSpeedIndex) {
                            return LineTooltipItem(
                              'MAX: ${maxSpeed.toStringAsFixed(1)} km/h\nGiro ${_currentLap + 1}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            );
                          }
                          return null;
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    _buildLine(speedSpots, const Color(0xFFFF4D4F), _focus == _MetricFocus.speed, maxSpeedIndex: maxSpeedIndex),
                    _buildLine(gSpots, const Color(0xFF4CD964), _focus == _MetricFocus.gForce),
                    _buildLine(rollSpots, const Color(0xFF00B8D4), _focus == _MetricFocus.rollAngle), // Colore ciano per roll angle
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Metric chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _metricChip('Speed', const Color(0xFFFF4D4F), _focus == _MetricFocus.speed, () {
                  HapticFeedback.selectionClick();
                  setState(() => _focus = _MetricFocus.speed);
                }),
                _metricChip('G-Force', const Color(0xFF4CD964), _focus == _MetricFocus.gForce, () {
                  HapticFeedback.selectionClick();
                  setState(() => _focus = _MetricFocus.gForce);
                }),
                _metricChip('Roll', const Color(0xFF00B8D4), _focus == _MetricFocus.rollAngle, () {
                  HapticFeedback.selectionClick();
                  setState(() => _focus = _MetricFocus.rollAngle);
                }),
              ],
            ),
          ),

          // Current values footer
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(4),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: const Border(top: BorderSide(color: _kBorderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _valueDisplay('v', '${curSpeed.toStringAsFixed(1)} km/h', const Color(0xFFFF4D4F)),
                Container(width: 1, height: 24, color: _kBorderColor),
                _valueDisplay('g', '${curG.toStringAsFixed(2)} g', const Color(0xFF4CD964)),
                Container(width: 1, height: 24, color: _kBorderColor),
                _valueDisplay('r', '${curRoll.toStringAsFixed(1)}°', const Color(0xFF00B8D4)),
                Container(width: 1, height: 24, color: _kBorderColor),
                _valueDisplay('t', '${xs[_selectedIndex].toStringAsFixed(1)}s', kBrandColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_kCardStart, _kCardEnd]),
        border: Border.all(color: _kBorderColor),
      ),
      child: Center(child: Text(message, style: const TextStyle(color: kMutedColor))),
    );
  }

  Widget _buildNavButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled ? kBrandColor.withAlpha(20) : kMutedColor.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: enabled ? kBrandColor.withAlpha(50) : kMutedColor.withAlpha(30)),
        ),
        child: Icon(icon, size: 18, color: enabled ? kBrandColor : kMutedColor.withAlpha(100)),
      ),
    );
  }

  LineChartBarData _buildLine(List<FlSpot> spots, Color baseColor, bool focused, {int? maxSpeedIndex}) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: focused ? baseColor : baseColor.withAlpha(50),
      barWidth: focused ? 2.5 : 1.5,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, barData) {
          // Mostra solo il punto viola per la velocità massima
          if (maxSpeedIndex != null) {
            return spots.indexOf(spot) == maxSpeedIndex;
          }
          return false;
        },
        getDotPainter: (spot, percent, barData, index) {
          if (maxSpeedIndex != null && spots.indexOf(spot) == maxSpeedIndex) {
            return FlDotCirclePainter(
              radius: 6,
              color: const Color(0xFF9C27B0),
              strokeWidth: 3,
              strokeColor: const Color(0xFF9C27B0).withAlpha(100),
            );
          }
          return FlDotCirclePainter(radius: 0, color: Colors.transparent);
        },
      ),
      belowBarData: BarAreaData(show: focused, color: baseColor.withAlpha(20)),
    );
  }

  Widget _metricChip(String label, Color color, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: [color.withAlpha(40), color.withAlpha(25)]) : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : color.withAlpha(60), width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? color : color.withAlpha(150))),
          ],
        ),
      ),
    );
  }

  Widget _valueDisplay(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, color: kFgColor, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _CircuitView extends StatelessWidget {
  final List<LatLng> path;
  final LatLng? marker;
  final List<double> accelG;

  const _CircuitView({required this.path, this.marker, this.accelG = const []});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: _kTileColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderColor),
        ),
        child: const Center(child: Text('Nessun dato GPS', style: TextStyle(color: kMutedColor))),
      );
    }

    return AspectRatio(
      aspectRatio: 2.0,
      child: CustomPaint(painter: _CircuitPainter(path: path, marker: marker, accelG: accelG)),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  final List<LatLng> path;
  final LatLng? marker;
  final List<double> accelG;

  _CircuitPainter({required this.path, this.marker, required this.accelG});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = _kTileColor;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), bgPaint);

    final gridPaint = Paint()..color = Colors.white.withAlpha(8)..strokeWidth = 0.5;
    const gridLines = 10;
    final dx = size.width / gridLines;
    final dy = size.height / gridLines;
    for (int i = 1; i < gridLines; i++) {
      canvas.drawLine(Offset(dx * i, 0), Offset(dx * i, size.height), gridPaint);
      canvas.drawLine(Offset(0, dy * i), Offset(size.width, dy * i), gridPaint);
    }

    double minLat = path.first.latitude, maxLat = path.first.latitude;
    double minLon = path.first.longitude, maxLon = path.first.longitude;
    for (final p in path) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final dLat = (maxLat - minLat).abs();
    final dLon = (maxLon - minLon).abs();
    final scale = (dLat == 0 || dLon == 0) ? 1.0 : math.min(size.width * 0.85 / dLon, size.height * 0.85 / dLat);

    Offset project(LatLng p) => Offset(
      (p.longitude - centerLon) * scale + size.width / 2,
      (centerLat - p.latitude) * scale + size.height / 2,
    );

    final List<Offset> projected = path.map(project).toList();

    for (int i = 1; i < projected.length; i++) {
      final g = i < accelG.length ? accelG[i] : 0.0;
      final paint = Paint()
        ..color = _colorForG(g)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(projected[i - 1], projected[i], paint);
    }

    if (marker != null) {
      final o = project(marker!);
      canvas.drawCircle(o, 12, Paint()..color = kPulseColor.withAlpha(60));
      canvas.drawCircle(o, 7, Paint()..color = Colors.white);
      canvas.drawCircle(o, 7, Paint()..color = kPulseColor..style = PaintingStyle.stroke..strokeWidth = 3);
    }
  }

  Color _colorForG(double g) {
    const pos = Color(0xFF4CD964);
    const neg = Color(0xFFFF4D4F);
    const neu = kBrandColor;
    final clamped = g.clamp(-1.5, 1.5);
    if (clamped >= 0) {
      return Color.lerp(neu, pos, (clamped / 1.5).clamp(0.0, 1.0))!;
    } else {
      return Color.lerp(neu, neg, 1.0 - (-clamped / 1.5).clamp(0.0, 1.0))!;
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.marker != marker || oldDelegate.accelG != accelG;
}

/* ============================================================
   LAP TIMES CARD
============================================================ */

class _LapTimesCard extends StatelessWidget {
  final List<LapModel> laps;
  final Duration? bestLap;

  const _LapTimesCard({required this.laps, required this.bestLap});

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sortedLaps = List<LapModel>.from(laps)..sort((a, b) => a.lapIndex.compareTo(b.lapIndex));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_kCardStart, _kCardEnd]),
        border: Border.all(color: _kBorderColor),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBrandColor.withAlpha(50)),
                  ),
                  child: const Icon(Icons.list_alt, size: 18, color: kBrandColor),
                ),
                const SizedBox(width: 12),
                const Text(
                  'TEMPI SUL GIRO',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kBrandColor, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
          ...sortedLaps.map((lap) {
            final isBest = bestLap != null && lap.duration == bestLap;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isBest ? LinearGradient(colors: [kPulseColor.withAlpha(30), Colors.transparent]) : null,
                border: Border(top: BorderSide(color: _kBorderColor.withAlpha(100))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isBest ? kPulseColor.withAlpha(30) : _kTileColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isBest ? kPulseColor : _kBorderColor),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${lap.lapIndex + 1}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isBest ? kPulseColor : kMutedColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDuration(lap.duration),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isBest ? kPulseColor : kFgColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Avg ${lap.avgSpeedKmh.toStringAsFixed(0)} km/h • Max ${lap.maxSpeedKmh.toStringAsFixed(0)} km/h',
                          style: TextStyle(fontSize: 11, color: kMutedColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  if (isBest)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [kPulseColor.withAlpha(40), kPulseColor.withAlpha(25)]),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kPulseColor, width: 1.5),
                      ),
                      child: const Text('BEST', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: kPulseColor)),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/* ============================================================
   MAP CARD
============================================================ */

class _MapCard extends StatefulWidget {
  final List<LatLng> fullPath;
  final List<Duration> timeHistory;
  final List<Duration> laps;
  final TrackDefinition? trackDefinition;

  const _MapCard({
    required this.fullPath,
    required this.timeHistory,
    required this.laps,
    this.trackDefinition,
  });

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  int _currentLap = 0;
  bool _showAllLaps = true;

  String _formatLap(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  List<LatLng> _getLapPath() {
    if (_showAllLaps || widget.laps.isEmpty) {
      return widget.fullPath;
    }

    Duration lapStartTime = Duration.zero;
    for (int i = 0; i < _currentLap; i++) {
      lapStartTime += widget.laps[i];
    }
    final Duration lapEndTime = lapStartTime + widget.laps[_currentLap];

    final List<LatLng> lapPath = [];
    for (int i = 0; i < widget.timeHistory.length && i < widget.fullPath.length; i++) {
      final t = widget.timeHistory[i];
      if (t >= lapStartTime && t <= lapEndTime) {
        lapPath.add(widget.fullPath[i]);
      }
    }
    return lapPath.isNotEmpty ? lapPath : widget.fullPath;
  }

  @override
  Widget build(BuildContext context) {
    final path = _getLapPath();
    if (path.isEmpty) return const SizedBox.shrink();

    double minLat = path.first.latitude, maxLat = path.first.latitude;
    double minLon = path.first.longitude, maxLon = path.first.longitude;
    for (final p in path) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final int lapCount = widget.laps.length;

    // Costruisci la linea del via se disponibile
    List<Polyline> finishLinePolylines = [];
    List<Marker> finishLineMarkers = [];
    if (widget.trackDefinition != null) {
      final td = widget.trackDefinition!;
      finishLinePolylines.add(
        Polyline(
          points: [td.finishLineStart, td.finishLineEnd],
          strokeWidth: 4,
          color: Colors.white,
          borderStrokeWidth: 2,
          borderColor: Colors.black,
        ),
      );
      final centerFinish = LatLng(
        (td.finishLineStart.latitude + td.finishLineEnd.latitude) / 2,
        (td.finishLineStart.longitude + td.finishLineEnd.longitude) / 2,
      );
      finishLineMarkers.add(
        Marker(
          point: centerFinish,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: kBrandColor, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 6)],
            ),
            child: const Icon(Icons.flag, size: 16, color: kBrandColor),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_kCardStart, _kCardEnd]),
        border: Border.all(color: _kBorderColor),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          // Header con navigazione giri
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBrandColor.withAlpha(50)),
                  ),
                  child: const Icon(Icons.satellite_alt, size: 18, color: kBrandColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MAPPA TRACCIATO',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kBrandColor, letterSpacing: 0.8),
                      ),
                      if (!_showAllLaps && lapCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Giro ${_currentLap + 1} di $lapCount • ${_formatLap(widget.laps[_currentLap])}',
                          style: TextStyle(fontSize: 11, color: kMutedColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                // Toggle tutti i giri / singolo giro
                if (lapCount > 0) ...[
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showAllLaps = !_showAllLaps);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showAllLaps ? kBrandColor.withAlpha(30) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _showAllLaps ? kBrandColor.withAlpha(80) : kMutedColor.withAlpha(50)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showAllLaps ? Icons.touch_app : Icons.filter_1,
                            size: 12,
                            color: _showAllLaps ? kBrandColor : kMutedColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showAllLaps ? 'TUTTI I GIRI' : 'GIRO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _showAllLaps ? kBrandColor : kMutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_showAllLaps) ...[
                    const SizedBox(width: 8),
                    _buildNavButton(Icons.chevron_left, _currentLap > 0, () {
                      HapticFeedback.selectionClick();
                      setState(() => _currentLap--);
                    }),
                    const SizedBox(width: 6),
                    _buildNavButton(Icons.chevron_right, _currentLap < lapCount - 1, () {
                      HapticFeedback.selectionClick();
                      setState(() => _currentLap++);
                    }),
                  ],
                ],
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            child: SizedBox(
              height: 280,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2),
                  initialZoom: 16.5,
                ),
                children: [
                  // Mappa satellitare ESRI
                  TileLayer(
                    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.racesense.pulse',
                  ),
                  // Linea del via
                  if (finishLinePolylines.isNotEmpty)
                    PolylineLayer(polylines: finishLinePolylines),
                  // Tracciato
                  PolylineLayer(polylines: [
                    Polyline(
                      points: path,
                      strokeWidth: 4,
                      color: kBrandColor,
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.black.withAlpha(180),
                    ),
                  ]),
                  // Marker linea del via
                  if (finishLineMarkers.isNotEmpty)
                    MarkerLayer(markers: finishLineMarkers),
                  // Marker start/end
                  MarkerLayer(markers: [
                    Marker(
                      point: path.first,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CD964),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 6)],
                        ),
                        child: const Icon(Icons.trip_origin, size: 10, color: Colors.white),
                      ),
                    ),
                    if (path.length > 1)
                      Marker(
                        point: path.last,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: kErrorColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 6)],
                          ),
                          child: const Icon(Icons.adjust, size: 14, color: Colors.white),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? kBrandColor.withAlpha(20) : kMutedColor.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? kBrandColor.withAlpha(50) : kMutedColor.withAlpha(30)),
        ),
        child: Icon(icon, size: 16, color: enabled ? kBrandColor : kMutedColor.withAlpha(100)),
      ),
    );
  }
}

/* ============================================================
   SESSION DATA CARD
============================================================ */

class _SessionDataCard extends StatelessWidget {
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final double maxGForce;
  final double distanceKm;

  const _SessionDataCard({
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.maxGForce,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_kCardStart, _kCardEnd]),
        border: Border.all(color: _kBorderColor),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPulseColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPulseColor.withAlpha(50)),
                  ),
                  child: const Icon(Icons.speed, size: 18, color: kPulseColor),
                ),
                const SizedBox(width: 12),
                const Text(
                  'DATI SESSIONE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kPulseColor, letterSpacing: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _techMetric(Icons.speed, 'Max Speed', '${maxSpeedKmh.toStringAsFixed(0)} km/h', kPulseColor)),
                const SizedBox(width: 10),
                Expanded(child: _techMetric(Icons.trending_up, 'Avg Speed', '${avgSpeedKmh.toStringAsFixed(0)} km/h', kBrandColor)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _techMetric(Icons.center_focus_strong, 'Max G', '${maxGForce.toStringAsFixed(2)} g', kCoachColor)),
                const SizedBox(width: 10),
                Expanded(child: _techMetric(Icons.straighten, 'Distanza', '${distanceKm.toStringAsFixed(2)} km', const Color(0xFFFF9500))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _techMetric(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 10, color: kMutedColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: kFgColor)),
        ],
      ),
    );
  }
}

/* ============================================================
   GPS DATA CARD
============================================================ */

class _GpsDataCard extends StatelessWidget {
  final int gpsDataCount;
  final double avgGpsAccuracy;
  final int gpsSampleRateHz;
  final bool usedBleDevice;

  const _GpsDataCard({
    required this.gpsDataCount,
    required this.avgGpsAccuracy,
    required this.gpsSampleRateHz,
    required this.usedBleDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_kCardStart, _kCardEnd]),
        border: Border.all(color: _kBorderColor),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CD964).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4CD964).withAlpha(50)),
                  ),
                  child: const Icon(Icons.gps_fixed, size: 18, color: Color(0xFF4CD964)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'DATI GPS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF4CD964), letterSpacing: 0.8),
                ),
                const Spacer(),
                if (usedBleDevice)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: kBrandColor.withAlpha(20),
                      border: Border.all(color: kBrandColor.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_connected, size: 12, color: kBrandColor),
                        const SizedBox(width: 4),
                        Text('BLE PRO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kBrandColor)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _techMetric(Icons.location_on, 'Punti GPS', '$gpsDataCount', const Color(0xFF4CD964))),
                const SizedBox(width: 10),
                Expanded(child: _techMetric(Icons.gps_not_fixed, 'Precisione', '${avgGpsAccuracy.toStringAsFixed(1)} m', const Color(0xFF5AC8FA))),
                const SizedBox(width: 10),
                Expanded(child: _techMetric(Icons.refresh, 'Sample Rate', '$gpsSampleRateHz Hz', const Color(0xFFFF9500))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _techMetric(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 9, color: kMutedColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: kFgColor)),
        ],
      ),
    );
  }
}

/* ============================================================
   TRACK INFO CARD
============================================================ */

class _TrackInfoCard extends StatelessWidget {
  final TrackDefinition trackDefinition;

  const _TrackInfoCard({required this.trackDefinition});

  @override
  Widget build(BuildContext context) {
    final hasTrackPath = trackDefinition.trackPath != null && trackDefinition.trackPath!.isNotEmpty;
    final estimatedLength = trackDefinition.estimatedLengthMeters;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_kCardStart, _kCardEnd]),
        border: Border.all(color: _kBorderColor),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kMutedColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kMutedColor.withAlpha(40)),
                  ),
                  child: Icon(Icons.route, size: 18, color: kMutedColor.withAlpha(200)),
                ),
                const SizedBox(width: 12),
                Text(
                  'INFO TRACCIATO',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kMutedColor.withAlpha(200), letterSpacing: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _infoTile(Icons.flag_outlined, 'Circuito', trackDefinition.name, const Color(0xFF5AC8FA))),
                const SizedBox(width: 10),
                Expanded(child: _infoTile(Icons.place_outlined, 'Località', trackDefinition.location, const Color(0xFF4CD964))),
              ],
            ),
            if (estimatedLength != null || hasTrackPath) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (estimatedLength != null)
                    Expanded(child: _infoTile(Icons.straighten, 'Lunghezza', '${(estimatedLength / 1000).toStringAsFixed(2)} km', const Color(0xFFFF9500))),
                  if (estimatedLength != null && hasTrackPath) const SizedBox(width: 10),
                  if (hasTrackPath)
                    Expanded(child: _infoTile(Icons.share_location, 'Punti', '${trackDefinition.trackPath!.length}', kPulseColor)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color.withAlpha(180)),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(fontSize: 9, color: kMutedColor, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kFgColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   SAVE BUTTON
============================================================ */

class _SaveButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onTap;

  const _SaveButton({required this.isSaving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSaving ? null : () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isSaving
                ? [kMutedColor.withAlpha(50), kMutedColor.withAlpha(30)]
                : [kBrandColor, kBrandColor.withAlpha(200)],
          ),
          border: Border.all(
            color: isSaving ? kMutedColor.withAlpha(100) : kBrandColor,
            width: 2,
          ),
          boxShadow: isSaving
              ? null
              : [
                  BoxShadow(
                    color: kBrandColor.withAlpha(100),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSaving)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(kMutedColor),
                ),
              )
            else
              const Icon(Icons.cloud_upload, color: Colors.black, size: 22),
            const SizedBox(width: 10),
            Text(
              isSaving ? 'SALVATAGGIO...' : 'SALVA SESSIONE',
              style: TextStyle(
                color: isSaving ? kMutedColor : Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   SAVE PROGRESS DIALOG
============================================================ */

class _SaveProgressDialog extends StatelessWidget {
  final ValueNotifier<double> progress;

  const _SaveProgressDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kCardStart, _kCardEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(150),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)],
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(80), width: 2),
                  ),
                  child: const Icon(Icons.cloud_upload, color: kBrandColor, size: 28),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Caricamento sessione',
                  style: TextStyle(
                    fontSize: 18,
                    color: kFgColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Salvataggio dei dati telemetrici...',
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: _kTileColor,
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${(value * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
