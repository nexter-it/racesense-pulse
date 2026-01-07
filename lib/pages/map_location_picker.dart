import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../theme.dart';

const Color _kBgColor = Color(0xFF0A0A0A);

class MapLocationPicker extends StatefulWidget {
  final LatLng? initialLocation;

  const MapLocationPicker({
    super.key,
    this.initialLocation,
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late MapController _mapController;
  LatLng? _selectedLocation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.initialLocation != null) {
        setState(() {
          _selectedLocation = widget.initialLocation;
          _isLoading = false;
        });
        return;
      }

      // Ottieni posizione corrente
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    } catch (e) {
      // Default a Roma se non riesci a ottenere la posizione
      setState(() {
        _selectedLocation = LatLng(41.9028, 12.4964);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kFgColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Seleziona Posizione',
          style: TextStyle(
            color: kFgColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_selectedLocation != null)
            IconButton(
              icon: const Icon(Icons.check, color: kBrandColor),
              onPressed: () {
                Navigator.of(context).pop(_selectedLocation);
              },
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: kBrandColor),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation!,
                    initialZoom: 15.0,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _selectedLocation = point;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.racesense.pulse',
                    ),
                    if (_selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLocation!,
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_on,
                              color: kBrandColor,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // Info box
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kBgColor.withAlpha(230),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBrandColor.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app, color: kBrandColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tocca la mappa per selezionare la posizione',
                            style: TextStyle(
                              color: kFgColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Coordinates display
                if (_selectedLocation != null)
                  Positioned(
                    bottom: 80,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _kBgColor.withAlpha(230),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Coordinate Selezionate',
                            style: TextStyle(
                              color: kMutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              color: kFgColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              color: kFgColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _selectedLocation != null
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).pop(_selectedLocation);
              },
              backgroundColor: kBrandColor,
              icon: const Icon(Icons.check, color: Colors.black),
              label: const Text(
                'Conferma',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : null,
    );
  }
}
