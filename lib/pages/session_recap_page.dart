import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';

import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/session_metadata_dialog.dart';
import '../services/session_service.dart';
import '../services/firestore_service.dart';
import '../models/session_model.dart';

class SessionRecapPage extends StatelessWidget {
  final List<Position> gpsTrack;
  final List<LatLng> smoothPath;
  final List<Duration> laps;
  final Duration totalDuration;
  final Duration? bestLap;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;

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
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  double _calculateDistance() {
    if (gpsTrack.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < gpsTrack.length; i++) {
      final prev = gpsTrack[i - 1];
      final curr = gpsTrack[i];

      final dLat = (curr.latitude - prev.latitude) * math.pi / 180.0;
      final dLon = (curr.longitude - prev.longitude) * math.pi / 180.0;

      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(prev.latitude * math.pi / 180.0) *
              math.cos(curr.latitude * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);

      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      totalDistance += 6371000 * c; // Raggio Terra in metri
    }

    return totalDistance / 1000; // Converti in km
  }

  double _getMaxSpeed() {
    if (speedHistory.isEmpty) return 0;
    return speedHistory.reduce(math.max);
  }

  double _getAvgSpeed() {
    if (speedHistory.isEmpty) return 0;
    return speedHistory.reduce((a, b) => a + b) / speedHistory.length;
  }

  double _getMaxGForce() {
    if (gForceHistory.isEmpty) return 0;
    return gForceHistory.reduce(math.max);
  }

  double _getAvgGpsAccuracy() {
    if (gpsAccuracyHistory.isEmpty) return 0;
    return gpsAccuracyHistory.reduce((a, b) => a + b) / gpsAccuracyHistory.length;
  }

  int _getGpsSampleRate() {
    if (timeHistory.length < 2) return 0;

    int totalIntervals = 0;
    int sumMs = 0;

    for (int i = 1; i < timeHistory.length; i++) {
      final diff = timeHistory[i].inMilliseconds - timeHistory[i - 1].inMilliseconds;
      if (diff > 0 && diff < 5000) {
        sumMs += diff;
        totalIntervals++;
      }
    }

    if (totalIntervals == 0) return 0;
    final avgMs = sumMs / totalIntervals;
    return (1000 / avgMs).round();
  }

  Future<void> _handleSaveSession(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi effettuare il login per salvare la sessione'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    // Mostra dialog per metadata
    final metadata = await showDialog<SessionMetadata>(
      context: context,
      builder: (context) => SessionMetadataDialog(gpsTrack: gpsTrack),
    );

    if (metadata == null) return; // Utente ha annullato

    // Mostra loading
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
        ),
      ),
    );

    try {
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
        driverFullName:
            user.displayName ?? user.email ?? 'Pilota',
        driverUsername: username,
        trackName: metadata.trackName,
        location: metadata.location,
        locationCoords: metadata.locationCoords,
        isPublic: metadata.isPublic,
        gpsTrack: gpsTrack,
        laps: laps,
        totalDuration: totalDuration,
        speedHistory: speedHistory,
        gForceHistory: gForceHistory,
        gpsAccuracyHistory: gpsAccuracyHistory,
        timeHistory: timeHistory,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Chiudi loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Sessione salvata con successo!'),
          backgroundColor: kBrandColor,
        ),
      );

      // Torna alla home dopo 1 secondo
      await Future.delayed(const Duration(seconds: 1));
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Chiudi loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = _calculateDistance();
    final maxSpeed = _getMaxSpeed();
    final avgSpeed = _getAvgSpeed();
    final maxGForce = _getMaxGForce();
    final avgGpsAccuracy = _getAvgGpsAccuracy();
    final gpsSampleRate = _getGpsSampleRate();

    // Convert to LapModel list for compatibility with widgets
    final lapModels = laps.asMap().entries.map((entry) {
      final index = entry.key;
      final duration = entry.value;

      // Calculate avg/max speed for this lap
      Duration lapStart = Duration.zero;
      for (int i = 0; i < index; i++) {
        lapStart += laps[i];
      }
      final lapEnd = lapStart + duration;

      final lapSpeedData = <double>[];
      for (int j = 0; j < timeHistory.length; j++) {
        if (timeHistory[j] >= lapStart && timeHistory[j] <= lapEnd) {
          if (j < speedHistory.length) {
            lapSpeedData.add(speedHistory[j]);
          }
        }
      }

      final avgSpeedKmh = lapSpeedData.isNotEmpty
          ? lapSpeedData.reduce((a, b) => a + b) / lapSpeedData.length
          : 0.0;
      final maxSpeedKmh = lapSpeedData.isNotEmpty
          ? lapSpeedData.reduce(math.max)
          : 0.0;

      return LapModel(
        lapIndex: index,
        duration: duration,
        avgSpeedKmh: avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh,
      );
    }).toList();

    return Scaffold(
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
          children: [
            // Header
            _buildHeader(context),

            // Contenuto scrollabile
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero Stats Cards
                    _HeroStatsGrid(
                      totalDuration: totalDuration,
                      bestLap: bestLap,
                      distance: distance,
                      lapCount: laps.length,
                    ),
                    const SizedBox(height: 24),

                    // Session Info Card
                    _SessionInfoCard(dateTime: DateTime.now()),
                    const SizedBox(height: 24),

                    // Telemetria interattiva con circuito
                    if (gpsTrack.isNotEmpty && laps.isNotEmpty)
                      _SessionOverviewPanel(
                        gpsTrack: gpsTrack,
                        smoothPath: smoothPath,
                        speedHistory: speedHistory,
                        gForceHistory: gForceHistory,
                        gpsAccuracyHistory: gpsAccuracyHistory,
                        timeHistory: timeHistory,
                        laps: laps,
                      ),
                    const SizedBox(height: 24),

                    // Lap Times List
                    if (laps.isNotEmpty)
                      _LapTimesList(
                        laps: lapModels,
                        bestLap: bestLap,
                      ),
                    const SizedBox(height: 24),

                    // Mappa OpenStreetMap
                    if (smoothPath.isNotEmpty)
                      _MapSection(
                        path: smoothPath,
                        trackName: 'Sessione Live',
                      ),
                    const SizedBox(height: 24),

                    // Technical Data
                    _TechnicalDataSection(
                      maxSpeedKmh: maxSpeed,
                      avgSpeedKmh: avgSpeed,
                      maxGForce: maxGForce,
                      avgGpsAccuracy: avgGpsAccuracy,
                      gpsSampleRateHz: gpsSampleRate,
                      gpsDataCount: gpsTrack.length,
                    ),
                    const SizedBox(height: 24),

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _handleSaveSession(context),
                        icon: const Icon(Icons.save),
                        label: const Text('SALVA SESSIONE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RACESENSE PULSE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: kMutedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Riepilogo Sessione',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Copy all widgets from activity_detail_page.dart

/* -------------------------------------------------------------
   HERO STATS GRID - Premium stats showcase
------------------------------------------------------------- */

class _HeroStatsGrid extends StatelessWidget {
  final Duration totalDuration;
  final Duration? bestLap;
  final double distance;
  final int lapCount;

  const _HeroStatsGrid({
    required this.totalDuration,
    required this.bestLap,
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
    final bestLapStr = bestLap != null
        ? _formatDuration(bestLap!)
        : '--:--';
    final totalTimeStr = _formatDuration(totalDuration);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PremiumStatCard(
                label: "BEST LAP",
                value: bestLapStr,
                icon: Icons.timer,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8E85FF), Color(0xFF6B5FFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
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
                value: "${distance.toStringAsFixed(1)} km",
                icon: Icons.route,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PremiumStatCard(
                label: "GIRI",
                value: lapCount.toString(),
                icon: Icons.refresh,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
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
  final bool highlight;

  const _PremiumStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
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
          color: highlight ? kPulseColor : kLineColor,
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: kPulseColor.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: highlight ? kPulseColor : kMutedColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: highlight ? kPulseColor : kMutedColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: highlight ? kPulseColor : kFgColor,
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
  final DateTime dateTime;

  const _SessionInfoCard({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0A0A0F),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: kBrandColor),
              const SizedBox(width: 8),
              const Text(
                'INFORMAZIONI SESSIONE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kBrandColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Data',
            value: dateStr,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: 'Ora',
            value: timeStr,
          ),
          const SizedBox(height: 12),
          const _InfoRow(
            icon: Icons.track_changes_outlined,
            label: 'Tipo',
            value: 'Sessione Live',
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
        Icon(icon, size: 16, color: kMutedColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: kMutedColor,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
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
        color: const Color(0xFF0A0A0F),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 16, color: kBrandColor),
                const SizedBox(width: 8),
                const Text(
                  'TEMPI SUL GIRO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
            separatorBuilder: (_, __) => const Divider(
              color: kLineColor,
              height: 0,
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
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: isBest
                      ? LinearGradient(
                          colors: [
                            kPulseColor.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isBest
                            ? kPulseColor.withOpacity(0.2)
                            : const Color(0xFF1A1A20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isBest ? kPulseColor : kLineColor,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${lap.lapIndex + 1}',
                        style: TextStyle(
                          fontSize: 13,
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
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isBest ? kPulseColor : kFgColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Avg: ${lap.avgSpeedKmh.toStringAsFixed(1)} km/h  •  Max: ${lap.maxSpeedKmh.toStringAsFixed(1)} km/h',
                            style: const TextStyle(
                              fontSize: 11,
                              color: kMutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isBest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kPulseColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: kPulseColor),
                        ),
                        child: const Text(
                          'BEST',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: kPulseColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (!isBest && isWorst)
                      Icon(
                        Icons.arrow_downward,
                        size: 16,
                        color: kMutedColor.withOpacity(0.5),
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
  final List<LatLng> path;
  final String trackName;

  const _MapSection({
    required this.path,
    required this.trackName,
  });

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
        color: const Color(0xFF0A0A0F),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, size: 16, color: kBrandColor),
                const SizedBox(width: 8),
                const Text(
                  'MAPPA TRACCIATO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
                  initialCenter: LatLng(centerLat, centerLon),
                  initialZoom: 15.0,
                  minZoom: 10.0,
                  maxZoom: 18.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.racesense.pulse',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: path,
                        strokeWidth: 4.0,
                        color: kBrandColor,
                        borderStrokeWidth: 2.0,
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
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final double maxGForce;
  final double avgGpsAccuracy;
  final int gpsSampleRateHz;
  final int gpsDataCount;

  const _TechnicalDataSection({
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.maxGForce,
    required this.avgGpsAccuracy,
    required this.gpsSampleRateHz,
    required this.gpsDataCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0A0A0F),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 16, color: kBrandColor),
              const SizedBox(width: 8),
              const Text(
                'DATI TECNICI',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kBrandColor,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.speed,
                  label: 'Velocità Max',
                  value: '${maxSpeedKmh.toStringAsFixed(0)} km/h',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.trending_up,
                  label: 'Velocità Media',
                  value: '${avgSpeedKmh.toStringAsFixed(0)} km/h',
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
                  value: '${maxGForce.toStringAsFixed(2)} g',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.gps_fixed,
                  label: 'GPS Accuracy',
                  value: '${avgGpsAccuracy.toStringAsFixed(1)} m',
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
                  value: '$gpsSampleRateHz Hz',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.data_usage,
                  label: 'Punti GPS',
                  value: gpsDataCount.toString(),
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

  const _TechnicalMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151520),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLineColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: kBrandColor.withOpacity(0.7)),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: kMutedColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kFgColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// OVERVIEW: CIRCUITO + GRAFICO COMBINATO (from activity_detail_page)
// ============================================================

enum _MetricFocus { speed, gForce, accuracy }

class _SessionOverviewPanel extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<LatLng> smoothPath;
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
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(16),
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
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(16),
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

    final List<LatLng> lapPath = indices
        .where((i) => i < widget.smoothPath.length)
        .map((i) => widget.smoothPath[i])
        .toList();

    LatLng? marker;
    if (globalIdx < widget.gpsTrack.length) {
      final p = widget.gpsTrack[globalIdx];
      marker = LatLng(p.latitude, p.longitude);
    }

    final double curSpeed = widget.speedHistory[globalIdx];
    final double curG = widget.gForceHistory[globalIdx];
    final double curAcc = widget.gpsAccuracyHistory[globalIdx];
    final double curT = xs[_selectedIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF050608),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                color: Colors.white70,
                onPressed: _currentLap > 0
                    ? () {
                        setState(() {
                          _currentLap--;
                          _selectedIndex = 0;
                        });
                      }
                    : null,
              ),
              Column(
                children: [
                  Text(
                    'LAP ${(_currentLap + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _formatLap(widget.laps[_currentLap]),
                    style: const TextStyle(
                      fontSize: 12,
                      color: kMutedColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                color: Colors.white70,
                onPressed: _currentLap < lapCount - 1
                    ? () {
                        setState(() {
                          _currentLap++;
                          _selectedIndex = 0;
                        });
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CircuitTrackView(
            path: lapPath,
            marker: marker,
          ),
          const SizedBox(height: 16),
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
                    color: kLineColor.withOpacity(0.35),
                    strokeWidth: 0.5,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.25),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(
                        color: kLineColor.withOpacity(0.7), width: 1),
                    bottom: BorderSide(
                        color: kLineColor.withOpacity(0.7), width: 1),
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
                            const TextStyle(color: kMutedColor, fontSize: 10),
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
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: cursorX,
                      color: Colors.white.withOpacity(0.7),
                      strokeWidth: 1,
                      dashArray: [4, 4],
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
                  _buildLine(speedSpots, Colors.redAccent,
                      _focus == _MetricFocus.speed),
                  _buildLine(gSpots, Colors.greenAccent,
                      _focus == _MetricFocus.gForce),
                  _buildLine(accSpots, Colors.blueAccent,
                      _focus == _MetricFocus.accuracy),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metricChip(
                label: 'Speed',
                color: Colors.redAccent,
                selected: _focus == _MetricFocus.speed,
                onTap: () => setState(() => _focus = _MetricFocus.speed),
              ),
              _metricChip(
                label: 'G-Force',
                color: Colors.greenAccent,
                selected: _focus == _MetricFocus.gForce,
                onTap: () => setState(() => _focus = _MetricFocus.gForce),
              ),
              _metricChip(
                label: 'Accuracy',
                color: Colors.blueAccent,
                selected: _focus == _MetricFocus.accuracy,
                onTap: () => setState(() => _focus = _MetricFocus.accuracy),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              't=${curT.toStringAsFixed(2)}s   '
              'v=${curSpeed.toStringAsFixed(1)} km/h   '
              'g=${curG.toStringAsFixed(2)}   '
              'acc=${curAcc.toStringAsFixed(2)} m',
              style: const TextStyle(
                fontSize: 11,
                color: kMutedColor,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
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
      color: focused ? baseColor : baseColor.withOpacity(0.25),
      barWidth: focused ? 2.5 : 1.5,
      isStrokeCapRound: false,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.4),
            width: 1,
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
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
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
  final List<LatLng> path;
  final LatLng? marker;

  const _CircuitTrackView({
    required this.path,
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
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
        painter: _CircuitPainter(path: path, marker: marker),
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  final List<LatLng> path;
  final LatLng? marker;

  _CircuitPainter({
    required this.path,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFF101015)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
      bgPaint,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    const int gridLines = 8;
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

    final usableW = size.width * 0.8;
    final usableH = size.height * 0.8;
    final scale = (dLat == 0 || dLon == 0)
        ? 1.0
        : math.min(usableW / dLon, usableH / dLat);

    Offset _project(LatLng p) {
      final x = (p.longitude - centerLon) * scale + size.width / 2;
      final y = (centerLat - p.latitude) * scale + size.height / 2;
      return Offset(x, y);
    }

    final ui.Path shadowPath = ui.Path();
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      if (i == 0) {
        shadowPath.moveTo(o.dx, o.dy);
      } else {
        shadowPath.lineTo(o.dx, o.dy);
      }
    }
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(shadowPath.shift(const Offset(2, 2)), shadowPaint);

    final ui.Path trackPath = ui.Path();
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      if (i == 0) {
        trackPath.moveTo(o.dx, o.dy);
      } else {
        trackPath.lineTo(o.dx, o.dy);
      }
    }
    final trackPaint = Paint()
      ..color = kBrandColor.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(trackPath, trackPaint);

    if (marker != null) {
      final o = _project(marker!);
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final markerBorder = Paint()
        ..color = kPulseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(o, 7, markerPaint);
      canvas.drawCircle(o, 7, markerBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.marker != marker;
  }
}
