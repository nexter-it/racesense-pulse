import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Risultato di un crossing della linea S/F
class LapCrossing {
  final DateTime timestamp;
  final LatLng position;
  final int lapNumber;
  final double distanceFromStart; // meters percorsi dall'inizio sessione

  LapCrossing({
    required this.timestamp,
    required this.position,
    required this.lapNumber,
    required this.distanceFromStart,
  });
}

/// Risultato completo del post-processing
class PostProcessingResult {
  final List<LapCrossing> crossings;
  final List<LapData> laps;
  final bool formationLapIncluded;

  PostProcessingResult({
    required this.crossings,
    required this.laps,
    this.formationLapIncluded = true,
  });
}

/// Dati di un singolo giro
class LapData {
  final int lapNumber;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final double distanceMeters;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final List<Position> gpsPoints;
  final bool isFormationLap;

  LapData({
    required this.lapNumber,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distanceMeters,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.gpsPoints,
    this.isFormationLap = false,
  });
}

/// Servizio per post-processing delle tracce GPS in stile RaceChrono Pro
/// Esegue analisi geometrica completa dopo la sessione live
class PostProcessingService {

  /// Esegue post-processing completo della traccia GPS
  ///
  /// [gpsTrack]: sequenza ordinata di campioni GPS ⟨t, lat, lon⟩
  /// [finishLineStart]: punto iniziale linea S/F
  /// [finishLineEnd]: punto finale linea S/F
  /// [includeFormationLap]: se true, il primo crossing marca il formation lap
  ///
  /// Returns: risultato con crossings interpolati e lap data
  static PostProcessingResult processTrack({
    required List<Position> gpsTrack,
    required LatLng finishLineStart,
    required LatLng finishLineEnd,
    bool includeFormationLap = true,
  }) {
    if (gpsTrack.length < 2) {
      return PostProcessingResult(crossings: [], laps: [], formationLapIncluded: includeFormationLap);
    }

    // Step 1: Rileva tutti i crossing con interpolazione temporale
    final crossings = _detectCrossingsWithInterpolation(
      gpsTrack,
      finishLineStart,
      finishLineEnd,
    );

    if (crossings.isEmpty) {
      return PostProcessingResult(crossings: [], laps: [], formationLapIncluded: includeFormationLap);
    }

    // Step 2: Costruisci lap data da crossings
    final laps = _buildLapData(
      gpsTrack,
      crossings,
      includeFormationLap,
    );

    return PostProcessingResult(
      crossings: crossings,
      laps: laps,
      formationLapIncluded: includeFormationLap,
    );
  }

  /// Rileva crossing usando intersezione geometrica + interpolazione temporale
  ///
  /// Per ogni segmento GPS [P(i), P(i+1)], verifica se interseca la linea S/F.
  /// Se sì, calcola il punto esatto di intersezione e interpola il timestamp.
  static List<LapCrossing> _detectCrossingsWithInterpolation(
    List<Position> gpsTrack,
    LatLng finishLineStart,
    LatLng finishLineEnd,
  ) {
    final crossings = <LapCrossing>[];
    double cumulativeDistance = 0.0;

    for (int i = 0; i < gpsTrack.length - 1; i++) {
      final p1 = gpsTrack[i];
      final p2 = gpsTrack[i + 1];

      final segmentStart = LatLng(p1.latitude, p1.longitude);
      final segmentEnd = LatLng(p2.latitude, p2.longitude);

      // Calcola distanza del segmento
      final segmentDistance = Geolocator.distanceBetween(
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
      );

      // Verifica intersezione geometrica
      final intersection = _computeLineIntersection(
        segmentStart,
        segmentEnd,
        finishLineStart,
        finishLineEnd,
      );

      if (intersection != null) {
        // Calcola parametro t ∈ [0,1] lungo il segmento GPS
        final t = _computeInterpolationParameter(
          segmentStart,
          segmentEnd,
          intersection,
        );

        // Interpola timestamp: t_crossing = t_1 + t * (t_2 - t_1)
        final dt = p2.timestamp!.difference(p1.timestamp!).inMicroseconds;
        final interpolatedTimestamp = p1.timestamp!.add(
          Duration(microseconds: (t * dt).round()),
        );

        // Distanza dall'inizio fino al punto di crossing
        final distanceToIntersection = cumulativeDistance + (segmentDistance * t);

        crossings.add(LapCrossing(
          timestamp: interpolatedTimestamp,
          position: intersection,
          lapNumber: crossings.length + 1,
          distanceFromStart: distanceToIntersection,
        ));
      }

      cumulativeDistance += segmentDistance;
    }

    return crossings;
  }

  /// Calcola intersezione tra due segmenti (algoritmo line-line intersection)
  ///
  /// Returns: punto di intersezione se esiste e giace sui segmenti, null altrimenti
  static LatLng? _computeLineIntersection(
    LatLng seg1Start,
    LatLng seg1End,
    LatLng seg2Start,
    LatLng seg2End,
  ) {
    // Converti in coordinate cartesiane locali (approssimazione flat-earth per distanze brevi)
    final x1 = seg1Start.longitude;
    final y1 = seg1Start.latitude;
    final x2 = seg1End.longitude;
    final y2 = seg1End.latitude;

    final x3 = seg2Start.longitude;
    final y3 = seg2Start.latitude;
    final x4 = seg2End.longitude;
    final y4 = seg2End.latitude;

    // Calcola denominatore
    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);

    // Linee parallele o coincidenti
    if (denom.abs() < 1e-10) {
      return null;
    }

    // Parametri t e u per le due linee parametriche
    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    final u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom;

    // Intersezione giace sui segmenti se t,u ∈ [0,1]
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
      final intersectionLng = x1 + t * (x2 - x1);
      final intersectionLat = y1 + t * (y2 - y1);
      return LatLng(intersectionLat, intersectionLng);
    }

    return null;
  }

  /// Calcola parametro di interpolazione t per un punto lungo un segmento
  ///
  /// Trova t ∈ [0,1] tale che: intersection = start + t * (end - start)
  static double _computeInterpolationParameter(
    LatLng segmentStart,
    LatLng segmentEnd,
    LatLng intersection,
  ) {
    // Usa proiezione lungo il vettore del segmento
    final dx = segmentEnd.longitude - segmentStart.longitude;
    final dy = segmentEnd.latitude - segmentStart.latitude;

    final dxIntersection = intersection.longitude - segmentStart.longitude;
    final dyIntersection = intersection.latitude - segmentStart.latitude;

    // Proiezione scalare: t = (intersection - start) · (end - start) / |end - start|²
    final dotProduct = dxIntersection * dx + dyIntersection * dy;
    final segmentLengthSquared = dx * dx + dy * dy;

    if (segmentLengthSquared < 1e-10) {
      return 0.0;
    }

    final t = dotProduct / segmentLengthSquared;
    return t.clamp(0.0, 1.0);
  }

  /// Costruisce lap data da crossings e GPS track
  static List<LapData> _buildLapData(
    List<Position> gpsTrack,
    List<LapCrossing> crossings,
    bool includeFormationLap,
  ) {
    final laps = <LapData>[];

    if (crossings.isEmpty) return laps;

    // Se includeFormationLap, il primo crossing è la fine del formation lap
    final startIndex = includeFormationLap ? 0 : 1;

    for (int i = startIndex; i < crossings.length - 1; i++) {
      final crossing1 = crossings[i];
      final crossing2 = crossings[i + 1];

      // Estrai punti GPS tra i due crossing
      final lapGpsPoints = gpsTrack.where((p) {
        final t = p.timestamp!;
        return t.isAfter(crossing1.timestamp) && t.isBefore(crossing2.timestamp);
      }).toList();

      // Calcola statistiche
      double maxSpeed = 0.0;
      double totalSpeed = 0.0;
      double lapDistance = 0.0;

      for (int j = 0; j < lapGpsPoints.length; j++) {
        final p = lapGpsPoints[j];
        final speedKmh = (p.speed * 3.6);
        maxSpeed = math.max(maxSpeed, speedKmh);
        totalSpeed += speedKmh;

        if (j > 0) {
          lapDistance += Geolocator.distanceBetween(
            lapGpsPoints[j - 1].latitude,
            lapGpsPoints[j - 1].longitude,
            p.latitude,
            p.longitude,
          );
        }
      }

      final avgSpeed = lapGpsPoints.isEmpty ? 0.0 : totalSpeed / lapGpsPoints.length;
      final duration = crossing2.timestamp.difference(crossing1.timestamp);

      // Aggiungi distanza finale (da ultimo punto GPS a crossing2)
      if (lapGpsPoints.isNotEmpty) {
        final lastPoint = lapGpsPoints.last;
        lapDistance += Geolocator.distanceBetween(
          lastPoint.latitude,
          lastPoint.longitude,
          crossing2.position.latitude,
          crossing2.position.longitude,
        );
      } else {
        // Se non ci sono punti GPS nel lap, usa distanza tra crossing
        lapDistance = Geolocator.distanceBetween(
          crossing1.position.latitude,
          crossing1.position.longitude,
          crossing2.position.latitude,
          crossing2.position.longitude,
        );
      }

      final isFormationLap = includeFormationLap && i == 0;

      laps.add(LapData(
        lapNumber: isFormationLap ? 0 : (i - (includeFormationLap ? 1 : 0) + 1),
        startTime: crossing1.timestamp,
        endTime: crossing2.timestamp,
        duration: duration,
        distanceMeters: lapDistance,
        maxSpeedKmh: maxSpeed,
        avgSpeedKmh: avgSpeed,
        gpsPoints: lapGpsPoints,
        isFormationLap: isFormationLap,
      ));
    }

    return laps;
  }

  /// Valida se una traccia GPS e una linea S/F sono compatibili
  ///
  /// Verifica che la traccia attraversi almeno una volta la linea S/F
  static bool validateTrackAndFinishLine({
    required List<Position> gpsTrack,
    required LatLng finishLineStart,
    required LatLng finishLineEnd,
  }) {
    if (gpsTrack.length < 2) return false;

    final crossings = _detectCrossingsWithInterpolation(
      gpsTrack,
      finishLineStart,
      finishLineEnd,
    );

    return crossings.isNotEmpty;
  }

  /// Calcola lunghezza stimata del circuito dalla mediana dei lap
  ///
  /// Esclude formation lap e outliers (±20% dalla mediana)
  static double estimateTrackLength(List<LapData> laps) {
    if (laps.isEmpty) return 0.0;

    // Filtra formation lap
    final validLaps = laps.where((lap) => !lap.isFormationLap).toList();
    if (validLaps.isEmpty) return 0.0;

    // Calcola mediana delle distanze
    final distances = validLaps.map((lap) => lap.distanceMeters).toList()..sort();
    final median = distances[distances.length ~/ 2];

    // Filtra outliers (±20%)
    final filtered = distances.where((d) {
      return (d - median).abs() / median < 0.2;
    }).toList();

    if (filtered.isEmpty) return median;

    // Media dei lap validi
    return filtered.reduce((a, b) => a + b) / filtered.length;
  }
}
