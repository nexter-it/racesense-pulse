import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../services/ble_tracking_service.dart';
import '../services/custom_circuit_service.dart';

/// Modalità di avvio sessione - RaceChrono Pro Style
///
/// Solo circuiti pre-tracciati (esistenti o custom).
/// Rimosso: quick mode, manual line.
enum StartMode { existing, privateCustom }

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
        // ModeCard(
        //   title: 'Circuiti ufficiali',
        //   subtitle: 'Autodromi famosi con linea S/F precisa',
        //   icon: Icons.track_changes,
        //   badge: 'Consigliata',
        //   selected: selected == StartMode.existing,
        //   onTap: () => onSelect(StartMode.existing),
        // ),
        const SizedBox(height: 0),
        ModeCard(
          title: 'Circuiti custom',
          subtitle: 'I tuoi tracciati salvati con GPS grezzo + linea S/F',
          icon: Icons.lock_outline,
          badge: 'Personali',
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

// Pagina per selezione circuiti ufficiali
class ExistingCircuitPage extends StatelessWidget {
  const ExistingCircuitPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Usa i circuiti predefiniti da PredefinedTracks
    final staticTracks = PredefinedTracks.all;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Circuiti ufficiali'),
        backgroundColor: kBgColor,
      ),
      body: staticTracks.isEmpty
          ? const Center(
              child: Text(
                'Nessun circuito ufficiale disponibile',
                style: TextStyle(color: kMutedColor),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: staticTracks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final t = staticTracks[index];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(t),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          Color.fromRGBO(255, 255, 255, 0.08),
                          Color.fromRGBO(255, 255, 255, 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: kBrandColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kBrandColor.withOpacity(0.14),
                          ),
                          child: const Icon(Icons.flag, color: kBrandColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.location,
                                style: const TextStyle(
                                  color: kMutedColor,
                                  fontSize: 12,
                                ),
                              ),
                              if (t.estimatedLengthMeters != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${(t.estimatedLengthMeters! / 1000).toStringAsFixed(2)} km',
                                  style: const TextStyle(
                                    color: kBrandColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: kMutedColor),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// Pagina per selezione circuiti custom
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

    // Usa i nuovi campi finishLineStart/finishLineEnd
    // Se non presenti, usa toTrackDefinition() che ha fallback logic
    return c.toTrackDefinition();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circuiti custom'),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.track_changes, size: 64, color: kMutedColor),
                  SizedBox(height: 16),
                  Text(
                    'Nessun circuito custom salvato',
                    style: TextStyle(color: kMutedColor, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Crea il tuo primo circuito dalla home',
                    style: TextStyle(color: kMutedColor, fontSize: 12),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: circuits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final c = circuits[index];
              final t = _toTrack(c);
              return InkWell(
                onTap: t != null ? () => Navigator.of(context).pop(t) : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [
                        Color.fromRGBO(255, 255, 255, 0.08),
                        Color.fromRGBO(255, 255, 255, 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                        color: t != null ? kBrandColor : kErrorColor.withOpacity(0.8)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kBrandColor.withOpacity(0.14),
                        ),
                        child: const Icon(Icons.track_changes, color: kBrandColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '${c.city} ${c.country}'.trim(),
                                  style: const TextStyle(
                                    color: kMutedColor,
                                    fontSize: 12,
                                  ),
                                ),
                                if (c.usedBleDevice) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: kBrandColor.withOpacity(0.15),
                                      border: Border.all(color: kBrandColor.withOpacity(0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.bluetooth_connected, color: kBrandColor, size: 10),
                                        SizedBox(width: 3),
                                        Text(
                                          'BLE',
                                          style: TextStyle(
                                            color: kBrandColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(c.lengthMeters / 1000).toStringAsFixed(2)} km',
                              style: const TextStyle(
                                color: kBrandColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        t != null ? Icons.chevron_right : Icons.error_outline,
                        color: t != null ? kMutedColor : kErrorColor,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
