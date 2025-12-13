import 'package:flutter/material.dart';

import '../models/session_model.dart';
import '../services/session_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import 'activity_detail_page.dart';

class SearchTrackSessionsPage extends StatefulWidget {
  final String trackName;
  final List<SessionModel> preloaded;

  const SearchTrackSessionsPage({
    super.key,
    required this.trackName,
    this.preloaded = const [],
  });

  @override
  State<SearchTrackSessionsPage> createState() =>
      _SearchTrackSessionsPageState();
}

class _SearchTrackSessionsPageState extends State<SearchTrackSessionsPage> {
  final SessionService _sessionService = SessionService();

  bool _loading = false;
  List<SessionModel> _sessions = [];

  @override
  void initState() {
    super.initState();
    _sessions = widget.preloaded;
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
    });
    try {
      final data = await _sessionService.getPublicSessionsByTrack(
        widget.trackName,
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _sessions = data;
        });
      }
    } catch (_) {
      // silenzioso
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatLap(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return 'Oggi';
    } else if (diff.inDays == 1) {
      return 'Ieri';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} giorni fa';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
          children: [
            const SizedBox(height: 8),

            // ---------- HEADER ----------
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
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
                          child: Icon(Icons.arrow_back,
                              color: kBrandColor, size: 20),
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
                          widget.trackName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_sessions.length} ${_sessions.length == 1 ? 'sessione' : 'sessioni'}',
                          style: const TextStyle(
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
            ),

            // ---------- BODY ----------
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadSessions,
                color: kBrandColor,
                child: _loading && _sessions.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(kBrandColor),
                        ),
                      )
                    : _buildSessionsList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsList() {
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    kMutedColor.withAlpha(40),
                    kMutedColor.withAlpha(20),
                  ],
                ),
                border:
                    Border.all(color: kMutedColor.withAlpha(100), width: 1.5),
              ),
              child:
                  const Icon(Icons.sports_score, color: kMutedColor, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Nessuna sessione trovata',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kMutedColor,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Prova a cercare un altro circuito',
              style: TextStyle(
                fontSize: 13,
                color: kMutedColor,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _buildSessionCard(session, index);
      },
    );
  }

  Widget _buildSessionCard(SessionModel session, int index) {
    final bestLapStr =
        session.bestLap != null ? _formatLap(session.bestLap!) : '--:--.--';

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
            builder: (_) => const ActivityDetailPage(),
            settings: RouteSettings(arguments: session),
          ),
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A20).withAlpha(255),
              const Color(0xFF0F0F15).withAlpha(255),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kLineColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(140),
              blurRadius: 16,
              spreadRadius: -3,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header con utente
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                // gradient: LinearGradient(
                //   colors: [
                //     kBrandColor.withAlpha(10),
                //     Colors.transparent,
                //   ],
                // ),
              ),
              child: Row(
                children: [
                  // Avatar dell'utente
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
                      radius: 24,
                      backgroundColor: const Color(0xFF1A1A20),
                      child: Text(
                        userInitials,
                        style: const TextStyle(
                          color: kBrandColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Nome utente e data
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.driverFullName.isNotEmpty
                              ? session.driverFullName
                              : 'Pilota Anonimo',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: kFgColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 11, color: kMutedColor),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(session.dateTime.toLocal()),
                              style: const TextStyle(
                                fontSize: 12,
                                color: kMutedColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Badge posizione
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          kPulseColor.withAlpha(40),
                          kPulseColor.withAlpha(25),
                        ],
                      ),
                      border: Border.all(color: kPulseColor, width: 1.5),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: const TextStyle(
                        color: kPulseColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Stats section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color.fromRGBO(255, 255, 255, 0.03),
                  border: Border.all(color: kLineColor.withAlpha(100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      icon: Icons.straighten,
                      label: 'Distanza',
                      value: '${session.distanceKm.toStringAsFixed(1)} km',
                      color: kBrandColor,
                    ),
                    Container(width: 1, height: 50, color: kLineColor),
                    _buildStatColumn(
                      icon: Icons.timer,
                      label: 'Best Lap',
                      value: bestLapStr,
                      color: kPulseColor,
                    ),
                    Container(width: 1, height: 50, color: kLineColor),
                    _buildStatColumn(
                      icon: Icons.location_on,
                      label: 'Località',
                      value: session.location.length > 8
                          ? '${session.location.substring(0, 8)}...'
                          : session.location,
                      color: kCoachColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: kFgColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: kMutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
