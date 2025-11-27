import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import 'activity_detail_page.dart';

import '../services/session_service.dart';
import '../models/session_model.dart';

import 'dart:math' as math;

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

class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionService = SessionService();

    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          const _TopBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
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
          Expanded(
            child: FutureBuilder<List<SessionModel>>(
              future: sessionService.getPublicSessions(limit: 20),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Errore nel caricamento delle attività',
                      style: const TextStyle(color: kErrorColor),
                    ),
                  );
                }

                final sessions = snapshot.data ?? [];

                if (sessions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Ancora nessuna attività pubblica',
                        style: TextStyle(color: kMutedColor),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                          .copyWith(bottom: 24),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final track2d = _buildTrack2dFromSession(session);
                    return _ActivityCard(
                      session: session,
                      track2d: track2d,
                    );
                  },
                );
              },
            ),
          ),
        ],
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
            child: FittedBox(
              fit: isNarrow ? BoxFit.scaleDown : BoxFit.none,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GradientText(
                    text: 'RACESENSE',
                    gradient: const LinearGradient(
                      colors: [
                        neon,
                        Color(0xFFE7FF4F),
                      ],
                    ),
                    shadowColor: neon.withOpacity(0.55),
                  ),
                  const SizedBox(width: 10),
                  _GradientText(
                    text: 'PULSE',
                    gradient: const LinearGradient(
                      colors: [
                        lilac,
                        Color(0xFFD9D4FF),
                      ],
                    ),
                    shadowColor: lilac.withOpacity(0.6),
                  ),
                ],
              ),
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

  const _ActivityCard({
    required this.session,
    required this.track2d,
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).pushNamed(
              ActivityDetailPage.routeName,
              arguments: session,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0E1118),
                  Color(0xFF0A0C11),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: kLineColor.withOpacity(0.45),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ----- HEADER PILOTA -----
                  Row(
                    children: [
                      _AvatarUser(userId: session.userId),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pilotName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@$pilotTag',
                              style: const TextStyle(
                                color: kMutedColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: const Color.fromRGBO(255, 255, 255, 0.04),
                          border: Border.all(
                            color: kLineColor.withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          _timeAgo(),
                          style: const TextStyle(
                            color: kMutedColor,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ----- HERO / TRACK PREVIEW -----
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kLineColor.withOpacity(0.35)),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.fromRGBO(255, 255, 255, 0.10),
                          Color.fromRGBO(255, 255, 255, 0.03),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          child: Container(
                            height: 140,
                            color: const Color.fromRGBO(6, 7, 12, 1),
                            child: CustomPaint(
                              painter: _MiniTrackPainter(
                                isPb: isPb,
                                path: track2d,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      circuitName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      city,
                                      style: const TextStyle(
                                        color: kMutedColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'BEST LAP',
                                    style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1.0,
                                      color: kMutedColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    bestLapText,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: isPb ? kPulseColor : Colors.white,
                                    ),
                                  ),
                                  if (isPb) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        color: kPulseColor.withOpacity(0.12),
                                      ),
                                      child: const Text(
                                        'PB',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: kPulseColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ----- CHIPS INFO -----
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      PulseChip(
                        icon: Icons.flag_outlined,
                        label: Text('${laps} giri'),
                      ),
                      PulseChip(
                        icon: Icons.speed,
                        label: Text(
                          '${distanceKm.toStringAsFixed(1)} km',
                        ),
                      ),
                      PulseChip(
                        icon: Icons.sports_motorsports_outlined,
                        label: Text(sessionType),
                      ),
                      // if (isPb)
                      //   const PulseChip(
                      //     label: Text('PB RACESENSE PULSE'),
                      //     icon: Icons.star_outline,
                      //   ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
