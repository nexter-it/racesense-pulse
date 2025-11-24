import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';

import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import 'feed_page.dart';
import 'dart:ui' as ui;

class ActivityDetailPage extends StatelessWidget {
  static const routeName = '/activity';

  const ActivityDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PulseActivity activity =
        ModalRoute.of(context)!.settings.arguments as PulseActivity;

    // Mock dati telemetrici (in futuro arrivano dal DB)
    // Mock dati telemetrici (in futuro arrivano dal DB)
    final random = math.Random();
    final samples = 600; // ~10 minuti a 10 Hz

    final speed = List<double>.generate(
      samples,
      (i) => 90 + math.sin(i / 20) * 30 + random.nextDouble() * 4,
    );
    final gForce = List<double>.generate(
      samples,
      (i) => 1.1 + math.sin(i / 12) * 0.2 + random.nextDouble() * 0.05,
    );
    final accuracy = List<double>.generate(
      samples,
      (i) => 0.4 + random.nextDouble() * 0.6,
    );

    final time = List<Duration>.generate(
      samples,
      (i) => Duration(milliseconds: i * 100),
    );

    final mockPath = List<ll.LatLng>.generate(
      samples,
      (i) => ll.LatLng(
        45.0 + math.sin(i / 40) * 0.0018,
        9.0 + math.cos(i / 40) * 0.0022,
      ),
    );

    // 🔹 finto elenco lap: 4 giri uguali sulla durata totale
    final totalMs = time.last.inMilliseconds;
    final perLapMs = (totalMs / 4).round();
    final laps = List<Duration>.generate(
      4,
      (_) => Duration(milliseconds: perLapMs),
    );

    // 🔹 finto gpsTrack a partire dalla path (serve per l’overview combinata)
    final gpsTrack = mockPath
        .map(
          (p) => Position(
            latitude: p.latitude,
            longitude: p.longitude,
            timestamp: DateTime.now(),
            accuracy: 3,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          ),
        )
        .toList();

    final deviceUsed = "RaceBox Mini S"; // ⬅️ puoi cambiarlo o leggere dal DB

    return Scaffold(
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
          children: [
            _TopBar(activity: activity, device: deviceUsed),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // _HeroTrack(activity: activity),
                    // const SizedBox(height: 20),
                    _SessionOverviewPanel(
                      gpsTrack: gpsTrack,
                      smoothPath: mockPath,
                      speedHistory: speed,
                      gForceHistory: gForce,
                      gpsAccuracyHistory: accuracy,
                      timeHistory: time,
                      laps: laps,
                    ),
                    const SizedBox(height: 24),
                    _StatsRow(activity: activity),

                    const SizedBox(height: 24),
                    // _SectorList(),
                    // const SizedBox(height: 24),
                    _ActionsRow(activity: activity),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------
   TOPBAR
------------------------------------------------------------- */

class _TopBar extends StatelessWidget {
  final PulseActivity activity;
  final String device;

  const _TopBar({required this.activity, required this.device});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RACESENSE PULSE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: kMutedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                activity.circuitName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          PulseChip(
            label: Text(device),
            icon: Icons.sensors,
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------
   HERO TRACK
------------------------------------------------------------- */

class _HeroTrack extends StatelessWidget {
  final PulseActivity activity;

  const _HeroTrack({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
        gradient: const LinearGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, 0.06),
            Color.fromRGBO(0, 0, 0, 0.80),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CustomPaint(
                painter: _DetailTrackPainter(),
              ),
            ),
          ),
          // Positioned(
          //   left: 16,
          //   bottom: 16,
          //   right: 16,
          //   child: Row(
          //     children: [
          //       Column(
          //         crossAxisAlignment: CrossAxisAlignment.start,
          //         children: [
          //           Text(
          //             activity.circuitName,
          //             style: const TextStyle(
          //               fontWeight: FontWeight.w900,
          //               fontSize: 16,
          //             ),
          //           ),
          //           const SizedBox(height: 2),
          //           Text(
          //             '${activity.city}, ${activity.country}',
          //             style: const TextStyle(
          //               color: kMutedColor,
          //               fontSize: 12,
          //             ),
          //           ),
          //         ],
          //       ),
          //       const Spacer(),
          //       Column(
          //         crossAxisAlignment: CrossAxisAlignment.end,
          //         children: [
          //           const Text(
          //             'BEST LAP',
          //             style: TextStyle(
          //               fontSize: 11,
          //               letterSpacing: 1,
          //               color: kMutedColor,
          //               fontWeight: FontWeight.w700,
          //             ),
          //           ),
          //           Text(
          //             activity.bestLap,
          //             style: const TextStyle(
          //               fontSize: 22,
          //               fontWeight: FontWeight.w900,
          //               color: kPulseColor,
          //             ),
          //           ),
          //         ],
          //       ),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }
}

class _DetailTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0A0A0A);
    canvas.drawRect(Offset.zero & size, bg);

    final center = Offset(size.width / 2, size.height / 2);
    final r = size.height * 0.34;

    final border = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.12)
      ..strokeWidth = 15
      ..style = PaintingStyle.stroke;

    final track = Paint()
      ..color = const Color.fromRGBO(90, 90, 97, 1)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;

    final path = Path()..addOval(Rect.fromCircle(center: center, radius: r));

    canvas.drawPath(path, border);
    canvas.drawPath(path, track);

    canvas.drawLine(
      Offset(center.dx + r, center.dy - 18),
      Offset(center.dx + r, center.dy + 18),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

/* -------------------------------------------------------------
   STATISTICHE
------------------------------------------------------------- */

class _StatsRow extends StatelessWidget {
  final PulseActivity activity;

  const _StatsRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(label: "GIRI", value: activity.laps.toString()),
        const SizedBox(width: 12),
        _StatCard(label: "DISTANZA", value: "${activity.distanceKm} km"),
        const SizedBox(width: 12),
        _StatCard(label: "BEST LAP", value: activity.bestLap, highlight: true),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatCard({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF10121A),
          border: Border.all(
            color: highlight ? kPulseColor : kLineColor,
            width: highlight ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: kMutedColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: highlight ? kPulseColor : kFgColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------
   DASHBOARD TECNICA (grafico + mappa + metriche)
------------------------------------------------------------- */

class _SessionTechDashboard extends StatefulWidget {
  final List<double> speed;
  final List<double> gForce;
  final List<double> accuracy;
  final List<Duration> time;
  final List<ll.LatLng> path;

  const _SessionTechDashboard({
    required this.speed,
    required this.gForce,
    required this.accuracy,
    required this.time,
    required this.path,
  });

  @override
  State<_SessionTechDashboard> createState() => _SessionTechDashboardState();
}

enum _MetricView { speed, g, accuracy }

class _SessionTechDashboardState extends State<_SessionTechDashboard> {
  _MetricView view = _MetricView.speed;
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.time.length - 1;
    selected = selected.clamp(0, total);

    final xs = List<double>.generate(total, (i) {
      return (widget.time[i].inMilliseconds -
              widget.time.first.inMilliseconds) /
          1000;
    });

    final spotsSpeed =
        List<FlSpot>.generate(total, (i) => FlSpot(xs[i], widget.speed[i]));
    final spotsG =
        List<FlSpot>.generate(total, (i) => FlSpot(xs[i], widget.gForce[i]));
    final spotsA =
        List<FlSpot>.generate(total, (i) => FlSpot(xs[i], widget.accuracy[i]));

    final curX = xs[selected];

    // current metric values
    final curV = widget.speed[selected];
    final curG = widget.gForce[selected];
    final curA = widget.accuracy[selected];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF050608),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TELEMETRIA",
            style: TextStyle(
              fontSize: 15,
              color: kMutedColor,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 16),

          // Circuit viewer
          _TelemetryTrack(path: widget.path, selectedIndex: selected),

          const SizedBox(height: 20),

          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: xs.first,
                maxX: xs.last,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: kLineColor.withOpacity(0.25), strokeWidth: 0.6),
                  getDrawingVerticalLine: (_) => FlLine(
                      color: kLineColor.withOpacity(0.2), strokeWidth: 0.6),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      reservedSize: 18,
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(
                        "${v.toStringAsFixed(0)}s",
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (e, r) {
                    if (r?.lineBarSpots != null &&
                        r!.lineBarSpots!.isNotEmpty) {
                      setState(
                          () => selected = r.lineBarSpots!.first.spotIndex);
                    }
                  },
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: curX,
                      color: Colors.white.withOpacity(0.7),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    )
                  ],
                ),
                lineBarsData: [
                  _line(
                      spotsSpeed, Colors.redAccent, view == _MetricView.speed),
                  _line(spotsG, Colors.greenAccent, view == _MetricView.g),
                  _line(
                      spotsA, Colors.blueAccent, view == _MetricView.accuracy),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Metric selectors
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metricChip("Speed", Colors.redAccent, view == _MetricView.speed,
                  () {
                setState(() => view = _MetricView.speed);
              }),
              _metricChip("G-Force", Colors.greenAccent, view == _MetricView.g,
                  () {
                setState(() => view = _MetricView.g);
              }),
              _metricChip(
                  "Accuracy", Colors.blueAccent, view == _MetricView.accuracy,
                  () {
                setState(() => view = _MetricView.accuracy);
              }),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            "t=${curX.toStringAsFixed(2)}s   "
            "v=${curV.toStringAsFixed(1)} km/h   "
            "g=${curG.toStringAsFixed(2)}   "
            "acc=${curA.toStringAsFixed(2)} m",
            style: const TextStyle(
              color: kMutedColor,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color c, bool active) {
    return LineChartBarData(
      spots: spots,
      color: active ? c : c.withOpacity(0.25),
      isCurved: false,
      barWidth: active ? 2.3 : 1.4,
      dotData: const FlDotData(show: false),
    );
  }

  Widget _metricChip(String label, Color c, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? c.withOpacity(0.18) : Colors.transparent,
          border: Border.all(
            color: selected ? c : c.withOpacity(0.3),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------
   CIRCUITO GPS (mini viewer)
------------------------------------------------------------- */

class _TelemetryTrack extends StatelessWidget {
  final List<ll.LatLng> path;
  final int selectedIndex;

  const _TelemetryTrack({required this.path, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.7,
      child: CustomPaint(
        painter: _TelemetryTrackPainter(path, selectedIndex),
      ),
    );
  }
}

class _TelemetryTrackPainter extends CustomPainter {
  final List<ll.LatLng> path;
  final int idx;

  _TelemetryTrackPainter(this.path, this.idx);

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    final bg = Paint()..color = const Color(0xFF0F0F15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      bg,
    );

    final grid = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    const g = 8;
    for (int i = 1; i < g; i++) {
      canvas.drawLine(Offset(size.width / g * i, 0),
          Offset(size.width / g * i, size.height), grid);
      canvas.drawLine(Offset(0, size.height / g * i),
          Offset(size.width, size.height / g * i), grid);
    }

    // bounds
    double minLat = path.first.latitude;
    double maxLat = path.first.latitude;
    double minLon = path.first.longitude;
    double maxLon = path.first.longitude;

    for (final p in path) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;

    final dLat = maxLat - minLat;
    final dLon = maxLon - minLon;

    final scale = (dLat == 0 || dLon == 0)
        ? 1.0
        : math.min(size.width * 0.78 / dLon, size.height * 0.78 / dLat);

    Offset proj(ll.LatLng p) {
      return Offset(
        (p.longitude - centerLon) * scale + size.width / 2,
        (centerLat - p.latitude) * scale + size.height / 2,
      );
    }

    final tp = Paint()
      ..color = kBrandColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pathShape = Path();
    for (int i = 0; i < path.length; i++) {
      final o = proj(path[i]);
      if (i == 0) {
        pathShape.moveTo(o.dx, o.dy);
      } else {
        pathShape.lineTo(o.dx, o.dy);
      }
    }

    canvas.drawPath(pathShape.shift(const Offset(1.6, 1.6)), shadow);
    canvas.drawPath(pathShape, tp);

    // marker
    if (idx >= 0 && idx < path.length) {
      final o = proj(path[idx]);
      final fill = Paint()..color = Colors.white;
      final stroke = Paint()
        ..color = kPulseColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(o, 7, fill);
      canvas.drawCircle(o, 7, stroke);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

/* -------------------------------------------------------------
   SECTOR LIST
------------------------------------------------------------- */

class _SectorList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sectors = [
      {"name": "S1", "time": "0:38.110"},
      {"name": "S2", "time": "0:39.880"},
      {"name": "S3", "time": "0:41.420"},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "SETTORI",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0E0F12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLineColor),
          ),
          child: Column(
            children: sectors.map((s) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          s["name"]!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          s["time"]!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (s != sectors.last)
                    const Divider(color: kLineColor, height: 0),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------
   ACTION BUTTONS
------------------------------------------------------------- */

class _ActionsRow extends StatelessWidget {
  final PulseActivity activity;

  const _ActionsRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.favorite_border),
            label: const Text('Preferito'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.share),
            label: const Text('Condividi'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kLineColor),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

enum _MetricFocus { speed, gForce, accuracy }

// ============================================================
// OVERVIEW: CIRCUITO + GRAFICO COMBINATO (stile Recap)
// ============================================================

class _SessionOverviewPanel extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<ll.LatLng> smoothPath;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;
  final List<Duration> laps;

  const _SessionOverviewPanel({
    required this.gpsTrack,
    required this.smoothPath,
    required this.speedHistory,
    required this.gForceHistory,
    required this.gpsAccuracyHistory,
    required this.timeHistory,
    required this.laps,
  });

  @override
  State<_SessionOverviewPanel> createState() => _SessionOverviewPanelState();
}

class _SessionOverviewPanelState extends State<_SessionOverviewPanel> {
  _MetricFocus _focus = _MetricFocus.speed;
  int _selectedIndex = 0;
  int _currentLap = 0;

  String _formatLap(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.timeHistory.length < 2 ||
        widget.speedHistory.isEmpty ||
        widget.gForceHistory.isEmpty ||
        widget.gpsAccuracyHistory.isEmpty ||
        widget.gpsTrack.isEmpty) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: const Center(
          child: Text(
            'Nessun dato registrato per questa sessione',
            style: TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    if (widget.laps.isEmpty) {
      widget.laps.add(widget.timeHistory.last);
    }

    final int lapCount = widget.laps.length;
    _currentLap = _currentLap.clamp(0, lapCount - 1);

    final Duration lapDuration = widget.laps[_currentLap];

// 👉 il grafico usa SEMPRE tutti i sample disponibili
    final List<int> indices = List<int>.generate(
      widget.timeHistory.length,
      (i) => i,
    );

    if (indices.length < 2) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: Center(
          child: Text(
            'Dati insufficienti per il giro ${_currentLap + 1}',
            style: const TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    final int len = indices.length;
    _selectedIndex = _selectedIndex.clamp(0, len - 1);

    final baseMs = widget.timeHistory[indices.first].inMilliseconds.toDouble();
    final List<double> xs = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return (widget.timeHistory[idx].inMilliseconds.toDouble() - baseMs) /
            1000.0;
      },
    );

    final List<FlSpot> speedSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.speedHistory[idx]);
      },
    );
    final List<FlSpot> gSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.gForceHistory[idx]);
      },
    );
    final List<FlSpot> accSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.gpsAccuracyHistory[idx]);
      },
    );

    double minY = speedSpots.first.y;
    double maxY = speedSpots.first.y;
    for (final s in [...speedSpots, ...gSpots, ...accSpots]) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final range = (maxY - minY).abs();
    final chartMinY = range > 0 ? minY - range * 0.1 : minY - 1;
    final chartMaxY = range > 0 ? maxY + range * 0.1 : maxY + 1;

    final cursorX = xs[_selectedIndex];
    final int globalIdx = indices[_selectedIndex];

    final List<ll.LatLng> lapPath = widget.smoothPath;

    ll.LatLng? marker;
    if (globalIdx < widget.gpsTrack.length) {
      final p = widget.gpsTrack[globalIdx];
      marker = ll.LatLng(p.latitude, p.longitude);
    }

    final double curSpeed = widget.speedHistory[globalIdx];
    final double curG = widget.gForceHistory[globalIdx];
    final double curAcc = widget.gpsAccuracyHistory[globalIdx];
    final double curT = xs[_selectedIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF050608),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                color: Colors.white70,
                onPressed: _currentLap > 0
                    ? () {
                        setState(() {
                          _currentLap--;
                          _selectedIndex = 0;
                        });
                      }
                    : null,
              ),
              Column(
                children: [
                  Text(
                    'LAP ${(_currentLap + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _formatLap(lapDuration),
                    style: const TextStyle(
                      fontSize: 12,
                      color: kMutedColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                color: Colors.white70,
                onPressed: _currentLap < lapCount - 1
                    ? () {
                        setState(() {
                          _currentLap++;
                          _selectedIndex = 0;
                        });
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CircuitTrackView(
            path: lapPath,
            marker: marker,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: xs.first,
                maxX: xs.last,
                minY: chartMinY,
                maxY: chartMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: range > 0 ? range / 4 : 1,
                  verticalInterval:
                      (xs.last - xs.first) > 0 ? (xs.last - xs.first) / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.35),
                    strokeWidth: 0.5,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.25),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(
                        color: kLineColor.withOpacity(0.7), width: 1),
                    bottom: BorderSide(
                        color: kLineColor.withOpacity(0.7), width: 1),
                    right: const BorderSide(color: Colors.transparent),
                    top: const BorderSide(color: Colors.transparent),
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toStringAsFixed(0)}s',
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: cursorX,
                      color: Colors.white.withOpacity(0.7),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.lineBarSpots == null ||
                        response.lineBarSpots!.isEmpty) {
                      return;
                    }
                    final spot = response.lineBarSpots!.first;
                    setState(() {
                      _selectedIndex = spot.spotIndex.clamp(0, len - 1);
                    });
                  },
                ),
                lineBarsData: [
                  _buildLine(speedSpots, Colors.redAccent,
                      _focus == _MetricFocus.speed),
                  _buildLine(gSpots, Colors.greenAccent,
                      _focus == _MetricFocus.gForce),
                  _buildLine(accSpots, Colors.blueAccent,
                      _focus == _MetricFocus.accuracy),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metricChip(
                label: 'Speed',
                color: Colors.redAccent,
                selected: _focus == _MetricFocus.speed,
                onTap: () => setState(() => _focus = _MetricFocus.speed),
              ),
              _metricChip(
                label: 'G-Force',
                color: Colors.greenAccent,
                selected: _focus == _MetricFocus.gForce,
                onTap: () => setState(() => _focus = _MetricFocus.gForce),
              ),
              _metricChip(
                label: 'Accuracy',
                color: Colors.blueAccent,
                selected: _focus == _MetricFocus.accuracy,
                onTap: () => setState(() => _focus = _MetricFocus.accuracy),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              't=${curT.toStringAsFixed(2)}s   '
              'v=${curSpeed.toStringAsFixed(1)} km/h   '
              'g=${curG.toStringAsFixed(2)}   '
              'acc=${curAcc.toStringAsFixed(2)} m',
              style: const TextStyle(
                fontSize: 11,
                color: kMutedColor,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _buildLine(
    List<FlSpot> spots,
    Color baseColor,
    bool focused,
  ) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: focused ? baseColor : baseColor.withOpacity(0.25),
      barWidth: focused ? 2.5 : 1.5,
      isStrokeCapRound: false,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _metricChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DISEGNO CIRCUITO (griglia + traccia + puntino posizione)
// ============================================================

class _CircuitTrackView extends StatelessWidget {
  final List<ll.LatLng> path;
  final ll.LatLng? marker;

  const _CircuitTrackView({
    required this.path,
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: const Center(
          child: Text(
            'Nessun dato GPS',
            style: TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1.6,
      child: CustomPaint(
        painter: _CircuitPainter(path: path, marker: marker),
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  final List<ll.LatLng> path;
  final ll.LatLng? marker;

  _CircuitPainter({
    required this.path,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFF101015)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
      bgPaint,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    const int gridLines = 8;
    final dx = size.width / gridLines;
    final dy = size.height / gridLines;
    for (int i = 1; i < gridLines; i++) {
      final x = dx * i;
      final y = dy * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double minLat = path.first.latitude;
    double maxLat = path.first.latitude;
    double minLon = path.first.longitude;
    double maxLon = path.first.longitude;
    for (final p in path) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final dLat = (maxLat - minLat).abs();
    final dLon = (maxLon - minLon).abs();

    final usableW = size.width * 0.8;
    final usableH = size.height * 0.8;
    final scale = (dLat == 0 || dLon == 0)
        ? 1.0
        : math.min(usableW / dLon, usableH / dLat);

    Offset _project(ll.LatLng p) {
      final x = (p.longitude - centerLon) * scale + size.width / 2;
      final y = (centerLat - p.latitude) * scale + size.height / 2;
      return Offset(x, y);
    }

    final ui.Path shadowPath = ui.Path();
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      if (i == 0) {
        shadowPath.moveTo(o.dx, o.dy);
      } else {
        shadowPath.lineTo(o.dx, o.dy);
      }
    }
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(shadowPath.shift(const Offset(2, 2)), shadowPaint);

    final ui.Path trackPath = ui.Path();
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      if (i == 0) {
        trackPath.moveTo(o.dx, o.dy);
      } else {
        trackPath.lineTo(o.dx, o.dy);
      }
    }
    final trackPaint = Paint()
      ..color = kBrandColor.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(trackPath, trackPaint);

    if (marker != null) {
      final o = _project(marker!);
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final markerBorder = Paint()
        ..color = kPulseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(o, 7, markerPaint);
      canvas.drawCircle(o, 7, markerBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.marker != marker;
  }
}
