import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Crea un nuovo documento utente in Firestore
  Future<void> createUserDocument({
    required String userId,
    required String fullName,
    required String email,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'fullName': fullName,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Errore nella creazione del profilo: $e';
    }
  }

  // Recupera i dati utente da Firestore
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      throw 'Errore nel recupero dei dati: $e';
    }
  }

  // Salva i dati utente in cache locale
  Future<void> cacheUserData(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_data', jsonEncode(userData));
    } catch (e) {
      // Ignora errori di cache, non critici
    }
  }

  // Recupera i dati utente dalla cache locale
  Future<Map<String, dynamic>?> getCachedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_user_data');
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Pulisci la cache (da chiamare al logout)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_user_data');
    } catch (e) {
      // Ignora errori
    }
  }

  // Recupera i dati utente: prima prova la cache, poi Firestore
  Future<Map<String, dynamic>?> getUserDataWithCache(String userId) async {
    // Prova prima dalla cache
    final cached = await getCachedUserData();
    if (cached != null) {
      return cached;
    }

    // Se non c'è cache, scarica da Firestore
    final userData = await getUserData(userId);
    if (userData != null) {
      // Salva in cache per il prossimo accesso
      await cacheUserData(userData);
    }
    return userData;
  }
}
