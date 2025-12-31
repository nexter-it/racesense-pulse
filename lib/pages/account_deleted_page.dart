import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);

/// Pagina mostrata quando un utente tenta di accedere con un account
/// che ha richiesto l'eliminazione dei dati.
class AccountDeletedPage extends StatelessWidget {
  final VoidCallback? onBackToLogin;

  const AccountDeletedPage({super.key, this.onBackToLogin});

  void _handleBackToLogin() {
    HapticFeedback.mediumImpact();
    onBackToLogin?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                _buildIcon(),
                const SizedBox(height: 32),
                _buildTitle(),
                const SizedBox(height: 40),
                _buildInfoCard(),
                const SizedBox(height: 32),
                _buildContactSection(),
                const SizedBox(height: 40),
                _buildLogoutButton(context),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              kErrorColor.withAlpha(40),
              kErrorColor.withAlpha(20),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kErrorColor.withAlpha(80), width: 2),
          boxShadow: [
            BoxShadow(
              color: kErrorColor.withAlpha(40),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.person_off_rounded,
            color: kErrorColor,
            size: 48,
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          'Account in eliminazione',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: kFgColor,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Non puoi accedere a questo account',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: kMutedColor,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            kMutedColor.withAlpha(30),
                            kMutedColor.withAlpha(15),
                          ],
                        ),
                        border: Border.all(color: kMutedColor.withAlpha(60)),
                      ),
                      child: const Center(
                        child: Icon(Icons.info_outline, color: kMutedColor, size: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Cosa significa?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: kFgColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Il tuo account risulta nella lista degli utenti che hanno richiesto l\'eliminazione dei propri dati.',
                  style: TextStyle(
                    color: kFgColor,
                    fontSize: 14,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: kErrorColor.withAlpha(10),
                    border: Border.all(color: kErrorColor.withAlpha(40)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: kErrorColor, size: 18),
                          const SizedBox(width: 10),
                          const Text(
                            'Stato richiesta',
                            style: TextStyle(
                              color: kErrorColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'La tua richiesta di eliminazione account è in fase di elaborazione. '
                        'Durante questo periodo non è possibile accedere all\'account.',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(4),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: const Border(
                top: BorderSide(color: _kBorderColor),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: kMutedColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'L\'eliminazione può richiedere fino a 30 giorni',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kBrandColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor.withAlpha(30),
                      kBrandColor.withAlpha(15),
                    ],
                  ),
                  border: Border.all(color: kBrandColor.withAlpha(60)),
                ),
                child: const Center(
                  child: Icon(Icons.support_agent, color: kBrandColor, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Hai bisogno di aiuto?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kFgColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Se hai cambiato idea o hai bisogno di assistenza, contatta il nostro supporto.',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: kBrandColor.withAlpha(15),
              border: Border.all(color: kBrandColor.withAlpha(50)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.email_outlined, color: kBrandColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  'support@racesense.app',
                  style: TextStyle(
                    color: kBrandColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return GestureDetector(
      onTap: _handleBackToLogin,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kMutedColor.withAlpha(30),
              kMutedColor.withAlpha(15),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderColor),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, color: kMutedColor, size: 20),
              const SizedBox(width: 10),
              Text(
                'TORNA AL LOGIN',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kMutedColor,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
