import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import 'search_user_profile_page.dart';
import '../models/session_model.dart';
import 'search_track_sessions_page.dart';
import '../services/follow_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Pagina Cerca - Mock UI (solo grafica, nessuna logica)
/// Funzionalità future:
/// - Ricerca utenti
/// - Ricerca circuiti
/// - Filtro per paese
/// - Mappa con tutti i circuiti della piattaforma (OpenStreetMap)
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FollowService _followService = FollowService();

  Timer? _debounce;
  String _query = '';
  String? _currentUserId;

  bool _loadingUsers = false;
  bool _loadingCircuits = false;
  String? _usersError;
  String? _circuitsError;

  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _topUsers = [];
  Map<String, List<SessionModel>> _circuitGroups = {};
  List<String> _circuitOrder = [];
  Map<String, List<SessionModel>> _topCircuitGroups = {};
  List<String> _topCircuitOrder = [];

  Set<String> _followingIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initCurrentUser();
    _loadTopUsers();
    _loadTopCircuits();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _currentUserId = user?.uid;
    });
    await _loadFollowingIds();
  }

  Future<void> _loadFollowingIds() async {
    if (_currentUserId == null) return;
    final ids = await _followService.getFollowingIds(limit: 300);
    if (mounted) {
      setState(() {
        _followingIds = ids;
      });
    }
  }

  Future<void> _loadTopUsers() async {
    try {
      final snap = await _firestore
          .collection('users')
          .orderBy('stats.followerCount', descending: true)
          .limit(3)
          .get();
      setState(() {
        _topUsers = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    } catch (_) {
      // silenzioso: top utenti opzionale
    }
  }

  Future<void> _loadTopCircuits() async {
    try {
      final snap = await _firestore
          .collection('sessions')
          .where('isPublic', isEqualTo: true)
          .orderBy('dateTime', descending: true)
          .limit(200)
          .get();
      final sessions = snap.docs
          .map((d) => SessionModel.fromFirestore(d.id, d.data()))
          .toList();

      final groups = <String, List<SessionModel>>{};
      for (final s in sessions) {
        groups.putIfAbsent(s.trackName, () => []).add(s);
      }

      final ordered = groups.keys.toList()
        ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
      setState(() {
        _topCircuitGroups = groups;
        _topCircuitOrder = ordered.take(3).toList();
      });
    } catch (_) {
      // silenzioso: top circuiti opzionale
    }
  }

  @override
  Widget build(BuildContext context) {
    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Search bar
          _buildSearchBar(),

          // Tabs
          _buildTabs(),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildCircuitsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Row(
        children: [
          const Text(
            'Ricerca',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(
              fontSize: 16, color: kFgColor, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Cerca utenti o circuiti...',
            hintStyle: TextStyle(
                color: kMutedColor.withAlpha(130), fontWeight: FontWeight.w500),
            prefixIcon: const Icon(Icons.search, color: kBrandColor, size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: kMutedColor, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _onQueryChanged('');
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF1A1A20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: kLineColor, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: kLineColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: kBrandColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          onChanged: (value) {
            _onQueryChanged(value);
          },
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A20).withAlpha(255),
            const Color(0xFF0F0F15).withAlpha(255),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLineColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              kBrandColor.withAlpha(40),
              kBrandColor.withAlpha(25),
            ],
          ),
          border: Border.all(color: kBrandColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: kBrandColor.withAlpha(60),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        labelColor: kBrandColor,
        unselectedLabelColor: kMutedColor,
        labelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'PILOTI'),
          Tab(text: 'CIRCUITI'),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    if (_query.length < 2) {
      return _buildSearchHint(
        title: 'Top 3 piloti',
        subtitle: 'Top 3 piloti più seguiti della piattaforma.',
        placeholderList:
            _topUsers.map((u) => _buildUserCard(u)).take(3).toList(),
      );
    }

    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    print(_usersError);
    if (_usersError != null) {
      return _buildErrorBox(_usersError!);
    }

    if (_userResults.isEmpty) {
      return _buildEmptyState('Nessun utente trovato con "$_query".');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: _userResults.map((user) => _buildUserCard(user)).toList(),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final fullName = user['fullName'] ?? user['name'] ?? '';
    final stats = user['stats'] as Map<String, dynamic>? ?? {};
    final totalSessions = stats['totalSessions'] ?? user['sessions'] ?? 0;
    final totalDistance =
        (stats['totalDistanceKm'] ?? user['distance'] ?? 0).toString();
    final initials = user['initials'] ??
        (fullName.isNotEmpty ? fullName[0].toUpperCase() : '?');
    final userId = user['id']?.toString();
    final followerCount = stats['followerCount'] ?? 0;
    final followingCount = stats['followingCount'] ?? 0;
    final isMe = _currentUserId != null && _currentUserId == userId;
    final isFollowing = userId != null && _followingIds.contains(userId);

    return InkWell(
      onTap: (userId != null && userId.isNotEmpty)
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchUserProfilePage(
                    userId: userId,
                    fullName: fullName,
                  ),
                ),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A20).withAlpha(255),
              const Color(0xFF0F0F15).withAlpha(255),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kLineColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(140),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(60),
                    kPulseColor.withAlpha(40)
                  ],
                ),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF1A1A20),
                child: Text(
                  initials.toString(),
                  style: const TextStyle(
                    color: kBrandColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: kFgColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color.fromRGBO(255, 255, 255, 0.05),
                          border: Border.all(color: kLineColor.withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions_run,
                                color: kBrandColor, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              '$totalSessions',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: kFgColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color.fromRGBO(255, 255, 255, 0.05),
                          border: Border.all(color: kLineColor.withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people,
                                color: kPulseColor, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              '$followerCount',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: kFgColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (!isMe)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
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
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: userId == null
                        ? null
                        : () async {
                            if (_currentUserId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Devi essere loggato per seguire.'),
                                ),
                              );
                              return;
                            }
                            try {
                              if (isFollowing) {
                                await _followService.unfollow(userId!);
                                setState(() {
                                  _followingIds.remove(userId);
                                  if (user['stats'] != null) {
                                    final s = Map<String, dynamic>.from(
                                        user['stats'] as Map);
                                    s['followerCount'] =
                                        (s['followerCount'] ?? 0) - 1;
                                    user['stats'] = s;
                                  }
                                });
                              } else {
                                await _followService.follow(userId!);
                                setState(() {
                                  _followingIds.add(userId);
                                  if (user['stats'] != null) {
                                    final s = Map<String, dynamic>.from(
                                        user['stats'] as Map);
                                    s['followerCount'] =
                                        (s['followerCount'] ?? 0) + 1;
                                    user['stats'] = s;
                                  }
                                });
                              }
                            } catch (e) {
                              print('❌ Follow toggle error: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Errore: $e'),
                                  backgroundColor: kErrorColor,
                                ),
                              );
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFollowing ? Icons.check : Icons.person_add,
                            color: isFollowing ? kMutedColor : kBrandColor,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isFollowing ? 'Segui' : 'Segui',
                            style: TextStyle(
                              color: isFollowing ? kMutedColor : kBrandColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircuitsTab() {
    if (_query.length < 2) {
      final widgets = _topCircuitOrder
          .map((name) => _buildCircuitGroupCard(
                name,
                _topCircuitGroups[name] ?? [],
              ))
          .toList();
      return _buildSearchHint(
        title: 'Top 3 circuiti',
        subtitle: 'Lista dei circuiti con più sessioni tracciate.',
        placeholderList: widgets,
      );
    }

    if (_loadingCircuits) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_circuitsError != null) {
      return _buildErrorBox(_circuitsError!);
    }

    if (_circuitGroups.isEmpty) {
      return _buildEmptyState('Nessun circuito trovato con "$_query".');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: _circuitOrder
          .map((name) => _buildCircuitGroupCard(
                name,
                _circuitGroups[name]!,
              ))
          .toList(),
    );
  }

  Widget _buildCircuitGroupCard(String trackName, List<SessionModel> sessions) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final location = sessions.first.location;
    final totalSessions = sessions.length;
    final bestLap = sessions
        .where((s) => s.bestLap != null)
        .map((s) => s.bestLap!)
        .fold<Duration?>(null, (prev, d) {
      if (prev == null) return d;
      return d < prev ? d : prev;
    });
    final avgDistance = sessions.isNotEmpty
        ? sessions.map((s) => s.distanceKm).reduce((a, b) => a + b) /
            sessions.length
        : 0.0;
    final bestLapStr =
        bestLap != null ? _formatBestLap(bestLap.inMilliseconds) : '—';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchTrackSessionsPage(
              trackName: trackName,
              preloaded: sessions,
            ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with gradient overlay
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      // gradient: LinearGradient(
                      //   colors: [
                      //     const Color.fromARGB(67, 255, 0, 0).withAlpha(40),
                      //     const Color.fromARGB(67, 255, 0, 0).withAlpha(40),
                      //   ],
                      // ),
                      border: Border.all(color: kPulseColor, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: kPulseColor.withAlpha(80),
                          blurRadius: 0,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on,
                        color: kPulseColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kFgColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.place,
                                size: 13, color: kMutedColor),
                            const SizedBox(width: 4),
                            Text(
                              location,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kMutedColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: kMutedColor, size: 24),
                ],
              ),
            ),

            // Stats section
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
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
                    _buildCircuitStat('Sessioni', totalSessions.toString()),
                    Container(width: 1, height: 45, color: kLineColor),
                    _buildCircuitStat(
                        'Avg km', '${avgDistance.toStringAsFixed(1)}'),
                    Container(width: 1, height: 45, color: kLineColor),
                    _buildCircuitStat('Record', bestLapStr),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mock/placeholder card for circuiti statici
  Widget _buildCircuitCard(Map<String, dynamic> circuit) {
    final name = (circuit['name'] ?? circuit['trackName'] ?? '').toString();
    final location = (circuit['location'] ?? '-').toString();
    final length =
        (circuit['length'] ?? circuit['estimatedLength'] ?? '—').toString();
    final sessions =
        (circuit['sessions'] ?? circuit['sessionCount'] ?? '—').toString();
    final record =
        _formatBestLap(circuit['record'] ?? circuit['bestLap'] ?? '—');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBrandColor.withOpacity(0.3)),
                ),
                child: const Icon(Icons.track_changes,
                    color: kBrandColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 12, color: kMutedColor),
                        const SizedBox(width: 4),
                        Text(
                          location,
                          style:
                              const TextStyle(fontSize: 12, color: kMutedColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCircuitStat('Lunghezza', length),
              _buildCircuitStat('Sessioni', sessions),
              _buildCircuitStat('Record', record),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color.fromARGB(255, 255, 255, 255),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: kMutedColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCountryCard(Map<String, dynamic> country) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF10121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        children: [
          // Flag placeholder
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kBrandColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                country['flag'],
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  country['name'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${country['circuits']} circuiti · ${country['users']} utenti',
                  style: const TextStyle(fontSize: 12, color: kMutedColor),
                ),
              ],
            ),
          ),

          const Icon(Icons.arrow_forward_ios, size: 16, color: kMutedColor),
        ],
      ),
    );
  }

  // Helper UI e ricerca
  Widget _buildSearchHint({
    required String title,
    required String subtitle,
    List<Widget> placeholderList = const [],
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: kMutedColor),
        ),
        if (placeholderList.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...placeholderList,
        ],
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: kMutedColor, size: 44),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMutedColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kErrorColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kErrorColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: kErrorColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: kErrorColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBestLap(dynamic raw) {
    if (raw == null) return '—';
    if (raw is String) return raw;
    if (raw is int) {
      final d = Duration(milliseconds: raw);
      final minutes = d.inMinutes;
      final seconds = d.inSeconds % 60;
      final millis = (d.inMilliseconds % 1000) ~/ 10;
      return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
    }
    if (raw is double) return raw.toStringAsFixed(2);
    return raw.toString();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value.trim();
    });

    if (_query.length < 2) {
      setState(() {
        _userResults = [];
        _circuitGroups = {};
        _circuitOrder = [];
        _usersError = null;
        _circuitsError = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(_query);
    });
  }

  Future<void> _runSearch(String term) async {
    await Future.wait(<Future<void>>[
      _searchUsers(term),
      _searchCircuits(term),
    ]);
  }

  Future<void> _searchUsers(String term) async {
    final termLower = term.toLowerCase();
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('users')
          .where('searchTokens', arrayContains: termLower)
          .limit(20);

      final snap = await q.get();

      List<Map<String, dynamic>> results =
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      if (results.isEmpty) {
        // fallback a startAt/endAt case-sensitive ma filtrato in locale
        final alt = await _firestore
            .collection('users')
            .orderBy('fullName')
            .startAt([term])
            .endAt(['$term\uf8ff'])
            .limit(20)
            .get();
        results = alt.docs
            .map((d) => {'id': d.id, ...d.data()})
            .where((u) => (u['fullName'] ?? '')
                .toString()
                .toLowerCase()
                .contains(termLower))
            .toList();
      }

      setState(() {
        _userResults = results;
      });
    } catch (e) {
      setState(() {
        _usersError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
      }
    }
  }

  Future<void> _searchCircuits(String term) async {
    final termLower = term.toLowerCase();
    setState(() {
      _loadingCircuits = true;
      _circuitsError = null;
    });
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('sessions')
          .where('isPublic', isEqualTo: true)
          .orderBy('trackNameLower')
          .startAt([termLower]).endAt(['$termLower\uf8ff']).limit(80);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await q.get();
      } on FirebaseException {
        // fallback se manca il campo indicizzato
        snap = await _firestore
            .collection('sessions')
            .where('isPublic', isEqualTo: true)
            .orderBy('trackName')
            .startAt([term])
            .endAt(['$term\uf8ff'])
            .limit(80)
            .get();
      }

      final results = snap.docs
          .map((d) => SessionModel.fromFirestore(d.id, d.data()))
          .where((s) => s.trackName.toLowerCase().contains(termLower))
          .toList();

      final groups = <String, List<SessionModel>>{};
      for (final s in results) {
        groups.putIfAbsent(s.trackName, () => []).add(s);
      }

      setState(() {
        _circuitGroups = groups;
        _circuitOrder = groups.keys.toList();
      });
    } catch (e) {
      setState(() {
        _circuitsError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCircuits = false;
        });
      }
    }
  }
}
