import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/official_circuit_info.dart';
import '../models/track_definition.dart';
import '../services/official_circuits_service.dart';
import '../theme.dart';
import 'official_circuit_detail_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kOfficialColor = Color(0xFF29B6F6); // Blu per circuiti ufficiali

/// Pagina che mostra la lista dei circuiti ufficiali caricati dal JSON.
/// Può essere usata in due modalità:
/// - Visualizzazione: mostra dettagli del circuito
/// - Selezione: ritorna un TrackDefinition quando l'utente seleziona
class OfficialCircuitsPage extends StatefulWidget {
  /// Se true, la pagina è in modalità selezione e ritorna un TrackDefinition
  final bool selectionMode;

  const OfficialCircuitsPage({
    super.key,
    this.selectionMode = false,
  });

  @override
  State<OfficialCircuitsPage> createState() => _OfficialCircuitsPageState();
}

class _OfficialCircuitsPageState extends State<OfficialCircuitsPage> {
  final OfficialCircuitsService _service = OfficialCircuitsService();
  bool _loading = true;
  List<OfficialCircuitInfo> _circuits = [];
  List<OfficialCircuitInfo> _filteredCircuits = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCircuits();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCircuits() async {
    setState(() => _loading = true);
    final list = await _service.loadCircuits();
    if (mounted) {
      setState(() {
        _circuits = list;
        _filteredCircuits = list;
        _loading = false;
      });
    }
  }

  void _filterCircuits(String query) {
    if (query.isEmpty) {
      setState(() => _filteredCircuits = _circuits);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredCircuits = _circuits.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.city.toLowerCase().contains(q) ||
            c.country.toLowerCase().contains(q);
      }).toList();
    });
  }

  void _onCircuitTap(OfficialCircuitInfo circuit) async {
    HapticFeedback.lightImpact();

    if (widget.selectionMode) {
      // Modalità selezione: vai alla pagina dettaglio che può ritornare TrackDefinition
      final result = await Navigator.of(context).push<TrackDefinition>(
        MaterialPageRoute(
          builder: (_) => OfficialCircuitDetailPage(
            circuit: circuit,
            selectionMode: true,
          ),
        ),
      );
      if (result != null && mounted) {
        Navigator.of(context).pop(result);
      }
    } else {
      // Modalità visualizzazione: mostra solo i dettagli
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OfficialCircuitDetailPage(
            circuit: circuit,
            selectionMode: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: _loading
                  ? _buildLoadingState()
                  : _filteredCircuits.isEmpty
                      ? _buildEmptyState()
                      : _buildCircuitsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: kFgColor, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          // Title and count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Circuiti Ufficiali',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: kFgColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kOfficialColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kOfficialColor.withAlpha(60)),
                      ),
                      child: Text(
                        _loading
                            ? '...'
                            : '${_circuits.length} ${_circuits.length == 1 ? 'circuito' : 'circuiti'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _kOfficialColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.selectionMode) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kBrandColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kBrandColor.withAlpha(60)),
                        ),
                        child: Text(
                          'SELEZIONA',
                          style: TextStyle(
                            fontSize: 9,
                            color: kBrandColor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Info icon
          Container(
            decoration: BoxDecoration(
              color: _kOfficialColor.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kOfficialColor.withAlpha(40)),
            ),
            child: IconButton(
              icon: Icon(
                Icons.verified_rounded,
                color: _kOfficialColor,
                size: 22,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                _showInfoDialog();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderColor),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterCircuits,
          style: const TextStyle(color: kFgColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Cerca circuito...',
            hintStyle: TextStyle(color: kMutedColor, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: kMutedColor, size: 20),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: kMutedColor, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _filterCircuits('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_kOfficialColor),
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          Text(
            'Caricamento circuiti...',
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

  Widget _buildEmptyState() {
    final isSearching = _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kOfficialColor.withAlpha(30),
                    _kOfficialColor.withAlpha(10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: _kOfficialColor.withAlpha(80), width: 2),
                ),
                child: Icon(
                  isSearching ? Icons.search_off : Icons.public_off,
                  size: 36,
                  color: _kOfficialColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearching ? 'Nessun risultato' : 'Nessun circuito disponibile',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kFgColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Prova a cercare con un altro termine'
                  : 'I circuiti ufficiali non sono stati caricati',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: kMutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircuitsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _filteredCircuits.length,
      itemBuilder: (context, i) {
        final c = _filteredCircuits[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < _filteredCircuits.length - 1 ? 14 : 0),
          child: _buildCircuitCard(c),
        );
      },
    );
  }

  Widget _buildCircuitCard(OfficialCircuitInfo circuit) {
    final lengthKm = circuit.lengthKm.toStringAsFixed(2);

    return GestureDetector(
      onTap: () => _onCircuitTap(circuit),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [_kCardStart, _kCardEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _kBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  // Header row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Circuit icon
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              _kOfficialColor.withAlpha(40),
                              _kOfficialColor.withAlpha(20),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border:
                              Border.all(color: _kOfficialColor.withAlpha(60), width: 1.5),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.stadium_rounded,
                            color: _kOfficialColor,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Name and location
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    circuit.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: kFgColor,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    color: kMutedColor, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    circuit.location,
                                    style: TextStyle(
                                      color: kMutedColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Arrow
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: kMutedColor,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    children: [
                      _buildStatChip(
                        icon: Icons.straighten_rounded,
                        value: '$lengthKm km',
                        color: const Color(0xFF00E676),
                      ),
                      const SizedBox(width: 10),
                      if (circuit.category != null)
                        _buildStatChip(
                          icon: Icons.emoji_events_rounded,
                          value: circuit.category!,
                          color: const Color(0xFFFFB74D),
                        ),
                      if (circuit.category != null) const SizedBox(width: 10),
                      _buildOfficialBadge(),
                    ],
                  ),
                ],
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(4),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: const Border(
                  top: BorderSide(color: _kBorderColor),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_circle_rounded, color: _kOfficialColor, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Linea S/F verificata',
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.selectionMode ? 'Seleziona' : 'Visualizza',
                    style: TextStyle(
                      color: widget.selectionMode ? kBrandColor : _kOfficialColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: widget.selectionMode ? kBrandColor : _kOfficialColor,
                    size: 14,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withAlpha(12),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfficialBadge() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _kOfficialColor.withAlpha(12),
          border: Border.all(color: _kOfficialColor.withAlpha(40)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_rounded, color: _kOfficialColor, size: 15),
            const SizedBox(width: 6),
            Text(
              'Ufficiale',
              style: TextStyle(
                color: _kOfficialColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kCardStart, _kCardEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kOfficialColor.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.verified_rounded, color: _kOfficialColor, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Circuiti Ufficiali',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Questi circuiti hanno la linea di Start/Finish verificata e pronta all\'uso per il conteggio automatico dei giri.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kMutedColor,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOfficialColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Capito',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
