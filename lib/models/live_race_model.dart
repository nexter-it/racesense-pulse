/// Modello per lo stato globale della gara live da Firebase Realtime Database
class LiveRaceModel {
  final String status; // "FORMATION LAP", "IN CORSO", "YELLOW FLAG", "RED FLAG", "FINITA"
  final String? circuitId;
  final String? circuitName;
  final int? totalLaps;
  final int? raceDurationMinutes;
  final int? remainingSeconds;
  final int? raceStartTime;
  final bool isFormationLap;
  final int? maxYellowFlagSpeed;
  final double? globalBestLap;
  final String? leaderMac;
  final int driversCount;
  final int? updatedAt;

  LiveRaceModel({
    required this.status,
    this.circuitId,
    this.circuitName,
    this.totalLaps,
    this.raceDurationMinutes,
    this.remainingSeconds,
    this.raceStartTime,
    this.isFormationLap = false,
    this.maxYellowFlagSpeed,
    this.globalBestLap,
    this.leaderMac,
    this.driversCount = 0,
    this.updatedAt,
  });

  factory LiveRaceModel.fromMap(Map<dynamic, dynamic> map) {
    return LiveRaceModel(
      status: map['status'] as String? ?? 'SCONOSCIUTO',
      circuitId: map['circuitId'] as String?,
      circuitName: map['circuitName'] as String?,
      totalLaps: map['totalLaps'] as int?,
      raceDurationMinutes: map['raceDurationMinutes'] as int?,
      remainingSeconds: map['remainingSeconds'] as int?,
      raceStartTime: map['raceStartTime'] as int?,
      isFormationLap: map['isFormationLap'] as bool? ?? false,
      maxYellowFlagSpeed: map['maxYellowFlagSpeed'] as int?,
      globalBestLap: (map['globalBestLap'] as num?)?.toDouble(),
      leaderMac: map['leaderMac'] as String?,
      driversCount: map['driversCount'] as int? ?? 0,
      updatedAt: map['updatedAt'] as int?,
    );
  }

  /// Formatta il tempo rimanente in MM:SS
  String get formattedRemainingTime {
    if (remainingSeconds == null) return '--:--';
    final mins = remainingSeconds! ~/ 60;
    final secs = remainingSeconds! % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Formatta il best lap globale
  String get formattedGlobalBestLap {
    if (globalBestLap == null) return '--:--.---';
    return _formatLapTime(globalBestLap!);
  }

  static String _formatLapTime(double seconds) {
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).toStringAsFixed(3);
    return '${mins.toString().padLeft(1, '0')}:${secs.padLeft(6, '0')}';
  }

  /// Verifica se c'è una bandiera gialla o rossa
  bool get isYellowFlag => status == 'YELLOW FLAG';
  bool get isRedFlag => status == 'RED FLAG';
  bool get isRaceActive => status == 'IN CORSO' || status == 'FORMATION LAP' || isYellowFlag;
  bool get isRaceFinished => status == 'FINITA';
}
