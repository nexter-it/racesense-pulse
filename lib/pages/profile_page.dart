import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/follow_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/session_service.dart';
import '../models/session_model.dart';
import '../widgets/follow_counts.dart';
import '../widgets/session_metadata_dialog.dart';
import 'story_composer_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final SessionService _sessionService = SessionService();
  final FollowService _followService = FollowService();

  String _userName = '';
  String _userTag = '';
  String _username = '';
  bool _isLoading = true;
  bool _sessionsLoadingAll = false;
  bool _showAllSessions = false;
  bool _hasAllSessions = false;
  int _followerCount = 0;
  int _followingCount = 0;

  UserStats _userStats = UserStats.empty();
  List<SessionModel> _recentSessions = [];
  List<Map<String, dynamic>> _followNotifs = [];
  List<SessionModel> _allSessions = [];
  bool _showNotifPanel = false;

  Future<void> _editSession(SessionModel session) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != session.userId) return;

    final metadata = await showDialog<SessionMetadata>(
      context: context,
      builder: (context) => SessionMetadataDialog(
        gpsTrack: const [],
        initialTrackName: session.trackName,
        initialLocationName: session.location,
        initialLocationCoords: session.locationCoords,
        initialIsPublic: session.isPublic,
      ),
    );

    if (metadata == null) return;

    try {
      await _sessionService.updateSessionMetadata(
        sessionId: session.sessionId,
        ownerId: user.uid,
        trackName: metadata.trackName,
        location: metadata.location,
        locationCoords: metadata.locationCoords,
        isPublic: metadata.isPublic,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessione aggiornata')),
        );
        _loadUserData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore aggiornamento: $e'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteSession(SessionModel session) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != session.userId) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title:
            const Text('Elimina sessione', style: TextStyle(color: kFgColor)),
        content: const Text(
          'Vuoi eliminare questa sessione? Questa azione non è reversibile.',
          style: TextStyle(color: kMutedColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla', style: TextStyle(color: kMutedColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina', style: TextStyle(color: kErrorColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _sessionService.deleteSession(
        sessionId: session.sessionId,
        ownerId: user.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessione eliminata')),
        );
        _loadUserData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore eliminazione: $e'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  }

  void _openStoryComposer(SessionModel session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryComposerPage(session: session),
      ),
    );
  }

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

      // 1) dati utente (fresh) + 2) ultime sessioni + 3) notifiche follow
      final results = await Future.wait([
        _firestoreService.getUserData(user.uid),
        _sessionService.getUserSessions(user.uid, limit: 5),
        _followService.fetchFollowNotifications(user.uid, limit: 20),
      ]);

      final userData = results[0] as Map<String, dynamic>?;
      final sessions = results[1] as List<SessionModel>;
      final notifs = results[2] as List<Map<String, dynamic>>;

      // Stats direttamente dal doc utente
      final stats = (userData != null && userData['stats'] != null)
          ? UserStats.fromMap(userData['stats'] as Map<String, dynamic>)
          : UserStats.empty();

      print(
          '✅ ProfilePage: Dati caricati - Stats: ${stats.totalSessions} sessioni, Sessioni: ${sessions.length}');

      if (mounted) {
        final fullName = userData?['fullName'] ?? user.displayName ?? 'Utente';
        if (userData == null || userData['searchTokens'] == null) {
          // Backfill token ricerca per utenti già esistenti
          _firestoreService.ensureSearchTokens(user.uid, fullName);
        }
        if (userData == null || userData['username'] == null) {
          _firestoreService.ensureUsernameForUser(user.uid, fullName);
        }

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
          _username = userData?['username'] as String? ??
              fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          _userStats = stats;
          _recentSessions = sessions;
          _followNotifs = notifs;
          _followerCount = stats.followerCount;
          _followingCount = stats.followingCount;
          _isLoading = false;
          _hasAllSessions = sessions.length < 5 ? true : false;
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

  Future<void> _loadAllSessions() async {
    if (_sessionsLoadingAll || _hasAllSessions) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _sessionsLoadingAll = true;
    });

    try {
      final sessions =
          await _sessionService.getUserSessions(user.uid, limit: 50);
      setState(() {
        _allSessions = sessions;
        _showAllSessions = true;
        _hasAllSessions = true;
      });
    } catch (e) {
      print('❌ Errore caricamento tutte le sessioni: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sessionsLoadingAll = false;
        });
      }
    }
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
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none, size: 24),
                      if (_followNotifs.isNotEmpty)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () {
                    setState(() {
                      _showNotifPanel = !_showNotifPanel;
                      if (_showNotifPanel) {
                        // mark as seen
                        _followNotifs = [];
                      }
                    });
                  },
                ),
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
          if (_showNotifPanel)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
                child: _FollowNotifications(notifs: _followNotifs),
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
                        _ProfileHeader(
                            name: _userName,
                            tag: _userTag,
                            username: _username),
                        const SizedBox(height: 10),
                        FollowCounts(
                          followerCount: _followerCount,
                          followingCount: _followingCount,
                        ),
                        const SizedBox(height: 14),
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
                        if ((_showAllSessions ? _allSessions : _recentSessions)
                            .isEmpty)
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
                          ...(_showAllSessions ? _allSessions : _recentSessions)
                              .map((session) => _SessionCard(
                                    session: session,
                                    onEdit: () => _editSession(session),
                                    onDelete: () => _deleteSession(session),
                                    onShare: () => _openStoryComposer(session),
                                  )),
                        const SizedBox(height: 10),
                        if (_allSessions.isNotEmpty || !_hasAllSessions)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _sessionsLoadingAll
                                  ? null
                                  : () {
                                      if (_showAllSessions &&
                                          _allSessions.isNotEmpty) {
                                        setState(() {
                                          _showAllSessions = false;
                                        });
                                      } else if (_allSessions.isNotEmpty) {
                                        setState(() {
                                          _showAllSessions = true;
                                        });
                                      } else {
                                        _loadAllSessions();
                                      }
                                    },
                              icon: _sessionsLoadingAll
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation(kBrandColor),
                                      ),
                                    )
                                  : Icon(_showAllSessions
                                      ? Icons.expand_less
                                      : Icons.expand_more),
                              label: Text(_showAllSessions
                                  ? 'Mostra meno'
                                  : 'Mostra tutte'),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: kBrandColor),
                              ),
                              onLongPress: null,
                            ),
                          ),
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
  final String username;

  const _ProfileHeader({
    required this.name,
    required this.tag,
    required this.username,
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
                  '@$username',
                  style: const TextStyle(
                    color: kMutedColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),

                // Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: const [
                    // PulseChip(
                    //   label: Text('RACESENSE LIVE'),
                    //   icon: Icons.bluetooth_connected,
                    // ),
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

class _FollowNotifications extends StatelessWidget {
  final List<Map<String, dynamic>> notifs;

  const _FollowNotifications({required this.notifs});

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    return '${diff.inDays}g fa';
  }

  @override
  Widget build(BuildContext context) {
    final hasNew = notifs.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color.fromRGBO(255, 255, 255, 0.04),
        border: Border.all(color: kLineColor.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none,
                      color: kFgColor, size: 22),
                  if (hasNew)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Text(
                'Nuovi follower',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                hasNew ? '${notifs.length} nuovi' : 'Nessuna notifica',
                style: const TextStyle(color: kMutedColor, fontSize: 12),
              ),
            ],
          ),
          if (hasNew) ...[
            const SizedBox(height: 10),
            ...notifs.take(5).map((n) {
              final followerName = n['followerName'] ?? 'Follower';
              final followerUsername = n['followerUsername'] ?? '';
              final ts = n['createdAt'];
              DateTime? t;
              if (ts is Timestamp) t = ts.toDate();
              final subtitle =
                  followerUsername.isNotEmpty ? '@$followerUsername' : '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.person_add_alt,
                        color: kBrandColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            followerName,
                            style: const TextStyle(
                              color: kFgColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: const TextStyle(
                                  color: kMutedColor, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    if (t != null)
                      Text(
                        _timeAgo(t),
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 11),
                      ),
                  ],
                ),
              );
            }).toList(),
          ],
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
    final distanceTotal = '${stats.totalDistanceKm.toStringAsFixed(0)} km';
    final sessionsTotal = '${stats.totalSessions} sessioni';
    final pbCount = '${stats.personalBests} circuiti';

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
            icon: Icons.flag_circle_outlined,
            label: 'Sessioni totali',
            value: sessionsTotal,
          ),
          const SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.timeline,
            label: 'Distanza totale',
            value: distanceTotal,
          ),
          const SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.emoji_events_outlined,
            label: 'PB circuiti',
            value: pbCount,
          ),
          const SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.flag_outlined,
            label: 'Giri totali',
            value: '${stats.totalLaps} giri',
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
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;

  const _SessionCard({
    super.key,
    required this.session,
    this.onEdit,
    this.onDelete,
    this.onShare,
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
            if (onShare != null || onEdit != null || onDelete != null) ...[
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'share') {
                    onShare?.call();
                  } else if (value == 'edit') {
                    onEdit?.call();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onShare != null)
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Condividi'),
                    ),
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Modifica'),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Elimina',
                        style: TextStyle(color: kErrorColor),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
