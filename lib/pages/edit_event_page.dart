import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../services/event_service.dart';
import '../services/event_image_service.dart';
import '../services/official_circuits_service.dart';
import '../models/event_model.dart';
import '../models/official_circuit_info.dart';
import 'map_location_picker.dart';

const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class EditEventPage extends StatefulWidget {
  final EventModel event;

  const EditEventPage({super.key, required this.event});

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  final _formKey = GlobalKey<FormState>();
  final EventService _eventService = EventService();
  final EventImageService _imageService = EventImageService();
  final OfficialCircuitsService _circuitsService = OfficialCircuitsService();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationNameController;
  late TextEditingController _dateController;
  late TextEditingController _timeController;
  late TextEditingController _entryFeeController;
  late TextEditingController _websiteController;

  File? _selectedImage;
  String? _existingImageUrl;
  double? _latitude;
  double? _longitude;
  bool _isLoadingLocation = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  bool _imageRemoved = false;

  OfficialCircuitInfo? _selectedCircuit;
  List<OfficialCircuitInfo> _circuits = [];

  @override
  void initState() {
    super.initState();
    _initializeFromEvent();
    _loadCircuits();
  }

  void _initializeFromEvent() {
    final event = widget.event;

    _titleController = TextEditingController(text: event.title);
    _descriptionController = TextEditingController(text: event.description);
    _locationNameController = TextEditingController(text: event.locationName ?? '');

    // Formatta data
    final date = event.eventDateTime;
    _dateController = TextEditingController(
      text: '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
    );

    // Formatta ora
    _timeController = TextEditingController(
      text: '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
    );

    _entryFeeController = TextEditingController(
      text: event.entryFee != null ? event.entryFee!.toStringAsFixed(0) : '',
    );
    _websiteController = TextEditingController(text: event.websiteUrl ?? '');

    _existingImageUrl = event.eventImageUrl;
    _latitude = event.location.latitude;
    _longitude = event.location.longitude;
  }

  Future<void> _loadCircuits() async {
    final circuits = await _circuitsService.loadCircuits();
    if (mounted) {
      setState(() {
        _circuits = circuits;
        // Se l'evento ha un circuito ufficiale, selezionalo
        if (widget.event.officialCircuitId != null) {
          _selectedCircuit = circuits.firstWhere(
            (c) => c.file == widget.event.officialCircuitId,
            orElse: () => circuits.first,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationNameController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _entryFeeController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String text) {
    if (text.length != 10) return null;
    final parts = text.split('/');
    if (parts.length != 3) return null;

    try {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      if (day < 1 || day > 31) return null;
      if (month < 1 || month > 12) return null;
      if (year < 2020 || year > 2100) return null;

      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  TimeOfDay? _parseTime(String text) {
    if (text.length != 5) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;

    try {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      if (hour < 0 || hour > 23) return null;
      if (minute < 0 || minute > 59) return null;

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null;
    }
  }

  Future<void> _selectImage() async {
    try {
      setState(() => _isUploadingImage = true);

      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _kCardStart,
          title: const Text(
            'Seleziona Foto',
            style: TextStyle(color: kFgColor, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library, color: kBrandColor),
                title: const Text('Galleria', style: TextStyle(color: kFgColor)),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: kBrandColor),
                title: const Text('Fotocamera', style: TextStyle(color: kFgColor)),
                onTap: () => Navigator.of(context).pop('camera'),
              ),
            ],
          ),
        ),
      );

      if (result == null) {
        setState(() => _isUploadingImage = false);
        return;
      }

      if (result == 'gallery') {
        final picked = await _imageService.picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (picked != null) {
          setState(() {
            _selectedImage = File(picked.path);
            _imageRemoved = false;
          });
        }
      } else if (result == 'camera') {
        final picked = await _imageService.picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (picked != null) {
          setState(() {
            _selectedImage = File(picked.path);
            _imageRemoved = false;
          });
        }
      }

      setState(() => _isUploadingImage = false);
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore selezione immagine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permessi di localizzazione negati');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permessi di localizzazione negati permanentemente');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final locationName = [
            placemark.name,
            placemark.locality,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
          _locationNameController.text = locationName;
        }
      } catch (e) {
        _locationNameController.text =
            'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}';
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isLoadingLocation = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Posizione ottenuta con successo'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoadingLocation = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectLocationOnMap() async {
    try {
      LatLng? initialLocation;
      if (_latitude != null && _longitude != null) {
        initialLocation = LatLng(_latitude!, _longitude!);
      } else {
        try {
          final position = await Geolocator.getCurrentPosition();
          initialLocation = LatLng(position.latitude, position.longitude);
        } catch (e) {
          initialLocation = LatLng(41.9028, 12.4964);
        }
      }

      final result = await Navigator.of(context).push<LatLng>(
        MaterialPageRoute(
          builder: (_) => MapLocationPicker(initialLocation: initialLocation),
        ),
      );

      if (result != null) {
        setState(() {
          _latitude = result.latitude;
          _longitude = result.longitude;
        });

        try {
          final placemarks = await placemarkFromCoordinates(
            result.latitude,
            result.longitude,
          );
          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            final locationName = [
              placemark.name,
              placemark.locality,
            ].where((e) => e != null && e.isNotEmpty).join(', ');
            _locationNameController.text = locationName;
          }
        } catch (e) {
          // Ignore geocoding errors
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Posizione selezionata sulla mappa'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    // Valida data
    final dateText = _dateController.text.trim();
    if (dateText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci la data dell\'evento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final parsedDate = _parseDate(dateText);
    if (parsedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato data non valido. Usa dd/mm/yyyy'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Valida ora
    final timeText = _timeController.text.trim();
    if (timeText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci l\'orario dell\'evento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final parsedTime = _parseTime(timeText);
    if (parsedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formato orario non valido. Usa hh:mm'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Valida GPS
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ottieni la posizione GPS per l\'evento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }

      // Combina data e ora
      final eventDateTime = DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
        parsedTime.hour,
        parsedTime.minute,
      );

      // Parsa costo iscrizione
      double? entryFee;
      if (_entryFeeController.text.trim().isNotEmpty) {
        entryFee = double.tryParse(_entryFeeController.text.trim());
      }

      // Gestisci upload immagine
      String? imageUrl = _existingImageUrl;
      if (_imageRemoved) {
        imageUrl = null;
      } else if (_selectedImage != null) {
        try {
          final compressedFile = await _imageService.compressImage(_selectedImage!);
          if (compressedFile != null) {
            imageUrl = await _imageService.uploadToStorage(compressedFile, widget.event.eventId);
            await compressedFile.delete();
          }
        } catch (e) {
          print('Errore upload immagine: $e');
        }
      }

      // Aggiorna evento
      await _eventService.updateEvent(
        eventId: widget.event.eventId,
        userId: currentUser.uid,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        eventDateTime: eventDateTime,
        latitude: _latitude!,
        longitude: _longitude!,
        locationName: _locationNameController.text.trim().isNotEmpty
            ? _locationNameController.text.trim()
            : null,
        eventImageUrl: imageUrl,
        officialCircuitId: _selectedCircuit?.file,
        officialCircuitName: _selectedCircuit?.name,
        entryFee: entryFee,
        websiteUrl: _websiteController.text.trim().isNotEmpty
            ? _websiteController.text.trim()
            : null,
      );

      // Aggiorna imageUrl separatamente se è stata rimossa
      if (_imageRemoved) {
        await FirebaseFirestore.instance
            .collection('events')
            .doc(widget.event.eventId)
            .update({'eventImageUrl': FieldValue.delete()});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Evento aggiornato con successo!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Ritorna true per indicare che c'è stato un aggiornamento
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
          'Modifica Evento',
          style: TextStyle(
            color: kFgColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader('Informazioni evento'),
              const SizedBox(height: 12),
              _buildInputLabel('TITOLO EVENTO'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _titleController,
                hint: 'Es: Track Day Monza 2026',
                icon: Icons.title,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Inserisci un titolo';
                  }
                  if (value.trim().length < 3) {
                    return 'Il titolo deve essere di almeno 3 caratteri';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildInputLabel('DESCRIZIONE'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _descriptionController,
                hint: 'Descrivi l\'evento e cosa aspettarsi...',
                icon: Icons.description,
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Inserisci una descrizione';
                  }
                  if (value.trim().length < 10) {
                    return 'La descrizione deve essere di almeno 10 caratteri';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Foto evento'),
              const SizedBox(height: 12),
              _buildImageSection(),
              const SizedBox(height: 24),
              _buildSectionHeader('Data e ora'),
              const SizedBox(height: 12),
              _buildInputLabel('DATA EVENTO'),
              const SizedBox(height: 8),
              _buildDateField(),
              const SizedBox(height: 16),
              _buildInputLabel('ORARIO EVENTO'),
              const SizedBox(height: 8),
              _buildTimeField(),
              const SizedBox(height: 24),
              _buildSectionHeader('Circuito (opzionale)'),
              const SizedBox(height: 12),
              _buildCircuitSelector(),
              const SizedBox(height: 24),
              _buildSectionHeader('Posizione GPS'),
              const SizedBox(height: 12),
              _buildInputLabel('NOME LUOGO (OPZIONALE)'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _locationNameController,
                hint: 'Es: Autodromo di Monza',
                icon: Icons.location_on,
              ),
              const SizedBox(height: 16),
              _buildLocationButtons(),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 12),
                _buildLocationConfirmation(),
              ],
              const SizedBox(height: 24),
              _buildSectionHeader('Dettagli aggiuntivi (opzionale)'),
              const SizedBox(height: 12),
              _buildInputLabel('COSTO ISCRIZIONE (€)'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _entryFeeController,
                hint: 'Es: 150 (lascia vuoto se gratuito)',
                icon: Icons.euro,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildInputLabel('SITO WEB'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _websiteController,
                hint: 'Es: https://www.trackday-monza.it',
                icon: Icons.language,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),
              _buildSaveButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
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
            color: Colors.amber,
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

  Widget _buildInputLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: kMutedColor,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        enabled: !_isSaving,
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.amber, size: 18),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildImageSection() {
    final hasImage = _selectedImage != null ||
        (_existingImageUrl != null && !_imageRemoved);

    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: Column(
        children: [
          if (_selectedImage != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.file(
                _selectedImage!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else if (_existingImageUrl != null && !_imageRemoved)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.network(
                _existingImageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  color: _kBorderColor,
                  child: Center(
                    child: Icon(Icons.broken_image, color: kMutedColor, size: 48),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildImageButton(
                    label: hasImage ? 'Cambia Foto' : 'Seleziona Foto',
                    icon: Icons.photo_library,
                    onTap: _isUploadingImage ? null : _selectImage,
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedImage = null;
                        _imageRemoved = true;
                      });
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageButton({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: onTap == null ? Colors.grey.shade800 : Colors.amber.withAlpha(25),
          border: Border.all(
            color: onTap == null ? Colors.grey.shade700 : Colors.amber.withAlpha(80),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: onTap == null ? Colors.grey : Colors.amber, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? Colors.grey : kFgColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: _dateController,
        keyboardType: TextInputType.number,
        enabled: !_isSaving,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          _DateInputFormatter(),
        ],
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'dd/mm/yyyy',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.calendar_today, color: Colors.amber, size: 18),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeField() {
    return Container(
      decoration: BoxDecoration(
        color: _kTileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor, width: 1),
      ),
      child: TextFormField(
        controller: _timeController,
        keyboardType: TextInputType.number,
        enabled: !_isSaving,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          _TimeInputFormatter(),
        ],
        style: const TextStyle(
          fontSize: 16,
          color: kFgColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'hh:mm',
          hintStyle: TextStyle(color: kMutedColor.withOpacity(0.4)),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.access_time, color: Colors.amber, size: 18),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildLocationButton(
            label: 'Posizione Attuale',
            icon: Icons.my_location,
            onTap: _isLoadingLocation ? null : _getCurrentLocation,
            isLoading: _isLoadingLocation,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildLocationButton(
            label: 'Seleziona su Mappa',
            icon: Icons.map,
            onTap: _selectLocationOnMap,
            color: kBrandColor,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationButton({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    bool isLoading = false,
    Color? color,
  }) {
    final btnColor = color ?? Colors.amber;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [btnColor.withAlpha(200), btnColor.withAlpha(180)],
          ),
          boxShadow: [
            BoxShadow(
              color: btnColor.withAlpha(60),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            else
              Icon(icon, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationConfirmation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.green.withAlpha(15),
        border: Border.all(color: Colors.green.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Posizione GPS salvata',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lat: ${_latitude!.toStringAsFixed(6)}, Lng: ${_longitude!.toStringAsFixed(6)}',
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
    );
  }

  Widget _buildCircuitSelector() {
    return GestureDetector(
      onTap: () => _showCircuitPicker(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kTileColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selectedCircuit != null ? kBrandColor.withAlpha(80) : _kBorderColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.stadium,
                color: kBrandColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedCircuit?.name ?? 'Seleziona circuito',
                    style: TextStyle(
                      color: _selectedCircuit != null ? kFgColor : kMutedColor.withAlpha(100),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_selectedCircuit != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedCircuit!.city}, ${_selectedCircuit!.country}',
                      style: TextStyle(
                        color: kMutedColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_selectedCircuit != null)
              IconButton(
                icon: Icon(Icons.close, color: kMutedColor, size: 20),
                onPressed: () {
                  setState(() {
                    _selectedCircuit = null;
                  });
                },
              )
            else
              Icon(Icons.arrow_drop_down, color: kMutedColor),
          ],
        ),
      ),
    );
  }

  Future<void> _showCircuitPicker() async {
    final searchController = TextEditingController();
    List<OfficialCircuitInfo> filteredCircuits = List.from(_circuits);

    final result = await showModalBottomSheet<OfficialCircuitInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: _kCardStart,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Seleziona Circuito',
                          style: TextStyle(
                            color: kFgColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: kMutedColor),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: _kTileColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorderColor),
                      ),
                      child: TextField(
                        controller: searchController,
                        style: const TextStyle(color: kFgColor),
                        decoration: InputDecoration(
                          hintText: 'Cerca circuito...',
                          hintStyle: TextStyle(color: kMutedColor.withAlpha(100)),
                          prefixIcon: Icon(Icons.search, color: kMutedColor),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            if (value.isEmpty) {
                              filteredCircuits = List.from(_circuits);
                            } else {
                              final q = value.toLowerCase();
                              filteredCircuits = _circuits.where((c) =>
                                c.name.toLowerCase().contains(q) ||
                                c.city.toLowerCase().contains(q)
                              ).toList();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filteredCircuits.length,
                  itemBuilder: (context, index) {
                    final circuit = filteredCircuits[index];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(circuit),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kTileColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: kBrandColor.withAlpha(20),
                              ),
                              child: Center(
                                child: Text(
                                  circuit.name.substring(0, 1),
                                  style: TextStyle(
                                    color: kBrandColor,
                                    fontSize: 18,
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
                                  Text(
                                    circuit.name,
                                    style: const TextStyle(
                                      color: kFgColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${circuit.city}, ${circuit.country}',
                                    style: TextStyle(
                                      color: kMutedColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: kMutedColor),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedCircuit = result;
        _locationNameController.text = '${result.name}, ${result.city}';
        _latitude = result.finishLineCenter.latitude;
        _longitude = result.finishLineCenter.longitude;
      });
    }
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _saveEvent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: _isSaving
                ? [Colors.grey.shade700, Colors.grey.shade800]
                : [Colors.amber, Colors.amber.shade700],
          ),
          boxShadow: _isSaving
              ? null
              : [
                  BoxShadow(
                    color: Colors.amber.withAlpha(80),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSaving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.save, color: Colors.black, size: 24),
            const SizedBox(width: 12),
            Text(
              _isSaving ? 'Salvataggio in corso...' : 'Salva Modifiche',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Input formatter per data dd/mm/yyyy
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    for (int i = 0; i < text.length && i < 8; i++) {
      buffer.write(text[i]);
      if (i == 1 || i == 3) buffer.write('/');
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Input formatter per ora hh:mm
class _TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    for (int i = 0; i < text.length && i < 4; i++) {
      buffer.write(text[i]);
      if (i == 1) buffer.write(':');
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
