import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import 'search_user_profile_page.dart';

// Reimport EventType for comparison
export '../models/event_model.dart' show EventType;

const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class EventDetailPage extends StatefulWidget {
  final String eventId;

  const EventDetailPage({
    super.key,
    required this.eventId,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final EventService _eventService = EventService();
  bool _isCheckingIn = false;

  void _showSuccessSnackBar(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: kFgColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: _kCardStart,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withAlpha(100), width: 1),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
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
                style: const TextStyle(
                  color: kFgColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: _kCardStart,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.red.withAlpha(100), width: 1),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _registerToEvent(String eventId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await _eventService.registerToEvent(eventId, userId);
      if (mounted) {
        HapticFeedback.lightImpact();
        _showSuccessSnackBar(
          'Iscrizione completata!',
          Icons.check_circle,
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Errore: $e');
      }
    }
  }

  Future<void> _unregisterFromEvent(String eventId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kCardStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _kBorderColor),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Annulla iscrizione',
              style: TextStyle(color: kFgColor, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Sei sicuro di voler annullare l\'iscrizione a questo evento?',
          style: TextStyle(color: kMutedColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Annulla', style: TextStyle(color: kMutedColor, fontWeight: FontWeight.w600)),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.red.withAlpha(25),
            ),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Conferma', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _eventService.unregisterFromEvent(eventId, userId);
      if (mounted) {
        HapticFeedback.lightImpact();
        _showSuccessSnackBar(
          'Iscrizione annullata',
          Icons.cancel,
          Colors.orange,
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Errore: $e');
      }
    }
  }

  Future<void> _checkInToEvent(EventModel event) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isCheckingIn = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permessi di localizzazione negati');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permessi di localizzazione negati permanentemente');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final badge = await _eventService.checkInToEvent(
        eventId: widget.eventId,
        userId: userId,
        userLatitude: position.latitude,
        userLongitude: position.longitude,
      );

      if (mounted) {
        HapticFeedback.heavyImpact();
        _showBadgeDialog(event);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingIn = false;
        });
      }
    }
  }

  void _showBadgeDialog(EventModel event) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFFFFD700).withAlpha(120), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withAlpha(60),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withAlpha(100),
                      blurRadius: 25,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.black,
                  size: 45,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Badge Ottenuto!',
                style: TextStyle(
                  color: kFgColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Hai partecipato all\'evento',
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                event.title,
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                    ),
                  ),
                  child: const Text(
                    'Fantastico!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
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

  Future<void> _openInMaps(double latitude, double longitude) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _kBgColor,
      body: StreamBuilder<EventModel?>(
        stream: _eventService.getEventStream(widget.eventId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: kBrandColor),
            );
          }

          final event = snapshot.data;
          if (event == null) {
            return _buildNotFoundState();
          }

          final isRegistered = event.registeredUserIds.contains(userId);
          final hasCheckedIn = event.checkedInUserIds.contains(userId);

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildHeroHeader(event),
                  SliverToBoxAdapter(
                    child: Transform.translate(
                      offset: const Offset(0, -30),
                      child: Column(
                        children: [
                          const SizedBox(height: 50),
                          _buildMainInfoCard(event, isRegistered, hasCheckedIn),
                          const SizedBox(height: 16),
                          _buildQuickStats(event),
                          const SizedBox(height: 16),
                          _buildDescriptionCard(event),
                          const SizedBox(height: 16),
                          // Info rapide inline (prezzo, durata, sito web)
                          if (_hasAnyQuickInfo(event))
                            _buildQuickInfoRow(event),
                          if (_hasAnyQuickInfo(event))
                            const SizedBox(height: 16),
                          // Requisiti (solo se presenti)
                          if (event.hasRequirements)
                            _buildRequirementsCard(event),
                          if (event.hasRequirements)
                            const SizedBox(height: 16),
                          _buildLocationCard(event),
                          const SizedBox(height: 16),
                          if (event.hasOfficialCircuit)
                            _buildCircuitCard(event),
                          if (event.hasOfficialCircuit)
                            const SizedBox(height: 16),
                          _buildOrganizerCard(event),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(event, isRegistered, hasCheckedIn),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  kMutedColor.withAlpha(30),
                  kMutedColor.withAlpha(10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kCardStart,
                border: Border.all(color: kMutedColor.withAlpha(60), width: 2),
              ),
              child: Icon(Icons.event_busy, color: kMutedColor, size: 30),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Evento non trovato',
            style: TextStyle(
              color: kFgColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'L\'evento potrebbe essere stato rimosso',
            style: TextStyle(color: kMutedColor, fontSize: 14),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, color: kBrandColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Torna indietro',
                    style: TextStyle(
                      color: kBrandColor,
                      fontWeight: FontWeight.w800,
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

  Widget _buildHeroHeader(EventModel event) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: _kBgColor,
      leading: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
        },
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBgColor.withAlpha(200),
            border: Border.all(color: _kBorderColor),
          ),
          child: const Icon(Icons.arrow_back, color: kFgColor, size: 22),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Immagine
            if (event.eventImageUrl != null)
              CachedNetworkImage(
                imageUrl: event.eventImageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: _kBgColor,
                  child: Center(
                    child: CircularProgressIndicator(color: kBrandColor),
                  ),
                ),
                errorWidget: (context, url, error) => _buildDefaultEventImage(),
              )
            else
              _buildDefaultEventImage(),
            // Gradiente overlay - fade verso background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    _kBgColor.withAlpha(0),
                    _kBgColor.withAlpha(150),
                    _kBgColor,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.4, 0.7, 1.0],
                ),
              ),
            ),
            // Badge stato evento
            Positioned(
              top: 100,
              left: 20,
              child: _buildEventStatusBadge(event),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultEventImage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kBrandColor.withAlpha(60),
            _kBgColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kCardStart.withAlpha(150),
            border: Border.all(color: kBrandColor.withAlpha(60), width: 2),
          ),
          child: Icon(
            Icons.event,
            color: kBrandColor.withAlpha(180),
            size: 60,
          ),
        ),
      ),
    );
  }

  Widget _buildEventStatusBadge(EventModel event) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (event.isPast) {
      badgeColor = kMutedColor;
      badgeText = 'CONCLUSO';
      badgeIcon = Icons.check_circle_outline;
    } else if (event.isOngoing) {
      badgeColor = Colors.green;
      badgeText = 'IN CORSO';
      badgeIcon = Icons.play_circle_outline;
    } else {
      badgeColor = kBrandColor;
      badgeText = 'PROSSIMO';
      badgeIcon = Icons.schedule;
    }

    return Row(
      children: [
        // Badge tipo evento (solo se diverso da "other")
        if (event.eventType != EventType.other) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: _kCardStart.withAlpha(220),
              border: Border.all(color: kPulseColor.withAlpha(120)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.eventType.emoji,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 6),
                Text(
                  event.eventType.displayName.toUpperCase(),
                  style: TextStyle(
                    color: kPulseColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        // Badge stato
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: _kCardStart.withAlpha(220),
            border: Border.all(color: badgeColor.withAlpha(120)),
            boxShadow: [
              BoxShadow(
                color: badgeColor.withAlpha(40),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, color: badgeColor, size: 16),
              const SizedBox(width: 8),
              Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainInfoCard(EventModel event, bool isRegistered, bool hasCheckedIn) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo evento
          Text(
            event.title,
            style: const TextStyle(
              color: kFgColor,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          // Data e ora con icona premium
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _kTileColor,
              border: Border.all(color: _kBorderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(40),
                        kBrandColor.withAlpha(20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(60)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd').format(event.eventDateTime),
                        style: TextStyle(
                          color: kBrandColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'it_IT').format(event.eventDateTime).toUpperCase(),
                        style: TextStyle(
                          color: kBrandColor.withAlpha(200),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE', 'it_IT').format(event.eventDateTime),
                        style: const TextStyle(
                          color: kFgColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, color: kMutedColor, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('HH:mm').format(event.eventDateTime),
                            style: TextStyle(
                              color: kMutedColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Badge iscrizione/check-in
                if (hasCheckedIn)
                  _buildUserStatusBadge(Icons.emoji_events, 'Badge', const Color(0xFFFFD700))
                else if (isRegistered)
                  _buildUserStatusBadge(Icons.check, 'Iscritto', Colors.green),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserStatusBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.people_alt_rounded,
              value: '${event.registeredCount}',
              label: 'Iscritti',
              color: kBrandColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.verified,
              value: '${event.checkedInCount}',
              label: 'Check-in',
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.my_location,
              value: '${event.checkInRadiusMeters.toInt()}m',
              label: 'Raggio',
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(20),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: kPulseColor.withAlpha(20),
                  border: Border.all(color: kPulseColor.withAlpha(60)),
                ),
                child: Icon(Icons.description_outlined, color: kPulseColor, size: 20),
              ),
              const SizedBox(width: 14),
              const Text(
                'Descrizione',
                style: TextStyle(
                  color: kFgColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _kTileColor,
              border: Border.all(color: _kBorderColor),
            ),
            child: Text(
              event.description,
              style: TextStyle(
                color: kFgColor.withAlpha(220),
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Controlla se ci sono info rapide da mostrare
  bool _hasAnyQuickInfo(EventModel event) {
    return event.hasEntryFee ||
           event.eventDurationMinutes != null ||
           event.hasWebsite ||
           event.maxParticipants != null;
  }

  // Row compatta con info rapide (prezzo, durata, sito, posti)
  Widget _buildQuickInfoRow(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          // Prezzo
          if (event.hasEntryFee)
            _buildInfoChip(
              icon: Icons.euro,
              label: event.formattedEntryFee,
              color: Colors.green,
            )
          else if (event.eventDurationMinutes != null || event.hasWebsite || event.maxParticipants != null)
            _buildInfoChip(
              icon: Icons.card_giftcard,
              label: 'Gratuito',
              color: Colors.green,
            ),
          // Durata
          if (event.eventDurationMinutes != null)
            _buildInfoChip(
              icon: Icons.schedule,
              label: event.formattedDuration,
              color: Colors.blue,
            ),
          // Posti disponibili
          if (event.maxParticipants != null)
            _buildInfoChip(
              icon: event.isFull ? Icons.block : Icons.group,
              label: event.isFull ? 'Completo' : '${event.availableSpots} posti',
              color: event.isFull ? Colors.red : Colors.orange,
            ),
          // Sito web
          if (event.hasWebsite)
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                if (event.websiteUrl != null) {
                  final uri = Uri.parse(event.websiteUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
              child: _buildInfoChip(
                icon: Icons.language,
                label: 'Sito Web',
                color: kPulseColor,
                isClickable: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    bool isClickable = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isClickable) ...[
            const SizedBox(width: 6),
            Icon(Icons.open_in_new, color: color.withAlpha(150), size: 14),
          ],
        ],
      ),
    );
  }

  // Card requisiti separata (solo se presenti)
  Widget _buildRequirementsCard(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.amber.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.amber.withAlpha(20),
                ),
                child: Icon(Icons.checklist, color: Colors.amber, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Requisiti',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...event.requirements.map((req) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.amber.withAlpha(150),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    req,
                    style: TextStyle(
                      color: kFgColor.withAlpha(220),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildLocationCard(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: kBrandColor.withAlpha(20),
                  border: Border.all(color: kBrandColor.withAlpha(60)),
                ),
                child: Icon(Icons.location_on, color: kBrandColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Posizione',
                      style: TextStyle(
                        color: kFgColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (event.locationName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.locationName!,
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mappa
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: _kBorderColor),
              ),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(
                    event.location.latitude,
                    event.location.longitude,
                  ),
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.racesense.pulse',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          event.location.latitude,
                          event.location.longitude,
                        ),
                        width: 50,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kBrandColor.withAlpha(60),
                            border: Border.all(color: kBrandColor, width: 2),
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: kBrandColor,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Bottone apri in maps
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _openInMaps(
                event.location.latitude,
                event.location.longitude,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(30),
                    kBrandColor.withAlpha(15),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(60)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.open_in_new, color: kBrandColor, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Apri in Google Maps',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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

  Widget _buildCircuitCard(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(40),
                  kBrandColor.withAlpha(20),
                ],
              ),
              border: Border.all(color: kBrandColor.withAlpha(60), width: 2),
            ),
            child: const Icon(
              Icons.stadium,
              color: kBrandColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Circuito Ufficiale',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  event.officialCircuitName ?? '',
                  style: const TextStyle(
                    color: kFgColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: kBrandColor.withAlpha(20),
              border: Border.all(color: kBrandColor.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: kBrandColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Ufficiale',
                  style: TextStyle(
                    color: kBrandColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizerCard(EventModel event) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchUserProfilePage(
              userId: event.creatorId,
              fullName: event.creatorName,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kBorderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    kPulseColor.withAlpha(40),
                    kPulseColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kPulseColor.withAlpha(60), width: 2),
              ),
              child: event.creatorProfileImage != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: event.creatorProfileImage!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Center(
                      child: Text(
                        event.creatorName.isNotEmpty
                            ? event.creatorName[0].toUpperCase()
                            : 'O',
                        style: TextStyle(
                          color: kPulseColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Organizzato da',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.creatorName,
                    style: const TextStyle(
                      color: kFgColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: kPulseColor.withAlpha(20),
                border: Border.all(color: kPulseColor.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, color: kPulseColor, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Verificato',
                    style: TextStyle(
                      color: kPulseColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: kMutedColor, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(EventModel event, bool isRegistered, bool hasCheckedIn) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kBgColor.withAlpha(0),
            _kBgColor.withAlpha(200),
            _kBgColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.3, 0.5],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: _kCardStart,
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: _buildActionContent(event, isRegistered, hasCheckedIn),
      ),
    );
  }

  Widget _buildActionContent(EventModel event, bool isRegistered, bool hasCheckedIn) {
    if (hasCheckedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events, color: Colors.black, size: 22),
            SizedBox(width: 10),
            Text(
              'Badge nella tua collezione!',
              style: TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        if (isRegistered) ...[
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _unregisterFromEvent(event.eventId);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.red.withAlpha(20),
                  border: Border.all(color: Colors.red.withAlpha(60)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.close, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Annulla',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (event.isOngoing) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _isCheckingIn ? null : () {
                  HapticFeedback.lightImpact();
                  _checkInToEvent(event);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: _isCheckingIn
                          ? [Colors.grey.shade700, Colors.grey.shade800]
                          : [Colors.green, Colors.green.shade700],
                    ),
                    boxShadow: _isCheckingIn
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.green.withAlpha(80),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isCheckingIn)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(Icons.location_on, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _isCheckingIn ? 'Verifica...' : 'Fai Check-in',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ] else ...[
          Expanded(
            child: GestureDetector(
              onTap: event.isPast
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      _registerToEvent(event.eventId);
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: event.isPast
                      ? LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade800])
                      : LinearGradient(colors: [kBrandColor, kBrandColor.withAlpha(200)]),
                  boxShadow: event.isPast
                      ? null
                      : [
                          BoxShadow(
                            color: kBrandColor.withAlpha(80),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      event.isPast ? Icons.event_busy : Icons.how_to_reg,
                      color: event.isPast ? Colors.grey : Colors.black,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      event.isPast ? 'Evento concluso' : 'Iscriviti all\'evento',
                      style: TextStyle(
                        color: event.isPast ? Colors.grey : Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
