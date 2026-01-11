import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'theme.dart';
import 'firebase_options.dart';
import 'pages/feed_page.dart';
import 'pages/profile_page.dart';
import 'pages/new_post_page.dart'; // Usato nel RootShell
import 'pages/activity_detail_page.dart';
import 'pages/auth_gate.dart';
import 'pages/search_page.dart';
import 'pages/splash_screen.dart';
import 'pages/events_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM NAV BAR CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kNavBgColor = Color(0xFF0A0A0A);
const Color _kNavBorderColor = Color(0xFF1A1A1A);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inizializza locale italiano per DateFormat
  await initializeDateFormatting('it_IT', null);

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase init failed, app continuerà offline: $e');
  }
  runApp(const RacesensePulseApp());
}

class RacesensePulseApp extends StatelessWidget {
  const RacesensePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Racesense Pulse',
      debugShowCheckedModeBanner: false,
      theme: buildPulseTheme(),
      home: const SplashScreen(
        nextPage: AuthGate(), // Mostra splash screen poi va all'AuthGate
      ),
      routes: {
        ActivityDetailPage.routeName: (_) => const ActivityDetailPage(),
        // NOTA: NewPostPage NON deve essere qui perché è già gestita nel RootShell
        // come tab della bottom navigation. Averla anche come route causava
        // problemi di navigazione (flash della FeedPage quando si tornava indietro).
      },
    );
  }
}

/// Shell con bottom navigation stile Strava: Feed / Eventi / Nuova / Cerca / Profilo
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Cache delle pagine già visitate (lazy loading)
  final Map<int, Widget> _cachedPages = {};

  // Factory per creare le pagine
  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const FeedPage();
      case 1:
        return const EventsPage();
      case 2:
        return const NewPostPage();
      case 3:
        return const SearchPage();
      case 4:
        return const ProfilePage();
      default:
        return const FeedPage();
    }
  }

  // Ottieni la pagina (dalla cache o creala)
  Widget _getPage(int index) {
    if (!_cachedPages.containsKey(index)) {
      _cachedPages[index] = _buildPage(index);
    }
    return _cachedPages[index]!;
  }

  @override
  Widget build(BuildContext context) {
    // Costruisci solo le pagine già visitate + quella corrente
    final List<Widget> stackChildren = [];
    for (int i = 0; i < 5; i++) {
      if (_cachedPages.containsKey(i) || i == _index) {
        stackChildren.add(_getPage(i));
      } else {
        // Placeholder vuoto per le pagine non ancora visitate
        stackChildren.add(const SizedBox.shrink());
      }
    }

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: stackChildren,
        ),
      ),
      bottomNavigationBar: _buildPremiumNavBar(),
    );
  }

  Widget _buildPremiumNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: _kNavBgColor,
        border: const Border(
          top: BorderSide(color: _kNavBorderColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home_rounded),
              _buildNavItem(1, Icons.event_outlined, Icons.event),
              _buildCenterNavItem(),
              _buildNavItem(3, Icons.search_outlined, Icons.search),
              _buildNavItem(4, Icons.person_outline, Icons.person),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon) {
    final isSelected = _index == index;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _index = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected ? kBrandColor.withAlpha(15) : Colors.transparent,
          border: Border.all(
            color: isSelected ? kBrandColor.withAlpha(40) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected ? kBrandColor : kMutedColor,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildCenterNavItem() {
    final isSelected = _index == 2;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        setState(() => _index = 2);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isSelected
                ? [kBrandColor, kBrandColor.withAlpha(200)]
                : [kBrandColor.withAlpha(30), kBrandColor.withAlpha(15)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: kBrandColor.withAlpha(isSelected ? 255 : 80),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: kBrandColor.withAlpha(isSelected ? 80 : 30),
              blurRadius: isSelected ? 16 : 8,
              spreadRadius: isSelected ? 2 : 0,
            ),
          ],
        ),
        child: Icon(
          Icons.add_rounded,
          color: isSelected ? Colors.black : kBrandColor,
          size: 28,
        ),
      ),
    );
  }
}
