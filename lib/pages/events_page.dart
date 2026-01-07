import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import 'create_event_page.dart';
import 'event_detail_page.dart';

// Premium UI constants
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage>
    with SingleTickerProviderStateMixin {
  final EventService _eventService = EventService();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  String _searchQuery = '';
  bool _isVerifiedCreator = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkVerifiedCreator();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkVerifiedCreator() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final isVerified = await _eventService.isUserVerifiedCreator(userId);
    if (mounted) {
      setState(() {
        _isVerifiedCreator = isVerified;
      });
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
            _buildSearchBar(),
            _buildTabs(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEventsList(showPast: false),
                  _buildEventsList(showPast: true),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isVerifiedCreator ? _buildCreateEventFAB() : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  Colors.amber.withAlpha(40),
                  Colors.amber.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.amber.withAlpha(80), width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.event, color: Colors.amber, size: 26),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eventi',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Scopri e partecipa agli eventi racing',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: kFgColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Cerca eventi...',
          hintStyle: TextStyle(color: kMutedColor, fontSize: 15),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.search, color: kMutedColor, size: 22),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: kMutedColor, size: 20),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: kBrandColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)],
          ),
          border: Border.all(color: kBrandColor, width: 1.5),
        ),
        labelColor: kBrandColor,
        unselectedLabelColor: kMutedColor,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'PROSSIMI'),
          Tab(text: 'PASSATI'),
        ],
      ),
    );
  }

  Widget _buildEventsList({required bool showPast}) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Center(
        child: Text(
          'Effettua il login per vedere gli eventi',
          style: TextStyle(color: kMutedColor),
        ),
      );
    }

    return StreamBuilder<List<EventModel>>(
      stream: _searchQuery.isNotEmpty
          ? _eventService.searchEvents(_searchQuery)
          : (showPast
              ? _eventService.getPastEvents()
              : _eventService.getFutureEvents()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        final events = snapshot.data ?? [];

        if (events.isEmpty) {
          return _buildEmptyState(showPast);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          itemCount: events.length,
          itemBuilder: (context, index) {
            return _buildEventCard(events[index], userId);
          },
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [_kCardStart, _kCardEnd],
              ),
              border: Border.all(color: _kBorderColor),
            ),
            child: CircularProgressIndicator(
              color: kBrandColor,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Caricamento eventi...',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    // Log dettagliato per debug
    print('═══════════════════════════════════════════════════════');
    print('❌ ERRORE CARICAMENTO EVENTI');
    print('═══════════════════════════════════════════════════════');
    print('Errore: $error');

    // Controlla se è un errore di indice mancante
    if (error.contains('index') || error.contains('Index') || error.contains('FAILED_PRECONDITION')) {
      print('');
      print('🔥 INDICE FIRESTORE MANCANTE!');
      print('');

      // Estrai il link se presente
      final linkRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
      final match = linkRegex.firstMatch(error);

      if (match != null) {
        final link = match.group(0);
        print('📎 CLICCA QUI PER CREARE L\'INDICE:');
        print(link);
        print('');
        print('Oppure vai manualmente a:');
        print('Firebase Console → Firestore Database → Indici → Crea indice');
      } else {
        print('Vai a: Firebase Console → Firestore Database → Indici');
        print('Crea un indice composito per la collezione "events"');
      }
    }

    print('═══════════════════════════════════════════════════════');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    Colors.red.withAlpha(25),
                    Colors.red.withAlpha(10),
                  ],
                ),
                border: Border.all(color: Colors.red.withAlpha(60)),
              ),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Errore caricamento eventi',
              style: TextStyle(
                color: kFgColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error.contains('index') || error.contains('Index') || error.contains('FAILED_PRECONDITION')
                  ? 'Indice Firestore mancante.\nControlla il terminale di debug per il link.'
                  : 'Si è verificato un errore.\nControlla il terminale di debug.',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => setState(() {}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [kBrandColor, kBrandColor.withAlpha(220)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withAlpha(60),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.refresh, color: Colors.black, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Riprova',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool showPast) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: LinearGradient(
                colors: [
                  Colors.amber.withAlpha(25),
                  Colors.amber.withAlpha(10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.amber.withAlpha(60)),
            ),
            child: Icon(
              showPast ? Icons.history : Icons.event_available,
              color: Colors.amber.withAlpha(180),
              size: 50,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            showPast ? 'Nessun evento passato' : 'Nessun evento in programma',
            style: const TextStyle(
              color: kFgColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              showPast
                  ? 'Gli eventi a cui hai partecipato appariranno qui'
                  : 'Quando verranno creati nuovi eventi li vedrai qui',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(EventModel event, String currentUserId) {
    final isRegistered = event.registeredUserIds.contains(currentUserId);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailPage(eventId: event.eventId),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Immagine evento (se presente)
            if (event.eventImageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: event.eventImageUrl!,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 140,
                        color: _kCardStart,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: kBrandColor,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.amber.withAlpha(30),
                              _kCardStart,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.event,
                            color: Colors.amber.withAlpha(100),
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    // Gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              _kCardStart.withAlpha(240),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    // Status badge in alto a destra (solo se iscritto)
                    if (isRegistered)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _buildIscrittoBadge(),
                      ),
                    // Data box in alto a sinistra
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _buildDateBox(event.eventDateTime),
                    ),
                  ],
                ),
              )
            else
              // Header senza immagine
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.withAlpha(15),
                      Colors.transparent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    _buildDateBox(event.eventDateTime),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              color: kFgColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 14, color: kMutedColor),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('HH:mm').format(event.eventDateTime),
                                style: TextStyle(
                                  color: kMutedColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isRegistered)
                      _buildIscrittoBadge(),
                  ],
                ),
              ),

            // Content section
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                event.eventImageUrl != null ? 12 : 0,
                16,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.eventImageUrl != null) ...[
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: kFgColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    event.description,
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Location bar
            if (event.locationName != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withAlpha(5),
                  border: Border.all(color: _kBorderColor.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: kBrandColor.withAlpha(20),
                      ),
                      child: Icon(Icons.location_on, size: 14, color: kBrandColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        event.locationName!,
                        style: TextStyle(
                          color: kFgColor.withAlpha(200),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: _kBorderColor.withAlpha(100)),
                ),
              ),
              child: Row(
                children: [
                  // Organizzatore
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withAlpha(8),
                    ),
                    child: Icon(Icons.person, size: 14, color: kMutedColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.creatorName,
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Partecipanti
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          kBrandColor.withAlpha(25),
                          kBrandColor.withAlpha(10),
                        ],
                      ),
                      border: Border.all(color: kBrandColor.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people, size: 14, color: kBrandColor),
                        const SizedBox(width: 6),
                        Text(
                          '${event.registeredCount}',
                          style: TextStyle(
                            color: kBrandColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Freccia
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withAlpha(8),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: kMutedColor,
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

  Widget _buildDateBox(DateTime dateTime) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            Colors.amber,
            Colors.amber.shade700,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withAlpha(80),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('dd').format(dateTime),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('MMM').format(dateTime).toUpperCase(),
            style: TextStyle(
              color: Colors.black.withAlpha(180),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIscrittoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: kBrandColor,
        boxShadow: [
          BoxShadow(
            color: kBrandColor.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check, color: Colors.black, size: 14),
          SizedBox(width: 4),
          Text(
            'ISCRITTO',
            style: TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateEventFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [Colors.amber, Colors.amber.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withAlpha(100),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreateEventPage()),
          );
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text(
          'Crea Evento',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
