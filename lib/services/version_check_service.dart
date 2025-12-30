import 'package:cloud_firestore/cloud_firestore.dart';

/// Versione corrente dell'app
const String appVersion = '0.0.1';

class VersionCheckService {
  static final VersionCheckService _instance = VersionCheckService._internal();
  factory VersionCheckService() => _instance;
  VersionCheckService._internal();

  /// Controlla se la versione dell'app è compatibile con quella richiesta da Firebase
  /// Ritorna true se l'app deve essere aggiornata, false se è ok
  Future<bool> needsUpdate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('version_settings')
          .get();

      if (!doc.exists) {
        // Documento non esiste, non bloccare l'utente
        return false;
      }

      final data = doc.data();
      if (data == null) {
        return false;
      }

      final minimumVersion = data['minimum'] as String?;
      if (minimumVersion == null) {
        return false;
      }

      // Confronta le versioni
      return appVersion != minimumVersion;
    } catch (e) {
      // In caso di errore (offline, permessi, ecc.) non bloccare l'utente
      print('⚠️ Version check failed: $e');
      return false;
    }
  }

  /// Ritorna la versione minima richiesta da Firebase
  Future<String?> getMinimumVersion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('version_settings')
          .get();

      if (!doc.exists) return null;
      return doc.data()?['minimum'] as String?;
    } catch (e) {
      return null;
    }
  }
}
