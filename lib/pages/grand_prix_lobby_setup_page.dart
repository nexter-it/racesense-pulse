import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme.dart';
import '../services/grand_prix_service.dart';
import '../services/custom_circuit_service.dart';
import '../services/official_circuits_service.dart';
import '../models/grand_prix_models.dart';
import '../models/official_circuit_info.dart';
import 'grand_prix_live_page.dart';
import '../widgets/profile_avatar.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class GrandPrixLobbySetupPage extends StatefulWidget {
  final String lobbyCode;

  const GrandPrixLobbySetupPage({super.key, required this.lobbyCode});

  @override
  State<GrandPrixLobbySetupPage> createState() =>
      _GrandPrixLobbySetupPageState();
}

class _GrandPrixLobbySetupPageState extends State<GrandPrixLobbySetupPage>
    with SingleTickerProviderStateMixin {
  final _grandPrixService = GrandPrixService();
  final _customCircuitService = CustomCircuitService();

  GrandPrixLobby? _lobby;
  StreamSubscription<DatabaseEvent>? _lobbySub;
  bool _isLoading = false;
  String? _selectedTrackId;
  String? _selectedTrackName;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _watchLobby();
  }

  @override
  void dispose() {
    _lobbySub?.cancel();
    _pulseController.dispose();
    _grandPrixService.leaveLobby(widget.lobbyCode);
    super.dispose();
  }

  void _watchLobby() {
    _lobbySub = _grandPrixService.watchLobby(widget.lobbyCode).listen((event) {
      if (!event.snapshot.exists) {
        // Lobby deleted
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final lobby = GrandPrixLobby.fromMap(widget.lobbyCode, data);

      if (mounted) {
        setState(() {
          _lobby = lobby;
          if (lobby.trackId != null) {
            _selectedTrackId = lobby.trackId;
            _selectedTrackName = lobby.trackName;
          }
        });

        // If session started, navigate to live page
        if (lobby.status == 'running') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GrandPrixLivePage(lobbyCode: widget.lobbyCode),
            ),
          );
        }
      }
    });
  }

  Future<void> _selectTrack() async {
    HapticFeedback.lightImpact();

    // Show bottom sheet with circuit selection
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _TrackSelectorSheet(),
    );

    if (result != null) {
      setState(() {
        _selectedTrackId = result['id'];
        _selectedTrackName = result['name'];
      });

      try {
        await _grandPrixService.setTrack(
          widget.lobbyCode,
          result['id']!,
          result['name']!,
        );
      } catch (e) {
        _showErrorSnackBar(e.toString());
      }
    }
  }

  Future<void> _startSession() async {
    if (_selectedTrackId == null) {
      _showErrorSnackBar('Seleziona un circuito prima di iniziare');
      return;
    }

    final participantCount = _lobby?.participants.values.where((p) => p.connected).length ?? 0;
    if (participantCount < 2) {
      _showErrorSnackBar('Servono almeno 2 piloti per iniziare');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      await _grandPrixService.startSession(widget.lobbyCode);
      // Navigation handled by lobby watcher
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(e.toString());
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 0.5),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _grandPrixService.leaveLobby(widget.lobbyCode);
        return true;
      },
      child: Scaffold(
        backgroundColor: _kBgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      _buildLobbyCodeCard(),
                      const SizedBox(height: 20),
                      _buildTrackSelector(),
                      const SizedBox(height: 20),
                      _buildParticipantsCard(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _buildStartButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kCardStart, _kBgColor],
        ),
        border: Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              HapticFeedback.lightImpact();
              await _grandPrixService.leaveLobby(widget.lobbyCode);
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorderColor, width: 1),
              ),
              child: const Icon(Icons.close, color: kFgColor, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Setup Lobby',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Configura la tua gara',
                  style: TextStyle(
                    fontSize: 13,
                    color: kMutedColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kBrandColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBrandColor.withOpacity(0.3), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars, color: kBrandColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'HOST',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyCodeCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kBrandColor.withOpacity(0.15 * _pulseAnimation.value),
                kBrandColor.withOpacity(0.05 * _pulseAnimation.value),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: kBrandColor.withOpacity(0.3 * _pulseAnimation.value),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.key,
                    color: kBrandColor.withOpacity(_pulseAnimation.value),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CODICE LOBBY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kMutedColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.lobbyCode,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                  letterSpacing: 12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Condividi questo codice con i tuoi amici',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: kMutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrackSelector() {
    return GestureDetector(
      onTap: _selectTrack,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kCardStart, _kCardEnd],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kBrandColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.track_changes,
                    color: kBrandColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Circuito',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kFgColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: kMutedColor,
                  size: 24,
                ),
              ],
            ),
            if (_selectedTrackName != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: kBrandColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: kBrandColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedTrackName!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kFgColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Tocca per selezionare un circuito',
                style: TextStyle(
                  fontSize: 13,
                  color: kMutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantsCard() {
    final connectedParticipants =
        _lobby?.participants.values.where((p) => p.connected).toList() ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.people,
                  color: kBrandColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Piloti Connessi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: kFgColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBrandColor.withOpacity(0.3)),
                ),
                child: Text(
                  '${connectedParticipants.length}/20',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (connectedParticipants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'In attesa di piloti...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: kMutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            ...connectedParticipants.map((participant) {
              final isHost = participant.userId == _lobby?.hostId;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kTileColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHost
                        ? kBrandColor.withOpacity(0.3)
                        : _kBorderColor,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    ProfileAvatarCompact(
                      profileImageUrl: participant.profileImageUrl,
                      userTag: participant.username.substring(0, 2).toUpperCase(),
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            participant.username,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kFgColor,
                            ),
                          ),
                          if (isHost)
                            Text(
                              'Host',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kBrandColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    final canStart = _selectedTrackId != null &&
        (_lobby?.participants.values.where((p) => p.connected).length ?? 0) >= 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: (_isLoading || !canStart) ? null : _startSession,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: canStart && !_isLoading
                  ? [kBrandColor, kBrandColor.withOpacity(0.85)]
                  : [
                      kMutedColor.withOpacity(0.3),
                      kMutedColor.withOpacity(0.2)
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: canStart && !_isLoading
                ? [
                    BoxShadow(
                      color: kBrandColor.withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.flag,
                        color: canStart ? Colors.black : kMutedColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'AVVIA SESSIONE',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: canStart ? Colors.black : kMutedColor,
                          letterSpacing: 1.5,
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

// Track selector bottom sheet
class _TrackSelectorSheet extends StatefulWidget {
  @override
  State<_TrackSelectorSheet> createState() => _TrackSelectorSheetState();
}

class _TrackSelectorSheetState extends State<_TrackSelectorSheet>
    with SingleTickerProviderStateMixin {
  final _customCircuitService = CustomCircuitService();
  final _officialCircuitsService = OfficialCircuitsService();
  final _searchController = TextEditingController();

  List<CustomCircuitInfo> _customCircuits = [];
  List<OfficialCircuitInfo> _officialCircuits = [];
  List<OfficialCircuitInfo> _filteredOfficialCircuits = [];
  bool _loading = true;

  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() => _currentTab = _tabController.index);
    });
    _searchController.addListener(_filterOfficialCircuits);
    _loadCircuits();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterOfficialCircuits() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOfficialCircuits = _officialCircuits;
      } else {
        _filteredOfficialCircuits = _officialCircuits.where((c) {
          return c.name.toLowerCase().contains(query) ||
              c.city.toLowerCase().contains(query) ||
              c.country.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadCircuits() async {
    setState(() => _loading = true);

    final customList = await _customCircuitService.listCircuits();
    final officialList = await _officialCircuitsService.loadCircuits();

    if (mounted) {
      setState(() {
        _customCircuits = customList;
        _officialCircuits = officialList;
        _filteredOfficialCircuits = officialList;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: _kBgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kBorderColor, width: 1),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kMutedColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Seleziona Circuito',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                  ),
                ),
                const SizedBox(height: 16),
                // Tab bar
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _kTileColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kBrandColor, kBrandColor.withAlpha(200)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.black,
                    unselectedLabelColor: kMutedColor,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.track_changes, size: 16),
                            const SizedBox(width: 6),
                            const Text('Tuoi Circuiti'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_rounded, size: 16),
                            const SizedBox(width: 6),
                            const Text('Ufficiali'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCustomCircuitsList(),
                      _buildOfficialCircuitsList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCircuitsList() {
    if (_customCircuits.isEmpty) {
      return Center(
        child: Text(
          'Nessun circuito custom disponibile',
          style: TextStyle(
            fontSize: 14,
            color: kMutedColor,
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: _customCircuits.length,
      itemBuilder: (context, index) {
        final circuit = _customCircuits[index];
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop({
              'id': 'custom:${circuit.trackId ?? circuit.name}',
              'name': circuit.name,
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kCardStart, _kCardEnd],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kBorderColor,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kBrandColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.track_changes,
                    color: kBrandColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circuit.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kFgColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Circuito Custom',
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: kMutedColor,
                  size: 24,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOfficialCircuitsList() {
    if (_officialCircuits.isEmpty) {
      return Center(
        child: Text(
          'Nessun circuito ufficiale disponibile',
          style: TextStyle(
            fontSize: 14,
            color: kMutedColor,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Container(
            decoration: BoxDecoration(
              color: _kTileColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorderColor),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: kFgColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Cerca circuito...',
                hintStyle: TextStyle(color: kMutedColor, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: kMutedColor, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: kMutedColor, size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ),
        // Results count
        if (_searchController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text(
                  '${_filteredOfficialCircuits.length} ${_filteredOfficialCircuits.length == 1 ? 'risultato' : 'risultati'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        // Circuit list
        Expanded(
          child: _filteredOfficialCircuits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, color: kMutedColor, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Nessun circuito trovato',
                        style: TextStyle(
                          fontSize: 14,
                          color: kMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _filteredOfficialCircuits.length,
                  itemBuilder: (context, index) {
                    final circuit = _filteredOfficialCircuits[index];
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop({
              'id': 'official:${circuit.file}',
              'name': circuit.name,
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kCardStart, _kCardEnd],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kBorderColor,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF29B6F6).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.stadium_rounded,
                    color: const Color(0xFF29B6F6),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circuit.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kFgColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: const Color(0xFF29B6F6),
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Ufficiale • ${circuit.location}',
                            style: TextStyle(
                              fontSize: 12,
                              color: kMutedColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: kMutedColor,
                  size: 24,
                ),
              ],
            ),
          ),
        );
                  },
                ),
        ),
      ],
    );
  }
}
