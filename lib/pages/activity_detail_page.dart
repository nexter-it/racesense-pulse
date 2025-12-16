import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';

import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import '../models/session_model.dart';
import '../models/track_definition.dart';
import '../services/session_service.dart';
import '../services/engagement_service.dart';
import 'search_user_profile_page.dart';
import 'dart:ui' as ui;

class ActivityDetailPage extends StatefulWidget {
  static const routeName = '/activity';

  const ActivityDetailPage({super.key});

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  final SessionService _sessionService = SessionService();
  final EngagementService _engagementService = EngagementService();

  bool _isLoading = true;
  String? _error;

  // Real data from Firestore
  List<GpsPoint> _gpsData = [];
  List<LapModel> _laps = [];
  late SessionModel _session;
  bool _liked = false;
  bool _challenged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) {
      _loadSessionData();
    }
  }

  /// Ottiene la definizione del circuito se disponibile
  TrackDefinition? _getTrackDefinition() {
    // 1. Check if session already has trackDefinition (from Firebase)
    if (_session.trackDefinition != null) {
      return _session.trackDefinition;
    }

    // 2. Try to find predefined track by name
    final predefined = PredefinedTracks.findById(_session.trackName.toLowerCase());
    if (predefined != null) {
      return predefined;
    }

    // 3. If session has displayPath, create a custom TrackDefinition
    // This is a fallback for old sessions that don't have trackDefinition stored
    if (_session.displayPath != null && _session.displayPath!.isNotEmpty) {
      final path = _session.displayPath!
          .map((p) => ll.LatLng(p['lat']!, p['lon']!))
          .toList();

      return TrackDefinition(
        id: 'custom_${_session.sessionId}',
        name: _session.trackName,
        location: _session.location,
        finishLineStart: path.first,
        finishLineEnd: path.length > 1 ? path[1] : path.first,
        trackPath: path,
        widthMeters: 10.0, // Default width
      );
    }

    return null;
  }

  Future<void> _loadSessionData() async {
    try {
      final args = ModalRoute.of(context)!.settings.arguments;

      if (args is! SessionModel) {
        setState(() {
          _error = 'Dati sessione non validi';
          _isLoading = false;
        });
        return;
      }

      _session = args;

      print('📥 Caricamento dettagli sessione: ${_session.sessionId}');

      // Load GPS data and laps in parallel
      final results = await Future.wait([
        _sessionService.getSessionGpsData(_session.sessionId),
        _sessionService.getSessionLaps(_session.sessionId),
      ]);

      _gpsData = results[0] as List<GpsPoint>;
      _laps = results[1] as List<LapModel>;
      final reactions =
          await _engagementService.getUserReactions(_session.sessionId);

      print('✅ Caricati ${_gpsData.length} punti GPS e ${_laps.length} giri');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _liked = reactions['like'] ?? false;
          _challenged = reactions['challenge'] ?? false;
        });
      }
    } catch (e) {
      print('❌ Errore caricamento sessione: $e');
      if (mounted) {
        setState(() {
          _error = 'Errore nel caricamento dei dati';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: PulseBackground(
          withTopPadding: true,
          child: const Center(
            child: CircularProgressIndicator(color: kBrandColor),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: PulseBackground(
          withTopPadding: true,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        kErrorColor.withAlpha(40),
                        kErrorColor.withAlpha(20),
                      ],
                    ),
                    border: Border.all(color: kErrorColor, width: 2),
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 64, color: kErrorColor),
                ),
                const SizedBox(height: 24),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: kFgColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(40),
                        kBrandColor.withAlpha(25),
                      ],
                    ),
                    border: Border.all(color: kBrandColor, width: 1.5),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        child: Text(
                          'Torna indietro',
                          style: TextStyle(
                            color: kBrandColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Extract data from GPS points
    final List<double> speedHistory = _gpsData.map((p) => p.speedKmh).toList();
    final List<double> accuracyHistory =
        _gpsData.map((p) => p.accuracy).toList();
    final List<Duration> timeHistory = _gpsData
        .map((p) => Duration(
            milliseconds: p.timestamp.millisecondsSinceEpoch -
                _gpsData.first.timestamp.millisecondsSinceEpoch))
        .toList();

    // G-Force longitudinale (fusione IMU+GPS salvata in Firestore)
    final List<double> gForceHistory =
        _gpsData.map((p) => p.longitudinalG ?? 0.0).toList();

    // Convert GPS to LatLng for visualization
    final List<ll.LatLng> smoothPath =
        _gpsData.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();

    // Convert to Position for compatibility
    final List<Position> gpsTrack = _gpsData
        .map((p) => Position(
              latitude: p.latitude,
              longitude: p.longitude,
              timestamp: p.timestamp,
              accuracy: p.accuracy,
              altitude: 0,
              heading: 0,
              speed: p.speedKmh / 3.6, // Convert km/h to m/s
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            ))
        .toList();

    return Scaffold(
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildHeader(context),
            const SizedBox(height: 8),
            _PilotHeader(session: _session),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero Stats Cards
                    _HeroStatsGrid(session: _session),
                    const SizedBox(height: 24),

                    // Session Info Card
                    _SessionInfoCard(session: _session),
                    const SizedBox(height: 24),

                    // Telemetria interattiva con circuito
                    if (gpsTrack.isNotEmpty && _laps.isNotEmpty)
                      _SessionOverviewPanel(
                        gpsTrack: gpsTrack,
                        smoothPath: smoothPath,
                        speedHistory: speedHistory,
                        gForceHistory: gForceHistory,
                        gpsAccuracyHistory: accuracyHistory,
                        timeHistory: timeHistory,
                        laps: _laps.map((l) => l.duration).toList(),
                      ),
                    const SizedBox(height: 24),

                    // Lap Times List
                    if (_laps.isNotEmpty)
                      _LapTimesList(
                        laps: _laps,
                        bestLap: _session.bestLap,
                      ),
                    const SizedBox(height: 24),

                    // Mappa OpenStreetMap
                    if (smoothPath.isNotEmpty)
                      _MapSection(
                        path: smoothPath,
                        trackName: _session.trackName,
                        trackDefinition: _getTrackDefinition(),
                      ),
                    const SizedBox(height: 24),

                    // Technical Data
                    _TechnicalDataSection(
                      session: _session,
                      gpsDataCount: _gpsData.length,
                      avgGForce: _gpsData.isNotEmpty
                          ? _gpsData
                                  .map((p) => (p.longitudinalG ?? 0).abs())
                                  .reduce((a, b) => a + b) /
                              _gpsData.length
                          : 0.0,
                    ),
                    const SizedBox(height: 16),
                    _GpsDeviceSection(
                      avgAccuracy: _session.avgGpsAccuracy,
                      sampleRateHz: _session.gpsSampleRateHz,
                      points: _gpsData.length,
                      deviceName: _session.usedBleDevice ? 'BLE GPS 15Hz' : 'Cellular GPS',
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons
                    _ActionsRow(
                      session: _session,
                      liked: _liked,
                      challenged: _challenged,
                      onToggleLike: () async {
                        await _engagementService.toggleLike(_session.sessionId);
                        setState(() {
                          _liked = !_liked;
                          final delta = _liked ? 1 : -1;
                          _session = _session.copyWith(
                            likesCount: _session.likesCount + delta,
                          );
                        });
                      },
                      onToggleChallenge: () async {
                        await _engagementService
                            .toggleChallenge(_session.sessionId);
                        setState(() {
                          _challenged = !_challenged;
                          final delta = _challenged ? 1 : -1;
                          _session = _session.copyWith(
                            challengeCount: _session.challengeCount + delta,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(40),
                  kBrandColor.withAlpha(25),
                ],
              ),
              border: Border.all(color: kBrandColor, width: 1.5),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.arrow_back, color: kBrandColor, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _session.trackName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _session.location,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),
          const PulseChip(
            label: Text('Cellular GPS'),
            icon: Icons.sensors,
          ),
        ],
      ),
    );
  }
}

class _PilotHeader extends StatelessWidget {
  final SessionModel session;

  const _PilotHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final userInitials = session.driverFullName.isNotEmpty
        ? session.driverFullName
            .split(' ')
            .map((e) => e[0])
            .take(2)
            .join()
            .toUpperCase()
        : '??';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchUserProfilePage(
              userId: session.userId,
              fullName: session.driverFullName,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A20).withAlpha(255),
              const Color(0xFF0F0F15).withAlpha(255),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kLineColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(100),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(60),
                    kPulseColor.withAlpha(40),
                  ],
                ),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF1A1A20),
                child: Text(
                  userInitials,
                  style: const TextStyle(
                    color: kBrandColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.driverFullName,
                    style: const TextStyle(
                      color: kFgColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${session.driverUsername}',
                    style: const TextStyle(
                      color: kMutedColor,
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
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: kBrandColor,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------
   HERO STATS GRID - Premium stats showcase
------------------------------------------------------------- */

class _HeroStatsGrid extends StatelessWidget {
  final SessionModel session;

  const _HeroStatsGrid({required this.session});

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bestLapStr =
        session.bestLap != null ? _formatDuration(session.bestLap!) : '--:--';
    final totalTimeStr = _formatDuration(session.totalDuration);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PremiumStatCard(
                label: "BEST LAP",
                value: bestLapStr,
                icon: Icons.timer,
                gradient: LinearGradient(
                  colors: [
                    kPulseColor.withAlpha(80),
                    kPulseColor.withAlpha(40),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderColor: kPulseColor,
                iconColor: kPulseColor,
                valueColor: kPulseColor,
                highlight: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PremiumStatCard(
                label: "TEMPO TOTALE",
                value: totalTimeStr,
                icon: Icons.access_time,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderColor: kLineColor,
                iconColor: kBrandColor,
                valueColor: kFgColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PremiumStatCard(
                label: "DISTANZA",
                value: "${session.distanceKm.toStringAsFixed(1)} km",
                icon: Icons.route,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderColor: kLineColor,
                iconColor: kCoachColor,
                valueColor: kFgColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PremiumStatCard(
                label: "GIRI",
                value: session.lapCount.toString(),
                icon: Icons.refresh,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderColor: kLineColor,
                iconColor: kBrandColor,
                valueColor: kFgColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PremiumStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Gradient gradient;
  final Color borderColor;
  final Color iconColor;
  final Color valueColor;
  final bool highlight;

  const _PremiumStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.borderColor,
    required this.iconColor,
    required this.valueColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: gradient,
        border: Border.all(
          color: borderColor,
          width: highlight ? 1.8 : 1,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: borderColor.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 10,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: iconColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: iconColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: valueColor,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------
   SESSION INFO CARD
------------------------------------------------------------- */

class _SessionInfoCard extends StatelessWidget {
  final SessionModel session;

  const _SessionInfoCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${session.dateTime.day}/${session.dateTime.month}/${session.dateTime.year}';
    final timeStr =
        '${session.dateTime.hour.toString().padLeft(2, '0')}:${session.dateTime.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kBrandColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBrandColor.withAlpha(60)),
                ),
                child:
                    const Icon(Icons.info_outline, size: 16, color: kBrandColor),
              ),
              const SizedBox(width: 10),
              const Text(
                'INFORMAZIONI SESSIONE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Circuito',
            value: session.trackName,
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.place_outlined,
            label: 'Località',
            value: session.location,
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Data',
            value: dateStr,
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: 'Ora',
            value: timeStr,
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.public_outlined,
            label: 'Visibilità',
            value: session.isPublic ? 'Pubblica' : 'Privata',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: kBrandColor.withAlpha(150)),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: kMutedColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: kFgColor,
          ),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------
   LAP TIMES LIST
------------------------------------------------------------- */

class _LapTimesList extends StatelessWidget {
  final List<LapModel> laps;
  final Duration? bestLap;

  const _LapTimesList({
    required this.laps,
    required this.bestLap,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sortedLaps = List<LapModel>.from(laps)
      ..sort((a, b) => a.lapIndex.compareTo(b.lapIndex));

    final worstLap = laps.isNotEmpty
        ? laps.reduce((a, b) => a.duration > b.duration ? a : b).duration
        : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBrandColor.withAlpha(60)),
                  ),
                  child: const Icon(Icons.list_alt, size: 16, color: kBrandColor),
                ),
                const SizedBox(width: 10),
                const Text(
                  'TEMPI SUL GIRO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedLaps.length,
            separatorBuilder: (_, __) => Divider(
              color: kLineColor.withAlpha(100),
              height: 1,
              indent: 20,
              endIndent: 20,
            ),
            itemBuilder: (context, index) {
              final lap = sortedLaps[index];
              final isBest = bestLap != null && lap.duration == bestLap;
              final isWorst = worstLap != null && lap.duration == worstLap;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: isBest
                      ? LinearGradient(
                          colors: [
                            kPulseColor.withOpacity(0.12),
                            Colors.transparent,
                          ],
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: isBest
                            ? LinearGradient(
                                colors: [
                                  kPulseColor.withAlpha(60),
                                  kPulseColor.withAlpha(40),
                                ],
                              )
                            : null,
                        color: isBest ? null : const Color(0xFF1A1A20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isBest ? kPulseColor : kLineColor,
                          width: isBest ? 1.5 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${lap.lapIndex + 1}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: isBest ? kPulseColor : kMutedColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDuration(lap.duration),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isBest ? kPulseColor : kFgColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Avg: ${lap.avgSpeedKmh.toStringAsFixed(1)} km/h  •  Max: ${lap.maxSpeedKmh.toStringAsFixed(1)} km/h',
                            style: const TextStyle(
                              fontSize: 11,
                              color: kMutedColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isBest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kPulseColor.withAlpha(40),
                              kPulseColor.withAlpha(25),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: kPulseColor, width: 1.5),
                        ),
                        child: const Text(
                          'BEST',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: kPulseColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    if (!isBest && isWorst)
                      Icon(
                        Icons.arrow_downward,
                        size: 18,
                        color: kMutedColor.withOpacity(0.4),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------
   MAP SECTION - OpenStreetMap
------------------------------------------------------------- */

class _MapSection extends StatelessWidget {
  final List<ll.LatLng> path;
  final String trackName;
  final TrackDefinition? trackDefinition;

  const _MapSection({
    required this.path,
    required this.trackName,
    this.trackDefinition,
  });

  /// Calcola i bordi del circuito (interno ed esterno) basandosi sulla linea centrale
  List<Widget> _buildCircuitLayers(TrackDefinition track) {
    if (track.trackPath == null || track.trackPath!.isEmpty) {
      return [];
    }

    final centerLine = track.trackPath!;
    final width = track.widthMeters ?? 10.0;
    final halfWidth = width / 2;

    final List<ll.LatLng> innerBorder = [];
    final List<ll.LatLng> outerBorder = [];

    for (int i = 0; i < centerLine.length; i++) {
      final current = centerLine[i];

      // Calculate tangent direction
      ll.LatLng tangent;
      if (i == 0) {
        tangent = _subtractLatLng(centerLine[i + 1], current);
      } else if (i == centerLine.length - 1) {
        tangent = _subtractLatLng(current, centerLine[i - 1]);
      } else {
        final prev = _subtractLatLng(current, centerLine[i - 1]);
        final next = _subtractLatLng(centerLine[i + 1], current);
        tangent = ll.LatLng(
          (prev.latitude + next.latitude) / 2,
          (prev.longitude + next.longitude) / 2,
        );
      }

      // Normalize tangent
      final tangentLen = math.sqrt(
        tangent.latitude * tangent.latitude +
            tangent.longitude * tangent.longitude,
      );
      if (tangentLen < 1e-10) continue;

      final tangentNorm = ll.LatLng(
        tangent.latitude / tangentLen,
        tangent.longitude / tangentLen,
      );

      // Calculate perpendicular normal
      final normal = ll.LatLng(-tangentNorm.longitude, tangentNorm.latitude);

      // Convert halfWidth from meters to degrees (approx 111km per degree)
      final halfWidthDegrees = halfWidth / 111000.0;

      // Calculate border points
      innerBorder.add(ll.LatLng(
        current.latitude - normal.latitude * halfWidthDegrees,
        current.longitude - normal.longitude * halfWidthDegrees,
      ));
      outerBorder.add(ll.LatLng(
        current.latitude + normal.latitude * halfWidthDegrees,
        current.longitude + normal.longitude * halfWidthDegrees,
      ));
    }

    return [
      // Circuit polygon (area between inner and outer borders)
      PolygonLayer(
        polygons: [
          Polygon(
            points: [
              ...innerBorder,
              ...outerBorder.reversed,
            ],
            color: const Color(0xFF2A2A35).withAlpha(180),
            borderStrokeWidth: 0,
          ),
        ],
      ),
      // Inner border
      PolylineLayer(
        polylines: [
          Polyline(
            points: innerBorder,
            strokeWidth: 2.5,
            color: const Color(0xFF1A1A25),
            borderStrokeWidth: 1.0,
            borderColor: Colors.black.withAlpha(128),
          ),
        ],
      ),
      // Outer border
      PolylineLayer(
        polylines: [
          Polyline(
            points: outerBorder,
            strokeWidth: 2.5,
            color: const Color(0xFF1A1A25),
            borderStrokeWidth: 1.0,
            borderColor: Colors.black.withAlpha(128),
          ),
        ],
      ),
      // Center line (optional, thin)
      PolylineLayer(
        polylines: [
          Polyline(
            points: centerLine,
            strokeWidth: 1.0,
            color: const Color(0xFF3A3A45).withAlpha(128),
          ),
        ],
      ),
    ];
  }

  /// Helper per sottrarre LatLng
  ll.LatLng _subtractLatLng(ll.LatLng a, ll.LatLng b) {
    return ll.LatLng(a.latitude - b.latitude, a.longitude - b.longitude);
  }

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();

    // Calculate center and bounds
    double minLat = path.first.latitude;
    double maxLat = path.first.latitude;
    double minLon = path.first.longitude;
    double maxLon = path.first.longitude;

    for (final p in path) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBrandColor.withAlpha(60)),
                  ),
                  child:
                      const Icon(Icons.map_outlined, size: 16, color: kBrandColor),
                ),
                const SizedBox(width: 10),
                const Text(
                  'MAPPA TRACCIATO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            child: SizedBox(
              height: 300,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: ll.LatLng(centerLat, centerLon),
                  initialZoom: 16.5,
                  minZoom: 10.0,
                  maxZoom: 20.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.racesense.pulse',
                  ),
                  // Render circuit layers if trackDefinition is available
                  if (trackDefinition != null) ..._buildCircuitLayers(trackDefinition!),
                  // User's GPS path (green lime)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: path,
                        strokeWidth: 2.5,
                        color: kBrandColor,
                        borderStrokeWidth: 1.0,
                        borderColor: Colors.black.withOpacity(0.5),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      // Start marker
                      Marker(
                        point: path.first,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.flag,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      // End marker
                      Marker(
                        point: path.last,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.flag_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------
   TECHNICAL DATA SECTION
------------------------------------------------------------- */

class _TechnicalDataSection extends StatelessWidget {
  final SessionModel session;
  final int gpsDataCount;
  final double avgGForce;

  const _TechnicalDataSection({
    required this.session,
    required this.gpsDataCount,
    required this.avgGForce,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kBrandColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBrandColor.withAlpha(60)),
                ),
                child: const Icon(Icons.analytics_outlined,
                    size: 16, color: kBrandColor),
              ),
              const SizedBox(width: 10),
              const Text(
                'DATI TECNICI',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.speed,
                  label: 'Velocità Max',
                  value: '${session.maxSpeedKmh.toStringAsFixed(0)} km/h',
                  color: kPulseColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.trending_up,
                  label: 'Velocità Media',
                  value: '${session.avgSpeedKmh.toStringAsFixed(0)} km/h',
                  color: kBrandColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.center_focus_strong,
                  label: 'G-Force Max',
                  value: '${session.maxGForce.toStringAsFixed(2)} g',
                  color: kCoachColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.analytics,
                  label: 'G-Force Media',
                  value: '${avgGForce.toStringAsFixed(2)} g',
                  color: const Color(0xFF4CD964),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TechnicalMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TechnicalMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLineColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: kMutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: kFgColor,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------
   GPS DEVICE SECTION
------------------------------------------------------------- */

class _GpsDeviceSection extends StatelessWidget {
  final double avgAccuracy;
  final int sampleRateHz;
  final int points;
  final String deviceName;

  const _GpsDeviceSection({
    required this.avgAccuracy,
    required this.sampleRateHz,
    required this.points,
    this.deviceName = 'Cellular GPS',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kBrandColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBrandColor.withAlpha(60)),
                ),
                child:
                    const Icon(Icons.gps_fixed, size: 16, color: kBrandColor),
              ),
              const SizedBox(width: 10),
              const Text(
                'DISPOSITIVO GPS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.smartphone,
                  label: 'Dispositivo',
                  value: deviceName,
                  color: kBrandColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.gps_not_fixed,
                  label: 'GPS Accuracy',
                  value: '${avgAccuracy.toStringAsFixed(1)} m',
                  color: kPulseColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.refresh,
                  label: 'Sample Rate',
                  value: '$sampleRateHz Hz',
                  color: kCoachColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.data_usage,
                  label: 'Punti GPS',
                  value: points.toString(),
                  color: const Color(0xFF4CD964),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------
   ACTION BUTTONS
------------------------------------------------------------- */

class _ActionsRow extends StatelessWidget {
  final SessionModel session;
  final bool liked;
  final bool challenged;
  final VoidCallback? onToggleLike;
  final VoidCallback? onToggleChallenge;

  const _ActionsRow({
    required this.session,
    required this.liked,
    required this.challenged,
    this.onToggleLike,
    this.onToggleChallenge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(liked ? 255 : 60),
                  kBrandColor.withAlpha(liked ? 255 : 40),
                ],
              ),
              border: Border.all(color: kBrandColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: kBrandColor.withAlpha(liked ? 100 : 40),
                  blurRadius: liked ? 16 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onToggleLike,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? Colors.black : kBrandColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mi piace (${session.likesCount})',
                        style: TextStyle(
                          color: liked ? Colors.black : kBrandColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: challenged
                  ? LinearGradient(
                      colors: [
                        kPulseColor.withAlpha(60),
                        kPulseColor.withAlpha(40),
                      ],
                    )
                  : null,
              border: Border.all(
                color: challenged ? kPulseColor : kLineColor,
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onToggleChallenge,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.sports_martial_arts,
                        color: challenged ? kPulseColor : kMutedColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ti sfido (${session.challengeCount})',
                        style: TextStyle(
                          color: challenged ? kPulseColor : kMutedColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _MetricFocus { speed, gForce, accuracy }

// ============================================================
// OVERVIEW: CIRCUITO + GRAFICO COMBINATO (stile Recap)
// ============================================================

class _SessionOverviewPanel extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<ll.LatLng> smoothPath;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;
  final List<Duration> laps;

  const _SessionOverviewPanel({
    required this.gpsTrack,
    required this.smoothPath,
    required this.speedHistory,
    required this.gForceHistory,
    required this.gpsAccuracyHistory,
    required this.timeHistory,
    required this.laps,
  });

  @override
  State<_SessionOverviewPanel> createState() => _SessionOverviewPanelState();
}

class _SessionOverviewPanelState extends State<_SessionOverviewPanel> {
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
    if (widget.timeHistory.length < 2 ||
        widget.speedHistory.isEmpty ||
        widget.gForceHistory.isEmpty ||
        widget.gpsAccuracyHistory.isEmpty ||
        widget.gpsTrack.isEmpty) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kLineColor),
        ),
        child: const Center(
          child: Text(
            'Nessun dato registrato per questa sessione',
            style: TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    if (widget.laps.isEmpty) {
      widget.laps.add(widget.timeHistory.last);
    }

    final int lapCount = widget.laps.length;
    _currentLap = _currentLap.clamp(0, lapCount - 1);

    final Duration lapDuration = widget.laps[_currentLap];

    // 👉 Calcola l'intervallo di tempo per questo giro specifico
    Duration lapStartTime = Duration.zero;
    for (int i = 0; i < _currentLap; i++) {
      lapStartTime += widget.laps[i];
    }
    final Duration lapEndTime = lapStartTime + widget.laps[_currentLap];

    // 👉 Filtra solo i sample che appartengono a QUESTO giro
    final List<int> indices = [];
    for (int i = 0; i < widget.timeHistory.length; i++) {
      final t = widget.timeHistory[i];
      if (t >= lapStartTime && t <= lapEndTime) {
        indices.add(i);
      }
    }

    if (indices.length < 2) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kLineColor),
        ),
        child: Center(
          child: Text(
            'Dati insufficienti per il giro ${_currentLap + 1}',
            style: const TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    final int len = indices.length;
    _selectedIndex = _selectedIndex.clamp(0, len - 1);

    final baseMs = widget.timeHistory[indices.first].inMilliseconds.toDouble();
    final List<double> xs = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return (widget.timeHistory[idx].inMilliseconds.toDouble() - baseMs) /
            1000.0;
      },
    );

    final List<FlSpot> speedSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.speedHistory[idx]);
      },
    );
    final List<FlSpot> gSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.gForceHistory[idx]);
      },
    );
    final List<FlSpot> accSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.gpsAccuracyHistory[idx]);
      },
    );

    double minY = speedSpots.first.y;
    double maxY = speedSpots.first.y;
    for (final s in [...speedSpots, ...gSpots, ...accSpots]) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final range = (maxY - minY).abs();
    final chartMinY = range > 0 ? minY - range * 0.1 : minY - 1;
    final chartMaxY = range > 0 ? maxY + range * 0.1 : maxY + 1;

    final cursorX = xs[_selectedIndex];
    final int globalIdx = indices[_selectedIndex];

    // 👉 Percorso GPS solo per questo giro
    final List<ll.LatLng> lapPath = indices
        .where((i) => i < widget.smoothPath.length)
        .map((i) => widget.smoothPath[i])
        .toList();
    final List<double> lapAccel = indices
        .where((i) => i < widget.gForceHistory.length)
        .map((i) => widget.gForceHistory[i])
        .toList();

    ll.LatLng? marker;
    if (globalIdx < widget.gpsTrack.length) {
      final p = widget.gpsTrack[globalIdx];
      marker = ll.LatLng(p.latitude, p.longitude);
    }

    final double curSpeed = widget.speedHistory[globalIdx];
    final double curG = widget.gForceHistory[globalIdx];
    final double curAcc = widget.gpsAccuracyHistory[globalIdx];
    final double curT = xs[_selectedIndex];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0A0F), Color(0xFF050608)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 12,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _currentLap > 0
                      ? kBrandColor.withAlpha(20)
                      : kMutedColor.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _currentLap > 0
                        ? kBrandColor.withAlpha(60)
                        : kMutedColor.withAlpha(30),
                  ),
                ),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: _currentLap > 0 ? kBrandColor : kMutedColor,
                  onPressed: _currentLap > 0
                      ? () {
                          setState(() {
                            _currentLap--;
                            _selectedIndex = 0;
                          });
                        }
                      : null,
                ),
              ),
              Column(
                children: [
                  Text(
                    'LAP ${(_currentLap + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: kFgColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatLap(lapDuration),
                    style: const TextStyle(
                      fontSize: 13,
                      color: kBrandColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: _currentLap < lapCount - 1
                      ? kBrandColor.withAlpha(20)
                      : kMutedColor.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _currentLap < lapCount - 1
                        ? kBrandColor.withAlpha(60)
                        : kMutedColor.withAlpha(30),
                  ),
                ),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  color: _currentLap < lapCount - 1 ? kBrandColor : kMutedColor,
                  onPressed: _currentLap < lapCount - 1
                      ? () {
                          setState(() {
                            _currentLap++;
                            _selectedIndex = 0;
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CircuitTrackView(
            path: lapPath,
            marker: marker,
            accelG: lapAccel,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: xs.first,
                maxX: xs.last,
                minY: chartMinY,
                maxY: chartMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: range > 0 ? range / 4 : 1,
                  verticalInterval:
                      (xs.last - xs.first) > 0 ? (xs.last - xs.first) / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.2),
                    strokeWidth: 0.5,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.15),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(
                        color: kLineColor.withOpacity(0.5), width: 1),
                    bottom: BorderSide(
                        color: kLineColor.withOpacity(0.5), width: 1),
                    right: const BorderSide(color: Colors.transparent),
                    top: const BorderSide(color: Colors.transparent),
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toStringAsFixed(0)}s',
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: cursorX,
                      color: kBrandColor.withOpacity(0.8),
                      strokeWidth: 1.5,
                      dashArray: [6, 3],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.lineBarSpots == null ||
                        response.lineBarSpots!.isEmpty) {
                      return;
                    }
                    final spot = response.lineBarSpots!.first;
                    setState(() {
                      _selectedIndex = spot.spotIndex.clamp(0, len - 1);
                    });
                  },
                ),
                lineBarsData: [
                  _buildLine(speedSpots, const Color(0xFFFF4D4F),
                      _focus == _MetricFocus.speed),
                  _buildLine(gSpots, const Color(0xFF4CD964),
                      _focus == _MetricFocus.gForce),
                  _buildLine(accSpots, const Color(0xFF5AC8FA),
                      _focus == _MetricFocus.accuracy),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metricChip(
                label: 'Speed',
                color: const Color(0xFFFF4D4F),
                selected: _focus == _MetricFocus.speed,
                onTap: () => setState(() => _focus = _MetricFocus.speed),
              ),
              _metricChip(
                label: 'G-Force',
                color: const Color(0xFF4CD964),
                selected: _focus == _MetricFocus.gForce,
                onTap: () => setState(() => _focus = _MetricFocus.gForce),
              ),
              _metricChip(
                label: 'Accuracy',
                color: const Color(0xFF5AC8FA),
                selected: _focus == _MetricFocus.accuracy,
                onTap: () => setState(() => _focus = _MetricFocus.accuracy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kLineColor.withAlpha(60)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metricValue('t', '${curT.toStringAsFixed(2)}s', kBrandColor),
                Container(width: 1, height: 30, color: kLineColor.withAlpha(80)),
                _metricValue('v', '${curSpeed.toStringAsFixed(1)} km/h',
                    const Color(0xFFFF4D4F)),
                Container(width: 1, height: 30, color: kLineColor.withAlpha(80)),
                _metricValue(
                    'g', '${curG.toStringAsFixed(2)}', const Color(0xFF4CD964)),
                Container(width: 1, height: 30, color: kLineColor.withAlpha(80)),
                _metricValue('acc', '${curAcc.toStringAsFixed(1)} m',
                    const Color(0xFF5AC8FA)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricValue(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: kFgColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  LineChartBarData _buildLine(
    List<FlSpot> spots,
    Color baseColor,
    bool focused,
  ) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: focused ? baseColor : baseColor.withOpacity(0.2),
      barWidth: focused ? 3.0 : 1.5,
      isStrokeCapRound: false,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: focused,
        color: baseColor.withOpacity(0.08),
      ),
    );
  }

  Widget _metricChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    color.withAlpha(40),
                    color.withAlpha(25),
                  ],
                )
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? color : color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DISEGNO CIRCUITO (griglia + traccia + puntino posizione)
// ============================================================

class _CircuitTrackView extends StatelessWidget {
  final List<ll.LatLng> path;
  final ll.LatLng? marker;
  final List<double> accelG;

  const _CircuitTrackView({
    required this.path,
    required this.marker,
    this.accelG = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: const Center(
          child: Text(
            'Nessun dato GPS',
            style: TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1.6,
      child: CustomPaint(
        painter: _CircuitPainter(
          path: path,
          marker: marker,
          accelG: accelG,
        ),
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  final List<ll.LatLng> path;
  final ll.LatLng? marker;
  final List<double> accelG;

  _CircuitPainter({
    required this.path,
    required this.marker,
    required this.accelG,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFF0A0A0F)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
      bgPaint,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 0.5;
    const int gridLines = 10;
    final dx = size.width / gridLines;
    final dy = size.height / gridLines;
    for (int i = 1; i < gridLines; i++) {
      final x = dx * i;
      final y = dy * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double minLat = path.first.latitude;
    double maxLat = path.first.latitude;
    double minLon = path.first.longitude;
    double maxLon = path.first.longitude;
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

    final usableW = size.width * 0.85;
    final usableH = size.height * 0.85;
    final scale = (dLat == 0 || dLon == 0)
        ? 1.0
        : math.min(usableW / dLon, usableH / dLat);

    Offset _project(ll.LatLng p) {
      final x = (p.longitude - centerLon) * scale + size.width / 2;
      final y = (centerLat - p.latitude) * scale + size.height / 2;
      return Offset(x, y);
    }

    final ui.Path shadowPath = ui.Path();
    final List<Offset> projected = [];
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      projected.add(o);
      if (i == 0) {
        shadowPath.moveTo(o.dx, o.dy);
      } else {
        shadowPath.lineTo(o.dx, o.dy);
      }
    }
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(shadowPath.shift(const Offset(2, 2)), shadowPaint);

    // Disegna segmento per segmento con colore basato su accel/decel
    for (int i = 1; i < projected.length; i++) {
      final double g = i < accelG.length ? accelG[i] : 0.0;
      final paint = Paint()
        ..color = _colorForG(g)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(projected[i - 1], projected[i], paint);
    }

    if (marker != null) {
      final o = _project(marker!);
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final markerBorder = Paint()
        ..color = kPulseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      final markerGlow = Paint()
        ..color = kPulseColor.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(o, 12, markerGlow);
      canvas.drawCircle(o, 8, markerPaint);
      canvas.drawCircle(o, 8, markerBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.marker != marker ||
        oldDelegate.accelG != accelG;
  }

  Color _colorForG(double g) {
    const pos = Color(0xFF4CD964); // verde accelerazione
    const neg = Color(0xFFFF4D4F); // rosso frenata
    const neu = kBrandColor; // neutro
    final double clamped = g.clamp(-1.5, 1.5).toDouble();
    if (clamped >= 0) {
      final double t = (clamped / 1.5).clamp(0.0, 1.0);
      return Color.lerp(neu, pos, t)!;
    } else {
      final double t = (-clamped / 1.5).clamp(0.0, 1.0);
      return Color.lerp(neu, neg, 1.0 - t)!;
    }
  }
}
