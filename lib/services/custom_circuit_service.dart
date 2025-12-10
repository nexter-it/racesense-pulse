import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

class CustomCircuitInfo {
  final String name;
  final double widthMeters;
  final String city;
  final String country;
  final double lengthMeters;
  final DateTime createdAt;
  final List<LatLng> points;
  final List<MicroSector> microSectors;

  CustomCircuitInfo({
    required this.name,
    required this.widthMeters,
    required this.city,
    required this.country,
    required this.lengthMeters,
    required this.createdAt,
    required this.points,
    required this.microSectors,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'widthMeters': widthMeters,
      'city': city,
      'country': country,
      'lengthMeters': lengthMeters,
      'createdAt': createdAt.toIso8601String(),
      'points': points
          .map((p) => {
                'lat': p.latitude,
                'lon': p.longitude,
              })
          .toList(),
      'microSectors': microSectors.map((s) => s.toJson()).toList(),
    };
  }

  factory CustomCircuitInfo.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List<dynamic>? ?? [])
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lon'] as num).toDouble(),
            ))
        .toList();
    return CustomCircuitInfo(
      name: json['name'] as String? ?? 'Circuito',
      widthMeters: (json['widthMeters'] as num?)?.toDouble() ?? 8.0,
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      lengthMeters: (json['lengthMeters'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      points: pts,
      microSectors: (json['microSectors'] as List<dynamic>?)
              ?.map((s) => MicroSector.fromJson(s as Map<String, dynamic>))
              .toList() ??
          buildSectorsFromPoints(pts),
    );
  }

  static List<MicroSector> buildSectorsFromPoints(List<LatLng> pts, {double widthMeters = 8.0}) {
    final List<MicroSector> sectors = [];
    if (pts.length < 2) return sectors;

    // Costanti per conversione metri -> gradi
    const latMetersPerDegree = 111111.0;

    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];

      // Calcola la direzione del tracciato in questo punto usando media delle direzioni (smoothing)
      double dx, dy;

      if (i == 0) {
        // Primo punto: usa direzione verso il prossimo
        dx = pts[1].longitude - p.longitude;
        dy = pts[1].latitude - p.latitude;
      } else if (i == pts.length - 1) {
        // Ultimo punto: usa direzione dal precedente
        dx = p.longitude - pts[i - 1].longitude;
        dy = p.latitude - pts[i - 1].latitude;
      } else {
        // Punto intermedio: usa la direzione media per smoothing
        final dxIn = p.longitude - pts[i - 1].longitude;
        final dyIn = p.latitude - pts[i - 1].latitude;
        final dxOut = pts[i + 1].longitude - p.longitude;
        final dyOut = pts[i + 1].latitude - p.latitude;

        // Media delle due direzioni
        dx = (dxIn + dxOut) / 2;
        dy = (dyIn + dyOut) / 2;
      }

      if (dx == 0 && dy == 0) continue;

      // Vettore perpendicolare (ruotato di 90°)
      final perpX = -dy;
      final perpY = dx;

      // Normalizza il vettore perpendicolare
      final length = math.sqrt(perpX * perpX + perpY * perpY);
      if (length == 0) continue;

      final normX = perpX / length;
      final normY = perpY / length;

      // Scala per la larghezza del circuito (metà larghezza per lato)
      final lonMetersPerDegree = latMetersPerDegree * math.cos(p.latitude * math.pi / 180);
      final halfWidth = widthMeters / 2;

      // Punti perpendicolari ai lati del circuito (da bordo a bordo)
      final start = LatLng(
        p.latitude + normY * (halfWidth / latMetersPerDegree),
        p.longitude + normX * (halfWidth / lonMetersPerDegree),
      );

      final end = LatLng(
        p.latitude - normY * (halfWidth / latMetersPerDegree),
        p.longitude - normX * (halfWidth / lonMetersPerDegree),
      );

      sectors.add(MicroSector(start: start, end: end));
    }

    return sectors;
  }
}

class MicroSector {
  final LatLng start;
  final LatLng end;

  MicroSector({required this.start, required this.end});

  Map<String, dynamic> toJson() {
    return {
      'startLat': start.latitude,
      'startLon': start.longitude,
      'endLat': end.latitude,
      'endLon': end.longitude,
    };
  }

  factory MicroSector.fromJson(Map<String, dynamic> json) {
    return MicroSector(
      start: LatLng(
        (json['startLat'] as num).toDouble(),
        (json['startLon'] as num).toDouble(),
      ),
      end: LatLng(
        (json['endLat'] as num).toDouble(),
        (json['endLon'] as num).toDouble(),
      ),
    );
  }
}

class CustomCircuitService {
  static const _folderName = 'custom_circuits';

  Future<Directory> _getDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<CustomCircuitInfo>> listCircuits() async {
    try {
      final dir = await _getDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      final List<CustomCircuitInfo> circuits = [];
      for (final file in files) {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        circuits.add(CustomCircuitInfo.fromJson(data));
      }
      circuits.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return circuits;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCircuit(CustomCircuitInfo circuit) async {
    final dir = await _getDir();
    final safeName = circuit.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final file = File('${dir.path}/${safeName.isEmpty ? 'circuit' : safeName}_${DateTime.now().millisecondsSinceEpoch}.json');
    final raw = jsonEncode(circuit.toJson());
    await file.writeAsString(raw);
  }
}
