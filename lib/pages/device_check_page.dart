import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class DeviceCheckPage extends StatefulWidget {
  final String deviceId;
  const DeviceCheckPage({super.key, required this.deviceId});

  @override
  State<DeviceCheckPage> createState() => _DeviceCheckPageState();
}

class _DeviceCheckPageState extends State<DeviceCheckPage>
    with TickerProviderStateMixin {
  final BleTrackingService _ble = BleTrackingService();
  final MapController _mapController = MapController();
  GpsData? _lastGpsData;
  final List<LatLng> _trail = [];
  static const int _maxTrailPoints = 100;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: StreamBuilder<Map<String, GpsData>>(
          stream: _ble.gpsStream,
          builder: (context, snapshot) {
            final newGpsData = snapshot.data?[widget.deviceId];
            if (newGpsData != null &&
                newGpsData.position != _lastGpsData?.position) {
              _lastGpsData = newGpsData;
              _trail.add(newGpsData.position);
              if (_trail.length > _maxTrailPoints) {
                _trail.removeAt(0);
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _mapController.move(
                      newGpsData.position, _mapController.camera.zoom);
                } catch (_) {}
              });
            }
            final lastPos = _lastGpsData?.position;
            final hasGps = lastPos != null;

            return Column(
              children: [
                _buildHeader(hasGps),
                Expanded(
                  child: hasGps
                      ? _buildMapView(lastPos)
                      : _buildWaitingState(),
                ),
                if (_lastGpsData != null) _buildDataPanel(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool hasGps) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kCardStart, _kBgColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(30),
                    kBrandColor.withAlpha(15),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: const Icon(Icons.arrow_back, color: kBrandColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          // Title and device ID
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Monitoraggio Dispositivo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kBrandColor.withAlpha(30),
                        border: Border.all(color: kBrandColor.withAlpha(80)),
                      ),
                      child: const Icon(
                        Icons.bluetooth_connected,
                        color: kBrandColor,
                        size: 10,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.deviceId.length > 10
                            ? '${widget.deviceId.substring(0, 10)}...'
                            : widget.deviceId,
                        style: TextStyle(
                          fontSize: 11,
                          color: kMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // GPS Status badge
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: hasGps
                        ? [
                            kBrandColor.withAlpha(40),
                            kBrandColor.withAlpha(20),
                          ]
                        : [
                            kPulseColor.withAlpha(30),
                            kPulseColor.withAlpha(15),
                          ],
                  ),
                  border: Border.all(
                    color: hasGps
                        ? kBrandColor.withAlpha(100)
                        : kPulseColor.withAlpha(80),
                    width: 1.5,
                  ),
                  boxShadow: hasGps
                      ? [
                          BoxShadow(
                            color: kBrandColor
                                .withOpacity(0.3 * _pulseAnimation.value),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasGps ? kBrandColor : kPulseColor,
                        boxShadow: hasGps
                            ? [
                                BoxShadow(
                                  color: kBrandColor.withAlpha(180),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasGps ? 'GPS OK' : 'Attesa',
                      style: TextStyle(
                        color: hasGps ? kBrandColor : kPulseColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated GPS icon
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        kPulseColor.withOpacity(0.15 * _pulseAnimation.value),
                        kPulseColor.withOpacity(0.05 * _pulseAnimation.value),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kPulseColor.withAlpha(40),
                            kPulseColor.withAlpha(20),
                          ],
                        ),
                        border: Border.all(
                          color: kPulseColor.withAlpha(100),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: kPulseColor.withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.gps_not_fixed,
                        size: 40,
                        color: kPulseColor,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'In attesa di coordinate',
              style: TextStyle(
                color: kFgColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Assicurati che il dispositivo sia all\'aperto\ncon visuale chiara del cielo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // Tips card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kCardStart, _kCardEnd],
                ),
                border: Border.all(color: _kBorderColor),
              ),
              child: Column(
                children: [
                  _buildTipItem(
                    Icons.wb_sunny_outlined,
                    'Porta il dispositivo all\'aperto',
                  ),
                  const SizedBox(height: 12),
                  _buildTipItem(
                    Icons.visibility,
                    'Evita ostacoli tra il dispositivo e il cielo',
                  ),
                  const SizedBox(height: 12),
                  _buildTipItem(
                    Icons.timer,
                    'Il primo fix può richiedere 30-60 secondi',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: kBrandColor.withAlpha(15),
          ),
          child: Icon(icon, color: kBrandColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapView(LatLng position) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: position,
              initialZoom: 17.5,
              minZoom: 15,
              maxZoom: 20,
              backgroundColor: _kBgColor,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.racesense.pulse',
              ),
              // Trail polyline
              if (_trail.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trail,
                      strokeWidth: 4,
                      color: kBrandColor,
                      borderStrokeWidth: 2,
                      borderColor: Colors.black.withAlpha(100),
                      gradientColors: [
                        kBrandColor.withAlpha(80),
                        kBrandColor.withAlpha(120),
                        kBrandColor,
                      ],
                    ),
                  ],
                ),
              // Position marker - simple circle, not directional
              MarkerLayer(
                markers: [
                  Marker(
                    point: position,
                    width: 56,
                    height: 56,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer pulsing ring
                            Container(
                              width: 56 * _pulseAnimation.value,
                              height: 56 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kBrandColor.withAlpha(20),
                                border: Border.all(
                                  color: kBrandColor.withAlpha(60),
                                  width: 2,
                                ),
                              ),
                            ),
                            // Inner circle marker
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: kBrandColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
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
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Map overlay gradient at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(150),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Coordinates badge
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.black.withAlpha(180),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, color: kBrandColor, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: kFgColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
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

  Widget _buildDataPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kCardStart, _kCardEnd],
        ),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kBorderColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: kBrandColor.withAlpha(20),
                  ),
                  child: Icon(Icons.analytics_outlined,
                      color: kBrandColor, size: 18),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Dati GPS in Tempo Reale',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kFgColor,
                  ),
                ),
              ],
            ),
          ),
          // Data grid
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: _buildDataTile(
                    icon: Icons.satellite_alt,
                    label: 'Satelliti',
                    value: _lastGpsData!.satellites?.toString() ?? '-',
                    color: kPulseColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDataTile(
                    icon: Icons.speed,
                    label: 'Velocità',
                    value: _lastGpsData!.speed != null
                        ? '${_lastGpsData!.speed!.toStringAsFixed(1)}'
                        : '-',
                    unit: 'km/h',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDataTile(
                    icon: Icons.battery_charging_full,
                    label: 'Batteria',
                    value: _lastGpsData!.battery != null
                        ? '${_lastGpsData!.battery}'
                        : '-',
                    unit: '%',
                    color: _getBatteryColor(_lastGpsData!.battery),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getBatteryColor(int? battery) {
    if (battery == null) return kMutedColor;
    if (battery > 60) return kBrandColor;
    if (battery > 30) return Colors.orange;
    return kErrorColor;
  }

  Widget _buildDataTile({
    required IconData icon,
    required String label,
    required String value,
    String? unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: _kTileColor,
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(20),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: kFgColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (unit != null)
                Text(
                  ' $unit',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
