import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/custom_circuit_service.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';

class CustomCircuitBuilderPage extends StatefulWidget {
  const CustomCircuitBuilderPage({super.key});

  @override
  State<CustomCircuitBuilderPage> createState() =>
      _CustomCircuitBuilderPageState();
}

enum BuilderStep { selectStartLine, tracking, finished }

class _CustomCircuitBuilderPageState extends State<CustomCircuitBuilderPage> {
  final MapController _mapController = MapController();
  final CustomCircuitService _service = CustomCircuitService();
  final BleTrackingService _bleService = BleTrackingService();

  StreamSubscription<Position>? _cellularGpsSubscription;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSubscription;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceSub;

  BuilderStep _step = BuilderStep.selectStartLine;
  bool _saving = false;

  // Step 1: Selezione linea del via
  LatLng? _startLinePointA;
  LatLng? _startLinePointB;
  LatLng? _currentPosition;

  // Tracking GPS source
  String? _connectedDeviceId;
  bool _isUsingBleDevice = false;

  // Step 2: Tracciamento
  List<LatLng> _trackPoints = [];
  double _currentSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _cellularGpsSubscription?.cancel();
    _bleGpsSubscription?.cancel();
    _bleDeviceSub?.cancel();
    super.dispose();
  }

  void _syncConnectedDeviceFromService() {
    final connectedIds = _bleService.getConnectedDeviceIds();
    if (connectedIds.isEmpty) return;
    _connectedDeviceId = connectedIds.first;
    _isUsingBleDevice = true;
  }

  void _listenBleConnectionChanges() {
    _bleDeviceSub?.cancel();
    _bleDeviceSub = _bleService.deviceStream.listen((devices) {
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
            _stopCellularTracking();
          } else {
            _connectedDeviceId = null;
            _isUsingBleDevice = false;
            _startCellularTrackingIfNeeded();
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
            _currentSpeed = data.speed ?? 0.0;
          });

          // Auto-center map during start line selection
          if (_step == BuilderStep.selectStartLine) {
            try {
              _mapController.move(data.position, _mapController.camera.zoom);
            } catch (_) {}
          }

          // Durante il tracciamento, aggiungi i punti
          if (_step == BuilderStep.tracking) {
            _trackPoints.add(data.position);
          }
        }
      }
    });

    _startCellularTrackingIfNeeded();
  }

  void _startCellularTrackingIfNeeded() {
    if (_isUsingBleDevice || _cellularGpsSubscription != null) return;
    _cellularGpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((position) {
      if (mounted && !_isUsingBleDevice) {
        final newPosition = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = newPosition;
          _currentSpeed = position.speed * 3.6; // m/s -> km/h
        });

        // Auto-center map during start line selection
        if (_step == BuilderStep.selectStartLine) {
          try {
            _mapController.move(newPosition, _mapController.camera.zoom);
          } catch (_) {}
        }

        // Durante il tracciamento, aggiungi i punti
        if (_step == BuilderStep.tracking) {
          _trackPoints.add(newPosition);
        }
      }
    });
  }

  void _stopCellularTracking() {
    _cellularGpsSubscription?.cancel();
    _cellularGpsSubscription = null;
  }

  void _startTracking() {
    if (_currentPosition == null) return;
    setState(() {
      _step = BuilderStep.tracking;
      _trackPoints = [_currentPosition!];
    });
  }

  Future<void> _finishTracking() async {
    setState(() {
      _step = BuilderStep.finished;
    });
    await _finalizeCircuit();
  }

  Future<void> _finalizeCircuit() async {
    if (_trackPoints.length < 5 || _saving) return;
    setState(() => _saving = true);
    try {
      final length = _calculateLength(_trackPoints);
      final sectors = _densifyEveryMeter(_trackPoints);
      String city = '';
      String country = '';
      try {
        final placemarks = await placemarkFromCoordinates(
            _trackPoints.first.latitude, _trackPoints.first.longitude);
        if (placemarks.isNotEmpty) {
          city = placemarks.first.locality ??
              placemarks.first.administrativeArea ??
              '';
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
                  style: const TextStyle(color: kFgColor),
                  decoration: const InputDecoration(
                    labelText: 'Nome circuito',
                    labelStyle: TextStyle(color: kMutedColor),
                  ),
                ),
                TextField(
                  controller: widthCtrl,
                  style: const TextStyle(color: kFgColor),
                  decoration: const InputDecoration(
                    labelText: 'Larghezza (metri)',
                    labelStyle: TextStyle(color: kMutedColor),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                Text(
                  'Lunghezza: ${length.toStringAsFixed(0)} m',
                  style: const TextStyle(color: kMutedColor, fontSize: 12),
                ),
                if (city.isNotEmpty || country.isNotEmpty)
                  Text(
                    '$city $country'.trim(),
                    style: const TextStyle(color: kMutedColor, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                if (_isUsingBleDevice)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: kBrandColor.withAlpha(20),
                      border: Border.all(color: kBrandColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.bluetooth_connected,
                            color: kBrandColor, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Tracciato con dispositivo BLE',
                          style: TextStyle(color: kBrandColor, fontSize: 11),
                        ),
                      ],
                    ),
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
                    name: nameCtrl.text.isEmpty
                        ? 'Circuito custom'
                        : nameCtrl.text,
                    widthMeters: width,
                  ));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandColor,
                  foregroundColor: Colors.black,
                ),
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

      if (!mounted) return;
      final progressNotifier = ValueNotifier<double>(0.0);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) => Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A20), Color(0xFF0F0F15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kLineColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.track_changes, color: kBrandColor, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Salvataggio circuito',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: kLineColor,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(kBrandColor),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: kBrandColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      progressNotifier.value = 0.1;
      final microSectors = CustomCircuitInfo.buildSectorsFromPoints(
        sectors,
        widthMeters: result.widthMeters,
      );
      progressNotifier.value = 0.2;

      final circuit = CustomCircuitInfo(
        name: result.name,
        widthMeters: result.widthMeters,
        city: city,
        country: country,
        lengthMeters: length,
        createdAt: DateTime.now(),
        points: sectors,
        microSectors: microSectors,
        usedBleDevice: _isUsingBleDevice,
      );

      try {
        await _service.saveCircuit(
          circuit,
          onProgress: (p) => progressNotifier.value = p,
        );
        if (!mounted) return;
        Navigator.of(context).pop(); // chiudi progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Circuito custom salvato'),
            backgroundColor: kBrandColor,
          ),
        );
        Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop(); // chiudi progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: kErrorColor,
          ),
        );
      }
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
    return Scaffold(
      body: PulseBackground(
        withTopPadding: false,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _step == BuilderStep.selectStartLine
                    ? _buildStartLineSelection()
                    : _buildTrackingView(),
              ),
              if (_step == BuilderStep.selectStartLine)
                _buildStartLineBottomPanel()
              else
                _buildTrackingBottomPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kLineColor, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: kFgColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crea circuito custom',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      _isUsingBleDevice
                          ? Icons.bluetooth_connected
                          : Icons.gps_fixed,
                      color: kBrandColor,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isUsingBleDevice
                          ? 'Dispositivo BLE connesso'
                          : 'GPS cellulare',
                      style: const TextStyle(
                        fontSize: 11,
                        color: kMutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_step == BuilderStep.tracking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    );
  }

  Widget _buildStartLineSelection() {
    final center = _currentPosition ?? const LatLng(45.4642, 9.19);
    final hasLine = _startLinePointA != null && _startLinePointB != null;

    return Stack(
      children: [
        FlutterMap(
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
                if (_startLinePointA == null ||
                    (_startLinePointA != null && _startLinePointB != null)) {
                  _startLinePointA = point;
                  _startLinePointB = null;
                } else {
                  _startLinePointB = point;
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
            if (_startLinePointA != null && _startLinePointB != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [_startLinePointA!, _startLinePointB!],
                    strokeWidth: 6,
                    color: kBrandColor,
                    borderStrokeWidth: 2,
                    borderColor: Colors.black.withAlpha(150),
                  ),
                ],
              ),
            // Markers
            MarkerLayer(
              markers: [
                // Posizione corrente
                if (_currentPosition != null)
                  Marker(
                    width: 56,
                    height: 56,
                    point: _currentPosition!,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
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
                // Point A
                if (_startLinePointA != null)
                  Marker(
                    width: 42,
                    height: 42,
                    point: _startLinePointA!,
                    child: _FlagMarker(
                      label: 'A',
                      color: const Color(0xFF00E676),
                    ),
                  ),
                // Point B
                if (_startLinePointB != null)
                  Marker(
                    width: 42,
                    height: 42,
                    point: _startLinePointB!,
                    child: _FlagMarker(
                      label: 'B',
                      color: const Color(0xFFFF1744),
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Info banner
        Positioned(
          top: 20,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(15),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(color: kBrandColor, width: 1.5),
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
                const Expanded(
                  child: Text(
                    'Tocca due punti sulla mappa per definire la linea del via: A (inizio) e B (fine)',
                    style: TextStyle(
                      color: kFgColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartLineBottomPanel() {
    final hasLine = _startLinePointA != null && _startLinePointB != null;
    final canStart = hasLine && _currentPosition != null;

    return Container(
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
          Row(
            children: [
              OutlinedButton.icon(
                onPressed:
                    (_startLinePointA != null || _startLinePointB != null)
                        ? () {
                            setState(() {
                              _startLinePointA = null;
                              _startLinePointB = null;
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
                    color:
                        (_startLinePointA != null || _startLinePointB != null)
                            ? kBrandColor
                            : kLineColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        hasLine
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: hasLine ? kBrandColor : kMutedColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasLine
                              ? 'Linea definita'
                              : (_startLinePointA != null
                                  ? 'Seleziona punto B'
                                  : 'Seleziona punto A'),
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
                    _isUsingBleDevice
                        ? Icons.bluetooth_connected
                        : Icons.gps_fixed,
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
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: canStart ? _startTracking : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text(
              'Inizia tracciamento',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: kBrandColor,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingView() {
    final center = _trackPoints.isNotEmpty
        ? _trackPoints.last
        : (_currentPosition ?? const LatLng(45.0, 9.0));

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 17.5,
        backgroundColor: const Color(0xFF0A0A0A),
      ),
      children: [
        // Mappa satellitare
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.racesense.pulse',
        ),
        // Traccia
        if (_trackPoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _trackPoints,
                strokeWidth: 5,
                color: kBrandColor,
                borderStrokeWidth: 2,
                borderColor: Colors.black.withAlpha(100),
              ),
            ],
          ),
        // Marker posizione corrente
        if (_trackPoints.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: _trackPoints.last,
                width: 14,
                height: 14,
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: kBrandColor,
                    boxShadow: [
                      BoxShadow(
                        color: kBrandColor,
                        blurRadius: 12,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTrackingBottomPanel() {
    final length = _calculateLength(_trackPoints);
    final speedColor = (_currentSpeed >= 10 && _currentSpeed <= 40)
        ? const Color(0xFF00E676)
        : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kLineColor, width: 1)),
      ),
      child: Column(
        children: [
          // Info boxes in a single row with dividers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                icon: Icons.straighten,
                label: 'Metri',
                value: length.toStringAsFixed(0),
              ),
              Container(
                width: 1,
                height: 40,
                color: kLineColor,
              ),
              _buildInfoItem(
                icon: Icons.gps_fixed,
                label: 'Punti GPS',
                value: _trackPoints.length.toString(),
              ),
              Container(
                width: 1,
                height: 40,
                color: kLineColor,
              ),
              _buildInfoItem(
                icon: Icons.speed,
                label: 'Velocità',
                value: '${_currentSpeed.toStringAsFixed(1)} km/h',
                valueColor: speedColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _saving ? null : _finishTracking,
            icon: const Icon(Icons.stop),
            label: const Text(
              'Fine tracciamento',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kBrandColor, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: kMutedColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? kFgColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CircuitMeta {
  final String name;
  final double widthMeters;

  _CircuitMeta({required this.name, required this.widthMeters});
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
