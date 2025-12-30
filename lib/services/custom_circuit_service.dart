import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/track_definition.dart';
import 'track_service.dart';

/// Info per circuito custom - RaceChrono Pro style
///
/// Solo GPS grezzo + linea S/F. Niente microsettori.
class CustomCircuitInfo {
  final String? trackId; // Firebase document ID for updates
  final String name;
  final String city;
  final String country;
  final double lengthMeters;
  final DateTime createdAt;
  final List<LatLng> points; // GPS grezzo
  final bool usedBleDevice;

  // Nuovi campi RaceChrono Pro
  final LatLng? finishLineStart;
  final LatLng? finishLineEnd;
  final double? gpsFrequencyHz;

  // Deprecated (mantenuto per backward compatibility)
  @Deprecated('Non più usato - rimuovere in futuro')
  final double widthMeters;
  @Deprecated('Non più usato - rimuovere in futuro')
  final List<MicroSector> microSectors;

  CustomCircuitInfo({
    this.trackId,
    required this.name,
    required this.city,
    required this.country,
    required this.lengthMeters,
    required this.createdAt,
    required this.points,
    this.usedBleDevice = false,
    this.finishLineStart,
    this.finishLineEnd,
    this.gpsFrequencyHz,
    // Deprecated fields
    this.widthMeters = 0.0,
    this.microSectors = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
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
      'usedBleDevice': usedBleDevice,
      if (finishLineStart != null)
        'finishLineStart': {
          'lat': finishLineStart!.latitude,
          'lon': finishLineStart!.longitude,
        },
      if (finishLineEnd != null)
        'finishLineEnd': {
          'lat': finishLineEnd!.latitude,
          'lon': finishLineEnd!.longitude,
        },
      if (gpsFrequencyHz != null) 'gpsFrequencyHz': gpsFrequencyHz,
      // Backward compatibility (deprecated)
      'widthMeters': widthMeters,
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

    // Parse finish line (nuovo formato)
    LatLng? finishLineStart;
    LatLng? finishLineEnd;

    if (json['finishLineStart'] != null) {
      final fls = json['finishLineStart'] as Map<String, dynamic>;
      finishLineStart = LatLng(
        (fls['lat'] as num).toDouble(),
        (fls['lon'] as num).toDouble(),
      );
    }

    if (json['finishLineEnd'] != null) {
      final fle = json['finishLineEnd'] as Map<String, dynamic>;
      finishLineEnd = LatLng(
        (fle['lat'] as num).toDouble(),
        (fle['lon'] as num).toDouble(),
      );
    }

    // Fallback: se non ha finishLine ma ha microSectors, usa primo microsettore
    if (finishLineStart == null && finishLineEnd == null) {
      final microSectors = (json['microSectors'] as List<dynamic>?)
          ?.map((s) => MicroSector.fromJson(s as Map<String, dynamic>))
          .toList();

      if (microSectors != null && microSectors.isNotEmpty) {
        finishLineStart = microSectors.first.start;
        finishLineEnd = microSectors.first.end;
      } else if (pts.isNotEmpty) {
        // Ultimo fallback: usa primi due punti della traccia
        finishLineStart = pts.first;
        finishLineEnd = pts.length > 1 ? pts[1] : pts.first;
      }
    }

    return CustomCircuitInfo(
      name: json['name'] as String? ?? 'Circuito',
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      lengthMeters: (json['lengthMeters'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      points: pts,
      usedBleDevice: json['usedBleDevice'] as bool? ?? false,
      finishLineStart: finishLineStart,
      finishLineEnd: finishLineEnd,
      gpsFrequencyHz: (json['gpsFrequencyHz'] as num?)?.toDouble(),
      // Deprecated (backward compatibility)
      widthMeters: (json['widthMeters'] as num?)?.toDouble() ?? 0.0,
      microSectors: (json['microSectors'] as List<dynamic>?)
              ?.map((s) => MicroSector.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Converti CustomCircuitInfo in TrackDefinition per Firebase
  TrackDefinition toTrackDefinition() {
    // Usa finish line se disponibile, altrimenti primo microsettore (fallback)
    LatLng fStart = finishLineStart ?? points.first;
    LatLng fEnd = finishLineEnd ??
        (points.length > 1 ? points[1] : points.first);

    // Se c'è microSectors (vecchio formato), usa quello come fallback
    if (finishLineStart == null &&
        finishLineEnd == null &&
        microSectors.isNotEmpty) {
      fStart = microSectors.first.start;
      fEnd = microSectors.first.end;
    }

    return TrackDefinition(
      id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
      name: name,
      location: '$city, $country',
      finishLineStart: fStart,
      finishLineEnd: fEnd,
      estimatedLengthMeters: lengthMeters,
      trackPath: points,
      usedBleDevice: usedBleDevice,
      gpsFrequencyHz: gpsFrequencyHz,
    );
  }

  /// Crea CustomCircuitInfo da TrackWithMetadata (Firebase)
  factory CustomCircuitInfo.fromTrackWithMetadata(TrackWithMetadata track) {
    final trackDef = track.trackDefinition;

    return CustomCircuitInfo(
      trackId: track.trackId,
      name: trackDef.name,
      city: trackDef.location.split(',').first.trim(),
      country: trackDef.location.contains(',')
          ? trackDef.location.split(',').last.trim()
          : '',
      lengthMeters: trackDef.estimatedLengthMeters ?? 0.0,
      createdAt: track.createdAt,
      points: trackDef.trackPath ?? [],
      usedBleDevice: trackDef.usedBleDevice ?? false,
      finishLineStart: trackDef.finishLineStart,
      finishLineEnd: trackDef.finishLineEnd,
      gpsFrequencyHz: trackDef.gpsFrequencyHz,
    );
  }
}

/// MicroSector - DEPRECATED
/// Mantenuto solo per backward compatibility con vecchi circuiti
@Deprecated('Non più usato - RaceChrono Pro usa solo linea S/F')
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
