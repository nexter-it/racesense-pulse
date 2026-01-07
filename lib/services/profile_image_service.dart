import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ProfileImageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  /// Permette all'utente di scegliere un'immagine dalla galleria
  Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      print('❌ Errore selezione immagine: $e');
      return null;
    }
  }

  /// Comprime l'immagine selezionata
  Future<File?> compressImage(String imagePath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        imagePath,
        targetPath,
        quality: 70,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.jpeg,
      );

      if (compressedFile == null) {
        print('❌ Errore compressione immagine');
        return null;
      }

      return File(compressedFile.path);
    } catch (e) {
      print('❌ Errore compressione immagine: $e');
      return null;
    }
  }

  /// Carica l'immagine su Firebase Storage e restituisce l'URL
  Future<String?> uploadProfileImage(File imageFile, String userId) async {
    try {
      final storageRef = _storage.ref().child('users_profiles_image/$userId.jpg');

      final uploadTask = storageRef.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      print('✅ Immagine caricata su Firebase Storage: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Errore upload immagine: $e');
      return null;
    }
  }

  /// Salva l'URL dell'immagine nel documento utente in Firestore
  Future<void> saveProfileImageUrl(String userId, String imageUrl) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'profileImageUrl': imageUrl,
        'profileImageUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ URL immagine profilo salvato in Firestore');
    } catch (e) {
      print('❌ Errore salvataggio URL in Firestore: $e');
      rethrow;
    }
  }

  /// Elimina l'immagine profilo (sia da Storage che da Firestore)
  Future<void> deleteProfileImage(String userId) async {
    try {
      // Elimina da Storage
      final storageRef = _storage.ref().child('users_profiles_image/$userId.jpg');
      await storageRef.delete();

      // Rimuovi URL da Firestore
      await _firestore.collection('users').doc(userId).update({
        'profileImageUrl': FieldValue.delete(),
        'profileImageUpdatedAt': FieldValue.delete(),
      });

      print('✅ Immagine profilo eliminata');
    } catch (e) {
      print('❌ Errore eliminazione immagine: $e');
      rethrow;
    }
  }

  /// Workflow completo: pick, compress, upload e save
  Future<String?> updateProfileImage(String userId) async {
    try {
      // 1. Seleziona immagine
      final pickedImage = await pickImageFromGallery();
      if (pickedImage == null) {
        print('⚠️ Nessuna immagine selezionata');
        return null;
      }

      // 2. Comprimi immagine
      final compressedImage = await compressImage(pickedImage.path);
      if (compressedImage == null) {
        print('❌ Errore compressione immagine');
        return null;
      }

      // 3. Upload su Firebase Storage
      final imageUrl = await uploadProfileImage(compressedImage, userId);
      if (imageUrl == null) {
        print('❌ Errore upload immagine');
        return null;
      }

      // 4. Salva URL in Firestore
      await saveProfileImageUrl(userId, imageUrl);

      // 5. Pulisci file temporaneo
      try {
        await compressedImage.delete();
      } catch (e) {
        print('⚠️ Impossibile eliminare file temporaneo: $e');
      }

      return imageUrl;
    } catch (e) {
      print('❌ Errore workflow aggiornamento immagine profilo: $e');
      return null;
    }
  }

  /// Ottiene l'URL dell'immagine profilo di un utente
  Future<String?> getProfileImageUrl(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data()?['profileImageUrl'] as String?;
    } catch (e) {
      print('❌ Errore recupero URL immagine profilo: $e');
      return null;
    }
  }
}
