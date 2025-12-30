import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../models/session_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../services/profile_cache_service.dart';
import '../theme.dart';
import '../widgets/follow_counts.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import '../widgets/session_metadata_dialog.dart';
import 'app_info_page.dart';
import 'connect_devices_page.dart';
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

  /// Bootstrap profilo: carica da cache se disponibile, altrimenti da Firebase
  Future<void> _bootstrapProfile() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ ProfilePage: Nessun utente loggato');
      setState(() => _isLoading = false);
      return;
    }

    // Prima prova a caricare dalla cache
    if (_cacheService.hasCachedData) {
      print('📦 ProfilePage: Caricamento da cache locale...');
      _loadFromCache();
      setState(() => _isLoading = false);
      return;
    }

    // Nessuna cache: carica da Firebase
    print('🔄 ProfilePage: Nessuna cache, caricamento da Firebase...');
    await _refreshFromFirebase();
  }

  /// Carica i dati dalla cache locale
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

  /// Refresh completo da Firebase (pull-to-refresh)
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

        // Assicura search tokens e username (background, non blocca UI)
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

        // Segna che il primo caricamento è completato
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

  /// Vecchio metodo per compatibilità (chiama refresh)
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
      // Usa il cache service per caricare tutte le sessioni
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
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        kMutedColor.withAlpha(30),
                        kMutedColor.withAlpha(20),
                      ],
                    ),
                    border: Border.all(color: kMutedColor.withAlpha(80), width: 1.5),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AppInfoPage(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.settings, color: kMutedColor, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Info',
                              style: TextStyle(
                                color: kMutedColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                    onRefresh: _refreshFromFirebase,
                    color: kBrandColor,
                    backgroundColor: kBgColor,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      children: [
                        _ProfileHeader(
                          name: _userName,
                          tag: _userTag,
                          username: _username,
                          followerCount: _followerCount,
                          followingCount: _followingCount,
                        ),
                        const SizedBox(height: 14),
                        _ProfileHighlights(stats: _userStats),
                        const SizedBox(height: 15),
                        _AffiliateCard(
                          code: _affiliateCode,
                          referredByCode: _referredByCode,
                          onGenerate: _showCreateAffiliateDialog,
                        ),
                        const SizedBox(height: 18),
                        // _ConnectDevicesTile(onTap: () {
                        //   Navigator.of(context).push(
                        //     MaterialPageRoute(
                        //       builder: (_) => const ConnectDevicesPage(),
                        //     ),
                        //   );
                        // }),
                        // const SizedBox(height: 24),
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
                              child: const Icon(Icons.history,
                                  color: kBrandColor, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Ultime attività',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if ((_showAllSessions ? _allSessions : _recentSessions)
                            .isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: const [
                                  Icon(Icons.directions_run,
                                      color: kMutedColor, size: 48),
                                  SizedBox(height: 12),
                                  Text(
                                    'Nessuna sessione registrata',
                                    style: TextStyle(
                                        color: kMutedColor,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
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
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    kBrandColor.withAlpha(40),
                                    kBrandColor.withAlpha(25),
                                  ],
                                ),
                                border:
                                    Border.all(color: kBrandColor, width: 1.5),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _sessionsLoadingAll
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
                                            child: CircularProgressIndicator(
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
                        const SizedBox(height: 20),
                        // const _HelpCenterCard(),
                        // const SizedBox(height: 30),
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
  final int followerCount;
  final int followingCount;

  const _ProfileHeader({
    required this.name,
    required this.tag,
    required this.username,
    required this.followerCount,
    required this.followingCount,
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
        ],
      ),
    );
  }
}

class _HelpCenterCard extends StatelessWidget {
  const _HelpCenterCard();

  static const _email = 'info@nexter.it';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(30),
                  kPulseColor.withAlpha(20),
                ],
              ),
              border: Border.all(color: kPulseColor.withAlpha(100), width: 1),
            ),
            child: const Icon(Icons.help_outline, color: kPulseColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Help Center',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Per assistenza o comunicazioni invia una mail a $_email '
                  'con oggetto: "TICKET APP RACESENSE".',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
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

class _AffiliateCard extends StatelessWidget {
  final String? code;
  final String? referredByCode;
  final VoidCallback onGenerate;

  const _AffiliateCard({
    required this.code,
    required this.referredByCode,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final hasCode = code != null && code!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      kPulseColor.withAlpha(30),
                      kPulseColor.withAlpha(20),
                    ],
                  ),
                  border:
                      Border.all(color: kPulseColor.withAlpha(100), width: 1),
                ),
                child: const Icon(Icons.card_membership,
                    color: kPulseColor, size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Codice affiliato',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (hasCode)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      final value = code ?? '';
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Codice copiato'),
                          backgroundColor: kBrandColor,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child:
                          const Icon(Icons.copy, color: kBrandColor, size: 20),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasCode) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color.fromRGBO(255, 255, 255, 0.05),
                border: Border.all(color: kLineColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    code!,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: kBrandColor,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: kBrandColor.withAlpha(25),
                      border: Border.all(color: kBrandColor.withAlpha(80)),
                    ),
                    child: const Text(
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
            const SizedBox(height: 10),
            const Text(
              'Condividi il tuo codice per attribuire le affiliazioni.',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            const Text(
              'Crea il tuo codice affiliato e condividilo con i tuoi contatti.',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
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
                    borderRadius: BorderRadius.circular(14),
                    onTap: onGenerate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_circle_outline,
                              size: 20, color: kBrandColor),
                          SizedBox(width: 8),
                          Text(
                            'Crea codice',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: kBrandColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (referredByCode != null && referredByCode!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: kPulseColor.withAlpha(15),
                border: Border.all(color: kPulseColor.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, color: kPulseColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sei stato invitato con il codice $referredByCode',
                      style: const TextStyle(
                        color: kPulseColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectDevicesTile extends StatelessWidget {
  final VoidCallback onTap;

  const _ConnectDevicesTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
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
                child:
                    const Icon(Icons.bluetooth, color: kBrandColor, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Collega dispositivi tracking',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Gestisci e collega i tracker GPS Tracker al tuo profilo.',
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kBrandColor, size: 24),
            ],
          ),
        ),
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

              if (onShare != null || onDelete != null) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onShare != null)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.ios_share,
                              size: 18, color: Colors.white),
                          onPressed: onShare,
                        ),
                      ),
                    if (onDelete != null)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: kErrorColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: kErrorColor.withAlpha(80)),
                        ),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: kErrorColor),
                          onPressed: onDelete,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
