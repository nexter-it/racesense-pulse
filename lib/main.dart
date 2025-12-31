import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme.dart';
import 'firebase_options.dart';
import 'pages/feed_page.dart';
import 'pages/profile_page.dart';
import 'pages/new_post_page.dart'; // Usato nel RootShell
import 'pages/activity_detail_page.dart';
import 'pages/auth_gate.dart';
import 'pages/search_page.dart';
import 'pages/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

/// Shell con bottom navigation stile Strava: Feed / Nuova / Profilo
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
        return const SearchPage();
      case 2:
        return const NewPostPage();
      case 3:
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
    for (int i = 0; i < 4; i++) {
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        backgroundColor: const Color(0xFF040404),
        selectedItemColor: kBrandColor,
        unselectedItemColor: kMutedColor,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.timeline_outlined),
            activeIcon: Icon(Icons.timeline),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Cerca',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'Nuova',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profilo',
          ),
        ],
      ),
    );
  }
}
