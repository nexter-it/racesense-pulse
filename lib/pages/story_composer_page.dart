import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/session_model.dart';
import '../theme.dart';

class StoryComposerPage extends StatefulWidget {
  final SessionModel session;

  const StoryComposerPage({super.key, required this.session});

  @override
  State<StoryComposerPage> createState() => _StoryComposerPageState();
}

class _StoryComposerPageState extends State<StoryComposerPage> {
  // Background image
  File? _backgroundImage;
  final ImagePicker _picker = ImagePicker();

  // Customization controls
  double _darken = 0.5;
  double _blur = 0.0;
  Color _accentColor = const Color(0xFFFC4C02); // Strava orange
  bool _showTrack = true;
  bool _showStats = true;

  // Track path
  List<Offset> _trackPath = [];

  // Global key for capturing the story as image
  final GlobalKey _storyKey = GlobalKey();

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

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          _backgroundImage = File(image.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore nel caricamento dell\'immagine: $e'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  Future<void> _captureAndShare() async {
    try {
      // Get the share button position for iPad popover (before async gap)
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin =
          box != null ? box.localToGlobal(Offset.zero) & box.size : null;

      // Capture the story widget as an image
      final RenderRepaintBoundary boundary =
          _storyKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/racesense_story.png').create();
      await file.writeAsBytes(pngBytes);

      // Share using system share sheet
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out my session on RaceSense Pulse! 🏁',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante la condivisione: $e'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  void _removeBackground() {
    setState(() {
      _backgroundImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: kFgColor),
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
                  ElevatedButton.icon(
                    onPressed: _captureAndShare,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Condividi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),

            // Story Preview
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Story canvas
                  RepaintBoundary(
                    key: _storyKey,
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const ui.Color.fromARGB(0, 192, 255, 3)),
                          color: const Color(0xFF000000),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Background image or gradient
                            if (_backgroundImage != null)
                              Positioned.fill(
                                child: Image.file(
                                  _backgroundImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF1a1a2e),
                                        Color(0xFF0f0f1e),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            // Blur overlay (if blur > 0)
                            if (_blur > 0)
                              Positioned.fill(
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: _blur,
                                    sigmaY: _blur,
                                  ),
                                  child: Container(
                                    color: Colors.transparent,
                                  ),
                                ),
                              ),

                            // Darken overlay
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(_darken),
                              ),
                            ),

                            // Content overlay
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Branding
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _accentColor,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: const Text(
                                            'RACESENSE PULSE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const Spacer(),

                                    // Track visualization
                                    if (_showTrack && _trackPath.isNotEmpty)
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          // decoration: BoxDecoration(
                                          //   color:
                                          //       Colors.black.withOpacity(0.3),
                                          //   borderRadius:
                                          //       BorderRadius.circular(24),
                                          //   border: Border.all(
                                          //     color:
                                          //         _accentColor.withOpacity(0.3),
                                          //     width: 2,
                                          //   ),
                                          // ),
                                          child: SizedBox(
                                            width: 150,
                                            height: 150,
                                            child: CustomPaint(
                                              painter: _TrackPainter(
                                                path: _trackPath,
                                                color: _accentColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    const Spacer(),

                                    // Stats section (Strava style)
                                    if (_showStats) ...[
                                      Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.4),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Track name
                                            Text(
                                              session.trackName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 24,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.location_on,
                                                    color: _accentColor,
                                                    size: 16),
                                                const SizedBox(width: 4),
                                                Text(
                                                  session.location,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.8),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 20),

                                            // Stats grid (Strava style)
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _StatBox(
                                                    label: 'BEST LAP',
                                                    value: session.bestLap !=
                                                            null
                                                        ? _formatLap(
                                                            session.bestLap!)
                                                        : '--:--',
                                                    color: _accentColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: _StatBox(
                                                    label: 'DISTANCE',
                                                    value:
                                                        '${session.distanceKm.toStringAsFixed(1)} km',
                                                    color: _accentColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _StatBox(
                                                    label: 'MAX SPEED',
                                                    value:
                                                        '${session.maxSpeedKmh.toStringAsFixed(0)} km/h',
                                                    color: _accentColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: _StatBox(
                                                    label: 'LAPS',
                                                    value: session.lapCount
                                                        .toString(),
                                                    color: _accentColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Editor controls
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0c0f15),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Personalizza',
                          style: TextStyle(
                            color: kFgColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Background image selector
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.photo_library, size: 20),
                                label: Text(_backgroundImage == null
                                    ? 'Scegli immagine'
                                    : 'Cambia immagine'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kLineColor,
                                  foregroundColor: kFgColor,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            if (_backgroundImage != null) ...[
                              const SizedBox(width: 12),
                              IconButton(
                                onPressed: _removeBackground,
                                icon: const Icon(Icons.delete_outline),
                                color: kErrorColor,
                                style: IconButton.styleFrom(
                                  backgroundColor: kLineColor,
                                  padding: const EdgeInsets.all(14),
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(color: kLineColor),
                        const SizedBox(height: 20),

                        // Darken slider
                        const Text(
                          'Oscuramento',
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.brightness_6,
                                color: kMutedColor, size: 18),
                            Expanded(
                              child: Slider(
                                value: _darken,
                                min: 0,
                                max: 0.85,
                                onChanged: (v) => setState(() => _darken = v),
                                activeColor: kBrandColor,
                                inactiveColor: kLineColor,
                              ),
                            ),
                            SizedBox(
                              width: 45,
                              child: Text(
                                '${(_darken * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: kFgColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Blur slider (only if background image is set)
                        if (_backgroundImage != null) ...[
                          const Text(
                            'Sfocatura',
                            style: TextStyle(
                              color: kMutedColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.blur_on,
                                  color: kMutedColor, size: 18),
                              Expanded(
                                child: Slider(
                                  value: _blur,
                                  min: 0,
                                  max: 10,
                                  onChanged: (v) => setState(() => _blur = v),
                                  activeColor: kBrandColor,
                                  inactiveColor: kLineColor,
                                ),
                              ),
                              SizedBox(
                                width: 45,
                                child: Text(
                                  _blur.toStringAsFixed(1),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: kFgColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Accent color picker
                        const Text(
                          'Colore accent',
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: [
                            _ColorDot(
                              color: const Color(0xFFFC4C02), // Strava orange
                              selected: _accentColor == const Color(0xFFFC4C02),
                              onTap: () => setState(
                                  () => _accentColor = const Color(0xFFFC4C02)),
                            ),
                            _ColorDot(
                              color: kBrandColor,
                              selected: _accentColor == kBrandColor,
                              onTap: () =>
                                  setState(() => _accentColor = kBrandColor),
                            ),
                            _ColorDot(
                              color: kPulseColor,
                              selected: _accentColor == kPulseColor,
                              onTap: () =>
                                  setState(() => _accentColor = kPulseColor),
                            ),
                            _ColorDot(
                              color: const Color(0xFF00D9FF), // Cyan
                              selected: _accentColor == const Color(0xFF00D9FF),
                              onTap: () => setState(
                                  () => _accentColor = const Color(0xFF00D9FF)),
                            ),
                            _ColorDot(
                              color: const Color(0xFF4CD964), // Green
                              selected: _accentColor == const Color(0xFF4CD964),
                              onTap: () => setState(
                                  () => _accentColor = const Color(0xFF4CD964)),
                            ),
                            _ColorDot(
                              color: const Color(0xFFFF2D55), // Red
                              selected: _accentColor == const Color(0xFFFF2D55),
                              onTap: () => setState(
                                  () => _accentColor = const Color(0xFFFF2D55)),
                            ),
                            _ColorDot(
                              color: Colors.white,
                              selected: _accentColor == Colors.white,
                              onTap: () =>
                                  setState(() => _accentColor = Colors.white),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(color: kLineColor),
                        const SizedBox(height: 20),

                        // Toggle switches
                        _ToggleOption(
                          label: 'Mostra tracciato',
                          value: _showTrack,
                          onChanged: (v) => setState(() => _showTrack = v),
                        ),
                        const SizedBox(height: 12),
                        _ToggleOption(
                          label: 'Mostra statistiche',
                          value: _showStats,
                          onChanged: (v) => setState(() => _showStats = v),
                        ),

                        const SizedBox(height: 30),
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

// Stats box widget (Strava style)
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.9),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// Color picker dot
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? kBrandColor : kLineColor,
            width: selected ? 3 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

// Track painter
class _TrackPainter extends CustomPainter {
  final List<Offset> path;
  final Color color;

  _TrackPainter({required this.path, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    // Glow effect
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Main track
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final offsetPath = _fitPath(path, size);

    // Draw glow first
    for (int i = 0; i < offsetPath.length - 1; i++) {
      canvas.drawLine(offsetPath[i], offsetPath[i + 1], glowPaint);
    }

    // Draw main track
    for (int i = 0; i < offsetPath.length - 1; i++) {
      canvas.drawLine(offsetPath[i], offsetPath[i + 1], paint);
    }

    // Draw start/finish marker
    if (offsetPath.isNotEmpty) {
      final startPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawCircle(offsetPath.first, 8, startPaint);
      canvas.drawCircle(
          offsetPath.first,
          6,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);
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
    final scale = 0.85 * math.min(size.width / w, size.height / h);
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

// Toggle option widget
class _ToggleOption extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleOption({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: kFgColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: kBrandColor,
          inactiveThumbColor: kMutedColor,
          inactiveTrackColor: kLineColor,
        ),
      ],
    );
  }
}
