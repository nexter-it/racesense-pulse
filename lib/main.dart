import 'package:flutter/material.dart';
import 'theme.dart';
import 'pages/feed_page.dart';
import 'pages/profile_page.dart';
import 'pages/new_post_page.dart';
import 'pages/activity_detail_page.dart';

void main() {
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
      home: const _RootShell(),
      routes: {
        ActivityDetailPage.routeName: (_) => const ActivityDetailPage(),
        NewPostPage.routeName: (_) => const NewPostPage(),
      },
    );
  }
}

/// Shell con bottom navigation stile Strava: Feed / Nuova / Profilo
class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FeedPage(),
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
