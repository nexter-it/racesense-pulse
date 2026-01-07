import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme.dart';
import '../services/grand_prix_service.dart';
import '../models/grand_prix_models.dart';
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

class GrandPrixWaitingRoomPage extends StatefulWidget {
  final String lobbyCode;

  const GrandPrixWaitingRoomPage({super.key, required this.lobbyCode});

  @override
  State<GrandPrixWaitingRoomPage> createState() =>
      _GrandPrixWaitingRoomPageState();
}

class _GrandPrixWaitingRoomPageState extends State<GrandPrixWaitingRoomPage>
    with TickerProviderStateMixin {
  final _grandPrixService = GrandPrixService();

  GrandPrixLobby? _lobby;
  StreamSubscription<DatabaseEvent>? _lobbySub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _spinController;

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
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _watchLobby();
  }

  @override
  void dispose() {
    _lobbySub?.cancel();
    _pulseController.dispose();
    _spinController.dispose();
    _grandPrixService.leaveLobby(widget.lobbyCode);
    super.dispose();
  }

  void _watchLobby() {
    _lobbySub = _grandPrixService.watchLobby(widget.lobbyCode).listen((event) {
      if (!event.snapshot.exists) {
        // Lobby deleted
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La lobby è stata chiusa dall\'host')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final lobby = GrandPrixLobby.fromMap(widget.lobbyCode, data);

      if (mounted) {
        setState(() {
          _lobby = lobby;
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
                      const SizedBox(height: 20),
                      _buildWaitingCard(),
                      const SizedBox(height: 24),
                      _buildLobbyCodeCard(),
                      const SizedBox(height: 20),
                      if (_lobby?.trackName != null) _buildTrackCard(),
                      if (_lobby?.trackName != null) const SizedBox(height: 20),
                      _buildParticipantsCard(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
              child: const Icon(Icons.arrow_back, color: kFgColor, size: 22),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting Room',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'In attesa dell\'host...',
                  style: TextStyle(
                    fontSize: 13,
                    color: kMutedColor,
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

  Widget _buildWaitingCard() {
    return AnimatedBuilder(
      animation: _spinController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kBrandColor.withOpacity(0.1),
                kBrandColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBrandColor.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Transform.rotate(
                angle: _spinController.value * 2 * 3.14159,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kBrandColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.hourglass_empty,
                    color: kBrandColor,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'In attesa di avvio',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'L\'host sta configurando la sessione',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: kMutedColor,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLobbyCodeCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
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
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.key,
                    color: kBrandColor.withOpacity(_pulseAnimation.value),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CODICE LOBBY',
                    style: TextStyle(
                      fontSize: 11,
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
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                  letterSpacing: 8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrackCard() {
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
                  Icons.track_changes,
                  color: kBrandColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Circuito Selezionato',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kFgColor,
                ),
              ),
            ],
          ),
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
                    _lobby?.trackName ?? '',
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
        ],
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
}
