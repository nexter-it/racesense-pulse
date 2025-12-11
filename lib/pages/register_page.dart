import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  DateTime? _birthDate;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi accettare i termini e condizioni'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci la tua data di nascita'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    final age = _calculateAge(_birthDate!);
    if (age < 13) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devi avere almeno 13 anni per registrarti'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = AuthService();
      await authService.registerWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
        _usernameController.text.trim(),
        _birthDate!,
      );

      // Torna al LoginPage, AuthGate rileverà l'autenticazione e reindirizzerà alla home
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: kErrorColor,
          ),
        );
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

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final initial = _birthDate ??
        DateTime(now.year - 18, now.month, now.day); // default 18 anni
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Seleziona la data di nascita',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PulseBackground(
        withTopPadding: true,
        child: SafeArea(
          child: Column(
            children: [
              // Header con back button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: kFgColor),
                    ),
                    const Text(
                      'Crea Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kFgColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Contenuto scrollabile
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),

                        // Logo
                        Center(
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: kBrandColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kBrandColor.withOpacity(0.4),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.flash_on,
                              size: 35,
                              color: Colors.black,
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Nome completo
                        Text(
                          'NOME COMPLETO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kMutedColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          keyboardType: TextInputType.name,
                          textCapitalization: TextCapitalization.words,
                          enabled: !_isLoading,
                          style: const TextStyle(
                            fontSize: 16,
                            color: kFgColor,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Mario Rossi',
                            hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
                            filled: true,
                            fillColor: const Color(0xFF1a1a1a),
                            prefixIcon: const Icon(Icons.person_outline, color: kBrandColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kLineColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kBrandColor, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
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

                        // Username
                        Text(
                          'USERNAME',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kMutedColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _usernameController,
                          enabled: !_isLoading,
                          style: const TextStyle(
                            fontSize: 16,
                            color: kFgColor,
                          ),
                          decoration: InputDecoration(
                            hintText: 'mrossi',
                            hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
                            filled: true,
                            fillColor: const Color(0xFF1a1a1a),
                            prefixIcon: const Icon(Icons.alternate_email, color: kBrandColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kLineColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kBrandColor, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            final sanitized =
                                v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

                        // Data di nascita
                        Text(
                          'DATA DI NASCITA',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kMutedColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _isLoading ? null : _pickBirthDate,
                          child: AbsorbPointer(
                            child: TextFormField(
                              controller: _birthDateController,
                              decoration: InputDecoration(
                                hintText: 'Seleziona la data',
                                hintStyle: TextStyle(
                                    color: kMutedColor.withOpacity(0.5)),
                                filled: true,
                                fillColor: const Color(0xFF1a1a1a),
                                prefixIcon: const Icon(Icons.cake_outlined,
                                    color: kBrandColor),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: kLineColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: kBrandColor, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              validator: (_) {
                                if (_birthDate == null) {
                                  return 'Inserisci la data di nascita';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Email
                        Text(
                          'EMAIL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kMutedColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enabled: !_isLoading,
                          style: const TextStyle(
                            fontSize: 16,
                            color: kFgColor,
                          ),
                          decoration: InputDecoration(
                            hintText: 'nome@example.com',
                            hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
                            filled: true,
                            fillColor: const Color(0xFF1a1a1a),
                            prefixIcon: const Icon(Icons.email_outlined, color: kBrandColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kLineColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kBrandColor, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
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

                        // Password
                        Text(
                          'PASSWORD',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kMutedColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          enabled: !_isLoading,
                          style: const TextStyle(
                            fontSize: 16,
                            color: kFgColor,
                          ),
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
                            filled: true,
                            fillColor: const Color(0xFF1a1a1a),
                            prefixIcon: const Icon(Icons.lock_outline, color: kBrandColor),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: kMutedColor,
                              ),
                              onPressed: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kLineColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kBrandColor, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
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

                        // Conferma Password
                        Text(
                          'CONFERMA PASSWORD',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kMutedColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          enabled: !_isLoading,
                          style: const TextStyle(
                            fontSize: 16,
                            color: kFgColor,
                          ),
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
                            filled: true,
                            fillColor: const Color(0xFF1a1a1a),
                            prefixIcon: const Icon(Icons.lock_outline, color: kBrandColor),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: kMutedColor,
                              ),
                              onPressed: () {
                                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kLineColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kBrandColor, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kErrorColor, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
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

                        const SizedBox(height: 24),

                        // Terms checkbox
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _acceptTerms,
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        setState(() => _acceptTerms = value ?? false);
                                      },
                                activeColor: kBrandColor,
                                checkColor: Colors.black,
                                side: BorderSide(color: kMutedColor),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Wrap(
                                children: [
                                  Text(
                                    'Accetto i ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: kMutedColor,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      // TODO: Mostra termini e condizioni
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Termini e condizioni - da implementare'),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Termini e Condizioni',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: kBrandColor,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    ' e la ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: kMutedColor,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      // TODO: Mostra privacy policy
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Privacy Policy - da implementare'),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Privacy Policy',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: kBrandColor,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Register button
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandColor,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                              shadowColor: kBrandColor.withOpacity(0.4),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                    ),
                                  )
                                : const Text(
                                    'REGISTRATI',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: kLineColor)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OPPURE',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: kMutedColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: kLineColor)),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Social register buttons
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    // TODO: Implementare Google Sign In
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Google Sign In - da implementare'),
                                      ),
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kFgColor,
                              side: const BorderSide(color: kLineColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: Image.asset(
                              'assets/images/google_logo.png',
                              height: 24,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.g_mobiledata, size: 24);
                              },
                            ),
                            label: const Text(
                              'Continua con Google',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    // TODO: Implementare Apple Sign In
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Apple Sign In - da implementare'),
                                      ),
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kFgColor,
                              side: const BorderSide(color: kLineColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.apple, size: 24),
                            label: const Text(
                              'Continua con Apple',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Login link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Hai già un account? ',
                              style: TextStyle(
                                color: kMutedColor,
                                fontSize: 14,
                              ),
                            ),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                    },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Accedi',
                                style: TextStyle(
                                  color: kBrandColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
