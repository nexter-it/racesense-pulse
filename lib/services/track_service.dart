import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/track_definition.dart';

/// Servizio per gestire i circuiti tracciati su Firebase
/// Ottimizzato per scalabilità con query efficienti
class TrackService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Salva un nuovo circuito tracciato su Firebase
  ///
  /// Struttura ottimizzata:
  /// /tracks/{trackId}
  ///   - userId: owner del circuito
  ///   - name: nome circuito
  ///   - nameLower: nome lowercase per ricerche case-insensitive
  ///   - location: località
  ///   - isPublic: visibilità
  ///   - createdAt: timestamp creazione
  ///   - trackData: definizione completa del circuito (TrackDefinition serializzata)
  Future<String> saveTrack({
    required String userId,
    required TrackDefinition trackDefinition,
    required bool isPublic,
  }) async {
    try {
      final trackData = trackDefinition.toMap();

      final doc = await _firestore.collection('tracks').add({
        'userId': userId,
        'name': trackDefinition.name,
        'nameLower': trackDefinition.name.toLowerCase(),
        'location': trackDefinition.location,
        'isPublic': isPublic,
        'createdAt': FieldValue.serverTimestamp(),
        'trackData': trackData,
      });

      print('✓ Circuito salvato su Firebase: ${doc.id}');
      return doc.id;
    } catch (e) {
      print('❌ Errore salvataggio circuito: $e');
      rethrow;
    }
  }

  /// Aggiorna un circuito esistente
  Future<void> updateTrack({
    required String trackId,
    required TrackDefinition trackDefinition,
    bool? isPublic,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'name': trackDefinition.name,
        'nameLower': trackDefinition.name.toLowerCase(),
        'location': trackDefinition.location,
        'trackData': trackDefinition.toMap(),
      };

      if (isPublic != null) {
        updateData['isPublic'] = isPublic;
      }

      await _firestore.collection('tracks').doc(trackId).update(updateData);
      print('✓ Circuito aggiornato: $trackId');
    } catch (e) {
      print('❌ Errore aggiornamento circuito: $e');
      rethrow;
    }
  }

  /// Elimina un circuito
  Future<void> deleteTrack(String trackId) async {
    try {
      await _firestore.collection('tracks').doc(trackId).delete();
      print('✓ Circuito eliminato: $trackId');
    } catch (e) {
      print('❌ Errore eliminazione circuito: $e');
      rethrow;
    }
  }

  /// Ottieni tutti i circuiti di un utente
  Future<List<TrackWithMetadata>> getUserTracks(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('tracks')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => TrackWithMetadata.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Errore caricamento circuiti utente: $e');
      return [];
    }
  }

  /// Ottieni un singolo circuito per ID
  Future<TrackWithMetadata?> getTrackById(String trackId) async {
    try {
      final doc = await _firestore.collection('tracks').doc(trackId).get();

      if (!doc.exists) {
        return null;
      }

      return TrackWithMetadata.fromFirestore(doc);
    } catch (e) {
      print('❌ Errore caricamento circuito: $e');
      return null;
    }
  }

  /// Cerca circuiti pubblici per nome (case-insensitive)
  /// Ottimizzato con indice su nameLower
  Future<List<TrackWithMetadata>> searchPublicTracks(String query) async {
    try {
      if (query.isEmpty) {
        return [];
      }

      final lowerQuery = query.toLowerCase();

      // Query ottimizzata con range query per prefix matching
      final snapshot = await _firestore
          .collection('tracks')
          .where('isPublic', isEqualTo: true)
          .where('nameLower', isGreaterThanOrEqualTo: lowerQuery)
          .where('nameLower', isLessThan: lowerQuery + '\uf8ff')
          .limit(20)
          .get();

      return snapshot.docs
          .map((doc) => TrackWithMetadata.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Errore ricerca circuiti: $e');
      return [];
    }
  }

  /// Ottieni circuiti pubblici più recenti
  /// Utile per feed/esplorazione
  Future<List<TrackWithMetadata>> getRecentPublicTracks({int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('tracks')
          .where('isPublic', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => TrackWithMetadata.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Errore caricamento circuiti recenti: $e');
      return [];
    }
  }
}

/// Wrapper che contiene TrackDefinition + metadata Firebase
class TrackWithMetadata {
  final String trackId;
  final String userId;
  final bool isPublic;
  final DateTime createdAt;
  final TrackDefinition trackDefinition;

  TrackWithMetadata({
    required this.trackId,
    required this.userId,
    required this.isPublic,
    required this.createdAt,
    required this.trackDefinition,
  });

  factory TrackWithMetadata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final trackData = data['trackData'] as Map<String, dynamic>;

    return TrackWithMetadata(
      trackId: doc.id,
      userId: data['userId'] as String,
      isPublic: data['isPublic'] as bool,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      trackDefinition: TrackDefinition.fromMap(trackData),
    );
  }
}
