import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';

/// Pagina Cerca - Mock UI (solo grafica, nessuna logica)
/// Funzionalità future:
/// - Ricerca utenti
/// - Ricerca circuiti
/// - Filtro per paese
/// - Mappa con tutti i circuiti della piattaforma (OpenStreetMap)
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Search bar
          _buildSearchBar(),

          // Tabs
          _buildTabs(),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildCircuitsTab(),
                _buildCountriesTab(),
                _buildMapTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text(
            'CERCA',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              // Future: filtri avanzati
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 16, color: kFgColor),
        decoration: InputDecoration(
          hintText: 'Cerca utenti, circuiti, paesi...',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
          prefixIcon: const Icon(Icons.search, color: kBrandColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: kMutedColor),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF0d0d0d),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kBrandColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d0d),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kLineColor),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: const BoxDecoration(),
        labelColor: kBrandColor,
        unselectedLabelColor: kMutedColor,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'UTENTI'),
          Tab(text: 'CIRCUITI'),
          Tab(text: 'PAESI'),
          Tab(icon: Icon(Icons.map_outlined, size: 20)),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Utenti popolari',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 16),
        ..._mockUsers.map((user) => _buildUserCard(user)),
      ],
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: kBrandColor.withOpacity(0.2),
            child: Text(
              user['initials'],
              style: const TextStyle(
                color: kBrandColor,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user['sessions']} sessioni · ${user['distance']} km',
                  style: const TextStyle(fontSize: 12, color: kMutedColor),
                ),
              ],
            ),
          ),

          // Follow button
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBrandColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Segui',
              style: TextStyle(
                color: kBrandColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Circuiti più popolari',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 16),
        ..._mockCircuits.map((circuit) => _buildCircuitCard(circuit)),
      ],
    );
  }

  Widget _buildCircuitCard(Map<String, dynamic> circuit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kBrandColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBrandColor.withOpacity(0.3)),
                ),
                child: const Icon(Icons.track_changes, color: kBrandColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      circuit['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 12, color: kMutedColor),
                        const SizedBox(width: 4),
                        Text(
                          circuit['location'],
                          style: const TextStyle(fontSize: 12, color: kMutedColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildCircuitStat('Lunghezza', circuit['length']),
              _buildCircuitStat('Sessioni', circuit['sessions']),
              _buildCircuitStat('Record', circuit['record']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: kBrandColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: kMutedColor.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildCountriesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Esplora per paese',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 16),
        ..._mockCountries.map((country) => _buildCountryCard(country)),
      ],
    );
  }

  Widget _buildCountryCard(Map<String, dynamic> country) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF10121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        children: [
          // Flag placeholder
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kBrandColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                country['flag'],
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  country['name'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${country['circuits']} circuiti · ${country['users']} utenti',
                  style: const TextStyle(fontSize: 12, color: kMutedColor),
                ),
              ],
            ),
          ),

          const Icon(Icons.arrow_forward_ios, size: 16, color: kMutedColor),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF10121A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kLineColor),
              ),
              child: Stack(
                children: [
                  // Map placeholder
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.map_outlined,
                          size: 80,
                          color: kMutedColor.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Mappa Circuiti',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kMutedColor.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'OpenStreetMap integration\nProximamente disponibile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: kMutedColor.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Map controls overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        _buildMapButton(Icons.add),
                        const SizedBox(height: 8),
                        _buildMapButton(Icons.remove),
                        const SizedBox(height: 8),
                        _buildMapButton(Icons.my_location),
                      ],
                    ),
                  ),

                  // Legend overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000).withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kLineColor.withOpacity(0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLegendItem(Colors.greenAccent, 'Circuiti verificati'),
                          const SizedBox(height: 6),
                          _buildLegendItem(Colors.blueAccent, 'Circuiti community'),
                          const SizedBox(height: 6),
                          _buildLegendItem(kBrandColor, 'Le mie sessioni'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kLineColor),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: kFgColor,
        onPressed: () {
          // Future: map controls
        },
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: kFgColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// Mock data
final _mockUsers = [
  {'initials': 'LH', 'name': 'Lewis Hamilton', 'sessions': 142, 'distance': 2840},
  {'initials': 'MV', 'name': 'Max Verstappen', 'sessions': 128, 'distance': 2560},
  {'initials': 'CF', 'name': 'Charles Leclerc', 'sessions': 95, 'distance': 1900},
  {'initials': 'LN', 'name': 'Lando Norris', 'sessions': 87, 'distance': 1740},
  {'initials': 'SA', 'name': 'Sebastian Alonso', 'sessions': 76, 'distance': 1520},
];

final _mockCircuits = [
  {
    'name': 'Monza',
    'location': 'Italia',
    'length': '5.8 km',
    'sessions': '1.2k',
    'record': '1:21.046',
  },
  {
    'name': 'Mugello',
    'location': 'Italia',
    'length': '5.2 km',
    'sessions': '890',
    'record': '1:15.144',
  },
  {
    'name': 'Misano',
    'location': 'Italia',
    'length': '4.2 km',
    'sessions': '756',
    'record': '1:31.137',
  },
  {
    'name': 'Spa-Francorchamps',
    'location': 'Belgio',
    'length': '7.0 km',
    'sessions': '2.1k',
    'record': '1:41.252',
  },
];

final _mockCountries = [
  {'flag': '🇮🇹', 'name': 'Italia', 'circuits': 24, 'users': 3420},
  {'flag': '🇩🇪', 'name': 'Germania', 'circuits': 18, 'users': 2840},
  {'flag': '🇫🇷', 'name': 'Francia', 'circuits': 16, 'users': 2310},
  {'flag': '🇬🇧', 'name': 'Regno Unito', 'circuits': 22, 'users': 4100},
  {'flag': '🇪🇸', 'name': 'Spagna', 'circuits': 14, 'users': 1980},
];
