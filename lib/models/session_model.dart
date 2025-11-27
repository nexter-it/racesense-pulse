import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

/// Modello per una sessione di tracciamento
///
/// Struttura Firestore ottimizzata per scalabilità:
///
/// /users/{userId}
///   - fullName, email, stats (sessioni totali, distanza, etc)
///
/// /sessions/{sessionId}
///   - userId, trackName, location, date, isPublic
///   - totalDuration, distance, bestLap, lapCount
///   - maxSpeed, avgSpeed, maxGForce
///   - gpsQuality (avg accuracy, sample rate)
///
/// /sessions/{sessionId}/laps/{lapIndex}
///   - duration, avgSpeed, maxSpeed
///
/// /sessions/{sessionId}/gpsData (sub-collection)
///   - Chunk di dati GPS compressi (es. ogni 100 punti)
///   - latitude, longitude, speed, timestamp, accuracy
///
/// Vantaggi:
/// - Query veloci per feed (solo metadata sessioni)
/// - Dati GPS separati (caricati solo quando serve visualizzare dettaglio)
/// - Statistiche utente aggregate per performance
/// - Facilità di implementare privacy (isPublic filter)
///

double _roundDouble(double value, int decimals) {
  final mod = math.pow(10.0, decimals);
  return (value * mod).round() / mod;
}

class SessionModel {
  final String sessionId;
  final String userId;
  final String trackName;
  final String driverFullName;
  final String location; // "Misano, Italy"
  final GeoPoint locationCoords; // Coordinate centro circuito
  final DateTime dateTime;
  final bool isPublic;

  // Statistiche principali
  final Duration totalDuration;
  final double distanceKm;
  final Duration? bestLap;
  final int lapCount;

  // Performance
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final double maxGForce;

  // Qualità GPS
  final double avgGpsAccuracy;
  final int gpsSampleRateHz;

  final List<Map<String, double>>? displayPath;

  SessionModel({
    required this.sessionId,
    required this.userId,
    required this.trackName,
    required this.driverFullName,
    required this.location,
    required this.locationCoords,
    required this.dateTime,
    required this.isPublic,
    required this.totalDuration,
    required this.distanceKm,
    this.bestLap,
    required this.lapCount,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.maxGForce,
    required this.avgGpsAccuracy,
    required this.gpsSampleRateHz,
    this.displayPath,
  });

  // Converti in Map per Firestore
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'userId': userId,
      'trackName': trackName,
      'driverfullName': driverFullName,
      'location': location,
      'locationCoords': locationCoords,
      'dateTime': Timestamp.fromDate(dateTime),
      'isPublic': isPublic,
      'totalDuration': totalDuration.inMilliseconds,
      'distanceKm': distanceKm,
      'bestLap': bestLap?.inMilliseconds,
      'lapCount': lapCount,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': avgSpeedKmh,
      'maxGForce': maxGForce,
      'avgGpsAccuracy': avgGpsAccuracy,
      'gpsSampleRateHz': gpsSampleRateHz,
    };

    // 👇 AGGIUNTO
    if (displayPath != null) {
      data['displayPath'] = displayPath;
    }

    return data;
  }

  // Crea da Firestore
  factory SessionModel.fromFirestore(
      String sessionId, Map<String, dynamic> data) {
    // 👇 Parsing opzionale di displayPath
    final rawPath = data['displayPath'] as List<dynamic>?;
    List<Map<String, double>>? displayPath;

    if (rawPath != null) {
      displayPath = rawPath
          .whereType<Map<String, dynamic>>()
          .map((m) => {
                'lat': (m['lat'] as num).toDouble(),
                'lon': (m['lon'] as num).toDouble(),
              })
          .toList();
    }

    return SessionModel(
      sessionId: sessionId,
      userId: data['userId'] as String,
      trackName: data['trackName'] as String,
      driverFullName:
          data['driverfullName'] as String? ??
          data['driverFullName'] as String? ??
          'Pilota',
      location: data['location'] as String,
      locationCoords: data['locationCoords'] as GeoPoint,
      dateTime: (data['dateTime'] as Timestamp).toDate(),
      isPublic: data['isPublic'] as bool,
      totalDuration: Duration(milliseconds: data['totalDuration'] as int),
      distanceKm: (data['distanceKm'] as num).toDouble(),
      bestLap: data['bestLap'] != null
          ? Duration(milliseconds: data['bestLap'] as int)
          : null,
      lapCount: data['lapCount'] as int,
      maxSpeedKmh: (data['maxSpeedKmh'] as num).toDouble(),
      avgSpeedKmh: (data['avgSpeedKmh'] as num).toDouble(),
      maxGForce: (data['maxGForce'] as num).toDouble(),
      avgGpsAccuracy: (data['avgGpsAccuracy'] as num).toDouble(),
      gpsSampleRateHz: data['gpsSampleRateHz'] as int,
      displayPath: displayPath, // 👈 AGGIUNTO
    );
  }
}

/// Modello per un singolo giro
class LapModel {
  final int lapIndex;
  final Duration duration;
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  LapModel({
    required this.lapIndex,
    required this.duration,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'lapIndex': lapIndex,
      'duration': duration.inMilliseconds,
      'avgSpeedKmh': avgSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
    };
  }

  factory LapModel.fromFirestore(Map<String, dynamic> data) {
    return LapModel(
      lapIndex: data['lapIndex'] as int,
      duration: Duration(milliseconds: data['duration'] as int),
      avgSpeedKmh: (data['avgSpeedKmh'] as num).toDouble(),
      maxSpeedKmh: (data['maxSpeedKmh'] as num).toDouble(),
    );
  }
}

/// Modello per un chunk di dati GPS (per ridurre numero documenti)
class GpsDataChunk {
  final int chunkIndex;
  final List<GpsPoint> points;

  GpsDataChunk({
    required this.chunkIndex,
    required this.points,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'chunkIndex': chunkIndex,
      'points': points.map((p) => p.toMap()).toList(),
    };
  }

  factory GpsDataChunk.fromFirestore(Map<String, dynamic> data) {
    final pointsList = data['points'] as List<dynamic>;
    return GpsDataChunk(
      chunkIndex: data['chunkIndex'] as int,
      points: pointsList
          .map((p) => GpsPoint.fromMap(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class GpsPoint {
  final double latitude;
  final double longitude;
  final double speedKmh;
  final DateTime timestamp;
  final double accuracy;

  GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.timestamp,
    required this.accuracy,
  });

  Map<String, dynamic> toMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      'spd': speedKmh.roundToDouble(), // 👈 velocità intera (es. 20)
      'ts': Timestamp.fromDate(timestamp),
      'acc': _roundDouble(accuracy, 1), // 👈 accuracy 1 decimale (es. 4.5)
    };
  }

  factory GpsPoint.fromMap(Map<String, dynamic> map) {
    return GpsPoint(
      latitude: (map['lat'] as num).toDouble(),
      longitude: (map['lng'] as num).toDouble(),
      speedKmh: (map['spd'] as num).toDouble(),
      timestamp: (map['ts'] as Timestamp).toDate(),
      accuracy: (map['acc'] as num).toDouble(),
    );
  }

  factory GpsPoint.fromPosition(Position pos, double speedKmh) {
    return GpsPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      speedKmh: speedKmh,
      timestamp: pos.timestamp ?? DateTime.now(),
      accuracy: pos.accuracy,
    );
  }
}

/// Statistiche aggregate dell'utente (memorizzate nel documento user)
class UserStats {
  final int totalSessions;
  final double totalDistanceKm;
  final int totalLaps;
  final Duration? bestLapEver;
  final String? bestLapTrack;
  final int personalBests; // Numero di circuiti con PB

  UserStats({
    required this.totalSessions,
    required this.totalDistanceKm,
    required this.totalLaps,
    this.bestLapEver,
    this.bestLapTrack,
    required this.personalBests,
  });

  Map<String, dynamic> toMap() {
    return {
      'totalSessions': totalSessions,
      'totalDistanceKm': totalDistanceKm,
      'totalLaps': totalLaps,
      'bestLapEver': bestLapEver?.inMilliseconds,
      'bestLapTrack': bestLapTrack,
      'personalBests': personalBests,
    };
  }

  factory UserStats.fromMap(Map<String, dynamic> map) {
    return UserStats(
      totalSessions: map['totalSessions'] as int? ?? 0,
      totalDistanceKm: (map['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
      totalLaps: map['totalLaps'] as int? ?? 0,
      bestLapEver: map['bestLapEver'] != null
          ? Duration(milliseconds: map['bestLapEver'] as int)
          : null,
      bestLapTrack: map['bestLapTrack'] as String?,
      personalBests: map['personalBests'] as int? ?? 0,
    );
  }

  factory UserStats.empty() {
    return UserStats(
      totalSessions: 0,
      totalDistanceKm: 0.0,
      totalLaps: 0,
      personalBests: 0,
    );
  }
}
