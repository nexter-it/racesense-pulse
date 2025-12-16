import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme.dart';
import 'firebase_options.dart';
import 'pages/feed_page.dart';
import 'pages/profile_page.dart';
import 'pages/new_post_page.dart';
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
        NewPostPage.routeName: (_) => const NewPostPage(),
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FeedPage(),
      const SearchPage(),
      const NewPostPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: pages[_index],
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
