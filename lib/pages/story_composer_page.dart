import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/session_model.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

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
      HapticFeedback.lightImpact();
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
      HapticFeedback.mediumImpact();

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
    HapticFeedback.lightImpact();
    setState(() {
      _backgroundImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // Story canvas
                  _buildStoryCanvas(session),
                  const SizedBox(height: 24),
                  // Editor controls
                  _buildEditorSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgColor, const Color(0xFF121212)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(Icons.close, color: kFgColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(40),
                  kPulseColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kPulseColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.auto_awesome, color: kPulseColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Story Editor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPulseColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kPulseColor.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 11, color: kPulseColor),
                      const SizedBox(width: 4),
                      Text(
                        'PULSE+',
                        style: TextStyle(
                          fontSize: 10,
                          color: kPulseColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Share button
          GestureDetector(
            onTap: _captureAndShare,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [kBrandColor, kBrandColor.withAlpha(200)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kBrandColor.withAlpha(60),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.share, size: 18, color: Colors.black),
                  SizedBox(width: 6),
                  Text(
                    'Condividi',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryCanvas(SessionModel session) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: _backgroundImage == null
                ? const Color(0xFF1a1a2e)
                : const Color(0xFF000000),
          ),
          clipBehavior: Clip.hardEdge,
          child: RepaintBoundary(
            key: _storyKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background image (or transparent if not set)
                if (_backgroundImage != null) ...[
                  Positioned.fill(
                    child: Image.file(
                      _backgroundImage!,
                      fit: BoxFit.cover,
                    ),
                  ),
                  // Blur overlay (only if image is set and blur > 0)
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
                  // Darken overlay (only if image is set)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(_darken),
                    ),
                  ),
                ],

                // Content overlay
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Branding - Logo RaceSense Pulse
                        Row(
                          children: [
                            Image.asset(
                              'assets/icon/allrspulselogoo.png',
                              height: 40,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),

                        const Spacer(),

                        // Track visualization
                        if (_showTrack && _trackPath.isNotEmpty)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(20),
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

                        // Stats section
                        if (_showStats) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                        color: _accentColor, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      session.location,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Stats grid
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StatBox(
                                        label: 'BEST LAP',
                                        value: session.bestLap != null
                                            ? _formatLap(session.bestLap!)
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
                                        value: session.lapCount.toString(),
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
    );
  }

  Widget _buildEditorSection() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(40),
                        kBrandColor.withAlpha(20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(60), width: 1.5),
                  ),
                  child: Center(
                    child: Icon(Icons.tune, color: kBrandColor, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Personalizza',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: kFgColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(
            height: 1,
            color: _kBorderColor,
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Background image selector
                _buildSectionTitle('Immagine di sfondo'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [
                                kBrandColor.withAlpha(30),
                                kBrandColor.withAlpha(15),
                              ],
                            ),
                            border: Border.all(color: kBrandColor.withAlpha(60)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library, color: kBrandColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _backgroundImage == null
                                    ? 'Scegli immagine'
                                    : 'Cambia immagine',
                                style: TextStyle(
                                  color: kBrandColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_backgroundImage != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _removeBackground,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: kErrorColor.withAlpha(20),
                            border: Border.all(color: kErrorColor.withAlpha(60)),
                          ),
                          child: Icon(Icons.delete_outline, color: kErrorColor, size: 20),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                // Darken slider
                _buildSliderControl(
                  label: 'Oscuramento',
                  icon: Icons.brightness_6,
                  value: _darken,
                  min: 0,
                  max: 0.85,
                  onChanged: (v) => setState(() => _darken = v),
                  displayValue: '${(_darken * 100).round()}%',
                ),

                // Blur slider (only if background image is set)
                if (_backgroundImage != null) ...[
                  const SizedBox(height: 20),
                  _buildSliderControl(
                    label: 'Sfocatura',
                    icon: Icons.blur_on,
                    value: _blur,
                    min: 0,
                    max: 10,
                    onChanged: (v) => setState(() => _blur = v),
                    displayValue: _blur.toStringAsFixed(1),
                  ),
                ],

                const SizedBox(height: 24),

                // Accent color picker
                _buildSectionTitle('Colore accent'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ColorDot(
                      color: const Color(0xFFFC4C02),
                      selected: _accentColor == const Color(0xFFFC4C02),
                      onTap: () => setState(() => _accentColor = const Color(0xFFFC4C02)),
                    ),
                    _ColorDot(
                      color: kBrandColor,
                      selected: _accentColor == kBrandColor,
                      onTap: () => setState(() => _accentColor = kBrandColor),
                    ),
                    _ColorDot(
                      color: kPulseColor,
                      selected: _accentColor == kPulseColor,
                      onTap: () => setState(() => _accentColor = kPulseColor),
                    ),
                    _ColorDot(
                      color: const Color(0xFF00D9FF),
                      selected: _accentColor == const Color(0xFF00D9FF),
                      onTap: () => setState(() => _accentColor = const Color(0xFF00D9FF)),
                    ),
                    _ColorDot(
                      color: const Color(0xFF4CD964),
                      selected: _accentColor == const Color(0xFF4CD964),
                      onTap: () => setState(() => _accentColor = const Color(0xFF4CD964)),
                    ),
                    _ColorDot(
                      color: const Color(0xFFFF2D55),
                      selected: _accentColor == const Color(0xFFFF2D55),
                      onTap: () => setState(() => _accentColor = const Color(0xFFFF2D55)),
                    ),
                    _ColorDot(
                      color: Colors.white,
                      selected: _accentColor == Colors.white,
                      onTap: () => setState(() => _accentColor = Colors.white),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Divider
                Container(
                  height: 1,
                  color: _kBorderColor,
                ),
                const SizedBox(height: 20),

                // Toggle switches
                _buildToggleOption(
                  icon: Icons.route,
                  label: 'Mostra tracciato',
                  value: _showTrack,
                  onChanged: (v) => setState(() => _showTrack = v),
                ),
                const SizedBox(height: 12),
                _buildToggleOption(
                  icon: Icons.analytics_outlined,
                  label: 'Mostra statistiche',
                  value: _showStats,
                  onChanged: (v) => setState(() => _showStats = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: kMutedColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required String displayValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: kMutedColor, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: kBrandColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: kBrandColor,
            inactiveTrackColor: _kBorderColor,
            thumbColor: kBrandColor,
            overlayColor: kBrandColor.withAlpha(30),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleOption({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: value ? kBrandColor.withAlpha(12) : Colors.white.withAlpha(5),
        border: Border.all(
          color: value ? kBrandColor.withAlpha(50) : _kBorderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? kBrandColor.withAlpha(25) : kMutedColor.withAlpha(15),
              border: Border.all(
                color: value ? kBrandColor.withAlpha(80) : kMutedColor.withAlpha(40),
              ),
            ),
            child: Icon(icon, color: value ? kBrandColor : kMutedColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: value ? kFgColor : kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
            activeColor: kBrandColor,
            inactiveThumbColor: kMutedColor,
            inactiveTrackColor: _kBorderColor,
          ),
        ],
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

// Stats box widget
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
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? kBrandColor : _kBorderColor,
            width: selected ? 3 : 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: selected
            ? Icon(
                Icons.check,
                color: color == Colors.white ? Colors.black : Colors.white,
                size: 20,
              )
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
