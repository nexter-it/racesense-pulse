import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/live_driver_model.dart';
import '../models/live_race_model.dart';
import '../services/live_timing_service.dart';
import '../theme.dart';

/// Dashboard per visualizzare i dati live della gara - RaceChrono Pro Style
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
    _raceSub?.cancel();
    _driverSub?.cancel();
    _uiTimer?.cancel();
    _lapWatch.stop();
    _flagAnimController.dispose();
    _liveService.dispose();
    super.dispose();
  }

  Future<void> _initLiveData() async {
    // print('🟢 [Dashboard] Inizializzazione per device: ${widget.deviceId}');
    try {
      // Verifica se esiste una gara attiva
      // print('🟢 [Dashboard] Verifica esistenza gara...');
      final raceExists = await _liveService.checkRaceExists();
      // print('🟢 [Dashboard] Gara esiste: $raceExists');

      if (!raceExists) {
        // print('🟢 [Dashboard] Nessuna gara attiva, mostro schermata attesa');
        setState(() {
          _isLoading = false;
          _noRaceActive = true;
        });
        return;
      }

      // Inizia ad ascoltare i dati
      // print('🟢 [Dashboard] Avvio ascolto streams...');
      await _liveService.startListening(widget.deviceId);

      // Timer UI (aggiorna ogni 100ms per il lap timer)
      _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted && _lapWatch.isRunning) {
          setState(() {});
        }
      });

      // Sottoscrivi agli stream
      _raceSub = _liveService.raceStream.listen(
        (race) {
          // print('🟢 [Dashboard] Race data ricevuti: ${race?.status}');
          if (mounted) {
            // Controlla cambio di status per banner bandiera
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
          // print('🟢 [Dashboard] ERRORE race stream: $e');
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
            // Controlla cambio di lap count per resettare il timer
            if (driver.lapCount != _lastLapCount) {
              _lastLapCount = driver.lapCount;
              _lapWatch.reset();
              _lapWatch.start();
            } else if (!_lapWatch.isRunning && driver.lapCount > 0) {
              // Avvia il timer se non è già in esecuzione
              _lapWatch.start();
            }

            // Controlla cambio penalità
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
          // print('🟢 [Dashboard] ERRORE driver stream: $e');
          if (mounted) {
            setState(() {
              _errorMessage = 'Errore dati driver: $e';
            });
          }
        },
      );
      // print('🟢 [Dashboard] Streams sottoscritti');
    } catch (e, stackTrace) {
      // print('🟢 [Dashboard] ERRORE inizializzazione: $e');
      // print('🟢 [Dashboard] StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Errore inizializzazione: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onStatusChanged(String newStatus) {
    // Mostra banner animato per tutte le bandiere importanti
    if (newStatus == 'YELLOW FLAG' ||
        newStatus == 'RED FLAG' ||
        newStatus == 'IN CORSO' ||
        newStatus == 'FINITA') {
      setState(() => _showFlagBanner = true);
      _flagAnimController.forward(from: 0.0);
      // Nascondi dopo 5 secondi (8 per la bandiera a scacchi)
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
    // Controlla squalifica
    if (penalty.dq && !_lastPenaltyDq) {
      _showPenaltyNotification('dq');
    }
    // Controlla nuovo warning
    else if (penalty.warnings > _lastPenaltyWarnings) {
      _showPenaltyNotification('warning');
    }
    // Controlla nuova penalità tempo
    else if (penalty.timeSec > _lastPenaltyTimeSec) {
      _showPenaltyNotification('time');
    }

    // Aggiorna i valori tracciati
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
    // Nascondi dopo 6 secondi
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

  String _formatDelta() {
    if (_driverData == null ||
        _driverData!.bestLapTime == null ||
        _driverData!.lastLapTime == null) {
      return '---';
    }

    final diff = _driverData!.lastLapTime! - _driverData!.bestLapTime!;
    final sign = diff > 0 ? '+' : '';
    return '$sign${diff.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            _buildBody(),

            // Banner bandiera animato
            if (_showFlagBanner && _raceData != null) _buildFlagBanner(),

            // Banner penalità animato
            if (_showPenaltyBanner && _driverData != null) _buildPenaltyBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kBrandColor),
            SizedBox(height: 16),
            Text(
              'Connessione in corso...',
              style: TextStyle(color: kMutedColor),
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

    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildMainDisplay()),
        if (_driverData != null) _buildGForceBar(),
        // _buildBottomInfo(),
      ],
    );
  }

  Widget _buildHeader() {
    final hasPenalty = _driverData?.penalty.hasAny ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          // Penalità indicator (se presenti) o LIVE indicator
          if (hasPenalty)
            _buildPenaltyIndicator()
          else
            _buildLiveIndicator(),
          const Spacer(),
          // Circuit name
          if (_raceData?.circuitName != null)
            Text(
              _raceData!.circuitName!.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white.withAlpha(150),
                letterSpacing: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _liveService.isConnected
            ? Colors.green.withAlpha(30)
            : Colors.red.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _liveService.isConnected
              ? Colors.green.withAlpha(150)
              : Colors.red.withAlpha(150),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _liveService.isConnected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _liveService.isConnected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: _liveService.isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyIndicator() {
    final penalty = _driverData!.penalty;

    // Squalificato
    if (penalty.dq) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(
              'DSQ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
    }

    // Penalità tempo e/o warning
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withAlpha(150)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          // Tempo penalità
          if (penalty.timeSec > 0)
            Text(
              '+${penalty.timeSec}s',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          // Separatore
          if (penalty.timeSec > 0 && penalty.warnings > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(
                width: 1,
                height: 12,
                color: Colors.orange.withAlpha(100),
              ),
            ),
          // Warnings
          if (penalty.warnings > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${penalty.warnings}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.flag, color: Colors.orange, size: 12),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMainDisplay() {
    final hasDriver = _driverData != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Status banner compatto
          if (_raceData != null) _buildStatusBanner(),

          const SizedBox(height: 16),

          // LAP NUMBER
          if (hasDriver)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LAP',
                    style: TextStyle(
                      color: Colors.white.withAlpha(100),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_driverData!.lapCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_raceData?.totalLaps != null) ...[
                    Text(
                      '/${_raceData!.totalLaps}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(100),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          const Spacer(flex: 1),

          // CURRENT LAP TIME - MASSIVE
          if (hasDriver) ...[
            Text(
              _formatCurrentLapTime(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'CURRENT LAP',
              style: TextStyle(
                color: Colors.white.withAlpha(80),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],

          const Spacer(flex: 1),

          // DELTA TIME
          if (hasDriver &&
              _driverData!.bestLapTime != null &&
              _driverData!.lastLapTime != null)
            _buildDeltaDisplay(),

          if (hasDriver) const SizedBox(height: 24),

          // LAST LAP & BEST LAP
          if (hasDriver) _buildLapComparison(),

          const Spacer(flex: 1),

          // Position and Gap
          if (hasDriver) _buildPositionRow(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final race = _raceData!;
    Color bannerColor;
    String bannerText;

    switch (race.status) {
      case 'YELLOW FLAG':
        bannerColor = const Color(0xFFFFD700);
        bannerText = 'YELLOW FLAG';
        break;
      case 'RED FLAG':
        bannerColor = Colors.red;
        bannerText = 'RED FLAG';
        break;
      case 'FORMATION LAP':
        bannerColor = Colors.orange;
        bannerText = 'FORMATION LAP';
        break;
      case 'FINITA':
        bannerColor = kMutedColor;
        bannerText = 'FINISHED';
        break;
      default:
        bannerColor = kBrandColor;
        bannerText = 'RACING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bannerColor.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bannerColor.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bannerColor,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            bannerText,
            style: TextStyle(
              color: bannerColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          if (race.remainingSeconds != null) ...[
            const SizedBox(width: 16),
            Text(
              race.formattedRemainingTime,
              style: TextStyle(
                color: bannerColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeltaDisplay() {
    final deltaStr = _formatDelta();
    final isPositive = deltaStr.startsWith('+');
    final isNegative = deltaStr.startsWith('-');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: isNegative
            ? Colors.green.withAlpha(25)
            : isPositive
                ? Colors.red.withAlpha(25)
                : Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNegative
              ? Colors.green.withAlpha(80)
              : isPositive
                  ? Colors.red.withAlpha(80)
                  : Colors.white.withAlpha(30),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'DELTA',
            style: TextStyle(
              color: (isNegative
                      ? Colors.green
                      : isPositive
                          ? Colors.red
                          : Colors.white)
                  .withAlpha(180),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            deltaStr,
            style: TextStyle(
              color: isNegative
                  ? Colors.green
                  : isPositive
                      ? Colors.red
                      : Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapComparison() {
    return Row(
      children: [
        // LAST LAP
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Column(
              children: [
                Text(
                  'LAST LAP',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _driverData!.formattedLastLapTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // BEST LAP
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.purple.withAlpha(20),
                  Colors.purple.withAlpha(10),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withAlpha(60)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.emoji_events,
                      color: Colors.purple.withAlpha(180),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'BEST LAP',
                      style: TextStyle(
                        color: Colors.purple.withAlpha(200),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _driverData!.formattedBestLapTime,
                  style: TextStyle(
                    color: Colors.purple.shade200,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPositionRow() {
    final driver = _driverData!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kBrandColor.withAlpha(20),
            kBrandColor.withAlpha(10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBrandColor.withAlpha(60)),
      ),
      child: Row(
        children: [
          // Position
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POS',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'P${driver.position}',
                style: TextStyle(
                  color: driver.isLeader ? kBrandColor : Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Gap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GAP',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  driver.isLeader ? 'LEADER' : driver.gapToLeader,
                  style: TextStyle(
                    color: driver.isLeader ? kBrandColor : Colors.white,
                    fontSize: driver.isLeader ? 20 : 24,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // Driver info
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (driver.tag != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kBrandColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    driver.tag!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                driver.fullName,
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGForceBar() {
    final gforce = _driverData!.gforce;
    final gLong = gforce?.long?.abs() ?? 0.0;
    final isAccel = (gforce?.long ?? 0.0) > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'G-FORCE',
                style: TextStyle(
                  color: Colors.white.withAlpha(100),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              Row(
                children: [
                  // Speed
                  if (_driverData!.speedKmh != null)
                    Text(
                      '${_driverData!.speedKmh!.toInt()} km/h',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withAlpha(150),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  const SizedBox(width: 16),
                  Text(
                    gforce?.total?.toStringAsFixed(2) ?? '-.-',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Text(
                    ' G',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kMutedColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // BRAKE indicator
              Text(
                'BRAKE',
                style: TextStyle(
                  color: Colors.red.withAlpha(150),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              // Decel bar
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.white.withAlpha(15),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: isAccel ? 0.0 : (gLong / 2.5).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.withAlpha(180),
                              Colors.red,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withAlpha(100),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Accel bar
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.white.withAlpha(15),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: isAccel ? (gLong / 2.5).clamp(0.0, 1.0) : 0.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(
                            colors: [
                              Colors.green,
                              Colors.green.withAlpha(180),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withAlpha(100),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ACCEL indicator
              Text(
                'ACCEL',
                style: TextStyle(
                  color: Colors.green.withAlpha(150),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          // Device ID
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bluetooth, color: kBrandColor.withAlpha(180), size: 14),
                const SizedBox(width: 8),
                Text(
                  widget.deviceId,
                  style: TextStyle(
                    color: Colors.white.withAlpha(150),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Global best lap
          if (_raceData?.globalBestLap != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kPulseColor.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPulseColor.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: kPulseColor.withAlpha(180), size: 14),
                  const SizedBox(width: 8),
                  Text(
                    _raceData!.formattedGlobalBestLap,
                    style: TextStyle(
                      color: kPulseColor.withAlpha(200),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
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
        subText = 'RACE IS ON - GO GO GO!';
        icon = Icons.flag_rounded;
        break;
      case 'FINITA':
        color = Colors.white;
        text = 'CHECKERED FLAG';
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
        return Positioned(
          top: 80,
          left: 20,
          right: 20,
          child: Transform.scale(
            scale: _flagAnimation.value,
            child: Opacity(
              opacity: _flagAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: isCheckered
                      ? null
                      : LinearGradient(
                          colors: [
                            color.withAlpha(240),
                            color.withAlpha(200),
                          ],
                        ),
                  color: isCheckered ? const Color(0xFF1A1A1A) : null,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: color.withAlpha(100),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            color: isCheckered ? Colors.white : Colors.white,
                            size: 28),
                        const SizedBox(width: 12),
                        Text(
                          text,
                          style: TextStyle(
                            color: isCheckered ? Colors.white : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subText,
                      style: TextStyle(
                        color: isCheckered
                            ? Colors.white.withAlpha(180)
                            : Colors.white.withAlpha(220),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
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
        return Positioned(
          top: 80,
          left: 20,
          right: 20,
          child: Transform.scale(
            scale: _flagAnimation.value,
            child: Opacity(
              opacity: _flagAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: isDq
                      ? null
                      : LinearGradient(
                          colors: [
                            color.withAlpha(240),
                            color.withAlpha(200),
                          ],
                        ),
                  color: isDq ? Colors.black : null,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDq ? Colors.white : color,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDq ? Colors.white : color).withAlpha(100),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subText,
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(6),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: Icon(
                Icons.timer_off_outlined,
                color: Colors.white.withAlpha(100),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'NO ACTIVE RACE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Waiting for race session to start.\nThis page will update automatically.',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: kBrandColor.withAlpha(15),
                border: Border.all(color: kBrandColor.withAlpha(50)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth, color: kBrandColor.withAlpha(180), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    widget.deviceId,
                    style: TextStyle(
                      color: kBrandColor.withAlpha(200),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
