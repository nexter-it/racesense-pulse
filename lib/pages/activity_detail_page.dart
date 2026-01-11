import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme.dart';
import '../models/session_model.dart';
import '../models/track_definition.dart';
import '../services/session_service.dart';
import '../services/engagement_service.dart';
import '../widgets/profile_avatar.dart';
import 'search_user_profile_page.dart';

class ActivityDetailPage extends StatefulWidget {
  static const routeName = '/activity';

  const ActivityDetailPage({super.key});

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage>
    with TickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  final EngagementService _engagementService = EngagementService();

  bool _isLoading = true;
  String? _error;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _bounceController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;

  // Real data from Firestore
  List<GpsPoint> _gpsData = [];
  List<LapModel> _laps = [];
  late SessionModel _session;
  bool _liked = false;

  // Premium colors
  static const Color _bgColor = Color(0xFF0A0A0A);
  static const Color _cardColor = Color(0xFF1A1A1A);
  static const Color _borderColor = Color(0xFF2A2A2A);

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

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) {
      _loadSessionData();
    }
  }

  TrackDefinition? _getTrackDefinition() {
    if (_session.trackDefinition != null) {
      return _session.trackDefinition;
    }

    final predefined =
        PredefinedTracks.findById(_session.trackName.toLowerCase());
    if (predefined != null) {
      return predefined;
    }

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

      final results = await Future.wait([
        _sessionService.getSessionGpsData(_session.sessionId),
        _sessionService.getSessionLaps(_session.sessionId),
      ]);

      _gpsData = results[0] as List<GpsPoint>;
      _laps = results[1] as List<LapModel>;
      final reactions =
          await _engagementService.getUserReactions(_session.sessionId);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _liked = reactions['like'] ?? false;
        });
      }
    } catch (e) {
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
        backgroundColor: _bgColor,
        body: SafeArea(child: _buildLoadingState()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _bgColor,
        body: SafeArea(child: _buildErrorState()),
      );
    }

    final List<double> speedHistory = _gpsData.map((p) => p.speedKmh).toList();
    final List<double> accuracyHistory =
        _gpsData.map((p) => p.accuracy).toList();
    final List<Duration> timeHistory = _gpsData
        .map((p) => Duration(
            milliseconds: p.timestamp.millisecondsSinceEpoch -
                _gpsData.first.timestamp.millisecondsSinceEpoch))
        .toList();
    final List<double> gForceHistory =
        _gpsData.map((p) => p.longitudinalG ?? 0.0).toList();
    final List<double> rollAngleHistory =
        _gpsData.map((p) => p.rollAngle ?? 0.0).toList();
    final List<ll.LatLng> smoothPath =
        _gpsData.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
    final List<Position> gpsTrack = _gpsData
        .map((p) => Position(
              latitude: p.latitude,
              longitude: p.longitude,
              timestamp: p.timestamp,
              accuracy: p.accuracy,
              altitude: 0,
              heading: 0,
              speed: p.speedKmh / 3.6,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            ))
        .toList();

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() => _isLoading = true);
                  await _loadSessionData();
                },
                color: kBrandColor,
                backgroundColor: _cardColor,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  children: [
                    const SizedBox(height: 8),

                    // === HERO CARD: Pilota + Tracciato + Best Lap ===
                    _HeroSessionCard(
                      session: _session,
                      onToggleLike: _handleToggleLike,
                      onShare: _handleShare,
                    ),
                    const SizedBox(height: 16),

                    // === STATS GRID ===
                    _StatsGrid(session: _session),
                    const SizedBox(height: 16),

                    // === TELEMETRIA INTERATTIVA ===
                    if (gpsTrack.isNotEmpty && _laps.isNotEmpty)
                      _TelemetryPanel(
                        gpsTrack: gpsTrack,
                        smoothPath: smoothPath,
                        speedHistory: speedHistory,
                        gForceHistory: gForceHistory,
                        gpsAccuracyHistory: accuracyHistory,
                        timeHistory: timeHistory,
                        rollAngleHistory: rollAngleHistory,
                        laps: _laps.map((l) => l.duration).toList(),
                      ),
                    if (gpsTrack.isNotEmpty && _laps.isNotEmpty)
                      const SizedBox(height: 16),

                    // === TEMPI GIRI ===
                    if (_laps.isNotEmpty)
                      _LapTimesCard(laps: _laps, bestLap: _session.bestLap),
                    if (_laps.isNotEmpty) const SizedBox(height: 16),

                    // === MAPPA ===
                    if (smoothPath.isNotEmpty)
                      _MapCard(
                        fullPath: smoothPath,
                        timeHistory: timeHistory,
                        laps: _laps.map((l) => l.duration).toList(),
                        trackDefinition: _getTrackDefinition(),
                      ),
                    if (smoothPath.isNotEmpty) const SizedBox(height: 16),

                    // === DATI SESSIONE ===
                    _SessionDataCard(session: _session),
                    const SizedBox(height: 16),

                    // === DATI GPS ===
                    _GpsDataCard(
                      gpsDataCount: _gpsData.length,
                      avgGpsAccuracy: _session.avgGpsAccuracy,
                      gpsSampleRateHz: _session.gpsSampleRateHz,
                    ),
                    const SizedBox(height: 16),

                    // === INFO SESSIONE (in fondo) ===
                    _SessionInfoCard(session: _session),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleToggleLike() async {
    HapticFeedback.lightImpact();
    await _engagementService.toggleLike(_session.sessionId);
    // Non serve più setState, lo stream si aggiorna automaticamente
  }

  Future<void> _handleShare() async {
    HapticFeedback.mediumImpact();

    // Formatta i dati della sessione
    final bestLap = _laps.isNotEmpty
        ? _laps.reduce((a, b) => a.duration < b.duration ? a : b)
        : null;

    final bestLapText = bestLap != null
        ? _formatLapDuration(bestLap.duration)
        : 'N/A';

    final totalLaps = _laps.length;
    final circuitName = _session.trackName;
    final date = DateFormat('dd/MM/yyyy').format(_session.dateTime);

    // Crea il messaggio di condivisione
    final shareText = '''
🏁 RaceSense Pulse
Circuito: $circuitName
Data: $date
Giri completati: $totalLaps
Miglior giro: $bestLapText

Scarica RaceSense Pulse e sfida i tuoi tempi!
''';

    try {
      // Su iOS serve specificare la posizione di origine del popover
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        shareText,
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante la condivisione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatLapDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_bgColor, const Color(0xFF121212)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _borderColor, width: 1),
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
                Text(
                  _session.trackName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 12, color: kMutedColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _session.location,
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // GPS Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: kBrandColor.withAlpha(15),
              border: Border.all(color: kBrandColor.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _session.usedBleDevice ? Icons.bluetooth : Icons.sensors,
                  size: 14,
                  color: kBrandColor,
                ),
                const SizedBox(width: 6),
                Text(
                  _session.usedBleDevice ? 'BLE' : 'GPS',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kBrandColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([
              _rotateController,
              _pulseAnimation,
              _bounceAnimation,
            ]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -_bounceAnimation.value),
                child: Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          kBrandColor.withAlpha(60),
                          kBrandColor.withAlpha(20),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Transform.rotate(
                        angle: _rotateController.value * 2 * math.pi,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                kBrandColor.withAlpha(100),
                                kPulseColor.withAlpha(60),
                              ],
                            ),
                            border: Border.all(color: kBrandColor, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: kBrandColor.withAlpha(80),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.speed,
                            color: kBrandColor,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Caricamento telemetria',
            style: TextStyle(
              color: kFgColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final delay = index * 0.2;
                  final animValue = ((_pulseController.value + delay) % 1.0);
                  final opacity = 0.3 + (0.7 * math.sin(animValue * math.pi));
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBrandColor.withAlpha((opacity * 255).toInt()),
                      boxShadow: [
                        BoxShadow(
                          color: kBrandColor.withAlpha((opacity * 128).toInt()),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kErrorColor.withAlpha(40),
                    kErrorColor.withAlpha(20),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(color: kErrorColor, width: 2),
              ),
              child: const Icon(Icons.error_outline, size: 56, color: kErrorColor),
            ),
            const SizedBox(height: 24),
            Text(
              _error!,
              style: const TextStyle(color: kFgColor, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [kBrandColor.withAlpha(40), kBrandColor.withAlpha(25)],
                  ),
                  border: Border.all(color: kBrandColor, width: 1.5),
                ),
                child: const Text(
                  'Torna indietro',
                  style: TextStyle(color: kBrandColor, fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   HERO SESSION CARD - Pilota + Tracciato + Actions
   Struttura simile alla card del feed
============================================================ */

class _HeroSessionCard extends StatefulWidget {
  final SessionModel session;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;

  const _HeroSessionCard({
    required this.session,
    required this.onToggleLike,
    required this.onShare,
  });

  @override
  State<_HeroSessionCard> createState() => _HeroSessionCardState();
}

class _HeroSessionCardState extends State<_HeroSessionCard> {
  final EngagementService _engagementService = EngagementService();

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  List<Offset> _buildTrack2d() {
    final raw = widget.session.displayPath;
    if (raw == null || raw.isEmpty) return _generateFakeTrack();

    final points = <Offset>[];
    for (final m in raw) {
      final lat = m['lat'];
      final lon = m['lon'];
      if (lat != null && lon != null) {
        points.add(Offset(lon, lat));
      }
    }
    return points.length < 2 ? _generateFakeTrack() : points;
  }

  List<Offset> _generateFakeTrack() {
    final List<Offset> result = [];
    final List<Offset> base = [
      const Offset(-1.0, -0.1),
      const Offset(-0.3, -0.6),
      const Offset(0.3, -0.65),
      const Offset(0.9, -0.2),
      const Offset(1.0, 0.2),
      const Offset(0.4, 0.7),
      const Offset(-0.2, 0.6),
      const Offset(-0.9, 0.2),
      const Offset(-1.0, -0.1),
    ];

    for (int i = 0; i < base.length - 1; i++) {
      final p0 = base[i];
      final p1 = base[i + 1];
      for (int j = 0; j < 12; j++) {
        final t = j / 12;
        final nx = p0.dx + (p1.dx - p0.dx) * t;
        final ny = p0.dy + (p1.dy - p0.dy) * t;
        result.add(Offset(nx * 120, ny * 80));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bestLapText = widget.session.bestLap != null
        ? _formatDuration(widget.session.bestLap!)
        : '--:--';
    final formattedDate = DateFormat('dd MMMM yyyy', 'it_IT').format(widget.session.dateTime);
    final formattedTime = DateFormat('HH:mm').format(widget.session.dateTime);
    final track2d = _buildTrack2d();

    // Design COMPLETAMENTE DIVERSO dal feed
    return Column(
      children: [
        // === CARD PILOTA (separata in alto) ===
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                kBrandColor.withAlpha(25),
                kBrandColor.withAlpha(10),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border.all(color: kBrandColor.withAlpha(80), width: 2),
            boxShadow: [
              BoxShadow(
                color: kBrandColor.withAlpha(30),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchUserProfilePage(
                    userId: widget.session.userId,
                    fullName: widget.session.driverFullName,
                  ),
                ),
              );
            },
            child: Column(
              children: [
                Row(
                  children: [
                    _AvatarWidget(userId: widget.session.userId),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.session.driverFullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: kFgColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '@${widget.session.driverUsername}',
                            style: TextStyle(
                              color: kBrandColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kBrandColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBrandColor, width: 2),
                      ),
                      child: const Icon(Icons.arrow_forward_rounded, color: kBrandColor, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Data e ora nella card pilota
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today_rounded, color: kMutedColor, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kBrandColor,
                        ),
                      ),
                      Icon(Icons.access_time_rounded, color: kMutedColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // === CARD TRACCIATO CON BEST LAP (design verticale) ===
        // Container(
        //   decoration: BoxDecoration(
        //     borderRadius: BorderRadius.circular(24),
        //     gradient: const LinearGradient(
        //       colors: [Color(0xFF1C1C1E), Color(0xFF0D0D0D)],
        //       begin: Alignment.topLeft,
        //       end: Alignment.bottomRight,
        //     ),
        //     border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
        //     boxShadow: [
        //       BoxShadow(
        //         color: Colors.black.withAlpha(120),
        //         blurRadius: 24,
        //         offset: const Offset(0, 10),
        //       ),
        //     ],
        //   ),
        //   child: Column(
        //     crossAxisAlignment: CrossAxisAlignment.start,
        //     children: [
        //       // Nome circuito in alto
        //       Padding(
        //         padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        //         child: Column(
        //           crossAxisAlignment: CrossAxisAlignment.start,
        //           children: [
        //             Row(
        //               children: [
        //                 Container(
        //                   padding: const EdgeInsets.all(10),
        //                   decoration: BoxDecoration(
        //                     color: kPulseColor.withAlpha(25),
        //                     borderRadius: BorderRadius.circular(12),
        //                     border: Border.all(color: kPulseColor.withAlpha(80)),
        //                   ),
        //                   child: const Icon(Icons.flag_rounded, color: kPulseColor, size: 20),
        //                 ),
        //                 const SizedBox(width: 14),
        //                 Expanded(
        //                   child: Column(
        //                     crossAxisAlignment: CrossAxisAlignment.start,
        //                     children: [
        //                       Text(
        //                         widget.session.trackName,
        //                         style: const TextStyle(
        //                           fontWeight: FontWeight.w900,
        //                           fontSize: 19,
        //                           color: kFgColor,
        //                           letterSpacing: -0.5,
        //                         ),
        //                       ),
        //                       const SizedBox(height: 4),
        //                       Row(
        //                         children: [
        //                           Icon(Icons.place, color: kMutedColor, size: 14),
        //                           const SizedBox(width: 6),
        //                           Expanded(
        //                             child: Text(
        //                               widget.session.location,
        //                               style: TextStyle(
        //                                 color: kMutedColor,
        //                                 fontSize: 13,
        //                                 fontWeight: FontWeight.w600,
        //                               ),
        //                             ),
        //                           ),
        //                         ],
        //                       ),
        //                     ],
        //                   ),
        //                 ),
        //               ],
        //             ),
        //           ],
        //         ),
        //       ),

        //       // Visualizzazione tracciato
        //       Container(
        //         margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        //         height: 180,
        //         decoration: BoxDecoration(
        //           borderRadius: BorderRadius.circular(18),
        //           color: const Color(0xFF000000),
        //           border: Border.all(color: const Color(0xFF2A2A2A), width: 1.5),
        //         ),
        //         child: ClipRRect(
        //           borderRadius: BorderRadius.circular(18),
        //           child: CustomPaint(
        //             painter: _TrackPainter(path: track2d),
        //             child: const SizedBox.expand(),
        //           ),
        //         ),
        //       ),

        //       // Best lap in basso (grande e prominente)
        //       Container(
        //         margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        //         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        //         decoration: BoxDecoration(
        //           borderRadius: BorderRadius.circular(18),
        //           gradient: LinearGradient(
        //             colors: [
        //               kPulseColor.withAlpha(50),
        //               kPulseColor.withAlpha(25),
        //             ],
        //           ),
        //           border: Border.all(color: kPulseColor, width: 2),
        //           boxShadow: [
        //             BoxShadow(
        //               color: kPulseColor.withAlpha(40),
        //               blurRadius: 20,
        //               spreadRadius: 2,
        //             ),
        //           ],
        //         ),
        //         child: Row(
        //           mainAxisAlignment: MainAxisAlignment.center,
        //           children: [
        //             Column(
        //               children: [
        //                 const Icon(Icons.emoji_events_rounded, color: kPulseColor, size: 28),
        //                 const SizedBox(height: 4),
        //                 Text(
        //                   'BEST LAP',
        //                   style: TextStyle(
        //                     fontSize: 10,
        //                     letterSpacing: 1.2,
        //                     color: kPulseColor.withAlpha(200),
        //                     fontWeight: FontWeight.w900,
        //                   ),
        //                 ),
        //               ],
        //             ),
        //             const SizedBox(width: 20),
        //             Text(
        //               bestLapText,
        //               style: const TextStyle(
        //                 fontSize: 32,
        //                 fontWeight: FontWeight.w900,
        //                 color: kPulseColor,
        //                 fontFeatures: [ui.FontFeature.tabularFigures()],
        //                 letterSpacing: -1,
        //               ),
        //             ),
        //           ],
        //         ),
        //       ),
        //     ],
        //   ),
        // ),

        // === ACTION BUTTONS E INFO (fuori dai box) ===
        const SizedBox(height: 5),

        // Action buttons
        Row(
          children: [
            // Like button con stream
            Expanded(
              child: StreamBuilder<bool>(
                stream: _engagementService.watchLikeStatus(widget.session.sessionId),
                initialData: false,
                builder: (context, likeSnapshot) {
                  final liked = likeSnapshot.data ?? false;
                  return StreamBuilder<int>(
                    stream: _engagementService.watchSessionLikesCount(widget.session.sessionId),
                    initialData: widget.session.likesCount,
                    builder: (context, countSnapshot) {
                      final likesCount = countSnapshot.data ?? widget.session.likesCount;
                      return _ActionButton(
                        icon: liked ? Icons.favorite : Icons.favorite_border,
                        label: 'Mi piace',
                        count: likesCount,
                        isActive: liked,
                        activeColor: kBrandColor,
                        onTap: widget.onToggleLike,
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.share,
                label: 'Condividi',
                count: null,
                isActive: false,
                activeColor: kBrandColor,
                onTap: widget.onShare,
              ),
            ),
          ],
        ),

        // Vehicle category, weather and BLE info (largo tutto lo schermo)
        if (widget.session.vehicleCategory != null ||
            widget.session.weather != null ||
            widget.session.usedBleDevice)
          Container(
            margin: const EdgeInsets.only(top: 15),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF1C1C1E), Color(0xFF141414)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFF3A3A3C), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                if (widget.session.vehicleCategory != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: kBrandColor.withAlpha(15),
                        border: Border.all(color: kBrandColor.withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.directions_car, color: kBrandColor, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.session.vehicleCategory!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kBrandColor,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.session.vehicleCategory != null && widget.session.weather != null)
                  const SizedBox(width: 10),
                if (widget.session.weather != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFFFA726).withAlpha(15),
                        border: Border.all(color: const Color(0xFFFFA726).withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wb_sunny, color: Color(0xFFFFA726), size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.session.weather!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kFgColor,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((widget.session.vehicleCategory != null || widget.session.weather != null) &&
                    widget.session.usedBleDevice)
                  const SizedBox(width: 10),
                if (widget.session.usedBleDevice)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFFF9500).withAlpha(15),
                        border: Border.all(color: const Color(0xFFFF9500).withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bluetooth, color: Color(0xFFFF9500), size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'BLE 15Hz',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFFF9500),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.count,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: isActive
              ? LinearGradient(colors: [activeColor, activeColor.withAlpha(200)])
              : LinearGradient(colors: [activeColor.withAlpha(20), activeColor.withAlpha(10)]),
          border: Border.all(
            color: isActive ? Colors.transparent : activeColor.withAlpha(60),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: activeColor.withAlpha(60), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? Colors.black : activeColor, size: 18),
            const SizedBox(width: 8),
            Text(
              count != null ? '$label ($count)' : label,
              style: TextStyle(
                color: isActive ? Colors.black : activeColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarWidget extends StatelessWidget {
  final String userId;

  const _AvatarWidget({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String?>>(
      future: _getUserData(),
      builder: (context, snapshot) {
        final userData = snapshot.data ?? {'initials': 'US', 'profileImageUrl': null};
        final initials = userData['initials'] ?? 'US';
        final profileImageUrl = userData['profileImageUrl'];

        return ProfileAvatar(
          profileImageUrl: profileImageUrl,
          userTag: initials,
          size: 48,
          borderWidth: 2,
          showGradientBorder: true,
        );
      },
    );
  }

  Future<Map<String, String?>> _getUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return {'initials': 'US', 'profileImageUrl': null};

      final data = doc.data();
      final fullName = data?['fullName'] as String? ?? 'User';
      final profileImageUrl = data?['profileImageUrl'] as String?;

      final nameParts = fullName.split(' ');
      String initials;

      if (nameParts.length >= 2 &&
          nameParts[0].isNotEmpty &&
          nameParts[1].isNotEmpty) {
        initials = nameParts[0][0].toUpperCase() + nameParts[1][0].toUpperCase();
      } else if (nameParts.isNotEmpty && nameParts[0].length >= 2) {
        initials = nameParts[0].substring(0, 2).toUpperCase();
      } else {
        initials = 'US';
      }

      return {'initials': initials, 'profileImageUrl': profileImageUrl};
    } catch (e) {
      return {'initials': 'US', 'profileImageUrl': null};
    }
  }
}

/* ============================================================
   STATS GRID
============================================================ */

class _StatsGrid extends StatelessWidget {
  final SessionModel session;

  const _StatsGrid({required this.session});

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
            icon: Icons.loop,
            value: '${session.lapCount}',
            label: 'Giri',
            color: const Color(0xFF29B6F6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.route,
            value: '${session.distanceKm.toStringAsFixed(1)} km',
            label: 'Distanza',
            color: const Color(0xFF00E676),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.access_time,
            value: _formatDuration(session.totalDuration),
            label: 'Totale',
            color: kBrandColor,
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
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1A1A), const Color(0xFF141414)],
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
            style: TextStyle(color: kFgColor, fontSize: 15, fontWeight: FontWeight.w900),
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
   TELEMETRY PANEL - Circuito + Grafico Sincronizzato
============================================================ */

enum _MetricFocus { speed, gForce, rollAngle }

class _TelemetryPanel extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<ll.LatLng> smoothPath;
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

    if (widget.laps.isEmpty) {
      widget.laps.add(widget.timeHistory.last);
    }

    final int lapCount = widget.laps.length;
    _currentLap = _currentLap.clamp(0, lapCount - 1);

    Duration lapStartTime = Duration.zero;
    for (int i = 0; i < _currentLap; i++) {
      lapStartTime += widget.laps[i];
    }
    final Duration lapEndTime = lapStartTime + widget.laps[_currentLap];

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
    final double curRoll = widget.rollAngleHistory[globalIdx];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
        ),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                        'Giro ${_currentLap + 1} di $lapCount • ${_formatLap(widget.laps[_currentLap])}',
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
                    getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFF2A2A2A).withAlpha(60), strokeWidth: 0.5),
                    getDrawingVerticalLine: (value) => FlLine(color: const Color(0xFF2A2A2A).withAlpha(40), strokeWidth: 0.5),
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
                        _buildLine(speedSpots, const Color(0xFFFF4D4F), _focus == _MetricFocus.speed, maxSpeedIndex: maxSpeedIndex),
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
              border: const Border(top: BorderSide(color: Color(0xFF2A2A2A))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _valueDisplay('v', '${curSpeed.toStringAsFixed(1)} km/h', const Color(0xFFFF4D4F)),
                Container(width: 1, height: 24, color: const Color(0xFF2A2A2A)),
                _valueDisplay('g', '${curG.toStringAsFixed(2)} g', const Color(0xFF4CD964)),
                Container(width: 1, height: 24, color: const Color(0xFF2A2A2A)),
                _valueDisplay('r', '${curRoll.toStringAsFixed(1)}°', const Color(0xFF00B8D4)),
                Container(width: 1, height: 24, color: const Color(0xFF2A2A2A)),
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
        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF141414)]),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
  final List<ll.LatLng> path;
  final ll.LatLng? marker;
  final List<double> accelG;

  const _CircuitView({required this.path, this.marker, this.accelG = const []});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2A2A)),
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
  final List<ll.LatLng> path;
  final ll.LatLng? marker;
  final List<double> accelG;

  _CircuitPainter({required this.path, this.marker, required this.accelG});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0A0A0A);
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

    Offset project(ll.LatLng p) => Offset(
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
        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF141414)]),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                border: Border(top: BorderSide(color: const Color(0xFF2A2A2A).withAlpha(100))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isBest ? kPulseColor.withAlpha(30) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isBest ? kPulseColor : const Color(0xFF2A2A2A)),
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
   MAP CARD - con navigazione giri
============================================================ */

class _MapCard extends StatefulWidget {
  final List<ll.LatLng> fullPath;
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

  List<ll.LatLng> _getLapPath() {
    if (_showAllLaps || widget.laps.isEmpty) {
      return widget.fullPath;
    }

    Duration lapStartTime = Duration.zero;
    for (int i = 0; i < _currentLap; i++) {
      lapStartTime += widget.laps[i];
    }
    final Duration lapEndTime = lapStartTime + widget.laps[_currentLap];

    final List<ll.LatLng> lapPath = [];
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
      // Marker centrale sulla linea del via
      final centerFinish = ll.LatLng(
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
        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF141414)]),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                  initialCenter: ll.LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2),
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
   SESSION INFO CARD - Stile griglia professionale
============================================================ */

class _SessionInfoCard extends StatelessWidget {
  final SessionModel session;

  const _SessionInfoCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${session.dateTime.day.toString().padLeft(2, '0')}/${session.dateTime.month.toString().padLeft(2, '0')}/${session.dateTime.year}';
    final timeStr = '${session.dateTime.hour.toString().padLeft(2, '0')}:${session.dateTime.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF141414)]),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kMutedColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kMutedColor.withAlpha(40)),
                  ),
                  child: Icon(Icons.info_outline, size: 18, color: kMutedColor.withAlpha(200)),
                ),
                const SizedBox(width: 12),
                Text(
                  'DETTAGLI SESSIONE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kMutedColor.withAlpha(200), letterSpacing: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Prima riga: Circuito + Località
            Row(
              children: [
                Expanded(child: _infoTile(Icons.flag_outlined, 'Circuito', session.trackName, const Color(0xFF5AC8FA))),
                const SizedBox(width: 10),
                Expanded(child: _infoTile(Icons.place_outlined, 'Località', session.location, const Color(0xFF4CD964))),
              ],
            ),
            const SizedBox(height: 10),

            // Seconda riga: Data + Ora + Visibilità
            Row(
              children: [
                Expanded(child: _infoTile(Icons.calendar_today_outlined, 'Data', dateStr, const Color(0xFFFF9500))),
                const SizedBox(width: 10),
                Expanded(child: _infoTile(Icons.schedule_outlined, 'Ora', timeStr, kPulseColor)),
                const SizedBox(width: 10),
                Expanded(child: _infoTile(
                  session.isPublic ? Icons.public_outlined : Icons.lock_outline,
                  'Visibilità',
                  session.isPublic ? 'Pubblica' : 'Privata',
                  session.isPublic ? kBrandColor : kMutedColor,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A).withAlpha(150)),
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
   SESSION DATA CARD - Dati Sessione (Velocità, G-Force)
============================================================ */

class _SessionDataCard extends StatelessWidget {
  final SessionModel session;

  const _SessionDataCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF141414)]),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                Expanded(child: _techMetric(Icons.speed, 'Max Speed', '${session.maxSpeedKmh.toStringAsFixed(0)} km/h', kPulseColor)),
                const SizedBox(width: 10),
                Expanded(child: _techMetric(Icons.trending_up, 'Avg Speed', '${session.avgSpeedKmh.toStringAsFixed(0)} km/h', kBrandColor)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _techMetric(Icons.center_focus_strong, 'Max G', '${session.maxGForce.toStringAsFixed(2)} g', kCoachColor)),
                const SizedBox(width: 10),
                Expanded(child: _techMetric(Icons.straighten, 'Distanza', '${session.distanceKm.toStringAsFixed(2)} km', const Color(0xFFFF9500))),
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
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A).withAlpha(150)),
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
   GPS DATA CARD - Dati GPS
============================================================ */

class _GpsDataCard extends StatelessWidget {
  final int gpsDataCount;
  final double avgGpsAccuracy;
  final int gpsSampleRateHz;

  const _GpsDataCard({
    required this.gpsDataCount,
    required this.avgGpsAccuracy,
    required this.gpsSampleRateHz,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF141414)]),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A).withAlpha(150)),
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
   TRACK PAINTER (for Hero Card)
============================================================ */

class _TrackPainter extends CustomPainter {
  final List<Offset> path;

  _TrackPainter({required this.path});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()..color = Colors.white.withAlpha(8)..strokeWidth = 1;
    const gridCount = 8;
    final dx = size.width / gridCount;
    final dy = size.height / gridCount;
    for (int i = 1; i < gridCount; i++) {
      canvas.drawLine(Offset(dx * i, 0), Offset(dx * i, size.height), gridPaint);
      canvas.drawLine(Offset(0, dy * i), Offset(size.width, dy * i), gridPaint);
    }

    final glowPaint = Paint()
      ..color = kBrandColor.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final trackPaint = Paint()
      ..color = Colors.white.withAlpha(230)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final accentPaint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [kBrandColor, kPulseColor])
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (path.isNotEmpty) {
      double minX = path.first.dx, maxX = path.first.dx;
      double minY = path.first.dy, maxY = path.first.dy;
      for (final p in path) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }

      final width = (maxX - minX).abs();
      final height = (maxY - minY).abs();
      const padding = 24.0;
      final usableW = w - 2 * padding;
      final usableH = h - 2 * padding;
      final scale = math.min(usableW / (width == 0 ? 1 : width), usableH / (height == 0 ? 1 : height));
      final centerX = (minX + maxX) / 2;
      final centerY = (minY + maxY) / 2;

      final trackPath = Path();
      final List<Offset> canvasPoints = [];

      for (int i = 0; i < path.length; i++) {
        final p = path[i];
        final cx = w / 2 + (p.dx - centerX) * scale;
        final cy = h / 2 - (p.dy - centerY) * scale;
        final c = Offset(cx, cy);
        canvasPoints.add(c);
        if (i == 0) {
          trackPath.moveTo(c.dx, c.dy);
        } else {
          trackPath.lineTo(c.dx, c.dy);
        }
      }

      canvas.drawPath(trackPath, glowPaint);
      canvas.drawPath(trackPath, trackPaint);
      canvas.drawPath(trackPath, accentPaint);

      if (canvasPoints.isNotEmpty) {
        final startPoint = canvasPoints.first;
        canvas.drawCircle(startPoint, 10, Paint()..color = kBrandColor.withAlpha(80)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(startPoint, 5, Paint()..color = kBrandColor);
        canvas.drawCircle(startPoint, 5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) => oldDelegate.path != path;
}
