import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/disclaimer_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class DisclaimerPage extends StatefulWidget {
  final String userId;
  final VoidCallback onAccepted;

  const DisclaimerPage({
    super.key,
    required this.userId,
    required this.onAccepted,
  });

  @override
  State<DisclaimerPage> createState() => _DisclaimerPageState();
}

class _DisclaimerPageState extends State<DisclaimerPage>
    with TickerProviderStateMixin {
  bool _acceptResponsibility = false;
  bool _acceptLegalUse = false;
  bool _acceptAccountTermination = false;
  bool _acceptDataCollection = false;
  bool _acceptSafetyWarning = false;
  bool _isLoading = false;

  late final AnimationController _headerController;
  late final Animation<double> _headerAnimation;

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _headerAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _headerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  bool get _allAccepted =>
      _acceptResponsibility &&
      _acceptLegalUse &&
      _acceptAccountTermination &&
      _acceptDataCollection &&
      _acceptSafetyWarning;

  Future<void> _handleConfirm() async {
    if (!_allAccepted) return;

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      await DisclaimerService().setDisclaimerAccepted(widget.userId);
      widget.onAccepted();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildWarningBanner(),
                    const SizedBox(height: 20),
                    _buildDisclaimerCard(),
                    const SizedBox(height: 20),
                    _buildCheckboxesCard(),
                    const SizedBox(height: 28),
                    _buildConfirmButton(),
                    const SizedBox(height: 16),
                    _buildFooterNote(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _headerAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.transparent],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(_headerAnimation.value * 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Icon
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange.withAlpha(60),
                      Colors.orange.withAlpha(30),
                    ],
                  ),
                  border: Border.all(color: Colors.orange.withAlpha(100), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.orange,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Condizioni d\'Uso',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Leggi attentamente e accetta per continuare',
                style: TextStyle(
                  fontSize: 14,
                  color: kMutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.withAlpha(25),
            Colors.orange.withAlpha(10),
          ],
        ),
        border: Border.all(color: Colors.orange.withAlpha(60), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange.withAlpha(30),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Avviso Importante',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Prima di utilizzare RaceSense Pulse, devi leggere e accettare le seguenti condizioni.',
                  style: TextStyle(
                    fontSize: 13,
                    color: kMutedColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kBorderColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: kBrandColor.withAlpha(20),
                  ),
                  child: Icon(Icons.gavel, color: kBrandColor, size: 20),
                ),
                const SizedBox(width: 14),
                const Text(
                  'Disclaimer Legale',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kFgColor,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDisclaimerSection(
                  icon: Icons.security,
                  title: 'Esclusione di Responsabilità',
                  content:
                      'RaceSense Pulse e Nexter S.r.l. non si assumono alcuna responsabilità per danni diretti, indiretti, incidentali o consequenziali derivanti dall\'utilizzo dell\'applicazione. L\'utente utilizza l\'app a proprio rischio e pericolo.',
                ),
                const SizedBox(height: 18),
                _buildDisclaimerSection(
                  icon: Icons.directions_car,
                  title: 'Uso Esclusivo in Circuiti',
                  content:
                      'L\'applicazione è progettata ESCLUSIVAMENTE per l\'uso in circuiti chiusi, piste private e contesti controllati. L\'utilizzo su strade pubbliche è vietato e avviene sotto l\'esclusiva responsabilità dell\'utente.',
                ),
                const SizedBox(height: 18),
                _buildDisclaimerSection(
                  icon: Icons.block,
                  title: 'Attività Illegali',
                  content:
                      'È severamente vietato utilizzare l\'app per organizzare, partecipare o documentare gare illegali, eventi non autorizzati o qualsiasi attività contraria alla legge. L\'uso improprio dell\'app può costituire reato.',
                ),
                const SizedBox(height: 18),
                _buildDisclaimerSection(
                  icon: Icons.person_off,
                  title: 'Sospensione Account',
                  content:
                      'Nexter S.r.l. si riserva il diritto di sospendere o eliminare permanentemente, senza preavviso, gli account che risultino coinvolti in attività illegali o che violino i Termini e Condizioni d\'uso.',
                ),
                const SizedBox(height: 18),
                _buildDisclaimerSection(
                  icon: Icons.health_and_safety,
                  title: 'Sicurezza Personale',
                  content:
                      'Non utilizzare mai l\'applicazione durante la guida attiva. Consultare lo schermo durante la guida può essere pericoloso e illegale. L\'utente è responsabile della propria sicurezza e di quella degli altri.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: _kTileColor,
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kBrandColor, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: kFgColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: kMutedColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxesCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kBorderColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: kPulseColor.withAlpha(20),
                  ),
                  child: Icon(Icons.checklist, color: kPulseColor, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accettazione Condizioni',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: kFgColor,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Seleziona tutte le caselle per continuare',
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Checkboxes
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _buildCheckboxTile(
                  value: _acceptResponsibility,
                  onChanged: (v) => setState(() => _acceptResponsibility = v ?? false),
                  title: 'Esclusione Responsabilità',
                  subtitle:
                      'Comprendo che l\'uso dell\'app è a mio rischio e pericolo e che Nexter S.r.l. non è responsabile per eventuali danni.',
                ),
                const SizedBox(height: 10),
                _buildCheckboxTile(
                  value: _acceptLegalUse,
                  onChanged: (v) => setState(() => _acceptLegalUse = v ?? false),
                  title: 'Uso Lecito',
                  subtitle:
                      'Mi impegno a utilizzare l\'app solo in circuiti autorizzati e per attività legali, mai su strade pubbliche.',
                ),
                const SizedBox(height: 10),
                _buildCheckboxTile(
                  value: _acceptAccountTermination,
                  onChanged: (v) =>
                      setState(() => _acceptAccountTermination = v ?? false),
                  title: 'Sospensione Account',
                  subtitle:
                      'Accetto che il mio account possa essere sospeso o eliminato in caso di violazione delle condizioni d\'uso.',
                ),
                const SizedBox(height: 10),
                _buildCheckboxTile(
                  value: _acceptDataCollection,
                  onChanged: (v) => setState(() => _acceptDataCollection = v ?? false),
                  title: 'Raccolta Dati',
                  subtitle:
                      'Accetto la raccolta dei dati GPS e telemetrici secondo la Privacy Policy dell\'applicazione.',
                ),
                const SizedBox(height: 10),
                _buildCheckboxTile(
                  value: _acceptSafetyWarning,
                  onChanged: (v) => setState(() => _acceptSafetyWarning = v ?? false),
                  title: 'Sicurezza alla Guida',
                  subtitle:
                      'Mi impegno a non consultare l\'app durante la guida attiva per garantire la mia sicurezza e quella degli altri.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String title,
    required String subtitle,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? kBrandColor.withAlpha(10) : _kTileColor,
          border: Border.all(
            color: value ? kBrandColor.withAlpha(60) : _kBorderColor,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: value
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kBrandColor, kBrandColor.withOpacity(0.7)],
                      )
                    : null,
                color: value ? null : _kTileColor,
                border: Border.all(
                  color: value ? kBrandColor : _kBorderColor,
                  width: 1.5,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, color: Colors.black, size: 18)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: value ? kFgColor : kMutedColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: kMutedColor.withOpacity(0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return GestureDetector(
      onTap: _allAccepted && !_isLoading ? _handleConfirm : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _allAccepted
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kBrandColor, kBrandColor.withOpacity(0.8)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kCardStart, _kCardEnd],
                ),
          border: Border.all(
            color: _allAccepted ? kBrandColor : _kBorderColor,
            width: 1.5,
          ),
          boxShadow: _allAccepted
              ? [
                  BoxShadow(
                    color: kBrandColor.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _allAccepted ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _allAccepted ? Colors.black : kMutedColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _allAccepted ? 'ACCETTA E CONTINUA' : 'SELEZIONA TUTTE LE CASELLE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: _allAccepted ? Colors.black : kMutedColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFooterNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _kTileColor,
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: kMutedColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Accettando queste condizioni dichiari di aver letto e compreso i Termini e Condizioni e la Privacy Policy di RaceSense Pulse.',
              style: TextStyle(
                fontSize: 11,
                color: kMutedColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
