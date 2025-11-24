import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme.dart';
import 'live_session_page.dart';

class GpsWaitPage extends StatefulWidget {
  const GpsWaitPage({super.key});

  @override
  State<GpsWaitPage> createState() => _GpsWaitPageState();
}

class _GpsWaitPageState extends State<GpsWaitPage> {
  StreamSubscription<Position>? _gpsSub;
  Timer? _timer;

  bool _checkingPermissions = true;
  bool _hasError = false;
  String _errorMessage = '';

  double? _accuracy; // in metri
  DateTime? _lastUpdate;
  int _elapsedSeconds = 0;

  // Soglia “fix buono” (puoi tarare)
  static const double _targetAccuracy = 20.0; // metri
  static const double _worstAccuracy = 60.0; // per grafica/progress

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _checkingPermissions = false;
          _hasError = true;
          _errorMessage =
              'Il GPS è disattivato. Attivalo dalle impostazioni del dispositivo.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _checkingPermissions = false;
          _hasError = true;
          _errorMessage =
              'Permesso GPS negato. Concedi l’accesso alla posizione dalle impostazioni.';
        });
        return;
      }

      // Ok, permessi a posto → iniziamo stream + timer
      _startGpsStream();
      _startElapsedTimer();

      setState(() {
        _checkingPermissions = false;
      });
    } catch (e) {
      setState(() {
        _checkingPermissions = false;
        _hasError = true;
        _errorMessage = 'Errore inizializzazione GPS: $e';
      });
    }
  }

  void _startGpsStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        setState(() {
          _accuracy = pos.accuracy;
          _lastUpdate = DateTime.now();
        });
      },
      onError: (e) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Errore stream GPS: $e';
        });
      },
    );
  }

  void _startElapsedTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  bool get _hasFix {
    if (_accuracy == null) return false;
    if (_elapsedSeconds < 3) return false;

    // Se l'ultimo sample è troppo vecchio, considera il fix perso
    if (_lastUpdate != null) {
      final age = DateTime.now().difference(_lastUpdate!);
      if (age.inSeconds > 6) {
        return false;
      }
    }

    return _accuracy! <= _targetAccuracy;
  }

  double get _qualityProgress {
    if (_accuracy == null) return 0.0;

    // clamp inverso: 0 = pessimo, 1 = ottimo
    final clampedAcc = _accuracy!.clamp(0.0, _worstAccuracy);
    final v = 1.0 - (clampedAcc / _worstAccuracy); // 0..1
    return v;
  }

  String get _statusLabel {
    if (_checkingPermissions) return 'Controllo permessi GPS...';
    if (_hasError) return 'Problema con il GPS';

    if (_accuracy == null) {
      return 'In attesa del primo fix...';
    }

    if (_accuracy! > 30) {
      return 'Segnale debole, attendi ancora un po’';
    } else if (_accuracy! > 15) {
      return 'Segnale in miglioramento...';
    } else if (!_hasFix) {
      return 'Quasi pronto, ancora un istante';
    } else {
      return 'GPS pronto, puoi iniziare la registrazione';
    }
  }

  Color get _indicatorColor {
    if (_hasError) return kErrorColor;
    if (_accuracy == null) return kMutedColor;

    if (_hasFix) return kBrandColor;

    // interpolate fra rosso e verde
    final start = kErrorColor;
    final end = kBrandColor;
    final t = _qualityProgress.clamp(0.0, 1.0);
    return Color.lerp(start, end, t) ?? kBrandColor;
  }

  void _goToLivePage() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LiveSessionPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Preparazione GPS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: const Color.fromRGBO(255, 255, 255, 0.06),
                      border: Border.all(color: kLineColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hasFix ? kBrandColor : kMutedColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'CELLULAR GPS',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: kMutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // const SizedBox(height: 16),

            // INDICATORE CENTRALE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [
                      Color.fromRGBO(255, 255, 255, 0.06),
                      Color.fromRGBO(255, 255, 255, 0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: kLineColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      _statusLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: kMutedColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildCircularIndicator(),
                    const SizedBox(height: 12),
                    if (_accuracy != null)
                      Text(
                        'Precisione stimata: ${_accuracy!.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kFgColor,
                        ),
                      )
                    else
                      const Text(
                        'In attesa del segnale...',
                        style: TextStyle(
                          fontSize: 13,
                          color: kFgColor,
                        ),
                      ),
                    // const SizedBox(height: 6),
                    // Text(
                    //   'Tempo di aggancio: ${_elapsedSeconds}s',
                    //   style: const TextStyle(
                    //     fontSize: 11,
                    //     color: kMutedColor,
                    //   ),
                    // ),
                    if (_hasError) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: kErrorColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            // CONSIGLI + BOX
// TITOLO "Consigli"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Consigli',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: kMutedColor,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

// BOX 1 — Dentro al circuito
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF15171E),
                      Color(0xFF101114),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: kLineColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.route_outlined,
                      color: kBrandColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Inizia la registrazione quando sei già dentro al circuito, '
                        'Racesense Pulse userà il tuo giro per costruire '
                        'automaticamente il tracciato e rilevare start/finish.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: kFgColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // BOX 2 — Posizionamento telefono / dispositivo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF14161C),
                      Color(0xFF101015),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: kLineColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.phone_android_outlined,
                      color: kPulseColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Tieni il telefono o il dispositivo con il cielo ben visibile e in una posizione stabile.\n'
                        'Evita tasche schermate o punti in cui la carrozzeria copre troppo il segnale GPS: '
                        'aiuta a mantenere il fix preciso durante tutta la sessione.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: kFgColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // BOTTONE
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: (!_hasError && _hasFix) ? _goToLivePage : null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text(
                      'Inizia registrazione LIVE',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_hasFix && !_hasError)
                    const Text(
                      'Il pulsante si attiverà quando il GPS avrà un buon fix.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: kMutedColor,
                      ),
                    ),
                  if (_hasError)
                    const Text(
                      'Risolvi il problema con il GPS per procedere.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: kErrorColor,
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

  Widget _buildCircularIndicator() {
    final progress = _qualityProgress.clamp(0.0, 1.0);
    final color = _indicatorColor;

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // cerchio di base
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color.fromRGBO(255, 255, 255, 0.03),
              border: Border.all(color: kLineColor),
            ),
          ),
          // progress "arco"
          CustomPaint(
            size: const Size(120, 120),
            painter: _ArcPainter(
              progress: progress,
              color: color,
            ),
          ),
          // testo al centro
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: color,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                _hasFix ? 'FIX OK' : 'AGGANCIO',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;

  _ArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 10.0;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweep = 2 * math.pi * progress;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
