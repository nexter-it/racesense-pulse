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

  /// Mostra dialog con risultati post-processing
  void _showResultsDialog(PostProcessingResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F15),
        title: const Text(
          'Post-Processing Completato',
          style: TextStyle(color: kFgColor),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✓ ${result.crossings.length} crossing rilevati',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kFgColor,
                ),
              ),
              Text(
                '✓ ${result.laps.length} giri completi',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kFgColor,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Giri rilevati:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: kFgColor,
                ),
              ),
              const SizedBox(height: 8),
              ...result.laps.map((lap) {
                final lapNumber = lap.isFormationLap ? 'OUT' : '#${lap.lapNumber}';
                final duration = _formatDuration(lap.duration);
                final distance = (lap.distanceMeters / 1000).toStringAsFixed(2);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        lapNumber,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: lap.isFormationLap ? Colors.orange : kBrandColor,
                        ),
                      ),
                      Text(duration, style: const TextStyle(color: kFgColor)),
                      Text('${distance}km', style: const TextStyle(color: kMutedColor)),
                    ],
                  ),
                );
              }).toList(),
              if (result.laps.length > 1) ...[
                const Divider(height: 24, color: kLineColor),
                Builder(
                  builder: (context) {
                    final validLaps = result.laps.where((l) => !l.isFormationLap).toList();
                    if (validLaps.isEmpty) return const SizedBox.shrink();

                    final bestLap = validLaps.reduce((a, b) =>
                      a.duration < b.duration ? a : b
                    );

                    final trackLength = PostProcessingService.estimateTrackLength(result.laps);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Best Lap: ${_formatDuration(bestLap.duration)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kBrandColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lunghezza circuito: ${(trackLength / 1000).toStringAsFixed(2)}km',
                          style: const TextStyle(fontSize: 12, color: kMutedColor),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CHIUDI', style: TextStyle(color: kMutedColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandColor,
              foregroundColor: kBgColor,
            ),
            onPressed: () {
              Navigator.pop(context); // Chiudi dialog
              _confirmAndReturn();
            },
            child: const Text('CONFERMA E SALVA'),
          ),
        ],
      ),
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
      backgroundColor: kBgColor,
      appBar: AppBar(
        title: Text(widget.trackName ?? 'Disegna Linea Start/Finish'),
        backgroundColor: kBgColor,
        actions: [
          if (_finishLineStart != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetSelection,
              tooltip: 'Reset',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Mappa con FlutterMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 16.0,
              backgroundColor: const Color(0xFF0A0A0A),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _onMapTap,
            ),
            children: [
              // Tile layer - Satellite imagery
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
                      color: kBrandColor.withOpacity(0.7),
                      borderStrokeWidth: 2,
                      borderColor: Colors.black.withAlpha(100),
                    ),
                  ],
                ),

              // Finish Line polyline (se entrambi i punti sono selezionati)
              if (_finishLineStart != null && _finishLineEnd != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_finishLineStart!, _finishLineEnd!],
                      strokeWidth: 6,
                      color: kErrorColor,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                  ],
                ),

              // Markers per i punti S/F
              MarkerLayer(
                markers: [
                  // Marker punto 1
                  if (_finishLineStart != null)
                    Marker(
                      point: _finishLineStart!,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Marker punto 2
                  if (_finishLineEnd != null)
                    Marker(
                      point: _finishLineEnd!,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: kErrorColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Center(
                          child: Text(
                            '2',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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

          // Istruzioni
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF1A1A20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _finishLineStart == null
                              ? Icons.looks_one
                              : _finishLineEnd == null
                                  ? Icons.looks_two
                                  : Icons.check_circle,
                          color: _finishLineEnd != null ? kBrandColor : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _finishLineStart == null
                                ? 'Tap sul primo punto della linea S/F'
                                : _finishLineEnd == null
                                    ? 'Tap sul secondo punto della linea S/F'
                                    : 'Linea S/F definita',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: kFgColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.usedBleDevice) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kBrandColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: kBrandColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.bluetooth, size: 14, color: kBrandColor),
                            SizedBox(width: 4),
                            Text(
                              'GPS BLE 15-20Hz',
                              style: TextStyle(fontSize: 11, color: kBrandColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Processing indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBrandColor),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(kBrandColor),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Processing traccia GPS...\nCalcolo lap e crossing',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kFgColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Messaggio errore
          if (_errorMessage != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: kErrorColor.withOpacity(0.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Colors.white),
                        onPressed: () => setState(() => _errorMessage = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Statistiche traccia
          if (_errorMessage == null)
            Positioned(
              bottom: 16,
              left: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF1A1A20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.gpsTrack.length} punti GPS',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: kFgColor,
                        ),
                      ),
                      if (_processingResult != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_processingResult!.laps.length} giri',
                          style: const TextStyle(
                            fontSize: 11,
                            color: kBrandColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
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
