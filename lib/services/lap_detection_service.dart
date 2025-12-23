import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Servizio per lap detection in stile RaceChrono Pro
///
/// Sistema best-effort durante sessione live usando intersezione geometrica
/// con linea Start/Finish. Post-processing esatto tramite PostProcessingService.
class LapDetectionService {
  // Linea Start/Finish (unica fonte di verità)
  LatLng? _finishLineStart;
  LatLng? _finishLineEnd;

  // Tracking GPS e lap detection live
  final List<Position> _gpsHistory = [];
  DateTime? _currentLapStartTime;
  DateTime? _lastCrossingTime;
  int _lapCount = 0;

  // Formation lap: attende primo passaggio dalla linea del via
  bool _inFormationLap = true;
  bool _formationLapCrossed = false;

  // Callback per notifica giro completato
  Function(Duration lapTime)? onLapCompleted;

  // ============================================================
  // INIZIALIZZAZIONE
  // ============================================================

  /// Inizializza con linea Start/Finish da circuito pre-tracciato
  void initializeWithFinishLine(LatLng finishLineStart, LatLng finishLineEnd) {
    _finishLineStart = finishLineStart;
    _finishLineEnd = finishLineEnd;

    _gpsHistory.clear();
    _currentLapStartTime = null;
    _lastCrossingTime = null;
    _lapCount = 0;
    _inFormationLap = true;
    _formationLapCrossed = false;

    print('✓ Lap detection inizializzato con linea S/F: ${finishLineStart.latitude},${finishLineStart.longitude} → ${finishLineEnd.latitude},${finishLineEnd.longitude}');
  }

  /// Reset completo del servizio
  void reset() {
    _finishLineStart = null;
    _finishLineEnd = null;
    _gpsHistory.clear();
    _currentLapStartTime = null;
    _lastCrossingTime = null;
    _lapCount = 0;
    _inFormationLap = true;
    _formationLapCrossed = false;
  }

  // ============================================================
  // GETTERS - FORMATION LAP
  // ============================================================

  /// Indica se siamo in formation lap (in attesa del primo passaggio dalla linea)
  bool get inFormationLap => _inFormationLap;

  /// Indica se abbiamo già attraversato la linea durante il formation lap
  bool get formationLapCrossed => _formationLapCrossed;

  /// Numero di giri completati (escluso formation lap)
  int get lapCount => _lapCount;

  // ============================================================
  // TRACKING DURANTE LA SESSIONE LIVE
  // ============================================================

  /// Processa un nuovo punto GPS e rileva eventuali crossing con best-effort
  ///
  /// Returns: true se è stato rilevato un crossing della linea S/F
  ///
  /// Nota: questo è un rilevamento live best-effort. Il post-processing
  /// fornirà la "fonte di verità" finale con interpolazione temporale precisa.
  bool processGpsPoint(Position position, {double? vehicleHeading}) {
    // Aggiungi a history
    _gpsHistory.add(position);

    // ============================================================
    // FORMATION LAP: Attende primo passaggio dalla linea del via
    // ============================================================
    if (_inFormationLap) {
      final crossed = _checkFinishLineCrossing(position);
      if (crossed) {
        _formationLapCrossed = true;
        _inFormationLap = false;
        _currentLapStartTime = position.timestamp;
        _lastCrossingTime = position.timestamp;
        print('✓ Formation lap completato: inizia tracciamento giri');
      }
      return false; // Durante formation lap non contiamo giri
    }

    // Se abbiamo meno di 2 punti GPS, non possiamo rilevare segmenti
    if (_gpsHistory.length < 2) {
      return false;
    }

    // Prendi gli ultimi 2 punti per formare un segmento GPS
    final p1 = _gpsHistory[_gpsHistory.length - 2];
    final p2 = _gpsHistory[_gpsHistory.length - 1];

    // Verifica intersezione geometrica tra segmento GPS e linea S/F
    final crossed = _checkSegmentIntersection(p1, p2);

    if (crossed) {
      // Calcola tempo del lap (best-effort)
      if (_currentLapStartTime != null) {
        final lapTime = p2.timestamp!.difference(_currentLapStartTime!);

        // Validazione: lap minimo 20 secondi (evita false detection)
        if (lapTime.inSeconds >= 20) {
          _lapCount++;
          _currentLapStartTime = p2.timestamp;
          _lastCrossingTime = p2.timestamp;

          // Notifica callback
          if (onLapCompleted != null) {
            onLapCompleted!(lapTime);
          }

          print('✓ Lap #$_lapCount completato (live best-effort): ${lapTime.inSeconds}s');
          return true;
        }
      } else {
        // Primo crossing dopo formation lap
        _currentLapStartTime = p2.timestamp;
        _lastCrossingTime = p2.timestamp;
      }
    }

    return false;
  }

  /// Verifica intersezione tra segmento GPS [p1, p2] e linea S/F
  ///
  /// Algoritmo geometrico semplificato per live detection (best-effort).
  /// Il post-processing userà algoritmo più preciso con interpolazione temporale.
  bool _checkSegmentIntersection(Position p1, Position p2) {
    if (_finishLineStart == null || _finishLineEnd == null) return false;

    // Converti in LatLng
    final seg1Start = LatLng(p1.latitude, p1.longitude);
    final seg1End = LatLng(p2.latitude, p2.longitude);

    // Calcola intersezione
    final intersection = _computeLineIntersection(
      seg1Start,
      seg1End,
      _finishLineStart!,
      _finishLineEnd!,
    );

    return intersection != null;
  }

  /// Verifica se abbiamo attraversato la linea di start/finish (fallback per formation lap)
  ///
  /// Usa geofence semplice come fallback per detection rapida durante formation lap
  bool _checkFinishLineCrossing(Position position) {
    if (_finishLineStart == null || _finishLineEnd == null) return false;

    // Calcola centro della linea
    final finishCenter = LatLng(
      (_finishLineStart!.latitude + _finishLineEnd!.latitude) / 2,
      (_finishLineStart!.longitude + _finishLineEnd!.longitude) / 2,
    );

    // Calcola distanza dal centro
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      finishCenter.latitude,
      finishCenter.longitude,
    );

    // Geofence: 30m dal centro (generoso per formation lap)
    if (distance > 30.0) {
      return false;
    }

    // Calcola larghezza della linea
    final lineWidth = Geolocator.distanceBetween(
      _finishLineStart!.latitude,
      _finishLineStart!.longitude,
      _finishLineEnd!.latitude,
      _finishLineEnd!.longitude,
    );

    // Verifica se siamo dentro la larghezza della linea (±10m di tolleranza)
    if (distance <= (lineWidth / 2 + 10.0)) {
      return true;
    }

    return false;
  }

  // ============================================================
  // ALGORITMI GEOMETRICI (RaceChrono Style)
  // ============================================================

  /// Calcola intersezione tra due segmenti (algoritmo line-line intersection)
  ///
  /// Returns: punto di intersezione se esiste e giace sui segmenti, null altrimenti
  LatLng? _computeLineIntersection(
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

  // ============================================================
  // GETTERS PER UI
  // ============================================================

  /// Tempo corrente del lap in corso
  Duration? get currentLapTime {
    if (_currentLapStartTime == null || _inFormationLap) return null;
    return DateTime.now().difference(_currentLapStartTime!);
  }

  /// Timestamp dell'ultimo crossing rilevato
  DateTime? get lastCrossingTime => _lastCrossingTime;

  /// Storia GPS completa (per post-processing)
  List<Position> get gpsHistory => List.unmodifiable(_gpsHistory);

  /// Linea S/F corrente (start point)
  LatLng? get finishLineStart => _finishLineStart;

  /// Linea S/F corrente (end point)
  LatLng? get finishLineEnd => _finishLineEnd;
}
