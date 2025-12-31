import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/post_processing_service.dart';
import '../theme.dart';

/// Pagina per disegnare manualmente la linea Start/Finish su una traccia GPS
///
/// Flusso RaceChrono Pro:
/// 1. Mostra traccia GPS completa sulla mappa
/// 2. Utente tap su 2 punti per definire linea S/F
/// 3. Valida che la linea intersechi la traccia
/// 4. Esegue post-processing per calcolare lap
/// 5. Mostra anteprima risultati
class DrawFinishLinePage extends StatefulWidget {
  final List<Position> gpsTrack;
  final String? trackName;
  final bool usedBleDevice;

  const DrawFinishLinePage({
    Key? key,
    required this.gpsTrack,
    this.trackName,
    this.usedBleDevice = false,
  }) : super(key: key);

  @override
  State<DrawFinishLinePage> createState() => _DrawFinishLinePageState();
}

// Premium UI constants
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class _DrawFinishLinePageState extends State<DrawFinishLinePage> {
  final MapController _mapController = MapController();

  LatLng? _finishLineStart;
  LatLng? _finishLineEnd;

  bool _isProcessing = false;
  PostProcessingResult? _processingResult;
  String? _errorMessage;

  List<LatLng> _gpsPath = [];

  @override
  void initState() {
    super.initState();
    _buildGpsPath();
  }

  /// Costruisce path dalla traccia GPS
  void _buildGpsPath() {
    if (widget.gpsTrack.isEmpty) return;
    _gpsPath = widget.gpsTrack
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  /// Gestisce tap sulla mappa per scegliere punti linea S/F
  void _onMapTap(TapPosition tapPosition, LatLng position) {
    if (_finishLineStart == null) {
      setState(() {
        _finishLineStart = position;
        _errorMessage = null;
      });
    } else if (_finishLineEnd == null) {
      setState(() {
        _finishLineEnd = position;
        _errorMessage = null;
      });

      // Valida e processa automaticamente
      _validateAndProcess();
    }
  }

  /// Valida linea S/F e esegue post-processing
  Future<void> _validateAndProcess() async {
    if (_finishLineStart == null || _finishLineEnd == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Valida che la linea intersechi la traccia
      final isValid = PostProcessingService.validateTrackAndFinishLine(
        gpsTrack: widget.gpsTrack,
        finishLineStart: _finishLineStart!,
        finishLineEnd: _finishLineEnd!,
      );

      if (!isValid) {
        setState(() {
          _errorMessage = 'La linea Start/Finish non interseca la traccia GPS.\n'
              'Riposiziona i punti sulla traccia.';
          _isProcessing = false;
        });
        return;
      }

      // Esegui post-processing
      final result = PostProcessingService.processTrack(
        gpsTrack: widget.gpsTrack,
        finishLineStart: _finishLineStart!,
        finishLineEnd: _finishLineEnd!,
        includeFormationLap: true,
      );

      if (result.laps.isEmpty) {
        setState(() {
          _errorMessage = 'Nessun giro completo rilevato.\n'
              'Assicurati di aver fatto almeno 2 passaggi sulla linea S/F.';
          _isProcessing = false;
        });
        return;
      }

      setState(() {
        _processingResult = result;
        _isProcessing = false;
      });

      // Mostra dialog con risultati
      _showResultsDialog(result);
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore durante il processing: $e';
        _isProcessing = false;
      });
    }
  }

  /// Mostra dialog con risultati post-processing - Premium style
  void _showResultsDialog(PostProcessingResult result) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBrandColor.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline, color: kBrandColor, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Post-Processing Completato',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 20),

              // Stats summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kTileColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBorderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryTile(
                        Icons.my_location,
                        '${result.crossings.length}',
                        'Crossing',
                        const Color(0xFF5AC8FA),
                      ),
                    ),
                    Container(width: 1, height: 50, color: _kBorderColor),
                    Expanded(
                      child: _summaryTile(
                        Icons.loop,
                        '${result.laps.length}',
                        'Giri',
                        const Color(0xFF4CD964),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Laps list
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kTileColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.format_list_numbered, color: kMutedColor, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Giri rilevati',
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: result.laps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final lap = result.laps[index];
                          final lapNumber = lap.isFormationLap ? 'OUT' : '#${lap.lapNumber}';
                          final duration = _formatDuration(lap.duration);
                          final distance = (lap.distanceMeters / 1000).toStringAsFixed(2);

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: lap.isFormationLap
                                  ? Colors.orange.withAlpha(15)
                                  : kBrandColor.withAlpha(10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: lap.isFormationLap
                                    ? Colors.orange.withAlpha(40)
                                    : kBrandColor.withAlpha(30),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  alignment: Alignment.center,
                                  child: Text(
                                    lapNumber,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: lap.isFormationLap ? Colors.orange : kBrandColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    duration,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${distance} km',
                                  style: TextStyle(
                                    color: kMutedColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Best lap & track length
              if (result.laps.length > 1) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final validLaps = result.laps.where((l) => !l.isFormationLap).toList();
                    if (validLaps.isEmpty) return const SizedBox.shrink();

                    final bestLap = validLaps.reduce((a, b) =>
                      a.duration < b.duration ? a : b
                    );

                    final trackLength = PostProcessingService.estimateTrackLength(result.laps);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kBrandColor.withAlpha(20), kBrandColor.withAlpha(8)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kBrandColor.withAlpha(50)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Best Lap',
                                  style: TextStyle(color: kMutedColor, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDuration(bestLap.duration),
                                  style: const TextStyle(
                                    color: kBrandColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 40, color: _kBorderColor),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lunghezza',
                                  style: TextStyle(color: kMutedColor, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${(trackLength / 1000).toStringAsFixed(2)} km',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _kBorderColor),
                        ),
                      ),
                      child: Text(
                        'Chiudi',
                        style: TextStyle(color: kMutedColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmAndReturn();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrandColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Conferma e Salva',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryTile(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: kMutedColor, fontSize: 11),
        ),
      ],
    );
  }

  /// Conferma linea S/F e ritorna al chiamante
  void _confirmAndReturn() {
    if (_finishLineStart == null || _finishLineEnd == null) return;

    Navigator.pop(context, {
      'finishLineStart': _finishLineStart,
      'finishLineEnd': _finishLineEnd,
      'processingResult': _processingResult,
    });
  }

  /// Reset selezione punti
  void _resetSelection() {
    setState(() {
      _finishLineStart = null;
      _finishLineEnd = null;
      _processingResult = null;
      _errorMessage = null;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final millis = duration.inMilliseconds % 1000;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}.${(millis ~/ 10).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = widget.gpsTrack.isNotEmpty
        ? LatLng(widget.gpsTrack.first.latitude, widget.gpsTrack.first.longitude)
        : const LatLng(45.4642, 9.1900); // Milano default

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  // Map
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 16.0,
                      backgroundColor: _kBgColor,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onTap: _onMapTap,
                    ),
                    children: [
                      // Satellite tiles
                      TileLayer(
                        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.racesense.pulse',
                      ),

                      // GPS Track polyline
                      if (_gpsPath.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _gpsPath,
                              strokeWidth: 5,
                              color: kBrandColor.withAlpha(180),
                              borderStrokeWidth: 2,
                              borderColor: Colors.black.withAlpha(150),
                            ),
                          ],
                        ),

                      // Finish Line polyline
                      if (_finishLineStart != null && _finishLineEnd != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [_finishLineStart!, _finishLineEnd!],
                              strokeWidth: 6,
                              color: const Color(0xFFFF453A),
                              borderStrokeWidth: 3,
                              borderColor: Colors.white,
                            ),
                          ],
                        ),

                      // Markers
                      MarkerLayer(
                        markers: [
                          if (_finishLineStart != null)
                            Marker(
                              point: _finishLineStart!,
                              width: 36,
                              height: 36,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [const Color(0xFF4CD964), const Color(0xFF34C759)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4CD964).withAlpha(100),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    '1',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_finishLineEnd != null)
                            Marker(
                              point: _finishLineEnd!,
                              width: 36,
                              height: 36,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [const Color(0xFFFF453A), const Color(0xFFFF3B30)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF453A).withAlpha(100),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    '2',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // Instructions card
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _buildInstructionsCard(),
                  ),

                  // Processing indicator
                  if (_isProcessing)
                    Container(
                      color: Colors.black.withAlpha(180),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_kCardStart, _kCardEnd],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: kBrandColor.withAlpha(100)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(80),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  valueColor: const AlwaysStoppedAnimation(kBrandColor),
                                  strokeWidth: 4,
                                  backgroundColor: _kBorderColor,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Processing traccia GPS...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Calcolo lap e crossing',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kMutedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Error message
                  if (_errorMessage != null)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [const Color(0xFFFF453A).withAlpha(30), const Color(0xFFFF453A).withAlpha(15)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFF453A).withAlpha(80)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF453A).withAlpha(30),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.error_outline, color: Color(0xFFFF453A), size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _errorMessage = null),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _kTileColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.close, size: 16, color: kMutedColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Stats badge
                  if (_errorMessage == null)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kCardStart, _kCardEnd],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _kBorderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(60),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gps_fixed, color: kBrandColor, size: 18),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${widget.gpsTrack.length} punti GPS',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_processingResult != null)
                                  Text(
                                    '${_processingResult!.laps.length} giri rilevati',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: kBrandColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: _kBorderColor)),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorderColor),
              ),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 16),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.trackName ?? 'Disegna Linea S/F',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Posiziona la linea Start/Finish',
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),

          // Reset button
          if (_finishLineStart != null)
            GestureDetector(
              onTap: _resetSelection,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kTileColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorderColor),
                ),
                child: const Icon(Icons.refresh, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    final step = _finishLineStart == null
        ? 0
        : _finishLineEnd == null
            ? 1
            : 2;

    final stepData = [
      {
        'icon': Icons.touch_app,
        'title': 'Punto 1',
        'subtitle': 'Tocca il primo punto della linea S/F',
        'color': const Color(0xFF4CD964),
      },
      {
        'icon': Icons.touch_app,
        'title': 'Punto 2',
        'subtitle': 'Tocca il secondo punto della linea S/F',
        'color': const Color(0xFFFF453A),
      },
      {
        'icon': Icons.check_circle,
        'title': 'Completato',
        'subtitle': 'Linea S/F posizionata correttamente',
        'color': kBrandColor,
      },
    ];

    final current = stepData[step];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (current['color'] as Color).withAlpha(100)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (current['color'] as Color).withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              current['icon'] as IconData,
              color: current['color'] as Color,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: current['color'] as Color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current['subtitle'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),
          if (widget.usedBleDevice) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.bluetooth, size: 14, color: kBrandColor),
                  SizedBox(width: 4),
                  Text(
                    'BLE',
                    style: TextStyle(fontSize: 10, color: kBrandColor, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
