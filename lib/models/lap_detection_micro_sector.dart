import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

/// Microsettore per il rilevamento giri
/// Rappresenta una "fetta" trasversale del circuito ogni 1-2 metri
class LapDetectionMicroSector {
  /// Indice progressivo (0 = start/finish line)
  final int index;

  /// Posizione centrale del microsettore (lat/lon)
  final LatLng center;

  /// Heading della traiettoria in questo punto (gradi, 0-360)
  /// 0 = Nord, 90 = Est, 180 = Sud, 270 = Ovest
  final double heading;

  /// Distanza cumulativa dall'inizio del tracciato (metri)
  final double cumulativeDistance;

  /// Larghezza del microsettore (metri) - tipicamente 20-25m
  final double width;

  const LapDetectionMicroSector({
    required this.index,
    required this.center,
    required this.heading,
    required this.cumulativeDistance,
    this.width = 22.0,
  });

  /// Converte in coordinate locali (metri) dato un origine
  /// Returns: (x, y) in metri rispetto all'origine
  Map<String, double> toLocal(double originLat, double originLon) {
    const double earthRadiusM = 6371000.0;
    final dLat = (center.latitude - originLat) * math.pi / 180.0;
    final dLon = (center.longitude - originLon) * math.pi / 180.0;
    final avgLat = (originLat + center.latitude) / 2 * math.pi / 180.0;

    final x = dLon * earthRadiusM * math.cos(avgLat);
    final y = dLat * earthRadiusM;

    return {'x': x, 'y': y};
  }

  /// Verifica se un punto GPS è "vicino" a questo microsettore
  /// considerando la larghezza trasversale
  bool containsPoint(
    double pointLat,
    double pointLon,
    double originLat,
    double originLon,
  ) {
    // Converti sia il microsettore che il punto in coordinate locali
    final sectorLocal = toLocal(originLat, originLon);

    const double earthRadiusM = 6371000.0;
    final dLat = (pointLat - originLat) * math.pi / 180.0;
    final dLon = (pointLon - originLon) * math.pi / 180.0;
    final avgLat = (originLat + pointLat) / 2 * math.pi / 180.0;

    final px = dLon * earthRadiusM * math.cos(avgLat);
    final py = dLat * earthRadiusM;

    // Calcola distanza dal centro del microsettore
    final dx = px - sectorLocal['x']!;
    final dy = py - sectorLocal['y']!;
    final distance = math.sqrt(dx * dx + dy * dy);

    // Verifica se è dentro la larghezza del microsettore
    return distance <= width / 2;
  }

  /// Calcola la differenza di heading tra due angoli (risultato in -180..180)
  static double headingDifference(double h1, double h2) {
    double diff = h2 - h1;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    return diff;
  }

  /// Verifica se il heading del veicolo è compatibile con il microsettore
  /// tolleranza tipica: 45-60 gradi
  bool isHeadingCompatible(double vehicleHeading, {double tolerance = 50.0}) {
    final diff = headingDifference(heading, vehicleHeading).abs();
    return diff <= tolerance;
  }

  /// Serializza per salvare su Firebase
  Map<String, dynamic> toMap() {
    return {
      'index': index,
      'center': {
        'lat': center.latitude,
        'lon': center.longitude,
      },
      'heading': heading,
      'cumulativeDistance': cumulativeDistance,
      'width': width,
    };
  }

  /// Deserializza da Firebase
  factory LapDetectionMicroSector.fromMap(Map<String, dynamic> map) {
    return LapDetectionMicroSector(
      index: map['index'] as int,
      center: LatLng(
        map['center']['lat'] as double,
        map['center']['lon'] as double,
      ),
      heading: map['heading'] as double,
      cumulativeDistance: map['cumulativeDistance'] as double,
      width: map['width'] as double? ?? 22.0,
    );
  }

  @override
  String toString() {
    return 'MicroSector($index, ${center.latitude.toStringAsFixed(6)}, ${center.longitude.toStringAsFixed(6)}, ${heading.toStringAsFixed(1)}°, ${cumulativeDistance.toStringAsFixed(1)}m)';
  }
}
