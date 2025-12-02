import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EngagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _currentUser => _auth.currentUser;

  Future<Map<String, bool>> getUserReactions(String sessionId) async {
    final uid = _currentUser?.uid;
    if (uid == null) return {'like': false, 'challenge': false};

    final likeDoc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('likes')
        .doc(sessionId)
        .get();
    final challengeDoc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('challenges')
        .doc(sessionId)
        .get();

    return {
      'like': likeDoc.exists,
      'challenge': challengeDoc.exists,
    };
  }

  Future<void> toggleLike(String sessionId) async {
    final uid = _currentUser?.uid;
    if (uid == null) return;

    final likeRef =
        _firestore.collection('users').doc(uid).collection('likes').doc(sessionId);
    final sessionRef = _firestore.collection('sessions').doc(sessionId);

    await _firestore.runTransaction((tx) async {
      final liked = (await tx.get(likeRef)).exists;
      if (liked) {
        tx.delete(likeRef);
        tx.update(sessionRef, {
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        tx.set(likeRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(sessionRef, {
          'likesCount': FieldValue.increment(1),
        });
      }
    });
  }

  Future<void> toggleChallenge(String sessionId) async {
    final uid = _currentUser?.uid;
    if (uid == null) return;

    final chalRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('challenges')
        .doc(sessionId);
    final sessionRef = _firestore.collection('sessions').doc(sessionId);

    await _firestore.runTransaction((tx) async {
      final challenged = (await tx.get(chalRef)).exists;
      if (challenged) {
        tx.delete(chalRef);
        tx.update(sessionRef, {
          'challengeCount': FieldValue.increment(-1),
        });
      } else {
        tx.set(chalRef, {
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(sessionRef, {
          'challengeCount': FieldValue.increment(1),
        });
      }
    });
  }
}
