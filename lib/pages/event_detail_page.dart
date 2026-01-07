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

const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);

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
      // Verifica permessi
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

      // Ottieni posizione corrente
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Fai check-in
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
            border: Border.all(color: Colors.green.withAlpha(120), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withAlpha(80),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.green, Colors.green.shade700],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withAlpha(120),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Badge Ottenuto!',
                style: TextStyle(
                  color: kFgColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Hai ottenuto il badge per',
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                event.title,
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [Colors.green, Colors.green.shade700],
                    ),
                  ),
                  child: const Text(
                    'Fantastico!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: kMutedColor, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    'Evento non trovato',
                    style: TextStyle(color: kMutedColor, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Torna indietro'),
                  ),
                ],
              ),
            );
          }

          final isRegistered = event.registeredUserIds.contains(userId);
          final hasCheckedIn = event.checkedInUserIds.contains(userId);

          return CustomScrollView(
            slivers: [
              _buildAppBar(event),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEventHeader(event),
                    _buildEventInfo(event),
                    _buildLocationSection(event),
                    _buildParticipantsSection(event),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: StreamBuilder<EventModel?>(
        stream: Stream.fromFuture(_eventService.getEvent(widget.eventId)),
        builder: (context, snapshot) {
          final event = snapshot.data;
          if (event == null) return const SizedBox.shrink();

          final isRegistered = event.registeredUserIds.contains(userId);
          final hasCheckedIn = event.checkedInUserIds.contains(userId);

          return _buildBottomBar(event, isRegistered, hasCheckedIn);
        },
      ),
    );
  }

  Widget _buildAppBar(EventModel event) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: _kBgColor,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBgColor.withAlpha(200),
          ),
          child: const Icon(Icons.arrow_back, color: kFgColor),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: event.eventImageUrl != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: event.eventImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: _kBgColor,
                      child: Center(
                        child: CircularProgressIndicator(color: kBrandColor),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.withAlpha(60),
                            _kBgColor,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.event,
                          color: Colors.amber.withAlpha(150),
                          size: 80,
                        ),
                      ),
                    ),
                  ),
                  // Gradiente overlay per leggibilità
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withAlpha(100),
                          Colors.black.withAlpha(200),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.withAlpha(60),
                      _kBgColor,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.event,
                    color: Colors.amber.withAlpha(150),
                    size: 80,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEventHeader(EventModel event) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.amber.withAlpha(25),
                  border: Border.all(color: Colors.amber.withAlpha(80)),
                ),
                child: Text(
                  event.isPast ? 'TERMINATO' : event.isOngoing ? 'IN CORSO' : 'FUTURO',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            event.title,
            style: const TextStyle(
              color: kFgColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: kMutedColor),
              const SizedBox(width: 8),
              Text(
                'Organizzato da ${event.creatorName}',
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
    );
  }

  Widget _buildEventInfo(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
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
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.amber.withAlpha(25),
                  border: Border.all(color: Colors.amber.withAlpha(80)),
                ),
                child: Icon(Icons.calendar_today, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data e ora',
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE dd MMMM yyyy • HH:mm')
                          .format(event.eventDateTime),
                      style: const TextStyle(
                        color: kFgColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: _kBorderColor, height: 1),
          const SizedBox(height: 20),
          Text(
            'Descrizione',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            event.description,
            style: const TextStyle(
              color: kFgColor,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(EventModel event) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
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
                  borderRadius: BorderRadius.circular(10),
                  color: kBrandColor.withAlpha(25),
                  border: Border.all(color: kBrandColor.withAlpha(80)),
                ),
                child: Icon(Icons.location_on, color: kBrandColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Posizione',
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.locationName ?? 'Posizione GPS',
                      style: const TextStyle(
                        color: kFgColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mappa satellitare
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 200,
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
                    flags: InteractiveFlag.none, // Disabilita interazioni
                  ),
                ),
                children: [
                  // Tile layer satellitare
                  TileLayer(
                    urlTemplate:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    userAgentPackageName: 'com.racesense.pulse',
                  ),
                  // Marker della posizione
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          event.location.latitude,
                          event.location.longitude,
                        ),
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.location_on,
                          color: kBrandColor,
                          size: 40,
                          shadows: [
                            Shadow(
                              color: Colors.black.withAlpha(150),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Bottone Apri in Maps
          GestureDetector(
            onTap: () => _openInMaps(
              event.location.latitude,
              event.location.longitude,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: kBrandColor.withAlpha(25),
                border: Border.all(color: kBrandColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, color: kBrandColor, size: 18),
                  const SizedBox(width: 8),
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

  Widget _buildParticipantsSection(EventModel event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
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
              Icon(Icons.people, color: kMutedColor, size: 20),
              const SizedBox(width: 10),
              Text(
                'Partecipanti',
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  label: 'Iscritti',
                  value: '${event.registeredCount}',
                  icon: Icons.how_to_reg,
                  color: kBrandColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  label: 'Check-in',
                  value: '${event.checkedInCount}',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withAlpha(15),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(EventModel event, bool isRegistered, bool hasCheckedIn) {
    if (hasCheckedIn) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kBgColor,
          border: const Border(top: BorderSide(color: _kBorderColor)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.green.withAlpha(25),
            border: Border.all(color: Colors.green.withAlpha(80)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, color: Colors.green, size: 24),
              const SizedBox(width: 12),
              Text(
                'Badge ottenuto!',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kBgColor,
        border: const Border(top: BorderSide(color: _kBorderColor)),
      ),
      child: Row(
        children: [
          if (isRegistered) ...[
            Expanded(
              child: _buildActionButton(
                label: 'Annulla iscrizione',
                icon: Icons.close,
                color: Colors.red,
                onTap: () => _unregisterFromEvent(event.eventId),
              ),
            ),
            const SizedBox(width: 12),
            if (event.isOngoing)
              Expanded(
                child: _buildActionButton(
                  label: _isCheckingIn ? 'Verifica...' : 'Check-in',
                  icon: Icons.location_on,
                  color: Colors.green,
                  onTap: _isCheckingIn ? null : () => _checkInToEvent(event),
                ),
              ),
          ] else ...[
            Expanded(
              child: _buildActionButton(
                label: 'Iscriviti',
                icon: Icons.how_to_reg,
                color: kBrandColor,
                onTap: event.isPast ? null : () => _registerToEvent(event.eventId),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: onTap == null
              ? LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade900])
              : LinearGradient(colors: [color, color.withAlpha(200)]),
          boxShadow: onTap == null
              ? null
              : [
                  BoxShadow(
                    color: color.withAlpha(80),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: onTap == null ? Colors.grey : Colors.black, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? Colors.grey : Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
