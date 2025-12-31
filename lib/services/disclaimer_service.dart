import 'package:shared_preferences/shared_preferences.dart';

/// Servizio per gestire l'accettazione del disclaimer dell'app.
/// Salva localmente se l'utente ha accettato le condizioni d'uso.
class DisclaimerService {
  static final DisclaimerService _instance = DisclaimerService._internal();
  factory DisclaimerService() => _instance;
  DisclaimerService._internal();

  static const String _acceptedKeyPrefix = 'disclaimer_accepted_v1_';

  /// Verifica se l'utente ha già accettato il disclaimer
  Future<bool> hasAcceptedDisclaimer(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_acceptedKeyPrefix$userId') ?? false;
  }

  /// Salva l'accettazione del disclaimer per l'utente
  Future<void> setDisclaimerAccepted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_acceptedKeyPrefix$userId', true);
    await prefs.setString('${_acceptedKeyPrefix}timestamp_$userId',
        DateTime.now().toIso8601String());
  }

  /// Cancella l'accettazione (per debug/test)
  Future<void> clearAcceptance(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_acceptedKeyPrefix$userId');
    await prefs.remove('${_acceptedKeyPrefix}timestamp_$userId');
  }
}
