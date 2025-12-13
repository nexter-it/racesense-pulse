import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../models/session_model.dart';
import '../widgets/follow_counts.dart';
import '../services/follow_service.dart';
import 'connect_devices_page.dart';

class SearchUserProfilePage extends StatefulWidget {
  final String userId;
  final String fullName;

  const SearchUserProfilePage({
    super.key,
    required this.userId,
    required this.fullName,
  });

  @override
  State<SearchUserProfilePage> createState() => _SearchUserProfilePageState();
}

class _SearchUserProfilePageState extends State<SearchUserProfilePage> {
  final FirestoreService _firestoreService = FirestoreService();
  final SessionService _sessionService = SessionService();
  final FollowService _followService = FollowService();

  String _userName = '';
  String _userTag = '';
  bool _isLoading = true;
  bool _error = false;

  UserStats _userStats = UserStats.empty();
  List<SessionModel> _publicSessions = [];
  List<SessionModel> _allPublicSessions = [];
  bool _showAllSessions = false;
  bool _sessionsLoadingAll = false;
  bool _hasAllSessions = false;
  int _followerCount = 0;
  int _followingCount = 0;
  String _username = '';
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadFollowState();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _error = false;
    });

    try {
      final results = await Future.wait([
        _firestoreService.getUserData(widget.userId),
        _sessionService.getUserSessions(
          widget.userId,
          limit: 5,
          onlyPublic: true,
        ),
      ]);

      final userData = results[0] as Map<String, dynamic>?;
      final sessions = results[1] as List<SessionModel>;

      final stats = (userData != null && userData['stats'] != null)
          ? UserStats.fromMap(userData['stats'] as Map<String, dynamic>)
          : UserStats.empty();

      if (mounted) {
        final fullName = userData?['fullName'] ?? widget.fullName;
        if (userData == null || userData['searchTokens'] == null) {
          _firestoreService.ensureSearchTokens(widget.userId, fullName);
        }
        if (userData == null || userData['username'] == null) {
          _firestoreService.ensureUsernameForUser(widget.userId, fullName);
        }

        String tag;
        final nameParts = fullName.split(' ');
        if (nameParts.length >= 2 &&
            nameParts[0].isNotEmpty &&
            nameParts[1].isNotEmpty) {
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
          _publicSessions = sessions;
          _isLoading = false;
          _hasAllSessions = sessions.length < 5;
          _showAllSessions = false;
          _allPublicSessions = [];
          _followerCount = stats.followerCount;
          _followingCount = stats.followingCount;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userName = widget.fullName;
          _userTag = widget.fullName.length >= 2
              ? widget.fullName.substring(0, 2).toUpperCase()
              : 'US';
          _error = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFollowState() async {
    final current = FirebaseAuth.instance.currentUser?.uid;
    if (current == null || current == widget.userId) return;
    final following = await _followService.isFollowing(widget.userId);
    if (mounted) {
      setState(() {
        _isFollowing = following;
      });
    }
  }

  Future<void> _loadAllPublicSessions() async {
    if (_sessionsLoadingAll || _hasAllSessions) return;
    setState(() {
      _sessionsLoadingAll = true;
    });
    try {
      final sessions = await _sessionService.getUserSessions(widget.userId,
          limit: 50, onlyPublic: true);
      if (mounted) {
        setState(() {
          _allPublicSessions = sessions;
          _showAllSessions = true;
          _hasAllSessions = true;
        });
      }
    } catch (_) {
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
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = currentUserId != null && currentUserId == widget.userId;

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
                    child: Text(
                      isMe ? 'Profilo' : _userName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMe)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kBrandColor),
                        color: kBrandColor.withAlpha(25),
                      ),
                      child: const Text(
                        'Tu',
                        style: TextStyle(
                          color: kBrandColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
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
                  : _error
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: kErrorColor.withAlpha(20),
                                    border: Border.all(
                                        color: kErrorColor, width: 2),
                                  ),
                                  child: const Icon(Icons.error_outline,
                                      color: kErrorColor, size: 48),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Errore nel caricamento profilo.',
                                  style: TextStyle(
                                      color: kErrorColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [
                                        kBrandColor.withAlpha(40),
                                        kBrandColor.withAlpha(25),
                                      ],
                                    ),
                                    border: Border.all(
                                        color: kBrandColor, width: 1.5),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: _loadUserData,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 12),
                                        child: Text(
                                          'Riprova',
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
                                username: _username,
                                followerCount: _followerCount,
                                followingCount: _followingCount,
                                showFollowButton:
                                    FirebaseAuth.instance.currentUser?.uid !=
                                        widget.userId,
                                isFollowing: _isFollowing,
                                onToggleFollow: () async {
                                  if (FirebaseAuth.instance.currentUser ==
                                      null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Devi essere loggato per seguire.'),
                                      ),
                                    );
                                    return;
                                  }
                                  try {
                                    if (_isFollowing) {
                                      await _followService
                                          .unfollow(widget.userId);
                                    } else {
                                      await _followService
                                          .follow(widget.userId);
                                    }
                                    setState(() {
                                      _isFollowing = !_isFollowing;
                                      _followerCount += _isFollowing ? 1 : -1;
                                    });
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Errore: $e'),
                                        backgroundColor: kErrorColor,
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 14),
                              _ProfileHighlights(stats: _userStats),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      gradient: LinearGradient(
                                        colors: [
                                          kBrandColor.withAlpha(30),
                                          kBrandColor.withAlpha(20),
                                        ],
                                      ),
                                      border: Border.all(
                                          color: kBrandColor.withAlpha(100),
                                          width: 1),
                                    ),
                                    child: const Icon(Icons.public,
                                        color: kBrandColor, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    isMe
                                        ? 'Ultime attività'
                                        : 'Attività pubbliche',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if ((_showAllSessions
                                      ? _allPublicSessions
                                      : _publicSessions)
                                  .isEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: kMutedColor.withAlpha(20),
                                            border: Border.all(
                                                color: kMutedColor, width: 2),
                                          ),
                                          child: const Icon(
                                              Icons.directions_run,
                                              color: kMutedColor,
                                              size: 48),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          isMe
                                              ? 'Nessuna sessione registrata'
                                              : 'Nessuna sessione pubblica disponibile',
                                          style: const TextStyle(
                                              color: kMutedColor,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...(_showAllSessions
                                        ? _allPublicSessions
                                        : _publicSessions)
                                    .map((session) =>
                                        _SessionCard(session: session)),
                              if (_allPublicSessions.isNotEmpty ||
                                  !_hasAllSessions)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [
                                          kBrandColor.withAlpha(40),
                                          kBrandColor.withAlpha(25),
                                        ],
                                      ),
                                      border: Border.all(
                                          color: kBrandColor, width: 1.5),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: _sessionsLoadingAll
                                            ? null
                                            : () {
                                                if (_showAllSessions &&
                                                    _allPublicSessions
                                                        .isNotEmpty) {
                                                  setState(() {
                                                    _showAllSessions = false;
                                                  });
                                                } else if (_allPublicSessions
                                                    .isNotEmpty) {
                                                  setState(() {
                                                    _showAllSessions = true;
                                                  });
                                                } else {
                                                  _loadAllPublicSessions();
                                                }
                                              },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_sessionsLoadingAll)
                                                const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation(
                                                            kBrandColor),
                                                  ),
                                                )
                                              else
                                                Icon(
                                                    _showAllSessions
                                                        ? Icons.expand_less
                                                        : Icons.expand_more,
                                                    color: kBrandColor,
                                                    size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                _showAllSessions
                                                    ? 'Mostra meno'
                                                    : 'Mostra tutte',
                                                style: const TextStyle(
                                                  color: kBrandColor,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 30),
                            ],
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
    HEADER PROFILO
============================================================ */

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String tag;
  final String username;
  final int followerCount;
  final int followingCount;
  final bool showFollowButton;
  final bool isFollowing;
  final VoidCallback? onToggleFollow;

  const _ProfileHeader({
    required this.name,
    required this.tag,
    required this.username,
    required this.followerCount,
    required this.followingCount,
    this.showFollowButton = false,
    this.isFollowing = false,
    this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
            color: Colors.black.withAlpha(140),
            blurRadius: 16,
            spreadRadius: -3,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar tag with gradient ring
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor.withAlpha(80),
                      kPulseColor.withAlpha(60),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0A0A0F),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandColor.withAlpha(60),
                        blurRadius: 12,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: kBrandColor,
                      ),
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
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@$username',
                      style: const TextStyle(
                        color: kMutedColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const PulseChip(
                      label: Text('Accesso PULSE+'),
                      icon: Icons.bolt,
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          FollowCounts(
            followerCount: followerCount,
            followingCount: followingCount,
          ),
          if (showFollowButton) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: isFollowing
                      ? null
                      : LinearGradient(
                          colors: [
                            kBrandColor.withAlpha(40),
                            kBrandColor.withAlpha(25),
                          ],
                        ),
                  border: Border.all(
                    color: isFollowing ? kMutedColor : kBrandColor,
                    width: 1.5,
                  ),
                  color: isFollowing ? kMutedColor.withAlpha(20) : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onToggleFollow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isFollowing ? Icons.check : Icons.person_add_alt,
                            color: isFollowing ? kMutedColor : kBrandColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isFollowing ? 'Segui già' : 'Segui',
                            style: TextStyle(
                              color: isFollowing ? kMutedColor : kBrandColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]
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
    final bestLapText =
        stats.bestLapEver != null ? _formatDuration(stats.bestLapEver!) : '—';
    final bestLapTrack = stats.bestLapTrack ?? 'N/A';
    final distanceTotal = stats.totalDistanceKm.toStringAsFixed(0);
    final sessionsTotal = stats.totalSessions.toString();
    final pbCount = stats.personalBests.toString();
    final totalLaps = stats.totalLaps.toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
            color: Colors.black.withAlpha(140),
            blurRadius: 16,
            spreadRadius: -3,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      kPulseColor.withAlpha(30),
                      kPulseColor.withAlpha(20),
                    ],
                  ),
                  border:
                      Border.all(color: kPulseColor.withAlpha(100), width: 1),
                ),
                child:
                    const Icon(Icons.auto_graph, color: kPulseColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Highlights',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: kPulseColor.withAlpha(25),
                  border: Border.all(color: kPulseColor.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.bolt, size: 14, color: kPulseColor),
                    SizedBox(width: 6),
                    Text(
                      'Performance',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 16),

          // Best lap card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(40),
                  kPulseColor.withAlpha(40),
                  // const Color(0xFF0F0F15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kPulseColor.withAlpha(90)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPulseColor.withAlpha(30),
                        border: Border.all(
                            color: kPulseColor.withAlpha(120), width: 1),
                      ),
                      child:
                          const Icon(Icons.speed, color: kPulseColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Best lap assoluto',
                      style: TextStyle(
                        color: kPulseColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  bestLapText,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    color: kPulseColor,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: kPulseColor.withAlpha(25),
                    border: Border.all(color: kPulseColor.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.track_changes,
                          size: 14, color: kPulseColor),
                      const SizedBox(width: 4),
                      Text(
                        bestLapTrack,
                        style: const TextStyle(
                          color: kPulseColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats grid
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _HighlightTile(
                    icon: Icons.flag_circle_outlined,
                    label: 'Sessioni',
                    value: sessionsTotal,
                    accent: kBrandColor,
                    width: tileWidth,
                  ),
                  _HighlightTile(
                    icon: Icons.timeline,
                    label: 'Distanza',
                    value: '$distanceTotal km',
                    accent: const Color.fromARGB(255, 255, 133, 133),
                    width: tileWidth,
                  ),
                  _HighlightTile(
                    icon: Icons.emoji_events_outlined,
                    label: 'PB',
                    value: '$pbCount circuiti',
                    accent: const Color(0xFFFFD166),
                    width: tileWidth,
                  ),
                  _HighlightTile(
                    icon: Icons.flag_outlined,
                    label: 'Giri',
                    value: totalLaps,
                    accent: Colors.lightBlueAccent,
                    width: tileWidth,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final double width;

  const _HighlightTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent.withAlpha(15),
        border: Border.all(color: accent.withAlpha(120), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(40),
            blurRadius: 0,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withAlpha(30),
              border: Border.all(color: accent, width: 1.5),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: accent.withAlpha(200),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: accent,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
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

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pushNamed(
            '/activity',
            arguments: session,
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
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
                color: Colors.black.withAlpha(120),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icona attività
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor.withAlpha(30),
                      kBrandColor.withAlpha(20),
                    ],
                  ),
                  border:
                      Border.all(color: kBrandColor.withAlpha(100), width: 1),
                ),
                child: const Icon(Icons.track_changes,
                    color: kBrandColor, size: 24),
              ),
              const SizedBox(width: 14),

              // Info sessione
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.trackName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${session.lapCount} giri · ${session.distanceKm.toStringAsFixed(1)} km${bestLapText.isNotEmpty ? ' · $bestLapText' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: kMutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: session.isPublic
                                ? kPulseColor.withAlpha(25)
                                : kMutedColor.withAlpha(25),
                            border: Border.all(
                              color: session.isPublic
                                  ? kPulseColor.withAlpha(80)
                                  : kMutedColor.withAlpha(80),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                session.isPublic
                                    ? Icons.public
                                    : Icons.lock_outline,
                                size: 10,
                                color: session.isPublic
                                    ? kPulseColor
                                    : kMutedColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                session.isPublic ? 'Pubblico' : 'Privato',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: session.isPublic
                                      ? kPulseColor
                                      : kMutedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(session.dateTime),
                          style: TextStyle(
                            fontSize: 11,
                            color: kMutedColor.withAlpha(180),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Velocità max
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor.withAlpha(30),
                      kBrandColor.withAlpha(20),
                    ],
                  ),
                  border: Border.all(color: kBrandColor.withAlpha(80)),
                ),
                child: Column(
                  children: [
                    Text(
                      session.maxSpeedKmh.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kBrandColor,
                      ),
                    ),
                    const Text(
                      'km/h',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: kBrandColor,
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
}
