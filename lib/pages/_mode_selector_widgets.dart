import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import '../models/track_definition.dart';
import '../services/ble_tracking_service.dart';
import '../services/custom_circuit_service.dart';
import 'custom_circuit_detail_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kTileColor = Color(0xFF0D0D0D);

/// Modalità di avvio sessione - RaceChrono Pro Style
///
/// Solo circuiti pre-tracciati (esistenti o custom).
/// Rimosso: quick mode, manual line.
enum StartMode { existing, privateCustom }

class ModeSelector extends StatelessWidget {
  final StartMode? selected;
  final ValueChanged<StartMode> onSelect;

  const ModeSelector({
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ModeCard(
        //   title: 'Circuiti ufficiali',
        //   subtitle: 'Autodromi famosi con linea S/F precisa',
        //   icon: Icons.track_changes,
        //   badge: 'Consigliata',
        //   selected: selected == StartMode.existing,
        //   onTap: () => onSelect(StartMode.existing),
        // ),
        const SizedBox(height: 0),
        ModeCard(
          title: 'Circuiti custom',
          subtitle: 'I tuoi tracciati salvati con GPS grezzo + linea S/F',
          icon: Icons.lock_outline,
          badge: 'Personali',
          selected: selected == StartMode.privateCustom,
          onTap: () => onSelect(StartMode.privateCustom),
        ),
      ],
    );
  }
}

class ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [
              Color.fromRGBO(255, 255, 255, 0.06),
              Color.fromRGBO(255, 255, 255, 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: selected ? kBrandColor : kLineColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? kBrandColor.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
              ),
              child: Icon(
                icon,
                color: selected ? kBrandColor : kMutedColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: kMutedColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? kBrandColor.withOpacity(0.15)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? kBrandColor : kLineColor.withOpacity(0.7),
                ),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? kBrandColor : kMutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGINA CIRCUITI UFFICIALI - PREMIUM STYLE
// ═══════════════════════════════════════════════════════════════════════════
class ExistingCircuitPage extends StatelessWidget {
  const ExistingCircuitPage({super.key});

  @override
  Widget build(BuildContext context) {
    final staticTracks = PredefinedTracks.all;

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Premium Header
            _buildHeader(context),
            // Content
            Expanded(
              child: staticTracks.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: staticTracks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final t = staticTracks[index];
                        return _CircuitCard(
                          name: t.name,
                          location: t.location,
                          lengthKm: t.estimatedLengthMeters != null
                              ? (t.estimatedLengthMeters! / 1000)
                              : null,
                          icon: Icons.flag_circle,
                          isOfficial: true,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop(t);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgColor, const Color(0xFF121212)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(Icons.arrow_back_ios_new, color: kFgColor, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kBrandColor.withAlpha(40),
                  kBrandColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kBrandColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.flag_circle, color: kBrandColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Circuiti Ufficiali',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Autodromi con linea S/F precisa',
                  style: TextStyle(
                    fontSize: 11,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Badge count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: kBrandColor.withAlpha(20),
              border: Border.all(color: kBrandColor.withAlpha(60)),
            ),
            child: Text(
              '${PredefinedTracks.all.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: kBrandColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kCardStart, _kCardEnd],
                ),
                border: Border.all(color: _kBorderColor),
              ),
              child: Center(
                child: Icon(Icons.flag_outlined, size: 36, color: kMutedColor),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nessun circuito disponibile',
              style: TextStyle(
                color: kFgColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'I circuiti ufficiali saranno\naggiunti prossimamente',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGINA CIRCUITI CUSTOM - PREMIUM STYLE
// ═══════════════════════════════════════════════════════════════════════════
class PrivateCircuitsPage extends StatefulWidget {
  const PrivateCircuitsPage({super.key});

  @override
  State<PrivateCircuitsPage> createState() => _PrivateCircuitsPageState();
}

class _PrivateCircuitsPageState extends State<PrivateCircuitsPage> {
  final CustomCircuitService _service = CustomCircuitService();
  late Future<List<CustomCircuitInfo>> _future;
  final TextEditingController _searchController = TextEditingController();
  List<CustomCircuitInfo> _allCircuits = [];
  List<CustomCircuitInfo> _filteredCircuits = [];

  @override
  void initState() {
    super.initState();
    _future = _service.listCircuits();
    _searchController.addListener(_filterCircuits);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCircuits() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCircuits = _allCircuits;
      } else {
        _filteredCircuits = _allCircuits.where((c) {
          return c.name.toLowerCase().contains(query) ||
              c.city.toLowerCase().contains(query) ||
              c.country.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  TrackDefinition? _toTrack(CustomCircuitInfo c) {
    // Validazione: il circuito deve avere una linea S/F valida
    if (c.finishLineStart == null || c.finishLineEnd == null) {
      return null;
    }
    return c.toTrackDefinition();
  }

  Future<void> _deleteCircuit(CustomCircuitInfo circuit) async {
    if (circuit.trackId == null) return;

    // Mostra dialog di conferma
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kBorderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kErrorColor.withAlpha(20),
                  border: Border.all(color: kErrorColor.withAlpha(60), width: 2),
                ),
                child: Icon(Icons.delete_forever, color: kErrorColor, size: 32),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'Elimina Circuito',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              // Message
              Text(
                'Sei sicuro di voler eliminare "${circuit.name}"?\n\nQuesta azione non può essere annullata.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: kMutedColor,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  // Cancel
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop(false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withAlpha(10),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: const Text(
                          'Annulla',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kFgColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Delete
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).pop(true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [kErrorColor, kErrorColor.withAlpha(200)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: kErrorColor.withAlpha(60),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Elimina',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        // Mostra loading
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(kFgColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Eliminazione in corso...', style: TextStyle(
                            color: Colors.white,
                          )),
                ],
              ),
              backgroundColor: _kCardStart,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Elimina da Firebase
        await _service.deleteCircuit(circuit.trackId!);

        // Refresh lista
        setState(() {
          _allCircuits.remove(circuit);
          _filteredCircuits.remove(circuit);
          _future = _service.listCircuits();
        });

        // Mostra successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: kBrandColor, size: 20),
                  const SizedBox(width: 12),
                  const Text('Circuito eliminato con successo', style: TextStyle(
                            color: Colors.white,
                          ),),
                ],
              ),
              backgroundColor: _kCardStart,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: kErrorColor, size: 20),
                  const SizedBox(width: 12),
                  Text('Errore: $e'),
                ],
              ),
              backgroundColor: kErrorColor.withAlpha(200),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Premium Header
            _buildHeader(context),
            // Content
            Expanded(
              child: FutureBuilder<List<CustomCircuitInfo>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation(kBrandColor),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Caricamento circuiti...',
                            style: TextStyle(
                              color: kMutedColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final circuits = snapshot.data ?? [];
                  // Inizializza la lista filtrata
                  if (_allCircuits.isEmpty && circuits.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _allCircuits = circuits;
                        _filteredCircuits = circuits;
                      });
                    });
                  }
                  if (circuits.isEmpty) {
                    return _buildEmptyState();
                  }

                  final displayCircuits = _filteredCircuits.isNotEmpty ? _filteredCircuits : circuits;

                  return Column(
                    children: [
                      // Barra di ricerca
                      _buildSearchBar(),
                      // Risultati
                      if (_searchController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 16, color: kMutedColor),
                              const SizedBox(width: 8),
                              Text(
                                '${displayCircuits.length} ${displayCircuits.length == 1 ? 'risultato' : 'risultati'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kMutedColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Lista circuiti
                      Expanded(
                        child: displayCircuits.isEmpty
                            ? _buildNoResultsState()
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                itemCount: displayCircuits.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final c = displayCircuits[index];
                                  final t = _toTrack(c);
                                  return _CircuitCard(
                                    name: c.name,
                                    location: '${c.city} ${c.country}'.trim(),
                                    lengthKm: c.lengthMeters / 1000,
                                    icon: Icons.edit_road,
                                    isOfficial: false,
                                    usedBle: c.usedBleDevice,
                                    hasError: t == null,
                                    onTap: t != null
                                        ? () async {
                                            HapticFeedback.lightImpact();
                                            // Apri pagina dettaglio
                                            final result = await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => CustomCircuitDetailPage(
                                                  circuit: c,
                                                  selectionMode: true,
                                                ),
                                              ),
                                            );
                                            if (result != null) {
                                              Navigator.of(context).pop(result);
                                            }
                                          }
                                        : null,
                                    onDelete: () {
                                      HapticFeedback.lightImpact();
                                      _deleteCircuit(c);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgColor, const Color(0xFF121212)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(Icons.arrow_back_ios_new, color: kFgColor, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  kPulseColor.withAlpha(40),
                  kPulseColor.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: kPulseColor.withAlpha(60), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.edit_road, color: kPulseColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Circuiti Custom',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'I tuoi tracciati personali',
                  style: TextStyle(
                    fontSize: 11,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Info icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withAlpha(6),
              border: Border.all(color: _kBorderColor),
            ),
            child: Icon(Icons.info_outline, color: kMutedColor, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: const Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
          color: kFgColor,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Cerca circuito...',
          hintStyle: TextStyle(
            color: kMutedColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(Icons.search, color: kPulseColor, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: kMutedColor, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    HapticFeedback.lightImpact();
                  },
                )
              : null,
          filled: true,
          fillColor: _kTileColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _kBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _kBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPulseColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kCardStart, _kCardEnd],
                ),
                border: Border.all(color: _kBorderColor),
              ),
              child: Center(
                child: Icon(Icons.search_off, size: 36, color: kMutedColor),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nessun risultato',
              style: TextStyle(
                color: kFgColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nessun circuito trovato per\n"${_searchController.text}"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kCardStart, _kCardEnd],
                ),
                border: Border.all(color: _kBorderColor),
              ),
              child: Center(
                child: Icon(Icons.add_road, size: 36, color: kMutedColor),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nessun circuito salvato',
              style: TextStyle(
                color: kFgColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crea il tuo primo circuito\ndalla pagina Nuova Attività',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            // Tip card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [_kCardStart, _kCardEnd],
                ),
                border: Border.all(color: _kBorderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kBrandColor.withAlpha(20),
                      border: Border.all(color: kBrandColor.withAlpha(50)),
                    ),
                    child: Icon(Icons.lightbulb_outline, color: kBrandColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I circuiti custom ti permettono di tracciare qualsiasi percorso con la tua linea S/F personalizzata.',
                      style: TextStyle(
                        fontSize: 12,
                        color: kMutedColor,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CIRCUIT CARD WIDGET - CONDIVISO TRA ENTRAMBE LE PAGINE
// ═══════════════════════════════════════════════════════════════════════════
class _CircuitCard extends StatelessWidget {
  final String name;
  final String location;
  final double? lengthKm;
  final IconData icon;
  final bool isOfficial;
  final bool usedBle;
  final bool hasError;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _CircuitCard({
    required this.name,
    required this.location,
    this.lengthKm,
    required this.icon,
    required this.isOfficial,
    this.usedBle = false,
    this.hasError = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? kErrorColor.withAlpha(150)
        : (isOfficial ? kBrandColor.withAlpha(80) : kPulseColor.withAlpha(80));
    final accentColor = hasError ? kErrorColor : (isOfficial ? kBrandColor : kPulseColor);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    accentColor.withAlpha(25),
                    accentColor.withAlpha(10),
                  ],
                ),
                border: Border.all(color: accentColor.withAlpha(60)),
              ),
              child: Center(
                child: Icon(
                  hasError ? Icons.error_outline : icon,
                  color: accentColor,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: kFgColor,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: kMutedColor, size: 13),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            color: kMutedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Bottom row with badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      // Length badge
                      if (lengthKm != null)
                        _buildBadge(
                          icon: Icons.straighten,
                          text: '${lengthKm!.toStringAsFixed(2)} km',
                          color: accentColor,
                        ),
                      // BLE badge
                      if (usedBle)
                        _buildBadge(
                          icon: Icons.bluetooth_connected,
                          text: 'GPS PRO',
                          color: kBrandColor,
                        ),
                      // Official badge
                      if (isOfficial)
                        _buildBadge(
                          icon: Icons.verified,
                          text: 'Ufficiale',
                          color: kBrandColor,
                        ),
                      // Error badge
                      if (hasError)
                        _buildBadge(
                          icon: Icons.warning_amber,
                          text: 'Non valido',
                          color: kErrorColor,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Delete button (only for custom circuits)
            if (onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kErrorColor.withAlpha(15),
                    border: Border.all(
                      color: kErrorColor.withAlpha(60),
                    ),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: kErrorColor,
                    size: 18,
                  ),
                ),
              ),
            // Arrow
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasError ? kErrorColor.withAlpha(15) : Colors.white.withAlpha(6),
                border: Border.all(
                  color: hasError ? kErrorColor.withAlpha(50) : _kBorderColor,
                ),
              ),
              child: Icon(
                hasError ? Icons.block : Icons.chevron_right,
                color: hasError ? kErrorColor : kMutedColor,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withAlpha(15),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
