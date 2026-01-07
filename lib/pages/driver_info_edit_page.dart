import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/driver_info.dart';
import '../theme.dart';

/// Pagina per modificare bacheca pilota dal profilo
/// Accessibile dal profilo utente
class DriverInfoEditPage extends StatefulWidget {
  final DriverInfo initialDriverInfo;

  const DriverInfoEditPage({
    super.key,
    required this.initialDriverInfo,
  });

  @override
  State<DriverInfoEditPage> createState() => _DriverInfoEditPageState();
}

class _DriverInfoEditPageState extends State<DriverInfoEditPage> {
  final Set<String> _selectedBadges = {};
  final TextEditingController _bioController = TextEditingController();
  String? _bioError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Inizializza con i dati esistenti
    _selectedBadges.addAll(widget.initialDriverInfo.selectedBadges);
    _bioController.text = widget.initialDriverInfo.bio;
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  void _toggleBadge(String badgeId) {
    setState(() {
      if (_selectedBadges.contains(badgeId)) {
        _selectedBadges.remove(badgeId);
      } else {
        _selectedBadges.add(badgeId);
      }
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _saveChanges() async {
    final bioError = DriverInfo.validateBio(_bioController.text);
    if (bioError != null) {
      setState(() {
        _bioError = bioError;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Utente non autenticato';

      final driverInfo = DriverInfo(
        selectedBadges: _selectedBadges.toList(),
        bio: _bioController.text.trim(),
      );

      // Salva su Firebase
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'driverInfo': driverInfo.toJson(),
      });

      if (mounted) {
        HapticFeedback.mediumImpact();

        // Mostra snackbar successo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Bacheca aggiornata',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF2A2A2A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

        // Torna indietro passando i nuovi dati
        Navigator.of(context).pop(driverInfo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Errore durante il salvataggio: $e',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: kErrorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Content scrollabile
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Categorie badge
                    ...DriverInfo.badgeCategories.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _buildCategory(entry.key, entry.value),
                      );
                    }).toList(),

                    const SizedBox(height: 8),

                    // Campo Bio
                    _buildBioField(),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Footer con bottoni
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            kBgColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Bottone indietro
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF2A2A2A),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.arrow_back,
                color: kFgColor,
                size: 20,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Titolo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modifica Bacheca',
                  style: TextStyle(
                    color: kFgColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Aggiorna le tue informazioni pubbliche',
                  style: TextStyle(
                    color: kMutedColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(String categoryName, List<Map<String, String>> badges) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo categoria con underline
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: kBrandColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                categoryName,
                style: TextStyle(
                  color: kFgColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Badge della categoria
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: badges.map((badge) {
              final badgeId = badge['id']!;
              final label = badge['label']!;
              final isSelected = _selectedBadges.contains(badgeId);

              return _buildBadgeButton(badgeId, label, isSelected);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeButton(String badgeId, String label, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleBadge(badgeId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    kBrandColor,
                    kBrandColor.withAlpha(220),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    const Color(0xFF1F1F1F),
                    const Color(0xFF1A1A1A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? kBrandColor.withAlpha(120)
                : const Color(0xFF2A2A2A),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: kBrandColor.withAlpha(50),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(
                Icons.check_circle_rounded,
                color: Colors.black,
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : kFgColor.withAlpha(200),
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                letterSpacing: isSelected ? -0.2 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBioField() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF141414),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _bioError != null
              ? kErrorColor.withAlpha(100)
              : const Color(0xFF2A2A2A),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _bioError != null
                ? kErrorColor.withAlpha(20)
                : Colors.black.withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo con icona
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: kBrandColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Bio',
                style: TextStyle(
                  color: kFgColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _bioController.text.length > 100
                      ? kErrorColor.withAlpha(20)
                      : Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _bioController.text.length > 100
                        ? kErrorColor.withAlpha(60)
                        : const Color(0xFF2A2A2A),
                  ),
                ),
                child: Text(
                  '${_bioController.text.length}/100',
                  style: TextStyle(
                    color: _bioController.text.length > 100
                        ? kErrorColor
                        : kMutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Campo testo
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(40),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _bioError != null
                    ? kErrorColor.withAlpha(80)
                    : const Color(0xFF2A2A2A),
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _bioController,
              maxLength: 100,
              maxLines: 4,
              style: TextStyle(
                color: kFgColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'Scrivi qualcosa su di te...',
                hintStyle: TextStyle(
                  color: kMutedColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(18),
                counterText: '',
              ),
              onChanged: (value) {
                setState(() {
                  if (_bioError != null) {
                    _bioError = null;
                  }
                });
              },
            ),
          ),

          // Errore
          if (_bioError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kErrorColor.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: kErrorColor.withAlpha(60),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: kErrorColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _bioError!,
                      style: TextStyle(
                        color: kErrorColor,
                        fontSize: 12,
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
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kBgColor,
            const Color(0xFF1A1A1A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
      ),
      child: GestureDetector(
        onTap: _isSaving ? null : _saveChanges,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: _isSaving
                ? null
                : LinearGradient(
                    colors: [
                      kBrandColor,
                      kBrandColor.withAlpha(220),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: _isSaving ? const Color(0xFF2A2A2A) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isSaving
                  ? const Color(0xFF3A3A3A)
                  : kBrandColor.withAlpha(60),
              width: 1.5,
            ),
            boxShadow: _isSaving
                ? null
                : [
                    BoxShadow(
                      color: kBrandColor.withAlpha(40),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Center(
            child: _isSaving
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(kMutedColor),
                    ),
                  )
                : Text(
                    'Salva Modifiche',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
