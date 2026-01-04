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
/// 1. Mostra pagina informativa con istruzioni
/// 2. Utente conferma e naviga direttamente a DrawFinishLinePage con mappa satellitare
/// 3. Utente disegna manualmente linea S/F sulla mappa con 2 tap
/// 4. Durante le sessioni verrà tracciata la traccia GPS e calcolati i giri
/// 5. Salvataggio su Firebase
class CustomCircuitBuilderPage extends StatefulWidget {
  const CustomCircuitBuilderPage({super.key});

  @override
  State<CustomCircuitBuilderPage> createState() =>
      _CustomCircuitBuilderPageState();
}

// Premium UI constants
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class _CustomCircuitBuilderPageState extends State<CustomCircuitBuilderPage>
    with SingleTickerProviderStateMixin {
  final CustomCircuitService _service = CustomCircuitService();
  final BleTrackingService _bleService = BleTrackingService();

  StreamSubscription<Position>? _cellularGpsSubscription;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSubscription;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceSub;

  bool _saving = false;

  // GPS positioning
  LatLng? _currentPosition;
  String? _connectedDeviceId;
  bool _isUsingBleDevice = false;

  // Posizione GPS corrente
  bool _isLoadingGps = true;

  @override
  void initState() {
    super.initState();
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
    _startPositioning();
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
        if (data != null && mounted) {
          setState(() {
            _currentPosition = data.position;
            _isLoadingGps = false;
          });
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
      if (mounted && !_isUsingBleDevice) {
        final newPosition = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = newPosition;
          _isLoadingGps = false;
        });
      }
    });
  }

  void _stopCellularPositioning() {
    _cellularGpsSubscription?.cancel();
    _cellularGpsSubscription = null;
  }

  /// Naviga direttamente a DrawFinishLinePage per selezione linea S/F
  Future<void> _continueToFinishLineSelection() async {
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
      // Utente ha annullato → chiudi la pagina
      if (mounted) {
        Navigator.of(context).pop();
      }
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
        child: _buildInstructionsPage(),
      ),
    );
  }

  Widget _buildInstructionsPage() {
    return Column(
      children: [
        // Header
        Container(
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
              const Expanded(
                child: Text(
                  'Nuovo Circuito Custom',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icona principale
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          kBrandColor.withAlpha(40),
                          kBrandColor.withAlpha(20),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kCardStart,
                        border: Border.all(color: kBrandColor.withAlpha(100), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: kBrandColor.withAlpha(50),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.flag_outlined,
                        size: 48,
                        color: kBrandColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Titolo
                const Center(
                  child: Text(
                    'Come Creare il Tuo Circuito',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: kFgColor,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Segui questi semplici passaggi',
                    style: TextStyle(
                      fontSize: 15,
                      color: kMutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),

                // Istruzioni
                _buildInstructionStep(
                  number: '1',
                  title: 'Visualizza la Mappa Satellitare',
                  description: 'Vedrai una mappa satellitare del tuo circuito con la tua posizione GPS in tempo reale.',
                  icon: Icons.satellite_alt,
                  color: const Color(0xFF5AC8FA),
                ),
                const SizedBox(height: 20),

                _buildInstructionStep(
                  number: '2',
                  title: 'Seleziona la Linea Start/Finish',
                  description: 'Fai 2 tap sulla mappa per definire i due estremi della linea di partenza/arrivo del tuo circuito.',
                  icon: Icons.touch_app,
                  color: kBrandColor,
                ),
                const SizedBox(height: 20),

                _buildInstructionStep(
                  number: '3',
                  title: 'Conferma e Salva',
                  description: 'Dai un nome al circuito e salvalo. La traccia GPS verrà registrata durante le tue sessioni.',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF4CD964),
                ),
                const SizedBox(height: 32),

                // Info box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kBrandColor.withAlpha(15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBrandColor.withAlpha(60)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, color: kBrandColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Suggerimento',
                              style: TextStyle(
                                color: kBrandColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Posiziona la linea Start/Finish nel punto più adatto del circuito. Posizionerai meglio con lo zoom della mappa.',
                              style: TextStyle(
                                color: kBrandColor.withAlpha(200),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom button
        Container(
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
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoadingGps)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _kTileColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(kBrandColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Rilevamento posizione GPS in corso...',
                          style: TextStyle(color: kMutedColor, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: _isLoadingGps ? null : _continueToFinishLineSelection,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _isLoadingGps
                        ? null
                        : const LinearGradient(colors: [kBrandColor, Color(0xFF00D4AA)]),
                    color: _isLoadingGps ? _kTileColor : null,
                    borderRadius: BorderRadius.circular(14),
                    border: _isLoadingGps ? Border.all(color: _kBorderColor) : null,
                    boxShadow: _isLoadingGps
                        ? null
                        : [
                            BoxShadow(
                              color: kBrandColor.withAlpha(60),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isLoadingGps ? Icons.gps_off : Icons.map,
                        color: _isLoadingGps ? kMutedColor : Colors.black,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isLoadingGps ? 'Attendi GPS...' : 'Inizia',
                        style: TextStyle(
                          color: _isLoadingGps ? kMutedColor : Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionStep({
    required String number,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kFgColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: kMutedColor,
                    height: 1.4,
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
