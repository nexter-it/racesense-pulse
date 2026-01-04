import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/custom_circuit_service.dart';
import '../theme.dart';

class CustomCircuitDetailPage extends StatefulWidget {
  final CustomCircuitInfo circuit;
  final String? trackId;
  final Function(CustomCircuitInfo)? onCircuitUpdated;

  const CustomCircuitDetailPage({
    super.key,
    required this.circuit,
    this.trackId,
    this.onCircuitUpdated,
  });

  @override
  State<CustomCircuitDetailPage> createState() => _CustomCircuitDetailPageState();
}

class _CustomCircuitDetailPageState extends State<CustomCircuitDetailPage>
    with SingleTickerProviderStateMixin {
  late LatLng? _finishLineStart;
  late LatLng? _finishLineEnd;
  bool _isEditingFinishLine = false;
  bool _isDragging = false;
  bool? _draggingStart; // true = start marker, false = end marker, null = nessuno
  bool? _selectedMarker; // Marker attualmente selezionato (tap per selezionare)
  bool _isSaving = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final MapController _mapController = MapController();

  // Chiave per ottenere la posizione della mappa
  final GlobalKey _mapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _finishLineStart = widget.circuit.finishLineStart;
    _finishLineEnd = widget.circuit.finishLineEnd;

    // Se non ha finish line, calcola dalla traccia
    if (_finishLineStart == null || _finishLineEnd == null) {
      _calculateDefaultFinishLine();
    }

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _calculateDefaultFinishLine() {
    final path = widget.circuit.points;
    if (path.length < 2) return;

    final p0 = path.first;
    final p1 = path[1];

    // Calcola direzione perpendicolare
    final dx = p1.longitude - p0.longitude;
    final dy = p1.latitude - p0.latitude;

    if (dx == 0 && dy == 0) return;

    final nx = -dy;
    final ny = dx;

    const latScale = 1 / 111111.0;
    final lonScale = 1 / (111111.0 * math.cos(p0.latitude * math.pi / 180));
    const halfWidth = 6.0; // 6 metri per lato

    _finishLineStart = LatLng(
      p0.latitude + ny * latScale * halfWidth,
      p0.longitude + nx * lonScale * halfWidth,
    );
    _finishLineEnd = LatLng(
      p0.latitude - ny * latScale * halfWidth,
      p0.longitude - nx * lonScale * halfWidth,
    );
  }

  List<LatLng> _closedPath() {
    if (widget.circuit.points.length < 2) return widget.circuit.points;
    final dist = const Distance();
    final first = widget.circuit.points.first;
    final last = widget.circuit.points.last;
    final meters = dist(first, last);
    if (meters < 20) {
      final pts = List<LatLng>.from(widget.circuit.points);
      if (meters > 2) {
        pts.add(first);
      }
      return pts;
    }
    return widget.circuit.points;
  }

  List<Polyline> _buildFinishLine() {
    if (_finishLineStart == null || _finishLineEnd == null) {
      return const [];
    }

    final a = _finishLineStart!;
    final b = _finishLineEnd!;

    // Linea a scacchi: spezza in segmenti alternati
    final segments = <LatLng>[];
    const dashCount = 12;
    for (int i = 0; i <= dashCount; i++) {
      final t = i / dashCount;
      segments.add(LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ));
    }

    final dashed = <Polyline>[];
    for (int i = 0; i < segments.length - 1; i++) {
      if (i.isEven) {
        dashed.add(
          Polyline(
            points: [segments[i], segments[i + 1]],
            strokeWidth: 5,
            color: Colors.white,
          ),
        );
      } else {
        dashed.add(
          Polyline(
            points: [segments[i], segments[i + 1]],
            strokeWidth: 5,
            color: Colors.black,
          ),
        );
      }
    }
    return dashed;
  }

  void _toggleEditMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isEditingFinishLine = !_isEditingFinishLine;
      // Reset selezione quando si esce dalla modalità modifica
      if (!_isEditingFinishLine) {
        _selectedMarker = null;
        _isDragging = false;
        _draggingStart = null;
      }
    });
  }

  Future<void> _saveFinishLine() async {
    if (_finishLineStart == null || _finishLineEnd == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedCircuit = CustomCircuitInfo(
        trackId: widget.trackId,
        name: widget.circuit.name,
        city: widget.circuit.city,
        country: widget.circuit.country,
        lengthMeters: widget.circuit.lengthMeters,
        createdAt: widget.circuit.createdAt,
        points: widget.circuit.points,
        usedBleDevice: widget.circuit.usedBleDevice,
        finishLineStart: _finishLineStart,
        finishLineEnd: _finishLineEnd,
        gpsFrequencyHz: widget.circuit.gpsFrequencyHz,
      );

      if (widget.trackId != null) {
        final service = CustomCircuitService();
        await service.updateCircuit(
          trackId: widget.trackId!,
          circuit: updatedCircuit,
        );
      }

      widget.onCircuitUpdated?.call(updatedCircuit);

      setState(() {
        _isEditingFinishLine = false;
        _isSaving = false;
      });

      HapticFeedback.heavyImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Linea del traguardo salvata',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF00C853),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Errore: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  /// Calcola la distanza in pixel tra un punto sullo schermo e un marker
  double _distanceToMarker(Offset screenPoint, LatLng markerPosition) {
    final markerScreenPoint = _mapController.camera.latLngToScreenPoint(markerPosition);
    final dx = screenPoint.dx - markerScreenPoint.x;
    final dy = screenPoint.dy - markerScreenPoint.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Trova quale marker è più vicino al tocco (entro una soglia)
  bool? _findClosestMarker(Offset localPosition) {
    if (_finishLineStart == null || _finishLineEnd == null) return null;

    const double touchThreshold = 80.0; // Raggio di tocco aumentato

    final distToStart = _distanceToMarker(localPosition, _finishLineStart!);
    final distToEnd = _distanceToMarker(localPosition, _finishLineEnd!);

    // Se entrambi sono fuori soglia, nessun marker selezionato
    if (distToStart > touchThreshold && distToEnd > touchThreshold) {
      return null;
    }

    // Ritorna il marker più vicino
    return distToStart <= distToEnd;
  }

  /// Seleziona un marker con un tap
  void _onMarkerTap(bool isStart) {
    HapticFeedback.mediumImpact();
    setState(() {
      // Se clicco sullo stesso marker già selezionato, deseleziono
      if (_selectedMarker == isStart) {
        _selectedMarker = null;
      } else {
        _selectedMarker = isStart;
      }
    });
  }

  /// Deseleziona il marker corrente
  void _deselectMarker() {
    if (_selectedMarker != null) {
      setState(() {
        _selectedMarker = null;
      });
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (!_isEditingFinishLine) return;

    // Se c'è un marker selezionato, spostalo nella nuova posizione
    if (_selectedMarker != null) {
      HapticFeedback.heavyImpact();
      setState(() {
        if (_selectedMarker!) {
          _finishLineStart = point;
        } else {
          _finishLineEnd = point;
        }
        // Mantieni la selezione per ulteriori spostamenti
      });
      return;
    }

    // Altrimenti controlla se ho tappato su un marker per selezionarlo
    final screenPoint = tapPosition.relative;
    if (screenPoint != null) {
      final closestMarker = _findClosestMarker(screenPoint);
      if (closestMarker != null) {
        _onMarkerTap(closestMarker);
      }
    }
  }

  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    if (!_isEditingFinishLine) return;

    // Long press su un punto: se c'è un marker selezionato, spostalo
    if (_selectedMarker != null) {
      HapticFeedback.heavyImpact();
      setState(() {
        if (_selectedMarker!) {
          _finishLineStart = point;
        } else {
          _finishLineEnd = point;
        }
      });
    }
  }

  void _onMapPanStart(DragStartDetails details) {
    if (!_isEditingFinishLine) return;

    // Se c'è un marker selezionato, inizia il drag da lì
    if (_selectedMarker != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isDragging = true;
        _draggingStart = _selectedMarker;
      });
      return;
    }

    // Altrimenti prova a trovare un marker vicino
    final closestMarker = _findClosestMarker(details.localPosition);
    if (closestMarker != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _isDragging = true;
        _draggingStart = closestMarker;
        _selectedMarker = closestMarker;
      });
    }
  }

  void _onMapPanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _draggingStart == null) return;

    // Converti la posizione dello schermo in coordinate geografiche
    final point = _mapController.camera.pointToLatLng(
      math.Point(details.localPosition.dx, details.localPosition.dy),
    );

    setState(() {
      if (_draggingStart!) {
        _finishLineStart = point;
      } else {
        _finishLineEnd = point;
      }
    });
  }

  void _onMapPanEnd(DragEndDetails details) {
    if (_isDragging) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _isDragging = false;
      _draggingStart = null;
      // Mantieni la selezione del marker dopo il drag
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = _closedPath();
    // Usa la posizione della linea S/F come centro se non ci sono punti GPS
    final center = path.isNotEmpty
        ? path.first
        : (_finishLineStart ?? _finishLineEnd ?? const LatLng(45.0, 9.0));

    final finishLines = _buildFinishLine();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Header Premium
            _buildHeader(context),
            // Stats Bar
            _buildStatsBar(),
            // Mappa con circuito
            Expanded(
              child: Stack(
                children: [
                  // Mappa
                  GestureDetector(
                    key: _mapKey,
                    onPanStart: _isEditingFinishLine ? _onMapPanStart : null,
                    onPanUpdate: _isEditingFinishLine ? _onMapPanUpdate : null,
                    onPanEnd: _isEditingFinishLine ? _onMapPanEnd : null,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 17.5,
                        minZoom: 14,
                        maxZoom: 20,
                        backgroundColor: const Color(0xFF0A0A0A),
                        onTap: _isEditingFinishLine ? _onMapTap : null,
                        onLongPress: _isEditingFinishLine ? _onMapLongPress : null,
                        interactionOptions: InteractionOptions(
                          // Disabilita pan/drag quando si sta trascinando un marker o c'è una selezione
                          flags: (_isDragging || _selectedMarker != null)
                              ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
                              : InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                          userAgentPackageName: 'racesense_pulse',
                        ),
                        // Mostra tracciato solo se ci sono punti GPS
                        if (path.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              // Tracciato principale con glow effect
                              Polyline(
                                points: path,
                                strokeWidth: 8,
                                color: kBrandColor.withAlpha(60),
                              ),
                              Polyline(
                                points: path,
                                strokeWidth: 4,
                                color: kBrandColor,
                                borderStrokeWidth: 1,
                                borderColor: Colors.black.withAlpha(150),
                              ),
                            ],
                          ),
                        // Linea start/finish sempre visibile
                        if (finishLines.isNotEmpty)
                          PolylineLayer(
                            polylines: finishLines,
                          ),
                        // Marker per editing (non draggabili - gestiti dal GestureDetector padre)
                        if (_isEditingFinishLine && _finishLineStart != null && _finishLineEnd != null)
                          MarkerLayer(
                            markers: [
                              _buildEditMarker(_finishLineStart!, true),
                              _buildEditMarker(_finishLineEnd!, false),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Edit mode overlay
                  if (_isEditingFinishLine)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _buildEditModeOverlay(),
                    ),
                  // Zoom controls
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: _buildZoomControls(),
                  ),
                ],
              ),
            ),
            // Bottom bar con azioni
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A0A0A),
            const Color(0xFF121212),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: kFgColor, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.circuit.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 12, color: kMutedColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${widget.circuit.city} ${widget.circuit.country}'.trim(),
                        style: const TextStyle(
                          color: kMutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Premium badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(30),
                  kBrandColor.withAlpha(15),
                ],
              ),
              border: Border.all(color: kBrandColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: kBrandColor.withAlpha(30),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.route, color: kBrandColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${widget.circuit.lengthMeters.toStringAsFixed(0)} m',
                  style: const TextStyle(
                    color: kBrandColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    // Calcola lunghezza della linea S/F
    double finishLineLength = 0;
    if (_finishLineStart != null && _finishLineEnd != null) {
      final dist = const Distance();
      finishLineLength = dist(_finishLineStart!, _finishLineEnd!);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: kBrandColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Linea Start/Finish Configurata',
                  style: TextStyle(
                    color: kBrandColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFinishLineInfo(
                    icon: Icons.straighten,
                    label: 'Lunghezza',
                    value: '${finishLineLength.toStringAsFixed(1)} m',
                    color: const Color(0xFF00E676),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFinishLineInfo(
                    icon: Icons.check_circle,
                    label: 'Stato',
                    value: 'Pronto',
                    color: const Color(0xFF4CD964),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: kMutedColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La traccia GPS verrà registrata durante le sessioni',
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

  Widget _buildFinishLineInfo({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: kFgColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditModeOverlay() {
    final hasSelection = _selectedMarker != null;
    final selectedName = _selectedMarker == true ? 'INIZIO' : (_selectedMarker == false ? 'FINE' : '');

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(240),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasSelection
                  ? const Color(0xFFFFD600).withAlpha((200 * _pulseAnimation.value).toInt())
                  : kBrandColor.withAlpha((200 * _pulseAnimation.value).toInt()),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: hasSelection
                    ? const Color(0xFFFFD600).withAlpha((60 * _pulseAnimation.value).toInt())
                    : kBrandColor.withAlpha((60 * _pulseAnimation.value).toInt()),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSelection) ...[
                // Mostra istruzioni per spostamento
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD600).withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.touch_app, color: Color(0xFFFFD600), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Punto $selectedName selezionato',
                            style: const TextStyle(
                              color: Color(0xFFFFD600),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tocca la mappa per spostarlo nella nuova posizione',
                            style: TextStyle(
                              color: kMutedColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottone deseleziona
                    GestureDetector(
                      onTap: _deselectMarker,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: const Icon(Icons.close, color: kMutedColor, size: 20),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Istruzioni iniziali
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kBrandColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.ads_click, color: kBrandColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Modalità Modifica',
                            style: TextStyle(
                              color: kFgColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tocca un cerchio per selezionarlo, poi tocca la mappa per spostarlo',
                            style: TextStyle(
                              color: kMutedColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Legenda marker
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMarkerLegend(
                      color: const Color(0xFF00E676),
                      label: 'Inizio linea',
                      icon: Icons.flag,
                    ),
                    const SizedBox(width: 24),
                    _buildMarkerLegend(
                      color: const Color(0xFFFF5252),
                      label: 'Fine linea',
                      icon: Icons.sports_score,
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMarkerLegend({
    required Color color,
    required String label,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, color: Colors.white, size: 12),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: kMutedColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Marker visuale per l'editing
  /// - Non selezionato: grigio/normale
  /// - Selezionato: bordo giallo pulsante, pronto per essere spostato
  /// - Dragging: più grande con glow intenso
  Marker _buildEditMarker(LatLng position, bool isStart) {
    final isSelected = _selectedMarker == isStart;
    final isDragging = _isDragging && _draggingStart == isStart;
    final color = isStart ? const Color(0xFF00E676) : const Color(0xFFFF5252);

    const double markerSize = 60; // Più grande per tocco più facile
    final double currentSize = isDragging ? markerSize + 16 : (isSelected ? markerSize + 8 : markerSize);

    return Marker(
      point: position,
      width: currentSize + 20, // Area extra per tocco
      height: currentSize + 20,
      child: GestureDetector(
        onTap: () => _onMarkerTap(isStart),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: currentSize,
            height: currentSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDragging ? color : (isSelected ? color : color.withAlpha(200)),
              border: Border.all(
                color: isSelected ? const Color(0xFFFFD600) : Colors.white, // Giallo quando selezionato
                width: isSelected ? 6 : 4,
              ),
              boxShadow: [
                // Glow principale
                BoxShadow(
                  color: color.withAlpha(isDragging ? 220 : (isSelected ? 180 : 120)),
                  blurRadius: isDragging ? 35 : (isSelected ? 25 : 15),
                  spreadRadius: isDragging ? 10 : (isSelected ? 6 : 2),
                ),
                // Glow giallo quando selezionato
                if (isSelected)
                  BoxShadow(
                    color: const Color(0xFFFFD600).withAlpha(100),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isStart ? Icons.flag : Icons.sports_score,
                    color: Colors.white,
                    size: isDragging ? 28 : (isSelected ? 26 : 24),
                  ),
                  if (isSelected && !isDragging) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(150),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'TAP',
                        style: TextStyle(
                          color: Color(0xFFFFD600),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, color: kFgColor),
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                currentZoom + 0.5,
              );
            },
          ),
          Container(
            height: 1,
            width: 24,
            color: const Color(0xFF2A2A2A),
          ),
          IconButton(
            icon: const Icon(Icons.remove, color: kFgColor),
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                currentZoom - 0.5,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF121212),
            const Color(0xFF0A0A0A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          top: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Legenda
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendChip(
                  color: kBrandColor,
                  label: 'Tracciato',
                ),
                const SizedBox(width: 24),
                _buildLegendChip(
                  color: Colors.white,
                  label: 'Traguardo',
                  isCheckered: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Bottone a tutta larghezza
            if (_isEditingFinishLine)
              Row(
                children: [
                  // Cancel button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: kFgColor),
                      onPressed: () {
                        setState(() {
                          _finishLineStart = widget.circuit.finishLineStart;
                          _finishLineEnd = widget.circuit.finishLineEnd;
                          if (_finishLineStart == null || _finishLineEnd == null) {
                            _calculateDefaultFinishLine();
                          }
                          _isEditingFinishLine = false;
                          _selectedMarker = null;
                          _isDragging = false;
                          _draggingStart = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Save button a tutta larghezza
                  Expanded(
                    child: GestureDetector(
                      onTap: _isSaving ? null : _saveFinishLine,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF00E676),
                              const Color(0xFF00C853),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E676).withAlpha(60),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _isSaving
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Salva Traguardo',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _toggleEditMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kBrandColor,
                          kBrandColor.withAlpha(200),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: kBrandColor.withAlpha(60),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_location_alt, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Modifica Traguardo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendChip({
    required Color color,
    required String label,
    bool isCheckered = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isCheckered ? null : color,
            gradient: isCheckered
                ? LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.black,
                      Colors.white,
                      Colors.black,
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75],
                  )
                : null,
            border: Border.all(color: Colors.white.withAlpha(50)),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(80),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: kMutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
