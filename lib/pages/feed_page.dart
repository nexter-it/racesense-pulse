import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import 'activity_detail_page.dart';

import '../services/session_service.dart';
import '../services/follow_service.dart';
import '../services/feed_cache_service.dart';
import '../services/engagement_service.dart';
import '../models/session_model.dart';
import '../widgets/profile_avatar.dart';

/// Converte il displayPath salvato nel doc sessione in una path 2D per il painter.
List<Offset> _buildTrack2dFromSession(SessionModel session) {
  final raw = session.displayPath;

  if (raw == null || raw.isEmpty) {
    return _generateFakeTrack(rotationDeg: 0);
  }

  final points = <Offset>[];

  for (final m in raw) {
    final lat = m['lat'];
    final lon = m['lon'];

    if (lat != null && lon != null) {
      points.add(Offset(lon, lat));
    }
  }

  if (points.length < 2) {
    return _generateFakeTrack(rotationDeg: 0);
  }

  return points;
}

List<Offset> _generateFakeTrack({
  double scaleX = 120,
  double scaleY = 80,
  int samplesPerSegment = 12,
  double rotationDeg = 0,
}) {
  final List<Offset> result = [];

  final List<Offset> base = [
    const Offset(-1.0, -0.1),
    const Offset(-0.3, -0.6),
    const Offset(0.3, -0.65),
    const Offset(0.9, -0.2),
    const Offset(1.0, 0.2),
    const Offset(0.4, 0.7),
    const Offset(-0.2, 0.6),
    const Offset(-0.9, 0.2),
    const Offset(-1.0, -0.1),
  ];

  final rot = rotationDeg * math.pi / 180.0;
  final cosR = math.cos(rot);
  final sinR = math.sin(rot);

  for (int i = 0; i < base.length - 1; i++) {
    final p0 = base[i];
    final p1 = base[i + 1];

    for (int j = 0; j < samplesPerSegment; j++) {
      final t = j / samplesPerSegment;

      final nx = p0.dx + (p1.dx - p0.dx) * t;
      final ny = p0.dy + (p1.dy - p0.dy) * t;

      double x = nx * scaleX;
      double y = ny * scaleY;

      final noise = (i.isEven ? 1 : -1) * 0.03;
      x += noise * scaleX * (math.sin(t * math.pi));
      y += noise * scaleY * (math.cos(t * math.pi));

      final xr = x * cosR - y * sinR;
      final yr = x * sinR + y * cosR;

      result.add(Offset(xr, yr));
    }
  }

  return result;
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedSessionItem {
  final SessionModel session;
  final bool isFollowed;
  final bool isNearby;

  const _FeedSessionItem({
    required this.session,
    required this.isFollowed,
    required this.isNearby,
  });
}

class _FeedPageState extends State<FeedPage> with TickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  final FollowService _followService = FollowService();
  final FeedCacheService _cacheService = FeedCacheService();
  final ScrollController _scrollController = ScrollController();

  final List<_FeedSessionItem> _feedItems = [];
  Set<String> _followingIds = {};
  Position? _userPosition;
  String? _locationError;
  bool _isLoadingLocation = false; // Nuovo: traccia se stiamo caricando la posizione

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isRefreshing = false;

  static const int _pageSize = 15;
  static const double _nearbyRadiusKm = 80;

  bool _showDisclaimer = false;
  bool _dontShowAgain = false;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Setup animations
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadDisclaimer();
    _bootstrapFeed();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapFeed() async {
    setState(() => _isLoading = true);
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      if (_cacheService.hasCachedData) {
        print('📦 Caricamento feed da cache locale...');
        _followingIds = _cacheService.getCachedFollowingIds();

        final cachedSessions = _cacheService.getCachedFeed();
        _feedItems.clear();
        for (final session in cachedSessions) {
          if (currentUserId != null && session.userId == currentUserId) {
            continue;
          }

          final isFollowed = _followingIds.contains(session.userId);
          // Nearby sarà false finché non abbiamo la posizione
          _feedItems.add(_FeedSessionItem(
            session: session,
            isFollowed: isFollowed,
            isNearby: false,
          ));
        }
        _hasMore = cachedSessions.length >= _pageSize;

        print('✅ Feed caricato da cache: ${_feedItems.length} sessioni');

        if (mounted) {
          setState(() => _isLoading = false);
        }

        // Carica posizione in background e aggiorna i badge nearby
        _loadLocationInBackground();
        return;
      }

      print('🔄 Nessuna cache, caricamento da Firebase...');
      await _refreshFromFirebase();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Carica la posizione GPS in background senza bloccare il feed
  Future<void> _loadLocationInBackground() async {
    if (_isLoadingLocation) return;

    _isLoadingLocation = true;
    try {
      final position = await _getUserLocation();
      _userPosition = position;

      if (position != null && mounted) {
        // Aggiorna i badge nearby per le sessioni già caricate
        _updateNearbyBadges();
      }
    } finally {
      _isLoadingLocation = false;
    }
  }

  /// Aggiorna i badge "nearby" per le sessioni già in lista
  void _updateNearbyBadges() {
    if (_userPosition == null) return;

    bool hasChanges = false;
    final updatedItems = <_FeedSessionItem>[];

    for (final item in _feedItems) {
      final isNearby = _isNearby(item.session);
      if (isNearby != item.isNearby) {
        hasChanges = true;
        updatedItems.add(_FeedSessionItem(
          session: item.session,
          isFollowed: item.isFollowed,
          isNearby: isNearby,
        ));
      } else {
        updatedItems.add(item);
      }
    }

    if (hasChanges && mounted) {
      setState(() {
        _feedItems.clear();
        _feedItems.addAll(updatedItems);
      });
      print('✅ Aggiornati ${updatedItems.where((i) => i.isNearby).length} badge nearby');
    }
  }

  Future<void> _refreshFromFirebase() async {
    setState(() => _isRefreshing = true);
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // 1. Carica following IDs (veloce, non dipende da GPS)
      _followingIds = await _cacheService.refreshFollowingIds(limit: 200);

      // 2. Avvia caricamento posizione in parallelo (non bloccante)
      final locationFuture = _getUserLocation();

      // 3. Carica subito le sessioni dei followed (non serve GPS)
      //    Per nearby, usa un filtro che ritorna sempre false se non abbiamo ancora la posizione
      final sessions = await _cacheService.refreshFeed(
        followingIds: _followingIds,
        isNearbyFilter: _isNearby,
        pageSize: _pageSize,
      );

      _feedItems.clear();
      for (final session in sessions) {
        if (currentUserId != null && session.userId == currentUserId) {
          continue;
        }

        final isFollowed = _followingIds.contains(session.userId);
        final isNearby = _isNearby(session);
        _feedItems.add(_FeedSessionItem(
          session: session,
          isFollowed: isFollowed,
          isNearby: isNearby,
        ));
      }
      _hasMore = sessions.length >= _pageSize;

      print('✅ Feed refreshed da Firebase: ${_feedItems.length} sessioni');

      _cacheService.markFirstLoadComplete();

      // 4. Aggiorna UI subito (senza aspettare GPS)
      if (mounted) {
        setState(() => _isRefreshing = false);
      }

      // 5. Aspetta la posizione e aggiorna i badge nearby
      _userPosition = await locationFuture;
      if (_userPosition != null && mounted) {
        _updateNearbyBadges();
      }
    } catch (e) {
      print('❌ Errore refresh feed: $e');
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _loadDisclaimer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getBool('disclaimer_hidden_$uid') ?? false;
    if (mounted) {
      setState(() {
        _showDisclaimer = !hidden;
        _dontShowAgain = hidden;
      });
    }
  }

  Future<void> _hideDisclaimer({bool forever = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    if (forever) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('disclaimer_hidden_$uid', true);
    }
    if (mounted) {
      setState(() {
        _showDisclaimer = false;
        _dontShowAgain = forever || _dontShowAgain;
      });
    }
  }

  Future<Position?> _getUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationError = 'GPS disattivato';
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _locationError = 'Permesso posizione negato';
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      _locationError = 'Errore localizzazione: $e';
      return null;
    }
  }

  bool _isNearby(SessionModel session) {
    if (_userPosition == null) return false;
    final coords = session.locationCoords;
    final distMeters = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      coords.latitude,
      coords.longitude,
    );
    return distMeters / 1000.0 <= _nearbyRadiusKm;
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_isLoadingMore) return;
    if (reset) {
      _feedItems.clear();
      _hasMore = true;
    }
    if (!_hasMore) return;

    if (!mounted) return;
    setState(() => _isLoadingMore = true);

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    try {
      // Trova la data più vecchia tra le sessioni caricate
      DateTime? olderThan;
      if (_feedItems.isNotEmpty) {
        olderThan = _feedItems.last.session.dateTime;
      }

      final newSessions = await _cacheService.loadMoreFeed(
        followingIds: _followingIds,
        isNearbyFilter: _isNearby,
        olderThan: olderThan,
        pageSize: _pageSize,
      );

      if (newSessions.isEmpty) {
        _hasMore = false;
      } else {
        for (final session in newSessions) {
          if (currentUserId != null && session.userId == currentUserId) {
            continue;
          }

          final alreadyAdded = _feedItems
              .any((item) => item.session.sessionId == session.sessionId);
          if (alreadyAdded) continue;

          final isFollowed = _followingIds.contains(session.userId);
          final isNearby = _isNearby(session);

          _feedItems.add(_FeedSessionItem(
            session: session,
            isFollowed: isFollowed,
            isNearby: isNearby,
          ));
        }

        _hasMore = newSessions.length >= _pageSize;
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
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
              child: Stack(
                children: [
                  _isLoading
                      ? _buildLoadingState()
                      : RefreshIndicator(
                          onRefresh: _refreshFromFirebase,
                          color: kBrandColor,
                          backgroundColor: const Color(0xFF1A1A1A),
                          child: _feedItems.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  controller: _scrollController,
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                  itemCount: _feedItems.length +
                                      (_isLoadingMore && _hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index >= _feedItems.length) {
                                      return _buildLoadMoreIndicator();
                                    }

                                    final item = _feedItems[index];
                                    final track2d =
                                        _buildTrack2dFromSession(item.session);
                                    return _ActivityCard(
                                      session: item.session,
                                      track2d: track2d,
                                      isFollowed: item.isFollowed,
                                      isNearby: item.isNearby,
                                    );
                                  },
                                ),
                        ),
                  // Disclaimer overlay
                  if (_showDisclaimer)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withAlpha(200),
                        child: Center(
                          child: _DisclaimerBanner(
                            dontShowAgain: _dontShowAgain,
                            onToggleDontShow: (value) async {
                              if (value) {
                                await _hideDisclaimer(forever: true);
                              } else {
                                setState(() {
                                  _dontShowAgain = false;
                                });
                              }
                            },
                            onClose: () => _hideDisclaimer(forever: _dontShowAgain),
                          ),
                        ),
                      ),
                    ),
                ],
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
          // Logo a sinistra
          Image.asset(
            'assets/icon/allrspulselogoo.png',
            height: 32,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          // Attività recenti + Beta a destra
          Text(
            'Attività recenti',
            style: TextStyle(
              fontSize: 12,
              color: kMutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kPulseColor.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kPulseColor.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kPulseColor,
                    boxShadow: [
                      BoxShadow(
                        color: kPulseColor.withAlpha(150),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'BETA',
                  style: TextStyle(
                    fontSize: 10,
                    color: kPulseColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
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
          // Animated track icon
          AnimatedBuilder(
            animation: _rotateController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotateController.value * 2 * math.pi,
                child: child,
              );
            },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          kBrandColor.withAlpha(60),
                          kBrandColor.withAlpha(20),
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
                        border: Border.all(color: kBrandColor.withAlpha(100), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: kBrandColor.withAlpha(60),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(Icons.flag_rounded, color: kBrandColor, size: 24),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          // Loading text with animation
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: 0.5 + (_pulseAnimation.value - 0.8) * 1.25,
                child: child,
              );
            },
            child: const Text(
              'Caricamento feed...',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Animated dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final delay = index * 0.2;
                  final value = ((_pulseController.value + delay) % 1.0);
                  final opacity = (math.sin(value * math.pi)).clamp(0.3, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBrandColor.withAlpha((opacity * 255).toInt()),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(24),
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
                mainAxisSize: MainAxisSize.min,
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
                      child: Icon(Icons.explore_outlined, color: kBrandColor, size: 24),
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
                    'Segui altri piloti o aspetta sessioni vicine a te',
                    style: TextStyle(
                      fontSize: 13,
                      color: kMutedColor,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: kMutedColor.withAlpha(20),
                      border: Border.all(color: kMutedColor.withAlpha(40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe_down, color: kMutedColor, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Scorri per aggiornare',
                          style: TextStyle(
                            fontSize: 12,
                            color: kMutedColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(kBrandColor),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Caricamento...',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
    DISCLAIMER BANNER
============================================================ */

class _DisclaimerBanner extends StatelessWidget {
  final bool dontShowAgain;
  final ValueChanged<bool> onToggleDontShow;
  final VoidCallback onClose;

  const _DisclaimerBanner({
    required this.dontShowAgain,
    required this.onToggleDontShow,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      constraints: const BoxConstraints(maxWidth: 500),
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
        border: Border.all(color: kBrandColor.withAlpha(100), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(200),
            blurRadius: 32,
            spreadRadius: 8,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: kBrandColor.withAlpha(40),
            blurRadius: 24,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        ),
                        border: Border.all(color: kBrandColor.withAlpha(80)),
                      ),
                      child: const Center(
                        child: Icon(Icons.shield_outlined, color: kBrandColor, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Avviso responsabilità',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: kFgColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withAlpha(20)),
                        ),
                        child: const Icon(Icons.close, color: kMutedColor, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: const Text(
                    'RaceSense non è progettata per gare illecite. '
                    'Usa l\'app solo in contesti sicuri e legali: non ci assumiamo responsabilità '
                    'per usi impropri o conseguenze di qualsiasi tipo.',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => onToggleDontShow(!dontShowAgain),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: dontShowAgain
                          ? kBrandColor.withAlpha(15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: dontShowAgain
                            ? kBrandColor.withAlpha(80)
                            : const Color(0xFF2A2A2A),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: dontShowAgain ? kBrandColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: dontShowAgain ? kBrandColor : kMutedColor,
                              width: 2,
                            ),
                          ),
                          child: dontShowAgain
                              ? const Icon(Icons.check, size: 14, color: Colors.black)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Non mostrare più questo messaggio',
                            style: TextStyle(
                              color: kFgColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================================================
    ACTIVITY CARD - Premium Style
============================================================ */

class _ActivityCard extends StatelessWidget {
  final SessionModel session;
  final List<Offset> track2d;
  final bool isFollowed;
  final bool isNearby;

  const _ActivityCard({
    required this.session,
    required this.track2d,
    this.isFollowed = false,
    this.isNearby = false,
  });

  String _timeAgo() {
    final now = DateTime.now();
    final diff = now.difference(session.dateTime);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min fa';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} h fa';
    } else {
      final days = diff.inDays;
      return '$days g fa';
    }
  }

  String _formatLap(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pilotName = session.driverFullName;
    final pilotTag = session.driverUsername;
    final circuitName = session.trackName;
    final city = session.location;
    final bestLapText = session.bestLap != null ? _formatLap(session.bestLap!) : '--:--';
    final laps = session.lapCount;
    final distanceKm = session.distanceKm;
    final formattedDate = DateFormat('dd MMM yyyy').format(session.dateTime);
    final formattedTime = DateFormat('HH:mm').format(session.dateTime);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pushNamed(
            ActivityDetailPage.routeName,
            arguments: session,
          );
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
                color: Colors.black.withAlpha(80),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----- HEADER PILOTA -----
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    _AvatarUser(userId: session.userId),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pilotName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: kFgColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '@$pilotTag',
                                style: TextStyle(
                                  color: kMutedColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: kMutedColor.withAlpha(100),
                                ),
                              ),
                              Text(
                                _timeAgo(),
                                style: TextStyle(
                                  color: kMutedColor.withAlpha(180),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Badges column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isFollowed)
                          _buildBadge('Seguito', Icons.star, kBrandColor),
                        if (isNearby)
                          Padding(
                            padding: EdgeInsets.only(top: isFollowed ? 6 : 0),
                            child: _buildBadge('Vicino', Icons.location_on, kPulseColor),
                          ),
                        if (session.usedBleDevice)
                          Padding(
                            padding: EdgeInsets.only(top: (isFollowed || isNearby) ? 6 : 0),
                            child: _buildBadge('BLE', Icons.bluetooth_connected, const Color(0xFFFF9500)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ----- TRACK VISUAL - Premium Style -----
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2A2A2A), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.2,
                        colors: [
                          const Color(0xFF0F1015),
                          const Color(0xFF080A0E),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Track visualization
                        CustomPaint(
                          painter: _PremiumTrackPainter(path: track2d),
                          child: const SizedBox.expand(),
                        ),
                        // Gradient overlay bottom
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFF080A0E).withAlpha(250),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Circuit info overlay
                        Positioned(
                          bottom: 14,
                          left: 14,
                          right: 14,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      circuitName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: kFgColor,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.location_on, color: kMutedColor, size: 12),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            city,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: kMutedColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Best lap badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: LinearGradient(
                                    colors: [
                                      kPulseColor.withAlpha(40),
                                      kPulseColor.withAlpha(20),
                                    ],
                                  ),
                                  border: Border.all(color: kPulseColor.withAlpha(120), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPulseColor.withAlpha(50),
                                      blurRadius: 16,
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.timer, color: kPulseColor, size: 16),
                                    const SizedBox(height: 4),
                                    Text(
                                      bestLapText,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: kPulseColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'BEST',
                                      style: TextStyle(
                                        fontSize: 8,
                                        letterSpacing: 0.8,
                                        color: kPulseColor.withAlpha(180),
                                        fontWeight: FontWeight.w800,
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
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ----- STATS ROW -----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(child: _buildStatChip(Icons.loop, '${laps}', 'Giri', const Color(0xFF29B6F6))),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatChip(Icons.route, '${distanceKm.toStringAsFixed(1)} km', 'Distanza', const Color(0xFF00E676))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LikeStatChip(session: session),
                    ),
                  ],
                ),
              ),

              // ----- FOOTER -----
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      ),
    );
  }

  Widget _buildBadge(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withAlpha(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color.withAlpha(180),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

}

/* ============================================================
    LIKE STAT CHIP - Widget separato per gestire i like
============================================================ */

class _LikeStatChip extends StatefulWidget {
  final SessionModel session;

  const _LikeStatChip({required this.session});

  @override
  State<_LikeStatChip> createState() => _LikeStatChipState();
}

class _LikeStatChipState extends State<_LikeStatChip> {
  final EngagementService _engagementService = EngagementService();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFF6B6B);

    return StreamBuilder<bool>(
      stream: _engagementService.watchLikeStatus(widget.session.sessionId),
      initialData: false,
      builder: (context, likeSnapshot) {
        final isLiked = likeSnapshot.data ?? false;

        return StreamBuilder<int>(
          stream: _engagementService.watchSessionLikesCount(widget.session.sessionId),
          initialData: widget.session.likesCount,
          builder: (context, countSnapshot) {
            final likesCount = countSnapshot.data ?? widget.session.likesCount;

            return GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                await _engagementService.toggleLike(widget.session.sessionId);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isLiked ? color.withAlpha(30) : color.withAlpha(12),
                  border: Border.all(
                    color: isLiked ? color : color.withAlpha(50),
                    width: isLiked ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: color,
                      size: 16,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$likesCount',
                      style: const TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Like',
                      style: TextStyle(
                        color: color.withAlpha(180),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/* ============================================================
    AVATAR
============================================================ */

class _AvatarUser extends StatelessWidget {
  final String userId;

  const _AvatarUser({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String?>>(
      future: _getUserData(),
      builder: (context, snapshot) {
        final userData = snapshot.data ?? {'initials': 'US', 'profileImageUrl': null};
        final initials = userData['initials'] ?? 'US';
        final profileImageUrl = userData['profileImageUrl'];

        return ProfileAvatar(
          profileImageUrl: profileImageUrl,
          userTag: initials,
          size: 44,
          borderWidth: 2,
          showGradientBorder: true,
        );
      },
    );
  }

  Future<Map<String, String?>> _getUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return {'initials': 'US', 'profileImageUrl': null};

      final data = doc.data();
      final fullName = data?['fullName'] as String? ?? 'User';
      final profileImageUrl = data?['profileImageUrl'] as String?;

      final nameParts = fullName.split(' ');
      String initials;

      if (nameParts.length >= 2 &&
          nameParts[0].isNotEmpty &&
          nameParts[1].isNotEmpty) {
        initials = nameParts[0][0].toUpperCase() + nameParts[1][0].toUpperCase();
      } else if (nameParts.isNotEmpty && nameParts[0].length >= 2) {
        initials = nameParts[0].substring(0, 2).toUpperCase();
      } else {
        initials = 'US';
      }

      return {'initials': initials, 'profileImageUrl': profileImageUrl};
    } catch (e) {
      return {'initials': 'US', 'profileImageUrl': null};
    }
  }
}

/* ============================================================
    PREMIUM TRACK PAINTER
============================================================ */

class _PremiumTrackPainter extends CustomPainter {
  final List<Offset> path;

  _PremiumTrackPainter({required this.path});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background with subtle grid
    final bgPaint = Paint()..color = const Color(0xFF080A0E);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Grid
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1;
    const gridCount = 8;
    final dx = size.width / gridCount;
    final dy = size.height / gridCount;
    for (int i = 1; i < gridCount; i++) {
      canvas.drawLine(Offset(dx * i, 0), Offset(dx * i, size.height), gridPaint);
      canvas.drawLine(Offset(0, dy * i), Offset(size.width, dy * i), gridPaint);
    }

    // Outer glow paint
    final glowPaint = Paint()
      ..color = kBrandColor.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    // Track shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(150)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Main track paint
    final trackPaint = Paint()
      ..color = Colors.white.withAlpha(230)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Accent paint
    final accentPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(w, h),
        [kBrandColor, kPulseColor],
      )
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (path.isNotEmpty) {
      // Calculate bounding box
      double minX = path.first.dx;
      double maxX = path.first.dx;
      double minY = path.first.dy;
      double maxY = path.first.dy;

      for (final p in path) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }

      final width = (maxX - minX).abs();
      final height = (maxY - minY).abs();

      const padding = 24.0;
      final usableW = w - 2 * padding;
      final usableH = h - 2 * padding;

      final safeWidth = width == 0 ? 1.0 : width;
      final safeHeight = height == 0 ? 1.0 : height;

      final scale = math.min(usableW / safeWidth, usableH / safeHeight);

      final centerX = (minX + maxX) / 2;
      final centerY = (minY + maxY) / 2;

      final trackPath = Path();
      final List<Offset> canvasPoints = [];

      for (int i = 0; i < path.length; i++) {
        final p = path[i];

        final cx = w / 2 + (p.dx - centerX) * scale;
        final cy = h / 2 - (p.dy - centerY) * scale;

        final c = Offset(cx, cy);
        canvasPoints.add(c);

        if (i == 0) {
          trackPath.moveTo(c.dx, c.dy);
        } else {
          trackPath.lineTo(c.dx, c.dy);
        }
      }

      // Draw layers
      canvas.drawPath(trackPath, glowPaint);
      canvas.drawPath(trackPath, shadowPaint);
      canvas.drawPath(trackPath, trackPaint);
      canvas.drawPath(trackPath, accentPaint);

      // Start/finish marker
      if (canvasPoints.isNotEmpty) {
        final startPoint = canvasPoints.first;

        // Outer glow
        final startGlowPaint = Paint()
          ..color = kBrandColor.withAlpha(80)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(startPoint, 10, startGlowPaint);

        // Inner circle
        final startPaint = Paint()
          ..color = kBrandColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(startPoint, 5, startPaint);

        // White border
        final startBorderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(startPoint, 5, startBorderPaint);
      }
    } else {
      // Fallback track
      final basePath = Path();
      basePath.moveTo(w * 0.18, h * 0.80);
      basePath.quadraticBezierTo(w * 0.05, h * 0.40, w * 0.32, h * 0.18);
      basePath.quadraticBezierTo(w * 0.70, h * 0.02, w * 0.86, h * 0.30);
      basePath.quadraticBezierTo(w * 0.98, h * 0.58, w * 0.56, h * 0.86);
      basePath.quadraticBezierTo(w * 0.34, h * 0.97, w * 0.18, h * 0.80);

      canvas.drawPath(basePath, glowPaint);
      canvas.drawPath(basePath, shadowPaint);
      canvas.drawPath(basePath, trackPaint);
      canvas.drawPath(basePath, accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumTrackPainter oldDelegate) {
    return oldDelegate.path != path;
  }
}
