import 'dart:async';
import 'dart:math' as math;

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
const Color _kTileColor = Color(0xFF0D0D0D);

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
  Timer? _timer;

  late AnimationController _pulseController;

  bool _checkingPermissions = true;
  bool _hasError = false;
  String _errorMessage = '';

  double? _accuracy;
  DateTime? _lastUpdate;
  int _elapsedSeconds = 0;
  Position? _lastPosition;

  // Stato BLE
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  GpsData? _lastBleGpsData;

  // Soglie
  static const double _targetAccuracy = 10.0;
  static const double _worstAccuracy = 60.0;

  // Selezione circuito
  TrackDefinition? _selectedTrack;
  StartMode? _selectedMode;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _syncConnectedDeviceFromService();
    _listenBleConnectionChanges();
    _initGps();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gpsSub?.cancel();
    _bleGpsSub?.cancel();
    _bleDeviceSub?.cancel();
    _timer?.cancel();
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
      _startElapsedTimer();

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

  void _startElapsedTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  bool get _hasFix {
    if (_isUsingBleDevice) {
      if (_lastBleGpsData == null) return false;
      if (_elapsedSeconds < 3) return false;

      if (_lastUpdate != null) {
        final age = DateTime.now().difference(_lastUpdate!);
        if (age.inSeconds > 6) return false;
      }

      return (_lastBleGpsData!.fix ?? 0) >= 1 &&
          (_lastBleGpsData!.satellites ?? 0) >= 4;
    } else {
      if (_accuracy == null) return false;
      if (_elapsedSeconds < 3) return false;

      if (_lastUpdate != null) {
        final age = DateTime.now().difference(_lastUpdate!);
        if (age.inSeconds > 6) return false;
      }

      return _accuracy! <= _targetAccuracy;
    }
  }

  double get _qualityProgress {
    if (_isUsingBleDevice) {
      final sats = _lastBleGpsData?.satellites ?? 0;
      if (sats == 0) return 0.0;
      return (sats / 12).clamp(0.0, 1.0);
    } else {
      if (_accuracy == null) return 0.0;
      final clampedAcc = _accuracy!.clamp(0.0, _worstAccuracy);
      final v = 1.0 - (clampedAcc / _worstAccuracy);
      return v;
    }
  }

  String get _statusLabel {
    if (_checkingPermissions) return 'Controllo permessi GPS...';
    if (_hasError) return 'Problema con il GPS';

    if (_isUsingBleDevice) {
      if (_lastBleGpsData == null) {
        return 'In attesa dati dal dispositivo...';
      }
      final fix = _lastBleGpsData!.fix ?? 0;
      final sats = _lastBleGpsData!.satellites ?? 0;

      if (fix == 0 || sats < 4) {
        return 'Aggancio satelliti in corso...';
      } else if (sats < 8) {
        return 'Segnale in miglioramento...';
      } else if (!_hasFix) {
        return 'Quasi pronto, ancora un istante';
      } else {
        return 'GPS professionale pronto';
      }
    } else {
      if (_accuracy == null) {
        return 'In attesa del primo fix...';
      }

      if (_accuracy! > 30) {
        return 'Segnale debole, attendi ancora...';
      } else if (_accuracy! > 15) {
        return 'Segnale in miglioramento...';
      } else if (!_hasFix) {
        return 'Quasi pronto, ancora un istante';
      } else {
        return 'GPS pronto per la registrazione';
      }
    }
  }

  Color get _indicatorColor {
    if (_hasError) return kErrorColor;

    if (_isUsingBleDevice) {
      if (_lastBleGpsData == null) return kMutedColor;
      if (_hasFix) return kBrandColor;

      final start = kErrorColor;
      final end = kBrandColor;
      final t = _qualityProgress.clamp(0.0, 1.0);
      return Color.lerp(start, end, t) ?? kBrandColor;
    } else {
      if (_accuracy == null) return kMutedColor;
      if (_hasFix) return kBrandColor;

      final start = kErrorColor;
      final end = kBrandColor;
      final t = _qualityProgress.clamp(0.0, 1.0);
      return Color.lerp(start, end, t) ?? kBrandColor;
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
        ),
      ),
    );
  }

  bool get _canStartRecording {
    return _hasFix && _selectedTrack != null;
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  // GPS Source Card - Very prominent
                  _buildGpsSourceCard(),
                  const SizedBox(height: 20),

                  // GPS Status Card with circular indicator
                  _buildGpsStatusCard(),
                  const SizedBox(height: 24),

                  // Circuit Selection Section
                  _buildSectionHeader('Seleziona circuito'),
                  const SizedBox(height: 12),
                  _buildCircuitSelector(),
                  const SizedBox(height: 12),
                  _buildSelectionSummary(),
                  const SizedBox(height: 24),

                  // Tips
                  _buildTipsCard(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgColor, const Color(0xFF121212)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(Icons.close, color: kFgColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(40),
                  kPulseColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kPulseColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.rocket_launch, color: kPulseColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          const Expanded(
            child: Text(
              'Preparazione',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: kFgColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          // Timer badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withAlpha(10),
              border: Border.all(color: _kBorderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, color: kMutedColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${_elapsedSeconds}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kMutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsSourceCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: _isUsingBleDevice
              ? [kBrandColor.withAlpha(25), kBrandColor.withAlpha(10)]
              : [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: _isUsingBleDevice ? kBrandColor.withAlpha(120) : _kBorderColor,
          width: _isUsingBleDevice ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isUsingBleDevice
                ? kBrandColor.withAlpha(30)
                : Colors.black.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon with pulse
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: _isUsingBleDevice
                          ? [
                              kBrandColor.withAlpha(
                                  (40 + 20 * _pulseController.value).toInt()),
                              kBrandColor.withAlpha(20),
                            ]
                          : [
                              Colors.white.withAlpha(12),
                              Colors.white.withAlpha(6),
                            ],
                    ),
                    border: Border.all(
                      color: _isUsingBleDevice
                          ? kBrandColor.withAlpha(100)
                          : _kBorderColor,
                      width: 2,
                    ),
                    boxShadow: _isUsingBleDevice
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
                      _isUsingBleDevice
                          ? Icons.bluetooth_connected
                          : Icons.smartphone,
                      color: _isUsingBleDevice ? kBrandColor : kMutedColor,
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
                    'SORGENTE GPS',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isUsingBleDevice
                        ? (_connectedDeviceName ?? 'GPS Professionale')
                        : 'GPS del telefono',
                    style: const TextStyle(
                      color: kFgColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: _isUsingBleDevice
                          ? kBrandColor.withAlpha(20)
                          : kMutedColor.withAlpha(15),
                      border: Border.all(
                        color: _isUsingBleDevice
                            ? kBrandColor.withAlpha(60)
                            : kMutedColor.withAlpha(40),
                      ),
                    ),
                    child: Text(
                      _isUsingBleDevice ? '15 Hz • <1m precisione' : '1 Hz • 5-8m precisione',
                      style: TextStyle(
                        color: _isUsingBleDevice ? kBrandColor : kMutedColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Status dot
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hasFix ? kBrandColor : kMutedColor,
                boxShadow: _hasFix
                    ? [
                        BoxShadow(
                          color: kBrandColor.withAlpha(150),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsStatusCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Status label
            Text(
              _statusLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _hasFix ? kBrandColor : kMutedColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            // Circular indicator
            _buildCircularIndicator(),
            const SizedBox(height: 24),
            // Stats grid
            _buildGpsStats(),
            // Error message
            if (_hasError) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: kErrorColor.withAlpha(15),
                  border: Border.all(color: kErrorColor.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: kErrorColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: kErrorColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCircularIndicator() {
    final progress = _qualityProgress.clamp(0.0, 1.0);
    final color = _indicatorColor;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(4),
              border: Border.all(color: _kBorderColor, width: 2),
            ),
          ),
          // Animated arc
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(140, 140),
                painter: _ArcPainter(
                  progress: progress,
                  color: color,
                  glowIntensity: _hasFix ? 0.5 + 0.5 * _pulseController.value : 0.0,
                ),
              );
            },
          ),
          // Center content - only icon, centered
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(15),
                  boxShadow: _hasFix
                      ? [
                          BoxShadow(
                            color: color.withAlpha(
                                (30 + 30 * _pulseController.value).toInt()),
                            blurRadius: 20,
                            spreadRadius: 6 * _pulseController.value,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: color,
                  size: 40,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGpsStats() {
    if (_isUsingBleDevice && _lastBleGpsData != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            icon: Icons.satellite_alt,
            label: 'Satelliti',
            value: '${_lastBleGpsData!.satellites ?? '-'}',
            color: kBrandColor,
          ),
          Container(width: 1, height: 40, color: _kBorderColor),
          _buildStatItem(
            icon: Icons.gps_fixed,
            label: 'Fix',
            value: '${_lastBleGpsData!.fix ?? '-'}',
            color: kPulseColor,
          ),
          Container(width: 1, height: 40, color: _kBorderColor),
          _buildStatItem(
            icon: Icons.battery_charging_full,
            label: 'Batteria',
            value: _lastBleGpsData!.battery != null
                ? '${_lastBleGpsData!.battery}%'
                : '-',
            color: const Color(0xFF00E676),
          ),
        ],
      );
    } else {
      final speedMs = _lastPosition?.speed ?? 0.0;
      final speedKph = (speedMs * 3.6);
      final altitude = _lastPosition?.altitude;

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            icon: Icons.my_location,
            label: 'Precisione',
            value: _accuracy != null ? '${_accuracy!.toStringAsFixed(1)}m' : '--',
            color: kBrandColor,
          ),
          Container(width: 1, height: 40, color: _kBorderColor),
          _buildStatItem(
            icon: Icons.speed,
            label: 'Velocità',
            value: '${speedKph.toStringAsFixed(1)}',
            color: kPulseColor,
          ),
          Container(width: 1, height: 40, color: _kBorderColor),
          _buildStatItem(
            icon: Icons.landscape,
            label: 'Altitudine',
            value: altitude != null ? '${altitude.toStringAsFixed(0)}m' : '--',
            color: const Color(0xFF29B6F6),
          ),
        ],
      );
    }
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(15),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: kMutedColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: kBrandColor,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: kMutedColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildCircuitSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildCircuitOption(
            icon: Icons.stadium_rounded,
            title: 'Ufficiale',
            subtitle: 'Autodromi verificati',
            isSelected: _selectedMode == StartMode.existing,
            onTap: () async {
              HapticFeedback.lightImpact();
              final track = await Navigator.of(context).push<TrackDefinition?>(
                MaterialPageRoute(
                  builder: (_) => const OfficialCircuitsPage(selectionMode: true),
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
          child: _buildCircuitOption(
            icon: Icons.edit_road,
            title: 'Custom',
            subtitle: 'I miei tracciati',
            isSelected: _selectedMode == StartMode.privateCustom,
            onTap: () async {
              HapticFeedback.lightImpact();
              final track = await Navigator.of(context).push<TrackDefinition?>(
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
    );
  }

  Widget _buildCircuitOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: isSelected
                ? [kBrandColor.withAlpha(25), kBrandColor.withAlpha(10)]
                : [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isSelected ? kBrandColor.withAlpha(120) : _kBorderColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: kBrandColor.withAlpha(30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: isSelected
                      ? [kBrandColor.withAlpha(40), kBrandColor.withAlpha(20)]
                      : [Colors.white.withAlpha(12), Colors.white.withAlpha(6)],
                ),
                border: Border.all(
                  color: isSelected ? kBrandColor.withAlpha(80) : _kBorderColor,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: isSelected ? kBrandColor : kMutedColor,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? kFgColor : kMutedColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionSummary() {
    final hasTrack = _selectedTrack != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: hasTrack
            ? LinearGradient(
                colors: [kBrandColor.withAlpha(15), kBrandColor.withAlpha(8)],
              )
            : null,
        color: hasTrack ? null : Colors.white.withAlpha(4),
        border: Border.all(
          color: hasTrack ? kBrandColor.withAlpha(80) : _kBorderColor,
          width: hasTrack ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasTrack ? kBrandColor.withAlpha(20) : kMutedColor.withAlpha(15),
              border: Border.all(
                color: hasTrack ? kBrandColor.withAlpha(60) : kMutedColor.withAlpha(40),
              ),
            ),
            child: Icon(
              hasTrack ? Icons.check_circle : Icons.info_outline,
              color: hasTrack ? kBrandColor : kMutedColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTrack
                      ? (_selectedMode == StartMode.existing
                          ? 'Circuito ufficiale'
                          : 'Circuito custom')
                      : 'Nessun circuito selezionato',
                  style: TextStyle(
                    color: hasTrack ? kFgColor : kMutedColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasTrack
                      ? '${_selectedTrack!.name} • ${_selectedTrack!.location}'
                      : 'Seleziona un circuito per iniziare',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          _buildTipRow(
            icon: Icons.route_outlined,
            text:
                'Sistema Pulse+: seleziona un circuito pre-tracciato per tempi giro precisi.',
            color: kBrandColor,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _kBorderColor),
          const SizedBox(height: 12),
          _buildTipRow(
            icon: _isUsingBleDevice ? Icons.bluetooth : Icons.smartphone,
            text: _isUsingBleDevice
                ? 'Posiziona il GPS con cielo visibile, evita coperture metalliche.'
                : 'Tieni il telefono con cielo visibile, evita tasche schermate.',
            color: kPulseColor,
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(15),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: kMutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: canStart
                    ? LinearGradient(
                        colors: [kBrandColor, kBrandColor.withAlpha(220)],
                      )
                    : null,
                color: canStart ? null : kMutedColor.withAlpha(30),
                boxShadow: canStart
                    ? [
                        BoxShadow(
                          color: kBrandColor.withAlpha(60),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    color: canStart ? Colors.black : kMutedColor,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Inizia Registrazione LIVE',
                    style: TextStyle(
                      color: canStart ? Colors.black : kMutedColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            !_hasFix && !_hasError
                ? 'Attendi un buon segnale GPS...'
                : (_hasFix && !_canStartRecording)
                    ? 'Seleziona un circuito per attivare'
                    : _hasError
                        ? 'Risolvi il problema GPS per procedere'
                        : 'Tutto pronto!',
            style: TextStyle(
              fontSize: 11,
              color: _hasError ? kErrorColor : kMutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double glowIntensity;

  _ArcPainter({
    required this.progress,
    required this.color,
    this.glowIntensity = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 12.0;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.white.withAlpha(10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, bgPaint);

    // Glow effect
    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = color.withAlpha((50 * glowIntensity).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final sweep = 2 * math.pi * progress;
      canvas.drawArc(rect, -math.pi / 2, sweep, false, glowPaint);
    }

    // Progress arc
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweep = 2 * math.pi * progress;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}
