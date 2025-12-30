import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session_model.dart';
import 'session_service.dart';
import 'firestore_service.dart';

/// Servizio di cache locale per il profilo utente - stile Instagram
///
/// Carica i dati da cache all'avvio e refresha solo con pull-to-refresh.
/// Questo riduce drasticamente le letture Firebase.
class ProfileCacheService {
  static final ProfileCacheService _instance = ProfileCacheService._internal();
  factory ProfileCacheService() => _instance;
  ProfileCacheService._internal();

  final SessionService _sessionService = SessionService();
  final FirestoreService _firestoreService = FirestoreService();

  // Cache in memoria
  Map<String, dynamic>? _cachedUserData;
  UserStats? _cachedUserStats;
  List<SessionModel> _cachedSessions = [];
  DateTime? _lastRefresh;
  String? _cachedUserId; // Per verificare che la cache sia dell'utente corrente
  bool _isFirstAppOpen = true; // Flag per forzare caricamento da Firebase all'apertura

  // Chiavi SharedPreferences
  static const String _userDataCacheKey = 'profile_user_data_v1';
  static const String _userStatsCacheKey = 'profile_user_stats_v1';
  static const String _sessionsCacheKey = 'profile_sessions_v1';
  static const String _timestampKey = 'profile_cache_timestamp';
  static const String _userIdCacheKey = 'profile_user_id_v1';

  // Durata massima cache
  static const Duration _maxCacheAge = Duration(hours: 24);

  /// Inizializza la cache all'avvio dell'app
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Verifica che la cache sia dell'utente corrente
    final cachedUserId = prefs.getString(_userIdCacheKey);
    if (cachedUserId != null && cachedUserId != user.uid) {
      // La cache è di un altro utente, cancellala
      print('⚠️ Cache di un altro utente, cancellazione...');
      await clearCache();
      return;
    }

    // Carica timestamp
    final timestamp = prefs.getInt(_timestampKey);
    if (timestamp != null) {
      _lastRefresh = DateTime.fromMillisecondsSinceEpoch(timestamp);
    }

    // Carica user data
    final userDataJson = prefs.getString(_userDataCacheKey);
    if (userDataJson != null) {
      try {
        _cachedUserData = jsonDecode(userDataJson) as Map<String, dynamic>;
      } catch (e) {
        print('⚠️ Errore parsing user data cache: $e');
      }
    }

    // Carica user stats
    final statsJson = prefs.getString(_userStatsCacheKey);
    if (statsJson != null) {
      try {
        final statsMap = jsonDecode(statsJson) as Map<String, dynamic>;
        _cachedUserStats = UserStats.fromMap(statsMap);
      } catch (e) {
        print('⚠️ Errore parsing stats cache: $e');
      }
    }

    // Carica sessioni
    final sessionsJson = prefs.getString(_sessionsCacheKey);
    if (sessionsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(sessionsJson);
        _cachedSessions = decoded
            .map((json) => SessionModel.fromCacheJson(json as Map<String, dynamic>))
            .toList();
        print('✅ Profile cache caricata: ${_cachedSessions.length} sessioni');
      } catch (e) {
        print('⚠️ Errore parsing sessions cache: $e');
        _cachedSessions = [];
      }
    }

    _cachedUserId = user.uid;
  }

  /// Verifica se abbiamo dati in cache
  /// All'apertura dell'app ritorna sempre false per forzare il caricamento da Firebase
  bool get hasCachedData {
    if (_isFirstAppOpen) {
      return false; // Forza caricamento da Firebase
    }
    return _cachedUserData != null || _cachedSessions.isNotEmpty;
  }

  /// Segna che il primo caricamento è stato completato
  void markFirstLoadComplete() {
    _isFirstAppOpen = false;
  }

  /// Verifica se è la prima apertura dell'app
  bool get isFirstAppOpen => _isFirstAppOpen;

  /// Verifica se la cache è valida
  bool get isCacheValid {
    if (_lastRefresh == null) return false;
    return DateTime.now().difference(_lastRefresh!) < _maxCacheAge;
  }

  /// Restituisce i dati cached
  Map<String, dynamic>? get cachedUserData => _cachedUserData;
  UserStats? get cachedUserStats => _cachedUserStats;
  List<SessionModel> get cachedSessions => List.unmodifiable(_cachedSessions);
  DateTime? get lastRefreshTime => _lastRefresh;

  /// Restituisce dati utente estratti dalla cache
  String getCachedFullName() {
    return _cachedUserData?['fullName'] as String? ??
           FirebaseAuth.instance.currentUser?.displayName ??
           'Utente';
  }

  String getCachedUsername() {
    final fullName = getCachedFullName();
    return _cachedUserData?['username'] as String? ??
           fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String? getCachedAffiliateCode() => _cachedUserData?['affiliateCode'] as String?;
  String? getCachedReferredByCode() => _cachedUserData?['referredByCode'] as String?;

  int getCachedFollowerCount() => _cachedUserStats?.followerCount ?? 0;
  int getCachedFollowingCount() => _cachedUserStats?.followingCount ?? 0;

  /// Refresh completo da Firebase (pull-to-refresh)
  Future<ProfileData> refreshFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Utente non autenticato');
    }

    print('🔄 Refreshing profile from Firebase...');

    try {
      // Inizializza stats se necessario
      await _firestoreService.initializeStatsIfNeeded(user.uid);

      // Carica dati in parallelo
      final results = await Future.wait([
        _firestoreService.getUserData(user.uid),
        _sessionService.getUserSessions(user.uid, limit: 5),
      ]);

      final userData = results[0] as Map<String, dynamic>?;
      final sessions = results[1] as List<SessionModel>;

      // Estrai stats
      final stats = (userData != null && userData['stats'] != null)
          ? UserStats.fromMap(userData['stats'] as Map<String, dynamic>)
          : UserStats.empty();

      // Aggiorna cache in memoria
      _cachedUserData = userData;
      _cachedUserStats = stats;
      _cachedSessions = sessions;
      _lastRefresh = DateTime.now();

      // Salva in SharedPreferences
      await _saveToPrefs();

      print('✅ Profile refreshed: ${sessions.length} sessioni');

      return ProfileData(
        userData: userData,
        stats: stats,
        sessions: sessions,
      );
    } catch (e) {
      print('❌ Errore refresh profile: $e');
      // Ritorna cache esistente in caso di errore
      return ProfileData(
        userData: _cachedUserData,
        stats: _cachedUserStats ?? UserStats.empty(),
        sessions: _cachedSessions,
      );
    }
  }

  /// Carica tutte le sessioni (per espansione lista)
  Future<List<SessionModel>> loadAllSessions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _cachedSessions;

    try {
      final sessions = await _sessionService.getUserSessions(user.uid, limit: 50);

      // Aggiorna cache solo se abbiamo più sessioni
      if (sessions.length > _cachedSessions.length) {
        _cachedSessions = sessions;
        await _saveToPrefs();
      }

      return sessions;
    } catch (e) {
      print('❌ Errore caricamento tutte le sessioni: $e');
      return _cachedSessions;
    }
  }

  /// Salva la cache corrente in SharedPreferences
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;

      // Salva userId per verificare la cache al prossimo accesso
      if (user != null) {
        await prefs.setString(_userIdCacheKey, user.uid);
      }

      // Salva user data
      if (_cachedUserData != null) {
        // Rimuovi campi non serializzabili (come Timestamp)
        final serializableData = _makeSerializable(_cachedUserData!);
        await prefs.setString(_userDataCacheKey, jsonEncode(serializableData));
      }

      // Salva stats
      if (_cachedUserStats != null) {
        await prefs.setString(_userStatsCacheKey, jsonEncode(_cachedUserStats!.toMap()));
      }

      // Salva sessioni (max 20)
      final sessionsToSave = _cachedSessions.take(20).toList();
      final jsonList = sessionsToSave.map((s) => s.toCacheJson()).toList();
      await prefs.setString(_sessionsCacheKey, jsonEncode(jsonList));

      // Salva timestamp
      await prefs.setInt(
        _timestampKey,
        _lastRefresh?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('⚠️ Errore salvataggio profile cache: $e');
    }
  }

  /// Converte i dati in formato serializzabile (rimuove Timestamp, GeoPoint, ecc.)
  Map<String, dynamic> _makeSerializable(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) {
        result[entry.key] = null;
      } else if (value is String || value is num || value is bool) {
        result[entry.key] = value;
      } else if (value is List) {
        result[entry.key] = value.map((e) {
          if (e is Map<String, dynamic>) return _makeSerializable(e);
          if (e is String || e is num || e is bool) return e;
          return e.toString();
        }).toList();
      } else if (value is Map<String, dynamic>) {
        result[entry.key] = _makeSerializable(value);
      }
      // Ignora Timestamp, GeoPoint e altri tipi non serializzabili
    }

    return result;
  }

  /// Pulisce la cache (utile per logout)
  Future<void> clearCache() async {
    _cachedUserData = null;
    _cachedUserStats = null;
    _cachedSessions = [];
    _lastRefresh = null;
    _cachedUserId = null;
    _isFirstAppOpen = true; // Reset per forzare caricamento al prossimo login

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDataCacheKey);
    await prefs.remove(_userStatsCacheKey);
    await prefs.remove(_sessionsCacheKey);
    await prefs.remove(_timestampKey);
    await prefs.remove(_userIdCacheKey);

    print('🗑️ Profile cache cleared');
  }

  /// Aggiorna il codice affiliato nella cache
  void updateAffiliateCode(String code) {
    _cachedUserData ??= {};
    _cachedUserData!['affiliateCode'] = code;
    _saveToPrefs();
  }

  /// Rimuove una sessione dalla cache
  void removeSessionFromCache(String sessionId) {
    _cachedSessions.removeWhere((s) => s.sessionId == sessionId);
    _saveToPrefs();
  }

  /// Aggiunge una sessione alla cache
  void addSessionToCache(SessionModel session) {
    _cachedSessions.insert(0, session);
    _saveToPrefs();
  }
}

/// Classe helper per i dati del profilo
class ProfileData {
  final Map<String, dynamic>? userData;
  final UserStats stats;
  final List<SessionModel> sessions;

  ProfileData({
    required this.userData,
    required this.stats,
    required this.sessions,
  });
}
