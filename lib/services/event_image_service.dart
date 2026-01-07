import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class EventImageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // Esponi picker pubblicamente
  ImagePicker get picker => _picker;

  /// Seleziona e carica una foto per l'evento
  Future<String?> pickAndUploadEventImage(String eventId) async {
    try {
      // Seleziona immagine dalla galleria
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile == null) return null;

      // Comprimi l'immagine
      final compressedFile = await compressImage(File(pickedFile.path));
      if (compressedFile == null) {
        throw Exception('Errore nella compressione dell\'immagine');
      }

      // Upload su Firebase Storage
      final imageUrl = await uploadToStorage(compressedFile, eventId);

      // Elimina file temporaneo
      await compressedFile.delete();

      return imageUrl;
    } catch (e) {
      print('❌ Errore upload immagine evento: $e');
      rethrow;
    }
  }

  /// Comprimi l'immagine (pubblico per uso in create_event_page)
  Future<File?> compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 85,
        minWidth: 1920,
        minHeight: 1080,
      );

      if (result == null) return null;
      return File(result.path);
    } catch (e) {
      print('❌ Errore compressione immagine: $e');
      return null;
    }
  }

  /// Upload su Firebase Storage (pubblico per uso in create_event_page)
  Future<String> uploadToStorage(File file, String eventId) async {
    try {
      // Path: events_images/{eventId}.jpg
      final ref = _storage.ref().child('events_images/$eventId.jpg');

      // Upload
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      // Attendi completamento
      final snapshot = await uploadTask;

      // Ottieni URL download
      final downloadUrl = await snapshot.ref.getDownloadURL();

      print('✅ Immagine evento caricata: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Errore upload Firebase Storage: $e');
      rethrow;
    }
  }

  /// Elimina immagine evento
  Future<void> deleteEventImage(String eventId) async {
    try {
      final ref = _storage.ref().child('events_images/$eventId.jpg');
      await ref.delete();
      print('✅ Immagine evento eliminata: $eventId');
    } catch (e) {
      print('❌ Errore eliminazione immagine: $e');
      // Non bloccare se l'immagine non esiste
    }
  }

  /// Scatta una foto con la fotocamera
  Future<String?> takeAndUploadEventPhoto(String eventId) async {
    try {
      // Scatta foto
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile == null) return null;

      // Comprimi l'immagine
      final compressedFile = await compressImage(File(pickedFile.path));
      if (compressedFile == null) {
        throw Exception('Errore nella compressione dell\'immagine');
      }

      // Upload su Firebase Storage
      final imageUrl = await uploadToStorage(compressedFile, eventId);

      // Elimina file temporaneo
      await compressedFile.delete();

      return imageUrl;
    } catch (e) {
      print('❌ Errore scatto foto evento: $e');
      rethrow;
    }
  }
}
