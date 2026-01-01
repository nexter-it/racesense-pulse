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
    final participantsMap = map['participants'] as Map<dynamic, dynamic>? ?? {};
    final participants = <String, GrandPrixParticipant>{};

    participantsMap.forEach((key, value) {
      participants[key.toString()] = GrandPrixParticipant.fromMap(
        key.toString(),
        Map<String, dynamic>.from(value as Map),
      );
    });

    return GrandPrixLobby(
      code: code,
      hostId: map['hostId']?.toString() ?? '',
      trackId: map['trackId']?.toString(),
      trackName: map['trackName']?.toString(),
      status: map['status']?.toString() ?? 'waiting',
      createdAt: map['createdAt'] as int? ?? 0,
      startedAt: map['startedAt'] as int?,
      finishedAt: map['finishedAt'] as int?,
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
    return GrandPrixParticipant(
      userId: userId,
      username: map['username']?.toString() ?? 'Unknown',
      joinedAt: map['joinedAt'] as int? ?? 0,
      connected: map['connected'] as bool? ?? false,
    );
  }
}

class GrandPrixLiveData {
  final String userId;
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
    final lapTimesList = map['lapTimes'] as List<dynamic>? ?? [];
    final lapTimes = lapTimesList.map((e) => (e as num).toDouble()).toList();

    return GrandPrixLiveData(
      userId: userId,
      currentLap: map['currentLap'] as int? ?? 0,
      lapTimes: lapTimes,
      bestLap: map['bestLap'] != null ? (map['bestLap'] as num).toDouble() : null,
      totalLaps: map['totalLaps'] as int? ?? 0,
      maxSpeed: (map['maxSpeed'] as num?)?.toDouble() ?? 0.0,
      maxGForce: (map['maxGForce'] as num?)?.toDouble() ?? 0.0,
      isFormationLap: map['isFormationLap'] as bool? ?? true,
      lastUpdate: map['lastUpdate'] as int? ?? 0,
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
