import 'package:latlong2/latlong.dart';
import 'track_definition.dart';

/// Model per i circuiti ufficiali caricati dal file JSON.
/// Contiene tutte le informazioni necessarie per identificare un circuito
/// e la sua linea di Start/Finish per il conteggio giri.
class OfficialCircuitInfo {
  final String id;
  final String name;
  final String city;
  final String country;
  final String countryCode;
  final String continent;
  final double lengthMeters;
  final LatLng finishLineStart;
  final LatLng finishLineEnd;
  final String? category; // F1, MotoGP, GT, Karting, etc.

  const OfficialCircuitInfo({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.continent,
    required this.lengthMeters,
    required this.finishLineStart,
    required this.finishLineEnd,
    this.category,
  });

  /// Crea un'istanza dal JSON
  factory OfficialCircuitInfo.fromJson(Map<String, dynamic> json) {
    return OfficialCircuitInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      city: json['city'] as String,
      country: json['country'] as String,
      countryCode: json['countryCode'] as String,
      continent: json['continent'] as String,
      lengthMeters: (json['lengthMeters'] as num).toDouble(),
      finishLineStart: LatLng(
        (json['finishLineStart']['lat'] as num).toDouble(),
        (json['finishLineStart']['lon'] as num).toDouble(),
      ),
      finishLineEnd: LatLng(
        (json['finishLineEnd']['lat'] as num).toDouble(),
        (json['finishLineEnd']['lon'] as num).toDouble(),
      ),
      category: json['category'] as String?,
    );
  }

  /// Converte in JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'city': city,
      'country': country,
      'countryCode': countryCode,
      'continent': continent,
      'lengthMeters': lengthMeters,
      'finishLineStart': {
        'lat': finishLineStart.latitude,
        'lon': finishLineStart.longitude,
      },
      'finishLineEnd': {
        'lat': finishLineEnd.latitude,
        'lon': finishLineEnd.longitude,
      },
      if (category != null) 'category': category,
    };
  }

  /// Converte in TrackDefinition per l'uso nelle sessioni live
  TrackDefinition toTrackDefinition() {
    return TrackDefinition(
      id: id,
      name: name,
      location: '$city, $country',
      finishLineStart: finishLineStart,
      finishLineEnd: finishLineEnd,
      estimatedLengthMeters: lengthMeters,
    );
  }

  /// Location formattata come stringa
  String get location => '$city, $country';

  /// Lunghezza in km con 2 decimali
  double get lengthKm => lengthMeters / 1000;

  /// Stringa formattata della lunghezza
  String get lengthFormatted => '${lengthKm.toStringAsFixed(2)} km';

  /// Centro della linea di traguardo
  LatLng get finishLineCenter => LatLng(
        (finishLineStart.latitude + finishLineEnd.latitude) / 2,
        (finishLineStart.longitude + finishLineEnd.longitude) / 2,
      );

  @override
  String toString() => 'OfficialCircuitInfo($name, $location)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfficialCircuitInfo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
