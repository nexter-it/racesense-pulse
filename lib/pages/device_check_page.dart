import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/ble_tracking_service.dart';
import '../theme.dart';

class DeviceCheckPage extends StatefulWidget {
  final String deviceId;
  const DeviceCheckPage({super.key, required this.deviceId});

  @override
  State<DeviceCheckPage> createState() => _DeviceCheckPageState();
}

class _DeviceCheckPageState extends State<DeviceCheckPage> {
  final BleTrackingService _ble = BleTrackingService();
  LatLng? _lastPos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifica settaggi dispositivo'),
        backgroundColor: kBgColor,
      ),
      body: StreamBuilder<Map<String, LatLng>>(
        stream: _ble.positionStream,
        builder: (context, snapshot) {
          _lastPos = snapshot.data?[widget.deviceId] ?? _lastPos;
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color.fromRGBO(255, 255, 255, 0.07),
                      Color.fromRGBO(255, 255, 255, 0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: kLineColor),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_connected, color: kBrandColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Device: ${widget.deviceId}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      _lastPos != null ? 'Segnale GPS OK' : 'In attesa dati',
                      style: TextStyle(
                        color: _lastPos != null ? kBrandColor : kMutedColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _lastPos == null
                    ? const Center(
                        child: Text(
                          'In attesa di coordinate dal dispositivo...',
                          style: TextStyle(color: kMutedColor),
                        ),
                      )
                    : FlutterMap(
                        options: MapOptions(
                          initialCenter: _lastPos!,
                          initialZoom: 16,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                            userAgentPackageName: 'com.racesense.pulse',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _lastPos!,
                                width: 44,
                                height: 44,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: kBrandColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: kBrandColor.withOpacity(0.4),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
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
}
