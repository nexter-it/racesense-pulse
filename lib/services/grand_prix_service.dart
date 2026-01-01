import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GrandPrixService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generate random 4-digit code
  String generateLobbyCode() {
    final random = Random();
    final code = (1000 + random.nextInt(9000)).toString();
    return code;
  }

  // Create a new lobby
  Future<String> createLobby() async {
    final user = _auth.currentUser;
    if (user == null) throw 'Utente non autenticato';

    // Get username
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] ?? 'Unknown';

    String code;
    bool codeExists = true;

    // Generate unique code
    while (codeExists) {
      code = generateLobbyCode();
      final snapshot = await _database.ref('grand_prix_lobbies/$code').get();
      codeExists = snapshot.exists;
      if (!codeExists) {
        // Create lobby
        await _database.ref('grand_prix_lobbies/$code').set({
          'hostId': user.uid,
          'trackId': null,
          'trackName': null,
          'status': 'waiting',
          'createdAt': ServerValue.timestamp,
          'participants': {
            user.uid: {
              'username': username,
              'joinedAt': ServerValue.timestamp,
              'connected': true,
            }
          },
        });
        return code;
      }
    }

    throw 'Impossibile creare lobby';
  }

  // Join an existing lobby
  Future<void> joinLobby(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Utente non autenticato';

    final lobbyRef = _database.ref('grand_prix_lobbies/$code');
    final snapshot = await lobbyRef.get();

    if (!snapshot.exists) {
      throw 'Lobby non trovata';
    }

    final lobbyData = snapshot.value as Map<dynamic, dynamic>;
    final participants = lobbyData['participants'] as Map<dynamic, dynamic>? ?? {};

    // Check if lobby is full (max 20)
    if (participants.length >= 20) {
      throw 'Lobby piena (max 20 piloti)';
    }

    // Check if already in lobby
    if (participants.containsKey(user.uid)) {
      // Just update connected status
      await lobbyRef.child('participants/${user.uid}/connected').set(true);
      return;
    }

    // Get username
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'] ?? 'Unknown';

    // Add user to participants
    await lobbyRef.child('participants/${user.uid}').set({
      'username': username,
      'joinedAt': ServerValue.timestamp,
      'connected': true,
    });
  }

  // Leave lobby
  Future<void> leaveLobby(String code) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final lobbyRef = _database.ref('grand_prix_lobbies/$code');
    final snapshot = await lobbyRef.get();

    if (!snapshot.exists) return;

    final lobbyData = snapshot.value as Map<dynamic, dynamic>;
    final hostId = lobbyData['hostId'];

    // If host is leaving, delete entire lobby
    if (hostId == user.uid) {
      await lobbyRef.remove();
    } else {
      // Just mark as disconnected
      await lobbyRef.child('participants/${user.uid}/connected').set(false);
    }
  }

  // Set track for lobby (host only)
  Future<void> setTrack(String code, String trackId, String trackName) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Utente non autenticato';

    final lobbyRef = _database.ref('grand_prix_lobbies/$code');
    final snapshot = await lobbyRef.get();

    if (!snapshot.exists) throw 'Lobby non trovata';

    final lobbyData = snapshot.value as Map<dynamic, dynamic>;
    if (lobbyData['hostId'] != user.uid) {
      throw 'Solo l\'host può modificare il circuito';
    }

    await lobbyRef.update({
      'trackId': trackId,
      'trackName': trackName,
    });
  }

  // Start session (host only)
  Future<void> startSession(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Utente non autenticato';

    final lobbyRef = _database.ref('grand_prix_lobbies/$code');
    final snapshot = await lobbyRef.get();

    if (!snapshot.exists) throw 'Lobby non trovata';

    final lobbyData = snapshot.value as Map<dynamic, dynamic>;
    if (lobbyData['hostId'] != user.uid) {
      throw 'Solo l\'host può avviare la sessione';
    }

    if (lobbyData['trackId'] == null) {
      throw 'Seleziona un circuito prima di iniziare';
    }

    // Assicuriamoci di preservare i dati essenziali quando aggiorniamo lo status
    await lobbyRef.update({
      'status': 'running',
      'startedAt': ServerValue.timestamp,
      'hostId': user.uid, // Ri-scrivi hostId per sicurezza
      'trackId': lobbyData['trackId'], // Preserva trackId
      'trackName': lobbyData['trackName'], // Preserva trackName
    });
  }

  // Stop session (host only)
  Future<void> stopSession(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw 'Utente non autenticato';

    final lobbyRef = _database.ref('grand_prix_lobbies/$code');
    final snapshot = await lobbyRef.get();

    if (!snapshot.exists) throw 'Lobby non trovata';

    final lobbyData = snapshot.value as Map<dynamic, dynamic>;
    print('🛑 stopSession - Lobby data keys: ${lobbyData.keys.toList()}');
    print('🛑 stopSession - hostId in lobby: ${lobbyData['hostId']}');
    print('🛑 stopSession - user.uid: ${user.uid}');

    // Check hostId solo se presente, altrimenti verifica che l'utente sia nei participants
    final hostId = lobbyData['hostId'];
    if (hostId != null && hostId != user.uid) {
      // Se hostId esiste e non corrisponde, blocca
      throw 'Solo l\'host può fermare la sessione';
    } else if (hostId == null) {
      // Se hostId è null (dati persi), logga warning ma procedi
      // perché abbiamo già verificato nella UI che solo l'host vede il bottone
      print('⚠️ hostId non trovato nei dati lobby, ma procedo con stop');
    }

    // Preserva hostId anche quando finisce la sessione
    await lobbyRef.update({
      'status': 'finished',
      'finishedAt': ServerValue.timestamp,
      'hostId': hostId ?? user.uid, // Usa hostId salvato o user.uid come fallback
    });
  }

  // Update live data for current user
  Future<void> updateLiveData(String code, Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final path = 'grand_prix_lobbies/$code/liveData/${user.uid}';
    print('📤 updateLiveData - Path: $path');
    print('📤 updateLiveData - Data keys: ${data.keys.toList()}');

    try {
      await _database.ref(path).update({
        ...data,
        'lastUpdate': ServerValue.timestamp,
      });
      print('✅ updateLiveData - Success');
    } catch (e) {
      print('❌ updateLiveData - Error: $e');
    }
  }

  // Preserve lobby metadata (chiamato periodicamente per evitare perdita dati)
  Future<void> preserveLobbyMetadata(String code, {
    required String hostId,
    required String? trackId,
    required String? trackName,
  }) async {
    final lobbyRef = _database.ref('grand_prix_lobbies/$code');

    // Scrivi i metadati essenziali senza toccare liveData o participants
    await lobbyRef.update({
      'hostId': hostId,
      'trackId': trackId,
      'trackName': trackName,
    });
  }

  // Listen to lobby changes
  Stream<DatabaseEvent> watchLobby(String code) {
    return _database.ref('grand_prix_lobbies/$code').onValue;
  }

  // Listen to live data changes
  Stream<DatabaseEvent> watchLiveData(String code) {
    return _database.ref('grand_prix_lobbies/$code/liveData').onValue;
  }

  // Check if user is host
  Future<bool> isHost(String code) async {
    final user = _auth.currentUser;
    if (user == null) {
      print('⚠️ isHost: user non autenticato');
      return false;
    }

    final snapshot = await _database.ref('grand_prix_lobbies/$code/hostId').get();
    final hostId = snapshot.value;
    final result = hostId == user.uid;
    print('🔍 isHost check: user.uid=${user.uid}, hostId=$hostId, result=$result');
    return result;
  }

  // Get lobby data
  Future<Map<String, dynamic>?> getLobbyData(String code) async {
    final snapshot = await _database.ref('grand_prix_lobbies/$code').get();
    if (!snapshot.exists) return null;
    return Map<String, dynamic>.from(snapshot.value as Map);
  }
}
