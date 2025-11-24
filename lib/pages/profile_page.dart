import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    const pilotName = 'Luca Martini';
    const pilotTag = 'LMC';

    final List<Map<String, dynamic>> _mockActivities = [
      {
        'title': 'Track day Misano',
        'subtitle': '12 giri · Best 1:48.3',
        'value': 'Moto',
      },
      {
        'title': 'Corsa di recupero',
        'subtitle': '5 km · 4:50/km',
        'value': '25:00',
      },
      {
        'title': 'Interval training',
        'subtitle': '10 × 400m',
        'value': '45:00',
      },
    ];

    final recent = _mockActivities.take(3).toList();

    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ---------- HEADER ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Row(
              children: [
                const Text(
                  'Profilo',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 26),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Le impostazioni profilo arriveranno presto.'),
                      ),
                    );
                  },
                )
              ],
            ),
          ),

          // ---------- BODY ----------
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _ProfileHeader(name: pilotName, tag: pilotTag),
                const SizedBox(height: 18),

                _ProfileStats(),
                const SizedBox(height: 18),

                const _ProfileHighlights(),
                const SizedBox(height: 26),

                const Text(
                  'Ultime attività',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 12),

                ...recent.map((a) => _MiniActivityCard(activity: a)),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
    HEADER PROFILO
============================================================ */

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String tag;

  const _ProfileHeader({
    required this.name,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color.fromRGBO(255, 255, 255, 0.10),
        border: Border.all(color: kLineColor, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar tag
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.35),
              border: Border.all(color: kBrandColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: kBrandColor.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '@$tag',
                  style: const TextStyle(
                    color: kMutedColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),

                // Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: const [
                    PulseChip(
                      label: Text('RACESENSE LIVE'),
                      icon: Icons.bluetooth_connected,
                    ),
                    PulseChip(
                      label: Text('Accesso PULSE+'),
                      icon: Icons.bolt,
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

/* ============================================================
    STATISTICHE PROFILO
============================================================ */

class _ProfileStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        children: const [
          _ProfileStatItem(label: 'Sessioni', value: '42'),
          SizedBox(width: 14),
          _ProfileStatItem(label: 'Distanza totale', value: '728 km'),
          SizedBox(width: 14),
          _ProfileStatItem(label: 'PB circuiti', value: '9'),
        ],
      ),
    );
  }
}

class _ProfileStatItem extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: kMutedColor,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
    HIGHLIGHTS
============================================================ */

class _ProfileHighlights extends StatelessWidget {
  const _ProfileHighlights();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color.fromRGBO(255, 255, 255, 0.07),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Highlights',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          _HighlightRow(
            icon: Icons.emoji_events_outlined,
            label: 'Best lap assoluto',
            value: '1:48.3 · Misano',
          ),
          SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.local_fire_department_outlined,
            label: 'Streak attività',
            value: '7 giorni consecutivi',
          ),
          SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.insights_outlined,
            label: 'Ultimo mese',
            value: '12 sessioni · 210 km',
          ),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HighlightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kBrandColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: kMutedColor),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/* ============================================================
    CARD ULTIMA ATTIVITÀ
============================================================ */

class _MiniActivityCard extends StatelessWidget {
  final Map<String, dynamic> activity;

  const _MiniActivityCard({
    super.key,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    final title = activity['title'] ?? '';
    final subtitle = activity['subtitle'] ?? '';
    final value = activity['value'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        children: [
          // Icona attività
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBrandColor.withOpacity(0.18),
            ),
            child: const Icon(Icons.timeline_outlined, color: kBrandColor, size: 20),
          ),
          const SizedBox(width: 12),

          // Info attività
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: kMutedColor),
                    ),
                  ),
              ],
            ),
          ),

          if (value.isNotEmpty)
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }
}
