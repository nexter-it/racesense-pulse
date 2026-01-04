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

/// Pagina per creare un circuito custom - Flusso semplificato
///
/// 1. Mostra mappa con posizione GPS attuale (cellulare o BLE)
/// 2. Utente naviga direttamente a DrawFinishLinePage
/// 3. Utente disegna manualmente linea S/F sulla mappa
/// 4. Durante la sessione verrà tracciata la traccia GPS e calcolati i giri
/// 5. Salvataggio su Firebase
class CustomCircuitBuilderPage extends StatefulWidget {
  const CustomCircuitBuilderPage({super.key});

  @override
  State<CustomCircuitBuilderPage> createState() =>
      _CustomCircuitBuilderPageState();
}

enum BuilderStep { positioning, finished }

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

  BuilderStep _step = BuilderStep.positioning;
  bool _saving = false;

  // GPS positioning
  LatLng? _currentPosition;
  String? _connectedDeviceId;
  bool _isUsingBleDevice = false;

  // Posizione GPS corrente
  double _currentSpeed = 0.0;
  double _currentAccuracy = 0.0;

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
    _startPositioning();
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
            _stopCellularPositioning();
          } else {
            _connectedDeviceId = null;
            _isUsingBleDevice = false;
            _startCellularPositioningIfNeeded();
          }
        });
      }
    });
  }

  /// Avvia monitoraggio posizione GPS
  void _startPositioning() {
    // Listen to BLE GPS data
    _bleGpsSubscription = _bleService.gpsStream.listen((gpsData) {
      if (_connectedDeviceId != null && _isUsingBleDevice) {
        final data = gpsData[_connectedDeviceId!];
        if (data != null && mounted && _step == BuilderStep.positioning) {
          setState(() {
            _currentPosition = data.position;
            _currentSpeed = data.speed ?? 0.0;
            _currentAccuracy = 5.0; // BLE GPS tipicamente ha accuratezza ~5m
          });

          // Auto-center map
          try {
            _mapController.move(data.position, _mapController.camera.zoom);
          } catch (_) {}
        }
      }
    });

    _startCellularPositioningIfNeeded();
  }

  void _startCellularPositioningIfNeeded() {
    if (_isUsingBleDevice || _cellularGpsSubscription != null) return;
    _cellularGpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((position) {
      if (mounted && !_isUsingBleDevice && _step == BuilderStep.positioning) {
        final newPosition = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = newPosition;
          _currentSpeed = position.speed * 3.6; // m/s → km/h
          _currentAccuracy = position.accuracy;
        });

        // Auto-center map
        try {
          _mapController.move(newPosition, _mapController.camera.zoom);
        } catch (_) {}
      }
    });
  }

  void _stopCellularPositioning() {
    _cellularGpsSubscription?.cancel();
    _cellularGpsSubscription = null;
  }

  /// Naviga direttamente a DrawFinishLinePage per selezione linea S/F
  Future<void> _selectFinishLine() async {
    if (_currentPosition == null) {
      _showErrorSnackBar('Attendi il fix GPS prima di continuare.');
      return;
    }

    setState(() {
      _step = BuilderStep.finished;
    });

    // Ferma aggiornamenti posizione
    _cellularGpsSubscription?.cancel();
    _bleGpsSubscription?.cancel();

    // Naviga a DrawFinishLinePage - senza traccia GPS pregressa
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawFinishLinePage(
          gpsTrack: [], // Traccia vuota - l'utente selezionerà solo la linea
          trackName: 'Nuovo Circuito Custom',
          usedBleDevice: _isUsingBleDevice,
          initialCenter: _currentPosition,
        ),
      ),
    );

    if (result == null) {
      // Utente ha annullato → torna a positioning
      setState(() {
        _step = BuilderStep.positioning;
      });
      _startPositioning();
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
      // Geocoding per city/country dalla posizione corrente
      String city = '';
      String country = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        if (placemarks.isNotEmpty) {
          city = placemarks.first.locality ??
              placemarks.first.administrativeArea ??
              '';
          country = placemarks.first.country ?? '';
        }
      } catch (_) {}

      // Calcola lunghezza stimata dalla linea di traguardo
      final dist = Distance();
      final length = dist(finishLineStart, finishLineEnd);

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

      // Crea CustomCircuitInfo - solo con linea S/F, senza traccia GPS
      final circuit = CustomCircuitInfo(
        name: name,
        widthMeters: 0.0, // Non più usato
        city: city,
        country: country,
        lengthMeters: 0.0, // Verrà calcolato durante le sessioni
        createdAt: DateTime.now(),
        points: [], // Vuoto: verrà popolato durante le sessioni
        microSectors: [], // Vuoto: non usiamo più microsettori
        usedBleDevice: _isUsingBleDevice,
        finishLineStart: finishLineStart,
        finishLineEnd: finishLineEnd,
        gpsFrequencyHz: _isUsingBleDevice ? 10.0 : 1.0,
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
                    _dialogInfoRow(Icons.straighten, 'Linea S/F', '${length.toStringAsFixed(1)} m', const Color(0xFF5AC8FA)),
                    if (city.isNotEmpty || country.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _dialogInfoRow(Icons.place_outlined, 'Località', '$city $country'.trim(), const Color(0xFF4CD964)),
                    ],
                    const SizedBox(height: 10),
                    _dialogInfoRow(Icons.gps_fixed, 'Accuratezza GPS', '${_currentAccuracy.toStringAsFixed(1)} m', const Color(0xFFFF9500)),
                    const SizedBox(height: 10),
                    _dialogInfoRow(Icons.speed, 'Frequenza GPS', '${_isUsingBleDevice ? "10.0" : "1.0"} Hz', const Color(0xFFAF52DE)),
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
      child: Material(
        color: Colors.transparent,
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
      ),
    );
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
            onTap: () => Navigator.of(context).pop(),
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
                  'Nuovo Circuito Custom',
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
                                ? 'GPS BLE 10Hz'
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

          // GPS Status indicator
          if (_currentPosition != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4CD964).withAlpha(60),
                    const Color(0xFF4CD964).withAlpha(30),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF4CD964).withAlpha(200),
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
                      color: const Color(0xFF4CD964),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CD964).withAlpha(100),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'GPS OK',
                    style: TextStyle(
                      color: Color(0xFF4CD964),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1,
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
    final center = _currentPosition ?? const LatLng(45.0, 9.0);

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
              // Current position marker
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 24,
                      height: 24,
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
                  child: const Icon(Icons.touch_app, color: kBrandColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seleziona la linea Start/Finish',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Premi il pulsante quando sei pronto',
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
    final hasGpsFix = _currentPosition != null;
    final accuracyColor = _currentAccuracy <= 10
        ? const Color(0xFF4CD964)
        : _currentAccuracy <= 20
            ? const Color(0xFFFF9500)
            : const Color(0xFFFF453A);

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
          // GPS Info row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kTileColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    Icons.gps_fixed,
                    'Lat',
                    _currentPosition?.latitude.toStringAsFixed(6) ?? '---',
                    const Color(0xFF5AC8FA)
                  )
                ),
                _verticalDivider(),
                Expanded(
                  child: _buildStatTile(
                    Icons.gps_not_fixed,
                    'Lon',
                    _currentPosition?.longitude.toStringAsFixed(6) ?? '---',
                    const Color(0xFF4CD964)
                  )
                ),
                _verticalDivider(),
                Expanded(
                  child: _buildStatTile(
                    Icons.my_location,
                    'Accuratezza',
                    _currentAccuracy > 0 ? '${_currentAccuracy.toStringAsFixed(1)}' : '---',
                    accuracyColor,
                    suffix: 'm'
                  )
                ),
                _verticalDivider(),
                Expanded(
                  child: _buildStatTile(
                    Icons.speed,
                    'Velocità',
                    '${_currentSpeed.toStringAsFixed(0)}',
                    const Color(0xFFFF9500),
                    suffix: 'km/h'
                  )
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // GPS status info
          if (!hasGpsFix) ...[
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
                    child: Text(
                      'Attendi il fix GPS prima di continuare',
                      style: TextStyle(color: kMutedColor, fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(kMutedColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action button
          GestureDetector(
            onTap: _saving || !hasGpsFix ? null : _selectFinishLine,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: hasGpsFix
                    ? const LinearGradient(colors: [kBrandColor, Color(0xFF00D4AA)])
                    : null,
                color: hasGpsFix ? null : _kTileColor,
                borderRadius: BorderRadius.circular(14),
                border: hasGpsFix ? null : Border.all(color: _kBorderColor),
                boxShadow: hasGpsFix
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
                    hasGpsFix ? Icons.flag_outlined : Icons.gps_off,
                    color: hasGpsFix ? Colors.black : kMutedColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasGpsFix ? 'Seleziona linea Start/Finish' : 'Attendi GPS...',
                    style: TextStyle(
                      color: hasGpsFix ? Colors.black : kMutedColor,
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
