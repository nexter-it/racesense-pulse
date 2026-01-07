import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servizio SEMPLIFICATO per gestire le lobby Gran Prix.
/// Approccio: meno controlli, più stabilità.
class GrandPrixService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _basePath => 'grand_prix_lobbies';

  // ============================================================
  // UTILITY
  // ============================================================

  String? get currentUserId => _auth.currentUser?.uid;

  Future<String> _getUsername() async {
    final user = _auth.currentUser;
    if (user == null) return 'Unknown';
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.data()?['username']?.toString() ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<String?> _getProfileImageUrl() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      return doc.data()?['profileImageUrl']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Genera codice lobby 4 cifre
  String _generateCode() {
    return (1000 + Random().nextInt(9000)).toString();
  }

  // ============================================================
  // LOBBY CREATION
  // ============================================================

  /// Crea una nuova lobby e ritorna il codice
  Future<String> createLobby() async {
    final userId = currentUserId;
    if (userId == null) throw 'Utente non autenticato';

    final username = await _getUsername();

    // Genera codice unico
    String code = _generateCode();
    var exists = (await _database.ref('$_basePath/$code').get()).exists;
    while (exists) {
      code = _generateCode();
      exists = (await _database.ref('$_basePath/$code').get()).exists;
    }

    // Crea lobby con tutti i dati
    await _database.ref('$_basePath/$code').set({
      'hostId': userId,
      'trackId': '',
      'trackName': '',
      'status': 'waiting',
      'createdAt': ServerValue.timestamp,
      'participants': {
        userId: {
          'username': username,
          'joinedAt': ServerValue.timestamp,
          'connected': true,
        }
      },
      'liveData': {},
    });

    return code;
  }

  // ============================================================
  // LOBBY MANAGEMENT
  // ============================================================

  /// Imposta il circuito
  Future<void> setTrack(String code, String trackId, String trackName) async {
    await _database.ref('$_basePath/$code').update({
      'trackId': trackId,
      'trackName': trackName,
    });
  }

  /// Avvia la sessione
  Future<void> startSession(String code) async {
    await _database.ref('$_basePath/$code').update({
      'status': 'running',
      'startedAt': ServerValue.timestamp,
    });
  }

  /// Ferma la sessione
  Future<void> stopSession(String code) async {
    await _database.ref('$_basePath/$code').update({
      'status': 'finished',
      'finishedAt': ServerValue.timestamp,
    });
  }

  // ============================================================
  // PARTICIPANT MANAGEMENT
  // ============================================================

  /// Entra in una lobby
  Future<void> joinLobby(String code) async {
    final userId = currentUserId;
    if (userId == null) throw 'Utente non autenticato';

    // Verifica che esista
    final snapshot = await _database.ref('$_basePath/$code').get();
    if (!snapshot.exists) throw 'Lobby non trovata';

    final username = await _getUsername();
    final profileImageUrl = await _getProfileImageUrl();

    // Aggiungi partecipante
    final participantData = {
      'username': username,
      'joinedAt': ServerValue.timestamp,
      'connected': true,
    };

    if (profileImageUrl != null) {
      participantData['profileImageUrl'] = profileImageUrl;
    }

    await _database.ref('$_basePath/$code/participants/$userId').set(participantData);
  }

  /// Esci dalla lobby
  Future<void> leaveLobby(String code) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      // Leggi hostId
      final hostSnapshot = await _database.ref('$_basePath/$code/hostId').get();
      final hostId = hostSnapshot.value?.toString();

      if (hostId == userId) {
        // Host esce: elimina tutta la lobby
        await _database.ref('$_basePath/$code').remove();
      } else {
        // Partecipante esce: marca come disconnesso
        await _database.ref('$_basePath/$code/participants/$userId/connected').set(false);
      }
    } catch (_) {
      // Ignora errori
    }
  }

  /// Aggiorna stato connessione
  Future<void> updateConnectionStatus(String code, bool connected) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _database.ref('$_basePath/$code/participants/$userId/connected').set(connected);
    } catch (_) {}
  }

  // ============================================================
  // LIVE DATA
  // ============================================================

  /// Aggiorna i dati live del pilota corrente
  Future<void> updateLiveData(String code, Map<String, dynamic> data) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _database.ref('$_basePath/$code/liveData/$userId').set({
        ...data,
        'lastUpdate': ServerValue.timestamp,
      });
    } catch (e) {
      print('updateLiveData error: $e');
    }
  }

  // ============================================================
  // LISTENERS
  // ============================================================

  /// Ascolta i cambiamenti della lobby
  Stream<DatabaseEvent> watchLobby(String code) {
    return _database.ref('$_basePath/$code').onValue;
  }

  /// Ascolta i cambiamenti dei liveData
  Stream<DatabaseEvent> watchLiveData(String code) {
    return _database.ref('$_basePath/$code/liveData').onValue;
  }

  /// Ascolta solo lo status della lobby
  Stream<DatabaseEvent> watchStatus(String code) {
    return _database.ref('$_basePath/$code/status').onValue;
  }

  // ============================================================
  // GETTERS
  // ============================================================

  /// Verifica se l'utente corrente è l'host
  Future<bool> isHost(String code) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final snapshot = await _database.ref('$_basePath/$code/hostId').get();
      return snapshot.value?.toString() == userId;
    } catch (_) {
      return false;
    }
  }

  /// Ottieni tutti i dati della lobby
  Future<Map<String, dynamic>?> getLobbyData(String code) async {
    try {
      final snapshot = await _database.ref('$_basePath/$code').get();
      if (!snapshot.exists) return null;
      final value = snapshot.value;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ottieni i dati liveData
  Future<Map<String, dynamic>?> getLiveData(String code) async {
    try {
      final snapshot = await _database.ref('$_basePath/$code/liveData').get();
      if (!snapshot.exists) return null;
      final value = snapshot.value;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
