import 'dart:convert';
import 'dart:io';

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

  CustomCircuitInfo({
    required this.name,
    required this.widthMeters,
    required this.city,
    required this.country,
    required this.lengthMeters,
    required this.createdAt,
    required this.points,
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
