import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/lap_detection_micro_sector.dart';
import '../models/track_definition.dart';

/// Servizio per il rilevamento giri basato su microsettori
class LapDetectionService {
  // Microsettori del circuito
  List<LapDetectionMicroSector>? _microSectors;

  // Tracking dello stato corrente
  int _currentSectorIndex = -1;
  int _lastCompletedSectorIndex = -1;

  // Storia recente per rilevamento frequenza GPS
  final List<DateTime> _recentGpsTimestamps = [];
  static const int _gpsHistorySize = 10;

  // Origine per coordinate locali
  double? _originLat;
  double? _originLon;

  // Linea start/finish per fallback
  LatLng? _finishLineStart;
  LatLng? _finishLineEnd;

  // Dati primo giro (modalità veloce)
  final List<Position> _firstLapRecording = [];
  bool _isRecordingFirstLap = false;
  DateTime? _firstLapStartTime;

  // Callback per notifica giro completato
  Function(Duration lapTime)? onLapCompleted;

  // ============================================================
  // INIZIALIZZAZIONE
  // ============================================================

  /// Inizializza con un circuito pre-tracciato
  void initializeWithTrack(TrackDefinition track) {
    _finishLineStart = track.finishLineStart;
    _finishLineEnd = track.finishLineEnd;

    // Imposta origine al centro della linea start/finish
    _originLat = (track.finishLineStart.latitude + track.finishLineEnd.latitude) / 2;
    _originLon = (track.finishLineStart.longitude + track.finishLineEnd.longitude) / 2;

    // Priorità 1: Se ha microSectors (circuiti custom), convertili
    if (track.microSectors != null && track.microSectors!.isNotEmpty) {
      _microSectors = _convertTrackMicroSectorsToLapDetection(
        track.microSectors!,
        track.finishLineStart,
        track.finishLineEnd,
      );
      print('✓ ${_microSectors!.length} microsettori convertiti da circuito custom');
    }
    // Priorità 2: Se ha trackPath, genera microsettori
    else if (track.trackPath != null && track.trackPath!.length > 10) {
      _microSectors = _generateMicroSectorsFromPath(
        track.trackPath!,
        track.finishLineStart,
        track.finishLineEnd,
      );
      print('✓ ${_microSectors!.length} microsettori generati da trackPath');
    }
    // Altrimenti: usa solo la linea di traguardo (fallback)
    else {
      print('⚠️ Nessun trackPath o microSectors: uso fallback per primo giro');
    }

    _currentSectorIndex = 0;
    _lastCompletedSectorIndex = -1;
  }

  /// Inizializza per modalità veloce (senza circuito pre-tracciato)
  void initializeQuickMode(LatLng finishLineStart, LatLng finishLineEnd) {
    _finishLineStart = finishLineStart;
    _finishLineEnd = finishLineEnd;

    _originLat = (finishLineStart.latitude + finishLineEnd.latitude) / 2;
    _originLon = (finishLineStart.longitude + finishLineEnd.longitude) / 2;

    // Avvia registrazione primo giro
    _isRecordingFirstLap = true;
    _firstLapRecording.clear();
    _firstLapStartTime = DateTime.now();

    print('✓ Modalità veloce: registrazione primo giro per generare microsettori');
  }

  /// Reset completo del servizio
  void reset() {
    _microSectors = null;
    _currentSectorIndex = -1;
    _lastCompletedSectorIndex = -1;
    _recentGpsTimestamps.clear();
    _firstLapRecording.clear();
    _isRecordingFirstLap = false;
    _firstLapStartTime = null;
  }

  // ============================================================
  // GENERAZIONE MICROSETTORI
  // ============================================================

  /// Genera microsettori da una traiettoria GPS
  List<LapDetectionMicroSector> _generateMicroSectorsFromPath(
    List<LatLng> path,
    LatLng finishLineStart,
    LatLng finishLineEnd,
  ) {
    if (path.length < 10) {
      throw Exception('Path troppo corta per generare microsettori');
    }

    // 🔧 Adatta spacing e larghezza in base alla frequenza GPS
    final gpsFrequency = _estimateGpsFrequency();
    final double sectorSpacing;
    final double sectorWidth;

    if (gpsFrequency >= 15.0) {
      // BLE GPS (15-20Hz): microsettori densi e stretti
      sectorSpacing = 1.5; // metri tra microsettori
      sectorWidth = 22.0;  // larghezza trasversale
    } else if (gpsFrequency >= 5.0) {
      // GPS intermedio: microsettori medi
      sectorSpacing = 3.0;
      sectorWidth = 30.0;
    } else {
      // GPS cellulare (1Hz): microsettori più spaziati e larghi
      sectorSpacing = 5.0; // 🔧 Aumentato da 1.5m a 5m
      // 🔧 Larghezza limitata a 40m per evitare sovrapposizioni su circuiti stretti
      sectorWidth = 40.0;  // Ridotto da 45m a 40m (più sicuro)
    }

    final sectors = <LapDetectionMicroSector>[];
    double cumulativeDistance = 0.0;

    // Primo microsettore: sulla linea start/finish
    final finishCenter = LatLng(
      (finishLineStart.latitude + finishLineEnd.latitude) / 2,
      (finishLineStart.longitude + finishLineEnd.longitude) / 2,
    );

    final finishHeading = _calculateHeading(finishLineStart, finishLineEnd);

    sectors.add(LapDetectionMicroSector(
      index: 0,
      center: finishCenter,
      heading: finishHeading,
      cumulativeDistance: 0.0,
      width: sectorWidth,
    ));

    // Genera microsettori lungo il percorso
    double distanceSinceLastSector = 0.0;
    int sectorIndex = 1;

    for (int i = 1; i < path.length; i++) {
      final prev = path[i - 1];
      final curr = path[i];

      final segmentDistance = _distanceBetween(prev, curr);
      cumulativeDistance += segmentDistance;
      distanceSinceLastSector += segmentDistance;

      // Crea un microsettore ogni ~sectorSpacing metri
      if (distanceSinceLastSector >= sectorSpacing) {
        final heading = _calculateHeading(prev, curr);

        sectors.add(LapDetectionMicroSector(
          index: sectorIndex++,
          center: curr,
          heading: heading,
          cumulativeDistance: cumulativeDistance,
          width: sectorWidth,
        ));

        distanceSinceLastSector = 0.0;
      }
    }

    print('✓ Generati ${sectors.length} microsettori, lunghezza totale: ${cumulativeDistance.toStringAsFixed(0)}m');

    return sectors;
  }

  /// Converte TrackMicroSector (vecchio formato) in LapDetectionMicroSector (nuovo formato)
  /// TrackMicroSector ha: start + end (linea trasversale)
  /// LapDetectionMicroSector ha: center + heading + index + cumulativeDistance + width
  List<LapDetectionMicroSector> _convertTrackMicroSectorsToLapDetection(
    List<TrackMicroSector> trackMicroSectors,
    LatLng finishLineStart,
    LatLng finishLineEnd,
  ) {
    if (trackMicroSectors.isEmpty) {
      throw Exception('Lista microSectors vuota');
    }

    // 🔧 Adatta larghezza in base alla frequenza GPS (per circuiti custom)
    final gpsFrequency = _estimateGpsFrequency();
    final double widthMultiplier;

    if (gpsFrequency >= 15.0) {
      widthMultiplier = 1.0; // BLE: usa larghezza originale
    } else if (gpsFrequency >= 5.0) {
      widthMultiplier = 1.4; // GPS intermedio: 40% più largo
    } else {
      widthMultiplier = 2.0; // GPS cellulare: 2x più largo
    }

    final sectors = <LapDetectionMicroSector>[];
    double cumulativeDistance = 0.0;

    for (int i = 0; i < trackMicroSectors.length; i++) {
      final trackSector = trackMicroSectors[i];

      // Calcola il centro del microsettore (punto medio tra start e end)
      final center = LatLng(
        (trackSector.start.latitude + trackSector.end.latitude) / 2,
        (trackSector.start.longitude + trackSector.end.longitude) / 2,
      );

      // Calcola heading: direzione perpendicolare alla linea start-end
      // La linea start-end è trasversale al tracciato, quindi ruotiamo di 90°
      final lineHeading = _calculateHeading(trackSector.start, trackSector.end);
      final trackHeading = (lineHeading + 90) % 360; // Perpendicular to the line

      // Calcola larghezza del microsettore e adattala per GPS
      final baseWidth = _distanceBetween(trackSector.start, trackSector.end);
      final adaptedWidth = baseWidth * widthMultiplier;

      // Calcola distanza cumulativa dal settore precedente
      if (i > 0) {
        final prevCenter = LatLng(
          (trackMicroSectors[i - 1].start.latitude + trackMicroSectors[i - 1].end.latitude) / 2,
          (trackMicroSectors[i - 1].start.longitude + trackMicroSectors[i - 1].end.longitude) / 2,
        );
        cumulativeDistance += _distanceBetween(prevCenter, center);
      }

      sectors.add(LapDetectionMicroSector(
        index: i,
        center: center,
        heading: trackHeading,
        cumulativeDistance: cumulativeDistance,
        width: adaptedWidth,
      ));
    }

    print('✓ Convertiti ${sectors.length} microsettori (GPS ${gpsFrequency.toStringAsFixed(1)}Hz, moltiplicatore larghezza ${widthMultiplier.toStringAsFixed(1)}x)');

    return sectors;
  }

  /// Completa il primo giro e genera i microsettori dalla traiettoria registrata
  void _completeFirstLapAndGenerateSectors(List<Position> recording) {
    if (recording.length < 20) {
      print('⚠️ Primo giro troppo corto, continua registrazione');
      return;
    }

    // Converti Position -> LatLng
    final path = recording.map((p) => LatLng(p.latitude, p.longitude)).toList();

    // Genera microsettori
    _microSectors = _generateMicroSectorsFromPath(
      path,
      _finishLineStart!,
      _finishLineEnd!,
    );

    _isRecordingFirstLap = false;
    _currentSectorIndex = 0;
    _lastCompletedSectorIndex = -1;

    print('✓ Primo giro completato, ${_microSectors!.length} microsettori generati');
  }

  // ============================================================
  // TRACKING DURANTE LA SESSIONE
  // ============================================================

  /// Processa un nuovo punto GPS e rileva eventuali attraversamenti di microsettori
  /// Returns: true se è stato completato un giro
  bool processGpsPoint(Position position, {double? vehicleHeading}) {
    // Aggiorna storia timestamp per rilevamento frequenza
    _updateGpsTimestamps(DateTime.now());

    // Se stiamo registrando il primo giro (modalità veloce)
    if (_isRecordingFirstLap) {
      _firstLapRecording.add(position);
      // Verifica se abbiamo completato il primo giro con fallback
      if (_checkFirstLapCompletionFallback(position)) {
        _completeFirstLapAndGenerateSectors(_firstLapRecording);
        return false; // Primo giro non conta come lap completato
      }
      return false;
    }

    // Se non abbiamo microsettori, usa fallback
    if (_microSectors == null || _microSectors!.isEmpty) {
      return _checkLapFallback(position, vehicleHeading);
    }

    // Sistema principale con microsettori
    return _trackWithMicroSectors(position, vehicleHeading);
  }

  /// Tracking principale con microsettori
  bool _trackWithMicroSectors(Position position, double? vehicleHeading) {
    if (_microSectors == null || _originLat == null || _originLon == null) {
      return false;
    }

    final gpsFrequency = _estimateGpsFrequency();
    final searchWindow = _calculateSearchWindow(gpsFrequency);

    // 🔧 GPS cellulare: interpola traiettoria tra ultimo punto e punto corrente
    List<LatLng> pointsToCheck = [LatLng(position.latitude, position.longitude)];

    if (gpsFrequency < 5.0 && _lastGpsPosition != null) {
      // Interpola 3 punti intermedi per GPS lento
      final start = LatLng(_lastGpsPosition!.latitude, _lastGpsPosition!.longitude);
      final end = LatLng(position.latitude, position.longitude);
      pointsToCheck = _interpolatePoints(start, end, 3);
    }

    // Cerca il microsettore corrispondente nella finestra avanti
    int? foundSectorIndex;
    double minDistance = double.infinity;

    final startSearch = _currentSectorIndex;
    final endSearch = math.min(
      _currentSectorIndex + searchWindow,
      _microSectors!.length,
    );

    // Controlla tutti i punti (interpolati o singolo)
    for (final checkPoint in pointsToCheck) {
      for (int i = startSearch; i < endSearch; i++) {
        final sector = _microSectors![i];

        if (sector.containsPoint(
          checkPoint.latitude,
          checkPoint.longitude,
          _originLat!,
          _originLon!,
        )) {
          // Verifica heading se disponibile (solo per punto finale)
          if (vehicleHeading != null && checkPoint == pointsToCheck.last) {
            // 🔧 Tolleranza heading adattiva: GPS cellulare meno preciso
            final headingTolerance = gpsFrequency < 5.0 ? 70.0 : 50.0;
            if (!sector.isHeadingCompatible(vehicleHeading, tolerance: headingTolerance)) {
              continue; // Skip se heading non compatibile
            }
          }

          // Calcola distanza dal centro del settore per scegliere il migliore
          final distance = _distanceBetween(checkPoint, sector.center);

          if (distance < minDistance) {
            minDistance = distance;
            foundSectorIndex = i;
          }
        }
      }
    }

    // Salva ultima posizione per interpolazione
    _lastGpsPosition = LatLng(position.latitude, position.longitude);

    // Se abbiamo trovato un settore, aggiorna la posizione
    if (foundSectorIndex != null) {
      if (foundSectorIndex > _currentSectorIndex) {
        _currentSectorIndex = foundSectorIndex;
        _lastCompletedSectorIndex = foundSectorIndex;
      }

      // Verifica se abbiamo completato un giro
      if (_hasCompletedLap()) {
        _resetLapTracking();
        return true;
      }
    }

    return false;
  }

  /// Interpola N punti tra start e end per GPS a bassa frequenza
  List<LatLng> _interpolatePoints(LatLng start, LatLng end, int numPoints) {
    final points = <LatLng>[start];

    for (int i = 1; i <= numPoints; i++) {
      final t = i / (numPoints + 1);
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lon = start.longitude + (end.longitude - start.longitude) * t;
      points.add(LatLng(lat, lon));
    }

    points.add(end);
    return points;
  }

  LatLng? _lastGpsPosition;

  /// Verifica se è stato completato un giro
  bool _hasCompletedLap() {
    if (_microSectors == null || _microSectors!.isEmpty) return false;

    // 🔧 Soglia adattiva in base alla frequenza GPS
    final gpsFrequency = _estimateGpsFrequency();
    final double completionThreshold;

    if (gpsFrequency >= 15.0) {
      // BLE GPS (15-20Hz): soglia alta (85%)
      completionThreshold = 0.85;
    } else if (gpsFrequency >= 5.0) {
      // GPS intermedio: soglia media (75%)
      completionThreshold = 0.75;
    } else {
      // GPS cellulare (1Hz): soglia bassa (65%)
      completionThreshold = 0.65; // 🔧 Ridotto da 80% a 65%
    }

    final minSectorsForLap = (_microSectors!.length * completionThreshold).floor();
    if (_lastCompletedSectorIndex < minSectorsForLap) return false;

    // Deve essere tornato vicino al settore 0
    final nearStart = _currentSectorIndex <= 10 ||
                      _currentSectorIndex >= _microSectors!.length - 10;

    return nearStart;
  }

  /// Reset tracking dopo un giro completato
  void _resetLapTracking() {
    _currentSectorIndex = 0;
    _lastCompletedSectorIndex = -1;
  }

  // ============================================================
  // FALLBACK (PRIMO GIRO MODALITÀ VELOCE)
  // ============================================================

  DateTime? _lastFallbackCrossing;
  double _fallbackLastDistance = 0.0;

  /// Verifica attraversamento con fallback semplice (geofence + heading)
  bool _checkLapFallback(Position position, double? vehicleHeading) {
    if (_finishLineStart == null || _finishLineEnd == null) return false;

    final finishCenter = LatLng(
      (_finishLineStart!.latitude + _finishLineEnd!.latitude) / 2,
      (_finishLineStart!.longitude + _finishLineEnd!.longitude) / 2,
    );

    final distance = _distanceBetween(
      LatLng(position.latitude, position.longitude),
      finishCenter,
    );

    // Geofence: 20m dal centro
    if (distance > 20.0) {
      _fallbackLastDistance = distance;
      return false;
    }

    // Tempo minimo tra attraversamenti
    if (_lastFallbackCrossing != null) {
      final timeSinceLastLap = DateTime.now().difference(_lastFallbackCrossing!);
      if (timeSinceLastLap.inSeconds < 25) return false;
    }

    // Verifica heading se disponibile
    if (vehicleHeading != null) {
      final finishHeading = _calculateHeading(_finishLineStart!, _finishLineEnd!);
      final normalHeading = (finishHeading + 90) % 360;

      final diff = LapDetectionMicroSector.headingDifference(
        normalHeading,
        vehicleHeading,
      ).abs();

      if (diff > 45) return false;
    }

    // Verifica di essere entrato nel geofence dall'esterno
    if (_fallbackLastDistance > 20.0) {
      _lastFallbackCrossing = DateTime.now();
      _fallbackLastDistance = distance;
      return true;
    }

    _fallbackLastDistance = distance;
    return false;
  }

  /// Verifica completamento primo giro in modalità veloce
  bool _checkFirstLapCompletionFallback(Position position) {
    if (!_isRecordingFirstLap || _firstLapRecording.length < 30) return false;

    // Tempo minimo: 30 secondi
    if (_firstLapStartTime != null) {
      final elapsed = DateTime.now().difference(_firstLapStartTime!);
      if (elapsed.inSeconds < 30) return false;
    }

    // Distanza minima: 300 metri
    double totalDistance = 0.0;
    for (int i = 1; i < _firstLapRecording.length; i++) {
      totalDistance += _distanceBetween(
        LatLng(_firstLapRecording[i - 1].latitude, _firstLapRecording[i - 1].longitude),
        LatLng(_firstLapRecording[i].latitude, _firstLapRecording[i].longitude),
      );
    }

    if (totalDistance < 300) return false;

    // Verifica ritorno vicino allo start
    final finishCenter = LatLng(
      (_finishLineStart!.latitude + _finishLineEnd!.latitude) / 2,
      (_finishLineStart!.longitude + _finishLineEnd!.longitude) / 2,
    );

    final distanceFromStart = _distanceBetween(
      LatLng(position.latitude, position.longitude),
      finishCenter,
    );

    return distanceFromStart < 25.0;
  }

  // ============================================================
  // RILEVAMENTO FREQUENZA GPS
  // ============================================================

  void _updateGpsTimestamps(DateTime timestamp) {
    _recentGpsTimestamps.add(timestamp);
    if (_recentGpsTimestamps.length > _gpsHistorySize) {
      _recentGpsTimestamps.removeAt(0);
    }
  }

  /// Stima la frequenza GPS corrente (Hz) basata sugli ultimi timestamp
  double _estimateGpsFrequency() {
    if (_recentGpsTimestamps.length < 3) return 1.0; // Default 1Hz

    final intervals = <int>[];
    for (int i = 1; i < _recentGpsTimestamps.length; i++) {
      final interval = _recentGpsTimestamps[i]
          .difference(_recentGpsTimestamps[i - 1])
          .inMilliseconds;
      if (interval > 0 && interval < 5000) {
        intervals.add(interval);
      }
    }

    if (intervals.isEmpty) return 1.0;

    final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    final frequency = 1000.0 / avgInterval;

    return frequency;
  }

  /// Calcola la dimensione della finestra di ricerca in base alla frequenza GPS
  int _calculateSearchWindow(double frequency) {
    if (frequency >= 15.0) {
      // BLE GPS (15-20Hz)
      return 100; // +100 settori
    } else if (frequency >= 5.0) {
      // GPS intermedio
      return 150;
    } else {
      // GPS cellulare (1Hz)
      return 200; // +200 settori
    }
  }

  // ============================================================
  // UTILITY
  // ============================================================

  /// Calcola distanza tra due punti in metri
  double _distanceBetween(LatLng p1, LatLng p2) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, p1, p2);
  }

  /// Calcola heading (direzione) tra due punti (0-360 gradi)
  double _calculateHeading(LatLng from, LatLng to) {
    final dLon = (to.longitude - from.longitude) * math.pi / 180.0;
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x) * 180.0 / math.pi;
    return (bearing + 360.0) % 360.0;
  }

  // ============================================================
  // GETTERS
  // ============================================================

  /// Numero totale di microsettori
  int get microSectorsCount => _microSectors?.length ?? 0;

  /// Indice del microsettore corrente
  int get currentSectorIndex => _currentSectorIndex;

  /// Percentuale del giro completato (0.0 - 1.0)
  double get lapProgress {
    if (_microSectors == null || _microSectors!.isEmpty) return 0.0;
    return (_currentSectorIndex / _microSectors!.length).clamp(0.0, 1.0);
  }

  /// Frequenza GPS stimata corrente
  double get estimatedGpsFrequency => _estimateGpsFrequency();

  /// Se sta registrando il primo giro
  bool get isRecordingFirstLap => _isRecordingFirstLap;

  /// Microsettori (per debug/visualizzazione)
  List<LapDetectionMicroSector>? get microSectors => _microSectors;
}
