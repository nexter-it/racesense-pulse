import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'privacy_policy_page.dart';
import 'terms_conditions_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM UI CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _referralController = TextEditingController();
  DateTime? _birthDate;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;

  late final AnimationController _headerGlowController;
  late final Animation<double> _headerGlowAnimation;

  @override
  void initState() {
    super.initState();
    _headerGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _headerGlowAnimation = Tween<double>(begin: 0.2, end: 0.5).animate(
      CurvedAnimation(parent: _headerGlowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _headerGlowController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _birthDateController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    HapticFeedback.lightImpact();
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptTerms) {
      _showErrorSnackBar('Devi accettare i termini e condizioni');
      return;
    }

    // Validate and parse birth date from text
    final birthDateText = _birthDateController.text.trim();
    if (birthDateText.isEmpty) {
      _showErrorSnackBar('Inserisci la tua data di nascita');
      return;
    }

    final parsedDate = _parseBirthDate(birthDateText);
    if (parsedDate == null) {
      _showErrorSnackBar('Formato data non valido. Usa dd/mm/yyyy');
      return;
    }

    // Check if date is in the future
    if (parsedDate.isAfter(DateTime.now())) {
      _showErrorSnackBar('La data di nascita non può essere nel futuro');
      return;
    }

    final age = _calculateAge(parsedDate);
    if (age < 13) {
      _showErrorSnackBar('Devi avere almeno 13 anni per registrarti');
      return;
    }

    _birthDate = parsedDate;

    setState(() => _isLoading = true);

    try {
      final authService = AuthService();
      String? referrerId;
      String? referralCode;
      final rawReferral = _referralController.text.trim();
      if (rawReferral.isNotEmpty) {
        final clean = FirestoreService().sanitizeAffiliateCode(rawReferral);
        if (clean.isEmpty) {
          throw 'Codice affiliazione non valido';
        }
        referralCode = clean;
        referrerId = await FirestoreService().getAffiliateOwnerUserId(clean);
        if (referrerId == null) {
          throw 'Codice affiliazione non valido';
        }
      }

      await authService.registerWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
        _usernameController.text.trim(),
        _birthDate!,
        referralCode: referralCode,
        referrerUserId: referrerId,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(e.toString());
      }
    }
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  DateTime? _parseBirthDate(String text) {
    if (text.length != 10) return null;

    final parts = text.split('/');
    if (parts.length != 3) return null;

    try {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      // Validate ranges
      if (day < 1 || day > 31) return null;
      if (month < 1 || month > 12) return null;
      if (year < 1900 || year > DateTime.now().year) return null;

      // Try to create the date (will throw if invalid like 31/02/2000)
      final date = DateTime(year, month, day);

      // Verify the date components match (handles invalid dates like 30/02)
      if (date.day != day || date.month != month || date.year != year) {
        return null;
      }

      return date;
    } catch (e) {
      return null;
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.red, width: 0.5),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      _buildProgressIndicator(),
                      const SizedBox(height: 28),
                      _buildPersonalInfoCard(),
                      const SizedBox(height: 20),
                      _buildCredentialsCard(),
                      const SizedBox(height: 20),
                      _buildReferralCard(),
                      const SizedBox(height: 20),
                      _buildTermsCard(),
                      const SizedBox(height: 28),
                      _buildRegisterButton(),
                      const SizedBox(height: 20),
                      _buildDivider(),
                      const SizedBox(height: 20),
                      _buildSocialButtons(),
                      const SizedBox(height: 24),
                      _buildLoginLink(),
                      const SizedBox(height: 32),
                    ],
                  ),
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
      animation: _headerGlowAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _kCardStart,
                _kBgColor,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: kBrandColor.withOpacity(_headerGlowAnimation.value * 0.1),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kTileColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderColor, width: 1),
                  ),
                  child: const Icon(Icons.arrow_back, color: kFgColor, size: 22),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crea Account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: kFgColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Inizia a tracciare le tue performance',
                      style: TextStyle(
                        fontSize: 13,
                        color: kMutedColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kBrandColor, kBrandColor.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.flash_on, color: Colors.black, size: 22),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Row(
        children: [
          _buildProgressStep(1, 'Info', true),
          _buildProgressLine(true),
          _buildProgressStep(2, 'Credenziali', true),
          _buildProgressLine(false),
          _buildProgressStep(3, 'Conferma', false),
        ],
      ),
    );
  }

  Widget _buildProgressStep(int step, String label, bool active) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kBrandColor, kBrandColor.withOpacity(0.7)],
                    )
                  : null,
              color: active ? null : _kTileColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? kBrandColor : _kBorderColor,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                '$step',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.black : kMutedColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? kFgColor : kMutedColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressLine(bool active) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [kBrandColor, kBrandColor.withOpacity(0.3)]
                : [_kBorderColor, _kBorderColor],
          ),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return _buildSectionCard(
      icon: Icons.person_outline,
      title: 'Informazioni Personali',
      children: [
        _buildInputLabel('NOME COMPLETO'),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _nameController,
          hint: 'Mario Rossi',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Inserisci il tuo nome';
            }
            if (value.length < 3) {
              return 'Il nome deve essere almeno 3 caratteri';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildInputLabel('USERNAME'),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _usernameController,
          hint: 'mrossi',
          icon: Icons.alternate_email,
          validator: (value) {
            final v = value?.trim() ?? '';
            final sanitized = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (sanitized.isEmpty) {
              return 'Usa solo lettere e numeri';
            }
            if (sanitized.length < 3) {
              return 'Minimo 3 caratteri';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildInputLabel('DATA DI NASCITA'),
        const SizedBox(height: 10),
        _buildDateField(),
      ],
    );
  }

  Widget _buildCredentialsCard() {
    return _buildSectionCard(
      icon: Icons.security,
      title: 'Credenziali',
      children: [
        _buildInputLabel('EMAIL'),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _emailController,
          hint: 'nome@example.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Inserisci la tua email';
            }
            if (!value.contains('@') || !value.contains('.')) {
              return 'Email non valida';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildInputLabel('PASSWORD'),
        const SizedBox(height: 10),
        _buildPasswordField(
          controller: _passwordController,
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Inserisci una password';
            }
            if (value.length < 8) {
              return 'La password deve essere almeno 8 caratteri';
            }
            if (!value.contains(RegExp(r'[A-Z]'))) {
              return 'Deve contenere almeno una maiuscola';
            }
            if (!value.contains(RegExp(r'[0-9]'))) {
              return 'Deve contenere almeno un numero';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildInputLabel('CONFERMA PASSWORD'),
        const SizedBox(height: 10),
        _buildPasswordField(
          controller: _confirmPasswordController,
          obscure: _obscureConfirmPassword,
          onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Conferma la tua password';
            }
            if (value != _passwordController.text) {
              return 'Le password non corrispondono';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildReferralCard() {
    return _buildSectionCard(
      icon: Icons.card_giftcard,
      title: 'Codice Affiliazione',
      subtitle: 'Opzionale',
      children: [
        _buildInputLabel('CODICE'),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _referralController,
          hint: 'ES: RSPULSE23',
          icon: Icons.loyalty_outlined,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kBrandColor.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBrandColor.withAlpha(30), width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: kBrandColor, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Inserisci un codice amico per ottenere vantaggi esclusivi',
                  style: TextStyle(
                    fontSize: 12,
                    color: kBrandColor.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _isLoading
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _acceptTerms = !_acceptTerms);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: _acceptTerms
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kBrandColor, kBrandColor.withOpacity(0.7)],
                      )
                    : null,
                color: _acceptTerms ? null : _kTileColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _acceptTerms ? kBrandColor : _kBorderColor,
                  width: 1.5,
                ),
              ),
              child: _acceptTerms
                  ? const Icon(Icons.check, color: Colors.black, size: 18)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(
              children: [
                Text(
                  'Accetto i ',
                  style: TextStyle(
                    fontSize: 14,
                    color: kMutedColor,
                    height: 1.5,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TermsConditionsPage()),
                    );
                  },
                  child: Text(
                    'Termini e Condizioni',
                    style: TextStyle(
                      fontSize: 14,
                      color: kBrandColor,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: kBrandColor,
                      height: 1.5,
                    ),
                  ),
                ),
                Text(
                  ' e la ',
                  style: TextStyle(
                    fontSize: 14,
                    color: kMutedColor,
                    height: 1.5,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                    );
                  },
                  child: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 14,
                      color: kBrandColor,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: kBrandColor,
                      height: 1.5,
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

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kBorderColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: kBrandColor, size: 20),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kFgColor,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Section content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: kMutedColor,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        autocorrect: false,
        enabled: !_isLoading,
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: kBrandColor, size: 18),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildDateField() {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: _birthDateController,
        keyboardType: TextInputType.number,
        enabled: !_isLoading,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          _DateInputFormatter(),
        ],
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'dd/mm/yyyy',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.cake_outlined, color: kBrandColor, size: 18),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          suffixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.calendar_today, color: kMutedColor, size: 20),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Inserisci la data di nascita';
          }
          if (value.length != 10) {
            return 'Formato: dd/mm/yyyy';
          }
          final parsed = _parseBirthDate(value);
          if (parsed == null) {
            return 'Data non valida';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        enabled: !_isLoading,
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: '••••••••',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.lock_outline, color: kBrandColor, size: 18),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          suffixIcon: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onToggle();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: kMutedColor,
                size: 22,
              ),
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildRegisterButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleRegister,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isLoading
                ? [kBrandColor.withOpacity(0.5), kBrandColor.withOpacity(0.3)]
                : [kBrandColor, kBrandColor.withOpacity(0.85)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isLoading
              ? []
              : [
                  BoxShadow(
                    color: kBrandColor.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_add, color: Colors.black, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'CREA ACCOUNT',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, _kBorderColor],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: _kCardStart,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorderColor, width: 1),
          ),
          child: Text(
            'OPPURE',
            style: TextStyle(
              fontSize: 11,
              color: kMutedColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kBorderColor, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButtons() {
    return Column(
      children: [
        _buildSocialButton(
          icon: Image.asset(
            'assets/images/google_logo.png',
            height: 22,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.g_mobiledata, size: 24, color: kFgColor);
            },
          ),
          label: 'Continua con Google',
          onTap: () {
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google Sign In - da implementare')),
            );
          },
        ),
        // const SizedBox(height: 14),
        // _buildSocialButton(
        //   icon: const Icon(Icons.apple, size: 24, color: kFgColor),
        //   label: 'Continua con Apple',
        //   onTap: () {
        //     HapticFeedback.lightImpact();
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(content: Text('Apple Sign In - da implementare')),
        //     );
        //   },
        // ),
      ],
    );
  }

  Widget _buildSocialButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kCardStart, _kCardEnd],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderColor, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: kFgColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Hai già un account? ',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          GestureDetector(
            onTap: _isLoading
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Accedi',
                style: TextStyle(
                  color: kBrandColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom input formatter for dd/mm/yyyy format
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Remove any non-digits
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limit to 8 digits (ddmmyyyy)
    final limitedDigits = digitsOnly.substring(0, digitsOnly.length > 8 ? 8 : digitsOnly.length);

    // Build formatted string
    final buffer = StringBuffer();
    for (int i = 0; i < limitedDigits.length; i++) {
      if (i == 2 || i == 4) {
        buffer.write('/');
      }
      buffer.write(limitedDigits[i]);
    }

    final formattedText = buffer.toString();

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
