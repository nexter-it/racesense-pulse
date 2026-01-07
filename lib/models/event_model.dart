import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipi di evento disponibili
enum EventType {
  trackday,
  race,
  test,
  course,
  meeting,
  other;

  String get displayName {
    switch (this) {
      case EventType.trackday:
        return 'Trackday';
      case EventType.race:
        return 'Gara';
      case EventType.test:
        return 'Test';
      case EventType.course:
        return 'Corso';
      case EventType.meeting:
        return 'Meeting';
      case EventType.other:
        return 'Altro';
    }
  }

  String get emoji {
    switch (this) {
      case EventType.trackday:
        return '🏁';
      case EventType.race:
        return '🏆';
      case EventType.test:
        return '⚙️';
      case EventType.course:
        return '📚';
      case EventType.meeting:
        return '🤝';
      case EventType.other:
        return '📅';
    }
  }

  static EventType fromString(String? value) {
    if (value == null) return EventType.other;
    try {
      return EventType.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return EventType.other;
    }
  }
}

/// Modello per un evento creato da un utente verificato
class EventModel {
  final String eventId;
  final String creatorId;
  final String creatorName;
  final String? creatorProfileImage;
  final String title;
  final String description;
  final DateTime eventDateTime;
  final GeoPoint location;
  final String? locationName;
  final double checkInRadiusMeters;
  final DateTime createdAt;
  final List<String> registeredUserIds;
  final List<String> checkedInUserIds;
  final bool isActive;
  final String? eventImageUrl;

  // Nuovi campi per esperienza pilota migliorata
  final EventType eventType;
  final int? maxParticipants;
  final int? eventDurationMinutes;
  final List<String> requirements;
  final String? contactInfo;
  final String? websiteUrl;
  final double? entryFee;
  final String? officialCircuitId; // ID del circuito ufficiale (se presente)
  final String? officialCircuitName; // Nome del circuito ufficiale

  EventModel({
    required this.eventId,
    required this.creatorId,
    required this.creatorName,
    this.creatorProfileImage,
    required this.title,
    required this.description,
    required this.eventDateTime,
    required this.location,
    this.locationName,
    this.checkInRadiusMeters = 100.0,
    required this.createdAt,
    this.registeredUserIds = const [],
    this.checkedInUserIds = const [],
    this.isActive = true,
    this.eventImageUrl,
    this.eventType = EventType.other,
    this.maxParticipants,
    this.eventDurationMinutes,
    this.requirements = const [],
    this.contactInfo,
    this.websiteUrl,
    this.entryFee,
    this.officialCircuitId,
    this.officialCircuitName,
  });

  /// Crea un EventModel da un documento Firestore
  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventModel(
      eventId: doc.id,
      creatorId: data['creatorId'] ?? '',
      creatorName: data['creatorName'] ?? '',
      creatorProfileImage: data['creatorProfileImage'],
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      eventDateTime: (data['eventDateTime'] as Timestamp).toDate(),
      location: data['location'] as GeoPoint,
      locationName: data['locationName'],
      checkInRadiusMeters: (data['checkInRadiusMeters'] ?? 100.0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      registeredUserIds: List<String>.from(data['registeredUserIds'] ?? []),
      checkedInUserIds: List<String>.from(data['checkedInUserIds'] ?? []),
      isActive: data['isActive'] ?? true,
      eventImageUrl: data['eventImageUrl'],
      eventType: EventType.fromString(data['eventType']),
      maxParticipants: data['maxParticipants'],
      eventDurationMinutes: data['eventDurationMinutes'],
      requirements: List<String>.from(data['requirements'] ?? []),
      contactInfo: data['contactInfo'],
      websiteUrl: data['websiteUrl'],
      entryFee: data['entryFee']?.toDouble(),
      officialCircuitId: data['officialCircuitId'],
      officialCircuitName: data['officialCircuitName'],
    );
  }

  /// Converte il modello in una mappa per Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'creatorId': creatorId,
      'creatorName': creatorName,
      'creatorProfileImage': creatorProfileImage,
      'title': title,
      'description': description,
      'eventDateTime': Timestamp.fromDate(eventDateTime),
      'location': location,
      'locationName': locationName,
      'checkInRadiusMeters': checkInRadiusMeters,
      'createdAt': Timestamp.fromDate(createdAt),
      'registeredUserIds': registeredUserIds,
      'checkedInUserIds': checkedInUserIds,
      'isActive': isActive,
      'eventImageUrl': eventImageUrl,
      'eventType': eventType.name,
      'maxParticipants': maxParticipants,
      'eventDurationMinutes': eventDurationMinutes,
      'requirements': requirements,
      'contactInfo': contactInfo,
      'websiteUrl': websiteUrl,
      'entryFee': entryFee,
      'officialCircuitId': officialCircuitId,
      'officialCircuitName': officialCircuitName,
    };
  }

  /// Crea una copia del modello con campi aggiornati
  EventModel copyWith({
    String? eventId,
    String? creatorId,
    String? creatorName,
    String? creatorProfileImage,
    String? title,
    String? description,
    DateTime? eventDateTime,
    GeoPoint? location,
    String? locationName,
    double? checkInRadiusMeters,
    DateTime? createdAt,
    List<String>? registeredUserIds,
    List<String>? checkedInUserIds,
    bool? isActive,
    String? eventImageUrl,
    EventType? eventType,
    int? maxParticipants,
    int? eventDurationMinutes,
    List<String>? requirements,
    String? contactInfo,
    String? websiteUrl,
    double? entryFee,
    String? officialCircuitId,
    String? officialCircuitName,
  }) {
    return EventModel(
      eventId: eventId ?? this.eventId,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorProfileImage: creatorProfileImage ?? this.creatorProfileImage,
      title: title ?? this.title,
      description: description ?? this.description,
      eventDateTime: eventDateTime ?? this.eventDateTime,
      location: location ?? this.location,
      locationName: locationName ?? this.locationName,
      checkInRadiusMeters: checkInRadiusMeters ?? this.checkInRadiusMeters,
      createdAt: createdAt ?? this.createdAt,
      registeredUserIds: registeredUserIds ?? this.registeredUserIds,
      checkedInUserIds: checkedInUserIds ?? this.checkedInUserIds,
      isActive: isActive ?? this.isActive,
      eventImageUrl: eventImageUrl ?? this.eventImageUrl,
      eventType: eventType ?? this.eventType,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      eventDurationMinutes: eventDurationMinutes ?? this.eventDurationMinutes,
      requirements: requirements ?? this.requirements,
      contactInfo: contactInfo ?? this.contactInfo,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      entryFee: entryFee ?? this.entryFee,
      officialCircuitId: officialCircuitId ?? this.officialCircuitId,
      officialCircuitName: officialCircuitName ?? this.officialCircuitName,
    );
  }

  /// Controlla se l'evento è già passato
  bool get isPast => DateTime.now().isAfter(eventDateTime);

  /// Controlla se l'evento è in corso (entro 2 ore dall'orario di inizio)
  bool get isOngoing {
    final now = DateTime.now();
    final diff = now.difference(eventDateTime);
    return diff.inMinutes >= -30 && diff.inHours < 2;
  }

  /// Controlla se l'evento è futuro
  bool get isFuture => DateTime.now().isBefore(eventDateTime);

  /// Numero di partecipanti registrati
  int get registeredCount => registeredUserIds.length;

  /// Numero di partecipanti che hanno fatto check-in
  int get checkedInCount => checkedInUserIds.length;

  /// Controlla se l'evento ha raggiunto il limite di partecipanti
  bool get isFull => maxParticipants != null && registeredCount >= maxParticipants!;

  /// Posti disponibili
  int? get availableSpots => maxParticipants != null ? maxParticipants! - registeredCount : null;

  /// Durata formattata
  String get formattedDuration {
    if (eventDurationMinutes == null) return '';
    final hours = eventDurationMinutes! ~/ 60;
    final minutes = eventDurationMinutes! % 60;
    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}min';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}min';
    }
  }

  /// Controlla se ha requisiti
  bool get hasRequirements => requirements.isNotEmpty;

  /// Controlla se ha informazioni di contatto
  bool get hasContactInfo => contactInfo != null && contactInfo!.isNotEmpty;

  /// Controlla se ha un sito web
  bool get hasWebsite => websiteUrl != null && websiteUrl!.isNotEmpty;

  /// Controlla se ha un costo di iscrizione
  bool get hasEntryFee => entryFee != null && entryFee! > 0;

  /// Formatta il costo di iscrizione
  String get formattedEntryFee => entryFee != null ? '€${entryFee!.toStringAsFixed(0)}' : 'Gratuito';

  /// Controlla se ha un circuito ufficiale collegato
  bool get hasOfficialCircuit => officialCircuitId != null && officialCircuitId!.isNotEmpty;
}
