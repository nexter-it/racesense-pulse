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
  Map<String, List<SessionModel>> _circuitGroups = {};
  List<String> _circuitOrder = [];

  Set<String> _followingIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initCurrentUser();
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
                _buildCountriesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text(
            'CERCA',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              // Future: filtri avanzati
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 16, color: kFgColor),
        decoration: InputDecoration(
          hintText: 'Cerca utenti, circuiti, paesi...',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
          prefixIcon: const Icon(Icons.search, color: kBrandColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: kMutedColor),
                  onPressed: () {
                    _searchController.clear();
                    _onQueryChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF0d0d0d),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kBrandColor, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (value) {
          _onQueryChanged(value);
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d0d),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kLineColor),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: const BoxDecoration(),
        labelColor: kBrandColor,
        unselectedLabelColor: kMutedColor,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'UTENTI'),
          Tab(text: 'CIRCUITI'),
          Tab(text: 'PAESI'),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    if (_query.length < 2) {
      return _buildSearchHint(
        title: 'Cerca utenti',
        subtitle: 'Digita almeno 2 caratteri per cercare per nome completo.',
        placeholderList: _mockUsers.map((u) => _buildUserCard(u)).toList(),
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF10121A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kLineColor),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: kBrandColor.withOpacity(0.2),
              child: Text(
                initials.toString(),
                style: const TextStyle(
                  color: kBrandColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
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
                    fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$totalSessions sessioni · $totalDistance km',
                    style: const TextStyle(fontSize: 12, color: kMutedColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$followerCount follower · $followingCount seguiti',
                    style: const TextStyle(fontSize: 11, color: kMutedColor),
                  ),
                ],
              ),
            ),

            if (!isMe)
              OutlinedButton(
                onPressed: userId == null
                    ? null
                    : () async {
                        if (_currentUserId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Devi essere loggato per seguire.'),
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
                          // ignore: avoid_print
                          print('❌ Follow toggle error: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Errore: $e'),
                              backgroundColor: kErrorColor,
                            ),
                          );
                        }
                      },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: isFollowing ? kMutedColor : kBrandColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor:
                      isFollowing ? kMutedColor.withOpacity(0.1) : null,
                ),
                child: Text(
                  isFollowing ? 'Segui già' : 'Segui',
                  style: TextStyle(
                    color: isFollowing ? kMutedColor : kBrandColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
      return _buildSearchHint(
        title: 'Cerca circuiti',
        subtitle:
            'Digita almeno 2 caratteri per cercare tra le sessioni pubbliche per nome circuito.',
        placeholderList:
            _mockCircuits.map((circuit) => _buildCircuitCard(circuit)).toList(),
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
                      trackName,
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
              _buildCircuitStat(
                  'Avg distanza', '${avgDistance.toStringAsFixed(1)} km'),
              _buildCircuitStat('Sessioni', totalSessions.toString()),
              _buildCircuitStat('Record', bestLapStr),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchTrackSessionsPage(
                      trackName: trackName,
                      preloaded: sessions,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('Vedi sessioni'),
            ),
          ),
        ],
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
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: kBrandColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: kMutedColor.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildCountriesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Esplora per paese',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 16),
        ..._mockCountries.map((country) => _buildCountryCard(country)),
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
    required List<Widget> placeholderList,
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
        const SizedBox(height: 16),
        ...placeholderList,
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
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      final snap = await _firestore
          .collection('users')
          .orderBy('fullName')
          .startAt([term])
          .endAt(['$term'])
          .limit(20)
          .get();
      final results = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
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
    setState(() {
      _loadingCircuits = true;
      _circuitsError = null;
    });
    try {
      final snap = await _firestore
          .collection('sessions')
          .where('isPublic', isEqualTo: true)
          .orderBy('trackName')
          .startAt([term])
          .endAt(['$term'])
          .limit(40)
          .get();

      final results = snap.docs
          .map((d) => SessionModel.fromFirestore(d.id, d.data()))
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

// Mock data
final _mockUsers = [
  {
    'initials': 'LH',
    'name': 'Lewis Hamilton',
    'sessions': 142,
    'distance': 2840
  },
  {
    'initials': 'MV',
    'name': 'Max Verstappen',
    'sessions': 128,
    'distance': 2560
  },
  {
    'initials': 'CF',
    'name': 'Charles Leclerc',
    'sessions': 95,
    'distance': 1900
  },
  {'initials': 'LN', 'name': 'Lando Norris', 'sessions': 87, 'distance': 1740},
  {
    'initials': 'SA',
    'name': 'Sebastian Alonso',
    'sessions': 76,
    'distance': 1520
  },
];

final _mockCircuits = [
  {
    'name': 'Monza',
    'location': 'Italia',
    'length': '5.8 km',
    'sessions': '1.2k',
    'record': '1:21.046',
  },
  {
    'name': 'Mugello',
    'location': 'Italia',
    'length': '5.2 km',
    'sessions': '890',
    'record': '1:15.144',
  },
  {
    'name': 'Misano',
    'location': 'Italia',
    'length': '4.2 km',
    'sessions': '756',
    'record': '1:31.137',
  },
  {
    'name': 'Spa-Francorchamps',
    'location': 'Belgio',
    'length': '7.0 km',
    'sessions': '2.1k',
    'record': '1:41.252',
  },
];

final _mockCountries = [
  {'flag': '🇮🇹', 'name': 'Italia', 'circuits': 24, 'users': 3420},
  {'flag': '🇩🇪', 'name': 'Germania', 'circuits': 18, 'users': 2840},
  {'flag': '🇫🇷', 'name': 'Francia', 'circuits': 16, 'users': 2310},
  {'flag': '🇬🇧', 'name': 'Regno Unito', 'circuits': 22, 'users': 4100},
  {'flag': '🇪🇸', 'name': 'Spagna', 'circuits': 14, 'users': 1980},
];
