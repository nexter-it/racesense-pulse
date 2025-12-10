import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../services/custom_circuit_service.dart';

enum StartMode { existing, privateCustom, manualLine }

class ModeSelector extends StatelessWidget {
  final StartMode? selected;
  final ValueChanged<StartMode> onSelect;

  const ModeSelector({
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ModeCard(
          title: 'Seleziona circuito esistente',
          subtitle: 'Modalità più sicura e precisa',
          icon: Icons.track_changes,
          badge: 'Consigliata',
          selected: selected == StartMode.existing,
          onTap: () => onSelect(StartMode.existing),
        ),
        const SizedBox(height: 10),
        ModeCard(
          title: 'Seleziona linea start/finish',
          subtitle: 'Equilibrio tra velocità e precisione',
          icon: Icons.flag_outlined,
          badge: 'Manuale',
          selected: selected == StartMode.manualLine,
          onTap: () => onSelect(StartMode.manualLine),
        ),
        const SizedBox(height: 10),
        ModeCard(
          title: 'Circuiti privati',
          subtitle: 'Usa i circuiti custom salvati in locale',
          icon: Icons.lock_outline,
          badge: 'Stabile',
          selected: selected == StartMode.privateCustom,
          onTap: () => onSelect(StartMode.privateCustom),
        ),
      ],
    );
  }
}

class ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [
              Color.fromRGBO(255, 255, 255, 0.06),
              Color.fromRGBO(255, 255, 255, 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: selected ? kBrandColor : kLineColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? kBrandColor.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
              ),
              child: Icon(
                icon,
                color: selected ? kBrandColor : kMutedColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? kBrandColor.withOpacity(0.15)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? kBrandColor : kLineColor.withOpacity(0.7),
                ),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? kBrandColor : kMutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        BannerTile(
          color: kBrandColor,
          title: 'Seleziona circuito esistente',
          desc: 'Modalità più sicura e precisa',
        ),
        SizedBox(height: 6),
        BannerTile(
          color: Colors.orangeAccent,
          title: 'Circuiti privati',
          desc: 'Usa i tracciati custom salvati in locale',
        ),
        SizedBox(height: 6),
        BannerTile(
          color: kPulseColor,
          title: 'Linea start/finish manuale',
          desc: 'Equilibrio tra velocità e sicurezza',
        ),
      ],
    );
  }
}

class BannerTile extends StatelessWidget {
  final Color color;
  final String title;
  final String desc;

  const BannerTile({
    required this.color,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.07),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                    color: kMutedColor,
                    fontSize: 11,
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

// Placeholder per la selezione circuito esistente (statica)
class ExistingCircuitPage extends StatelessWidget {
  const ExistingCircuitPage({super.key});

  @override
  Widget build(BuildContext context) {
    final staticTracks = [
      TrackDefinition(
        id: 'monza',
        name: 'Autodromo di Monza',
        location: 'Monza, Italia',
        finishLineStart: const LatLng(45.6214, 9.2848),
        finishLineEnd: const LatLng(45.6210, 9.2857),
      ),
      TrackDefinition(
        id: 'mugello',
        name: 'Mugello Circuit',
        location: 'Scarperia, Italia',
        finishLineStart: const LatLng(43.9988, 11.3712),
        finishLineEnd: const LatLng(43.9982, 11.3720),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circuiti esistenti'),
        backgroundColor: kBgColor,
      ),
      body: ListView.builder(
        itemCount: staticTracks.length,
        itemBuilder: (context, index) {
          final t = staticTracks[index];
          return ListTile(
            title: Text(t.name),
            subtitle: Text(t.location),
            onTap: () => Navigator.of(context).pop(t),
          );
        },
      ),
    );
  }
}

class PrivateCircuitsPage extends StatefulWidget {
  const PrivateCircuitsPage({super.key});

  @override
  State<PrivateCircuitsPage> createState() => _PrivateCircuitsPageState();
}

class _PrivateCircuitsPageState extends State<PrivateCircuitsPage> {
  final CustomCircuitService _service = CustomCircuitService();
  late Future<List<CustomCircuitInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.listCircuits();
  }

  TrackDefinition? _toTrack(CustomCircuitInfo c) {
    if (c.points.length < 2) return null;
    return TrackDefinition(
      id: 'custom-${c.name}-${c.createdAt.millisecondsSinceEpoch}',
      name: c.name,
      location: '${c.city} ${c.country}'.trim(),
      finishLineStart: c.points.first,
      finishLineEnd: c.points[1],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circuiti privati'),
        backgroundColor: kBgColor,
      ),
      body: FutureBuilder<List<CustomCircuitInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(kBrandColor),
              ),
            );
          }
          final circuits = snapshot.data ?? [];
          if (circuits.isEmpty) {
            return const Center(
              child: Text(
                'Nessun circuito custom salvato',
                style: TextStyle(color: kMutedColor),
              ),
            );
          }
          return ListView.builder(
            itemCount: circuits.length,
            itemBuilder: (context, index) {
              final c = circuits[index];
              final t = _toTrack(c);
              return ListTile(
                title: Text(c.name),
                subtitle: Text('${c.city} ${c.country}'.trim()),
                onTap: t != null ? () => Navigator.of(context).pop(t) : null,
                trailing: t == null
                    ? const Icon(Icons.error_outline, color: kErrorColor)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

// Mappa per selezione start/finish
class ManualLinePage extends StatefulWidget {
  final LatLng? initialCenter;

  const ManualLinePage({super.key, this.initialCenter});

  @override
  State<ManualLinePage> createState() => _ManualLinePageState();
}

class _ManualLinePageState extends State<ManualLinePage> {
  LatLng? _start;
  LatLng? _end;
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter ?? const LatLng(45.4642, 9.19);
    final hasLine = _start != null && _end != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linea start/finish'),
        backgroundColor: kBgColor,
        actions: [
          TextButton(
            onPressed:
                hasLine ? () => Navigator.of(context).pop(LineResult(_start!, _end!)) : null,
            child: const Text(
              'Salva',
              style: TextStyle(color: kBrandColor),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: kLineColor)),
              color: const Color.fromRGBO(255, 255, 255, 0.02),
            ),
            child: const Text(
              'Tocca due punti sulla mappa per fissare Start e Finish.\n'
              'A = inizio linea, B = fine linea.',
              style: TextStyle(color: kMutedColor, fontSize: 12),
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 17,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (tapPos, point) {
                  setState(() {
                    if (_start == null || (_start != null && _end != null)) {
                      _start = point;
                      _end = null;
                    } else {
                      _end = point;
                    }
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.racesense.pulse',
                ),
                if (_start != null || _end != null)
                  PolylineLayer(
                    polylines: [
                      if (_start != null && _end != null)
                        Polyline(
                          points: [_start!, _end!],
                          strokeWidth: 6,
                          color: kBrandColor.withOpacity(0.8),
                        ),
                    ],
                  ),
                if (_start != null || _end != null)
                  MarkerLayer(
                    markers: [
                      if (_start != null)
                        Marker(
                          width: 42,
                          height: 42,
                          point: _start!,
                          child: _FlagMarker(
                            label: 'A',
                            color: kBrandColor,
                          ),
                        ),
                      if (_end != null)
                        Marker(
                          width: 42,
                          height: 42,
                          point: _end!,
                          child: _FlagMarker(
                            label: 'B',
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _start = null;
                      _end = null;
                    });
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
                const Spacer(),
                if (hasLine)
                  Text(
                    'Linea: ${_start!.latitude.toStringAsFixed(5)}, ${_start!.longitude.toStringAsFixed(5)} '
                    '→ ${_end!.latitude.toStringAsFixed(5)}, ${_end!.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(color: kMutedColor, fontSize: 11),
                  )
                else
                  const Text(
                    'Seleziona due punti per procedere',
                    style: TextStyle(color: kMutedColor, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LineResult {
  final LatLng start;
  final LatLng end;
  LineResult(this.start, this.end);
}

class _FlagMarker extends StatelessWidget {
  final String label;
  final Color color;

  const _FlagMarker({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
