import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/pulse_background.dart';
import 'login_page.dart';
import '../main.dart';

/// AuthGate monitora lo stato di autenticazione e mostra
/// LoginPage se l'utente non è autenticato,
/// altrimenti mostra la home dell'app
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Mostra loading mentre controlla lo stato
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: PulseBackground(
              withTopPadding: true,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        // Se c'è un utente autenticato, mostra la home
        if (snapshot.hasData) {
          return const RootShell();
        }

        // Altrimenti mostra il login
        return const LoginPage();
      },
    );
  }
}
