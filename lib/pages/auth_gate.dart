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

/// AuthGate monitora lo stato di autenticazione e mostra
/// LoginPage se l'utente non è autenticato,
/// altrimenti mostra la home dell'app (previo check del disclaimer)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _hasAcceptedDisclaimer;
  String? _currentUserId;

  Future<void> _checkDisclaimer(String userId) async {
    if (_currentUserId == userId && _hasAcceptedDisclaimer != null) {
      return; // Already checked for this user
    }

    final accepted = await DisclaimerService().hasAcceptedDisclaimer(userId);
    if (mounted) {
      setState(() {
        _currentUserId = userId;
        _hasAcceptedDisclaimer = accepted;
      });
    }
  }

  void _onDisclaimerAccepted() {
    setState(() {
      _hasAcceptedDisclaimer = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Mostra loading mentre controlla lo stato
        if (snapshot.connectionState == ConnectionState.waiting) {
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
        }

        // Se non c'è un utente autenticato, mostra il login
        if (!snapshot.hasData || snapshot.data == null) {
          // Reset disclaimer state when user logs out
          _hasAcceptedDisclaimer = null;
          _currentUserId = null;
          return const LoginPage();
        }

        final user = snapshot.data!;

        // Check del disclaimer
        if (_hasAcceptedDisclaimer == null || _currentUserId != user.uid) {
          // Prima verifica se ha già accettato
          _checkDisclaimer(user.uid);

          // Mostra loading mentre verifica
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
        }

        // Se non ha ancora accettato il disclaimer, mostralo
        if (_hasAcceptedDisclaimer == false) {
          return DisclaimerPage(
            userId: user.uid,
            onAccepted: _onDisclaimerAccepted,
          );
        }

        // Se ha accettato, mostra la home
        return const RootShell();
      },
    );
  }
}
