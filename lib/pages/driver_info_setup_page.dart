import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/driver_info.dart';
import '../theme.dart';

/// Pagina setup bacheca pilota durante registrazione
/// Appare dopo la pagina dati personali
class DriverInfoSetupPage extends StatefulWidget {
  final Function(DriverInfo driverInfo) onComplete;

  const DriverInfoSetupPage({
    super.key,
    required this.onComplete,
  });

  @override
  State<DriverInfoSetupPage> createState() => _DriverInfoSetupPageState();
}

class _DriverInfoSetupPageState extends State<DriverInfoSetupPage> {
  final Set<String> _selectedBadges = {};
  final TextEditingController _bioController = TextEditingController();
  String? _bioError;

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

  void _validateAndComplete() {
    print('🔵 _validateAndComplete chiamato');
    final bioError = DriverInfo.validateBio(_bioController.text);
    if (bioError != null) {
      print('❌ Errore validazione bio: $bioError');
      setState(() {
        _bioError = bioError;
      });
      HapticFeedback.mediumImpact();
      return;
    }

    final driverInfo = DriverInfo(
      selectedBadges: _selectedBadges.toList(),
      bio: _bioController.text.trim(),
    );

    print('✅ Validazione OK, chiamando onComplete con ${_selectedBadges.length} badges');
    widget.onComplete(driverInfo);
  }

  void _skip() {
    // Salta e passa info vuote
    widget.onComplete(DriverInfo.empty());
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
                    // Descrizione
                    _buildDescription(),
                    const SizedBox(height: 28),

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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        // gradient: LinearGradient(
        //   colors: [
        //     const Color(0xFF1A1A1A),
        //     kBgColor,
        //   ],
        //   begin: Alignment.topCenter,
        //   end: Alignment.bottomCenter,
        // ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Icon badge
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(40),
                  kBrandColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: kBrandColor.withAlpha(60),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.person_pin_outlined,
                color: kBrandColor,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bacheca Pilota',
            style: TextStyle(
              color: kFgColor,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Personalizza il tuo profilo pubblico',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMutedColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kBrandColor.withAlpha(15),
            kBrandColor.withAlpha(8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kBrandColor.withAlpha(40),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: kBrandColor.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kBrandColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: kBrandColor.withAlpha(50),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.info_outline,
              color: kBrandColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Seleziona le informazioni che vuoi condividere con altri piloti e sponsor',
              style: TextStyle(
                color: kFgColor.withAlpha(220),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
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
      child: Row(
        children: [
          // Bottone Salta
          Expanded(
            child: GestureDetector(
              onTap: _skip,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2A2A2A),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Salta',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Bottone Continua
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _validateAndComplete,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kBrandColor,
                      kBrandColor.withAlpha(220),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: kBrandColor.withAlpha(60),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withAlpha(40),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Continua',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
