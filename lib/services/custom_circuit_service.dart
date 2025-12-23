import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/track_definition.dart';
import 'track_service.dart';

class CustomCircuitInfo {
  final String name;
  final double widthMeters;
  final String city;
  final String country;
  final double lengthMeters;
  final DateTime createdAt;
  final List<LatLng> points;
  final List<MicroSector> microSectors;
  final bool usedBleDevice;

  CustomCircuitInfo({
    required this.name,
    required this.widthMeters,
    required this.city,
    required this.country,
    required this.lengthMeters,
    required this.createdAt,
    required this.points,
    required this.microSectors,
    this.usedBleDevice = false,
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
      'usedBleDevice': usedBleDevice,
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
      usedBleDevice: json['usedBleDevice'] as bool? ?? false,
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

  /// Converti CustomCircuitInfo in TrackDefinition per Firebase
  TrackDefinition toTrackDefinition() {
    // La linea del via è definita dal primo micro settore
    final finishLine = microSectors.isNotEmpty
        ? microSectors.first
        : MicroSector(start: points.first, end: points.first);

    return TrackDefinition(
      id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
      name: name,
      location: '$city, $country',
      finishLineStart: finishLine.start,
      finishLineEnd: finishLine.end,
      estimatedLengthMeters: lengthMeters,
      trackPath: points,
      widthMeters: widthMeters,
      microSectors: microSectors
          .map((s) => TrackMicroSector(start: s.start, end: s.end))
          .toList(),
    );
  }

  /// Crea CustomCircuitInfo da TrackWithMetadata (Firebase)
  factory CustomCircuitInfo.fromTrackWithMetadata(TrackWithMetadata track) {
    final trackDef = track.trackDefinition;

    return CustomCircuitInfo(
      name: trackDef.name,
      widthMeters: trackDef.widthMeters ?? 8.0,
      city: trackDef.location.split(',').first.trim(),
      country: trackDef.location.contains(',')
          ? trackDef.location.split(',').last.trim()
          : '',
      lengthMeters: trackDef.estimatedLengthMeters ?? 0.0,
      createdAt: track.createdAt,
      points: trackDef.trackPath ?? [],
      microSectors: trackDef.microSectors
              ?.map((s) => MicroSector(start: s.start, end: s.end))
              .toList() ??
          [],
      usedBleDevice: false, // Info non salvata in TrackDefinition
    );
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
  final TrackService _trackService = TrackService();

  /// Salva un circuito su Firebase
  /// Usa TrackService per scalabilità e condivisione
  Future<String> saveCircuit(
    CustomCircuitInfo circuit, {
    Function(double progress)? onProgress, // 0.0 - 1.0
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    // Converti CustomCircuitInfo in TrackDefinition
    onProgress?.call(0.2);
    final trackDefinition = circuit.toTrackDefinition();

    // Salva su Firebase (di default privato, l'utente può renderlo pubblico dopo)
    final trackId = await _trackService.saveTrack(
      userId: user.uid,
      trackDefinition: trackDefinition,
      isPublic: false,
      onProgress: (p) {
        // Rimappa in un range "salvataggio" (0.2 -> 1.0)
        onProgress?.call(0.2 + (p * 0.8));
      },
    );

    return trackId;
  }

  /// Ottieni tutti i circuiti dell'utente corrente da Firebase
  Future<List<CustomCircuitInfo>> listCircuits() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return [];
    }

    try {
      final tracksWithMetadata = await _trackService.getUserTracks(user.uid);

      // Converti TrackWithMetadata in CustomCircuitInfo
      return tracksWithMetadata
          .map((track) => CustomCircuitInfo.fromTrackWithMetadata(track))
          .toList();
    } catch (e) {
      print('❌ Errore caricamento circuiti: $e');
      return [];
    }
  }

  /// Elimina un circuito
  Future<void> deleteCircuit(String trackId) async {
    await _trackService.deleteTrack(trackId);
  }

  /// Aggiorna un circuito esistente
  Future<void> updateCircuit({
    required String trackId,
    required CustomCircuitInfo circuit,
    bool? isPublic,
  }) async {
    final trackDefinition = circuit.toTrackDefinition();
    await _trackService.updateTrack(
      trackId: trackId,
      trackDefinition: trackDefinition,
      isPublic: isPublic,
    );
  }
}
