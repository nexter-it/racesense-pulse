import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme.dart';
import '../services/grand_prix_service.dart';
import '../models/grand_prix_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class GrandPrixStatisticsPage extends StatefulWidget {
  final String lobbyCode;

  const GrandPrixStatisticsPage({super.key, required this.lobbyCode});

  @override
  State<GrandPrixStatisticsPage> createState() =>
      _GrandPrixStatisticsPageState();
}

class _GrandPrixStatisticsPageState extends State<GrandPrixStatisticsPage>
    with SingleTickerProviderStateMixin {
  final _grandPrixService = GrandPrixService();

  GrandPrixLobby? _lobby;
  Map<String, GrandPrixLiveData> _liveData = {};
  List<GrandPrixStatistics> _statistics = [];
  List<CloseBattle> _battles = [];
  bool _loading = true;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _loadStatistics();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadStatistics() async {
    setState(() => _loading = true);

    // Get lobby data
    final lobbyData = await _grandPrixService.getLobbyData(widget.lobbyCode);
    if (lobbyData == null) {
      Navigator.of(context).pop();
      return;
    }

    final lobby = GrandPrixLobby.fromMap(widget.lobbyCode, lobbyData);

    // Get live data
    final liveDataSnapshot =
        await FirebaseDatabase.instance.ref('grand_prix_lobbies/${widget.lobbyCode}/liveData').get();

    final Map<String, GrandPrixLiveData> liveDataMap = {};
    if (liveDataSnapshot.exists) {
      final data = liveDataSnapshot.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        liveDataMap[key.toString()] =
            GrandPrixLiveData.fromMap(key.toString(), value);
      });
    }

    // Calculate statistics for each participant
    final List<GrandPrixStatistics> stats = [];
    lobby.participants.forEach((userId, participant) {
      final liveData = liveDataMap[userId];
      if (liveData != null) {
        stats.add(GrandPrixStatistics.fromLiveData(
          userId,
          participant.username,
          liveData,
        ));
      }
    });

    // Sort by best lap time
    stats.sort((a, b) {
      if (a.bestLap == null) return 1;
      if (b.bestLap == null) return -1;
      return a.bestLap!.compareTo(b.bestLap!);
    });

    // Find close battles (lap times within 0.5 seconds)
    final battles = _findCloseBattles(stats);

    if (mounted) {
      setState(() {
        _lobby = lobby;
        _liveData = liveDataMap;
        _statistics = stats;
        _battles = battles;
        _loading = false;
      });
    }
  }

  List<CloseBattle> _findCloseBattles(List<GrandPrixStatistics> stats) {
    final List<CloseBattle> battles = [];

    // Compare lap times between all drivers
    for (int i = 0; i < stats.length; i++) {
      for (int j = i + 1; j < stats.length; j++) {
        final driver1 = stats[i];
        final driver2 = stats[j];

        // Compare each lap
        final maxLaps = driver1.lapTimes.length < driver2.lapTimes.length
            ? driver1.lapTimes.length
            : driver2.lapTimes.length;

        for (int lap = 0; lap < maxLaps; lap++) {
          final time1 = driver1.lapTimes[lap];
          final time2 = driver2.lapTimes[lap];
          final diff = (time1 - time2).abs();

          // Battle if within 0.5 seconds
          if (diff < 0.5 && diff > 0) {
            battles.add(CloseBattle(
              driver1Username: driver1.username,
              driver2Username: driver2.username,
              driver1Time: time1,
              driver2Time: time2,
              difference: diff,
              lapNumber: lap + 1,
            ));
          }
        }
      }
    }

    // Sort by closest battles
    battles.sort((a, b) => a.difference.compareTo(b.difference));

    return battles.take(5).toList(); // Top 5 closest battles
  }

  String _formatLapTime(double seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          _buildPodium(),
                          const SizedBox(height: 24),
                          _buildFullLeaderboard(),
                          const SizedBox(height: 24),
                          _buildAwards(),
                          const SizedBox(height: 24),
                          if (_battles.isNotEmpty) _buildCloseBattles(),
                          if (_battles.isNotEmpty) const SizedBox(height: 32),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_kCardStart, _kBgColor],
            ),
            boxShadow: [
              BoxShadow(
                color: kBrandColor.withOpacity(_glowAnimation.value * 0.15),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kTileColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderColor, width: 1),
                  ),
                  child: const Icon(Icons.close, color: kFgColor, size: 22),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Risultati Finali',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: kFgColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gran Premio',
                      style: TextStyle(
                        fontSize: 13,
                        color: kMutedColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kBrandColor, kBrandColor.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.emoji_events, color: Colors.black, size: 22),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPodium() {
    if (_statistics.isEmpty) return const SizedBox.shrink();

    final top3 = _statistics.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kBrandColor.withOpacity(0.15),
            kBrandColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBrandColor.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (top3.length > 1) _buildPodiumPlace(top3[1], 2, 140, Colors.grey),
          if (top3.isNotEmpty) _buildPodiumPlace(top3[0], 1, 180, kBrandColor),
          if (top3.length > 2) _buildPodiumPlace(top3[2], 3, 120, Colors.brown),
        ],
      ),
    );
  }

  Widget _buildPodiumPlace(
      GrandPrixStatistics stats, int position, double height, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withOpacity(0.7)],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              stats.username.substring(0, 2).toUpperCase(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          stats.username,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: kFgColor,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        if (stats.bestLap != null)
          Text(
            _formatLapTime(stats.bestLap!),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        const SizedBox(height: 12),
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withOpacity(0.6), color.withOpacity(0.3)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: color.withOpacity(0.5), width: 2),
          ),
          child: Center(
            child: Text(
              '$position',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullLeaderboard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.leaderboard,
                  color: kBrandColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Classifica Finale',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kFgColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._statistics.asMap().entries.map((entry) {
            final index = entry.key;
            final stats = entry.value;
            return _buildLeaderboardRow(index + 1, stats);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(int position, GrandPrixStatistics stats) {
    Color positionColor = kMutedColor;
    if (position == 1) positionColor = kBrandColor;
    if (position == 2) positionColor = Colors.grey;
    if (position == 3) positionColor = Colors.brown;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: position <= 3
              ? positionColor.withOpacity(0.3)
              : _kBorderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: positionColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$position',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: positionColor,
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
                  stats.username,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kFgColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stats.totalLaps} giri',
                  style: TextStyle(
                    fontSize: 11,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (stats.bestLap != null)
            Text(
              _formatLapTime(stats.bestLap!),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: positionColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAwards() {
    if (_statistics.isEmpty) return const SizedBox.shrink();

    // Find award winners
    final mostConsistent = _statistics.reduce(
        (a, b) => a.consistency > b.consistency ? a : b);
    final bestProgression = _statistics.reduce(
        (a, b) => a.progression > b.progression ? a : b);
    final fastestSpeed = _statistics.reduce(
        (a, b) => a.maxSpeed > b.maxSpeed ? a : b);
    final highestGForce = _statistics.reduce(
        (a, b) => a.maxGForce > b.maxGForce ? a : b);
    final slowestLap = _statistics.where((s) => s.slowestLap != null).reduce(
        (a, b) => a.slowestLap! > b.slowestLap! ? a : b);
    final mostLaps = _statistics.reduce(
        (a, b) => a.totalLaps > b.totalLaps ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAwardCard(
          'Pilota Più Costante',
          mostConsistent.username,
          Icons.trending_flat,
          Colors.blue,
          '',
        ),
        const SizedBox(height: 12),
        _buildAwardCard(
          'Miglior Progressione',
          bestProgression.username,
          Icons.trending_up,
          Colors.green,
          bestProgression.progression > 0
              ? '-${bestProgression.progression.toStringAsFixed(3)}s'
              : '',
        ),
        const SizedBox(height: 12),
        _buildAwardCard(
          'Velocità Massima',
          fastestSpeed.username,
          Icons.speed,
          Colors.orange,
          '${fastestSpeed.maxSpeed.toStringAsFixed(1)} km/h',
        ),
        const SizedBox(height: 12),
        _buildAwardCard(
          'G-Force Massima',
          highestGForce.username,
          Icons.adjust,
          Colors.red,
          '${highestGForce.maxGForce.toStringAsFixed(2)}g',
        ),
        const SizedBox(height: 12),
        _buildAwardCard(
          'Giro Più Lento',
          slowestLap.username,
          Icons.slow_motion_video,
          Colors.grey,
          slowestLap.slowestLap != null
              ? _formatLapTime(slowestLap.slowestLap!)
              : '',
        ),
        const SizedBox(height: 12),
        _buildAwardCard(
          'Numero Giri Completati',
          mostLaps.username,
          Icons.loop,
          Colors.purple,
          '${mostLaps.totalLaps} giri',
        ),
      ],
    );
  }

  Widget _buildAwardCard(
      String title, String winner, IconData icon, Color color, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  winner,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCloseBattles() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.compare_arrows,
                  color: kBrandColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Lotte Ravvicinate',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kFgColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._battles.map((battle) => _buildBattleRow(battle)).toList(),
        ],
      ),
    );
  }

  Widget _buildBattleRow(CloseBattle battle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBrandColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'GIRO ${battle.lapNumber}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Δ ${battle.difference.toStringAsFixed(3)}s',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kBrandColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      battle.driver1Username,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kFgColor,
                      ),
                    ),
                    Text(
                      _formatLapTime(battle.driver1Time),
                      style: TextStyle(
                        fontSize: 11,
                        color: kMutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.compare_arrows,
                color: kMutedColor,
                size: 18,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      battle.driver2Username,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kFgColor,
                      ),
                    ),
                    Text(
                      _formatLapTime(battle.driver2Time),
                      style: TextStyle(
                        fontSize: 11,
                        color: kMutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
