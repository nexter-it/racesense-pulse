import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/pulse_background.dart';
import '../services/disclaimer_service.dart';
import '../theme.dart';
import 'login_page.dart';
import 'disclaimer_page.dart';
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

  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      if (user == null) {
        // Utente non autenticato - resetta tutto
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

  void _onDisclaimerAccepted() {
    setState(() {
      _authState = _AuthState.authenticated;
      // Crea RootShell solo una volta
      _rootShell ??= const RootShell();
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
