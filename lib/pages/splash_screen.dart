import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import '../services/feed_cache_service.dart';
import '../services/profile_cache_service.dart';
import '../services/version_check_service.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextPage;

  const SplashScreen({super.key, required this.nextPage});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  bool _showUpdateBanner = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Fade in: da 0 a 1
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Scale: da 0.5 a 1.0 con rimbalzo
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    // Glow: pulsa da 0 a 40 e ritorno
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 40.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 40.0, end: 20.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Avvia animazione
    _controller.forward();

    // Inizializza cache e naviga alla prossima schermata
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    // Inizializza le cache in parallelo con l'animazione
    final feedCacheService = FeedCacheService();
    final profileCacheService = ProfileCacheService();
    final versionCheckService = VersionCheckService();

    await Future.wait([
      feedCacheService.initialize(),
      profileCacheService.initialize(),
    ]);
    print('✅ Cache inizializzate (feed + profilo)');

    // Controlla versione app
    final needsUpdate = await versionCheckService.needsUpdate();
    if (needsUpdate) {
      print('⚠️ App deve essere aggiornata!');
      if (mounted) {
        setState(() {
          _showUpdateBanner = true;
        });
      }
      return; // Non navigare, mostra banner bloccante
    }

    // Aspetta almeno 2.5 secondi per l'animazione
    await Future.delayed(const Duration(milliseconds: 2500));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              widget.nextPage,
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openStore() async {
    // URL per App Store e Play Store
    final Uri storeUrl;
    if (Platform.isIOS) {
      // Sostituisci con il tuo App Store URL
      storeUrl = Uri.parse('https://apps.apple.com/app/racesense-pulse/id123456789');
    } else {
      // Sostituisci con il tuo Play Store URL
      storeUrl = Uri.parse('https://play.google.com/store/apps/details?id=com.racesense.pulse');
    }

    if (await canLaunchUrl(storeUrl)) {
      await launchUrl(storeUrl, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildUpdateBanner() {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo con glow
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kBrandColor.withOpacity(0.6),
                        blurRadius: 30,
                        spreadRadius: 10,
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
                const SizedBox(height: 48),

                // Icona aggiornamento
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kBrandColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kBrandColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.system_update,
                    size: 48,
                    color: kBrandColor,
                  ),
                ),
                const SizedBox(height: 32),

                // Titolo
                const Text(
                  'Aggiornamento Disponibile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Descrizione
                Text(
                  'È disponibile una nuova versione di RaceSense Pulse.\nAggiorna l\'app per continuare ad utilizzarla.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Versione corrente
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Versione attuale: $appVersion',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // Bottone aggiorna
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openStore,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      shadowColor: kBrandColor.withOpacity(0.4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download, size: 22),
                        SizedBox(width: 12),
                        Text(
                          'AGGIORNA ORA',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Se deve mostrare il banner di aggiornamento, mostra solo quello
    if (_showUpdateBanner) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildUpdateBanner(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(
                            255, 192, 255, 3), // Brand color
                        blurRadius: _glowAnimation.value,
                        spreadRadius: _glowAnimation.value * 0.3,
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
              ),
            );
          },
        ),
      ),
    );
  }
}
