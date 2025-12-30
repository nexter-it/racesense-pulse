import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../services/version_check_service.dart';
import '../services/feed_cache_service.dart';
import '../services/profile_cache_service.dart';
import '../widgets/pulse_background.dart';
import 'privacy_policy_page.dart';

class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  Future<void> _showLogoutDialog(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(color: kFgColor, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Sei sicuro di voler uscire dal tuo account?',
          style: TextStyle(color: kMutedColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla', style: TextStyle(color: kMutedColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Esci', style: TextStyle(color: kErrorColor)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      // Cancella la cache locale prima del logout
      await FeedCacheService().clearCache();
      await ProfileCacheService().clearCache();

      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kMutedColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: kMutedColor, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Elimina Account',
              style: TextStyle(color: kFgColor, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sei sicuro di voler eliminare il tuo account?',
              style: TextStyle(color: kFgColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kMutedColor.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kMutedColor.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Questa azione comporta:',
                    style: TextStyle(
                      color: kFgColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '\u2022 Eliminazione di tutte le tue sessioni\n'
                    '\u2022 Eliminazione dei dati del profilo\n'
                    '\u2022 Rimozione dai follower/following\n'
                    '\u2022 Eliminazione permanente dell\'account',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Questa azione non e\' reversibile.',
              style: TextStyle(
                color: kMutedColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla', style: TextStyle(color: kMutedColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina Account',
                style: TextStyle(color: kBrandColor)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      // TODO: Implementare eliminazione account quando richiesto
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Funzionalita\' in arrivo. Contatta il supporto per eliminare l\'account.'),
            backgroundColor: kPulseColor,
          ),
        );
      }
    }
  }

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PrivacyPolicyPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withAlpha(20)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: kFgColor, size: 18),
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Info App',
                  style: TextStyle(
                    color: kFgColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Logo e info app
                _buildAppInfoCard(),
                const SizedBox(height: 20),

                // Azienda
                _buildCompanyCard(),
                const SizedBox(height: 20),

                // Privacy
                _buildActionCard(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: kPulseColor,
                  title: 'Privacy Policy',
                  subtitle: 'Leggi la nostra informativa sulla privacy',
                  onTap: () => _openPrivacyPolicy(context),
                ),
                const SizedBox(height: 12),

                // Logout
                _buildActionCard(
                  icon: Icons.logout,
                  iconColor: kBrandColor,
                  title: 'Esci dall\'account',
                  subtitle: 'Disconnettiti da RaceSense Pulse',
                  onTap: () => _showLogoutDialog(context),
                ),
                const SizedBox(height: 12),

                // Elimina account
                _buildActionCard(
                  icon: Icons.delete_forever,
                  iconColor: kMutedColor,
                  title: 'Elimina Account',
                  subtitle: 'Rimuovi definitivamente il tuo account',
                  onTap: () => _showDeleteAccountDialog(context),
                ),

                const SizedBox(height: 32),

                // Footer
                Center(
                  child: Text(
                    'Made with passion by Nexter S.r.l.',
                    style: TextStyle(
                      color: kMutedColor.withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildAppInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A20).withAlpha(255),
            const Color(0xFF0F0F15).withAlpha(255),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(140),
            blurRadius: 16,
            spreadRadius: -3,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kBrandColor.withAlpha(80),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/icon/RPICON.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Nome app
          const Text(
            'RaceSense Pulse',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Versione
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: kBrandColor.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kBrandColor.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: kBrandColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Versione $appVersion',
                  style: const TextStyle(
                    color: kBrandColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Descrizione
          Text(
            'La tua app per il tracking delle performance in pista. '
            'Registra le tue sessioni, analizza i tempi e condividi con la community.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A20).withAlpha(255),
            const Color(0xFF0F0F15).withAlpha(255),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 12,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(30),
                  kPulseColor.withAlpha(20),
                ],
              ),
              border: Border.all(color: kPulseColor.withAlpha(100), width: 1),
            ),
            child: const Icon(Icons.business, color: kPulseColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sviluppato da',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Nexter S.r.l.',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Innovazione per il motorsport',
                  style: TextStyle(
                    color: kMutedColor.withAlpha(180),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: isDanger
                  ? [
                      kErrorColor.withAlpha(15),
                      kErrorColor.withAlpha(8),
                    ]
                  : [
                      const Color(0xFF1A1A20).withAlpha(255),
                      const Color(0xFF0F0F15).withAlpha(255),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: isDanger ? kErrorColor.withAlpha(60) : kLineColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: iconColor.withAlpha(25),
                  border: Border.all(color: iconColor.withAlpha(100), width: 1),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.3,
                        color: isDanger ? kErrorColor : kFgColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDanger ? kErrorColor : kMutedColor,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
