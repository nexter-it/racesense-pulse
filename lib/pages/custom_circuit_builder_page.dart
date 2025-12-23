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
import 'draw_finish_line_page.dart';

/// Pagina per creare un circuito custom - Flusso RaceChrono Pro
///
/// 1. Utente fa più giri nel circuito (registrazione GPS grezzo)
/// 2. Fine tracciamento → naviga a DrawFinishLinePage
/// 3. Utente disegna manualmente linea S/F sulla traccia
/// 4. Post-processing calcola lap e lunghezza circuito
/// 5. Salvataggio su Firebase
class CustomCircuitBuilderPage extends StatefulWidget {
  const CustomCircuitBuilderPage({super.key});

  @override
  State<CustomCircuitBuilderPage> createState() =>
      _CustomCircuitBuilderPageState();
}

enum BuilderStep { tracking, finished }

class _CustomCircuitBuilderPageState extends State<CustomCircuitBuilderPage> {
  final MapController _mapController = MapController();
  final CustomCircuitService _service = CustomCircuitService();
  final BleTrackingService _bleService = BleTrackingService();

  StreamSubscription<Position>? _cellularGpsSubscription;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSubscription;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceSub;

  BuilderStep _step = BuilderStep.tracking;
  bool _saving = false;

  // GPS tracking
  LatLng? _currentPosition;
  String? _connectedDeviceId;
  bool _isUsingBleDevice = false;

  // Traccia GPS completa (grezzo)
  List<Position> _gpsTrack = [];
  List<LatLng> _displayPath = []; // Per visualizzazione mappa
  double _currentSpeed = 0.0;
  DateTime? _trackingStartTime;

  @override
  void initState() {
    super.initState();
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
    _startTracking();
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

  /// Avvia tracciamento GPS immediato
  void _startTracking() {
    _trackingStartTime = DateTime.now();
    _gpsTrack.clear();
    _displayPath.clear();

    // Listen to BLE GPS data
    _bleGpsSubscription = _bleService.gpsStream.listen((gpsData) {
      if (_connectedDeviceId != null && _isUsingBleDevice) {
        final data = gpsData[_connectedDeviceId!];
        if (data != null && mounted && _step == BuilderStep.tracking) {
          // Crea Position da BLE GPS data
          final position = Position(
            latitude: data.position.latitude,
            longitude: data.position.longitude,
            timestamp: DateTime.now(),
            accuracy: 5.0, // BLE GPS tipicamente ha accuratezza ~5m
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: (data.speed ?? 0.0) / 3.6, // km/h → m/s
            speedAccuracy: 0.0,
          );

          setState(() {
            _currentPosition = data.position;
            _currentSpeed = data.speed ?? 0.0;
            _gpsTrack.add(position);
            _displayPath.add(data.position);
          });

          // Auto-center map
          try {
            _mapController.move(data.position, _mapController.camera.zoom);
          } catch (_) {}
        }
      }
    });

    _startCellularTrackingIfNeeded();
  }

  void _startCellularTrackingIfNeeded() {
    if (_isUsingBleDevice || _cellularGpsSubscription != null) return;
    _cellularGpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // Nessun filtro: GPS grezzo completo
      ),
    ).listen((position) {
      if (mounted && !_isUsingBleDevice && _step == BuilderStep.tracking) {
        final newPosition = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = newPosition;
          _currentSpeed = position.speed * 3.6; // m/s → km/h
          _gpsTrack.add(position);
          _displayPath.add(newPosition);
        });

        // Auto-center map
        try {
          _mapController.move(newPosition, _mapController.camera.zoom);
        } catch (_) {}
      }
    });
  }

  void _stopCellularTracking() {
    _cellularGpsSubscription?.cancel();
    _cellularGpsSubscription = null;
  }

  /// Fine tracciamento → naviga a DrawFinishLinePage
  Future<void> _finishTracking() async {
    if (_gpsTrack.length < 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Traccia GPS troppo corta. Fai almeno 2-3 giri completi.'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    setState(() {
      _step = BuilderStep.finished;
    });

    // Ferma GPS tracking
    _cellularGpsSubscription?.cancel();
    _bleGpsSubscription?.cancel();

    // Naviga a DrawFinishLinePage
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawFinishLinePage(
          gpsTrack: _gpsTrack,
          trackName: 'Nuovo Circuito Custom',
          usedBleDevice: _isUsingBleDevice,
        ),
      ),
    );

    if (result == null) {
      // Utente ha annullato → torna a tracking
      setState(() {
        _step = BuilderStep.tracking;
      });
      _startTracking();
      return;
    }

    // Utente ha confermato linea S/F → salva circuito
    await _saveCircuit(
      finishLineStart: result['finishLineStart'] as LatLng,
      finishLineEnd: result['finishLineEnd'] as LatLng,
      processingResult: result['processingResult'],
    );
  }

  /// Salva circuito su Firebase
  Future<void> _saveCircuit({
    required LatLng finishLineStart,
    required LatLng finishLineEnd,
    required dynamic processingResult,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // Geocoding per city/country
      String city = '';
      String country = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          _displayPath.first.latitude,
          _displayPath.first.longitude,
        );
        if (placemarks.isNotEmpty) {
          city = placemarks.first.locality ??
              placemarks.first.administrativeArea ??
              '';
          country = placemarks.first.country ?? '';
        }
      } catch (_) {}

      // Calcola lunghezza stimata dalla traccia
      final length = _calculateLength(_displayPath);

      // Mostra dialog per nome circuito
      final name = await _showNameDialog(city, country, length);
      if (name == null) {
        setState(() => _saving = false);
        return;
      }

      // Mostra progress dialog
      if (!mounted) return;
      final progressNotifier = ValueNotifier<double>(0.0);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) => _buildProgressDialog(progress),
        ),
      );

      progressNotifier.value = 0.1;

      // Crea CustomCircuitInfo (SENZA microsettori)
      final circuit = CustomCircuitInfo(
        name: name,
        widthMeters: 0.0, // Non più usato
        city: city,
        country: country,
        lengthMeters: length,
        createdAt: DateTime.now(),
        points: _displayPath,
        microSectors: [], // Vuoto: non usiamo più microsettori
        usedBleDevice: _isUsingBleDevice,
        finishLineStart: finishLineStart,
        finishLineEnd: finishLineEnd,
        gpsFrequencyHz: _estimateGpsFrequency(),
      );

      progressNotifier.value = 0.3;

      // Salva su Firebase
      await _service.saveCircuit(
        circuit,
        onProgress: (p) => progressNotifier.value = 0.3 + (p * 0.7),
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // chiudi progress dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Circuito custom salvato con successo'),
          backgroundColor: kBrandColor,
        ),
      );

      Navigator.of(context).pop(); // torna indietro
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // chiudi progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: kErrorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Stima frequenza GPS media (Hz)
  double _estimateGpsFrequency() {
    if (_gpsTrack.length < 10) return 1.0;

    final intervals = <int>[];
    for (int i = 1; i < _gpsTrack.length && i < 50; i++) {
      final interval = _gpsTrack[i]
          .timestamp!
          .difference(_gpsTrack[i - 1].timestamp!)
          .inMilliseconds;
      if (interval > 0 && interval < 5000) {
        intervals.add(interval);
      }
    }

    if (intervals.isEmpty) return 1.0;
    final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    return 1000.0 / avgInterval;
  }

  /// Dialog per nome circuito
  Future<String?> _showNameDialog(String city, String country, double length) async {
    final nameCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome circuito',
                labelStyle: TextStyle(color: kMutedColor),
                hintText: 'es. Autodromo locale',
                hintStyle: TextStyle(color: kMutedColor),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Lunghezza: ${(length / 1000).toStringAsFixed(2)} km',
              style: const TextStyle(color: kMutedColor, fontSize: 12),
            ),
            if (city.isNotEmpty || country.isNotEmpty)
              Text(
                '$city $country'.trim(),
                style: const TextStyle(color: kMutedColor, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Text(
              '${_gpsTrack.length} punti GPS - ${_estimateGpsFrequency().toStringAsFixed(1)} Hz',
              style: const TextStyle(color: kMutedColor, fontSize: 11),
            ),
            if (_isUsingBleDevice) ...[
              const SizedBox(height: 12),
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
                    Icon(Icons.bluetooth_connected, color: kBrandColor, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Tracciato con dispositivo BLE',
                      style: TextStyle(color: kBrandColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              Navigator.of(context).pop(name.isEmpty ? 'Circuito custom' : name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressDialog(double progress) {
    return Center(
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
                valueColor: const AlwaysStoppedAnimation<Color>(kBrandColor),
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
    );
  }

  double _calculateLength(List<LatLng> pts) {
    final dist = Distance();
    double sum = 0.0;
    for (int i = 1; i < pts.length; i++) {
      sum += dist(pts[i - 1], pts[i]);
    }
    return sum;
  }

  /// Calcola tempo trascorso
  String _getElapsedTime() {
    if (_trackingStartTime == null) return '0:00';
    final elapsed = DateTime.now().difference(_trackingStartTime!);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
              Expanded(child: _buildTrackingView()),
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
            onPressed: () {
              if (_gpsTrack.isEmpty) {
                Navigator.of(context).pop();
              } else {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF0F0F15),
                    title: const Text('Annullare tracciamento?', style: TextStyle(color: kFgColor)),
                    content: const Text(
                      'Perderai tutti i dati GPS registrati.',
                      style: TextStyle(color: kMutedColor),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('No'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: kErrorColor),
                        child: const Text('Sì, annulla'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tracciamento Circuito',
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
                      _isUsingBleDevice ? Icons.bluetooth_connected : Icons.gps_fixed,
                      color: kBrandColor,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isUsingBleDevice
                          ? 'GPS BLE ${_estimateGpsFrequency().toStringAsFixed(0)}Hz'
                          : 'GPS cellulare 1Hz',
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'REC',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
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

  Widget _buildTrackingView() {
    final center = _displayPath.isNotEmpty
        ? _displayPath.last
        : (_currentPosition ?? const LatLng(45.0, 9.0));

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 17.0,
            backgroundColor: const Color(0xFF0A0A0A),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            // Mappa satellitare
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.racesense.pulse',
            ),
            // Traccia GPS
            if (_displayPath.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _displayPath,
                    strokeWidth: 5,
                    color: kBrandColor,
                    borderStrokeWidth: 2,
                    borderColor: Colors.black.withAlpha(100),
                  ),
                ],
              ),
            // Marker posizione corrente
            if (_displayPath.isNotEmpty)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _displayPath.last,
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: kBrandColor,
                        boxShadow: [
                          BoxShadow(
                            color: kBrandColor,
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Banner istruzioni
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(20),
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
                    Icons.track_changes,
                    color: kBrandColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Fai 2-3 giri completi del circuito.\nPosizionerai la linea S/F dopo.',
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

  Widget _buildTrackingBottomPanel() {
    final length = _calculateLength(_displayPath);
    final speedColor = (_currentSpeed >= 10 && _currentSpeed <= 80)
        ? const Color(0xFF00E676)
        : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kLineColor, width: 1)),
      ),
      child: Column(
        children: [
          // Statistiche
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                icon: Icons.timer,
                label: 'Tempo',
                value: _getElapsedTime(),
              ),
              Container(width: 1, height: 40, color: kLineColor),
              _buildInfoItem(
                icon: Icons.straighten,
                label: 'Distanza',
                value: '${(length / 1000).toStringAsFixed(2)} km',
              ),
              Container(width: 1, height: 40, color: kLineColor),
              _buildInfoItem(
                icon: Icons.gps_fixed,
                label: 'Punti GPS',
                value: _gpsTrack.length.toString(),
              ),
              Container(width: 1, height: 40, color: kLineColor),
              _buildInfoItem(
                icon: Icons.speed,
                label: 'Velocità',
                value: '${_currentSpeed.toStringAsFixed(0)} km/h',
                valueColor: speedColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Bottone fine tracciamento
          ElevatedButton.icon(
            onPressed: _saving ? null : _finishTracking,
            icon: const Icon(Icons.flag),
            label: Text(
              _gpsTrack.length < 50
                  ? 'Continua tracciamento (${_gpsTrack.length}/50 punti min)'
                  : 'Fine tracciamento e disegna linea S/F',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: _gpsTrack.length < 50 ? kLineColor : kBrandColor,
              foregroundColor: _gpsTrack.length < 50 ? kMutedColor : Colors.black,
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
        Icon(icon, color: kBrandColor, size: 18),
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
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
