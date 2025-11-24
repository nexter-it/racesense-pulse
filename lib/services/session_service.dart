import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../models/session_model.dart';

double _roundDouble(double value, int decimals) {
  // 👈 AGGIUNTO
  final mod = math.pow(10.0, decimals);
  return (value * mod).round() / mod;
}

class SessionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Salva una sessione completa su Firestore
  /// Ottimizzato per scalabilità con sub-collections
  Future<String> saveSession({
    required String userId,
    required String trackName,
    required String location,
    required GeoPoint locationCoords,
    required bool isPublic,
    required List<Position> gpsTrack,
    required List<Duration> laps,
    required Duration totalDuration,
    required List<double> speedHistory,
    required List<double> gForceHistory,
    required List<double> gpsAccuracyHistory,
    required List<Duration> timeHistory,
  }) async {
    try {
      // Calcola statistiche
      final rawDistance = _calculateDistance(gpsTrack);
      final distance = _roundDouble(rawDistance, 1); // es. 5.3 km

      final bestLap =
          laps.isNotEmpty ? laps.reduce((a, b) => a < b ? a : b) : null;

      final rawMaxSpeed =
          speedHistory.isNotEmpty ? speedHistory.reduce(math.max) : 0.0;
      final rawAvgSpeed = speedHistory.isNotEmpty
          ? speedHistory.reduce((a, b) => a + b) / speedHistory.length
          : 0.0;

      final maxSpeed = rawMaxSpeed.roundToDouble(); // es. 20 km/h
      final avgSpeed = rawAvgSpeed.roundToDouble(); // es. 18 km/h

      final rawMaxGForce =
          gForceHistory.isNotEmpty ? gForceHistory.reduce(math.max) : 0.0;
      final maxGForce = _roundDouble(rawMaxGForce, 2); // es. 1.06

      final rawAvgAccuracy = gpsAccuracyHistory.isNotEmpty
          ? gpsAccuracyHistory.reduce((a, b) => a + b) /
              gpsAccuracyHistory.length
          : 0.0;
      final avgAccuracy = _roundDouble(rawAvgAccuracy, 1); // es. 4.5 m

      final sampleRate = _calculateGpsSampleRate(timeHistory);

      // 👇 AGGIUNGI QUESTO
      final displayPath = _buildDisplayPath(gpsTrack, maxPoints: 200);

      // Crea il modello della sessione
      final sessionModel = SessionModel(
        sessionId: '', // Verrà assegnato da Firestore
        userId: userId,
        trackName: trackName,
        location: location,
        locationCoords: locationCoords,
        dateTime: DateTime.now(),
        isPublic: isPublic,
        totalDuration: totalDuration,
        distanceKm: distance,
        bestLap: bestLap,
        lapCount: laps.length,
        maxSpeedKmh: maxSpeed,
        avgSpeedKmh: avgSpeed,
        maxGForce: maxGForce,
        avgGpsAccuracy: avgAccuracy,
        gpsSampleRateHz: sampleRate,
        displayPath: displayPath,
      );

      // 1. Salva documento sessione principale
      final sessionRef = await _firestore.collection('sessions').add(
            sessionModel.toFirestore(),
          );
      final sessionId = sessionRef.id;

      // 👇 AGGIUNGI: path semplificato per feed/profilo
      await sessionRef.update({
        'displayPath': displayPath,
      });

      // 2. Salva giri in sub-collection
      await _saveLaps(sessionId, laps, speedHistory, timeHistory);

      // 3. Salva dati GPS in chunks (opzionale, caricato solo in dettaglio)
      await _saveGpsData(sessionId, gpsTrack, speedHistory);

      // 4. Aggiorna statistiche utente
      await _updateUserStats(userId, distance, laps.length, bestLap, trackName);

      return sessionId;
    } catch (e) {
      throw 'Errore nel salvataggio della sessione: $e';
    }
  }

  /// Salva i giri in una sub-collection
  Future<void> _saveLaps(
    String sessionId,
    List<Duration> laps,
    List<double> speedHistory,
    List<Duration> timeHistory,
  ) async {
    final batch = _firestore.batch();

    for (int i = 0; i < laps.length; i++) {
      // Calcola velocità media e massima per questo giro
      final lapStartTime =
          i == 0 ? Duration.zero : laps.take(i).reduce((a, b) => a + b);
      final lapEndTime = laps.take(i + 1).reduce((a, b) => a + b);

      // Trova indici dei punti di questo giro
      final lapSpeedData = <double>[];
      for (int j = 0; j < timeHistory.length; j++) {
        if (timeHistory[j] >= lapStartTime && timeHistory[j] <= lapEndTime) {
          if (j < speedHistory.length) {
            lapSpeedData.add(speedHistory[j]);
          }
        }
      }

      final avgSpeed = lapSpeedData.isNotEmpty
          ? lapSpeedData.reduce((a, b) => a + b) / lapSpeedData.length
          : 0.0;
      final maxSpeed =
          lapSpeedData.isNotEmpty ? lapSpeedData.reduce(math.max) : 0.0;

      final lapModel = LapModel(
        lapIndex: i,
        duration: laps[i],
        avgSpeedKmh: avgSpeed,
        maxSpeedKmh: maxSpeed,
      );

      final lapRef = _firestore
          .collection('sessions')
          .doc(sessionId)
          .collection('laps')
          .doc('lap_$i');

      batch.set(lapRef, lapModel.toFirestore());
    }

    await batch.commit();
  }

  /// Salva dati GPS in chunks per ottimizzare le query
  /// Ogni chunk contiene 100 punti GPS
  Future<void> _saveGpsData(
    String sessionId,
    List<Position> gpsTrack,
    List<double> speedHistory,
  ) async {
    const chunkSize = 100;
    final chunks = <GpsDataChunk>[];

    for (int i = 0; i < gpsTrack.length; i += chunkSize) {
      final end = math.min(i + chunkSize, gpsTrack.length);
      final chunkPoints = <GpsPoint>[];

      for (int j = i; j < end; j++) {
        final speed = j < speedHistory.length ? speedHistory[j] : 0.0;
        final roundedSpeed = speed.roundToDouble(); // 👈 velocità intera
        chunkPoints.add(GpsPoint.fromPosition(gpsTrack[j], roundedSpeed));
      }

      chunks.add(GpsDataChunk(
        chunkIndex: i ~/ chunkSize,
        points: chunkPoints,
      ));
    }

    // Salva chunks in batch
    final batch = _firestore.batch();
    for (final chunk in chunks) {
      final chunkRef = _firestore
          .collection('sessions')
          .doc(sessionId)
          .collection('gpsData')
          .doc('chunk_${chunk.chunkIndex}');
      batch.set(chunkRef, chunk.toFirestore());
    }

    await batch.commit();
  }

  /// Aggiorna statistiche aggregate dell'utente
  Future<void> _updateUserStats(
    String userId,
    double distanceKm,
    int lapsCount,
    Duration? bestLap,
    String trackName,
  ) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final userDoc = await userRef.get();

      UserStats currentStats;
      if (userDoc.exists && userDoc.data()?['stats'] != null) {
        currentStats =
            UserStats.fromMap(userDoc.data()!['stats'] as Map<String, dynamic>);
      } else {
        currentStats = UserStats.empty();
      }

      // Aggiorna statistiche
      final updatedStats = UserStats(
        totalSessions: currentStats.totalSessions + 1,
        totalDistanceKm: _roundDouble(
          // 👈 1 decimale
          currentStats.totalDistanceKm + distanceKm,
          1,
        ),
        totalLaps: currentStats.totalLaps + lapsCount,
        bestLapEver: _getBestLap(currentStats.bestLapEver, bestLap),
        bestLapTrack: _getBestLap(currentStats.bestLapEver, bestLap) == bestLap
            ? trackName
            : currentStats.bestLapTrack,
        personalBests: currentStats.personalBests,
      );

      // Usa set con merge per creare il campo se non esiste
      await userRef.set({
        'stats': updatedStats.toMap(),
      }, SetOptions(merge: true));

      print('✅ Stats aggiornate per user $userId: ${updatedStats.toMap()}');
    } catch (e) {
      print('❌ Errore aggiornamento stats: $e');
      rethrow;
    }
  }

  Duration? _getBestLap(Duration? current, Duration? new_) {
    if (current == null) return new_;
    if (new_ == null) return current;
    return current < new_ ? current : new_;
  }

  /// Calcola distanza totale dal tracciato GPS
  double _calculateDistance(List<Position> gpsTrack) {
    if (gpsTrack.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < gpsTrack.length; i++) {
      final prev = gpsTrack[i - 1];
      final curr = gpsTrack[i];

      final dLat = (curr.latitude - prev.latitude) * math.pi / 180.0;
      final dLon = (curr.longitude - prev.longitude) * math.pi / 180.0;

      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(prev.latitude * math.pi / 180.0) *
              math.cos(curr.latitude * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);

      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      totalDistance += 6371000 * c; // Raggio Terra in metri
    }

    return totalDistance / 1000; // Converti in km
  }

  /// Calcola frequenza di campionamento GPS
  int _calculateGpsSampleRate(List<Duration> timeHistory) {
    if (timeHistory.length < 2) return 0;

    int totalIntervals = 0;
    int sumMs = 0;

    for (int i = 1; i < timeHistory.length; i++) {
      final diff =
          timeHistory[i].inMilliseconds - timeHistory[i - 1].inMilliseconds;
      if (diff > 0 && diff < 5000) {
        sumMs += diff;
        totalIntervals++;
      }
    }

    if (totalIntervals == 0) return 0;
    final avgMs = sumMs / totalIntervals;
    return (1000 / avgMs).round();
  }

  /// Path semplificato per feed/profilo (max [maxPoints] punti)
  List<Map<String, double>> _buildDisplayPath(
    List<Position> gpsTrack, {
    int maxPoints = 200,
  }) {
    if (gpsTrack.isEmpty) return [];

    if (gpsTrack.length <= maxPoints) {
      return gpsTrack
          .map((p) => {
                'lat': p.latitude,
                'lon': p.longitude,
              })
          .toList();
    }

    final step = (gpsTrack.length / maxPoints).ceil().clamp(1, gpsTrack.length);
    final points = <Map<String, double>>[];

    for (int i = 0; i < gpsTrack.length; i += step) {
      final p = gpsTrack[i];
      points.add({
        'lat': p.latitude,
        'lon': p.longitude,
      });
    }

    // assicurati di includere l'ultimo punto
    final last = gpsTrack.last;
    points.add({'lat': last.latitude, 'lon': last.longitude});

    return points;
  }

  /// Recupera le sessioni di un utente (solo metadata, no GPS)
  Future<List<SessionModel>> getUserSessions(String userId,
      {int limit = 20}) async {
    try {
      print('📥 Caricamento sessioni per user: $userId');

      final querySnapshot = await _firestore
          .collection('sessions')
          .where('userId', isEqualTo: userId)
          .orderBy('dateTime', descending: true)
          .limit(limit)
          .get();

      print('📊 Trovate ${querySnapshot.docs.length} sessioni');

      final sessions = querySnapshot.docs.map((doc) {
        print('  - Sessione: ${doc.id} - ${doc.data()['trackName']}');
        return SessionModel.fromFirestore(doc.id, doc.data());
      }).toList();

      return sessions;
    } catch (e) {
      print('❌ Errore caricamento sessioni: $e');
      rethrow;
    }
  }

  /// Recupera le sessioni pubbliche per il feed (senza GPS)
  Future<List<SessionModel>> getPublicSessions({int limit = 20}) async {
    try {
      print('📥 Caricamento sessioni pubbliche...');

      final query = _firestore
          .collection('sessions')
          .where('isPublic', isEqualTo: true)
          .orderBy('dateTime', descending: true)
          .limit(limit);

      print(
          '🔎 Eseguo query feed: isPublic == true, orderBy dateTime DESC, limit $limit');

      final querySnapshot = await query.get();

      print('📊 Trovate ${querySnapshot.docs.length} sessioni pubbliche');
      for (final doc in querySnapshot.docs) {
        print('  - ${doc.id} => ${doc.data()}');
      }

      return querySnapshot.docs
          .map((doc) => SessionModel.fromFirestore(doc.id, doc.data()))
          .toList();
    } on FirebaseException catch (e) {
      // 👇 QUI, se manca un indice, vedi il link per crearla
      print('❌ Firestore getPublicSessions error: ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Errore generico getPublicSessions: $e');
      rethrow;
    }
  }

  /// Recupera i dati GPS di una sessione specifica (caricamento on-demand)
  Future<List<GpsPoint>> getSessionGpsData(String sessionId) async {
    final querySnapshot = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('gpsData')
        .orderBy('chunkIndex')
        .get();

    final allPoints = <GpsPoint>[];
    for (final doc in querySnapshot.docs) {
      final chunk = GpsDataChunk.fromFirestore(doc.data());
      allPoints.addAll(chunk.points);
    }

    return allPoints;
  }

  /// Recupera i giri di una sessione
  Future<List<LapModel>> getSessionLaps(String sessionId) async {
    final querySnapshot = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('laps')
        .orderBy('lapIndex')
        .get();

    return querySnapshot.docs
        .map((doc) => LapModel.fromFirestore(doc.data()))
        .toList();
  }

  /// Recupera le statistiche dell'utente
  Future<UserStats> getUserStats(String userId) async {
    try {
      print('📈 Caricamento stats per user: $userId');

      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists && userDoc.data()?['stats'] != null) {
        final stats =
            UserStats.fromMap(userDoc.data()!['stats'] as Map<String, dynamic>);
        print(
            '✅ Stats trovate: ${stats.totalSessions} sessioni, ${stats.totalDistanceKm.toStringAsFixed(1)} km');
        return stats;
      }

      print('⚠️ Nessuna stats trovata, ritorno stats vuote');
      return UserStats.empty();
    } catch (e) {
      print('❌ Errore caricamento stats: $e');
      return UserStats.empty();
    }
  }
}
