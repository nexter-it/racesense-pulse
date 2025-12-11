import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';

class DeviceCheckPage extends StatefulWidget {
  final String deviceId;
  const DeviceCheckPage({super.key, required this.deviceId});

  @override
  State<DeviceCheckPage> createState() => _DeviceCheckPageState();
}

class _DeviceCheckPageState extends State<DeviceCheckPage> {
  final BleTrackingService _ble = BleTrackingService();
  final MapController _mapController = MapController();
  LatLng? _lastPos;
  final List<LatLng> _trail = [];
  static const int _maxTrailPoints = 100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PulseBackground(
        withTopPadding: false,
        child: StreamBuilder<Map<String, LatLng>>(
          stream: _ble.positionStream,
          builder: (context, snapshot) {
            final newPos = snapshot.data?[widget.deviceId];
            if (newPos != null && newPos != _lastPos) {
              _lastPos = newPos;
              _trail.add(newPos);
              if (_trail.length > _maxTrailPoints) {
                _trail.removeAt(0);
              }
              // Auto-center map on new position
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _mapController.move(newPos, _mapController.camera.zoom);
                } catch (_) {}
              });
            }
            return Column(
              children: [
                // Premium header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: kLineColor, width: 1),
                    ),
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
                              'Monitoraggio dispositivo',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: kFgColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        kBrandColor.withAlpha(40),
                                        kBrandColor.withAlpha(20),
                                      ],
                                    ),
                                    border: Border.all(color: kBrandColor, width: 1),
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
                                    widget.deviceId,
                                    style: const TextStyle(
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: _lastPos != null
                                ? [
                                    kBrandColor.withAlpha(40),
                                    kBrandColor.withAlpha(20),
                                  ]
                                : [
                                    Colors.white.withAlpha(20),
                                    Colors.white.withAlpha(10),
                                  ],
                          ),
                          border: Border.all(
                            color: _lastPos != null ? kBrandColor : kLineColor,
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
                                shape: BoxShape.circle,
                                color: _lastPos != null ? kBrandColor : kMutedColor,
                                boxShadow: _lastPos != null
                                    ? [
                                        BoxShadow(
                                          color: kBrandColor.withAlpha(128),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _lastPos != null ? 'GPS OK' : 'In attesa',
                              style: TextStyle(
                                color: _lastPos != null ? kBrandColor : kMutedColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Map
                Expanded(
                  child: _lastPos == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        kPulseColor.withAlpha(40),
                                        kPulseColor.withAlpha(20),
                                      ],
                                    ),
                                    border: Border.all(
                                        color: kPulseColor.withAlpha(100), width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.gps_not_fixed,
                                    size: 48,
                                    color: kPulseColor,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'In attesa di coordinate',
                                  style: TextStyle(
                                    color: kFgColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Assicurati che il dispositivo sia all\'aperto\ncon visuale chiara del cielo',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: kMutedColor, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        )
                      : FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _lastPos!,
                            initialZoom: 17.5,
                            minZoom: 15,
                            maxZoom: 20,
                            backgroundColor: const Color(0xFF0A0A0A),
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
                            // Marker with premium styling
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _lastPos!,
                                  width: 56,
                                  height: 56,
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
                              ],
                            ),
                          ],
                        ),
                ),
                // Bottom info panel
                if (_lastPos != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: kLineColor, width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoItem(
                          icon: Icons.my_location,
                          label: 'Latitudine',
                          value: _lastPos!.latitude.toStringAsFixed(6),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: kLineColor,
                        ),
                        _buildInfoItem(
                          icon: Icons.explore,
                          label: 'Longitudine',
                          value: _lastPos!.longitude.toStringAsFixed(6),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: kLineColor,
                        ),
                        _buildInfoItem(
                          icon: Icons.route,
                          label: 'Punti traccia',
                          value: '${_trail.length}',
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
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
          style: const TextStyle(
            color: kFgColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
