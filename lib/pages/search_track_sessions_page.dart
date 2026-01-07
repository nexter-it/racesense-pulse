import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/session_model.dart';
import '../services/session_service.dart';
import '../theme.dart';
import '../widgets/profile_avatar.dart';
import 'activity_detail_page.dart';
import 'search_user_profile_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = false;
  List<SessionModel> _sessions = [];

  // Cache per le immagini profilo degli utenti
  final Map<String, String?> _userProfileImages = {};
  bool _loadingProfiles = false;

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
        // Sort by best lap time
        data.sort((a, b) {
          if (a.bestLap == null && b.bestLap == null) return 0;
          if (a.bestLap == null) return 1;
          if (b.bestLap == null) return -1;
          return a.bestLap!.compareTo(b.bestLap!);
        });
        setState(() {
          _sessions = data;
        });
        // Carica le foto profilo in background
        _loadUserProfileImages(data);
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

  /// Carica le immagini profilo degli utenti in batch (una sola query)
  Future<void> _loadUserProfileImages(List<SessionModel> sessions) async {
    if (_loadingProfiles) return;

    // Raccogli tutti gli userId unici che non sono già in cache
    final userIds = sessions
        .map((s) => s.userId)
        .where((id) => id.isNotEmpty && !_userProfileImages.containsKey(id))
        .toSet()
        .toList();

    if (userIds.isEmpty) return;

    setState(() => _loadingProfiles = true);

    try {
      // Firebase supporta max 30 elementi per query whereIn
      // Facciamo batch se necessario
      const batchSize = 30;
      for (int i = 0; i < userIds.length; i += batchSize) {
        final batchIds = userIds.skip(i).take(batchSize).toList();

        final snap = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          _userProfileImages[doc.id] = data['profileImageUrl'] as String?;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Errore caricamento foto profilo: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  String _formatLap(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
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
              child: _loading && _sessions.isEmpty
                  ? _buildLoadingState()
                  : RefreshIndicator(
                      onRefresh: _loadSessions,
                      color: kBrandColor,
                      backgroundColor: _kCardStart,
                      child: _sessions.isEmpty
                          ? _buildEmptyState()
                          : _buildSessionsList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
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
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: const Icon(Icons.arrow_back, color: kBrandColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          // Track icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(40),
                  kPulseColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kPulseColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.flag_rounded, color: kPulseColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title and count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.trackName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kBrandColor.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.leaderboard, size: 11, color: kBrandColor),
                      const SizedBox(width: 4),
                      Text(
                        '${_sessions.length} ${_sessions.length == 1 ? 'sessione' : 'sessioni'}',
                        style: TextStyle(
                          fontSize: 10,
                          color: kBrandColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(kBrandColor),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Caricamento classifica...',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      kMutedColor.withAlpha(30),
                      kMutedColor.withAlpha(10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kCardStart,
                    border: Border.all(color: kMutedColor.withAlpha(60), width: 2),
                  ),
                  child: Icon(Icons.sports_score, color: kMutedColor, size: 26),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nessuna sessione trovata',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Non ci sono ancora sessioni pubbliche\nper questo circuito',
                style: TextStyle(
                  fontSize: 13,
                  color: kMutedColor,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSessionsList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _sessions.length + 1, // +1 for header card
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildLeaderboardHeader();
        }
        final session = _sessions[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildSessionCard(session, index - 1),
        );
      },
    );
  }

  Widget _buildLeaderboardHeader() {
    if (_sessions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
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
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFFD700).withAlpha(40),
                        const Color(0xFFFFD700).withAlpha(20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFFFFD700).withAlpha(60), width: 1.5),
                  ),
                  child: Center(
                    child: Icon(Icons.emoji_events, color: const Color(0xFFFFD700), size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Classifica Circuito',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: kFgColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: kPulseColor.withAlpha(20),
                    border: Border.all(color: kPulseColor.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 12, color: kPulseColor),
                      const SizedBox(width: 4),
                      Text(
                        'Best Lap',
                        style: TextStyle(
                          fontSize: 10,
                          color: kPulseColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Top 3 podium
            if (_sessions.length >= 1)
              _buildPodiumSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPodiumSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 2nd place
        if (_sessions.length >= 2)
          Expanded(
            child: _buildPodiumItem(
              session: _sessions[1],
              position: 2,
              color: const Color(0xFFC0C0C0), // Silver
              height: 70,
            ),
          )
        else
          const Expanded(child: SizedBox()),
        const SizedBox(width: 8),
        // 1st place
        Expanded(
          child: _buildPodiumItem(
            session: _sessions[0],
            position: 1,
            color: const Color(0xFFFFD700), // Gold
            height: 90,
          ),
        ),
        const SizedBox(width: 8),
        // 3rd place
        if (_sessions.length >= 3)
          Expanded(
            child: _buildPodiumItem(
              session: _sessions[2],
              position: 3,
              color: const Color(0xFFCD7F32), // Bronze
              height: 55,
            ),
          )
        else
          const Expanded(child: SizedBox()),
      ],
    );
  }

  Widget _buildPodiumItem({
    required SessionModel session,
    required int position,
    required Color color,
    required double height,
  }) {
    final userInitials = session.driverFullName.isNotEmpty
        ? session.driverFullName
            .split(' ')
            .map((e) => e.isNotEmpty ? e[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : '??';

    final profileImageUrl = _userProfileImages[session.userId];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ActivityDetailPage(),
            settings: RouteSettings(arguments: session),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar con foto profilo
          ProfileAvatar(
            profileImageUrl: profileImageUrl,
            userTag: userInitials,
            size: position == 1 ? 52 : 44,
            borderWidth: 2,
            showGradientBorder: true,
            gradientColors: [color.withAlpha(200), color.withAlpha(120)],
          ),
          const SizedBox(height: 8),
          // Name
          Text(
            session.driverFullName.split(' ').first,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kFgColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Time
          Text(
            session.bestLap != null ? _formatLap(session.bestLap!) : '--:--.--',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          // Podium block
          Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              gradient: LinearGradient(
                colors: [
                  color.withAlpha(40),
                  color.withAlpha(20),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Center(
              child: Text(
                '$position',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(SessionModel session, int index) {
    final bestLapStr =
        session.bestLap != null ? _formatLap(session.bestLap!) : '--:--.--';
    final formattedDate = DateFormat('dd MMM yyyy').format(session.dateTime);

    final userInitials = session.driverFullName.isNotEmpty
        ? session.driverFullName
            .split(' ')
            .map((e) => e.isNotEmpty ? e[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : '??';

    final profileImageUrl = _userProfileImages[session.userId];

    // Position colors for top 3
    Color positionColor;
    if (index == 0) {
      positionColor = const Color(0xFFFFD700); // Gold
    } else if (index == 1) {
      positionColor = const Color(0xFFC0C0C0); // Silver
    } else if (index == 2) {
      positionColor = const Color(0xFFCD7F32); // Bronze
    } else {
      positionColor = kMutedColor;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ActivityDetailPage(),
            settings: RouteSettings(arguments: session),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Position badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [
                      positionColor.withAlpha(40),
                      positionColor.withAlpha(20),
                    ],
                  ),
                  border: Border.all(color: positionColor.withAlpha(80)),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: positionColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Avatar con foto profilo
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchUserProfilePage(
                        userId: session.userId,
                        fullName: session.driverFullName,
                      ),
                    ),
                  );
                },
                child: ProfileAvatar(
                  profileImageUrl: profileImageUrl,
                  userTag: userInitials,
                  size: 44,
                  borderWidth: 2,
                  showGradientBorder: true,
                ),
              ),
              const SizedBox(width: 12),
              // Name and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.driverFullName.isNotEmpty
                          ? session.driverFullName
                          : 'Pilota Anonimo',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kFgColor,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildMiniStat(Icons.calendar_today, formattedDate, kMutedColor),
                        _buildMiniStat(Icons.loop, '${session.lapCount}', const Color(0xFF29B6F6)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Best lap time
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      kPulseColor.withAlpha(30),
                      kPulseColor.withAlpha(15),
                    ],
                  ),
                  border: Border.all(color: kPulseColor.withAlpha(60)),
                ),
                child: Column(
                  children: [
                    Text(
                      bestLapStr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: kPulseColor,
                      ),
                    ),
                    Text(
                      'Best Lap',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kPulseColor.withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withAlpha(15),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
