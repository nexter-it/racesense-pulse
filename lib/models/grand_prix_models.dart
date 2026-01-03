class GrandPrixLobby {
  final String code;
  final String hostId;
  final String? trackId;
  final String? trackName;
  final String status; // waiting, running, finished
  final int createdAt;
  final int? startedAt;
  final int? finishedAt;
  final Map<String, GrandPrixParticipant> participants;

  GrandPrixLobby({
    required this.code,
    required this.hostId,
    this.trackId,
    this.trackName,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    required this.participants,
  });

  factory GrandPrixLobby.fromMap(String code, Map<dynamic, dynamic> map) {
    final participants = <String, GrandPrixParticipant>{};

    final participantsRaw = map['participants'];
    if (participantsRaw is Map) {
      participantsRaw.forEach((key, value) {
        if (value is Map) {
          participants[key.toString()] = GrandPrixParticipant.fromMap(
            key.toString(),
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    // Helper per convertire timestamp (può essere int o Map con .sv)
    int? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    return GrandPrixLobby(
      code: code,
      hostId: map['hostId']?.toString() ?? '',
      trackId: map['trackId']?.toString(),
      trackName: map['trackName']?.toString(),
      status: map['status']?.toString() ?? 'waiting',
      createdAt: parseTimestamp(map['createdAt']) ?? 0,
      startedAt: parseTimestamp(map['startedAt']),
      finishedAt: parseTimestamp(map['finishedAt']),
      participants: participants,
    );
  }
}

class GrandPrixParticipant {
  final String userId;
  final String username;
  final int joinedAt;
  final bool connected;

  GrandPrixParticipant({
    required this.userId,
    required this.username,
    required this.joinedAt,
    required this.connected,
  });

  factory GrandPrixParticipant.fromMap(String userId, Map<String, dynamic> map) {
    // Helper per convertire timestamp
    int parseTimestamp(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return GrandPrixParticipant(
      userId: userId,
      username: map['username']?.toString() ?? 'Unknown',
      joinedAt: parseTimestamp(map['joinedAt']),
      connected: map['connected'] == true,
    );
  }
}

class GrandPrixLiveData {
  final String userId;
  final String? username; // Username del pilota
  final int currentLap;
  final List<double> lapTimes;
  final double? bestLap;
  final int totalLaps;
  final double maxSpeed;
  final double maxGForce;
  final bool isFormationLap;
  final int lastUpdate;

  GrandPrixLiveData({
    required this.userId,
    this.username,
    required this.currentLap,
    required this.lapTimes,
    this.bestLap,
    required this.totalLaps,
    required this.maxSpeed,
    required this.maxGForce,
    required this.isFormationLap,
    required this.lastUpdate,
  });

  factory GrandPrixLiveData.fromMap(String userId, Map<dynamic, dynamic> map) {
    // Debug: stampa i dati raw ricevuti
    print('🔍 GrandPrixLiveData.fromMap per $userId: $map');

    // Parsing robusto di lapTimes
    // NOTA: Firebase può restituire sia List che Map (quando array ha chiavi sparse)
    final List<double> lapTimes = [];
    final lapTimesRaw = map['lapTimes'];
    if (lapTimesRaw is List) {
      for (final e in lapTimesRaw) {
        if (e is num) {
          // lapTimes salvati in millisecondi, convertiamo in secondi
          lapTimes.add(e.toDouble() / 1000.0);
        }
      }
    } else if (lapTimesRaw is Map) {
      // Firebase converte array in Map con chiavi numeriche (0, 1, 2...)
      // Ordiniamo per chiave e estraiamo i valori
      final sortedKeys = lapTimesRaw.keys.toList()
        ..sort((a, b) => int.parse(a.toString()).compareTo(int.parse(b.toString())));
      for (final key in sortedKeys) {
        final value = lapTimesRaw[key];
        if (value is num) {
          lapTimes.add(value.toDouble() / 1000.0);
        }
      }
    }
    print('🔍 lapTimes parsati: $lapTimes (raw type: ${lapTimesRaw.runtimeType})');

    // bestLap viene salvato in millisecondi, convertiamo in secondi
    double? bestLapSeconds;
    final bestLapRaw = map['bestLap'];
    if (bestLapRaw is num) {
      bestLapSeconds = bestLapRaw.toDouble() / 1000.0;
    }

    // Helper per parsing numeri
    int parseIntSafe(dynamic value, int defaultValue) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return defaultValue;
    }

    double parseDoubleSafe(dynamic value, double defaultValue) {
      if (value is num) return value.toDouble();
      return defaultValue;
    }

    final parsedUsername = map['username']?.toString();
    final parsedTotalLaps = parseIntSafe(map['totalLaps'], 0);
    print('🔍 username: $parsedUsername, totalLaps: $parsedTotalLaps, bestLap: $bestLapSeconds');

    return GrandPrixLiveData(
      userId: userId,
      username: parsedUsername,
      currentLap: parseIntSafe(map['currentLap'], 0),
      lapTimes: lapTimes,
      bestLap: bestLapSeconds,
      totalLaps: parsedTotalLaps,
      maxSpeed: parseDoubleSafe(map['maxSpeed'], 0.0),
      maxGForce: parseDoubleSafe(map['maxGForce'], 0.0),
      isFormationLap: map['isFormationLap'] == true,
      lastUpdate: parseIntSafe(map['lastUpdate'], 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'currentLap': currentLap,
      'lapTimes': lapTimes,
      'bestLap': bestLap,
      'totalLaps': totalLaps,
      'maxSpeed': maxSpeed,
      'maxGForce': maxGForce,
      'isFormationLap': isFormationLap,
    };
  }
}

class GrandPrixStatistics {
  final String userId;
  final String username;
  final int totalLaps;
  final double? bestLap;
  final double? slowestLap;
  final List<double> lapTimes;
  final double maxSpeed;
  final double maxGForce;
  final double consistency; // Standard deviation
  final double progression; // Difference between first and best lap

  GrandPrixStatistics({
    required this.userId,
    required this.username,
    required this.totalLaps,
    this.bestLap,
    this.slowestLap,
    required this.lapTimes,
    required this.maxSpeed,
    required this.maxGForce,
    required this.consistency,
    required this.progression,
  });

  factory GrandPrixStatistics.fromLiveData(
    String userId,
    String username,
    GrandPrixLiveData liveData,
  ) {
    final validLaps = liveData.lapTimes.where((t) => t > 0).toList();

    double? bestLap;
    double? slowestLap;
    double consistency = 0.0;
    double progression = 0.0;

    if (validLaps.isNotEmpty) {
      bestLap = validLaps.reduce((a, b) => a < b ? a : b);
      slowestLap = validLaps.reduce((a, b) => a > b ? a : b);

      // Calculate consistency (standard deviation)
      if (validLaps.length > 1) {
        final mean = validLaps.reduce((a, b) => a + b) / validLaps.length;
        final variance = validLaps.map((t) => (t - mean) * (t - mean)).reduce((a, b) => a + b) / validLaps.length;
        consistency = variance > 0 ? (1.0 / variance) : 0.0; // Higher is better
      }

      // Calculate progression (improvement from first to best lap)
      if (validLaps.length > 1) {
        final firstLap = validLaps.first;
        progression = firstLap - bestLap;
      }
    }

    return GrandPrixStatistics(
      userId: userId,
      username: username,
      totalLaps: liveData.totalLaps,
      bestLap: bestLap,
      slowestLap: slowestLap,
      lapTimes: validLaps,
      maxSpeed: liveData.maxSpeed,
      maxGForce: liveData.maxGForce,
      consistency: consistency,
      progression: progression,
    );
  }
}

class CloseBattle {
  final String driver1Username;
  final String driver2Username;
  final double driver1Time;
  final double driver2Time;
  final double difference;
  final int lapNumber;

  CloseBattle({
    required this.driver1Username,
    required this.driver2Username,
    required this.driver1Time,
    required this.driver2Time,
    required this.difference,
    required this.lapNumber,
  });
}
