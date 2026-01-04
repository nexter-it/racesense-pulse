import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/custom_circuit_service.dart';
import '../theme.dart';
import 'custom_circuit_builder_page.dart';
import 'custom_circuit_detail_page.dart';

class CustomCircuitsPage extends StatefulWidget {
  const CustomCircuitsPage({super.key});

  @override
  State<CustomCircuitsPage> createState() => _CustomCircuitsPageState();
}

class _CustomCircuitsPageState extends State<CustomCircuitsPage> {
  final CustomCircuitService _service = CustomCircuitService();
  bool _loading = true;
  List<CustomCircuitInfo> _circuits = [];

  @override
  void initState() {
    super.initState();
    _loadCircuits();
  }

  Future<void> _loadCircuits() async {
    setState(() => _loading = true);
    final list = await _service.listCircuits();
    if (mounted) {
      setState(() {
        _circuits = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? _buildLoadingState()
                  : _circuits.isEmpty
                      ? _buildEmptyState()
                      : _buildCircuitsList(),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0A0A0A),
            const Color(0xFF121212),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
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
                  'I Miei Circuiti',
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kBrandColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kBrandColor.withAlpha(60)),
                      ),
                      child: Text(
                        _loading
                            ? '...'
                            : '${_circuits.length} ${_circuits.length == 1 ? 'tracciato' : 'tracciati'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: kBrandColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Refresh button
          Container(
            decoration: BoxDecoration(
              color: kBrandColor.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBrandColor.withAlpha(40)),
            ),
            child: IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                color: kBrandColor,
                size: 22,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                _loadCircuits();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(kBrandColor),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Caricamento circuiti...',
            style: TextStyle(
              color: kMutedColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon container
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kBrandColor.withAlpha(30),
                    kBrandColor.withAlpha(10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: kBrandColor.withAlpha(80), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandColor.withAlpha(40),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add_road_rounded,
                  size: 40,
                  color: kBrandColor,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Nessun circuito salvato',
              style: TextStyle(
                color: kFgColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Crea il tuo primo circuito personalizzato\ntracciando il percorso con il GPS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kMutedColor,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
            // Quick start hint
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF151515),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kBrandColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.touch_app, color: kBrandColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Premi il pulsante in basso',
                        style: TextStyle(
                          color: kFgColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'per iniziare a tracciare',
                        style: TextStyle(
                          color: kMutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircuitsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _circuits.length,
      itemBuilder: (context, i) {
        final c = _circuits[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < _circuits.length - 1 ? 16 : 0),
          child: _buildCircuitCard(c, i),
        );
      },
    );
  }

  Widget _buildCircuitCard(CustomCircuitInfo circuit, int index) {
    final formattedDate = DateFormat('dd MMM yyyy').format(circuit.createdAt);
    final formattedTime = DateFormat('HH:mm').format(circuit.createdAt);

    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomCircuitDetailPage(
              circuit: circuit,
              trackId: circuit.trackId,
              onCircuitUpdated: (updatedCircuit) {
                setState(() {
                  final idx = _circuits.indexWhere((c) => c.trackId == circuit.trackId);
                  if (idx != -1) {
                    _circuits[idx] = updatedCircuit;
                  }
                });
              },
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A1A),
              const Color(0xFF141414),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFF2A2A2A)),
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
                      // Circuit icon with number
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
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
                          child: Icon(
                            Icons.route_rounded,
                            color: kBrandColor,
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
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: kFgColor,
                                      letterSpacing: -0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (circuit.usedBleDevice) ...[
                                  const SizedBox(width: 10),
                                  _buildBleChip(),
                                ],
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
                                    '${circuit.city} ${circuit.country}'.trim().isEmpty
                                        ? 'Posizione non specificata'
                                        : '${circuit.city}, ${circuit.country}'.trim(),
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
                  const SizedBox(height: 14),
                  // Info linea S/F
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kBrandColor.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBrandColor.withAlpha(40)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, color: kBrandColor, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Linea Start/Finish configurata',
                                style: TextStyle(
                                  color: kBrandColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Pronto per le sessioni',
                                style: TextStyle(
                                  color: kBrandColor.withAlpha(180),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.check_circle, color: kBrandColor, size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Footer with date
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(4),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(
                  top: BorderSide(color: const Color(0xFF2A2A2A)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: kMutedColor, size: 13),
                  const SizedBox(width: 6),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kMutedColor.withAlpha(100),
                    ),
                  ),
                  Icon(Icons.access_time_rounded, color: kMutedColor, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      color: kMutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Visualizza',
                    style: TextStyle(
                      color: kBrandColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: kBrandColor, size: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBleChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C4DFF).withAlpha(30),
            const Color(0xFF7C4DFF).withAlpha(15),
          ],
        ),
        border: Border.all(color: const Color(0xFF7C4DFF).withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth, color: const Color(0xFF7C4DFF), size: 12),
          const SizedBox(width: 4),
          Text(
            'GPS Pro',
            style: TextStyle(
              color: const Color(0xFF7C4DFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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

  Widget _buildFAB() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomCircuitBuilderPage(),
          ),
        );
        _loadCircuits();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1E1E1E),
          border: Border.all(
            color: Colors.white.withAlpha(25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kBrandColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.add_location_alt_rounded,
                color: kBrandColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'Nuovo Tracciato',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
