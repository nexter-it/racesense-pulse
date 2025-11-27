import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

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

    final meDoc = await _firestore.collection('users').doc(uid).get();
    final followerUsername = meDoc.data()?['username'] as String? ?? 'user';
    final followerName = meDoc.data()?['fullName'] as String? ?? 'Follower';

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
