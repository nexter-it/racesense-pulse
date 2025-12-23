import 'package:latlong2/latlong.dart';

/// Definizione di un circuito con linea Start/Finish
///
/// Sistema RaceChrono Pro: solo GPS grezzo + linea S/F disegnata manualmente.
/// Niente microsettori: lap detection via intersezione geometrica.
class TrackDefinition {
  final String id;
  final String name;
  final String location;

  /// Punto iniziale della linea Start/Finish (lat/lon)
  final LatLng finishLineStart;

  /// Punto finale della linea Start/Finish (lat/lon)
  final LatLng finishLineEnd;

  /// Lunghezza stimata del circuito in metri
  /// (calcolata dal post-processing della mediana dei lap)
  final double? estimatedLengthMeters;

  /// URL o path dell'immagine del circuito (opzionale)
  final String? imageUrl;

  /// Tracciato completo del circuito (lista di punti GPS)
  /// GPS grezzo registrato durante la sessione di tracciamento
  final List<LatLng>? trackPath;

  /// Se questo circuito è stato creato con dispositivo BLE GPS
  final bool? usedBleDevice;

  /// Frequenza GPS media usata durante il tracciamento (Hz)
  final double? gpsFrequencyHz;

  const TrackDefinition({
    required this.id,
    required this.name,
    required this.location,
    required this.finishLineStart,
    required this.finishLineEnd,
    this.estimatedLengthMeters,
    this.imageUrl,
    this.trackPath,
    this.usedBleDevice,
    this.gpsFrequencyHz,
  });

  /// Calcola il punto centrale della linea Start/Finish
  LatLng get finishLineCenter {
    return LatLng(
      (finishLineStart.latitude + finishLineEnd.latitude) / 2,
      (finishLineStart.longitude + finishLineEnd.longitude) / 2,
    );
  }

  /// Calcola la lunghezza della linea Start/Finish in metri
  double get finishLineLength {
    const distance = Distance();
    return distance.as(
      LengthUnit.Meter,
      finishLineStart,
      finishLineEnd,
    );
  }

  /// Serializza in Map per Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'finishLineStart': {
        'lat': finishLineStart.latitude,
        'lon': finishLineStart.longitude,
      },
      'finishLineEnd': {
        'lat': finishLineEnd.latitude,
        'lon': finishLineEnd.longitude,
      },
      if (estimatedLengthMeters != null)
        'estimatedLengthMeters': estimatedLengthMeters,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (trackPath != null)
        'trackPath': trackPath!
            .map((p) => {'lat': p.latitude, 'lon': p.longitude})
            .toList(),
      if (usedBleDevice != null) 'usedBleDevice': usedBleDevice,
      if (gpsFrequencyHz != null) 'gpsFrequencyHz': gpsFrequencyHz,
    };
  }

  /// Crea da Map (Firestore)
  factory TrackDefinition.fromMap(Map<String, dynamic> map) {
    return TrackDefinition(
      id: map['id'] as String,
      name: map['name'] as String,
      location: map['location'] as String,
      finishLineStart: LatLng(
        map['finishLineStart']['lat'] as double,
        map['finishLineStart']['lon'] as double,
      ),
      finishLineEnd: LatLng(
        map['finishLineEnd']['lat'] as double,
        map['finishLineEnd']['lon'] as double,
      ),
      estimatedLengthMeters: map['estimatedLengthMeters'] as double?,
      imageUrl: map['imageUrl'] as String?,
      trackPath: map['trackPath'] != null
          ? (map['trackPath'] as List)
              .map((p) => LatLng(p['lat'] as double, p['lon'] as double))
              .toList()
          : null,
      usedBleDevice: map['usedBleDevice'] as bool?,
      gpsFrequencyHz: map['gpsFrequencyHz'] as double?,
    );
  }

  /// Copia con modifiche
  TrackDefinition copyWith({
    String? id,
    String? name,
    String? location,
    LatLng? finishLineStart,
    LatLng? finishLineEnd,
    double? estimatedLengthMeters,
    String? imageUrl,
    List<LatLng>? trackPath,
    bool? usedBleDevice,
    double? gpsFrequencyHz,
  }) {
    return TrackDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      finishLineStart: finishLineStart ?? this.finishLineStart,
      finishLineEnd: finishLineEnd ?? this.finishLineEnd,
      estimatedLengthMeters: estimatedLengthMeters ?? this.estimatedLengthMeters,
      imageUrl: imageUrl ?? this.imageUrl,
      trackPath: trackPath ?? this.trackPath,
      usedBleDevice: usedBleDevice ?? this.usedBleDevice,
      gpsFrequencyHz: gpsFrequencyHz ?? this.gpsFrequencyHz,
    );
  }

  @override
  String toString() {
    return 'TrackDefinition(id: $id, name: $name, location: $location)';
  }
}

/// Circuiti predefiniti statici (circuiti ufficiali)
class PredefinedTracks {
  static final List<TrackDefinition> all = [
    const TrackDefinition(
      id: 'mugello',
      name: 'Autodromo Internazionale del Mugello',
      location: 'Scarperia e San Piero, Firenze',
      finishLineStart: LatLng(43.997439, 11.371856),
      finishLineEnd: LatLng(43.997589, 11.372044),
      estimatedLengthMeters: 5245,
      imageUrl: null,
    ),
    const TrackDefinition(
      id: 'monza',
      name: 'Autodromo Nazionale di Monza',
      location: 'Monza, MB',
      finishLineStart: LatLng(45.620722, 9.281167),
      finishLineEnd: LatLng(45.620856, 9.281389),
      estimatedLengthMeters: 5793,
      imageUrl: null,
    ),
    const TrackDefinition(
      id: 'imola',
      name: 'Autodromo Enzo e Dino Ferrari',
      location: 'Imola, BO',
      finishLineStart: LatLng(44.344167, 11.715722),
      finishLineEnd: LatLng(44.344278, 11.715889),
      estimatedLengthMeters: 4909,
      imageUrl: null,
    ),
    const TrackDefinition(
      id: 'misano',
      name: 'Misano World Circuit Marco Simoncelli',
      location: 'Misano Adriatico, RN',
      finishLineStart: LatLng(43.965389, 12.686056),
      finishLineEnd: LatLng(43.965500, 12.686222),
      estimatedLengthMeters: 4226,
      imageUrl: null,
    ),
    const TrackDefinition(
      id: 'vallelunga',
      name: 'Autodromo Vallelunga Piero Taruffi',
      location: 'Campagnano di Roma, RM',
      finishLineStart: LatLng(42.147500, 12.270833),
      finishLineEnd: LatLng(42.147639, 12.271000),
      estimatedLengthMeters: 4085,
      imageUrl: null,
    ),
  ];

  static TrackDefinition? findById(String id) {
    try {
      return all.firstWhere((track) => track.id == id);
    } catch (_) {
      return null;
    }
  }
}
