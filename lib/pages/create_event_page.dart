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
import 'map_location_picker.dart';

const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  final EventService _eventService = EventService();
  final EventImageService _imageService = EventImageService();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationNameController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  File? _selectedImage;
  String? _imageUrl;
  double? _latitude;
  double? _longitude;
  bool _isLoadingLocation = false;
  bool _isCreating = false;
  bool _isUploadingImage = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationNameController.dispose();
    _dateController.dispose();
    _timeController.dispose();
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

      // Per ora salviamo solo il riferimento all'immagine
      // L'upload vero verrà fatto al momento della creazione evento
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
      // Se non abbiamo ancora una posizione, ottieni quella corrente
      LatLng? initialLocation;
      if (_latitude != null && _longitude != null) {
        initialLocation = LatLng(_latitude!, _longitude!);
      } else {
        try {
          final position = await Geolocator.getCurrentPosition();
          initialLocation = LatLng(position.latitude, position.longitude);
        } catch (e) {
          // Default a Roma se fallisce
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

        // Prova a ottenere il nome del luogo
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

  Future<void> _createEvent() async {
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

    if (parsedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La data dell\'evento non può essere nel passato'),
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

    setState(() => _isCreating = true);

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

      // Prima crea l'evento per ottenere l'ID
      final eventId = await _eventService.createEvent(
        creatorId: currentUser.uid,
        creatorName: currentUser.displayName ?? 'Utente',
        creatorProfileImage: currentUser.photoURL,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        eventDateTime: eventDateTime,
        latitude: _latitude!,
        longitude: _longitude!,
        locationName: _locationNameController.text.trim().isNotEmpty
            ? _locationNameController.text.trim()
            : null,
        eventImageUrl: null, // Verrà aggiornato dopo l'upload
      );

      // Se c'è un'immagine, caricala
      String? imageUrl;
      if (_selectedImage != null) {
        try {
          // Upload dell'immagine compressa
          final compressedFile = await _imageService.compressImage(_selectedImage!);
          if (compressedFile != null) {
            imageUrl = await _imageService.uploadToStorage(compressedFile, eventId);
            await compressedFile.delete();

            // Aggiorna l'evento con l'URL dell'immagine
            await FirebaseFirestore.instance
                .collection('events')
                .doc(eventId)
                .update({'eventImageUrl': imageUrl});
          }
        } catch (e) {
          print('❌ Errore upload immagine (evento creato senza foto): $e');
          // Continua comunque, l'evento è già stato creato
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Evento creato con successo!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
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
        setState(() => _isCreating = false);
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
          'Crea Evento',
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
              _buildInfoBox(),
              const SizedBox(height: 24),
              _buildCreateButton(),
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
        enabled: !_isCreating,
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
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildImageButton(
                    label: _selectedImage == null ? 'Seleziona Foto' : 'Cambia Foto',
                    icon: Icons.photo_library,
                    onTap: _isUploadingImage ? null : _selectImage,
                  ),
                ),
                if (_selectedImage != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      setState(() => _selectedImage = null);
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
        enabled: !_isCreating,
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
        enabled: !_isCreating,
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

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.blue.withAlpha(15),
        border: Border.all(color: Colors.blue.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Come funziona',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Gli utenti potranno iscriversi al tuo evento e riceveranno un badge quando faranno check-in durante l\'evento nel raggio di 100 metri dalla posizione GPS indicata.',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 12,
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

  Widget _buildCreateButton() {
    return GestureDetector(
      onTap: _isCreating ? null : _createEvent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: _isCreating
                ? [Colors.grey.shade700, Colors.grey.shade800]
                : [Colors.amber, Colors.amber.shade700],
          ),
          boxShadow: _isCreating
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
            if (_isCreating)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.check_circle, color: Colors.black, size: 24),
            const SizedBox(width: 12),
            Text(
              _isCreating ? 'Creazione in corso...' : 'Crea Evento',
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
