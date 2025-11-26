import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import 'search_user_profile_page.dart';
import '../models/session_model.dart';
import 'search_track_sessions_page.dart';

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

  Timer? _debounce;
  String _query = '';

  bool _loadingUsers = false;
  bool _loadingCircuits = false;
  String? _usersError;
  String? _circuitsError;

  List<Map<String, dynamic>> _userResults = [];
  Map<String, List<SessionModel>> _circuitGroups = {};
  List<String> _circuitOrder = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
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
                _buildMapTab(),
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
          Tab(icon: Icon(Icons.map_outlined, size: 20)),
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
                ],
              ),
            ),

            // Follow button placeholder
            OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kBrandColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text(
                'Segui',
                style: TextStyle(
                  color: kBrandColor,
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

  Widget _buildMapTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF10121A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kLineColor),
              ),
              child: Stack(
                children: [
                  // Map placeholder
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.map_outlined,
                          size: 80,
                          color: kMutedColor.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Mappa Circuiti',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kMutedColor.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'OpenStreetMap integration\nProximamente disponibile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: kMutedColor.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Map controls overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        _buildMapButton(Icons.add),
                        const SizedBox(height: 8),
                        _buildMapButton(Icons.remove),
                        const SizedBox(height: 8),
                        _buildMapButton(Icons.my_location),
                      ],
                    ),
                  ),

                  // Legend overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000).withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kLineColor.withOpacity(0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLegendItem(
                              Colors.greenAccent, 'Circuiti verificati'),
                          const SizedBox(height: 6),
                          _buildLegendItem(
                              Colors.blueAccent, 'Circuiti community'),
                          const SizedBox(height: 6),
                          _buildLegendItem(kBrandColor, 'Le mie sessioni'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kLineColor),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: kFgColor,
        onPressed: () {
          // Future: map controls
        },
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: kFgColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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

  List<String> _tokenize(String input) {
    final tokens = <String>{};
    final cleaned = input.toLowerCase().trim();
    if (cleaned.isEmpty) return [];
    final parts = cleaned.split(RegExp(r'\s+'));
    for (final part in parts) {
      if (part.isEmpty) continue;
      for (int i = 1; i <= part.length; i++) {
        tokens.add(part.substring(0, i));
      }
    }
    for (int i = 1; i <= cleaned.length; i++) {
      tokens.add(cleaned.substring(0, i));
    }
    return tokens.toList();
  }

  // ===== Helper UI =====
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

  // ===== Search logic =====
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
    await Future.wait([
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
      final tokens = _tokenize(term);
      if (tokens.isEmpty) {
        setState(() {
          _userResults = [];
        });
        return;
      }

      final snap = await _firestore
          .collection('users')
          .where('searchTokens', arrayContainsAny: tokens.take(10).toList())
          .orderBy('fullName')
          .limit(20)
          .get();

      final results = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          ...data,
        };
      }).toList();

      setState(() {
        _userResults = results;
      });
    } catch (e) {
      // Mostra errore in console per link indici Firestore
      // ignore: avoid_print
      print('❌ Search users error: $e');
      // Mostra l'errore per poter creare l'indice Firestore se richiesto
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
          .endAt(['$term\uf8ff'])
          .limit(40)
          .get();

      final results = snap.docs.map((d) {
        final data = d.data();
        return SessionModel.fromFirestore(d.id, data);
      }).toList();

      final groups = <String, List<SessionModel>>{};
      for (final s in results) {
        groups.putIfAbsent(s.trackName, () => []).add(s);
      }

      setState(() {
        _circuitGroups = groups;
        _circuitOrder = groups.keys.toList();
      });
    } catch (e) {
      // Mostra errore in console per link indici Firestore
      // ignore: avoid_print
      print('❌ Search circuits error: $e');
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
