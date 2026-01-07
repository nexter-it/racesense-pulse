import 'package:cloud_firestore/cloud_firestore.dart';

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
}
