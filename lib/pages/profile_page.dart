import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../models/session_model.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final SessionService _sessionService = SessionService();

  String _userName = '';
  String _userTag = '';
  bool _isLoading = true;

  UserStats _userStats = UserStats.empty();
  List<SessionModel> _recentSessions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ricarica dati quando l'app torna in primo piano
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ ProfilePage: Nessun utente loggato');
      return;
    }

    print('🔄 ProfilePage: Caricamento dati per ${user.uid}');

    try {
      // Inizializza stats se non esistono (ora senza read extra)
      await _firestoreService.initializeStatsIfNeeded(user.uid);

      // 1) dati utente (con cache locale) + 2) ultime sessioni
      final results = await Future.wait([
        _firestoreService.getUserDataWithCache(user.uid),
        _sessionService.getUserSessions(user.uid, limit: 5),
      ]);

      final userData = results[0] as Map<String, dynamic>?;
      final sessions = results[1] as List<SessionModel>;

      // Stats direttamente dal doc utente
      final stats = (userData != null && userData['stats'] != null)
          ? UserStats.fromMap(userData['stats'] as Map<String, dynamic>)
          : UserStats.empty();

      print(
          '✅ ProfilePage: Dati caricati - Stats: ${stats.totalSessions} sessioni, Sessioni: ${sessions.length}');

      if (mounted) {
        final fullName = userData?['fullName'] ?? user.displayName ?? 'Utente';

        // Crea tag dalle iniziali del nome
        String tag;
        final nameParts = fullName.split(' ');
        if (nameParts.length >= 2) {
          tag = nameParts[0][0].toUpperCase() + nameParts[1][0].toUpperCase();
        } else if (nameParts.isNotEmpty && nameParts[0].length >= 2) {
          tag = nameParts[0].substring(0, 2).toUpperCase();
        } else {
          tag = 'US';
        }

        setState(() {
          _userName = fullName;
          _userTag = tag;
          _userStats = stats;
          _recentSessions = sessions;
          _isLoading = false;
        });
        print('✅ ProfilePage: UI aggiornata');
      }
    } catch (e) {
      print('❌ ProfilePage: Errore caricamento dati - $e');
      // In caso di errore, usa i dati di Firebase Auth
      if (mounted) {
        final user = FirebaseAuth.instance.currentUser;
        setState(() {
          _userName = user?.displayName ?? 'Utente';
          _userTag = _userName.length >= 2
              ? _userName.substring(0, 2).toUpperCase()
              : 'US';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ---------- HEADER ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Row(
              children: [
                const Text(
                  'Profilo',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.logout, size: 26),
                  onPressed: () async {
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF1a1a1a),
                        title: const Text('Logout',
                            style: TextStyle(color: kFgColor)),
                        content: const Text(
                          'Sei sicuro di voler uscire?',
                          style: TextStyle(color: kMutedColor),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Annulla',
                                style: TextStyle(color: kMutedColor)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Logout',
                                style: TextStyle(color: kErrorColor)),
                          ),
                        ],
                      ),
                    );

                    if (shouldLogout == true) {
                      final authService = AuthService();
                      await authService.signOut();
                    }
                  },
                )
              ],
            ),
          ),

          // ---------- BODY ----------
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadUserData,
                    color: kBrandColor,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      children: [
                        _ProfileHeader(name: _userName, tag: _userTag),
                        const SizedBox(height: 18),
                        _ProfileStats(stats: _userStats),
                        const SizedBox(height: 18),
                        _ProfileHighlights(stats: _userStats),
                        const SizedBox(height: 26),
                        const Text(
                          'Ultime attività',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_recentSessions.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'Nessuna sessione registrata',
                                style: TextStyle(color: kMutedColor),
                              ),
                            ),
                          )
                        else
                          ..._recentSessions
                              .map((session) => _SessionCard(session: session)),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
    HEADER PROFILO
============================================================ */

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String tag;

  const _ProfileHeader({
    required this.name,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color.fromRGBO(255, 255, 255, 0.10),
        border: Border.all(color: kLineColor, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar tag
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.35),
              border: Border.all(color: kBrandColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: kBrandColor.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '@$tag',
                  style: const TextStyle(
                    color: kMutedColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),

                // Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: const [
                    PulseChip(
                      label: Text('RACESENSE LIVE'),
                      icon: Icons.bluetooth_connected,
                    ),
                    PulseChip(
                      label: Text('Accesso PULSE+'),
                      icon: Icons.bolt,
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

/* ============================================================
    STATISTICHE PROFILO
============================================================ */

class _ProfileStats extends StatelessWidget {
  final UserStats stats;

  const _ProfileStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        children: [
          _ProfileStatItem(
            label: 'Sessioni',
            value: '${stats.totalSessions}',
          ),
          const SizedBox(width: 14),
          _ProfileStatItem(
            label: 'Distanza totale',
            value: '${stats.totalDistanceKm.toStringAsFixed(0)} km',
          ),
          const SizedBox(width: 14),
          _ProfileStatItem(
            label: 'PB circuiti',
            value: '${stats.personalBests}',
          ),
        ],
      ),
    );
  }
}

class _ProfileStatItem extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: kMutedColor,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
    HIGHLIGHTS
============================================================ */

class _ProfileHighlights extends StatelessWidget {
  final UserStats stats;

  const _ProfileHighlights({required this.stats});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bestLapText = stats.bestLapEver != null
        ? '${_formatDuration(stats.bestLapEver!)}${stats.bestLapTrack != null ? ' · ${stats.bestLapTrack}' : ''}'
        : 'Nessun record';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color.fromRGBO(255, 255, 255, 0.07),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Highlights',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _HighlightRow(
            icon: Icons.emoji_events_outlined,
            label: 'Best lap assoluto',
            value: bestLapText,
          ),
          const SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.flag_outlined,
            label: 'Giri totali',
            value: '${stats.totalLaps} giri',
          ),
          const SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.insights_outlined,
            label: 'Distanza media',
            value: stats.totalSessions > 0
                ? '${(stats.totalDistanceKm / stats.totalSessions).toStringAsFixed(1)} km/sessione'
                : '0 km',
          ),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HighlightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kBrandColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: kMutedColor),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
    CARD SESSIONE
============================================================ */

class _SessionCard extends StatelessWidget {
  final SessionModel session;

  const _SessionCard({
    super.key,
    required this.session,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Oggi';
    if (diff.inDays == 1) return 'Ieri';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';

    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bestLapText = session.bestLap != null
        ? 'Best ${_formatDuration(session.bestLap!)}'
        : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushNamed(
          '/activity',
          arguments: session,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color.fromRGBO(255, 255, 255, 0.06),
          border: Border.all(color: kLineColor),
        ),
        child: Row(
        children: [
          // Icona attività
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBrandColor.withOpacity(0.18),
            ),
            child:
                const Icon(Icons.track_changes, color: kBrandColor, size: 22),
          ),
          const SizedBox(width: 12),

          // Info sessione
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.trackName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.lapCount} giri · ${session.distanceKm.toStringAsFixed(1)} km${bestLapText.isNotEmpty ? ' · $bestLapText' : ''}',
                  style: const TextStyle(fontSize: 12, color: kMutedColor),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      session.isPublic ? Icons.public : Icons.lock_outline,
                      size: 12,
                      color: kMutedColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(session.dateTime),
                      style: TextStyle(
                          fontSize: 11, color: kMutedColor.withOpacity(0.7)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Velocità max
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${session.maxSpeedKmh.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                ),
              ),
              const Text(
                'km/h',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kMutedColor,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
