import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'search_user_profile_page.dart';
import '../models/session_model.dart';
import 'search_track_sessions_page.dart';
import '../services/follow_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Premium UI constants
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

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
  bool _loadingTopUsers = false;
  bool _loadingTopCircuits = false;
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
    setState(() => _loadingTopUsers = true);
    try {
      final snap = await _firestore
          .collection('users')
          .orderBy('stats.followerCount', descending: true)
          .limit(3)
          .get();
      if (!mounted) return;
      setState(() {
        _topUsers = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _loadingTopUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTopUsers = false);
    }
  }

  Future<void> _loadTopCircuits() async {
    setState(() => _loadingTopCircuits = true);
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
      if (!mounted) return;
      setState(() {
        _topCircuitGroups = groups;
        _topCircuitOrder = ordered.take(3).toList();
        _loadingTopCircuits = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTopCircuits = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildTabs(),
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
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kBrandColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.search, color: kBrandColor, size: 22),
          ),
          const SizedBox(width: 14),
          const Text(
            'Ricerca',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(
            fontSize: 15,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Cerca piloti o circuiti...',
            hintStyle: TextStyle(
              color: kMutedColor.withAlpha(130),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(Icons.search, color: kMutedColor.withAlpha(150), size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _onQueryChanged('');
                    },
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _kTileColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.close, color: kMutedColor, size: 16),
                    ),
                  )
                : null,
            filled: true,
            fillColor: _kTileColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kBrandColor, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)],
          ),
          border: Border.all(color: kBrandColor, width: 1.5),
        ),
        labelColor: kBrandColor,
        unselectedLabelColor: kMutedColor,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
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
      return _buildTopSection(
        title: 'Top Piloti',
        subtitle: 'I piloti pi seguiti della piattaforma',
        icon: Icons.emoji_events_outlined,
        iconColor: const Color(0xFFFFD60A),
        isLoading: _loadingTopUsers && _topUsers.isEmpty,
        children: _topUsers.take(3).map((u) => _buildUserCard(u)).toList(),
      );
    }

    if (_loadingUsers) {
      return _buildLoadingState();
    }

    if (_usersError != null) {
      return _buildErrorState(_usersError!);
    }

    if (_userResults.isEmpty) {
      return _buildEmptyState('Nessun pilota trovato per "$_query"');
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: _userResults.map((user) => _buildUserCard(user)).toList(),
    );
  }

  Widget _buildCircuitsTab() {
    if (_query.length < 2) {
      final widgets = _topCircuitOrder
          .map((name) => _buildCircuitCard(name, _topCircuitGroups[name] ?? []))
          .toList();
      return _buildTopSection(
        title: 'Top Circuiti',
        subtitle: 'I circuiti con più sessioni tracciate',
        icon: Icons.flag_outlined,
        iconColor: kPulseColor,
        isLoading: _loadingTopCircuits && _topCircuitOrder.isEmpty,
        children: widgets,
      );
    }

    if (_loadingCircuits) {
      return _buildLoadingState();
    }

    if (_circuitsError != null) {
      return _buildErrorState(_circuitsError!);
    }

    if (_circuitGroups.isEmpty) {
      return _buildEmptyState('Nessun circuito trovato per "$_query"');
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: _circuitOrder
          .map((name) => _buildCircuitCard(name, _circuitGroups[name]!))
          .toList(),
    );
  }

  Widget _buildTopSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isLoading,
    required List<Widget> children,
  }) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: iconColor.withAlpha(60)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: kMutedColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isLoading)
          _buildLoadingCard()
        else
          ...children,
      ],
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final fullName = user['fullName'] ?? user['name'] ?? '';
    final stats = user['stats'] as Map<String, dynamic>? ?? {};
    final totalSessions = stats['totalSessions'] ?? user['sessions'] ?? 0;
    final initials = user['initials'] ??
        (fullName.isNotEmpty ? fullName[0].toUpperCase() : '?');
    final userId = user['id']?.toString();
    final followerCount = stats['followerCount'] ?? 0;
    final isMe = _currentUserId != null && _currentUserId == userId;
    final isFollowing = userId != null && _followingIds.contains(userId);

    return GestureDetector(
      onTap: (userId != null && userId.isNotEmpty)
          ? () {
              HapticFeedback.selectionClick();
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 16,
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
                  colors: [kBrandColor.withAlpha(80), kPulseColor.withAlpha(60)],
                ),
              ),
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kTileColor,
                ),
                child: Center(
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildMiniStat(Icons.directions_run, '$totalSessions', kBrandColor),
                      const SizedBox(width: 8),
                      _buildMiniStat(Icons.people, '$followerCount', kPulseColor),
                    ],
                  ),
                ],
              ),
            ),

            // Follow button
            if (!isMe)
              GestureDetector(
                onTap: userId == null
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        if (_currentUserId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Devi essere loggato per seguire.')),
                          );
                          return;
                        }
                        try {
                          if (isFollowing) {
                            await _followService.unfollow(userId);
                            setState(() {
                              _followingIds.remove(userId);
                              if (user['stats'] != null) {
                                final s = Map<String, dynamic>.from(user['stats'] as Map);
                                s['followerCount'] = (s['followerCount'] ?? 0) - 1;
                                user['stats'] = s;
                              }
                            });
                          } else {
                            await _followService.follow(userId);
                            setState(() {
                              _followingIds.add(userId);
                              if (user['stats'] != null) {
                                final s = Map<String, dynamic>.from(user['stats'] as Map);
                                s['followerCount'] = (s['followerCount'] ?? 0) + 1;
                                user['stats'] = s;
                              }
                            });
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Errore: $e'), backgroundColor: kErrorColor),
                          );
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isFollowing
                        ? null
                        : LinearGradient(colors: [kBrandColor.withAlpha(30), kBrandColor.withAlpha(15)]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFollowing ? kMutedColor.withAlpha(100) : kBrandColor,
                      width: 1.5,
                    ),
                  ),
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

  Widget _buildMiniStat(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitCard(String trackName, List<SessionModel> sessions) {
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
    final bestLapStr = bestLap != null ? _formatLap(bestLap) : '--:--.--';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchTrackSessionsPage(
              trackName: trackName,
              preloaded: sessions,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kPulseColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kPulseColor.withAlpha(60)),
                    ),
                    child: const Icon(Icons.location_on, color: kPulseColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.place, size: 14, color: kMutedColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kMutedColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: kMutedColor, size: 24),
                ],
              ),
            ),

            // Stats row
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildCircuitStat(Icons.sports_score, '$totalSessions', 'Sessioni', kBrandColor)),
                  Container(width: 1, height: 45, color: _kBorderColor),
                  Expanded(child: _buildCircuitStat(Icons.timer_outlined, bestLapStr, 'Record', kPulseColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircuitStat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Colors.white,
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

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBrandColor.withAlpha(60)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: const AlwaysStoppedAnimation(kBrandColor),
                backgroundColor: _kBorderColor,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ricerca in corso...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: const AlwaysStoppedAnimation(kBrandColor),
              backgroundColor: _kBorderColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Caricamento...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recupero dati da Firebase',
                  style: TextStyle(color: kMutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kBorderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kMutedColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off, color: kMutedColor, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kErrorColor.withAlpha(20), kErrorColor.withAlpha(10)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kErrorColor.withAlpha(60)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kErrorColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, color: kErrorColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kErrorColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLap(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
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
      // Carica tutte le sessioni pubbliche recenti e filtra localmente
      // per supportare ricerca case-insensitive con contains
      final snap = await _firestore
          .collection('sessions')
          .where('isPublic', isEqualTo: true)
          .orderBy('dateTime', descending: true)
          .limit(500)
          .get();

      // Filtra localmente: case-insensitive e supporta sottostringhe
      final results = snap.docs
          .map((d) => SessionModel.fromFirestore(d.id, d.data()))
          .where((s) => s.trackName.toLowerCase().contains(termLower))
          .toList();

      final groups = <String, List<SessionModel>>{};
      for (final s in results) {
        groups.putIfAbsent(s.trackName, () => []).add(s);
      }

      // Ordina i circuiti per numero di sessioni (più popolari prima)
      final orderedKeys = groups.keys.toList()
        ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));

      setState(() {
        _circuitGroups = groups;
        _circuitOrder = orderedKeys;
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
