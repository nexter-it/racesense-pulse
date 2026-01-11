import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../services/follow_service.dart';
import '../services/event_service.dart';
import '../models/session_model.dart';
import '../models/driver_info.dart';
import '../widgets/follow_counts.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/badge_display_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

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
  final EventService _eventService = EventService();

  String _userName = '';
  String _userTag = '';
  String _username = '';
  String? _profileImageUrl;
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
  bool _isFollowing = false;
  DriverInfo? _driverInfo;

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

      // Carica driverInfo se presente
      DriverInfo? driverInfo;
      if (userData != null && userData['driverInfo'] != null) {
        try {
          driverInfo = DriverInfo.fromJson(userData['driverInfo'] as Map<String, dynamic>);
        } catch (e) {
          driverInfo = null;
        }
      }

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
          _profileImageUrl = userData?['profileImageUrl'] as String?;
          _userStats = stats;
          _publicSessions = sessions;
          _isLoading = false;
          _hasAllSessions = sessions.length < 5;
          _showAllSessions = false;
          _allPublicSessions = [];
          _followerCount = stats.followerCount;
          _followingCount = stats.followingCount;
          _driverInfo = driverInfo;
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
      final sessions = await _sessionService.getUserSessions(
        widget.userId,
        limit: 50,
        onlyPublic: true,
      );
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

  Future<void> _toggleFollow() async {
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devi essere loggato per seguire.')),
      );
      return;
    }
    try {
      HapticFeedback.lightImpact();
      if (_isFollowing) {
        await _followService.unfollow(widget.userId);
      } else {
        await _followService.follow(widget.userId);
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
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = currentUserId != null && currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isMe),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _error
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _loadUserData,
                          color: kBrandColor,
                          backgroundColor: _kCardStart,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                            children: [
                              _buildProfileCard(isMe),
                              const SizedBox(height: 16),
                              if (_driverInfo != null && _driverInfo!.hasAnyInfo) ...[
                                _buildDriverInfoCard(),
                                const SizedBox(height: 16),
                              ],
                              _buildHighlightsCard(),
                              const SizedBox(height: 16),
                              // Collezione Badge
                              BadgeCard(
                                userId: widget.userId,
                                badgesStream: _eventService.getUserBadges(widget.userId),
                              ),
                              const SizedBox(height: 24),
                              _buildSessionsSection(isMe),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMe) {
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
          // Avatar
          ProfileAvatar(
            profileImageUrl: _profileImageUrl,
            userTag: _userTag,
            size: 40,
            borderWidth: 2,
            showGradientBorder: true,
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName.isNotEmpty ? _userName : 'Profilo Pilota',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_username.isNotEmpty)
                  Text(
                    '@$_username',
                    style: TextStyle(
                      fontSize: 12,
                      color: kMutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          // "Tu" badge if it's the current user
          if (isMe)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: kBrandColor.withAlpha(20),
                border: Border.all(color: kBrandColor.withAlpha(80)),
              ),
              child: Text(
                'Tu',
                style: TextStyle(
                  color: kBrandColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
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
            'Caricamento profilo...',
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
                    kErrorColor.withAlpha(30),
                    kErrorColor.withAlpha(10),
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
                  border: Border.all(color: kErrorColor.withAlpha(100), width: 2),
                ),
                child: Icon(Icons.error_outline, color: kErrorColor, size: 28),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Errore nel caricamento',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: kFgColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Impossibile caricare il profilo del pilota',
              style: TextStyle(
                fontSize: 13,
                color: kMutedColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _loadUserData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor.withAlpha(40),
                      kBrandColor.withAlpha(20),
                    ],
                  ),
                  border: Border.all(color: kBrandColor.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: kBrandColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Riprova',
                      style: TextStyle(
                        color: kBrandColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
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

  Widget _buildProfileCard(bool isMe) {
    final showFollowButton = !isMe && FirebaseAuth.instance.currentUser != null;

    return Container(
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Large Avatar
                ProfileAvatar(
                  profileImageUrl: _profileImageUrl,
                  userTag: _userTag,
                  size: 72,
                  borderWidth: 3,
                  showGradientBorder: true,
                ),
                const SizedBox(width: 16),
                // Name and stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: kFgColor,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$_username',
                        style: TextStyle(
                          fontSize: 13,
                          color: kMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Follow counts inline
                      Row(
                        children: [
                          _buildMiniStat('Follower', _followerCount.toString(), kBrandColor),
                          const SizedBox(width: 12),
                          _buildMiniStat('Seguiti', _followingCount.toString(), kPulseColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Follow button section
          if (showFollowButton)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: GestureDetector(
                onTap: _toggleFollow,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: _isFollowing
                        ? null
                        : LinearGradient(
                            colors: [
                              kBrandColor.withAlpha(40),
                              kBrandColor.withAlpha(20),
                            ],
                          ),
                    color: _isFollowing ? kMutedColor.withAlpha(15) : null,
                    border: Border.all(
                      color: _isFollowing ? kMutedColor.withAlpha(60) : kBrandColor.withAlpha(80),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isFollowing ? Icons.check : Icons.person_add_alt,
                        color: _isFollowing ? kMutedColor : kBrandColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isFollowing ? 'Segui già' : 'Segui',
                        style: TextStyle(
                          color: _isFollowing ? kMutedColor : kBrandColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(4),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: const Border(
                top: BorderSide(color: _kBorderColor),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, color: kBrandColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Pilota verificato',
                  style: TextStyle(
                    color: kBrandColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Accesso PULSE+',
                  style: TextStyle(
                    color: kPulseColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.bolt, color: kPulseColor, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withAlpha(15),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withAlpha(180),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightsCard() {
    final distanceTotal = _userStats.totalDistanceKm.toStringAsFixed(0);
    final sessionsTotal = _userStats.totalSessions.toString();
    final totalLaps = _userStats.totalLaps.toString();

    return Container(
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
                        kPulseColor.withAlpha(40),
                        kPulseColor.withAlpha(20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: kPulseColor.withAlpha(60), width: 1.5),
                  ),
                  child: Center(
                    child: Icon(Icons.auto_graph, color: kPulseColor, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Performance',
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
                        'Stats',
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
            // Stats in una riga
            Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.flag_circle_outlined,
                    value: sessionsTotal,
                    label: 'Sessioni',
                    color: kBrandColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: const Color(0xFF2A2A2A),
                ),
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.route_rounded,
                    value: '$distanceTotal km',
                    label: 'Distanza',
                    color: const Color(0xFF29B6F6),
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: const Color(0xFF2A2A2A),
                ),
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.loop_rounded,
                    value: totalLaps,
                    label: 'Giri',
                    color: const Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(20),
            border: Border.all(color: color.withAlpha(60), width: 1.5),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: kFgColor,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: kMutedColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionsSection(bool isMe) {
    final sessions = _showAllSessions ? _allPublicSessions : _publicSessions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: kBrandColor.withAlpha(60), width: 1.5),
              ),
              child: Center(
                child: Icon(Icons.public, color: kBrandColor, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMe ? 'Ultime Attività' : 'Attività Pubbliche',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: kFgColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kBrandColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: kBrandColor.withAlpha(60)),
                    ),
                    child: Text(
                      '${sessions.length} ${sessions.length == 1 ? 'sessione' : 'sessioni'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: kBrandColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Sessions list
        if (sessions.isEmpty)
          _buildEmptySessionsState(isMe)
        else
          ...sessions.map((session) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSessionCard(session),
          )),

        // Show more/less button
        if (_allPublicSessions.isNotEmpty || !_hasAllSessions)
          GestureDetector(
            onTap: _sessionsLoadingAll
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    if (_showAllSessions && _allPublicSessions.isNotEmpty) {
                      setState(() => _showAllSessions = false);
                    } else if (_allPublicSessions.isNotEmpty) {
                      setState(() => _showAllSessions = true);
                    } else {
                      _loadAllPublicSessions();
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _kCardStart,
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sessionsLoadingAll)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(kBrandColor),
                      ),
                    )
                  else
                    Icon(
                      _showAllSessions ? Icons.expand_less : Icons.expand_more,
                      color: kBrandColor,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _showAllSessions ? 'Mostra meno' : 'Mostra tutte',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptySessionsState(bool isMe) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
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
              child: Icon(Icons.directions_car, color: kMutedColor, size: 24),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isMe ? 'Nessuna sessione' : 'Nessuna sessione pubblica',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: kFgColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMe
                ? 'Inizia a registrare le tue sessioni in pista'
                : 'Questo pilota non ha ancora sessioni pubbliche',
            style: TextStyle(
              fontSize: 13,
              color: kMutedColor,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(SessionModel session) {
    final formattedDate = DateFormat('dd MMM yyyy').format(session.dateTime);
    final formattedTime = DateFormat('HH:mm').format(session.dateTime);
    final bestLapText = session.bestLap != null
        ? _formatDuration(session.bestLap!)
        : '-:--.--';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).pushNamed('/activity', arguments: session);
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          kBrandColor.withAlpha(40),
                          kBrandColor.withAlpha(20),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: kBrandColor.withAlpha(60), width: 1.5),
                    ),
                    child: Center(
                      child: Icon(Icons.flag_rounded, color: kBrandColor, size: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.trackName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: kFgColor,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Stats row
                        Row(
                          children: [
                            _buildSessionStat(Icons.loop, '${session.lapCount}', const Color(0xFF29B6F6)),
                            const SizedBox(width: 10),
                            _buildSessionStat(Icons.route, '${session.distanceKm.toStringAsFixed(1)} km', const Color(0xFF00E676)),
                            const SizedBox(width: 10),
                            _buildSessionStat(Icons.timer, bestLapText, const Color(0xFFFFB74D)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Max speed
                  // Container(
                  //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  //   decoration: BoxDecoration(
                  //     borderRadius: BorderRadius.circular(12),
                  //     gradient: LinearGradient(
                  //       colors: [
                  //         kBrandColor.withAlpha(30),
                  //         kBrandColor.withAlpha(15),
                  //       ],
                  //     ),
                  //     border: Border.all(color: kBrandColor.withAlpha(60)),
                  //   ),
                  //   child: Column(
                  //     children: [
                  //       Text(
                  //         session.maxSpeedKmh.toStringAsFixed(0),
                  //         style: TextStyle(
                  //           fontSize: 18,
                  //           fontWeight: FontWeight.w900,
                  //           color: kBrandColor,
                  //         ),
                  //       ),
                  //       Text(
                  //         'km/h',
                  //         style: TextStyle(
                  //           fontSize: 9,
                  //           fontWeight: FontWeight.w700,
                  //           color: kBrandColor.withAlpha(180),
                  //         ),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                ],
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(4),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: const Border(
                  top: BorderSide(color: _kBorderColor),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: kMutedColor, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kMutedColor.withAlpha(100),
                    ),
                  ),
                  Icon(Icons.access_time_rounded, color: kMutedColor, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Dettagli',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: kBrandColor, size: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withAlpha(15),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverInfoCard() {
    // Mappa colori e icone per categoria (corrispondenti a DriverInfo.badgeCategories)
    final categoryConfig = {
      'Status/Obiettivi': (const Color(0xFFAB47BC), Icons.rocket_launch), // Viola
      'Specializzazione': (const Color(0xFF29B6F6), Icons.sports_score), // Blu
      'Disponibilità': (const Color(0xFF66BB6A), Icons.handshake), // Verde
    };

    // Raggruppa i badge per categoria
    final badgesByCategory = <String, List<String>>{};
    for (final badgeId in _driverInfo!.selectedBadges) {
      final category = DriverInfo.getCategoryForBadge(badgeId) ?? 'Altro';
      badgesByCategory.putIfAbsent(category, () => []).add(badgeId);
    }

    // Ordina le categorie
    final orderedCategories = ['Status/Obiettivi', 'Specializzazione', 'Disponibilità']
        .where((c) => badgesByCategory.containsKey(c))
        .toList();

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(40),
                        kBrandColor.withAlpha(20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(60), width: 1.5),
                  ),
                  child: Center(
                    child: Icon(Icons.person_pin_outlined, color: kBrandColor, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profilo Pilota',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: kFgColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kBrandColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kBrandColor.withAlpha(60)),
                        ),
                        child: Text(
                          '${_driverInfo!.selectedBadges.length} caratteristiche',
                          style: TextStyle(
                            fontSize: 10,
                            color: kBrandColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bio (se presente)
          if (_driverInfo!.hasBio)
            Container(
              margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _kTileColor,
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote, color: kMutedColor.withAlpha(100), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _driverInfo!.bio ?? '',
                      style: TextStyle(
                        color: kFgColor.withAlpha(220),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Categorie organizzate
          ...orderedCategories.map((category) {
            final config = categoryConfig[category]!;
            final color = config.$1;
            final icon = config.$2;
            final badges = badgesByCategory[category]!;

            return Container(
              margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withAlpha(8),
                border: Border.all(color: color.withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: color.withAlpha(25),
                        ),
                        child: Icon(icon, color: color, size: 14),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        category.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Badge chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: badges.map((badgeId) {
                      final label = DriverInfo.getLabelForBadge(badgeId);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withAlpha(60)),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }
}
