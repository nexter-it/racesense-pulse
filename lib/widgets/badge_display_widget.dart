import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/badge_model.dart';
import '../theme.dart';
import '../pages/event_detail_page.dart';

const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);

// Colore oro uniforme per tutti i badge
const Color _kGoldPrimary = Color(0xFFFFD700);
const Color _kGoldSecondary = Color(0xFFB8860B);
const Color _kGoldAccent = Color(0xFFFFF8DC);

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
      return _buildCompactView(context);
    }

    return _buildFullView(context);
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

  Widget _buildCompactView(BuildContext context) {
    // Mostra i badge sovrapposti (stile collezione)
    final displayBadges = badges.take(5).toList();
    final hasMore = badges.length > 5;

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
                            style: const TextStyle(
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
              // Freccia per vedere tutti
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withAlpha(8),
                  border: Border.all(color: _kBorderColor),
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: kMutedColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Badge sovrapposti
          SizedBox(
            height: 70,
            child: Stack(
              children: [
                ...displayBadges.asMap().entries.map((entry) {
                  final index = entry.key;
                  final badge = entry.value;
                  return Positioned(
                    left: index * 45.0, // Sovrapposizione
                    child: _buildStackedBadge(context, badge),
                  );
                }),
                if (hasMore)
                  Positioned(
                    left: displayBadges.length * 45.0,
                    child: _buildMoreBadge(badges.length - 5),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedBadge(BuildContext context, BadgeModel badge) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailPage(eventId: badge.eventId),
          ),
        );
      },
      child: Container(
        width: 60,
        height: 70,
        child: Column(
          children: [
            // Medaglia
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_kGoldPrimary, _kGoldSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _kCardStart, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _kGoldPrimary.withAlpha(60),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Cerchio interno
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [_kGoldSecondary, _kGoldPrimary],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      border: Border.all(
                        color: _kGoldAccent.withAlpha(150),
                        width: 2,
                      ),
                    ),
                  ),
                  // Icona
                  Icon(
                    Icons.emoji_events,
                    color: Colors.black.withAlpha(180),
                    size: 20,
                  ),
                  // Shine
                  Positioned(
                    top: 6,
                    left: 12,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Anno
            Text(
              badge.year.toString(),
              style: TextStyle(
                color: _kGoldPrimary.withAlpha(200),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreBadge(int count) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kCardStart,
        border: Border.all(color: _kBorderColor, width: 2),
      ),
      child: Center(
        child: Text(
          '+$count',
          style: TextStyle(
            color: kMutedColor,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildFullView(BuildContext context) {
    // Raggruppa badge per mese
    final Map<String, List<BadgeModel>> badgesByMonth = {};

    for (final badge in badges) {
      final monthKey = DateFormat('MMMM yyyy').format(badge.eventDate);
      badgesByMonth.putIfAbsent(monthKey, () => []);
      badgesByMonth[monthKey]!.add(badge);
    }

    // Ordina i mesi dal più recente
    final sortedMonths = badgesByMonth.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('MMMM yyyy').parse(a);
        final dateB = DateFormat('MMMM yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

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
                  ),
                  border: Border.all(color: _kGoldPrimary.withAlpha(60)),
                ),
                child: const Icon(Icons.emoji_events, color: _kGoldPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Collezione Badge (${badges.length})',
                style: const TextStyle(
                  color: kFgColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Badge organizzati per mese
          ...sortedMonths.map((month) {
            final monthBadges = badgesByMonth[month]!;
            return _buildMonthSection(context, month, monthBadges);
          }),
        ],
      ),
    );
  }

  Widget _buildMonthSection(BuildContext context, String month, List<BadgeModel> monthBadges) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header mese
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white.withAlpha(5),
            border: Border.all(color: _kBorderColor.withAlpha(100)),
          ),
          child: Text(
            month.toUpperCase(),
            style: TextStyle(
              color: kMutedColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        // Badge sovrapposti per questo mese
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          height: 80,
          child: Stack(
            children: monthBadges.asMap().entries.map((entry) {
              final index = entry.key;
              final badge = entry.value;
              return Positioned(
                left: index * 50.0,
                child: _buildCollectionBadge(context, badge),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionBadge(BuildContext context, BadgeModel badge) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailPage(eventId: badge.eventId),
          ),
        );
      },
      child: Container(
        width: 70,
        child: Column(
          children: [
            // Medaglia grande
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_kGoldPrimary, _kGoldSecondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _kCardStart, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _kGoldPrimary.withAlpha(80),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Cerchio interno
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [_kGoldSecondary, _kGoldPrimary],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      border: Border.all(
                        color: _kGoldAccent.withAlpha(150),
                        width: 2,
                      ),
                    ),
                  ),
                  // Icona
                  Icon(
                    Icons.emoji_events,
                    color: Colors.black.withAlpha(200),
                    size: 24,
                  ),
                  // Shine
                  Positioned(
                    top: 8,
                    left: 14,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Anno piccolo sotto
            Text(
              badge.year.toString(),
              style: const TextStyle(
                color: _kGoldPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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

          if (error.contains('index') || error.contains('Index') || error.contains('FAILED_PRECONDITION')) {
            print('');
            print('🔥 INDICE FIRESTORE MANCANTE!');
            print('');

            final linkRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
            final match = linkRegex.firstMatch(error);

            if (match != null) {
              final link = match.group(0);
              print('📎 CLICCA QUI PER CREARE L\'INDICE:');
              print(link);
            }
          }

          print('═══════════════════════════════════════════════════════');

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
