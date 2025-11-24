import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream per monitorare lo stato di autenticazione
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Utente corrente
  User? get currentUser => _auth.currentUser;

  // Login con email e password
  Future<UserCredential?> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Registrazione con email e password
  Future<UserCredential?> registerWithEmailPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Aggiorna il display name
      await credential.user?.updateDisplayName(displayName.trim());
      await credential.user?.reload();

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Logout
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Reset password
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Gestione errori Firebase Auth
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Nessun utente trovato con questa email';
      case 'wrong-password':
        return 'Password errata';
      case 'email-already-in-use':
        return 'Email già in uso da un altro account';
      case 'invalid-email':
        return 'Email non valida';
      case 'weak-password':
        return 'Password troppo debole';
      case 'user-disabled':
        return 'Questo account è stato disabilitato';
      case 'too-many-requests':
        return 'Troppi tentativi. Riprova più tardi';
      case 'operation-not-allowed':
        return 'Operazione non consentita';
      case 'invalid-credential':
        return 'Credenziali non valide';
      default:
        return 'Errore: ${e.message ?? 'Errore sconosciuto'}';
    }
  }
}
