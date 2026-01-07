import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/badge_model.dart';
import '../theme.dart';

const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);

// Colori premium per le medaglie
const Color _kGoldPrimary = Color(0xFFFFD700);
const Color _kGoldSecondary = Color(0xFFB8860B);
const Color _kGoldAccent = Color(0xFFFFF8DC);
const Color _kSilverPrimary = Color(0xFFC0C0C0);
const Color _kSilverSecondary = Color(0xFF808080);
const Color _kBronzePrimary = Color(0xFFCD7F32);
const Color _kBronzeSecondary = Color(0xFF8B4513);

class BadgeDisplayWidget extends StatelessWidget {
  final List<BadgeModel> badges;
  final bool isCompact;

  const BadgeDisplayWidget({
    super.key,
    required this.badges,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return _buildEmptyState();
    }

    if (isCompact) {
      return _buildCompactView();
    }

    return _buildFullView();
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.grey.withAlpha(20),
                  Colors.grey.withAlpha(10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.grey.withAlpha(40), width: 2),
            ),
            child: const Icon(Icons.emoji_events_outlined, color: Colors.grey, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nessun badge ancora',
            style: TextStyle(
              color: kFgColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Partecipa agli eventi e fai check-in\nper ottenere i tuoi primi badge!',
            style: TextStyle(
              color: kMutedColor.withAlpha(180),
              fontSize: 13,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactView() {
    // Mostra i primi 4 badge in una griglia premium
    final displayBadges = badges.take(4).toList();
    final hasMore = badges.length > 4;

    return Container(
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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      _kGoldPrimary.withAlpha(40),
                      _kGoldSecondary.withAlpha(20),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: _kGoldPrimary.withAlpha(60)),
                  boxShadow: [
                    BoxShadow(
                      color: _kGoldPrimary.withAlpha(30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.emoji_events, color: _kGoldPrimary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Collezione Badge',
                      style: TextStyle(
                        color: kFgColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: _kGoldPrimary.withAlpha(25),
                          ),
                          child: Text(
                            '${badges.length} ${badges.length == 1 ? 'badge' : 'badge'}',
                            style: TextStyle(
                              color: _kGoldPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasMore)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withAlpha(8),
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: Text(
                    '+${badges.length - 4}',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Badge Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: displayBadges.asMap().entries.map((entry) {
              return _buildPremiumBadgeIcon(entry.value, entry.key);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFullView() {
    return Container(
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
                  gradient: LinearGradient(
                    colors: [
                      _kGoldPrimary.withAlpha(40),
                      _kGoldSecondary.withAlpha(20),
                    ],
                  ),
                  border: Border.all(color: _kGoldPrimary.withAlpha(60)),
                ),
                child: const Icon(Icons.emoji_events, color: _kGoldPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Tutti i Badge (${badges.length})',
                style: const TextStyle(
                  color: kFgColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: badges.asMap().entries.map((entry) {
              return _buildFullBadgeCard(entry.value, entry.key);
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Determina il colore del badge basato sull'indice (simulazione rarità)
  List<Color> _getBadgeColors(int index) {
    // Primo badge = oro, secondo = argento, terzo = bronzo, resto = oro
    if (index == 0) {
      return [_kGoldPrimary, _kGoldSecondary, _kGoldAccent];
    } else if (index == 1) {
      return [_kSilverPrimary, _kSilverSecondary, Colors.white];
    } else if (index == 2) {
      return [_kBronzePrimary, _kBronzeSecondary, const Color(0xFFDEB887)];
    } else {
      return [_kGoldPrimary, _kGoldSecondary, _kGoldAccent];
    }
  }

  Widget _buildPremiumBadgeIcon(BadgeModel badge, int index) {
    final colors = _getBadgeColors(index);

    return Container(
      width: 70,
      height: 85,
      child: Column(
        children: [
          // Medaglia principale
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colors[0], colors[1]],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors[0].withAlpha(80),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: colors[0].withAlpha(40),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Cerchio interno
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [colors[1], colors[0]],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    border: Border.all(
                      color: colors[2].withAlpha(150),
                      width: 2,
                    ),
                  ),
                ),
                // Icona centrale
                Icon(
                  Icons.emoji_events,
                  color: Colors.black.withAlpha(180),
                  size: 24,
                ),
                // Shine effect
                Positioned(
                  top: 8,
                  left: 15,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(180),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Anno
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: colors[0].withAlpha(30),
            ),
            child: Text(
              badge.year.toString(),
              style: TextStyle(
                color: colors[0],
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullBadgeCard(BadgeModel badge, int index) {
    final colors = _getBadgeColors(index % 3); // Cicla tra oro, argento, bronzo

    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colors[0].withAlpha(15),
            colors[0].withAlpha(5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colors[0].withAlpha(60)),
        boxShadow: [
          BoxShadow(
            color: colors[0].withAlpha(20),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Medaglia grande
          Stack(
            alignment: Alignment.center,
            children: [
              // Glow background
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors[0].withAlpha(40),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Medaglia
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [colors[0], colors[1]],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withAlpha(100),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Inner ring
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [colors[1], colors[0]],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        border: Border.all(
                          color: colors[2].withAlpha(180),
                          width: 3,
                        ),
                      ),
                    ),
                    // Icon
                    Icon(
                      Icons.emoji_events,
                      color: Colors.black.withAlpha(200),
                      size: 28,
                    ),
                    // Shine
                    Positioned(
                      top: 12,
                      left: 18,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Ribbon
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: [colors[0], colors[1]],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors[0].withAlpha(60),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    badge.year.toString(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Titolo evento
          Text(
            badge.eventTitle,
            style: const TextStyle(
              color: kFgColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Data check-in
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withAlpha(5),
              border: Border.all(color: _kBorderColor.withAlpha(100)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 12, color: Colors.green.withAlpha(180)),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yy').format(badge.checkedInAt),
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (badge.eventLocationName != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, size: 10, color: kMutedColor.withAlpha(150)),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    badge.eventLocationName!,
                    style: TextStyle(
                      color: kMutedColor.withAlpha(150),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Widget per mostrare i badge in una card separata nella pagina profilo
class BadgeCard extends StatelessWidget {
  final String userId;
  final Stream<List<BadgeModel>> badgesStream;

  const BadgeCard({
    super.key,
    required this.userId,
    required this.badgesStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BadgeModel>>(
      stream: badgesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [_kCardStart, _kCardEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: _kBorderColor),
            ),
            child: Center(
              child: CircularProgressIndicator(color: kBrandColor, strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          final error = snapshot.error.toString();

          // Log dettagliato per debug
          print('═══════════════════════════════════════════════════════');
          print('❌ ERRORE CARICAMENTO BADGE');
          print('═══════════════════════════════════════════════════════');
          print('Errore: $error');
          print('User ID: $userId');

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
              print('Crea un indice composito per la collezione "badges"');
              print('Campi necessari: userId (Ascending) + eventDate (Descending)');
            }
          }

          print('═══════════════════════════════════════════════════════');

          // Mostra un widget di errore compatto
          return Container(
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.withAlpha(30),
                        Colors.red.withAlpha(15),
                      ],
                    ),
                    border: Border.all(color: Colors.red.withAlpha(60)),
                  ),
                  child: const Icon(Icons.error_outline, color: Colors.red, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Errore caricamento badge',
                        style: TextStyle(
                          color: kFgColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Controlla il terminale per dettagli',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final badges = snapshot.data ?? [];
        return BadgeDisplayWidget(badges: badges, isCompact: true);
      },
    );
  }
}
