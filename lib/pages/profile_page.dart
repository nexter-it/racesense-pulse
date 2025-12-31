import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/session_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../services/profile_cache_service.dart';
import '../theme.dart';
import '../widgets/follow_counts.dart';
import '../widgets/session_metadata_dialog.dart';
import 'app_info_page.dart';
import 'story_composer_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final SessionService _sessionService = SessionService();
  final ProfileCacheService _cacheService = ProfileCacheService();

  String _userName = '';
  String _userTag = '';
  String _username = '';
  bool _isLoading = true;
  bool _sessionsLoadingAll = false;
  bool _showAllSessions = false;
  bool _hasAllSessions = false;
  int _followerCount = 0;
  int _followingCount = 0;
  bool _creatingCode = false;

  UserStats _userStats = UserStats.empty();
  List<SessionModel> _recentSessions = [];
  List<SessionModel> _allSessions = [];
  String? _affiliateCode;
  String? _referredByCode;

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
    _bootstrapProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Non ricaricare automaticamente al resume - l'utente può fare pull-to-refresh
  }

  Future<void> _bootstrapProfile() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ ProfilePage: Nessun utente loggato');
      setState(() => _isLoading = false);
      return;
    }

    if (_cacheService.hasCachedData) {
      print('📦 ProfilePage: Caricamento da cache locale...');
      _loadFromCache();
      setState(() => _isLoading = false);
      return;
    }

    print('🔄 ProfilePage: Nessuna cache, caricamento da Firebase...');
    await _refreshFromFirebase();
  }

  void _loadFromCache() {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = _cacheService.getCachedFullName();

    String tag;
    final nameParts = fullName.split(' ');
    if (nameParts.length >= 2) {
      tag = nameParts[0][0].toUpperCase() + nameParts[1][0].toUpperCase();
    } else if (nameParts.isNotEmpty && nameParts[0].length >= 2) {
      tag = nameParts[0].substring(0, 2).toUpperCase();
    } else {
      tag = 'US';
    }

    final sessions = _cacheService.cachedSessions;
    final stats = _cacheService.cachedUserStats ?? UserStats.empty();

    setState(() {
      _userName = fullName;
      _userTag = tag;
      _username = _cacheService.getCachedUsername();
      _userStats = stats;
      _recentSessions = sessions;
      _followerCount = stats.followerCount;
      _followingCount = stats.followingCount;
      _affiliateCode = _cacheService.getCachedAffiliateCode();
      _referredByCode = _cacheService.getCachedReferredByCode();
      _hasAllSessions = sessions.length < 5;
    });

    print('✅ ProfilePage: Caricato da cache (${sessions.length} sessioni)');
  }

  Future<void> _refreshFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ ProfilePage: Nessun utente loggato');
      return;
    }

    print('🔄 ProfilePage: Refreshing da Firebase...');

    try {
      final profileData = await _cacheService.refreshFromFirebase();

      final userData = profileData.userData;
      final stats = profileData.stats;
      final sessions = profileData.sessions;

      if (mounted) {
        final fullName = userData?['fullName'] ?? user.displayName ?? 'Utente';

        if (userData == null || userData['searchTokens'] == null) {
          _firestoreService.ensureSearchTokens(user.uid, fullName);
        }
        if (userData == null || userData['username'] == null) {
          _firestoreService.ensureUsernameForUser(user.uid, fullName);
        }

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
          _followerCount = stats.followerCount;
          _followingCount = stats.followingCount;
          _affiliateCode = userData?['affiliateCode'] as String?;
          _referredByCode = userData?['referredByCode'] as String?;
          _isLoading = false;
          _hasAllSessions = sessions.length < 5;
        });

        print('✅ ProfilePage: Refreshed da Firebase (${sessions.length} sessioni)');
        _cacheService.markFirstLoadComplete();
      }
    } catch (e) {
      print('❌ ProfilePage: Errore refresh - $e');
      if (mounted) {
        setState(() {
          _userName = user.displayName ?? 'Utente';
          _userTag = _userName.length >= 2
              ? _userName.substring(0, 2).toUpperCase()
              : 'US';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    await _refreshFromFirebase();
  }

  Future<void> _showCreateAffiliateDialog() async {
    final controller = TextEditingController(
      text: (_username.isNotEmpty ? _username.toUpperCase() : 'RSPULSE'),
    );
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Crea codice affiliato',
          style: TextStyle(color: kFgColor, fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: kFgColor),
          decoration: const InputDecoration(
            hintText: 'RSPULSE',
            hintStyle: TextStyle(color: kMutedColor),
            labelText: 'Codice',
            labelStyle: TextStyle(color: kMutedColor),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla', style: TextStyle(color: kMutedColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty) return;

    setState(() => _creatingCode = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Utente non autenticato';
      final clean = _firestoreService.sanitizeAffiliateCode(code);
      final claimed =
          await _firestoreService.claimAffiliateCode(user.uid, clean);
      if (mounted) {
        setState(() {
          _affiliateCode = claimed;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Codice creato: $claimed'),
            backgroundColor: kBrandColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: kErrorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingCode = false);
    }
  }

  Future<void> _loadAllSessions() async {
    if (_sessionsLoadingAll || _hasAllSessions) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _sessionsLoadingAll = true;
    });

    try {
      final sessions = await _cacheService.loadAllSessions();
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : RefreshIndicator(
                      onRefresh: _refreshFromFirebase,
                      color: kBrandColor,
                      backgroundColor: const Color(0xFF1A1A1A),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        children: [
                          _buildProfileCard(),
                          const SizedBox(height: 16),
                          _buildHighlightsCard(),
                          const SizedBox(height: 16),
                          _buildAffiliateCard(),
                          const SizedBox(height: 24),
                          _buildSessionsSection(),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A0A0A),
            const Color(0xFF121212),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(120),
                  kPulseColor.withAlpha(80),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A1A),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
              ),
              child: Center(
                child: Text(
                  _userTag,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Title and username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName.isNotEmpty ? _userName : 'Profilo',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
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
                          Icon(Icons.bolt, size: 11, color: kBrandColor),
                          const SizedBox(width: 4),
                          Text(
                            'PULSE+',
                            style: TextStyle(
                              fontSize: 10,
                              color: kBrandColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_username.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '@$_username',
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Settings button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: kMutedColor, size: 22),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AppInfoPage(),
                  ),
                );
              },
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

  Widget _buildProfileCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(100),
                        kPulseColor.withAlpha(80),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0A0A0A),
                      boxShadow: [
                        BoxShadow(
                          color: kBrandColor.withAlpha(40),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _userTag,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: kBrandColor,
                        ),
                      ),
                    ),
                  ),
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
                top: BorderSide(color: Color(0xFF2A2A2A)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, color: kBrandColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Account verificato',
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
    final pbCount = _userStats.personalBests.toString();
    final totalLaps = _userStats.totalLaps.toString();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                // Stats grid
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        icon: Icons.flag_circle_outlined,
                        value: sessionsTotal,
                        label: 'Sessioni',
                        color: kBrandColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatChip(
                        icon: Icons.route_rounded,
                        value: '$distanceTotal km',
                        label: 'Distanza',
                        color: const Color(0xFF29B6F6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        icon: Icons.emoji_events_outlined,
                        value: pbCount,
                        label: 'Record',
                        color: const Color(0xFFFFB74D),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatChip(
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
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withAlpha(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(25),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildAffiliateCard() {
    final hasCode = _affiliateCode != null && _affiliateCode!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        child: Icon(Icons.card_membership, color: kPulseColor, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Codice Affiliato',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: kFgColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (hasCode)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Clipboard.setData(ClipboardData(text: _affiliateCode ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Codice copiato'),
                              backgroundColor: kBrandColor,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: kBrandColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kBrandColor.withAlpha(60)),
                          ),
                          child: Icon(Icons.copy, color: kBrandColor, size: 18),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (hasCode) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withAlpha(6),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _affiliateCode!.length > 10
                              ? '${_affiliateCode!.substring(0, 10)}...'
                              : _affiliateCode!,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            color: kBrandColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: kBrandColor.withAlpha(20),
                            border: Border.all(color: kBrandColor.withAlpha(80)),
                          ),
                          child: Text(
                            'ATTIVO',
                            style: TextStyle(
                              color: kBrandColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    'Crea il tuo codice affiliato e condividilo',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _showCreateAffiliateDialog,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            kBrandColor.withAlpha(30),
                            kBrandColor.withAlpha(15),
                          ],
                        ),
                        border: Border.all(color: kBrandColor.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, color: kBrandColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Crea codice',
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
              ],
            ),
          ),
          if (_referredByCode != null && _referredByCode!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: kPulseColor.withAlpha(10),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: const Border(
                  top: BorderSide(color: Color(0xFF2A2A2A)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, color: kPulseColor, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Invitato con: $_referredByCode',
                    style: TextStyle(
                      color: kPulseColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionsSection() {
    final sessions = _showAllSessions ? _allSessions : _recentSessions;

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
                child: Icon(Icons.history, color: kBrandColor, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ultime Attività',
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
          _buildEmptySessionsState()
        else
          ...sessions.map((session) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSessionCard(session),
          )),

        // Show more/less button
        if (_allSessions.isNotEmpty || !_hasAllSessions)
          GestureDetector(
            onTap: _sessionsLoadingAll
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    if (_showAllSessions && _allSessions.isNotEmpty) {
                      setState(() => _showAllSessions = false);
                    } else if (_allSessions.isNotEmpty) {
                      setState(() => _showAllSessions = true);
                    } else {
                      _loadAllSessions();
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF1A1A1A),
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

  Widget _buildEmptySessionsState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                  kBrandColor.withAlpha(30),
                  kBrandColor.withAlpha(10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A1A),
                border: Border.all(color: kBrandColor.withAlpha(60), width: 2),
              ),
              child: Icon(Icons.directions_car, color: kBrandColor, size: 24),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Nessuna sessione',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: kFgColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Inizia a registrare le tue sessioni in pista',
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
            colors: [
              const Color(0xFF1A1A1A),
              const Color(0xFF141414),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFF2A2A2A)),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
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
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: session.isPublic
                                    ? kPulseColor.withAlpha(20)
                                    : kMutedColor.withAlpha(20),
                                border: Border.all(
                                  color: session.isPublic
                                      ? kPulseColor.withAlpha(60)
                                      : kMutedColor.withAlpha(60),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    session.isPublic ? Icons.public : Icons.lock_outline,
                                    size: 10,
                                    color: session.isPublic ? kPulseColor : kMutedColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    session.isPublic ? 'Pubblico' : 'Privato',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: session.isPublic ? kPulseColor : kMutedColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Stats row
                        Row(
                          children: [
                            _buildSessionStat(Icons.loop, '${session.lapCount}', const Color(0xFF29B6F6)),
                            const SizedBox(width: 10),
                            _buildSessionStat(Icons.route, '${session.distanceKm.toStringAsFixed(1)} km', const Color(0xFF00E676)),
                            // const SizedBox(width: 10),
                            // _buildSessionStat(Icons.timer, bestLapText, const Color(0xFFFFB74D)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _openStoryComposer(session),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withAlpha(20)),
                          ),
                          child: const Icon(Icons.ios_share, size: 16, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _deleteSession(session),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: kErrorColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kErrorColor.withAlpha(60)),
                          ),
                          child: Icon(Icons.delete_outline, size: 16, color: kErrorColor.withAlpha(200)),
                        ),
                      ),
                    ],
                  ),
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
                  top: BorderSide(color: Color(0xFF2A2A2A)),
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }
}
