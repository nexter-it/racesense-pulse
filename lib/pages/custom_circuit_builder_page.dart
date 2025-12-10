import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/custom_circuit_service.dart';
import '../theme.dart';

class CustomCircuitBuilderPage extends StatefulWidget {
  const CustomCircuitBuilderPage({super.key});

  @override
  State<CustomCircuitBuilderPage> createState() =>
      _CustomCircuitBuilderPageState();
}

class _CustomCircuitBuilderPageState extends State<CustomCircuitBuilderPage> {
  final MapController _mapController = MapController();
  final CustomCircuitService _service = CustomCircuitService();
  StreamSubscription<Position>? _gpsSub;

  bool _hasPermission = false;
  bool _hasFix = false;
  bool _recording = false;
  bool _saving = false;

  List<LatLng> _track = [];
  Position? _lastPos;

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    super.dispose();
  }

  Future<void> _initGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    setState(() => _hasPermission = true);

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );
    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _lastPos = pos;
        if (!_hasFix) {
          setState(() {
            _hasFix = true;
          });
        }
        if (_recording) {
          final p = LatLng(pos.latitude, pos.longitude);
          _track.add(p);
          _mapController.move(p, _mapController.camera.zoom);
          setState(() {});
        }
      },
    );
  }

  Future<void> _toggleRecording() async {
    if (!_recording) {
      if (!_hasFix || _lastPos == null) return;
      setState(() {
        _track = [LatLng(_lastPos!.latitude, _lastPos!.longitude)];
        _recording = true;
      });
    } else {
      setState(() => _recording = false);
      await _finalizeCircuit();
    }
  }

  Future<void> _finalizeCircuit() async {
    if (_track.length < 5 || _saving) return;
    setState(() => _saving = true);
    try {
      final length = _calculateLength(_track);
      final sectors = _densifyEveryMeter(_track);
      String city = '';
      String country = '';
      try {
        final placemarks = await placemarkFromCoordinates(
            _track.first.latitude, _track.first.longitude);
        if (placemarks.isNotEmpty) {
          city = placemarks.first.locality ?? placemarks.first.administrativeArea ?? '';
          country = placemarks.first.country ?? '';
        }
      } catch (_) {}

      final result = await showDialog<_CircuitMeta>(
        context: context,
        builder: (context) {
          final nameCtrl = TextEditingController();
          final widthCtrl = TextEditingController(text: '8');
          return AlertDialog(
            backgroundColor: const Color(0xFF0F0F15),
            title: const Text(
              'Salva circuito',
              style: TextStyle(color: kFgColor),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome circuito',
                  ),
                ),
                TextField(
                  controller: widthCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Larghezza (metri)',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lunghezza: ${length.toStringAsFixed(0)} m',
                  style: const TextStyle(color: kMutedColor, fontSize: 12),
                ),
                if (city.isNotEmpty || country.isNotEmpty)
                  Text(
                    '$city $country'.trim(),
                    style: const TextStyle(color: kMutedColor, fontSize: 12),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: () {
                  final width = double.tryParse(widthCtrl.text) ?? 8.0;
                  Navigator.of(context).pop(_CircuitMeta(
                    name: nameCtrl.text.isEmpty ? 'Circuito custom' : nameCtrl.text,
                    widthMeters: width,
                  ));
                },
                child: const Text('Salva'),
              ),
            ],
          );
        },
      );

      if (result == null) {
        setState(() => _saving = false);
        return;
      }

      final circuit = CustomCircuitInfo(
        name: result.name,
        widthMeters: result.widthMeters,
        city: city,
        country: country,
        lengthMeters: length,
        createdAt: DateTime.now(),
        points: sectors,
        microSectors: CustomCircuitInfo.buildSectorsFromPoints(sectors, widthMeters: result.widthMeters),
      );

      await _service.saveCircuit(circuit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Circuito custom salvato'),
          backgroundColor: kBrandColor,
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  double _calculateLength(List<LatLng> pts) {
    final dist = Distance();
    double sum = 0.0;
    for (int i = 1; i < pts.length; i++) {
      sum += dist(pts[i - 1], pts[i]);
    }
    return sum;
  }

  List<LatLng> _densifyEveryMeter(List<LatLng> pts) {
    if (pts.length < 2) return pts;
    final dist = Distance();
    final List<LatLng> result = [];
    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final segment = dist(a, b);
      if (segment <= 1) {
        if (result.isEmpty) result.add(a);
        result.add(b);
        continue;
      }
      final steps = segment.floor();
      for (int s = 0; s <= steps; s++) {
        final t = s / segment;
        final lat = a.latitude + (b.latitude - a.latitude) * t;
        final lon = a.longitude + (b.longitude - a.longitude) * t;
        result.add(LatLng(lat, lon));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final currentCenter = _track.isNotEmpty
        ? _track.last
        : (_lastPos != null
            ? LatLng(_lastPos!.latitude, _lastPos!.longitude)
            : const LatLng(45.0, 9.0));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Traccia circuito custom',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (_recording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red),
                      ),
                      child: const Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: currentCenter,
                      initialZoom: 17,
                      backgroundColor: const Color(0xFF0A0A0A),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'racesense_pulse',
                      ),
                      if (_track.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _track,
                              strokeWidth: 5,
                              color: kBrandColor,
                            ),
                          ],
                        ),
                      if (_track.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _track.last,
                              width: 14,
                              height: 14,
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: kBrandColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // Banner istruzioni quando non si sta registrando
                  if (!_recording && _hasFix)
                    Positioned(
                      top: 20,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              kBrandColor.withOpacity(0.95),
                              kBrandWeakColor.withOpacity(0.95),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: kBrandColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: kBrandColor.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.3),
                              ),
                              child: const Icon(
                                Icons.info_outline,
                                color: Colors.black,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Posizionati sulla linea del via e premi "Inizia tracciamento"',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _recording
                              ? 'Tracciamento in corso...'
                              : (_hasFix
                                  ? 'GPS pronto'
                                  : 'Attendi fix GPS...'),
                          style: TextStyle(
                            color:
                                _hasFix ? kMutedColor : kMutedColor.withOpacity(0.7),
                          ),
                        ),
                      ),
                      if (_track.isNotEmpty)
                        Text(
                          '${_calculateLength(_track).toStringAsFixed(0)} m',
                          style: const TextStyle(
                              color: kFgColor, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed:
                        (!_hasPermission || (!_hasFix && !_recording) || _saving)
                            ? null
                            : _toggleRecording,
                    icon: Icon(_recording ? Icons.stop : Icons.play_arrow),
                    label: Text(_recording
                        ? 'Fine tracciamento'
                        : 'Inizia tracciamento'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                          _recording ? Colors.redAccent : kBrandColor,
                      foregroundColor:
                          _recording ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Premi “Inizia” dopo il fix GPS. “Fine” salva il circuito.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kMutedColor, fontSize: 12),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _CircuitMeta {
  final String name;
  final double widthMeters;

  _CircuitMeta({required this.name, required this.widthMeters});
}
