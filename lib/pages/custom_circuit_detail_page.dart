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

  List<Polyline> _startFinishLines(List<LatLng> path, double stroke) {
    if (path.length < 2) {
      return const [];
    }
    final p0 = path.first;
    final p1 = path[1];
    const double widthMeters = 8;
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
    const dashCount = 10;
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
            strokeWidth: stroke,
            color: Colors.white,
          ),
        );
      }
    }
    return dashed;
  }

  @override
  Widget build(BuildContext context) {
    final path = _closedPath();
    final center = path.isNotEmpty
        ? path.first
        : const LatLng(45.0, 9.0);
    final stroke = (circuit.widthMeters / 1.5).clamp(6, 18).toDouble();
    final startFinish = _startFinishLines(path, stroke);
    final boundaryOffset = (circuit.widthMeters / 2) / 111111.0; // circa °lat

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
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
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${circuit.city} ${circuit.country}'.trim(),
                          style: const TextStyle(
                            color: kMutedColor,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: kBrandColor.withOpacity(0.12),
                      border: Border.all(color: kBrandColor.withOpacity(0.7)),
                    ),
                    child: Text(
                      '${circuit.lengthMeters.toStringAsFixed(0)} m',
                      style: const TextStyle(
                        color: kBrandColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 18,
                  backgroundColor: const Color(0xFF050505),
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
                        // bordo superiore
                        Polyline(
                          points: path
                              .map((p) =>
                                  LatLng(p.latitude + boundaryOffset, p.longitude))
                              .toList(),
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.35),
                        ),
                        // bordo inferiore
                        Polyline(
                          points: path
                              .map((p) =>
                                  LatLng(p.latitude - boundaryOffset, p.longitude))
                              .toList(),
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.35),
                        ),
                        // corpo pista
                        Polyline(
                          points: path,
                          strokeWidth: stroke,
                          color: kBrandColor.withOpacity(0.55),
                        ),
                        ...startFinish,
                      ],
                    ),
                  if (path.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: path.first,
                          width: 12,
                          height: 12,
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Marker(
                          point: path.last,
                          width: 12,
                          height: 12,
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
