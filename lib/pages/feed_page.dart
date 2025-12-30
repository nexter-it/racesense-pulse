import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import 'activity_detail_page.dart';

import '../services/session_service.dart';
import '../services/follow_service.dart';
import '../services/feed_cache_service.dart';
import '../models/session_model.dart';

class PulseActivity {
  final String id;
  final String pilotName;
  final String pilotTag;
  final String circuitName;
  final String city;
  final String country;
  final String bestLap;
  final String sessionType; // es: "Gara", "Practice"
  final int laps;
  final DateTime date;
  final bool isPb; // personal best
  final double distanceKm;
  final List<Offset> track2d;

  const PulseActivity({
    required this.id,
    required this.pilotName,
    required this.pilotTag,
    required this.circuitName,
    required this.city,
    required this.country,
    required this.bestLap,
    required this.sessionType,
    required this.laps,
    required this.date,
    required this.isPb,
    required this.distanceKm,
    required this.track2d,
  });
}

List<Offset> _generateFakeTrack({
  double scaleX = 120,
  double scaleY = 80,
  int samplesPerSegment = 12,
  double rotationDeg = 0,
}) {
  final List<Offset> result = [];

  // Layout normalizzato del circuito (rettilinei + curve)
  // coordinate in [-1, 1]
  final List<Offset> base = [
    const Offset(-1.0, -0.1), // start rettilineo principale
    const Offset(-0.3, -0.6), // curva 1
    const Offset(0.3, -0.65), // breve rettilineo alto
    const Offset(0.9, -0.2), // fine rettilineo alto curva 2
    const Offset(1.0, 0.2), // discesa lato destro
    const Offset(0.4, 0.7), // curva bassa destra
    const Offset(-0.2, 0.6), // rettilineo basso
    const Offset(-0.9, 0.2), // curva bassa sinistra
    const Offset(-1.0, -0.1), // chiusura vicino allo start
  ];

  final rot = rotationDeg * math.pi / 180.0;
  final cosR = math.cos(rot);
  final sinR = math.sin(rot);

  for (int i = 0; i < base.length - 1; i++) {
    final p0 = base[i];
    final p1 = base[i + 1];

    for (int j = 0; j < samplesPerSegment; j++) {
      final t = j / samplesPerSegment;

      // interpolazione lineare tra i due punti (rettilineo/curva spezzata)
      final nx = p0.dx + (p1.dx - p0.dx) * t;
      final ny = p0.dy + (p1.dy - p0.dy) * t;

      // scala
      double x = nx * scaleX;
      double y = ny * scaleY;

      // piccola irregolarità per evitare forme troppo "perfette"
      final noise = (i.isEven ? 1 : -1) * 0.03;
      x += noise * scaleX * (math.sin(t * math.pi));
      y += noise * scaleY * (math.cos(t * math.pi));

      // rotazione globale
      final xr = x * cosR - y * sinR;
      final yr = x * sinR + y * cosR;

      result.add(Offset(xr, yr));
    }
  }

  return result;
}

/// Converte il displayPath salvato nel doc sessione in una path 2D per il painter.
/// Usa lat come Y e lon come X, la scala la gestisce già il painter.
List<Offset> _buildTrack2dFromSession(SessionModel session) {
  final raw = session.displayPath;

  // se non c'è path o è vuota → fallback estetico
  if (raw == null || raw.isEmpty) {
    return _generateFakeTrack(rotationDeg: 0);
  }

  final points = <Offset>[];

  for (final m in raw) {
    final lat = m['lat'];
    final lon = m['lon'];

    if (lat != null && lon != null) {
      points.add(Offset(lon, lat)); // X = lon, Y = lat
    }
  }

  // se per qualche motivo abbiamo meno di 2 punti, facciamo comunque fallback
  if (points.length < 2) {
    return _generateFakeTrack(rotationDeg: 0);
  }

  return points;
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

class _FeedPageState extends State<FeedPage> {
  final SessionService _sessionService = SessionService();
  final FollowService _followService = FollowService();
  final FeedCacheService _cacheService = FeedCacheService();
  final ScrollController _scrollController = ScrollController();

  final List<_FeedSessionItem> _feedItems = [];
  Set<String> _followingIds = {};
  Position? _userPosition;
  String? _locationError;

  DocumentSnapshot? _lastDoc;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isRefreshing = false;

  static const int _pageSize = 10;
  static const int _fetchBatchSize =
      25; // batch più ampio per filtrare senza troppe read
  static const double _nearbyRadiusKm = 80;

  bool _showDisclaimer = false;
  bool _dontShowAgain = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDisclaimer();
    _bootstrapFeed();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Bootstrap feed: carica da cache se disponibile, altrimenti da Firebase
  Future<void> _bootstrapFeed() async {
    setState(() => _isLoading = true);
    try {
      // Ottieni l'ID dell'utente corrente per filtrare le proprie sessioni
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // Prima prova a caricare dalla cache
      if (_cacheService.hasCachedData) {
        print('📦 Caricamento feed da cache locale...');
        _followingIds = _cacheService.getCachedFollowingIds();
        _userPosition = await _getUserLocation();

        final cachedSessions = _cacheService.getCachedFeed();
        _feedItems.clear();
        for (final session in cachedSessions) {
          // Salta le proprie sessioni - non devono apparire nel feed
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
        _hasMore = cachedSessions.length >= _pageSize;

        print('✅ Feed caricato da cache: ${_feedItems.length} sessioni');

        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Nessuna cache: carica da Firebase
      print('🔄 Nessuna cache, caricamento da Firebase...');
      await _refreshFromFirebase();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Refresh completo da Firebase (pull-to-refresh)
  Future<void> _refreshFromFirebase() async {
    setState(() => _isRefreshing = true);
    try {
      // Ottieni l'ID dell'utente corrente per filtrare le proprie sessioni
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // Carica following ids e posizione in parallelo
      final results = await Future.wait([
        _cacheService.refreshFollowingIds(limit: 200),
        _getUserLocation(),
      ]);

      _followingIds = results[0] as Set<String>;
      _userPosition = results[1] as Position?;

      // Refresh feed da Firebase con cache
      final sessions = await _cacheService.refreshFeed(
        followingIds: _followingIds,
        isNearbyFilter: _isNearby,
        pageSize: _pageSize,
      );

      _feedItems.clear();
      _lastDoc = null;
      for (final session in sessions) {
        // Salta le proprie sessioni - non devono apparire nel feed
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

      // Segna che il primo caricamento è completato
      _cacheService.markFirstLoadComplete();
    } finally {
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
      _lastDoc = null;
      _hasMore = true;
    }
    if (!_hasMore) return;

    if (!mounted) return;
    setState(() => _isLoadingMore = true);
    int added = 0;
    int attempts = 0;

    // Ottieni l'ID dell'utente corrente per filtrare le proprie sessioni
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    try {
      while (added < _pageSize && _hasMore && attempts < 4) {
        attempts++;
        final snap = await _sessionService.fetchSessionsPage(
          limit: _fetchBatchSize,
          startAfter: _lastDoc,
        );

        if (snap.docs.isEmpty) {
          _hasMore = false;
          break;
        }

        _lastDoc = snap.docs.last;

        for (final doc in snap.docs) {
          final session = SessionModel.fromFirestore(doc.id, doc.data());

          // Salta le proprie sessioni - non devono apparire nel feed
          if (currentUserId != null && session.userId == currentUserId) {
            continue;
          }

          final isFollowed = _followingIds.contains(session.userId);
          final isNearby = _isNearby(session);
          if (!isFollowed && !isNearby) continue;

          final alreadyAdded = _feedItems
              .any((item) => item.session.sessionId == session.sessionId);
          if (alreadyAdded) continue;

          _feedItems.add(_FeedSessionItem(
            session: session,
            isFollowed: isFollowed,
            isNearby: isNearby,
          ));
          added++;

          if (added >= _pageSize) break;
        }

        if (snap.docs.length < _fetchBatchSize) {
          _hasMore = false;
        }
      }

      if (added == 0 || (added < _pageSize && attempts >= 4)) {
        _hasMore = false;
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
    return PulseBackground(
      withTopPadding: true,
      child: Stack(
        children: [
          Column(
            children: [
              const _TopBar(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                child: Row(
                  children: const [
                    Text(
                      'Attività recenti',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color.fromARGB(255, 255, 255, 255),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (_locationError != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    _locationError!,
                    style: const TextStyle(color: kMutedColor, fontSize: 12),
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(kBrandColor),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshFromFirebase,
                        color: kBrandColor,
                        backgroundColor: kBgColor,
                        child: _feedItems.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.4,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Nessuna sessione da piloti che segui o vicina a te',
                                              style: TextStyle(color: kMutedColor),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Scorri verso il basso per aggiornare',
                                              style: TextStyle(
                                                color: kMutedColor.withAlpha(150),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8)
                                    .copyWith(bottom: 24),
                                itemCount: _feedItems.length +
                                    (_isLoadingMore && _hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _feedItems.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                              kBrandColor),
                                        ),
                                      ),
                                    );
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
              ),
            ],
          ),
          // Overlay scuro e banner disclaimer centrato
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
    );
  }
}

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(220),
            blurRadius: 32,
            spreadRadius: 8,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: kBrandColor.withAlpha(60),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1A1A1A).withAlpha(250),
                  const Color(0xFF0F0F0F).withAlpha(250),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: kBrandColor.withAlpha(100),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kBrandColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kBrandColor.withAlpha(100)),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: kBrandColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Avviso responsabilità',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: kFgColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.close, color: kMutedColor, size: 20),
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(80),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: kLineColor.withAlpha(100),
                    ),
                  ),
                  child: const Text(
                    'RaceSense non è progettata per gare illecite. '
                    'Usa l\'app solo in contesti sicuri e legali: non ci assumiamo responsabilità '
                    'per usi impropri o conseguenze di qualsiasi tipo.',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => onToggleDontShow(!dontShowAgain),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: dontShowAgain
                          ? kBrandColor.withAlpha(20)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: dontShowAgain
                            ? kBrandColor.withAlpha(100)
                            : kLineColor.withAlpha(80),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: dontShowAgain
                                ? kBrandColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: dontShowAgain ? kBrandColor : kMutedColor,
                              width: 2,
                            ),
                          ),
                          child: dontShowAgain
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.black,
                                )
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
    TOP BAR
============================================================ */

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Row(
        children: [
          const _PremiumLogoTitle(),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(142, 133, 255, 0.18),
              borderRadius: BorderRadius.circular(999),
              // border: Border.all(
              //   color: kPulseColor.withOpacity(0.9),
              //   width: 1.2,
              // ),
              boxShadow: [
                BoxShadow(
                  color: kPulseColor.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kPulseColor,
                    boxShadow: [
                      BoxShadow(
                        color: kPulseColor.withOpacity(0.8),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'BETA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
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

class _PremiumLogoTitle extends StatelessWidget {
  const _PremiumLogoTitle();

  @override
  Widget build(BuildContext context) {
    const neon = Color(0xFFCCFF00);
    const lilac = Color(0xFFB6B0F5);

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 260;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [
                  Color.fromRGBO(26, 56, 36, 0.5),
                  Color.fromRGBO(18, 18, 26, 0.7),
                  Color.fromRGBO(41, 26, 63, 0.5),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border.all(color: kLineColor.withOpacity(0.7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Image.asset(
              'assets/icon/allrspulselogoo.png',
              height: 32,
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }
}

class _GradientText extends StatelessWidget {
  final String text;
  final LinearGradient gradient;
  final Color shadowColor;

  const _GradientText({
    required this.text,
    required this.gradient,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: Colors.white,
          shadows: [
            Shadow(
              color: shadowColor,
              blurRadius: 14,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: shadowColor.withOpacity(0.35),
              blurRadius: 28,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
    ACTIVITY CARD
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

  @override
  Widget build(BuildContext context) {
    final sessionType = 'Sessione';
    final pilotName = session.driverFullName;
    final pilotTag = session.driverUsername;

    final circuitName = session.trackName;
    final city = session.location;
    final bestLapText =
        session.bestLap != null ? _formatLap(session.bestLap!) : '--:--';
    final laps = session.lapCount;
    final distanceKm = session.distanceKm;
    final isPb = false; // se un domani salvi isPb nella sessione, cambialo qui.

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.of(context).pushNamed(
              ActivityDetailPage.routeName,
              arguments: session,
            );
          },
          child: Container(
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
              border: Border.all(
                color: kLineColor,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(160),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
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
                                fontSize: 16,
                                color: kFgColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  '@$pilotTag',
                                  style: const TextStyle(
                                    color: kMutedColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '• ${_timeAgo()}',
                                  style: const TextStyle(
                                    color: kMutedColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFollowed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: kBrandColor.withAlpha(30),
                                border:
                                    Border.all(color: kBrandColor, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.star,
                                      color: kBrandColor, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'Seguito',
                                    style: TextStyle(
                                      color: kBrandColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isNearby)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: kPulseColor.withAlpha(30),
                                  border:
                                      Border.all(color: kPulseColor, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.location_on,
                                        color: kPulseColor, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Vicino',
                                      style: TextStyle(
                                        color: kPulseColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (session.usedBleDevice)
                            Padding(
                              padding: EdgeInsets.only(
                                  top: (isFollowed || isNearby) ? 6.0 : 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFFF9500).withAlpha(40),
                                      const Color(0xFFFF6B00).withAlpha(40),
                                    ],
                                  ),
                                  border: Border.all(
                                      color: const Color(0xFFFF9500), width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.bluetooth_connected,
                                        color: Color(0xFFFF9500), size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'BLE',
                                      style: TextStyle(
                                        color: Color(0xFFFF9500),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ----- TRACK VISUAL -----
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: kLineColor.withAlpha(180), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 180,
                      color: const Color.fromRGBO(6, 7, 12, 1),
                      child: Stack(
                        children: [
                          // Track visualization
                          CustomPaint(
                            painter: _MiniTrackPainter(
                              isPb: isPb,
                              path: track2d,
                            ),
                            child: const SizedBox.expand(),
                          ),
                          // Gradient overlay bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    const Color.fromRGBO(6, 7, 12, 1)
                                        .withAlpha(240),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Circuit info overlay
                          Positioned(
                            bottom: 12,
                            left: 12,
                            right: 12,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        circuitName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 17,
                                          color: kFgColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            color: kMutedColor,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              city,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: kMutedColor,
                                                fontSize: 13,
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
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: LinearGradient(
                                      colors: [
                                        kPulseColor.withAlpha(40),
                                        kPulseColor.withAlpha(20),
                                      ],
                                    ),
                                    border: Border.all(
                                        color: kPulseColor, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: kPulseColor.withAlpha(80),
                                        blurRadius: 12,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.timer,
                                        color: kPulseColor,
                                        size: 18,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        bestLapText,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: kPulseColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'BEST',
                                        style: TextStyle(
                                          fontSize: 9,
                                          letterSpacing: 0.8,
                                          color: kPulseColor,
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
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ----- STATS ROW -----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color.fromRGBO(255, 255, 255, 0.03),
                      border: Border.all(color: kLineColor.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          icon: Icons.flag_outlined,
                          label: 'Giri',
                          value: laps.toString(),
                        ),
                        Container(width: 1, height: 40, color: kLineColor),
                        _StatItem(
                          icon: Icons.route,
                          label: 'Distanza',
                          value: '${distanceKm.toStringAsFixed(1)} km',
                        ),
                        Container(width: 1, height: 40, color: kLineColor),
                        _StatItem(
                          icon: Icons.favorite_border,
                          label: 'Like',
                          value: session.likesCount.toString(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kBrandColor, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: kMutedColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: kFgColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

String _formatLap(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  final ms = (d.inMilliseconds % 1000) ~/ 10;
  return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
}

/* ============================================================
    AVATAR
============================================================ */

class _AvatarUser extends StatelessWidget {
  final String userId;

  const _AvatarUser({required this.userId});

  String _assetForUser() {
    final seed = userId.hashCode & 0x7fffffff;
    final idx = (math.Random(seed).nextInt(5)) + 1;
    return 'assets/images/dr$idx.png';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color.fromRGBO(10, 12, 18, 1),
        border: Border.all(color: kLineColor.withOpacity(0.5), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _assetForUser(),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return const Icon(Icons.person, color: kMutedColor);
        },
      ),
    );
  }
}

/* ============================================================
    MINI TRACK PAINTER (placeholder estetico)
============================================================ */

class _MiniTrackPainter extends CustomPainter {
  final bool isPb;
  final List<Offset> path;

  _MiniTrackPainter({
    required this.isPb,
    required this.path,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // background grid-ish
    final bgPaint = Paint()..color = const Color.fromRGBO(12, 14, 22, 1);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    const gridCount = 7;
    final dx = size.width / gridCount;
    final dy = size.height / gridCount;
    for (int i = 1; i < gridCount; i++) {
      canvas.drawLine(
          Offset(dx * i, 0), Offset(dx * i, size.height), gridPaint);
      canvas.drawLine(Offset(0, dy * i), Offset(size.width, dy * i), gridPaint);
    }

    // outer glow
    // final glowPaint = Paint()
    //   ..color = kBrandColor.withOpacity(0.45)
    //   ..style = PaintingStyle.stroke
    //   ..strokeWidth = 10
    //   ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    final trackPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final accentPaint = Paint()
      ..color = isPb ? kPulseColor : kBrandColor
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // circuito fittizio
    // se abbiamo una path, usiamola; altrimenti fallback minimale
    if (path.isNotEmpty) {
      // calcola bounding box
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

      // differenza reale in coordinate "mondo" (lat/lon)
      final width = (maxX - minX).abs();
      final height = (maxY - minY).abs();

      const padding = 18.0;
      final usableW = w - 2 * padding;
      final usableH = h - 2 * padding;

      // evita solo il caso patologico "tutti i punti identici"
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
        final cy = h / 2 - (p.dy - centerY) * scale; // inverti Y per lo schermo

        final c = Offset(cx, cy);
        canvasPoints.add(c);

        if (i == 0) {
          trackPath.moveTo(c.dx, c.dy);
        } else {
          trackPath.lineTo(c.dx, c.dy);
        }
      }

      canvas.drawPath(trackPath, trackPaint);
      canvas.drawPath(trackPath, accentPaint);

      // start/finish line approssimata sui primi punti
      if (canvasPoints.length >= 2) {
        final s = canvasPoints.first;
        final e = canvasPoints[1];
        final startPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 3;
        canvas.drawLine(s, e, startPaint);
      }

      // PB marker glow (punto circa a 1/3 del giro)
      // if (isPb && canvasPoints.length > 5) {
      //   final idx = (canvasPoints.length / 3).floor();
      //   final p = canvasPoints[idx];
      //   final pbPaint = Paint()
      //     ..color = kPulseColor.withOpacity(0.7)
      //     ..style = PaintingStyle.fill
      //     ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      //   canvas.drawCircle(p, 12, pbPaint);
      // }
    } else {
      // fallback: piccola curva standard se la path è vuota
      final basePath = Path();
      basePath.moveTo(w * 0.18, h * 0.80);
      basePath.quadraticBezierTo(w * 0.05, h * 0.40, w * 0.32, h * 0.18);
      basePath.quadraticBezierTo(w * 0.70, h * 0.02, w * 0.86, h * 0.30);
      basePath.quadraticBezierTo(w * 0.98, h * 0.58, w * 0.56, h * 0.86);
      basePath.quadraticBezierTo(w * 0.34, h * 0.97, w * 0.18, h * 0.80);

      canvas.drawPath(basePath, trackPaint);
      canvas.drawPath(basePath, accentPaint);
    }

    // start/finish line
    // final startPaint = Paint()
    //   ..color = Colors.white
    //   ..strokeWidth = 3;
    // canvas.drawLine(
    //   Offset(w * 0.20, h * 0.78),
    //   Offset(w * 0.24, h * 0.83),
    //   startPaint,
    // );

    // PB marker glow
    if (isPb) {
      final pbPaint = Paint()
        ..color = kPulseColor.withOpacity(0.7)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(Offset(w * 0.55, h * 0.32), 12, pbPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTrackPainter oldDelegate) {
    return oldDelegate.isPb != isPb;
  }
}
