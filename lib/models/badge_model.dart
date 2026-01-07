import 'package:cloud_firestore/cloud_firestore.dart';

/// Modello per un badge ottenuto da un utente partecipando a un evento
class BadgeModel {
  final String badgeId;
  final String userId;
  final String eventId;
  final String eventTitle;
  final DateTime eventDate;
  final DateTime checkedInAt;
  final String? eventLocationName;

  BadgeModel({
    required this.badgeId,
    required this.userId,
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.checkedInAt,
    this.eventLocationName,
  });

  /// Crea un BadgeModel da un documento Firestore
  factory BadgeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BadgeModel(
      badgeId: doc.id,
      userId: data['userId'] ?? '',
      eventId: data['eventId'] ?? '',
      eventTitle: data['eventTitle'] ?? '',
      eventDate: (data['eventDate'] as Timestamp).toDate(),
      checkedInAt: (data['checkedInAt'] as Timestamp).toDate(),
      eventLocationName: data['eventLocationName'],
    );
  }

  /// Converte il modello in una mappa per Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'eventDate': Timestamp.fromDate(eventDate),
      'checkedInAt': Timestamp.fromDate(checkedInAt),
      'eventLocationName': eventLocationName,
    };
  }

  /// Crea una copia del modello con campi aggiornati
  BadgeModel copyWith({
    String? badgeId,
    String? userId,
    String? eventId,
    String? eventTitle,
    DateTime? eventDate,
    DateTime? checkedInAt,
    String? eventLocationName,
  }) {
    return BadgeModel(
      badgeId: badgeId ?? this.badgeId,
      userId: userId ?? this.userId,
      eventId: eventId ?? this.eventId,
      eventTitle: eventTitle ?? this.eventTitle,
      eventDate: eventDate ?? this.eventDate,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      eventLocationName: eventLocationName ?? this.eventLocationName,
    );
  }

  /// Genera un nome abbreviato per il badge (prime 2-3 lettere del titolo)
  String get abbreviation {
    final words = eventTitle.split(' ');
    if (words.isEmpty) return 'EV';
    if (words.length == 1) {
      return words[0].substring(0, words[0].length > 2 ? 3 : words[0].length).toUpperCase();
    }
    // Prendi le iniziali delle prime 2-3 parole
    return words.take(3).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
  }

  /// Anno dell'evento per raggruppamento
  int get year => eventDate.year;
}
