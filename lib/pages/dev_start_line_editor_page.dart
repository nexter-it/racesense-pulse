// ═══════════════════════════════════════════════════════════════════════════
// DEV TOOL: Editor temporaneo per modificare le coordinate della linea di start
// dei circuiti ufficiali. DISATTIVABILE con il flag kEnableStartLineEditor.
//
// COME USARE:
// 1. Imposta kEnableStartLineEditor = true
// 2. Accedi dalla pagina circuiti ufficiali (icona rossa)
// 3. Seleziona un circuito dalla lista
// 4. Modifica le coordinate con i pulsanti +/- o inserimento manuale
// 5. Copia il JSON aggiornato dalla console
// 6. Aggiorna il file assets/data/start_lines_italia.json
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/official_circuit_info.dart';
import '../services/official_circuits_service.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FLAG PER ABILITARE/DISABILITARE L'EDITOR
// ═══════════════════════════════════════════════════════════════════════════
const bool kEnableStartLineEditor = true; // Imposta a false per disabilitare

// ═══════════════════════════════════════════════════════════════════════════
// UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);
const Color _kPoint1Color = Color(0xFF4CAF50); // Verde per punto 1
const Color _kPoint2Color = Color(0xFFE91E63); // Rosa per punto 2
const Color _kLineColor = Color(0xFFFFEB3B); // Giallo per la linea

/// Cache globale per le modifiche ai circuiti (persiste durante la sessione)
final Map<String, Map<String, dynamic>> _globalCircuitChanges = {};

/// Genera l'intero file JSON con tutte le modifiche applicate
/// e lo stampa in console per copiarlo
Future<String> _generateFullJsonWithChanges(Map<String, dynamic> updatedCircuit) async {
  try {
    // Salva nella cache globale
    final fileId = updatedCircuit['file'] as String;
    _globalCircuitChanges[fileId] = updatedCircuit;

    // Carica tutti i circuiti dall'asset
    final jsonString =
        await rootBundle.loadString('assets/data/start_lines_italia.json');
    final circuits = json.decode(jsonString) as List<dynamic>;

    // Applica tutte le modifiche dalla cache
    for (int i = 0; i < circuits.length; i++) {
      final circuit = circuits[i] as Map<String, dynamic>;
      final circuitFileId = circuit['file'] as String;
      if (_globalCircuitChanges.containsKey(circuitFileId)) {
        circuits[i] = _globalCircuitChanges[circuitFileId];
      }
    }

    // Genera JSON formattato
    final encoder = const JsonEncoder.withIndent('  ');
    return encoder.convert(circuits);
  } catch (e) {
    debugPrint('❌ Errore durante la generazione: $e');
    return '';
  }
}

/// Pagina lista circuiti per selezionare quale modificare
class DevStartLineEditorPage extends StatefulWidget {
  const DevStartLineEditorPage({super.key});

  @override
  State<DevStartLineEditorPage> createState() => _DevStartLineEditorPageState();
}

class _DevStartLineEditorPageState extends State<DevStartLineEditorPage> {
  final OfficialCircuitsService _service = OfficialCircuitsService();
  final TextEditingController _searchController = TextEditingController();

  List<OfficialCircuitInfo> _circuits = [];
  List<OfficialCircuitInfo> _filteredCircuits = [];
  bool _loading = true;

  // Mappa delle modifiche salvate
  final Map<String, Map<String, dynamic>> _savedChanges = {};

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
    final circuits = await _service.loadCircuits();
    if (mounted) {
      setState(() {
        _circuits = circuits;
        _filteredCircuits = circuits;
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
            c.city.toLowerCase().contains(q);
      }).toList();
    });
  }

  void _openEditor(OfficialCircuitInfo circuit) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _CircuitEditorPage(
          circuit: circuit,
          existingChanges: _savedChanges[circuit.file],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _savedChanges[circuit.file] = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modifiche salvate per ${circuit.name}'),
          backgroundColor: kBrandColor,
        ),
      );
    }
  }

  void _exportAllChanges() {
    if (_savedChanges.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nessuna modifica da esportare'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final jsonList = _savedChanges.values.toList();
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
    Clipboard.setData(ClipboardData(text: jsonString));

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('ESPORTAZIONE TUTTE LE MODIFICHE (${_savedChanges.length} circuiti)');
    debugPrint(jsonString);
    debugPrint('═══════════════════════════════════════════════════════════');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_savedChanges.length} circuiti esportati - Vedi console'),
        backgroundColor: kBrandColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        title: const Text(
          'DEV: Start Line Editor',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.red,
          ),
        ),
        actions: [
          if (_savedChanges.isNotEmpty)
            TextButton.icon(
              onPressed: _exportAllChanges,
              icon: Badge(
                label: Text('${_savedChanges.length}'),
                child: const Icon(Icons.upload_file, color: kBrandColor),
              ),
              label: const Text('Esporta', style: TextStyle(color: kBrandColor)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrandColor))
          : Column(
              children: [
                // Ricerca
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: kFgColor),
                    decoration: InputDecoration(
                      hintText: 'Cerca circuito...',
                      hintStyle: TextStyle(color: kMutedColor),
                      prefixIcon: Icon(Icons.search, color: kMutedColor),
                      filled: true,
                      fillColor: _kCardStart,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _filterCircuits,
                  ),
                ),
                // Lista
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredCircuits.length,
                    itemBuilder: (context, index) {
                      final circuit = _filteredCircuits[index];
                      final hasChanges = _savedChanges.containsKey(circuit.file);

                      return GestureDetector(
                        onTap: () => _openEditor(circuit),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_kCardStart, _kCardEnd],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: hasChanges ? Colors.orange : _kBorderColor,
                              width: hasChanges ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (hasChanges)
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.orange,
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      circuit.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: kFgColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      circuit.city,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: kMutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_location_alt,
                                color: hasChanges ? Colors.orange : kMutedColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// Pagina editor per un singolo circuito
class _CircuitEditorPage extends StatefulWidget {
  final OfficialCircuitInfo circuit;
  final Map<String, dynamic>? existingChanges;

  const _CircuitEditorPage({
    required this.circuit,
    this.existingChanges,
  });

  @override
  State<_CircuitEditorPage> createState() => _CircuitEditorPageState();
}

class _CircuitEditorPageState extends State<_CircuitEditorPage> {
  final MapController _mapController = MapController();

  late LatLng _point1;
  late LatLng _point2;
  bool _hasChanges = false;

  // Quale punto stiamo editando (1 o 2)
  int _editingPoint = 1;

  // Incremento per le coordinate (in gradi)
  double _increment = 0.00001; // ~1 metro

  @override
  void initState() {
    super.initState();

    // Carica da modifiche esistenti o da circuito originale
    if (widget.existingChanges != null) {
      final sl = widget.existingChanges!['start_line'] as Map<String, dynamic>;
      final p1 = sl['point1'] as Map<String, dynamic>;
      final p2 = sl['point2'] as Map<String, dynamic>;
      _point1 = LatLng(p1['lat'] as double, p1['lon'] as double);
      _point2 = LatLng(p2['lat'] as double, p2['lon'] as double);
    } else {
      _point1 = widget.circuit.finishLineStart;
      _point2 = widget.circuit.finishLineEnd;
    }
  }

  LatLng get _center => LatLng(
        (_point1.latitude + _point2.latitude) / 2,
        (_point1.longitude + _point2.longitude) / 2,
      );

  double get _trackWidth {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, _point1, _point2);
  }

  double get _lineDirection {
    final dLat = _point2.latitude - _point1.latitude;
    final dLon = _point2.longitude - _point1.longitude;
    var angle = atan2(dLon, dLat) * 180 / pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  double get _trackDirection {
    var dir = _lineDirection + 90;
    if (dir >= 360) dir -= 360;
    return dir;
  }

  void _movePoint(double dLat, double dLon) {
    setState(() {
      if (_editingPoint == 1) {
        _point1 = LatLng(_point1.latitude + dLat, _point1.longitude + dLon);
      } else {
        _point2 = LatLng(_point2.latitude + dLat, _point2.longitude + dLon);
      }
      _hasChanges = true;
    });
  }

  Map<String, dynamic> _generateJson() {
    return {
      'file': widget.circuit.file,
      'name': widget.circuit.name,
      'city': widget.circuit.city,
      'country': widget.circuit.country,
      'start_line': {
        'center': {
          'lat': double.parse(_center.latitude.toStringAsFixed(7)),
          'lon': double.parse(_center.longitude.toStringAsFixed(7)),
        },
        'point1': {
          'lat': double.parse(_point1.latitude.toStringAsFixed(7)),
          'lon': double.parse(_point1.longitude.toStringAsFixed(7)),
        },
        'point2': {
          'lat': double.parse(_point2.latitude.toStringAsFixed(7)),
          'lon': double.parse(_point2.longitude.toStringAsFixed(7)),
        },
        'track_direction_deg': double.parse(_trackDirection.toStringAsFixed(2)),
        'line_direction_deg': double.parse(_lineDirection.toStringAsFixed(2)),
        'track_width_m': double.parse(_trackWidth.toStringAsFixed(1)),
        'width_estimated': false,
      },
    };
  }

  Future<void> _save() async {
    final circuitJson = _generateJson();

    // Genera il file JSON completo con tutte le modifiche
    final fullJson = await _generateFullJsonWithChanges(circuitJson);

    if (fullJson.isNotEmpty) {
      // Copia l'intero file JSON negli appunti
      Clipboard.setData(ClipboardData(text: fullJson));

      // Stampa in console con istruzioni
      debugPrint('');
      debugPrint('╔═══════════════════════════════════════════════════════════════╗');
      debugPrint('║  FILE JSON COMPLETO COPIATO NEGLI APPUNTI!                    ║');
      debugPrint('║  Modifiche applicate: ${_globalCircuitChanges.length} circuito/i                          ║');
      debugPrint('╠═══════════════════════════════════════════════════════════════╣');
      debugPrint('║  ISTRUZIONI:                                                  ║');
      debugPrint('║  1. Apri: assets/data/start_lines_italia.json                 ║');
      debugPrint('║  2. Seleziona tutto (Cmd+A)                                   ║');
      debugPrint('║  3. Incolla (Cmd+V)                                           ║');
      debugPrint('║  4. Salva il file                                             ║');
      debugPrint('╚═══════════════════════════════════════════════════════════════╝');
      debugPrint('');

      // Pulisci la cache del service
      OfficialCircuitsService().clearCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'JSON completo copiato! (${_globalCircuitChanges.length} modifiche)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore nella generazione del JSON'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      Navigator.of(context).pop(circuitJson);
    }
  }

  void _centerMap() {
    _mapController.move(_center, 19);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        title: Text(
          widget.circuit.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: kFgColor,
          ),
        ),
        actions: [
          if (_hasChanges)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: Colors.green),
              label: const Text('Salva', style: TextStyle(color: Colors.green)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Mappa
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 19,
                    maxZoom: 22,
                    minZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                      userAgentPackageName: 'com.racesense.pulse',
                    ),
                    // Linea
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [_point1, _point2],
                          color: _kLineColor,
                          strokeWidth: 5,
                        ),
                      ],
                    ),
                    // Markers
                    MarkerLayer(
                      markers: [
                        // Punto 1
                        Marker(
                          point: _point1,
                          width: 50,
                          height: 50,
                          child: GestureDetector(
                            onTap: () => setState(() => _editingPoint = 1),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _kPoint1Color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _editingPoint == 1 ? Colors.white : Colors.white54,
                                  width: _editingPoint == 1 ? 4 : 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(100),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  '1',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Punto 2
                        Marker(
                          point: _point2,
                          width: 50,
                          height: 50,
                          child: GestureDetector(
                            onTap: () => setState(() => _editingPoint = 2),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _kPoint2Color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _editingPoint == 2 ? Colors.white : Colors.white54,
                                  width: _editingPoint == 2 ? 4 : 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(100),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  '2',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Centro
                        Marker(
                          point: _center,
                          width: 20,
                          height: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: _kLineColor, width: 3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Pulsante centra mappa
                Positioned(
                  right: 16,
                  top: 16,
                  child: FloatingActionButton.small(
                    onPressed: _centerMap,
                    backgroundColor: _kCardStart,
                    child: const Icon(Icons.center_focus_strong, color: kFgColor),
                  ),
                ),
              ],
            ),
          ),

          // Pannello controlli
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kCardStart, _kCardEnd]),
              border: Border(top: BorderSide(color: _kBorderColor)),
            ),
            child: Column(
              children: [
                // Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoChip('Larghezza', '${_trackWidth.toStringAsFixed(1)}m'),
                    _buildInfoChip('Dir. pista', '${_trackDirection.toStringAsFixed(0)}°'),
                  ],
                ),
                const SizedBox(height: 16),

                // Selezione punto
                Row(
                  children: [
                    const Text('Editing:', style: TextStyle(color: kFgColor)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _editingPoint = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _editingPoint == 1 ? _kPoint1Color : _kPoint1Color.withAlpha(40),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kPoint1Color, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    'PUNTO 1',
                                    style: TextStyle(
                                      color: _editingPoint == 1 ? Colors.white : _kPoint1Color,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _editingPoint = 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _editingPoint == 2 ? _kPoint2Color : _kPoint2Color.withAlpha(40),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kPoint2Color, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    'PUNTO 2',
                                    style: TextStyle(
                                      color: _editingPoint == 2 ? Colors.white : _kPoint2Color,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Incremento
                Row(
                  children: [
                    const Text('Passo:', style: TextStyle(color: kFgColor)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildIncrementChip('1m', 0.00001),
                            const SizedBox(width: 8),
                            _buildIncrementChip('5m', 0.00005),
                            const SizedBox(width: 8),
                            _buildIncrementChip('10m', 0.0001),
                            const SizedBox(width: 8),
                            _buildIncrementChip('50m', 0.0005),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Controlli direzionali
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Nord
                    Column(
                      children: [
                        _buildDirectionButton(Icons.arrow_upward, () => _movePoint(_increment, 0)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildDirectionButton(Icons.arrow_back, () => _movePoint(0, -_increment)),
                            const SizedBox(width: 8),
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _editingPoint == 1 ? _kPoint1Color : _kPoint2Color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '$_editingPoint',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildDirectionButton(Icons.arrow_forward, () => _movePoint(0, _increment)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildDirectionButton(Icons.arrow_downward, () => _movePoint(-_increment, 0)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Coordinate correnti
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _buildCoordRow('P1', _point1, _kPoint1Color),
                      const SizedBox(height: 4),
                      _buildCoordRow('P2', _point2, _kPoint2Color),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: kMutedColor, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: kFgColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildIncrementChip(String label, double value) {
    final isSelected = _increment == value;
    return GestureDetector(
      onTap: () => setState(() => _increment = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kBrandColor : kBrandColor.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBrandColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : kBrandColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: _kCardStart,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderColor),
          ),
          child: Icon(icon, color: kFgColor, size: 28),
        ),
      ),
    );
  }

  Widget _buildCoordRow(String label, LatLng point, Color color) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${point.latitude.toStringAsFixed(7)}, ${point.longitude.toStringAsFixed(7)}',
            style: const TextStyle(
              color: kFgColor,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
