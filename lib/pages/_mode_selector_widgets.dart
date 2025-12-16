import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../services/ble_tracking_service.dart';
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

    // Converti MicroSector in TrackMicroSector
    final trackMicroSectors = c.microSectors
        .map((ms) => TrackMicroSector(start: ms.start, end: ms.end))
        .toList();

    // Usa il primo microsettore per la finish line, se disponibile
    final firstMicroSector = c.microSectors.isNotEmpty ? c.microSectors.first : null;
    final finishLineStart = firstMicroSector?.start ?? c.points.first;
    final finishLineEnd = firstMicroSector?.end ??
        (c.points.length > 1 ? c.points[1] : c.points.first);

    return TrackDefinition(
      id: 'custom-${c.name}-${c.createdAt.millisecondsSinceEpoch}',
      name: c.name,
      location: '${c.city} ${c.country}'.trim(),
      finishLineStart: finishLineStart,
      finishLineEnd: finishLineEnd,
      estimatedLengthMeters: c.lengthMeters,
      trackPath: c.points,
      microSectors: trackMicroSectors,
      widthMeters: c.widthMeters,
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
  LatLng? _currentPosition;
  final MapController _mapController = MapController();
  final BleTrackingService _bleService = BleTrackingService();

  StreamSubscription<Position>? _gpsSubscription;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSubscription;
  String? _connectedDeviceId;
  bool _isUsingBleDevice = false;

  @override
  void initState() {
    super.initState();
    _checkConnectedDevices();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _bleGpsSubscription?.cancel();
    super.dispose();
  }

  void _checkConnectedDevices() {
    _bleService.deviceStream.listen((devices) {
      final connected = devices.values.firstWhere(
        (d) => d.isConnected,
        orElse: () => BleDeviceSnapshot(
          id: '',
          name: '',
          rssi: null,
          isConnected: false,
        ),
      );

      if (mounted) {
        setState(() {
          if (connected.isConnected) {
            _connectedDeviceId = connected.id;
            _isUsingBleDevice = true;
          } else {
            _connectedDeviceId = null;
            _isUsingBleDevice = false;
          }
        });
      }
    });
  }

  void _startLocationTracking() {
    // Listen to BLE GPS data
    _bleGpsSubscription = _bleService.gpsStream.listen((gpsData) {
      if (_connectedDeviceId != null && _isUsingBleDevice) {
        final data = gpsData[_connectedDeviceId!];
        if (data != null && mounted) {
          setState(() {
            _currentPosition = data.position;
          });
        }
      }
    });

    // Listen to cellular GPS data (fallback)
    if (!_isUsingBleDevice) {
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen((position) {
        if (mounted && !_isUsingBleDevice) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter ?? _currentPosition ?? const LatLng(45.4642, 9.19);
    final hasLine = _start != null && _end != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linea start/finish'),
        backgroundColor: kBgColor,
        actions: [
          // Bottone per centrare sulla posizione corrente
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: kBrandColor),
              onPressed: () {
                _mapController.move(_currentPosition!, 17.5);
              },
              tooltip: 'Centra su posizione',
            ),
          TextButton(
            onPressed:
                hasLine ? () => Navigator.of(context).pop(LineResult(_start!, _end!)) : null,
            child: Text(
              'Salva',
              style: TextStyle(
                color: hasLine ? kBrandColor : kMutedColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: kLineColor)),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(15),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kBrandColor.withAlpha(40),
                    border: Border.all(color: kBrandColor, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: kBrandColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seleziona la linea start/finish',
                        style: TextStyle(
                          color: kFgColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentPosition != null
                            ? 'Il marker giallo mostra la tua posizione attuale.\nTocca due punti sulla mappa: A (inizio) e B (fine).'
                            : 'Tocca due punti sulla mappa per definire la linea:\nA = inizio linea, B = fine linea.',
                        style: const TextStyle(
                          color: kMutedColor,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 17.5,
                minZoom: 15,
                maxZoom: 20,
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
                // Mappa satellitare
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.racesense.pulse',
                ),
                // Linea start/finish
                if (_start != null && _end != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_start!, _end!],
                        strokeWidth: 6,
                        color: kBrandColor,
                        borderStrokeWidth: 2,
                        borderColor: Colors.black.withAlpha(150),
                      ),
                    ],
                  ),
                // Markers per start/finish e posizione corrente
                MarkerLayer(
                  markers: [
                    // Posizione corrente dell'utente
                    if (_currentPosition != null)
                      Marker(
                        width: 56,
                        height: 56,
                        point: _currentPosition!,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer pulsing ring
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kBrandColor.withAlpha(30),
                                border: Border.all(
                                  color: kBrandColor.withAlpha(100),
                                  width: 2,
                                ),
                              ),
                            ),
                            // Inner marker
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: kBrandColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kBrandColor.withAlpha(180),
                                    blurRadius: 16,
                                    spreadRadius: 4,
                                  ),
                                  const BoxShadow(
                                    color: Colors.black,
                                    blurRadius: 8,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.navigation,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Start marker (A)
                    if (_start != null)
                      Marker(
                        width: 42,
                        height: 42,
                        point: _start!,
                        child: _FlagMarker(
                          label: 'A',
                          color: const Color(0xFF00E676),
                        ),
                      ),
                    // End marker (B)
                    if (_end != null)
                      Marker(
                        width: 42,
                        height: 42,
                        point: _end!,
                        child: _FlagMarker(
                          label: 'B',
                          color: const Color(0xFFFF1744),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: kLineColor)),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  kBgColor.withAlpha(250),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                // Status row
                Row(
                  children: [
                    // Reset button
                    OutlinedButton.icon(
                      onPressed: (_start != null || _end != null)
                          ? () {
                              setState(() {
                                _start = null;
                                _end = null;
                              });
                            }
                          : null,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text(
                        'Reset',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kBrandColor,
                        side: BorderSide(
                          color: (_start != null || _end != null) ? kBrandColor : kLineColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Status indicator
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: hasLine
                              ? kBrandColor.withAlpha(20)
                              : const Color.fromRGBO(255, 255, 255, 0.03),
                          border: Border.all(
                            color: hasLine ? kBrandColor : kLineColor,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasLine ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: hasLine ? kBrandColor : kMutedColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hasLine
                                    ? 'Linea definita (${(_start!.latitude - _end!.latitude).abs().toStringAsFixed(5)}°)'
                                    : (_start != null ? 'Seleziona punto B' : 'Seleziona punto A'),
                                style: TextStyle(
                                  color: hasLine ? kBrandColor : kMutedColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Position info (if available)
                if (_currentPosition != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color.fromRGBO(255, 255, 255, 0.03),
                      border: Border.all(color: kLineColor.withAlpha(100)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isUsingBleDevice ? Icons.bluetooth_connected : Icons.gps_fixed,
                          color: kBrandColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Posizione: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              color: kMutedColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
