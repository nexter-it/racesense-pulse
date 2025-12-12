import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/custom_circuit_service.dart';
import '../theme.dart';
import '../widgets/pulse_background.dart';
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
      body: PulseBackground(
        withTopPadding: false,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(kBrandColor),
                        ),
                      )
                    : _circuits.isEmpty
                        ? _buildEmptyState()
                        : _buildCircuitsList(),
              ),
              _buildBottomButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kLineColor, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: kFgColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
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
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _circuits.isEmpty
                      ? 'Nessun circuito salvato'
                      : '${_circuits.length} ${_circuits.length == 1 ? 'circuito' : 'circuiti'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: kBrandColor),
            onPressed: _loadCircuits,
            tooltip: 'Ricarica',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(100), width: 2),
              ),
              child: const Icon(
                Icons.route,
                size: 48,
                color: kBrandColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nessun circuito salvato',
              style: TextStyle(
                color: kFgColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Inizia a tracciare il tuo primo circuito custom.\nPotrai usarlo per le tue sessioni live!',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMutedColor, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircuitsList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _circuits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final c = _circuits[i];
        return _buildCircuitCard(c);
      },
    );
  }

  Widget _buildCircuitCard(CustomCircuitInfo circuit) {
    final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(circuit.createdAt);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomCircuitDetailPage(circuit: circuit),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [
              Color.fromRGBO(255, 255, 255, 0.08),
              Color.fromRGBO(255, 255, 255, 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kLineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon and name
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kBrandColor.withAlpha(40),
                    border: Border.all(color: kBrandColor, width: 1.5),
                  ),
                  child: const Icon(Icons.track_changes, color: kBrandColor, size: 20),
                ),
                const SizedBox(width: 12),
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
                                fontWeight: FontWeight.w900,
                                color: kFgColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (circuit.usedBleDevice) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: kBrandColor.withAlpha(30),
                                border: Border.all(color: kBrandColor, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.bluetooth_connected, color: kBrandColor, size: 10),
                                  SizedBox(width: 3),
                                  Text(
                                    'BLE',
                                    style: TextStyle(
                                      color: kBrandColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: kMutedColor, size: 12),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${circuit.city} ${circuit.country}'.trim().isEmpty
                                  ? 'Posizione sconosciuta'
                                  : '${circuit.city} ${circuit.country}'.trim(),
                              style: const TextStyle(
                                color: kMutedColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: kMutedColor, size: 20),
              ],
            ),
            const SizedBox(height: 14),
            // Stats row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color.fromRGBO(255, 255, 255, 0.03),
                border: Border.all(color: kLineColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(
                    icon: Icons.straighten,
                    label: 'Lunghezza',
                    value: '${circuit.lengthMeters.toStringAsFixed(0)} m',
                  ),
                  Container(width: 1, height: 30, color: kLineColor),
                  _buildStat(
                    icon: Icons.width_normal,
                    label: 'Larghezza',
                    value: '${circuit.widthMeters.toStringAsFixed(1)} m',
                  ),
                  Container(width: 1, height: 30, color: kLineColor),
                  _buildStat(
                    icon: Icons.gps_fixed,
                    label: 'Punti',
                    value: circuit.points.length.toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Date
            Row(
              children: [
                const Icon(Icons.access_time, color: kMutedColor, size: 12),
                const SizedBox(width: 6),
                Text(
                  'Creato il $formattedDate',
                  style: const TextStyle(
                    color: kMutedColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kBrandColor, size: 16),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: kMutedColor,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: kFgColor,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: kLineColor)),
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            kBgColor.withAlpha(250),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomCircuitBuilderPage(),
                ),
              );
              _loadCircuits();
            },
            icon: const Icon(Icons.add_location_alt, size: 20),
            label: const Text(
              'Traccia nuovo circuito',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: kBrandColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }
}
