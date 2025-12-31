import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/official_circuit_info.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kOfficialColor = Color(0xFF29B6F6);

/// Pagina dettaglio per i circuiti ufficiali.
/// Mostra la mappa con la linea di Start/Finish in modalità READ-ONLY.
/// In modalità selezione, permette di confermare e usare il circuito.
class OfficialCircuitDetailPage extends StatefulWidget {
  final OfficialCircuitInfo circuit;
  final bool selectionMode;

  const OfficialCircuitDetailPage({
    super.key,
    required this.circuit,
    this.selectionMode = false,
  });

  @override
  State<OfficialCircuitDetailPage> createState() =>
      _OfficialCircuitDetailPageState();
}

class _OfficialCircuitDetailPageState extends State<OfficialCircuitDetailPage> {
  final MapController _mapController = MapController();

  /// Costruisce la linea di traguardo a scacchi (bianco/nero alternato)
  List<Polyline> _buildFinishLine() {
    final a = widget.circuit.finishLineStart;
    final b = widget.circuit.finishLineEnd;

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
      dashed.add(
        Polyline(
          points: [segments[i], segments[i + 1]],
          strokeWidth: 5,
          color: i.isEven ? Colors.white : Colors.black,
        ),
      );
    }
    return dashed;
  }

  /// Costruisce i marker per Start e Finish
  List<Marker> _buildMarkers() {
    return [
      // Marker Start (verde)
      Marker(
        point: widget.circuit.finishLineStart,
        width: 50,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00E676),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withAlpha(150),
                blurRadius: 15,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.flag, color: Colors.white, size: 22),
          ),
        ),
      ),
      // Marker Finish (rosso)
      Marker(
        point: widget.circuit.finishLineEnd,
        width: 50,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5252),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5252).withAlpha(150),
                blurRadius: 15,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.sports_score, color: Colors.white, size: 22),
          ),
        ),
      ),
    ];
  }

  void _useCircuit() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(widget.circuit.toTrackDefinition());
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.circuit.finishLineCenter;
    final finishLines = _buildFinishLine();
    final markers = _buildMarkers();

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStatsBar(),
            Expanded(
              child: Stack(
                children: [
                  // Mappa
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 17.5,
                      minZoom: 14,
                      maxZoom: 20,
                      backgroundColor: _kBgColor,
                    ),
                    children: [
                      // Satellite tiles
                      TileLayer(
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'racesense_pulse',
                      ),
                      // Finish line
                      PolylineLayer(polylines: finishLines),
                      // Markers
                      MarkerLayer(markers: markers),
                    ],
                  ),
                  // Zoom controls
                  _buildZoomControls(),
                  // Info overlay
                  _buildInfoOverlay(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14),
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
          const SizedBox(width: 14),
          // Circuit info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.circuit.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: kMutedColor, size: 13),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.circuit.location,
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
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
          // Official badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kOfficialColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kOfficialColor.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: _kOfficialColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Ufficiale',
                  style: TextStyle(
                    fontSize: 11,
                    color: _kOfficialColor,
                    fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Length stat
          _buildStatItem(
            icon: Icons.straighten_rounded,
            value: widget.circuit.lengthFormatted,
            color: const Color(0xFF00E676),
          ),
          const SizedBox(width: 16),
          // Category stat
          if (widget.circuit.category != null)
            _buildStatItem(
              icon: Icons.emoji_events_rounded,
              value: widget.circuit.category!,
              color: const Color(0xFFFFB74D),
            ),
          const Spacer(),
          // Finish line info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_circle_rounded, color: _kOfficialColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'S/F Verificata',
                  style: TextStyle(
                    fontSize: 11,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: kFgColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        children: [
          _buildZoomButton(
            icon: Icons.add,
            onPressed: () {
              HapticFeedback.lightImpact();
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom + 1,
              );
            },
          ),
          const SizedBox(height: 8),
          _buildZoomButton(
            icon: Icons.remove,
            onPressed: () {
              HapticFeedback.lightImpact();
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom - 1,
              );
            },
          ),
          const SizedBox(height: 8),
          _buildZoomButton(
            icon: Icons.my_location,
            onPressed: () {
              HapticFeedback.lightImpact();
              _mapController.move(widget.circuit.finishLineCenter, 17.5);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withAlpha(230),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: kFgColor, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoOverlay() {
    return Positioned(
      left: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withAlpha(230),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E676),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Start',
              style: TextStyle(
                fontSize: 11,
                color: kMutedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF5252),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Finish',
              style: TextStyle(
                fontSize: 11,
                color: kMutedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: const Border(
          top: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: widget.selectionMode
            ? _buildSelectionButton()
            : _buildInfoButton(),
      ),
    );
  }

  Widget _buildSelectionButton() {
    return GestureDetector(
      onTap: _useCircuit,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kBrandColor, kBrandColor.withAlpha(200)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: kBrandColor.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.black, size: 22),
            const SizedBox(width: 10),
            const Text(
              'Usa questo circuito',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoButton() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, color: kMutedColor, size: 20),
          const SizedBox(width: 10),
          Text(
            'Circuito ufficiale - Solo visualizzazione',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kMutedColor,
            ),
          ),
        ],
      ),
    );
  }
}
