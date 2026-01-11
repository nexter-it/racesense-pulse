import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../services/ble_tracking_service.dart';
import '../theme.dart';
import '../models/track_definition.dart';
import 'live_session_page.dart';
import '_mode_selector_widgets.dart';
import 'official_circuits_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);

/// Pagina di preparazione GPS - Premium Style
class GpsWaitPage extends StatefulWidget {
  const GpsWaitPage({super.key});

  @override
  State<GpsWaitPage> createState() => _GpsWaitPageState();
}

class _GpsWaitPageState extends State<GpsWaitPage>
    with SingleTickerProviderStateMixin {
  final BleTrackingService _bleService = BleTrackingService();
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<Map<String, GpsData>>? _bleGpsSub;
  StreamSubscription<Map<String, BleDeviceSnapshot>>? _bleDeviceSub;

  late AnimationController _pulseController;

  bool _checkingPermissions = true;
  bool _hasError = false;
  String _errorMessage = '';

  double? _accuracy;
  DateTime? _lastUpdate;
  Position? _lastPosition;

  // Stato BLE
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  GpsData? _lastBleGpsData;

  // Soglie
  static const double _targetAccuracy = 10.0;

  // Selezione circuito
  TrackDefinition? _selectedTrack;
  StartMode? _selectedMode;

  // Categoria veicolo
  String? _selectedVehicleCategory;
  final TextEditingController _vehicleSearchController = TextEditingController();
  final List<String> _defaultCategories = [
    'Kart rental',
    'Kart',
    'Auto',
    'Rally',
    'Moto rental',
    'Moto',
  ];
  List<String> _filteredCategories = [];
  bool _showCategoryDropdown = false;

  @override
  void initState() {
    super.initState();
    _filteredCategories = List.from(_defaultCategories);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
    _initGps();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _vehicleSearchController.dispose();
    _gpsSub?.cancel();
    _bleGpsSub?.cancel();
    _bleDeviceSub?.cancel();
    super.dispose();
  }

  void _syncConnectedDeviceFromService() {
    final connectedIds = _bleService.getConnectedDeviceIds();
    if (connectedIds.isEmpty) return;
    final id = connectedIds.first;
    final snap = _bleService.getSnapshot(id);
    _connectedDeviceId = id;
    _connectedDeviceName = snap?.name ?? id;
    _listenBleGps();
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
            _connectedDeviceName = connected.name;
            _listenBleGps();
            _gpsSub?.cancel();
            _gpsSub = null;
          } else {
            _connectedDeviceId = null;
            _connectedDeviceName = null;
            _lastBleGpsData = null;
            _bleGpsSub?.cancel();
            _bleGpsSub = null;
            if (_gpsSub == null && !_checkingPermissions && !_hasError) {
              _startGpsStream();
            }
          }
        });
      }
    });
  }

  void _listenBleGps() {
    _bleGpsSub?.cancel();
    _bleGpsSub = _bleService.gpsStream.listen((gpsData) {
      if (_connectedDeviceId != null) {
        final data = gpsData[_connectedDeviceId!];
        if (data != null && mounted) {
          setState(() {
            _lastBleGpsData = data;
            _lastUpdate = DateTime.now();
          });
        }
      }
    });
  }

  bool get _isUsingBleDevice => _connectedDeviceId != null;

  Future<void> _initGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _checkingPermissions = false;
          _hasError = true;
          _errorMessage =
              'Il GPS è disattivato. Attivalo dalle impostazioni del dispositivo.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _checkingPermissions = false;
          _hasError = true;
          _errorMessage =
              'Permesso GPS negato. Concedi l\'accesso alla posizione dalle impostazioni.';
        });
        return;
      }

      if (!_isUsingBleDevice) {
        _startGpsStream();
      }

      setState(() {
        _checkingPermissions = false;
      });
    } catch (e) {
      setState(() {
        _checkingPermissions = false;
        _hasError = true;
        _errorMessage = 'Errore inizializzazione GPS: $e';
      });
    }
  }

  void _startGpsStream() {
    if (_isUsingBleDevice) return;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        setState(() {
          _accuracy = pos.accuracy;
          _lastUpdate = DateTime.now();
          _lastPosition = pos;
        });
      },
      onError: (e) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Errore stream GPS: $e';
        });
      },
    );
  }

  bool get _hasFix {
    if (_isUsingBleDevice) {
      if (_lastBleGpsData == null) return false;

      if (_lastUpdate != null) {
        final age = DateTime.now().difference(_lastUpdate!);
        if (age.inSeconds > 6) return false;
      }

      return (_lastBleGpsData!.fix ?? 0) >= 1 &&
          (_lastBleGpsData!.satellites ?? 0) >= 4;
    } else {
      if (_accuracy == null) return false;

      if (_lastUpdate != null) {
        final age = DateTime.now().difference(_lastUpdate!);
        if (age.inSeconds > 6) return false;
      }

      return _accuracy! <= _targetAccuracy;
    }
  }

  String get _gpsStatusMessage {
    if (_checkingPermissions) return 'Verifica permessi...';
    if (_hasError) return 'Problema rilevato';

    if (_isUsingBleDevice) {
      if (_lastBleGpsData == null) {
        return 'In attesa del segnale...';
      }
      final fix = _lastBleGpsData!.fix ?? 0;
      final sats = _lastBleGpsData!.satellites ?? 0;

      if (fix == 0 || sats < 4) {
        return 'Ricerca satelliti...';
      } else if (!_hasFix) {
        return 'Miglioramento segnale...';
      } else {
        return 'Segnale GPS pronto';
      }
    } else {
      if (_accuracy == null) {
        return 'In attesa del segnale...';
      }

      if (_accuracy! > 30) {
        return 'Segnale debole...';
      } else if (!_hasFix) {
        return 'Miglioramento segnale...';
      } else {
        return 'Segnale GPS pronto';
      }
    }
  }

  void _goToLivePage() {
    if (!_canStartRecording) return;
    if (_selectedTrack == null) return;

    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LiveSessionPage(
          trackDefinition: _selectedTrack,
          vehicleCategory: _selectedVehicleCategory,
        ),
      ),
    );
  }

  bool get _canStartRecording {
    return _hasFix && _selectedTrack != null && _selectedVehicleCategory != null;
  }

  void _filterCategories(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCategories = List.from(_defaultCategories);
      } else {
        _filteredCategories = _defaultCategories
            .where((cat) => cat.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  int get _completedSteps {
    int count = 0;
    if (_hasFix) count++;
    if (_selectedVehicleCategory != null) count++;
    if (_selectedTrack != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // Progress indicator
                  _buildProgressBar(),
                  const SizedBox(height: 20),

                  // Step 1: GPS Status
                  _buildGpsCard(),
                  const SizedBox(height: 16),

                  // Step 2: Categoria veicolo
                  _buildVehicleCard(),
                  const SizedBox(height: 16),

                  // Step 3: Circuito
                  _buildCircuitCard(),
                  const SizedBox(height: 24),

                  // Ready card
                  if (_canStartRecording) _buildReadyTip(),
                ],
              ),
            ),

            // Bottom button
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withAlpha(12),
                    Colors.white.withAlpha(6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _kBorderColor, width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.arrow_back, color: kFgColor, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preparazione',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Completa i 3 passaggi per iniziare',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),
          // Step counter badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(30),
                  kBrandColor.withAlpha(15),
                ],
              ),
              border: Border.all(color: kBrandColor.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _completedSteps == 3 ? Icons.check_circle : Icons.pending,
                  color: kBrandColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '$_completedSteps/3',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: kBrandColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: _kBorderColor,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: constraints.maxWidth * (_completedSteps / 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: [kBrandColor, kBrandColor.withAlpha(200)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGpsCard() {
    final isReady = _hasFix;
    final statusColor = _hasError ? kErrorColor : (isReady ? kBrandColor : kMutedColor);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isReady
              ? [kBrandColor.withAlpha(20), kBrandColor.withAlpha(8)]
              : [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isReady ? kBrandColor.withAlpha(100) : _kBorderColor,
          width: isReady ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isReady ? kBrandColor.withAlpha(30) : Colors.black.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Step number / check
                _buildStepIndicator(1, isReady),
                const SizedBox(width: 14),
                // GPS Icon with animation
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: isReady
                              ? [
                                  kBrandColor.withAlpha(
                                      (35 + 15 * _pulseController.value).toInt()),
                                  kBrandColor.withAlpha(15),
                                ]
                              : [
                                  statusColor.withAlpha(20),
                                  statusColor.withAlpha(10),
                                ],
                        ),
                        border: Border.all(
                          color: statusColor.withAlpha(isReady ? 100 : 60),
                          width: 2,
                        ),
                        boxShadow: isReady
                            ? [
                                BoxShadow(
                                  color: kBrandColor.withAlpha(
                                      (20 + 20 * _pulseController.value).toInt()),
                                  blurRadius: 12,
                                  spreadRadius: 2 * _pulseController.value,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          _hasError
                              ? Icons.gps_off
                              : (isReady ? Icons.gps_fixed : Icons.gps_not_fixed),
                          color: statusColor,
                          size: 28,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEGNALE GPS',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _gpsStatusMessage,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isUsingBleDevice
                            ? 'GPS Pro: ${_connectedDeviceName ?? 'Connesso'}'
                            : 'GPS del telefono',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Error message
          if (_hasError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kErrorColor.withAlpha(15),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: kErrorColor.withAlpha(40)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: kErrorColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                        color: kErrorColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Stats footer (only when ready)
          if (isReady && !_hasError)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(4),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: kBrandColor.withAlpha(40)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (_isUsingBleDevice && _lastBleGpsData != null) ...[
                    _buildStatBadge(
                      Icons.satellite_alt,
                      '${_lastBleGpsData!.satellites ?? '-'} sat',
                    ),
                    _buildStatBadge(Icons.speed, '15 Hz'),
                    _buildStatBadge(Icons.gps_fixed, '<1m'),
                  ] else ...[
                    _buildStatBadge(
                      Icons.my_location,
                      '${_accuracy?.toStringAsFixed(1) ?? '-'}m',
                    ),
                    _buildStatBadge(Icons.speed, '1 Hz'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    final hasCategory = _selectedVehicleCategory != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: hasCategory
              ? [kBrandColor.withAlpha(20), kBrandColor.withAlpha(8)]
              : [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: hasCategory ? kBrandColor.withAlpha(100) : _kBorderColor,
          width: hasCategory ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasCategory ? kBrandColor.withAlpha(30) : Colors.black.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _showCategoryDropdown = !_showCategoryDropdown;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  // Step number / check
                  _buildStepIndicator(2, hasCategory),
                  const SizedBox(width: 14),
                  // Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: hasCategory
                            ? [kBrandColor.withAlpha(35), kBrandColor.withAlpha(15)]
                            : [Colors.white.withAlpha(12), Colors.white.withAlpha(6)],
                      ),
                      border: Border.all(
                        color: hasCategory ? kBrandColor.withAlpha(80) : _kBorderColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.directions_car,
                        color: hasCategory ? kBrandColor : kMutedColor,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CATEGORIA VEICOLO',
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasCategory
                              ? _selectedVehicleCategory!
                              : 'Seleziona categoria',
                          style: TextStyle(
                            color: hasCategory ? kFgColor : kMutedColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(8),
                    ),
                    child: Icon(
                      _showCategoryDropdown
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: hasCategory ? kBrandColor : kMutedColor,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Dropdown
          if (_showCategoryDropdown)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    color: _kBorderColor,
                    margin: const EdgeInsets.only(bottom: 14),
                  ),
                  // Search
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorderColor),
                    ),
                    child: TextField(
                      controller: _vehicleSearchController,
                      onChanged: _filterCategories,
                      style: const TextStyle(
                        color: kFgColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Cerca categoria...',
                        hintStyle: TextStyle(
                          color: kMutedColor.withAlpha(150),
                        ),
                        prefixIcon: Icon(Icons.search, color: kMutedColor, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Categories
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _filteredCategories.map((category) {
                      final isSelected = _selectedVehicleCategory == category;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedVehicleCategory = category;
                            _showCategoryDropdown = false;
                            _vehicleSearchController.clear();
                            _filteredCategories = List.from(_defaultCategories);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [
                                      kBrandColor.withAlpha(35),
                                      kBrandColor.withAlpha(20),
                                    ],
                                  )
                                : null,
                            color: isSelected ? null : Colors.white.withAlpha(6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? kBrandColor : _kBorderColor,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: isSelected ? kBrandColor : kFgColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircuitCard() {
    final hasTrack = _selectedTrack != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: hasTrack
              ? [kBrandColor.withAlpha(20), kBrandColor.withAlpha(8)]
              : [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: hasTrack ? kBrandColor.withAlpha(100) : _kBorderColor,
          width: hasTrack ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasTrack ? kBrandColor.withAlpha(30) : Colors.black.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Step number / check
                _buildStepIndicator(3, hasTrack),
                const SizedBox(width: 14),
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: hasTrack
                          ? [kBrandColor.withAlpha(35), kBrandColor.withAlpha(15)]
                          : [Colors.white.withAlpha(12), Colors.white.withAlpha(6)],
                    ),
                    border: Border.all(
                      color: hasTrack ? kBrandColor.withAlpha(80) : _kBorderColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      hasTrack ? Icons.stadium : Icons.flag_outlined,
                      color: hasTrack ? kBrandColor : kMutedColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CIRCUITO',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasTrack
                            ? _selectedTrack!.name
                            : 'Seleziona circuito',
                        style: TextStyle(
                          color: hasTrack ? kFgColor : kMutedColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasTrack) ...[
                        const SizedBox(height: 4),
                        Text(
                          _selectedTrack!.location,
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Circuit selection buttons
          Container(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: _buildCircuitButton(
                    icon: Icons.stadium_rounded,
                    title: 'Ufficiale',
                    isSelected: _selectedMode == StartMode.existing,
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final track =
                          await Navigator.of(context).push<TrackDefinition?>(
                        MaterialPageRoute(
                          builder: (_) =>
                              const OfficialCircuitsPage(selectionMode: true),
                        ),
                      );
                      if (track != null) {
                        setState(() {
                          _selectedTrack = track;
                          _selectedMode = StartMode.existing;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCircuitButton(
                    icon: Icons.edit_road,
                    title: 'Custom',
                    isSelected: _selectedMode == StartMode.privateCustom,
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final track =
                          await Navigator.of(context).push<TrackDefinition?>(
                        MaterialPageRoute(
                          builder: (_) => const PrivateCircuitsPage(),
                        ),
                      );
                      if (track != null) {
                        setState(() {
                          _selectedTrack = track;
                          _selectedMode = StartMode.privateCustom;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitButton({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: isSelected
              ? LinearGradient(
                  colors: [kBrandColor.withAlpha(30), kBrandColor.withAlpha(15)],
                )
              : null,
          color: isSelected ? null : Colors.white.withAlpha(6),
          border: Border.all(
            color: isSelected ? kBrandColor.withAlpha(80) : _kBorderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? kBrandColor : kMutedColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? kBrandColor : kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, bool isCompleted) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isCompleted
            ? LinearGradient(
                colors: [kBrandColor, kBrandColor.withAlpha(200)],
              )
            : null,
        color: isCompleted ? null : Colors.white.withAlpha(10),
        border: Border.all(
          color: isCompleted ? kBrandColor : kMutedColor.withAlpha(60),
          width: 2,
        ),
        boxShadow: isCompleted
            ? [
                BoxShadow(
                  color: kBrandColor.withAlpha(40),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check, color: Colors.black, size: 16)
            : Text(
                '$step',
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kBrandColor, size: 16),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: kBrandColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildReadyTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: kBrandColor.withAlpha(12),
        border: Border.all(color: kBrandColor.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kBrandColor.withAlpha(20),
              border: Border.all(color: kBrandColor.withAlpha(60)),
            ),
            child: Icon(Icons.rocket_launch, color: kBrandColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tutto pronto!',
                  style: TextStyle(
                    color: kBrandColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Premi il pulsante per iniziare la sessione',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    final canStart = !_hasError && _canStartRecording;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: _kBgColor,
        border: Border(
          top: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: canStart ? _goToLivePage : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: canStart
                    ? LinearGradient(
                        colors: [kBrandColor, kBrandColor.withAlpha(220)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: canStart ? null : kMutedColor.withAlpha(25),
                boxShadow: canStart
                    ? [
                        BoxShadow(
                          color: kBrandColor.withAlpha(60),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: canStart
                          ? Colors.black.withAlpha(30)
                          : Colors.white.withAlpha(10),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: canStart ? Colors.black : kMutedColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Inizia Sessione',
                    style: TextStyle(
                      color: canStart ? Colors.black : kMutedColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            !_hasFix && !_hasError
                ? 'Attendi segnale GPS...'
                : (_hasFix && _selectedVehicleCategory == null)
                    ? 'Seleziona categoria veicolo'
                    : (_hasFix && _selectedTrack == null)
                        ? 'Seleziona un circuito'
                        : _hasError
                            ? 'Risolvi il problema GPS'
                            : 'Pronto per partire!',
            style: TextStyle(
              fontSize: 12,
              color: _hasError ? kErrorColor : kMutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
