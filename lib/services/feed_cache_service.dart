import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session_model.dart';
import 'session_service.dart';
import 'follow_service.dart';

/// Servizio di cache locale per il feed - stile Instagram
///
/// Carica i dati da cache all'avvio e refresha solo con pull-to-refresh.
/// Questo riduce drasticamente le letture Firebase.
class FeedCacheService {
  static final FeedCacheService _instance = FeedCacheService._internal();
  factory FeedCacheService() => _instance;
  FeedCacheService._internal();

  final SessionService _sessionService = SessionService();
  final FollowService _followService = FollowService();

  // Cache in memoria
  List<SessionModel> _cachedFeedSessions = [];
  Set<String> _cachedFollowingIds = {};
  DateTime? _lastFeedRefresh;
  DateTime? _lastFollowingRefresh;
  String? _cachedUserId; // Per verificare che la cache sia dell'utente corrente
  bool _isFirstAppOpen = true; // Flag per forzare caricamento da Firebase all'apertura

  // Chiavi SharedPreferences
  static const String _feedCacheKey = 'feed_cache_v1';
  static const String _followingCacheKey = 'following_cache_v1';
  static const String _feedTimestampKey = 'feed_cache_timestamp';
  static const String _followingTimestampKey = 'following_cache_timestamp';
  static const String _userIdCacheKey = 'feed_user_id_v1';

  // Durata massima cache (per evitare dati troppo vecchi)
  static const Duration _maxCacheAge = Duration(hours: 24);

  /// Inizializza la cache all'avvio dell'app
  /// Carica i dati salvati da SharedPreferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    // Verifica che la cache sia dell'utente corrente
    final cachedUserId = prefs.getString(_userIdCacheKey);
    if (user != null && cachedUserId != null && cachedUserId != user.uid) {
      // La cache è di un altro utente, cancellala
      print('⚠️ Feed cache di un altro utente, cancellazione...');
      await clearCache();
      return;
    }

    // Carica following ids dalla cache
    final followingJson = prefs.getString(_followingCacheKey);
    if (followingJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(followingJson);
        _cachedFollowingIds = decoded.cast<String>().toSet();

        final timestamp = prefs.getInt(_followingTimestampKey);
        if (timestamp != null) {
          _lastFollowingRefresh = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      } catch (e) {
        print('⚠️ Errore parsing following cache: $e');
      }
    }

    // Carica feed dalla cache
    final feedJson = prefs.getString(_feedCacheKey);
    if (feedJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(feedJson);
        _cachedFeedSessions = decoded
            .map((json) => SessionModel.fromCacheJson(json as Map<String, dynamic>))
            .toList();

        final timestamp = prefs.getInt(_feedTimestampKey);
        if (timestamp != null) {
          _lastFeedRefresh = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }

        print('✅ Feed cache caricata: ${_cachedFeedSessions.length} sessioni');
      } catch (e) {
        print('⚠️ Errore parsing feed cache: $e');
        _cachedFeedSessions = [];
      }
    }

    if (user != null) {
      _cachedUserId = user.uid;
    }
  }

  /// Restituisce i dati cached del feed (senza fare chiamate Firebase)
  List<SessionModel> getCachedFeed() => List.unmodifiable(_cachedFeedSessions);

  /// Restituisce i following ids cached
  Set<String> getCachedFollowingIds() => Set.unmodifiable(_cachedFollowingIds);

  /// Verifica se la cache è valida (non troppo vecchia)
  bool get isCacheValid {
    if (_lastFeedRefresh == null) return false;
    return DateTime.now().difference(_lastFeedRefresh!) < _maxCacheAge;
  }

  /// Verifica se abbiamo dati in cache
  /// All'apertura dell'app ritorna sempre false per forzare il caricamento da Firebase
  bool get hasCachedData {
    if (_isFirstAppOpen) {
      return false; // Forza caricamento da Firebase
    }
    return _cachedFeedSessions.isNotEmpty;
  }

  /// Segna che il primo caricamento è stato completato
  void markFirstLoadComplete() {
    _isFirstAppOpen = false;
  }

  /// Verifica se è la prima apertura dell'app
  bool get isFirstAppOpen => _isFirstAppOpen;

  /// Timestamp ultimo refresh
  DateTime? get lastRefreshTime => _lastFeedRefresh;

  /// Refresha i following ids da Firebase e salva in cache
  Future<Set<String>> refreshFollowingIds({int limit = 200}) async {
    try {
      _cachedFollowingIds = await _followService.getFollowingIds(limit: limit);
      _lastFollowingRefresh = DateTime.now();

      // Salva in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _followingCacheKey,
        jsonEncode(_cachedFollowingIds.toList()),
      );
      await prefs.setInt(
        _followingTimestampKey,
        _lastFollowingRefresh!.millisecondsSinceEpoch,
      );

      print('✅ Following IDs refreshed: ${_cachedFollowingIds.length}');
      return _cachedFollowingIds;
    } catch (e) {
      print('❌ Errore refresh following: $e');
      return _cachedFollowingIds; // Ritorna cache esistente
    }
  }

  /// Refresha il feed completo da Firebase
  /// Chiamato solo con pull-to-refresh o al primo avvio senza cache
  ///
  /// OTTIMIZZAZIONE: Ridotto maxBatchAttempts da 4 a 2 e aggiunto early exit
  /// Risparmio: da 100 letture potenziali a max 50 per refresh
  Future<List<SessionModel>> refreshFeed({
    required Set<String> followingIds,
    required bool Function(SessionModel) isNearbyFilter,
    int pageSize = 10,
    int maxBatchAttempts = 2, // OTTIMIZZATO: era 4
  }) async {
    try {
      print('🔄 Refreshing feed from Firebase...');

      final List<SessionModel> feedSessions = [];
      DocumentSnapshot? lastDoc;
      int added = 0;
      int attempts = 0;
      const fetchBatchSize = 25;

      while (added < pageSize && attempts < maxBatchAttempts) {
        attempts++;

        final snap = await _sessionService.fetchSessionsPage(
          limit: fetchBatchSize,
          startAfter: lastDoc,
        );

        if (snap.docs.isEmpty) break;
        lastDoc = snap.docs.last;

        for (final doc in snap.docs) {
          final session = SessionModel.fromFirestore(doc.id, doc.data());
          final isFollowed = followingIds.contains(session.userId);
          final isNearby = isNearbyFilter(session);

          if (!isFollowed && !isNearby) continue;

          // Evita duplicati
          if (feedSessions.any((s) => s.sessionId == session.sessionId)) continue;

          feedSessions.add(session);
          added++;

          if (added >= pageSize) break;
        }

        // OTTIMIZZAZIONE: Early exit se abbiamo abbastanza sessioni
        if (added >= pageSize) {
          print('✅ Early exit: raggiunte $added sessioni in $attempts tentativi');
          break;
        }

        if (snap.docs.length < fetchBatchSize) break;
      }

      // Aggiorna cache in memoria
      _cachedFeedSessions = feedSessions;
      _lastFeedRefresh = DateTime.now();

      // Salva in SharedPreferences
      await _saveFeedToPrefs();

      print('✅ Feed refreshed: ${feedSessions.length} sessioni in $attempts batch');
      return feedSessions;
    } catch (e) {
      print('❌ Errore refresh feed: $e');
      return _cachedFeedSessions; // Ritorna cache esistente in caso di errore
    }
  }

  /// Carica più sessioni per il feed (paginazione)
  /// Usato per infinite scroll
  ///
  /// OTTIMIZZAZIONE: Ridotto maxAttempts da 4 a 2 con early exit
  Future<List<SessionModel>> loadMoreFeed({
    required Set<String> followingIds,
    required bool Function(SessionModel) isNearbyFilter,
    required DocumentSnapshot? startAfter,
    int pageSize = 10,
  }) async {
    try {
      final List<SessionModel> newSessions = [];
      DocumentSnapshot? lastDoc = startAfter;
      int added = 0;
      int attempts = 0;
      const fetchBatchSize = 25;
      const maxAttempts = 2; // OTTIMIZZATO: era 4

      while (added < pageSize && attempts < maxAttempts) {
        attempts++;

        final snap = await _sessionService.fetchSessionsPage(
          limit: fetchBatchSize,
          startAfter: lastDoc,
        );

        if (snap.docs.isEmpty) break;
        lastDoc = snap.docs.last;

        for (final doc in snap.docs) {
          final session = SessionModel.fromFirestore(doc.id, doc.data());
          final isFollowed = followingIds.contains(session.userId);
          final isNearby = isNearbyFilter(session);

          if (!isFollowed && !isNearby) continue;

          // Evita duplicati con cache esistente
          if (_cachedFeedSessions.any((s) => s.sessionId == session.sessionId)) continue;
          if (newSessions.any((s) => s.sessionId == session.sessionId)) continue;

          newSessions.add(session);
          added++;

          if (added >= pageSize) break;
        }

        // OTTIMIZZAZIONE: Early exit se abbiamo abbastanza sessioni
        if (added >= pageSize) break;

        if (snap.docs.length < fetchBatchSize) break;
      }

      // Aggiungi alla cache
      _cachedFeedSessions.addAll(newSessions);
      await _saveFeedToPrefs();

      return newSessions;
    } catch (e) {
      print('❌ Errore load more: $e');
      return [];
    }
  }

  /// Salva il feed corrente in SharedPreferences
  Future<void> _saveFeedToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;

      // Salva userId per verificare la cache al prossimo accesso
      if (user != null) {
        await prefs.setString(_userIdCacheKey, user.uid);
      }

      // Limita a 50 sessioni per non appesantire troppo
      final sessionsToSave = _cachedFeedSessions.take(50).toList();

      final jsonList = sessionsToSave
          .map((s) => s.toCacheJson())
          .toList();

      await prefs.setString(_feedCacheKey, jsonEncode(jsonList));
      await prefs.setInt(
        _feedTimestampKey,
        _lastFeedRefresh?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('⚠️ Errore salvataggio cache: $e');
    }
  }

  /// Pulisce la cache (utile per logout o debug)
  Future<void> clearCache() async {
    _cachedFeedSessions = [];
    _cachedFollowingIds = {};
    _lastFeedRefresh = null;
    _lastFollowingRefresh = null;
    _cachedUserId = null;
    _isFirstAppOpen = true; // Reset per forzare caricamento al prossimo login

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_feedCacheKey);
    await prefs.remove(_followingCacheKey);
    await prefs.remove(_feedTimestampKey);
    await prefs.remove(_followingTimestampKey);
    await prefs.remove(_userIdCacheKey);

    print('🗑️ Feed cache cleared');
  }

  /// Aggiunge una sessione alla cache (dopo salvataggio locale)
  void addSessionToCache(SessionModel session) {
    _cachedFeedSessions.insert(0, session);
    _saveFeedToPrefs();
  }

  /// Rimuove una sessione dalla cache
  void removeSessionFromCache(String sessionId) {
    _cachedFeedSessions.removeWhere((s) => s.sessionId == sessionId);
    _saveFeedToPrefs();
  }
}
