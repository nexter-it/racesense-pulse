import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';

import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import 'feed_page.dart';

class ActivityDetailPage extends StatelessWidget {
  static const routeName = '/activity';

  const ActivityDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PulseActivity activity =
        ModalRoute.of(context)!.settings.arguments as PulseActivity;

    // Mock dati telemetrici (in futuro arrivano dal DB)
    final random = math.Random();
    final samples = 600; // ~10 minuti a 10 Hz

    final speed = List<double>.generate(
        samples, (i) => 90 + math.sin(i / 20) * 30 + random.nextDouble() * 4);
    final gForce = List<double>.generate(samples,
        (i) => 1.1 + math.sin(i / 12) * 0.2 + random.nextDouble() * 0.05);
    final accuracy =
        List<double>.generate(samples, (i) => 0.4 + random.nextDouble() * 0.6);

    final time = List<Duration>.generate(
        samples, (i) => Duration(milliseconds: i * 100));

    final mockPath = List<ll.LatLng>.generate(
      samples,
      (i) => ll.LatLng(
          45.0 + math.sin(i / 40) * 0.0018, 9.0 + math.cos(i / 40) * 0.0022),
    );

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
                    _SessionTechDashboard(
                      speed: speed,
                      gForce: gForce,
                      accuracy: accuracy,
                      time: time,
                      path: mockPath,
                    ),
                    const SizedBox(height: 24),
                    _StatsRow(activity: activity),

                    const SizedBox(height: 24),
                    _SectorList(),
                    const SizedBox(height: 24),
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
