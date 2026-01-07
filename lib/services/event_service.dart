import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/event_model.dart';
import '../models/badge_model.dart';

export '../models/event_model.dart' show EventType;

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Verifica se un utente è verificato per creare eventi
  Future<bool> isUserVerifiedCreator(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      return data?['verifiedCreatorEvents'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Crea un nuovo evento
  Future<String> createEvent({
    required String creatorId,
    required String creatorName,
    String? creatorProfileImage,
    required String title,
    required String description,
    required DateTime eventDateTime,
    required double latitude,
    required double longitude,
    String? locationName,
    double checkInRadiusMeters = 100.0,
    String? eventImageUrl,
    EventType eventType = EventType.other,
    int? maxParticipants,
    int? eventDurationMinutes,
    List<String> requirements = const [],
    String? contactInfo,
    String? websiteUrl,
    double? entryFee,
    String? officialCircuitId,
    String? officialCircuitName,
  }) async {
    // Verifica che l'utente sia verificato
    final isVerified = await isUserVerifiedCreator(creatorId);
    if (!isVerified) {
      throw Exception('Non sei autorizzato a creare eventi');
    }

    final eventRef = _firestore.collection('events').doc();
    final event = EventModel(
      eventId: eventRef.id,
      creatorId: creatorId,
      creatorName: creatorName,
      creatorProfileImage: creatorProfileImage,
      title: title,
      description: description,
      eventDateTime: eventDateTime,
      location: GeoPoint(latitude, longitude),
      locationName: locationName,
      checkInRadiusMeters: checkInRadiusMeters,
      createdAt: DateTime.now(),
      registeredUserIds: [],
      checkedInUserIds: [],
      isActive: true,
      eventImageUrl: eventImageUrl,
      eventType: eventType,
      maxParticipants: maxParticipants,
      eventDurationMinutes: eventDurationMinutes,
      requirements: requirements,
      contactInfo: contactInfo,
      websiteUrl: websiteUrl,
      entryFee: entryFee,
      officialCircuitId: officialCircuitId,
      officialCircuitName: officialCircuitName,
    );

    await eventRef.set(event.toFirestore());
    return eventRef.id;
  }

  /// Ottieni tutti gli eventi attivi (ordinati per data)
  Stream<List<EventModel>> getActiveEvents() {
    return _firestore
        .collection('events')
        .where('isActive', isEqualTo: true)
        .orderBy('eventDateTime', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList());
  }

  /// Ottieni eventi futuri
  Stream<List<EventModel>> getFutureEvents() {
    return _firestore
        .collection('events')
        .where('isActive', isEqualTo: true)
        .where('eventDateTime', isGreaterThan: Timestamp.now())
        .orderBy('eventDateTime', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList());
  }

  /// Ottieni eventi passati
  Stream<List<EventModel>> getPastEvents() {
    return _firestore
        .collection('events')
        .where('isActive', isEqualTo: true)
        .where('eventDateTime', isLessThan: Timestamp.now())
        .orderBy('eventDateTime', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList());
  }

  /// Ottieni un evento specifico
  Future<EventModel?> getEvent(String eventId) async {
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return null;
      return EventModel.fromFirestore(doc);
    } catch (e) {
      return null;
    }
  }

  /// Ottieni uno stream in tempo reale per un evento specifico
  Stream<EventModel?> getEventStream(String eventId) {
    return _firestore
        .collection('events')
        .doc(eventId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return EventModel.fromFirestore(doc);
    });
  }

  /// Iscriviti a un evento
  Future<void> registerToEvent(String eventId, String userId) async {
    await _firestore.collection('events').doc(eventId).update({
      'registeredUserIds': FieldValue.arrayUnion([userId]),
    });
  }

  /// Cancella iscrizione a un evento
  Future<void> unregisterFromEvent(String eventId, String userId) async {
    await _firestore.collection('events').doc(eventId).update({
      'registeredUserIds': FieldValue.arrayRemove([userId]),
    });
  }

  /// Controlla se un utente è iscritto a un evento
  Future<bool> isUserRegistered(String eventId, String userId) async {
    final event = await getEvent(eventId);
    return event?.registeredUserIds.contains(userId) ?? false;
  }

  /// Controlla se un utente ha già fatto check-in
  Future<bool> hasUserCheckedIn(String eventId, String userId) async {
    final event = await getEvent(eventId);
    return event?.checkedInUserIds.contains(userId) ?? false;
  }

  /// Calcola la distanza tra due coordinate in metri
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Verifica se l'utente è nel raggio dell'evento e fa check-in
  Future<BadgeModel?> checkInToEvent({
    required String eventId,
    required String userId,
    required double userLatitude,
    required double userLongitude,
  }) async {
    // Ottieni l'evento
    final event = await getEvent(eventId);
    if (event == null) {
      throw Exception('Evento non trovato');
    }

    // Verifica che l'utente sia iscritto
    if (!event.registeredUserIds.contains(userId)) {
      throw Exception('Devi essere iscritto all\'evento per fare check-in');
    }

    // Verifica che l'utente non abbia già fatto check-in
    if (event.checkedInUserIds.contains(userId)) {
      throw Exception('Hai già fatto check-in per questo evento');
    }

    // Verifica che l'evento sia in corso (entro una finestra temporale)
    if (!event.isOngoing) {
      throw Exception('Il check-in è disponibile solo durante l\'evento');
    }

    // Calcola la distanza
    final distance = _calculateDistance(
      userLatitude,
      userLongitude,
      event.location.latitude,
      event.location.longitude,
    );

    // Verifica che l'utente sia nel raggio
    if (distance > event.checkInRadiusMeters) {
      throw Exception(
          'Sei troppo lontano dall\'evento (distanza: ${distance.toInt()}m, richiesti: ${event.checkInRadiusMeters.toInt()}m)');
    }

    // Aggiungi l'utente agli utenti che hanno fatto check-in
    await _firestore.collection('events').doc(eventId).update({
      'checkedInUserIds': FieldValue.arrayUnion([userId]),
    });

    // Crea il badge
    final badgeRef = _firestore.collection('badges').doc();
    final badge = BadgeModel(
      badgeId: badgeRef.id,
      userId: userId,
      eventId: eventId,
      eventTitle: event.title,
      eventDate: event.eventDateTime,
      checkedInAt: DateTime.now(),
      eventLocationName: event.locationName,
    );

    await badgeRef.set(badge.toFirestore());

    return badge;
  }

  /// Ottieni tutti i badge di un utente
  Stream<List<BadgeModel>> getUserBadges(String userId) {
    return _firestore
        .collection('badges')
        .where('userId', isEqualTo: userId)
        .orderBy('eventDate', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => BadgeModel.fromFirestore(doc)).toList());
  }

  /// Conta i badge di un utente
  Future<int> getUserBadgeCount(String userId) async {
    final snapshot = await _firestore
        .collection('badges')
        .where('userId', isEqualTo: userId)
        .get();
    return snapshot.docs.length;
  }

  /// Cerca eventi per titolo
  Stream<List<EventModel>> searchEvents(String query) {
    final lowerQuery = query.toLowerCase();
    return _firestore
        .collection('events')
        .where('isActive', isEqualTo: true)
        .orderBy('eventDateTime', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EventModel.fromFirestore(doc))
            .where((event) =>
                event.title.toLowerCase().contains(lowerQuery) ||
                (event.description.toLowerCase().contains(lowerQuery)) ||
                (event.locationName?.toLowerCase().contains(lowerQuery) ?? false))
            .toList());
  }

  /// Aggiorna un evento esistente (solo per il creatore)
  Future<void> updateEvent({
    required String eventId,
    required String userId,
    String? title,
    String? description,
    DateTime? eventDateTime,
    double? latitude,
    double? longitude,
    String? locationName,
    String? eventImageUrl,
    String? officialCircuitId,
    String? officialCircuitName,
    double? entryFee,
    String? websiteUrl,
    int? maxParticipants,
    int? eventDurationMinutes,
    List<String>? requirements,
    String? contactInfo,
  }) async {
    final event = await getEvent(eventId);
    if (event == null) {
      throw Exception('Evento non trovato');
    }
    if (event.creatorId != userId) {
      throw Exception('Solo il creatore può modificare l\'evento');
    }

    final updates = <String, dynamic>{};

    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (eventDateTime != null) updates['eventDateTime'] = Timestamp.fromDate(eventDateTime);
    if (latitude != null && longitude != null) {
      updates['location'] = GeoPoint(latitude, longitude);
    }
    if (locationName != null) updates['locationName'] = locationName;
    if (eventImageUrl != null) updates['eventImageUrl'] = eventImageUrl;
    if (officialCircuitId != null) updates['officialCircuitId'] = officialCircuitId;
    if (officialCircuitName != null) updates['officialCircuitName'] = officialCircuitName;
    if (entryFee != null) updates['entryFee'] = entryFee;
    if (websiteUrl != null) updates['websiteUrl'] = websiteUrl;
    if (maxParticipants != null) updates['maxParticipants'] = maxParticipants;
    if (eventDurationMinutes != null) updates['eventDurationMinutes'] = eventDurationMinutes;
    if (requirements != null) updates['requirements'] = requirements;
    if (contactInfo != null) updates['contactInfo'] = contactInfo;

    if (updates.isEmpty) {
      return; // Nessuna modifica da applicare
    }

    await _firestore.collection('events').doc(eventId).update(updates);
  }

  /// Elimina un evento (solo per il creatore)
  Future<void> deleteEvent(String eventId, String userId) async {
    final event = await getEvent(eventId);
    if (event == null) {
      throw Exception('Evento non trovato');
    }
    if (event.creatorId != userId) {
      throw Exception('Solo il creatore può eliminare l\'evento');
    }

    await _firestore.collection('events').doc(eventId).update({
      'isActive': false,
    });
  }

  /// Ottieni gli eventi creati da un utente
  Stream<List<EventModel>> getUserCreatedEvents(String userId) {
    return _firestore
        .collection('events')
        .where('creatorId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('eventDateTime', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList());
  }

  /// Ottieni gli eventi a cui l'utente è iscritto
  Stream<List<EventModel>> getUserRegisteredEvents(String userId) {
    return _firestore
        .collection('events')
        .where('registeredUserIds', arrayContains: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('eventDateTime', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList());
  }
}
