import 'package:flutter/material.dart';

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
        withTopPadding: true,
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Circuiti Custom',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadCircuits,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(kBrandColor),
                      ),
                    )
                  : _circuits.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.route, size: 40, color: kMutedColor),
                                SizedBox(height: 10),
                                Text(
                                  'Nessun circuito custom salvato',
                                  style:
                                      TextStyle(color: kMutedColor, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: _circuits.length,
                          itemBuilder: (context, i) {
                            final c = _circuits[i];
                            return InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CustomCircuitDetailPage(circuit: c),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: const Color(0xFF0F1016),
                                  border: Border.all(color: kLineColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.track_changes,
                                            color: kBrandColor, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            c.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${c.lengthMeters.toStringAsFixed(0)} m',
                                          style: const TextStyle(
                                              color: kMutedColor, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${c.city} ${c.country}'.trim(),
                                      style: const TextStyle(
                                        color: kMutedColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _pill(
                                            'Larghezza ${c.widthMeters.toStringAsFixed(1)} m'),
                                        const SizedBox(width: 8),
                                        _pill(
                                            'Punti ${c.points.length.toString()}'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
              child: Column(
                children: [
                  SizedBox(
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
                      icon: const Icon(Icons.alt_route_outlined),
                      label: const Text('Traccia circuito custom'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color.fromRGBO(255, 255, 255, 0.05),
        border: Border.all(color: kLineColor.withOpacity(0.6)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: kMutedColor, fontSize: 11),
      ),
    );
  }
}
