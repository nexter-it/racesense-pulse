import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/session_model.dart';
import '../theme.dart';

class StoryComposerPage extends StatefulWidget {
  final SessionModel session;

  const StoryComposerPage({super.key, required this.session});

  @override
  State<StoryComposerPage> createState() => _StoryComposerPageState();
}

class _StoryComposerPageState extends State<StoryComposerPage> {
  final List<String> _backgrounds = [
    'assets/images/dr1.png',
    'assets/images/dr2.png',
    'assets/images/dr3.png',
    'assets/images/dr4.png',
    'assets/images/dr5.png',
  ];

  int _bgIndex = 0;
  double _darken = 0.4;
  Color _trackColor = kBrandColor;

  List<Offset> _trackPath = [];

  @override
  void initState() {
    super.initState();
    _trackPath = _buildTrackPath(widget.session.displayPath);
  }

  List<Offset> _buildTrackPath(List<Map<String, double>>? raw) {
    if (raw == null || raw.isEmpty) return [];
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    final pts = <Offset>[];
    for (final p in raw) {
      final x = p['lon'] ?? p['x'] ?? 0;
      final y = p['lat'] ?? p['y'] ?? 0;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
      pts.add(Offset(x, y));
    }
    final width = (maxX - minX).abs() == 0 ? 1 : (maxX - minX);
    final height = (maxY - minY).abs() == 0 ? 1 : (maxY - minY);

    return pts
        .map((p) => Offset(
              (p.dx - minX) / width * 300,
              (p.dy - minY) / height * 300,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Story Editor',
                    style: TextStyle(
                      color: kFgColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Condivisione su Instagram (stub: integra l\'API Instagram Stories)'),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Condividi'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kLineColor),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              _backgrounds[_bgIndex],
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(_darken),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(18.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'RACESENSE PULSE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Stats centrati, più grandi
                                  Center(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Time',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.8),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          session.bestLap != null
                                              ? _formatLap(session.bestLap!)
                                              : '--:--',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Distance',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.8),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${session.distanceKm.toStringAsFixed(1)} km',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Max speed',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.8),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${session.maxSpeedKmh.toStringAsFixed(0)} km/h',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Center(
                                    child: SizedBox(
                                      width: 180,
                                      height: 180,
                                      child: CustomPaint(
                                        painter: _TrackPainter(
                                          path: _trackPath,
                                          color: _trackColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  _StatLine(
                                    icon: Icons.track_changes,
                                    label: session.trackName,
                                    value: session.location,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0c0f15),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editor',
                          style: TextStyle(
                            color: kFgColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 70,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _backgrounds.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              return GestureDetector(
                                onTap: () => setState(() => _bgIndex = i),
                                child: Container(
                                  width: 70,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: i == _bgIndex
                                            ? kBrandColor
                                            : kLineColor),
                                    image: DecorationImage(
                                      image: AssetImage(_backgrounds[i]),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Darken',
                                style: TextStyle(color: kMutedColor)),
                            Expanded(
                              child: Slider(
                                value: _darken,
                                min: 0,
                                max: 0.8,
                                onChanged: (v) => setState(() => _darken = v),
                                activeColor: kBrandColor,
                                inactiveColor: kLineColor,
                              ),
                            ),
                            Text(
                              '${(_darken * 100).round()}%',
                              style: const TextStyle(color: kMutedColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Colore circuito',
                                style: TextStyle(color: kMutedColor)),
                            const SizedBox(width: 12),
                            _ColorDot(
                              color: kBrandColor,
                              selected: _trackColor == kBrandColor,
                              onTap: () =>
                                  setState(() => _trackColor = kBrandColor),
                            ),
                            const SizedBox(width: 8),
                            _ColorDot(
                              color: kPulseColor,
                              selected: _trackColor == kPulseColor,
                              onTap: () =>
                                  setState(() => _trackColor = kPulseColor),
                            ),
                            const SizedBox(width: 8),
                            _ColorDot(
                              color: Colors.white,
                              selected: _trackColor == Colors.white,
                              onTap: () =>
                                  setState(() => _trackColor = Colors.white),
                            ),
                          ],
                        ),
                      ],
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

  String _formatLap(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? kBrandColor : kLineColor,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final List<Offset> path;
  final Color color;

  _TrackPainter({required this.path, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final offsetPath = _fitPath(path, size);

    for (int i = 0; i < offsetPath.length - 1; i++) {
      canvas.drawLine(offsetPath[i], offsetPath[i + 1], paint);
    }
  }

  List<Offset> _fitPath(List<Offset> pts, Size size) {
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = (maxX - minX) == 0 ? 1 : (maxX - minX);
    final h = (maxY - minY) == 0 ? 1 : (maxY - minY);
    final scale = 0.9 * math.min(size.width / w, size.height / h);
    final dx = size.width / 2 - ((minX + maxX) / 2) * scale;
    final dy = size.height / 2 - ((minY + maxY) / 2) * scale;

    return pts
        .map((p) => Offset(p.dx * scale + dx, p.dy * scale + dy))
        .toList();
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.color != color;
  }
}

class _StatLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kBrandColor, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: kMutedColor,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
