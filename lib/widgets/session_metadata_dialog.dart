import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

class SessionMetadata {
  final String trackName;
  final String location;
  final GeoPoint locationCoords;
  final bool isPublic;

  SessionMetadata({
    required this.trackName,
    required this.location,
    required this.locationCoords,
    required this.isPublic,
  });
}

class SessionMetadataDialog extends StatefulWidget {
  final List<Position> gpsTrack;
  final String? initialTrackName;
  final String? initialLocationName;
  final GeoPoint? initialLocationCoords;
  final bool? initialIsPublic;

  const SessionMetadataDialog({
    super.key,
    required this.gpsTrack,
    this.initialTrackName,
    this.initialLocationName,
    this.initialLocationCoords,
    this.initialIsPublic,
  });

  @override
  State<SessionMetadataDialog> createState() => _SessionMetadataDialogState();
}

class _SessionMetadataDialogState extends State<SessionMetadataDialog> {
  final TextEditingController _trackNameController = TextEditingController();
  String _locationName = '';
  GeoPoint? _locationCoords;
  bool _isPublic = true;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialTrackName != null) {
      _trackNameController.text = widget.initialTrackName!;
    }
    if (widget.initialLocationName != null) {
      _locationName = widget.initialLocationName!;
      _isLoadingLocation = false;
    }
    if (widget.initialLocationCoords != null) {
      _locationCoords = widget.initialLocationCoords;
      _isLoadingLocation = false;
    }
    if (widget.initialIsPublic != null) {
      _isPublic = widget.initialIsPublic!;
    }
    _loadLocationName();
  }

  @override
  void dispose() {
    _trackNameController.dispose();
    super.dispose();
  }

  Future<void> _loadLocationName() async {
    if (widget.initialLocationCoords != null &&
        widget.initialLocationName != null) {
      return;
    }
    if (widget.gpsTrack.isEmpty) {
      setState(() {
        _locationName = 'Località non disponibile';
        _isLoadingLocation = false;
      });
      return;
    }

    try {
      // Usa i primi punti GPS per determinare la località
      final firstPoint = widget.gpsTrack.first;
      _locationCoords = GeoPoint(firstPoint.latitude, firstPoint.longitude);

      final placemarks = await placemarkFromCoordinates(
        firstPoint.latitude,
        firstPoint.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final locality = place.locality ?? place.subAdministrativeArea ?? '';
        final country = place.country ?? '';

        setState(() {
          _locationName = locality.isNotEmpty && country.isNotEmpty
              ? '$locality, $country'
              : 'Località non disponibile';
          _isLoadingLocation = false;
        });
      } else {
        setState(() {
          _locationName = 'Località non disponibile';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationName = 'Località non disponibile';
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _handleSave() {
    final trackName = _trackNameController.text.trim();
    if (trackName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci il nome del circuito'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    if (_locationCoords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendere il caricamento della posizione'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      SessionMetadata(
        trackName: trackName,
        location: _locationName,
        locationCoords: _locationCoords!,
        isPublic: _isPublic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a1a),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            const Text(
              'Salva Sessione',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: kFgColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completa le informazioni sulla sessione',
              style: TextStyle(
                fontSize: 14,
                color: kMutedColor,
              ),
            ),

            const SizedBox(height: 24),

            // Nome circuito
            Text(
              'NOME CIRCUITO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kMutedColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _trackNameController,
              style: const TextStyle(
                fontSize: 16,
                color: kFgColor,
              ),
              decoration: InputDecoration(
                hintText: 'es. Autodromo di Misano',
                hintStyle: TextStyle(color: kMutedColor.withOpacity(0.5)),
                filled: true,
                fillColor: const Color(0xFF0d0d0d),
                prefixIcon: const Icon(Icons.flag_outlined, color: kBrandColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBrandColor, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Posizione geografica
            Text(
              'POSIZIONE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kMutedColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0d0d0d),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kLineColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: kBrandColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _isLoadingLocation
                        ? Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(kMutedColor),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Caricamento...',
                                style: TextStyle(color: kMutedColor),
                              ),
                            ],
                          )
                        : Text(
                            _locationName,
                            style: const TextStyle(
                              fontSize: 15,
                              color: kFgColor,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Privacy
            Text(
              'PRIVACY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kMutedColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            // Radio buttons per privacy
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0d0d0d),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kLineColor),
              ),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _isPublic,
                    onChanged: (value) {
                      setState(() => _isPublic = value ?? true);
                    },
                    activeColor: kBrandColor,
                    title: const Text(
                      'Pubblica',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kFgColor,
                      ),
                    ),
                    subtitle: Text(
                      'Visibile a tutti nel feed',
                      style: TextStyle(
                        fontSize: 13,
                        color: kMutedColor,
                      ),
                    ),
                  ),
                  Divider(color: kLineColor, height: 1),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _isPublic,
                    onChanged: (value) {
                      setState(() => _isPublic = value ?? true);
                    },
                    activeColor: kBrandColor,
                    title: const Text(
                      'Privata',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kFgColor,
                      ),
                    ),
                    subtitle: Text(
                      'Visibile solo a te',
                      style: TextStyle(
                        fontSize: 13,
                        color: kMutedColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kMutedColor,
                      side: BorderSide(color: kLineColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Annulla',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBrandColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: const Text(
                      'SALVA SESSIONE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
