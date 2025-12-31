import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FollowService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  // Cache locale per username e fullName per evitare letture Firebase
  static String? _cachedUsername;
  static String? _cachedFullName;
  static String? _cachedUserId;

  /// Carica e cacha i dati utente corrente (chiamare una volta al login)
  /// OTTIMIZZAZIONE: Evita letture ripetute del documento utente
  Future<void> cacheCurrentUserData() async {
    final user = _currentUser;
    if (user == null) return;

    // Se già cached per questo utente, skip
    if (_cachedUserId == user.uid && _cachedUsername != null) return;

    try {
      // Prima prova da SharedPreferences (0 letture Firebase)
      final prefs = await SharedPreferences.getInstance();
      final cachedId = prefs.getString('follow_cached_user_id');

      if (cachedId == user.uid) {
        _cachedUsername = prefs.getString('follow_cached_username');
        _cachedFullName = prefs.getString('follow_cached_fullname');
        _cachedUserId = user.uid;
        if (_cachedUsername != null) return;
      }

      // Altrimenti leggi da Firebase (1 lettura, poi cached)
      final doc = await _firestore.collection('users').doc(user.uid).get();
      _cachedUsername = doc.data()?['username'] as String? ?? 'user';
      _cachedFullName = doc.data()?['fullName'] as String? ?? user.displayName ?? 'Follower';
      _cachedUserId = user.uid;

      // Salva in SharedPreferences per prossimo avvio
      await prefs.setString('follow_cached_user_id', user.uid);
      await prefs.setString('follow_cached_username', _cachedUsername!);
      await prefs.setString('follow_cached_fullname', _cachedFullName!);
    } catch (e) {
      // Fallback ai dati Firebase Auth
      _cachedUsername = user.displayName?.split(' ').first.toLowerCase() ?? 'user';
      _cachedFullName = user.displayName ?? 'Follower';
      _cachedUserId = user.uid;
    }
  }

  /// Pulisce la cache (chiamare al logout)
  static Future<void> clearCache() async {
    _cachedUsername = null;
    _cachedFullName = null;
    _cachedUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('follow_cached_user_id');
    await prefs.remove('follow_cached_username');
    await prefs.remove('follow_cached_fullname');
  }

  Future<Set<String>> getFollowingIds({int limit = 200}) async {
    final uid = _currentUser?.uid;
    if (uid == null) return {};

    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('following')
          .limit(limit)
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<bool> isFollowing(String targetUserId) async {
    final uid = _currentUser?.uid;
    if (uid == null || uid == targetUserId) return false;
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(targetUserId)
        .get();
    return doc.exists;
  }

  Future<void> follow(String targetUserId) async {
    final uid = _currentUser?.uid;
    if (uid == null || uid == targetUserId) return;

    // OTTIMIZZAZIONE: Usa cache invece di leggere da Firebase ogni volta
    // Prima del fix: 1 lettura documento utente per ogni follow
    // Dopo il fix: 0 letture (usa cache)
    await cacheCurrentUserData(); // Assicura che la cache sia popolata
    final followerUsername = _cachedUsername ?? 'user';
    final followerName = _cachedFullName ?? 'Follower';

    final batch = _firestore.batch();

    final followingRef =
        _firestore.collection('users').doc(uid).collection('following').doc(targetUserId);
    final followerRef =
        _firestore.collection('users').doc(targetUserId).collection('followers').doc(uid);

    batch.set(followingRef, {
      'targetUserId': targetUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(followerRef, {
      'followerId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(_firestore.collection('users').doc(uid), {
      'stats.followingCount': FieldValue.increment(1),
    });
    batch.update(_firestore.collection('users').doc(targetUserId), {
      'stats.followerCount': FieldValue.increment(1),
    });

    // Notifica follow
    final notifRef = _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('notifications')
        .doc(uid); // usa followerId come docId per evitare duplicati
    batch.set(notifRef, {
      'type': 'follow',
      'followerId': uid,
      'followerUsername': followerUsername,
      'followerName': followerName,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });

    await batch.commit();
  }

  Future<void> unfollow(String targetUserId) async {
    final uid = _currentUser?.uid;
    if (uid == null || uid == targetUserId) return;

    final batch = _firestore.batch();

    final followingRef =
        _firestore.collection('users').doc(uid).collection('following').doc(targetUserId);
    final followerRef =
        _firestore.collection('users').doc(targetUserId).collection('followers').doc(uid);

    batch.delete(followingRef);
    batch.delete(followerRef);
    final notifRef = _firestore
        .collection('users')
        .doc(targetUserId)
        .collection('notifications')
        .doc(uid);
    batch.delete(notifRef);

    batch.update(_firestore.collection('users').doc(uid), {
      'stats.followingCount': FieldValue.increment(-1),
    });
    batch.update(_firestore.collection('users').doc(targetUserId), {
      'stats.followerCount': FieldValue.increment(-1),
    });

    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> fetchFollowNotifications(
    String userId, {
    int limit = 20,
  }) async {
    final snap = await _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('type', isEqualTo: 'follow')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }
}
