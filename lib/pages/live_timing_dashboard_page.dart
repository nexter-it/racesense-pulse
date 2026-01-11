import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/live_driver_model.dart';
import '../models/live_race_model.dart';
import '../services/live_timing_service.dart';
import '../theme.dart';

/// Dashboard per visualizzare i dati live della gara - AIM MXS Style
/// Layout orizzontale ottimizzato per uso in pista
class LiveTimingDashboardPage extends StatefulWidget {
  final String deviceId;

  const LiveTimingDashboardPage({
    super.key,
    required this.deviceId,
  });

  @override
  State<LiveTimingDashboardPage> createState() =>
      _LiveTimingDashboardPageState();
}

class _LiveTimingDashboardPageState extends State<LiveTimingDashboardPage>
    with SingleTickerProviderStateMixin {
  final LiveTimingService _liveService = LiveTimingService();

  LiveRaceModel? _raceData;
  LiveDriverModel? _driverData;
  bool _isLoading = true;
  bool _noRaceActive = false;
  String? _errorMessage;

  StreamSubscription<LiveRaceModel?>? _raceSub;
  StreamSubscription<LiveDriverModel?>? _driverSub;

  // Timer locale per il giro attuale
  final Stopwatch _lapWatch = Stopwatch();
  Timer? _uiTimer;
  int _lastLapCount = 0;

  // Animazione per banner bandiera/penalità
  late AnimationController _flagAnimController;
  late Animation<double> _flagAnimation;
  String? _lastStatus;
  bool _showFlagBanner = false;

  // Tracking penalità
  int _lastPenaltyTimeSec = 0;
  int _lastPenaltyWarnings = 0;
  bool _lastPenaltyDq = false;
  bool _showPenaltyBanner = false;
  String _penaltyBannerType = ''; // 'time', 'warning', 'dq'

  @override
  void initState() {
    super.initState();
    // Forza orientamento landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Mantieni lo schermo acceso durante la sessione live
    WakelockPlus.enable();

    _flagAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _flagAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flagAnimController, curve: Curves.easeOut),
    );
    _initLiveData();
  }

  @override
  void dispose() {
    // Ripristina orientamento normale
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Disattiva wakelock quando si esce dalla sessione
    WakelockPlus.disable();

    _raceSub?.cancel();
    _driverSub?.cancel();
    _uiTimer?.cancel();
    _lapWatch.stop();
    _flagAnimController.dispose();
    _liveService.dispose();
    super.dispose();
  }

  Future<void> _initLiveData() async {
    try {
      final raceExists = await _liveService.checkRaceExists();

      if (!raceExists) {
        setState(() {
          _isLoading = false;
          _noRaceActive = true;
        });
        return;
      }

      await _liveService.startListening(widget.deviceId);

      // Timer UI (aggiorna ogni 50ms per precisione timer)
      _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (mounted && _lapWatch.isRunning) {
          setState(() {});
        }
      });

      _raceSub = _liveService.raceStream.listen(
        (race) {
          if (mounted) {
            if (race != null && _lastStatus != race.status) {
              _onStatusChanged(race.status);
              _lastStatus = race.status;
            }
            setState(() {
              _raceData = race;
              _isLoading = false;
              _noRaceActive = race == null;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Errore connessione: $e';
              _isLoading = false;
            });
          }
        },
      );

      _driverSub = _liveService.driverStream.listen(
        (driver) {
          if (mounted && driver != null) {
            if (driver.lapCount != _lastLapCount) {
              _lastLapCount = driver.lapCount;
              _lapWatch.reset();
              _lapWatch.start();
            } else if (!_lapWatch.isRunning && driver.lapCount > 0) {
              _lapWatch.start();
            }

            _checkPenaltyChange(driver.penalty);

            setState(() {
              _driverData = driver;
              _isLoading = false;
            });
          } else if (mounted) {
            setState(() {
              _driverData = null;
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Errore dati driver: $e';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Errore inizializzazione: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onStatusChanged(String newStatus) {
    if (newStatus == 'YELLOW FLAG' ||
        newStatus == 'RED FLAG' ||
        newStatus == 'IN CORSO' ||
        newStatus == 'FINITA') {
      setState(() => _showFlagBanner = true);
      _flagAnimController.forward(from: 0.0);
      final duration = newStatus == 'FINITA' ? 8 : 5;
      Future.delayed(Duration(seconds: duration), () {
        if (mounted) {
          _flagAnimController.reverse().then((_) {
            if (mounted) setState(() => _showFlagBanner = false);
          });
        }
      });
    }
  }

  void _checkPenaltyChange(PenaltyInfo penalty) {
    if (penalty.dq && !_lastPenaltyDq) {
      _showPenaltyNotification('dq');
    } else if (penalty.warnings > _lastPenaltyWarnings) {
      _showPenaltyNotification('warning');
    } else if (penalty.timeSec > _lastPenaltyTimeSec) {
      _showPenaltyNotification('time');
    }

    _lastPenaltyTimeSec = penalty.timeSec;
    _lastPenaltyWarnings = penalty.warnings;
    _lastPenaltyDq = penalty.dq;
  }

  void _showPenaltyNotification(String type) {
    setState(() {
      _penaltyBannerType = type;
      _showPenaltyBanner = true;
    });
    _flagAnimController.forward(from: 0.0);
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        _flagAnimController.reverse().then((_) {
          if (mounted) setState(() => _showPenaltyBanner = false);
        });
      }
    });
  }

  String _formatCurrentLapTime() {
    final elapsed = _lapWatch.elapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final hundredths = (elapsed.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        children: [
          _buildBody(),
          if (_showFlagBanner && _raceData != null) _buildFlagBanner(),
          if (_showPenaltyBanner && _driverData != null) _buildPenaltyBanner(),
          // Exit button
          Positioned(
            top: 12,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, color: Colors.white54, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kBrandColor, strokeWidth: 3),
            SizedBox(height: 16),
            Text(
              'CONNECTING...',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      );
    }

    if (_noRaceActive) {
      return _buildNoRaceScreen();
    }

    if (_errorMessage != null) {
      return _buildErrorScreen();
    }

    return _buildAIMDisplay();
  }

  /// Layout principale stile AIM MXS - 4 quadranti
  Widget _buildAIMDisplay() {
    final hasDriver = _driverData != null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A0A0A),
            Color(0xFF000000),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              // Top bar - Status e info gara
              _buildTopBar(),
              const SizedBox(height: 8),
              // Main display - 4 quadranti
              Expanded(
                child: hasDriver
                    ? Row(
                        children: [
                          // LEFT - Current Lap Time (GIGANTE)
                          Expanded(
                            flex: 5,
                            child: _buildCurrentLapPanel(),
                          ),
                          const SizedBox(width: 12),
                          // RIGHT - Delta, Best, Last
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                // DELTA LIVE - Prominente
                                Expanded(
                                  flex: 5,
                                  child: _buildDeltaPanel(),
                                ),
                                const SizedBox(height: 8),
                                // BEST e LAST
                                Expanded(
                                  flex: 4,
                                  child: Row(
                                    children: [
                                      Expanded(child: _buildBestLapPanel()),
                                      const SizedBox(width: 8),
                                      Expanded(child: _buildLastLapPanel()),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : _buildWaitingForDriver(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          // Status indicator
          _buildStatusIndicator(),
          const SizedBox(width: 16),
          // Lap counter
          if (_driverData != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Text(
                    'LAP',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_driverData!.lapCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (_raceData?.totalLaps != null)
                    Text(
                      '/${_raceData!.totalLaps}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(80),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
          const Spacer(),
          // Circuit name
          if (_raceData?.circuitName != null)
            Text(
              _raceData!.circuitName!.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white.withAlpha(100),
                letterSpacing: 1,
              ),
            ),
          const SizedBox(width: 16),
          // Position
          if (_driverData != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Text(
                'P${_driverData!.position}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final isConnected = _liveService.isConnected;
    final hasPenalty = _driverData?.penalty.hasAny ?? false;

    if (hasPenalty) {
      final penalty = _driverData!.penalty;
      if (penalty.dq) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Text(
            'DSQ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (penalty.timeSec > 0)
              Text(
                '+${penalty.timeSec}s',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (penalty.timeSec > 0 && penalty.warnings > 0)
              const SizedBox(width: 6),
            if (penalty.warnings > 0)
              Text(
                '${penalty.warnings}W',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.red,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.red,
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? Colors.green : Colors.red).withAlpha(150),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: isConnected ? Colors.green : Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Panel CURRENT LAP - Il più grande, stile AIM
  Widget _buildCurrentLapPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withAlpha(8),
            Colors.white.withAlpha(4),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Stack(
        children: [
          // Background pattern (grid effect like AIM)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _GridPatternPainter(),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Label
                Text(
                  'CURRENT LAP',
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                const Spacer(),
                // TEMPO GIGANTE
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatCurrentLapTime(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                // Speed
                if (_driverData?.speedKmh != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${_driverData!.speedKmh!.toInt()}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(180),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'km/h',
                        style: TextStyle(
                          color: Colors.white.withAlpha(80),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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

  /// Panel DELTA LIVE - Colorato in base a performance
  Widget _buildDeltaPanel() {
    final liveDelta = _driverData?.liveDelta;
    final isPositive = liveDelta != null && liveDelta > 0;
    final isNegative = liveDelta != null && liveDelta < 0;

    // Colori AIM style
    final Color bgColor;
    final Color textColor;
    final Color borderColor;

    if (isNegative) {
      // Più veloce - Verde
      bgColor = const Color(0xFF00C853);
      textColor = Colors.white;
      borderColor = const Color(0xFF00E676);
    } else if (isPositive) {
      // Più lento - Rosso
      bgColor = const Color(0xFFD50000);
      textColor = Colors.white;
      borderColor = const Color(0xFFFF1744);
    } else {
      // Neutro
      bgColor = const Color(0xFF1A1A1A);
      textColor = Colors.white;
      borderColor = Colors.white.withAlpha(40);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          if (isNegative || isPositive)
            BoxShadow(
              color: bgColor.withAlpha(100),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Stack(
        children: [
          // Glow effect per delta attivo
          if (isNegative || isPositive)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: RadialGradient(
                    colors: [
                      bgColor.withAlpha(40),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isNegative)
                      Icon(Icons.arrow_drop_down, color: textColor, size: 24),
                    if (isPositive)
                      Icon(Icons.arrow_drop_up, color: textColor, size: 24),
                    Text(
                      'DELTA',
                      style: TextStyle(
                        color: textColor.withAlpha(200),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _driverData?.formattedLiveDelta ?? '---',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  isNegative
                      ? 'FASTER'
                      : isPositive
                          ? 'SLOWER'
                          : 'ON PACE',
                  style: TextStyle(
                    color: textColor.withAlpha(180),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Panel BEST LAP
  Widget _buildBestLapPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.withAlpha(30),
            Colors.purple.withAlpha(15),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emoji_events,
                  color: Colors.purple.withAlpha(200),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'BEST',
                  style: TextStyle(
                    color: Colors.purple.withAlpha(200),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _driverData?.formattedBestLapTime ?? '--:--.---',
                style: TextStyle(
                  color: Colors.purple.shade200,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  /// Panel LAST LAP
  Widget _buildLastLapPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'LAST',
              style: TextStyle(
                color: Colors.white.withAlpha(120),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _driverData?.formattedLastLapTime ?? '--:--.---',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForDriver() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: kBrandColor,
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            'WAITING FOR DATA',
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlagBanner() {
    final status = _raceData!.status;

    Color color;
    String text;
    String subText;
    IconData icon;

    switch (status) {
      case 'YELLOW FLAG':
        color = const Color(0xFFFFD700);
        text = 'YELLOW FLAG';
        subText = 'SLOW DOWN - ${_raceData!.maxYellowFlagSpeed ?? 60} KM/H MAX';
        icon = Icons.flag_rounded;
        break;
      case 'RED FLAG':
        color = Colors.red;
        text = 'RED FLAG';
        subText = 'SESSION STOPPED';
        icon = Icons.flag_rounded;
        break;
      case 'IN CORSO':
        color = Colors.green;
        text = 'GREEN FLAG';
        subText = 'GO GO GO!';
        icon = Icons.flag_rounded;
        break;
      case 'FINITA':
        color = Colors.white;
        text = 'CHECKERED';
        subText = 'SESSION FINISHED';
        icon = Icons.sports_score;
        break;
      default:
        return const SizedBox.shrink();
    }

    final isCheckered = status == 'FINITA';

    return AnimatedBuilder(
      animation: _flagAnimation,
      builder: (context, child) {
        return Positioned.fill(
          child: Container(
            color: Colors.black.withAlpha((200 * _flagAnimation.value).toInt()),
            child: Center(
              child: Transform.scale(
                scale: 0.8 + (0.2 * _flagAnimation.value),
                child: Opacity(
                  opacity: _flagAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      gradient: isCheckered
                          ? null
                          : LinearGradient(
                              colors: [color, color.withAlpha(220)],
                            ),
                      color: isCheckered ? const Color(0xFF1A1A1A) : null,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withAlpha(150),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 48,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subText,
                          style: TextStyle(
                            color: Colors.white.withAlpha(220),
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPenaltyBanner() {
    final penalty = _driverData!.penalty;

    Color color;
    String text;
    String subText;
    IconData icon;

    switch (_penaltyBannerType) {
      case 'dq':
        color = Colors.black;
        text = 'DISQUALIFIED';
        subText = 'YOU HAVE BEEN DISQUALIFIED';
        icon = Icons.block;
        break;
      case 'warning':
        color = Colors.orange;
        text = 'WARNING';
        subText = 'Warning ${penalty.warnings} received';
        icon = Icons.flag;
        break;
      case 'time':
        color = Colors.orange;
        text = 'TIME PENALTY';
        subText = '+${penalty.timeSec} seconds added';
        icon = Icons.timer;
        break;
      default:
        return const SizedBox.shrink();
    }

    final isDq = _penaltyBannerType == 'dq';

    return AnimatedBuilder(
      animation: _flagAnimation,
      builder: (context, child) {
        return Positioned.fill(
          child: Container(
            color: Colors.black.withAlpha((200 * _flagAnimation.value).toInt()),
            child: Center(
              child: Transform.scale(
                scale: 0.8 + (0.2 * _flagAnimation.value),
                child: Opacity(
                  opacity: _flagAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      gradient: isDq
                          ? null
                          : LinearGradient(
                              colors: [color, color.withAlpha(220)],
                            ),
                      color: isDq ? Colors.black : null,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDq ? Colors.white : color,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isDq ? Colors.white : color).withAlpha(150),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 36,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subText,
                          style: TextStyle(
                            color: Colors.white.withAlpha(220),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoRaceScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(8),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Icon(
              Icons.timer_off_outlined,
              color: Colors.white.withAlpha(100),
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'NO ACTIVE SESSION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for race session to start',
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(30)),
              ),
              child: Text(
                'GO BACK',
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withAlpha(20),
              border: Border.all(color: Colors.red.withAlpha(60)),
            ),
            child: const Icon(Icons.error_outline, color: Colors.red, size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.red.withAlpha(200), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _initLiveData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBrandColor.withAlpha(80)),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: kBrandColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter per effetto griglia stile AIM
class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1;

    const spacing = 30.0;

    // Linee verticali
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Linee orizzontali
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
