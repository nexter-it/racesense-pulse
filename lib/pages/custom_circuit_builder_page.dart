import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/custom_circuit_service.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';
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

// Premium UI constants
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class _CustomCircuitBuilderPageState extends State<CustomCircuitBuilderPage>
    with SingleTickerProviderStateMixin {
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

  // Animation for recording indicator
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
    _startTracking();
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
      _showErrorSnackBar('Traccia GPS troppo corta. Fai almeno 2-3 giri completi.');
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFFF453A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
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
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Circuito custom salvato con successo'),
            ],
          ),
          backgroundColor: kBrandColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      Navigator.of(context).pop(); // torna indietro
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // chiudi progress dialog
      _showErrorSnackBar('Errore: $e');
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

  /// Dialog per nome circuito - Premium style
  Future<String?> _showNameDialog(String city, String country, double length) async {
    final nameCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBrandColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.save_outlined, color: kBrandColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Salva Circuito',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // TextField
              Container(
                decoration: BoxDecoration(
                  color: _kTileColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorderColor),
                ),
                child: TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nome circuito',
                    labelStyle: TextStyle(color: kMutedColor.withAlpha(180)),
                    hintText: 'es. Autodromo locale',
                    hintStyle: TextStyle(color: kMutedColor.withAlpha(100)),
                    prefixIcon: Icon(Icons.edit_road, color: kMutedColor.withAlpha(150), size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Info grid
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kTileColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorderColor),
                ),
                child: Column(
                  children: [
                    _dialogInfoRow(Icons.straighten, 'Lunghezza', '${(length / 1000).toStringAsFixed(2)} km', const Color(0xFF5AC8FA)),
                    if (city.isNotEmpty || country.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _dialogInfoRow(Icons.place_outlined, 'Località', '$city $country'.trim(), const Color(0xFF4CD964)),
                    ],
                    const SizedBox(height: 10),
                    _dialogInfoRow(Icons.gps_fixed, 'Punti GPS', '${_gpsTrack.length}', const Color(0xFFFF9500)),
                    const SizedBox(height: 10),
                    _dialogInfoRow(Icons.speed, 'Frequenza', '${_estimateGpsFrequency().toStringAsFixed(1)} Hz', const Color(0xFFAF52DE)),
                  ],
                ),
              ),

              // BLE Badge
              if (_isUsingBleDevice) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [kBrandColor.withAlpha(30), kBrandColor.withAlpha(10)],
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.bluetooth_connected, color: kBrandColor, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Tracciato con dispositivo BLE',
                        style: TextStyle(color: kBrandColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _kBorderColor),
                        ),
                      ),
                      child: Text(
                        'Annulla',
                        style: TextStyle(color: kMutedColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        Navigator.of(context).pop(name.isEmpty ? 'Circuito custom' : name);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrandColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Salva Circuito',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: kMutedColor, fontSize: 12)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildProgressDialog(double progress) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(100),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_outlined, color: kBrandColor, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Salvataggio circuito',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Caricamento su Firebase...',
              style: TextStyle(fontSize: 13, color: kMutedColor),
            ),
            const SizedBox(height: 24),
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(kBrandColor),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 28,
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
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildTrackingView()),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: _kBorderColor)),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              if (_gpsTrack.isEmpty) {
                Navigator.of(context).pop();
              } else {
                _showExitDialog();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorderColor),
              ),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 16),

          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tracciamento Circuito',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kBrandColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                              fontSize: 10,
                              color: kBrandColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // REC indicator
          if (_step == BuilderStep.tracking)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.withAlpha((60 * _pulseAnimation.value).toInt()),
                      Colors.red.withAlpha((30 * _pulseAnimation.value).toInt()),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.withAlpha((200 * _pulseAnimation.value).toInt()),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha((255 * _pulseAnimation.value).toInt()),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withAlpha((100 * _pulseAnimation.value).toInt()),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Annullare tracciamento?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Perderai tutti i ${_gpsTrack.length} punti GPS registrati.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kMutedColor, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _kBorderColor),
                        ),
                      ),
                      child: Text('Continua', style: TextStyle(color: kMutedColor, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Annulla', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingView() {
    final center = _displayPath.isNotEmpty
        ? _displayPath.last
        : (_currentPosition ?? const LatLng(45.0, 9.0));

    return Stack(
      children: [
        // Map
        ClipRRect(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 17.0,
              backgroundColor: _kBgColor,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              // Satellite tiles
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.racesense.pulse',
              ),
              // GPS Track
              if (_displayPath.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _displayPath,
                      strokeWidth: 5,
                      color: kBrandColor,
                      borderStrokeWidth: 2,
                      borderColor: Colors.black.withAlpha(150),
                    ),
                  ],
                ),
              // Current position marker
              if (_displayPath.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _displayPath.last,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kBrandColor,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: kBrandColor.withAlpha(150),
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
        ),

        // Instructions banner
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kCardStart, _kCardEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBrandColor.withAlpha(100)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.track_changes, color: kBrandColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fai 2-3 giri completi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Posizionerai la linea S/F dopo',
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
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    final length = _calculateLength(_displayPath);
    final speedColor = (_currentSpeed >= 10 && _currentSpeed <= 80)
        ? const Color(0xFF4CD964)
        : const Color(0xFFFF453A);
    final minPoints = 50;
    final hasEnoughPoints = _gpsTrack.length >= minPoints;
    final progress = (_gpsTrack.length / minPoints).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(top: BorderSide(color: _kBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Stats row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kTileColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorderColor),
            ),
            child: Row(
              children: [
                Expanded(child: _buildStatTile(Icons.timer_outlined, 'Tempo', _getElapsedTime(), const Color(0xFF5AC8FA))),
                _verticalDivider(),
                Expanded(child: _buildStatTile(Icons.straighten, 'Distanza', '${(length / 1000).toStringAsFixed(2)} km', const Color(0xFF4CD964))),
                _verticalDivider(),
                Expanded(child: _buildStatTile(Icons.location_on_outlined, 'Punti', _gpsTrack.length.toString(), const Color(0xFFFF9500))),
                _verticalDivider(),
                Expanded(child: _buildStatTile(Icons.speed, 'Velocità', '${_currentSpeed.toStringAsFixed(0)}', speedColor, suffix: 'km/h')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Progress bar for minimum points
          if (!hasEnoughPoints) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kTileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: kMutedColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Minimo ${minPoints} punti GPS richiesti',
                          style: TextStyle(color: kMutedColor, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: _kBorderColor,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress < 0.5 ? Colors.red : (progress < 1.0 ? Colors.orange : kBrandColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_gpsTrack.length}/$minPoints',
                    style: TextStyle(
                      color: hasEnoughPoints ? kBrandColor : kMutedColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action button
          GestureDetector(
            onTap: _saving || !hasEnoughPoints ? null : _finishTracking,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: hasEnoughPoints
                    ? const LinearGradient(colors: [kBrandColor, Color(0xFF00D4AA)])
                    : null,
                color: hasEnoughPoints ? null : _kTileColor,
                borderRadius: BorderRadius.circular(14),
                border: hasEnoughPoints ? null : Border.all(color: _kBorderColor),
                boxShadow: hasEnoughPoints
                    ? [
                        BoxShadow(
                          color: kBrandColor.withAlpha(60),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasEnoughPoints ? Icons.flag : Icons.hourglass_top,
                    color: hasEnoughPoints ? Colors.black : kMutedColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasEnoughPoints ? 'Fine tracciamento' : 'Continua tracciamento...',
                    style: TextStyle(
                      color: hasEnoughPoints ? Colors.black : kMutedColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(IconData icon, String label, String value, Color color, {String? suffix}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: kMutedColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (suffix != null)
              Text(
                ' $suffix',
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: _kBorderColor,
    );
  }
}
