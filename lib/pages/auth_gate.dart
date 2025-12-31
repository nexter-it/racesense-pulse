import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/pulse_background.dart';
import '../services/disclaimer_service.dart';
import '../services/follow_service.dart';
import '../theme.dart';
import 'login_page.dart';
import 'disclaimer_page.dart';
import 'account_deleted_page.dart';
import '../main.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);

/// Enum per lo stato dell'autenticazione
enum _AuthState {
  loading,
  unauthenticated,
  checkingDisclaimer,
  needsDisclaimer,
  accountDeleted, // Nuovo stato per account in eliminazione
  authenticated,
}

/// AuthGate monitora lo stato di autenticazione e mostra
/// LoginPage se l'utente non è autenticato,
/// altrimenti mostra la home dell'app (previo check del disclaimer)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _AuthState _authState = _AuthState.loading;
  String? _currentUserId;

  // RootShell mantenuto come istanza persistente - NON viene mai ricreato
  // una volta che l'utente è autenticato
  Widget? _rootShell;

  // FIX MEMORY LEAK: Subscription per auth state changes
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  @override
  void dispose() {
    // FIX MEMORY LEAK: Cancella subscription quando widget viene distrutto
    _authSubscription?.cancel();
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      if (user == null) {
        // Utente non autenticato - resetta tutto
        // OTTIMIZZAZIONE: Pulisce cache FollowService al logout
        FollowService.clearCache();
        setState(() {
          _authState = _AuthState.unauthenticated;
          _currentUserId = null;
          _rootShell = null; // Distruggi RootShell solo al logout
        });
        return;
      }

      // Se è lo stesso utente già autenticato, non fare nulla
      if (_currentUserId == user.uid && _authState == _AuthState.authenticated) {
        return;
      }

      // Nuovo utente o primo check
      if (_currentUserId != user.uid) {
        setState(() {
          _authState = _AuthState.checkingDisclaimer;
          _currentUserId = user.uid;
        });

        // Prima controlla se l'account è nella lista di eliminazione
        final isDeleted = await _checkIfAccountDeleted(user.uid);

        if (!mounted) return;

        if (isDeleted) {
          // Account in eliminazione - fai logout e mostra pagina
          await FirebaseAuth.instance.signOut();
          setState(() {
            _authState = _AuthState.accountDeleted;
            _currentUserId = null;
            _rootShell = null;
          });
          return;
        }

        // Controlla disclaimer
        final accepted = await DisclaimerService().hasAcceptedDisclaimer(user.uid);

        if (!mounted) return;

        if (accepted) {
          setState(() {
            _authState = _AuthState.authenticated;
            // Crea RootShell solo una volta
            _rootShell ??= const RootShell();
          });
        } else {
          setState(() {
            _authState = _AuthState.needsDisclaimer;
          });
        }
      }
    });
  }

  /// Controlla se l'utente ha richiesto l'eliminazione dell'account
  Future<bool> _checkIfAccountDeleted(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('deleted_request_account')
          .doc(userId)
          .get();
      return doc.exists;
    } catch (e) {
      // In caso di errore, permetti il login
      debugPrint('Errore nel controllo eliminazione account: $e');
      return false;
    }
  }

  void _onDisclaimerAccepted() {
    setState(() {
      _authState = _AuthState.authenticated;
      // Crea RootShell solo una volta
      _rootShell ??= const RootShell();
    });
  }

  /// Chiamato quando l'utente clicca "Torna al login" dalla pagina AccountDeleted
  void _onBackToLogin() {
    setState(() {
      _authState = _AuthState.unauthenticated;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_authState) {
      case _AuthState.loading:
      case _AuthState.checkingDisclaimer:
        return Scaffold(
          backgroundColor: _kBgColor,
          body: const PulseBackground(
            withTopPadding: true,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kBrandColor),
              ),
            ),
          ),
        );

      case _AuthState.unauthenticated:
        return const LoginPage();

      case _AuthState.accountDeleted:
        return AccountDeletedPage(onBackToLogin: _onBackToLogin);

      case _AuthState.needsDisclaimer:
        return DisclaimerPage(
          userId: _currentUserId!,
          onAccepted: _onDisclaimerAccepted,
        );

      case _AuthState.authenticated:
        // Usa l'istanza cached di RootShell - MAI ricreata
        return _rootShell!;
    }
  }
}
