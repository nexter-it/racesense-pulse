import 'package:latlong2/latlong.dart';
import 'track_definition.dart';

/// Model per i circuiti ufficiali caricati dal file JSON.
/// Contiene tutte le informazioni necessarie per identificare un circuito
/// e la sua linea di Start/Finish per il conteggio giri.
class OfficialCircuitInfo {
  final String file; // Nome file .tkk
  final String name;
  final String city;
  final String country;
  final LatLng finishLineStart;
  final LatLng finishLineEnd;
  final LatLng finishLineCenter;
  final double trackDirectionDeg;
  final double lineDirectionDeg;
  final double trackWidthM;
  final bool widthEstimated;

  const OfficialCircuitInfo({
    required this.file,
    required this.name,
    required this.city,
    required this.country,
    required this.finishLineStart,
    required this.finishLineEnd,
    required this.finishLineCenter,
    required this.trackDirectionDeg,
    required this.lineDirectionDeg,
    required this.trackWidthM,
    required this.widthEstimated,
  });

  /// Crea un'istanza dal JSON
  factory OfficialCircuitInfo.fromJson(Map<String, dynamic> json) {
    final startLine = json['start_line'] as Map<String, dynamic>;
    final center = startLine['center'] as Map<String, dynamic>;
    final point1 = startLine['point1'] as Map<String, dynamic>;
    final point2 = startLine['point2'] as Map<String, dynamic>;

    return OfficialCircuitInfo(
      file: json['file'] as String,
      name: json['name'] as String,
      city: json['city'] as String,
      country: json['country'] as String,
      finishLineStart: LatLng(
        (point1['lat'] as num).toDouble(),
        (point1['lon'] as num).toDouble(),
      ),
      finishLineEnd: LatLng(
        (point2['lat'] as num).toDouble(),
        (point2['lon'] as num).toDouble(),
      ),
      finishLineCenter: LatLng(
        (center['lat'] as num).toDouble(),
        (center['lon'] as num).toDouble(),
      ),
      trackDirectionDeg: (startLine['track_direction_deg'] as num).toDouble(),
      lineDirectionDeg: (startLine['line_direction_deg'] as num).toDouble(),
      trackWidthM: (startLine['track_width_m'] as num).toDouble(),
      widthEstimated: startLine['width_estimated'] as bool,
    );
  }

  /// Converte in JSON
  Map<String, dynamic> toJson() {
    return {
      'file': file,
      'name': name,
      'city': city,
      'country': country,
      'start_line': {
        'center': {
          'lat': finishLineCenter.latitude,
          'lon': finishLineCenter.longitude,
        },
        'point1': {
          'lat': finishLineStart.latitude,
          'lon': finishLineStart.longitude,
        },
        'point2': {
          'lat': finishLineEnd.latitude,
          'lon': finishLineEnd.longitude,
        },
        'track_direction_deg': trackDirectionDeg,
        'line_direction_deg': lineDirectionDeg,
        'track_width_m': trackWidthM,
        'width_estimated': widthEstimated,
      },
    };
  }

  /// Converte in TrackDefinition per l'uso nelle sessioni live
  TrackDefinition toTrackDefinition() {
    return TrackDefinition(
      id: file, // Usa il nome file come ID
      name: name,
      location: '$city, $country',
      finishLineStart: finishLineStart,
      finishLineEnd: finishLineEnd,
      estimatedLengthMeters: null, // Non abbiamo la lunghezza nel nuovo formato
    );
  }

  /// Location formattata come stringa
  String get location => '$city, $country';

  /// ID univoco basato sul nome file
  String get id => file;

  @override
  String toString() => 'OfficialCircuitInfo($name, $location)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfficialCircuitInfo &&
          runtimeType == other.runtimeType &&
          file == other.file;

  @override
  int get hashCode => file.hashCode;
}
