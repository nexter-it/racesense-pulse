import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme.dart';
import '../models/event_model.dart';
import '../services/event_service.dart';
import 'edit_event_page.dart';

const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class ManageEventsPage extends StatefulWidget {
  const ManageEventsPage({super.key});

  @override
  State<ManageEventsPage> createState() => _ManageEventsPageState();
}

class _ManageEventsPageState extends State<ManageEventsPage> {
  final EventService _eventService = EventService();

  Future<void> _deleteEvent(EventModel event) async {
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
                color: Colors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Elimina evento',
              style: TextStyle(color: kFgColor, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sei sicuro di voler eliminare questo evento?',
              style: TextStyle(color: kMutedColor, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.event, color: Colors.amber, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      event.title,
                      style: const TextStyle(
                        color: kFgColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Questa azione non può essere annullata.',
              style: TextStyle(color: Colors.red.withAlpha(200), fontSize: 12),
            ),
          ],
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
              child: const Text('Elimina', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      await _eventService.deleteEvent(event.eventId, userId);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.green, size: 18),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Evento eliminato',
                  style: TextStyle(color: kFgColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: _kCardStart,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.green.withAlpha(100)),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kCardStart,
              border: Border.all(color: _kBorderColor),
            ),
            child: const Icon(Icons.arrow_back, color: kFgColor, size: 22),
          ),
        ),
        title: const Text(
          'I Miei Eventi',
          style: TextStyle(
            color: kFgColor,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: userId == null
          ? _buildNotLoggedIn()
          : StreamBuilder<List<EventModel>>(
              stream: _eventService.getUserCreatedEvents(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                if (snapshot.hasError) {
                  // Stampa l'errore completo per debug (utile per link indici Firebase)
                  debugPrint('═══════════════════════════════════════════════════════════');
                  debugPrint('ERRORE FIREBASE - Potrebbe essere necessario creare un indice');
                  debugPrint('Errore: ${snapshot.error}');
                  debugPrint('═══════════════════════════════════════════════════════════');
                  return _buildErrorState(snapshot.error.toString());
                }

                final events = snapshot.data ?? [];

                if (events.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    return _buildEventCard(events[index]);
                  },
                );
              },
            ),
    );
  }

  Widget _buildNotLoggedIn() {
    return Center(
      child: Text(
        'Effettua il login per vedere i tuoi eventi',
        style: TextStyle(color: kMutedColor),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: kBrandColor),
          const SizedBox(height: 16),
          Text(
            'Caricamento eventi...',
            style: TextStyle(color: kMutedColor),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            'Errore: $error',
            style: TextStyle(color: kMutedColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
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
              ),
              border: Border.all(color: Colors.amber.withAlpha(60)),
            ),
            child: Icon(
              Icons.event_note,
              color: Colors.amber.withAlpha(180),
              size: 50,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Nessun evento creato',
            style: TextStyle(
              color: kFgColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Gli eventi che crei appariranno qui',
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(EventModel event) {
    final isPast = event.isPast;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isPast ? _kBorderColor : Colors.amber.withAlpha(60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con immagine o default
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
                    height: 120,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 120,
                      color: _kCardStart,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: kBrandColor,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 120,
                      color: _kCardStart,
                      child: Icon(Icons.event, color: kMutedColor, size: 40),
                    ),
                  ),
                  // Overlay gradient
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
                            _kCardStart,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  // Badge stato
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isPast ? kMutedColor : Colors.green,
                      ),
                      child: Text(
                        isPast ? 'CONCLUSO' : 'ATTIVO',
                        style: TextStyle(
                          color: isPast ? kFgColor : Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.eventImageUrl == null)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isPast ? kMutedColor : Colors.green,
                        ),
                        child: Text(
                          isPast ? 'CONCLUSO' : 'ATTIVO',
                          style: TextStyle(
                            color: isPast ? kFgColor : Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                if (event.eventImageUrl == null)
                  const SizedBox(height: 12),
                Text(
                  event.title,
                  style: const TextStyle(
                    color: kFgColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: kMutedColor),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd MMM yyyy', 'it_IT').format(event.eventDateTime),
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.access_time, size: 14, color: kMutedColor),
                    const SizedBox(width: 6),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.people, size: 14, color: kBrandColor),
                    const SizedBox(width: 6),
                    Text(
                      '${event.registeredCount} iscritti',
                      style: TextStyle(
                        color: kBrandColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.verified, size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      '${event.checkedInCount} check-in',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: _kBorderColor),
              ),
            ),
            child: Row(
              children: [
                // Bottone Modifica
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditEventPage(event: event),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.withAlpha(30),
                            Colors.amber.withAlpha(15),
                          ],
                        ),
                        border: Border.all(color: Colors.amber.withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Modifica',
                            style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Bottone Elimina
                Expanded(
                  child: GestureDetector(
                    onTap: () => _deleteEvent(event),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            Colors.red.withAlpha(25),
                            Colors.red.withAlpha(10),
                          ],
                        ),
                        border: Border.all(color: Colors.red.withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Elimina',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
