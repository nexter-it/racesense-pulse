/// Modello per i dati live di un pilota/driver da Firebase Realtime Database
class LiveDriverModel {
  // Identificazione
  final String mac;
  final String? pilotId;
  final String type; // "pilot" o "team"
  final String fullName;
  final String? tag; // abbreviazione 4 char tipo "ROSS"
  final String? team;
  final String? photoTeamUrl;
  final String? logoUrl;
  final FormulaInfo? formula;

  // Classifica
  final int position;
  final int? classPosition;
  final String gapToLeader; // "LEADER", "+0.45", "+2L"
  final String? classGapToLeader;

  // Giri
  final int lapCount;
  final double? lastLapTime;
  final double? bestLapTime;
  final double? currentLapTime;
  final List<double> lapTimes;

  // Settori
  final SectorTimes? sectorTimes;
  final SectorTimes? lastSectorTimes;

  // Penalita
  final PenaltyInfo penalty;

  // GPS e Telemetria
  final double? lat;
  final double? lon;
  final double? speedKmh;
  final GForceData? gforce;

  final int? updatedAt;

  LiveDriverModel({
    required this.mac,
    this.pilotId,
    this.type = 'pilot',
    required this.fullName,
    this.tag,
    this.team,
    this.photoTeamUrl,
    this.logoUrl,
    this.formula,
    this.position = 0,
    this.classPosition,
    this.gapToLeader = '',
    this.classGapToLeader,
    this.lapCount = 0,
    this.lastLapTime,
    this.bestLapTime,
    this.currentLapTime,
    this.lapTimes = const [],
    this.sectorTimes,
    this.lastSectorTimes,
    this.penalty = const PenaltyInfo(),
    this.lat,
    this.lon,
    this.speedKmh,
    this.gforce,
    this.updatedAt,
  });

  factory LiveDriverModel.fromMap(Map<dynamic, dynamic> map) {
    // Parse lap times array
    List<double> parsedLapTimes = [];
    if (map['lapTimes'] != null) {
      final lapTimesRaw = map['lapTimes'];
      if (lapTimesRaw is List) {
        parsedLapTimes = lapTimesRaw
            .whereType<num>()
            .map((e) => e.toDouble())
            .toList();
      }
    }

    return LiveDriverModel(
      mac: map['mac'] as String? ?? '',
      pilotId: map['pilotId'] as String?,
      type: map['type'] as String? ?? 'pilot',
      fullName: map['fullName'] as String? ?? 'Sconosciuto',
      tag: map['tag'] as String?,
      team: map['team'] as String?,
      photoTeamUrl: map['photoTeamUrl'] as String?,
      logoUrl: map['logoUrl'] as String?,
      formula: map['formula'] != null
          ? FormulaInfo.fromMap(map['formula'] as Map<dynamic, dynamic>)
          : null,
      position: map['position'] as int? ?? 0,
      classPosition: map['classPosition'] as int?,
      gapToLeader: map['gapToLeader'] as String? ?? '',
      classGapToLeader: map['classGapToLeader'] as String?,
      lapCount: map['lapCount'] as int? ?? 0,
      lastLapTime: (map['lastLapTime'] as num?)?.toDouble(),
      bestLapTime: (map['bestLapTime'] as num?)?.toDouble(),
      currentLapTime: (map['currentLapTime'] as num?)?.toDouble(),
      lapTimes: parsedLapTimes,
      sectorTimes: map['sectorTimes'] != null
          ? SectorTimes.fromMap(map['sectorTimes'] as Map<dynamic, dynamic>)
          : null,
      lastSectorTimes: map['lastSectorTimes'] != null
          ? SectorTimes.fromMap(map['lastSectorTimes'] as Map<dynamic, dynamic>)
          : null,
      penalty: map['penalty'] != null
          ? PenaltyInfo.fromMap(map['penalty'] as Map<dynamic, dynamic>)
          : const PenaltyInfo(),
      lat: (map['lat'] as num?)?.toDouble(),
      lon: (map['lon'] as num?)?.toDouble(),
      speedKmh: (map['speedKmh'] as num?)?.toDouble(),
      gforce: map['gforce'] != null
          ? GForceData.fromMap(map['gforce'] as Map<dynamic, dynamic>)
          : null,
      updatedAt: map['updatedAt'] as int?,
    );
  }

  /// Formatta il tempo dell'ultimo giro
  String get formattedLastLapTime {
    if (lastLapTime == null) return '--:--.---';
    return _formatLapTime(lastLapTime!);
  }

  /// Formatta il miglior tempo
  String get formattedBestLapTime {
    if (bestLapTime == null) return '--:--.---';
    return _formatLapTime(bestLapTime!);
  }

  /// Formatta il tempo del giro in corso
  String get formattedCurrentLapTime {
    if (currentLapTime == null) return '--:--.---';
    return _formatLapTime(currentLapTime!);
  }

  /// Formatta la velocita
  String get formattedSpeed {
    if (speedKmh == null) return '-- km/h';
    return '${speedKmh!.toInt()} km/h';
  }

  /// Verifica se il pilota e' il leader
  bool get isLeader => gapToLeader == 'LEADER' || position == 1;

  /// Verifica se ha penalita
  bool get hasPenalty => penalty.timeSec > 0 || penalty.warnings > 0;

  /// Verifica se e' squalificato
  bool get isDisqualified => penalty.dq;

  static String _formatLapTime(double seconds) {
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).toStringAsFixed(3);
    return '${mins.toString().padLeft(1, '0')}:${secs.padLeft(6, '0')}';
  }
}

/// Info sulla formula/classe del pilota
class FormulaInfo {
  final String? id;
  final String? label;

  const FormulaInfo({this.id, this.label});

  factory FormulaInfo.fromMap(Map<dynamic, dynamic> map) {
    return FormulaInfo(
      id: map['id'] as String?,
      label: map['label'] as String?,
    );
  }
}

/// Tempi dei settori
class SectorTimes {
  final double? s1;
  final double? s2;
  final double? s3;

  const SectorTimes({this.s1, this.s2, this.s3});

  factory SectorTimes.fromMap(Map<dynamic, dynamic> map) {
    return SectorTimes(
      s1: (map['S1'] as num?)?.toDouble(),
      s2: (map['S2'] as num?)?.toDouble(),
      s3: (map['S3'] as num?)?.toDouble(),
    );
  }

  String formatSector(double? time) {
    if (time == null) return '--.---';
    return time.toStringAsFixed(3);
  }
}

/// Dati penalita
class PenaltyInfo {
  final int timeSec;
  final int warnings;
  final bool dq;
  final String? summary;

  const PenaltyInfo({
    this.timeSec = 0,
    this.warnings = 0,
    this.dq = false,
    this.summary,
  });

  factory PenaltyInfo.fromMap(Map<dynamic, dynamic> map) {
    return PenaltyInfo(
      timeSec: map['timeSec'] as int? ?? 0,
      warnings: map['warnings'] as int? ?? 0,
      dq: map['dq'] as bool? ?? false,
      summary: map['summary'] as String?,
    );
  }

  bool get hasAny => timeSec > 0 || warnings > 0 || dq;
}

/// Dati G-Force
class GForceData {
  final double? lat;
  final double? long;
  final double? vert;
  final double? total;

  const GForceData({this.lat, this.long, this.vert, this.total});

  factory GForceData.fromMap(Map<dynamic, dynamic> map) {
    return GForceData(
      lat: (map['lat'] as num?)?.toDouble(),
      long: (map['long'] as num?)?.toDouble(),
      vert: (map['vert'] as num?)?.toDouble(),
      total: (map['total'] as num?)?.toDouble(),
    );
  }

  String get formattedTotal {
    if (total == null) return '-.--G';
    return '${total!.toStringAsFixed(2)}G';
  }
}
