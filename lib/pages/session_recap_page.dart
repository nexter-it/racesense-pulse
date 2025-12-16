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
import '../models/track_definition.dart';

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
  final TrackDefinition? trackDefinition;
  final bool usedBleDevice;

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
    this.trackDefinition,
    this.usedBleDevice = false,
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
    return gForceHistory.map((g) => g.abs()).reduce(math.max);
  }

  double _getAvgGpsAccuracy() {
    if (gpsAccuracyHistory.isEmpty) return 0;
    return gpsAccuracyHistory.reduce((a, b) => a + b) /
        gpsAccuracyHistory.length;
  }

  int _getGpsSampleRate() {
    if (timeHistory.length < 2) return 0;

    int totalIntervals = 0;
    int sumMs = 0;

    for (int i = 1; i < timeHistory.length; i++) {
      final diff =
          timeHistory[i].inMilliseconds - timeHistory[i - 1].inMilliseconds;
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

    // Mostra loading con progress
    if (!context.mounted) return;
    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, progress, _) => Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kLineColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_upload, color: kBrandColor, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Caricamento sessione',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: kLineColor,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(kBrandColor),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                  ),
                ),
              ],
            ),
          ),
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
        driverFullName: user.displayName ?? user.email ?? 'Pilota',
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
        trackDefinition: trackDefinition,
        usedBleDevice: usedBleDevice,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
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
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
          children: [
            const SizedBox(height: 8),
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
                        trackDefinition: trackDefinition,
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
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            kBrandColor.withAlpha(255),
                            kBrandColor.withAlpha(200),
                          ],
                        ),
                        border: Border.all(color: kBrandColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: kBrandColor.withAlpha(100),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _handleSaveSession(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.save, color: Colors.black, size: 22),
                                SizedBox(width: 10),
                                Text(
                                  'SALVA SESSIONE',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Riepilogo Sessione',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Sessione completata',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    final bestLapStr = bestLap != null ? _formatDuration(bestLap!) : '--:--';
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
                value: "${distance.toStringAsFixed(1)} km",
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
                value: lapCount.toString(),
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
  final DateTime dateTime;

  const _SessionInfoCard({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    final timeStr =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

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
                child: const Icon(Icons.info_outline,
                    size: 16, color: kBrandColor),
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
                  child:
                      const Icon(Icons.list_alt, size: 16, color: kBrandColor),
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
  final List<LatLng> path;
  final String trackName;
  final TrackDefinition? trackDefinition;

  const _MapSection({
    required this.path,
    required this.trackName,
    this.trackDefinition,
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
                  child: const Icon(Icons.map_outlined,
                      size: 16, color: kBrandColor),
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
                  initialCenter: LatLng(centerLat, centerLon),
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
                  // Circuit track with width (premium rendering)
                  if (trackDefinition?.trackPath != null &&
                      trackDefinition!.trackPath!.isNotEmpty)
                    ..._buildCircuitLayers(trackDefinition!),
                  // User session path (fluo brand color on top)
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

  /// Calcola i bordi del circuito (interno ed esterno) basandosi sulla linea centrale
  List<Widget> _buildCircuitLayers(TrackDefinition track) {
    if (track.trackPath == null || track.trackPath!.isEmpty) {
      return [];
    }

    final centerLine = track.trackPath!;
    final width = track.widthMeters ?? 10.0; // Default 10m se non specificato
    final halfWidth = width / 2;

    // Calcola i bordi usando normali perpendicolari
    final List<LatLng> innerBorder = [];
    final List<LatLng> outerBorder = [];

    for (int i = 0; i < centerLine.length; i++) {
      final current = centerLine[i];

      // Calcola la direzione della tangente
      LatLng tangent;
      if (i == 0) {
        // Primo punto: usa direzione verso il prossimo
        tangent = _subtractLatLng(centerLine[i + 1], current);
      } else if (i == centerLine.length - 1) {
        // Ultimo punto: usa direzione dal precedente
        tangent = _subtractLatLng(current, centerLine[i - 1]);
      } else {
        // Punto intermedio: media delle direzioni
        final prev = _subtractLatLng(current, centerLine[i - 1]);
        final next = _subtractLatLng(centerLine[i + 1], current);
        tangent = LatLng(
          (prev.latitude + next.latitude) / 2,
          (prev.longitude + next.longitude) / 2,
        );
      }

      // Normalizza la tangente
      final tangentLen = math.sqrt(
        tangent.latitude * tangent.latitude +
            tangent.longitude * tangent.longitude,
      );
      if (tangentLen < 1e-10) continue;

      final tangentNorm = LatLng(
        tangent.latitude / tangentLen,
        tangent.longitude / tangentLen,
      );

      // Calcola la normale (perpendicolare, ruotata di 90°)
      final normal = LatLng(-tangentNorm.longitude, tangentNorm.latitude);

      // Converti halfWidth da metri a gradi (approssimazione)
      // 1 grado di latitudine ≈ 111km
      final halfWidthDegrees = halfWidth / 111000.0;

      // Calcola i punti dei bordi
      innerBorder.add(LatLng(
        current.latitude - normal.latitude * halfWidthDegrees,
        current.longitude - normal.longitude * halfWidthDegrees,
      ));
      outerBorder.add(LatLng(
        current.latitude + normal.latitude * halfWidthDegrees,
        current.longitude + normal.longitude * halfWidthDegrees,
      ));
    }

    return [
      // Poligono del circuito (area tra bordo interno ed esterno)
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
      // Bordo interno (più scuro)
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
      // Bordo esterno (più scuro)
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
      // Linea centrale (opzionale, sottile e tratteggiata visivamente)
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

  /// Helper per sottrarre coordinate LatLng
  LatLng _subtractLatLng(LatLng a, LatLng b) {
    return LatLng(a.latitude - b.latitude, a.longitude - b.longitude);
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
                  value: '${maxSpeedKmh.toStringAsFixed(0)} km/h',
                  color: kPulseColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.trending_up,
                  label: 'Velocità Media',
                  value: '${avgSpeedKmh.toStringAsFixed(0)} km/h',
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
                  value: '${maxGForce.toStringAsFixed(2)} g',
                  color: kCoachColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.gps_fixed,
                  label: 'GPS Accuracy',
                  value: '${avgGpsAccuracy.toStringAsFixed(1)} m',
                  color: const Color(0xFF4CD964),
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
                  color: const Color(0xFF5AC8FA),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechnicalMetric(
                  icon: Icons.data_usage,
                  label: 'Punti GPS',
                  value: gpsDataCount.toString(),
                  color: const Color(0xFFFF9F0A),
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

// ============================================================
// OVERVIEW: CIRCUITO + GRAFICO COMBINATO
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
                        style: const TextStyle(
                            color: kMutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toStringAsFixed(0)}s',
                        style: const TextStyle(
                            color: kMutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
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
                Container(
                    width: 1, height: 30, color: kLineColor.withAlpha(80)),
                _metricValue('v', '${curSpeed.toStringAsFixed(1)} km/h',
                    const Color(0xFFFF4D4F)),
                Container(
                    width: 1, height: 30, color: kLineColor.withAlpha(80)),
                _metricValue(
                    'g', '${curG.toStringAsFixed(2)}', const Color(0xFF4CD964)),
                Container(
                    width: 1, height: 30, color: kLineColor.withAlpha(80)),
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
  final List<LatLng> path;
  final LatLng? marker;
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
  final List<LatLng> path;
  final LatLng? marker;
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

    Offset project(LatLng p) {
      final x = (p.longitude - centerLon) * scale + size.width / 2;
      final y = (centerLat - p.latitude) * scale + size.height / 2;
      return Offset(x, y);
    }

    final ui.Path shadowPath = ui.Path();
    final List<Offset> projected = [];
    for (int i = 0; i < path.length; i++) {
      final o = project(path[i]);
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
      final o = project(marker!);
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
