import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import 'register_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM UI CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late final AnimationController _logoGlowController;
  late final Animation<double> _logoGlowAnimation;

  @override
  void initState() {
    super.initState();
    _logoGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _logoGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _logoGlowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _logoGlowController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    HapticFeedback.lightImpact();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = AuthService();
      await authService.signInWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
      // Il routing viene gestito automaticamente da AuthGate
      // che controlla anche se l'account è nella lista di eliminazione
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(e.toString());
      }
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

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle_outline, color: kBrandColor, size: 18),
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
          side: BorderSide(color: kBrandColor, width: 0.5),
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
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  _buildLogo(),
                  // const SizedBox(height: 48),
                  _buildWelcomeText(),
                  const SizedBox(height: 40),
                  _buildLoginCard(),
                  const SizedBox(height: 24),
                  _buildDivider(),
                  const SizedBox(height: 24),
                  _buildSocialButtons(),
                  const SizedBox(height: 32),
                  _buildSignUpLink(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: AnimatedBuilder(
        animation: _logoGlowAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: kBrandColor.withOpacity(_logoGlowAnimation.value * 0.4),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/icon/allrspulselogoo.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback al vecchio logo con icona
                  return Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kBrandColor, kBrandColor.withOpacity(0.7)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.flash_on,
                      size: 50,
                      color: Colors.black,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeText() {
    return Column(
      children: [
        const Text(
          'Bentornato',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: kFgColor,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Accedi per continuare a tracciare le tue performance',
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

  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Email field
          _buildInputLabel('EMAIL'),
          const SizedBox(height: 10),
          _buildEmailField(),

          const SizedBox(height: 20),

          // Password field
          _buildInputLabel('PASSWORD'),
          const SizedBox(height: 10),
          _buildPasswordField(),

          const SizedBox(height: 16),

          // Forgot password
          _buildForgotPassword(),

          const SizedBox(height: 28),

          // Login button
          _buildLoginButton(),
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

  Widget _buildEmailField() {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        enabled: !_isLoading,
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'nome@example.com',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.email_outlined, color: kBrandColor, size: 20),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 60),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Inserisci la tua email';
          }
          if (!value.contains('@')) {
            return 'Email non valida';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
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
              child: Icon(Icons.lock_outline, color: kBrandColor, size: 20),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 60),
          suffixIcon: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _obscurePassword = !_obscurePassword);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: kMutedColor,
                size: 22,
              ),
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Inserisci la tua password';
          }
          if (value.length < 6) {
            return 'La password deve essere almeno 6 caratteri';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: _isLoading
            ? null
            : () async {
                HapticFeedback.lightImpact();
                final email = _emailController.text.trim();
                if (email.isEmpty) {
                  _showErrorSnackBar('Inserisci prima la tua email');
                  return;
                }

                try {
                  final authService = AuthService();
                  await authService.sendPasswordResetEmail(email);
                  if (mounted) {
                    _showSuccessSnackBar('Email di recupero inviata!');
                  }
                } catch (e) {
                  if (mounted) {
                    _showErrorSnackBar(e.toString());
                  }
                }
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Text(
            'Password dimenticata?',
            style: TextStyle(
              color: kBrandColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleLogin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isLoading
                ? [kBrandColor.withOpacity(0.5), kBrandColor.withOpacity(0.3)]
                : [kBrandColor, kBrandColor.withOpacity(0.85)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isLoading
              ? []
              : [
                  BoxShadow(
                    color: kBrandColor.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
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
                    const Icon(Icons.login, color: Colors.black, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'ACCEDI',
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
        height: 56,
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

  Widget _buildSignUpLink() {
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
            'Non hai un account? ',
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RegisterPage(),
                      ),
                    );
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Registrati',
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
