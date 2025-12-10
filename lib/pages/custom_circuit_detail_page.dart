import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../services/custom_circuit_service.dart';
import '../theme.dart';

class CustomCircuitDetailPage extends StatelessWidget {
  final CustomCircuitInfo circuit;

  const CustomCircuitDetailPage({super.key, required this.circuit});

  List<LatLng> _closedPath() {
    if (circuit.points.length < 2) return circuit.points;
    final dist = const Distance();
    final first = circuit.points.first;
    final last = circuit.points.last;
    final meters = dist(first, last);
    if (meters < 20) {
      // se il giro non è chiuso, aggancia start/finish
      final pts = List<LatLng>.from(circuit.points);
      if (meters > 2) {
        pts.add(first);
      }
      return pts;
    }
    return circuit.points;
  }

  // Crea i bordi sinistro e destro del circuito con direzione smoothed
  List<LatLng> _createBorder(List<LatLng> path, double offsetMeters, {bool isLeft = true}) {
    if (path.length < 2) return [];

    const latMetersPerDegree = 111111.0;
    final List<LatLng> border = [];

    for (int i = 0; i < path.length; i++) {
      final p = path[i];

      // Calcola la direzione del tracciato in questo punto usando media delle direzioni
      double dx, dy;

      if (i == 0) {
        // Primo punto: usa direzione verso il prossimo
        dx = path[1].longitude - p.longitude;
        dy = path[1].latitude - p.latitude;
      } else if (i == path.length - 1) {
        // Ultimo punto: usa direzione dal precedente
        dx = p.longitude - path[i - 1].longitude;
        dy = p.latitude - path[i - 1].latitude;
      } else {
        // Punto intermedio: usa la direzione media (smoothing)
        final dxIn = p.longitude - path[i - 1].longitude;
        final dyIn = p.latitude - path[i - 1].latitude;
        final dxOut = path[i + 1].longitude - p.longitude;
        final dyOut = path[i + 1].latitude - p.latitude;

        // Media delle due direzioni
        dx = (dxIn + dxOut) / 2;
        dy = (dyIn + dyOut) / 2;
      }

      if (dx == 0 && dy == 0) {
        border.add(p);
        continue;
      }

      // Vettore perpendicolare (ruotato 90°)
      final perpX = -dy;
      final perpY = dx;

      // Normalizza
      final length = math.sqrt(perpX * perpX + perpY * perpY);
      if (length == 0) {
        border.add(p);
        continue;
      }

      final normX = perpX / length;
      final normY = perpY / length;

      // Applica offset
      final lonMetersPerDegree = latMetersPerDegree * math.cos(p.latitude * math.pi / 180);
      final sign = isLeft ? 1.0 : -1.0;

      border.add(LatLng(
        p.latitude + sign * normY * (offsetMeters / latMetersPerDegree),
        p.longitude + sign * normX * (offsetMeters / lonMetersPerDegree),
      ));
    }

    return border;
  }

  List<Polyline> _startFinishLines(List<LatLng> path) {
    if (path.length < 2) {
      return const [];
    }
    final p0 = path.first;
    final p1 = path[1];
    final widthMeters = circuit.widthMeters;
    final dx = p1.longitude - p0.longitude;
    final dy = p1.latitude - p0.latitude;
    if (dx == 0 && dy == 0) {
      return const [];
    }
    // vettore perpendicolare per disegnare la linea di arrivo
    final nx = -dy;
    final ny = dx;
    // approssimazione metri->gradi (piccolo segmento)
    final latScale = 1 / 111111.0;
    final lonScale = 1 / (111111.0 * math.cos(p0.latitude * math.pi / 180));
    final half = widthMeters / 2;
    final a = LatLng(
      p0.latitude + ny * latScale * half,
      p0.longitude + nx * lonScale * half,
    );
    final b = LatLng(
      p0.latitude - ny * latScale * half,
      p0.longitude - nx * lonScale * half,
    );
    // linea a scacchi: spezza in segmenti alternati
    final segments = <LatLng>[];
    const dashCount = 12;
    for (int i = 0; i <= dashCount; i++) {
      final t = i / dashCount;
      segments.add(LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ));
    }
    // polyline layer non supporta isDotted: disegniamo segmenti alternati manualmente
    final dashed = <Polyline>[];
    for (int i = 0; i < segments.length - 1; i++) {
      if (i.isEven) {
        dashed.add(
          Polyline(
            points: [segments[i], segments[i + 1]],
            strokeWidth: 4,
            color: Colors.white,
          ),
        );
      } else {
        dashed.add(
          Polyline(
            points: [segments[i], segments[i + 1]],
            strokeWidth: 4,
            color: Colors.black,
          ),
        );
      }
    }
    return dashed;
  }

  // Crea microsettori usando esattamente i punti dei bordi
  List<MicroSector> _buildMicroSectorsFromBorders(List<LatLng> leftBorder, List<LatLng> rightBorder) {
    final sectors = <MicroSector>[];
    final minLength = leftBorder.length < rightBorder.length ? leftBorder.length : rightBorder.length;

    for (int i = 0; i < minLength; i++) {
      sectors.add(MicroSector(
        start: leftBorder[i],
        end: rightBorder[i],
      ));
    }

    return sectors;
  }

  @override
  Widget build(BuildContext context) {
    final path = _closedPath();
    final center = path.isNotEmpty
        ? path.first
        : const LatLng(45.0, 9.0);

    final halfWidth = circuit.widthMeters / 2;
    final leftBorder = _createBorder(path, halfWidth, isLeft: true);
    final rightBorder = _createBorder(path, halfWidth, isLeft: false);
    final startFinish = _startFinishLines(path);

    // Crea microsettori che vanno esattamente da bordo a bordo
    final microSectors = _buildMicroSectorsFromBorders(leftBorder, rightBorder);

    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header con info circuito
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0A0A0A),
                    kBgColor,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  bottom: BorderSide(color: kLineColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: kFgColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          circuit.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: kFgColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 12, color: kMutedColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${circuit.city} ${circuit.country}'.trim(),
                                style: const TextStyle(
                                  color: kMutedColor,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              kBrandColor.withAlpha(30),
                              kBrandColor.withAlpha(20),
                            ],
                          ),
                          border: Border.all(color: kBrandColor, width: 1.5),
                        ),
                        child: Text(
                          '${circuit.lengthMeters.toStringAsFixed(0)} m',
                          style: const TextStyle(
                            color: kBrandColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Larghezza: ${circuit.widthMeters.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          color: kMutedColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Mappa con circuito
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 17.5,
                  minZoom: 15,
                  maxZoom: 20,
                  backgroundColor: const Color(0xFF0A0A0A),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'racesense_pulse',
                  ),
                  if (path.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        // Bordo sinistro (premium style)
                        if (leftBorder.isNotEmpty)
                          Polyline(
                            points: leftBorder,
                            strokeWidth: 3,
                            color: const Color(0xFFFF4D4F),
                            borderStrokeWidth: 1,
                            borderColor: Colors.white.withAlpha(100),
                          ),
                        // Bordo destro (premium style)
                        if (rightBorder.isNotEmpty)
                          Polyline(
                            points: rightBorder,
                            strokeWidth: 3,
                            color: const Color(0xFFFF4D4F),
                            borderStrokeWidth: 1,
                            borderColor: Colors.white.withAlpha(100),
                          ),
                        // Linea centrale tracciata (percorso originale)
                        Polyline(
                          points: path,
                          strokeWidth: 2,
                          color: kBrandColor,
                          borderStrokeWidth: 1,
                          borderColor: Colors.black.withAlpha(150),
                        ),
                        // Linea start/finish a scacchi
                        ...startFinish,
                        // Microsettori perpendicolari (ogni metro, da bordo a bordo)
                        ...microSectors.map(
                          (s) => Polyline(
                            points: [s.start, s.end],
                            strokeWidth: 2,
                            color: const Color(0xFF8E85FF).withAlpha(200),
                          ),
                        ),
                      ],
                    ),
                  if (path.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        // Marker start
                        Marker(
                          point: path.first,
                          width: 20,
                          height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kBrandColor,
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: kBrandColor.withAlpha(128),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.flag,
                              color: Colors.black,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Legenda
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kBgColor,
                    const Color(0xFF0A0A0A),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  top: BorderSide(color: kLineColor, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegendItem(
                    color: kBrandColor,
                    label: 'Tracciato',
                    icon: Icons.timeline,
                  ),
                  _buildLegendItem(
                    color: const Color(0xFFFF4D4F),
                    label: 'Bordi pista',
                    icon: Icons.border_outer,
                  ),
                  _buildLegendItem(
                    color: const Color(0xFF8E85FF),
                    label: 'Microsettori',
                    icon: Icons.grid_on,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label, required IconData icon}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(128), width: 1),
          ),
          child: Icon(icon, color: color, size: 14),
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
