import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';


import '../theme.dart';
import '../widgets/pulse_background.dart';

class SessionRecapPage extends StatelessWidget {
  final List<Position> gpsTrack;
  final List<LatLng> smoothPath;
  final List<Duration> laps;
  final Duration totalDuration;
  final Duration? bestLap;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;

  const SessionRecapPage({
    super.key,
    required this.gpsTrack,
    required this.smoothPath,
    required this.laps,
    required this.totalDuration,
    this.bestLap,
    required this.speedHistory,
    required this.gForceHistory,
    required this.gpsAccuracyHistory,
    required this.timeHistory,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  double _calculateDistance() {
    if (gpsTrack.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < gpsTrack.length; i++) {
      final prev = gpsTrack[i - 1];
      final curr = gpsTrack[i];

      final dLat = (curr.latitude - prev.latitude) * math.pi / 180.0;
      final dLon = (curr.longitude - prev.longitude) * math.pi / 180.0;

      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(prev.latitude * math.pi / 180.0) *
              math.cos(curr.latitude * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);

      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      totalDistance += 6371000 * c; // Raggio Terra in metri
    }

    return totalDistance / 1000; // Converti in km
  }

  double _getMaxSpeed() {
    if (speedHistory.isEmpty) return 0;
    return speedHistory.reduce(math.max);
  }

  double _getAvgSpeed() {
    if (speedHistory.isEmpty) return 0;
    return speedHistory.reduce((a, b) => a + b) / speedHistory.length;
  }

  double _getMaxGForce() {
    if (gForceHistory.isEmpty) return 0;
    return gForceHistory.reduce(math.max);
  }

  double _getAvgGpsAccuracy() {
    if (gpsAccuracyHistory.isEmpty) return 0;
    return gpsAccuracyHistory.reduce((a, b) => a + b) / gpsAccuracyHistory.length;
  }

  int _getGpsSampleRate() {
    if (timeHistory.length < 2) return 0;

    int totalIntervals = 0;
    int sumMs = 0;

    for (int i = 1; i < timeHistory.length; i++) {
      final diff = timeHistory[i].inMilliseconds - timeHistory[i - 1].inMilliseconds;
      if (diff > 0 && diff < 5000) { // Ignora outlier (> 5 sec)
        sumMs += diff;
        totalIntervals++;
      }
    }

    if (totalIntervals == 0) return 0;
    final avgMs = sumMs / totalIntervals;
    return (1000 / avgMs).round(); // Hz
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PulseBackground(
        withTopPadding: true,
        child: Column(
          children: [
            // Header
            _buildHeader(context),

            // Contenuto scrollabile
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                    // Pannello circuito + grafico combinato
                    _SessionOverviewPanel(
                      gpsTrack: gpsTrack,
                      smoothPath: smoothPath,
                      speedHistory: speedHistory,
                      gForceHistory: gForceHistory,
                      gpsAccuracyHistory: gpsAccuracyHistory,
                      timeHistory: timeHistory,
                      laps: laps, // ⬅️ AGGIUNTO
                    ),

                    const SizedBox(height: 24),

                    // Statistiche principali (box che avevi già)
                    _buildMainStats(),

                    const SizedBox(height: 24),

                    // Dati tecnici
                    _buildTechnicalData(),

                    const SizedBox(height: 24),

                    // Lista giri dettagliata
                    _buildLapList(),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 28),
          ),
          const SizedBox(width: 8),
          const Text(
            'SESSIONE',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sessione salvata!'),
                  backgroundColor: kBrandColor,
                ),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Salva'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kBrandColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

    Widget _buildMainStats() {
    final distance = _calculateDistance();
    final maxSpeed = _getMaxSpeed();
    final avgSpeed = _getAvgSpeed();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STATISTICHE PRINCIPALI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: kMutedColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _buildStatCard(
              'Tempo Totale',
              _formatDuration(totalDuration),
              Icons.timer,
            ),
            _buildStatCard(
              'Best Lap',
              bestLap != null ? _formatDuration(bestLap!) : '--:--',
              Icons.flash_on,
            ),
            _buildStatCard(
              'Giri',
              '${laps.length}',
              Icons.replay,
            ),
            _buildStatCard(
              'Distanza',
              '${distance.toStringAsFixed(2)} km',
              Icons.straighten,
            ),
            _buildStatCard(
              'Vel. Max',
              '${maxSpeed.toStringAsFixed(0)} km/h',
              Icons.speed,
            ),
            _buildStatCard(
              'Vel. Media',
              '${avgSpeed.toStringAsFixed(0)} km/h',
              Icons.trending_up,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1a1a1a),
            const Color(0xFF121212),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: kBrandColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: kMutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: kFgColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalData() {
    final maxGForce = _getMaxGForce();
    final avgGpsAccuracy = _getAvgGpsAccuracy();
    final gpsSampleRate = _getGpsSampleRate();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DATI TECNICI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: kMutedColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1a1a1a),
                const Color(0xFF121212),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLineColor),
          ),
          child: Column(
            children: [
              _buildTechRow('Punti GPS raccolti', '${gpsTrack.length}', Icons.location_on),
              const Divider(color: kLineColor, height: 24),
              _buildTechRow('Frequenza GPS media', '$gpsSampleRate Hz', Icons.settings_input_antenna),
              const Divider(color: kLineColor, height: 24),
              _buildTechRow('Precisione GPS media', '${avgGpsAccuracy.toStringAsFixed(1)} m', Icons.gps_fixed),
              const Divider(color: kLineColor, height: 24),
              _buildTechRow('G-Force massima', '${maxGForce.toStringAsFixed(2)} g', Icons.speed),
              const Divider(color: kLineColor, height: 24),
              _buildTechRow('Campioni velocità', '${speedHistory.length}', Icons.data_usage),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTechRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: kBrandColor.withOpacity(0.7), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: kMutedColor,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: kFgColor,
          ),
        ),
      ],
    );
  }

  Widget _buildLapList() {
    if (laps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TEMPI GIRI DETTAGLIATI',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: kMutedColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),

        ...laps.asMap().entries.map((entry) {
          final index = entry.key;
          final lap = entry.value;
          final isBest = bestLap != null && lap == bestLap;

          // Calcola differenza con best lap
          String delta = '--';
          if (bestLap != null && lap != bestLap) {
            final diff = lap.inMilliseconds - bestLap!.inMilliseconds;
            delta = '+${(diff / 1000).toStringAsFixed(3)}';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: isBest
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kBrandColor.withOpacity(0.15),
                        kBrandColor.withOpacity(0.05),
                      ],
                    )
                  : null,
              color: isBest ? null : const Color(0xFF1a1a1a),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isBest ? kBrandColor : kLineColor,
                width: isBest ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isBest ? kBrandColor : kLineColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isBest ? Colors.black : kFgColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Giro ${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isBest ? kBrandColor : kFgColor,
                              fontSize: 14,
                            ),
                          ),
                          if (isBest) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kBrandColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'BEST',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!isBest) ...[
                        const SizedBox(height: 2),
                        Text(
                          delta,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kErrorColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _formatDuration(lap),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isBest ? kBrandColor : kFgColor,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

// ============================================================
// OVERVIEW: CIRCUITO + GRAFICO COMBINATO (stile RaceBox)
// ============================================================

enum _MetricFocus { speed, gForce, accuracy }

class _SessionOverviewPanel extends StatefulWidget {
  final List<Position> gpsTrack;
  final List<LatLng> smoothPath;
  final List<double> speedHistory;
  final List<double> gForceHistory;
  final List<double> gpsAccuracyHistory;
  final List<Duration> timeHistory;
  final List<Duration> laps;

  const _SessionOverviewPanel({
    required this.gpsTrack,
    required this.smoothPath,
    required this.speedHistory,
    required this.gForceHistory,
    required this.gpsAccuracyHistory,
    required this.timeHistory,
    required this.laps,
  });

  @override
  State<_SessionOverviewPanel> createState() => _SessionOverviewPanelState();
}

class _SessionOverviewPanelState extends State<_SessionOverviewPanel> {
  _MetricFocus _focus = _MetricFocus.speed;
  int _selectedIndex = 0;
  int _currentLap = 0; // ⬅️ LAP CORRENTE

  String _formatLap(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Se non ho dati di base → placeholder
    if (widget.timeHistory.length < 2 ||
        widget.speedHistory.isEmpty ||
        widget.gForceHistory.isEmpty ||
        widget.gpsAccuracyHistory.isEmpty ||
        widget.gpsTrack.isEmpty) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: const Center(
          child: Text(
            'Nessun dato registrato per questa sessione',
            style: TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    // Nessun giro → usa tutti i dati come fallback
    if (widget.laps.isEmpty) {
      // Fallback vecchio comportamento: un "lap" unico con tutti i sample
      widget.laps.add(widget.timeHistory.last); // se vuoi evitare questa riga, puoi gestire diversamente
    }

    final int lapCount = widget.laps.length;
    _currentLap = _currentLap.clamp(0, lapCount - 1);

    // Calcola start/end assoluti (Duration) del giro selezionato
    Duration lapStart = Duration.zero;
    for (int i = 0; i < _currentLap; i++) {
      lapStart += widget.laps[i];
    }
    final Duration lapDuration = widget.laps[_currentLap];
    final Duration lapEnd = lapStart + lapDuration;

    // Indici dei sample che appartengono a questo giro
    final List<int> indices = [];
    for (int i = 0; i < widget.timeHistory.length; i++) {
      final t = widget.timeHistory[i];
      if (t >= lapStart && t <= lapEnd) {
        indices.add(i);
      }
    }

    // Se per qualche motivo non abbiamo abbastanza punti per questo giro,
    // esci con placeholder "tecnico"
    if (indices.length < 2) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: Center(
          child: Text(
            'Dati insufficienti per il giro ${_currentLap + 1}',
            style: const TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    final int len = indices.length;
    _selectedIndex = _selectedIndex.clamp(0, len - 1);

    // Timeline (secondi) relativa all’inizio del giro
    final baseMs =
        widget.timeHistory[indices.first].inMilliseconds.toDouble();
    final List<double> xs = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return (widget.timeHistory[idx].inMilliseconds.toDouble() - baseMs) /
            1000.0;
      },
    );

    // Serie (solo campioni del giro)
    final List<FlSpot> speedSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.speedHistory[idx]);
      },
    );
    final List<FlSpot> gSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.gForceHistory[idx]);
      },
    );
    final List<FlSpot> accSpots = List.generate(
      len,
      (j) {
        final idx = indices[j];
        return FlSpot(xs[j], widget.gpsAccuracyHistory[idx]);
      },
    );

    // Range Y globale
    double minY = speedSpots.first.y;
    double maxY = speedSpots.first.y;
    for (final s in [...speedSpots, ...gSpots, ...accSpots]) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final range = (maxY - minY).abs();
    final chartMinY = range > 0 ? minY - range * 0.1 : minY - 1;
    final chartMaxY = range > 0 ? maxY + range * 0.1 : maxY + 1;

    final cursorX = xs[_selectedIndex];

    // Indice "globale" del sample attualmente selezionato
    final int globalIdx = indices[_selectedIndex];

    // Segmento di traccia GPS solo del giro
    final List<LatLng> lapPath = indices
        .where((i) => i < widget.gpsTrack.length)
        .map((i) => LatLng(
              widget.gpsTrack[i].latitude,
              widget.gpsTrack[i].longitude,
            ))
        .toList();

    // Marker posizione corrente
    LatLng? marker;
    if (globalIdx < widget.gpsTrack.length) {
      final p = widget.gpsTrack[globalIdx];
      marker = LatLng(p.latitude, p.longitude);
    }

    // Valori correnti per il cursore
    final double curSpeed = widget.speedHistory[globalIdx];
    final double curG = widget.gForceHistory[globalIdx];
    final double curAcc = widget.gpsAccuracyHistory[globalIdx];
    final double curT = xs[_selectedIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF050608),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLineColor),
      ),
      child: Column(
        children: [
          // Barra superiore stile RaceBox con selettore giro
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                color: Colors.white70,
                onPressed: _currentLap > 0
                    ? () {
                        setState(() {
                          _currentLap--;
                          _selectedIndex = 0;
                        });
                      }
                    : null,
              ),
              Column(
                children: [
                  Text(
                    'LAP ${(_currentLap + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _formatLap(lapDuration),
                    style: const TextStyle(
                      fontSize: 12,
                      color: kMutedColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                color: Colors.white70,
                onPressed: _currentLap < lapCount - 1
                    ? () {
                        setState(() {
                          _currentLap++;
                          _selectedIndex = 0;
                        });
                      }
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Circuito (solo giro corrente)
          _CircuitTrackView(
            path: lapPath,
            marker: marker,
          ),
          const SizedBox(height: 16),

          // Grafico combinato
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: xs.first,
                maxX: xs.last,
                minY: chartMinY,
                maxY: chartMaxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: range > 0 ? range / 4 : 1,
                  verticalInterval:
                      (xs.last - xs.first) > 0 ? (xs.last - xs.first) / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.35),
                    strokeWidth: 0.5,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: kLineColor.withOpacity(0.25),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(
                        color: kLineColor.withOpacity(0.7), width: 1),
                    bottom: BorderSide(
                        color: kLineColor.withOpacity(0.7), width: 1),
                    right: const BorderSide(color: Colors.transparent),
                    top: const BorderSide(color: Colors.transparent),
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toStringAsFixed(0)}s',
                        style:
                            const TextStyle(color: kMutedColor, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: cursorX,
                      color: Colors.white.withOpacity(0.7),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.lineBarSpots == null ||
                        response.lineBarSpots!.isEmpty) {
                      return;
                    }
                    final spot = response.lineBarSpots!.first;
                    setState(() {
                      _selectedIndex =
                          spot.spotIndex.clamp(0, len - 1); // slider → punto
                    });
                  },
                ),
                lineBarsData: [
                  _buildLine(speedSpots, Colors.redAccent,
                      _focus == _MetricFocus.speed),
                  _buildLine(gSpots, Colors.greenAccent,
                      _focus == _MetricFocus.gForce),
                  _buildLine(
                      accSpots,
                      Colors.blueAccent,
                      _focus == _MetricFocus.accuracy),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Legend / selettore metrica
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metricChip(
                label: 'Speed',
                color: Colors.redAccent,
                selected: _focus == _MetricFocus.speed,
                onTap: () =>
                    setState(() => _focus = _MetricFocus.speed),
              ),
              _metricChip(
                label: 'G-Force',
                color: Colors.greenAccent,
                selected: _focus == _MetricFocus.gForce,
                onTap: () =>
                    setState(() => _focus = _MetricFocus.gForce),
              ),
              _metricChip(
                label: 'Accuracy',
                color: Colors.blueAccent,
                selected: _focus == _MetricFocus.accuracy,
                onTap: () =>
                    setState(() => _focus = _MetricFocus.accuracy),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Valori al cursore
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              't=${curT.toStringAsFixed(2)}s   '
              'v=${curSpeed.toStringAsFixed(1)} km/h   '
              'g=${curG.toStringAsFixed(2)}   '
              'acc=${curAcc.toStringAsFixed(2)} m',
              style: const TextStyle(
                fontSize: 11,
                color: kMutedColor,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _buildLine(
    List<FlSpot> spots,
    Color baseColor,
    bool focused,
  ) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: focused ? baseColor : baseColor.withOpacity(0.25),
      barWidth: focused ? 2.5 : 1.5,
      isStrokeCapRound: false,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _metricChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DISEGNO CIRCUITO (griglia + traccia + puntino posizione)
// ============================================================

class _CircuitTrackView extends StatelessWidget {
  final List<LatLng> path;
  final LatLng? marker;

  const _CircuitTrackView({
    required this.path,
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLineColor),
        ),
        child: const Center(
          child: Text(
            'Nessun dato GPS',
            style: TextStyle(color: kMutedColor),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1.6,
      child: CustomPaint(
        painter: _CircuitPainter(path: path, marker: marker),
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  final List<LatLng> path;
  final LatLng? marker;

  _CircuitPainter({
    required this.path,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = const Color(0xFF101015)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
      bgPaint,
    );

    // Griglia
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    const int gridLines = 8;
    final dx = size.width / gridLines;
    final dy = size.height / gridLines;
    for (int i = 1; i < gridLines; i++) {
      final x = dx * i;
      final y = dy * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Bounds lat/lon
    double minLat = path.first.latitude;
    double maxLat = path.first.latitude;
    double minLon = path.first.longitude;
    double maxLon = path.first.longitude;
    for (final p in path) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;
    final dLat = (maxLat - minLat).abs();
    final dLon = (maxLon - minLon).abs();

    final usableW = size.width * 0.8;
    final usableH = size.height * 0.8;
    final scale = (dLat == 0 || dLon == 0)
        ? 1.0
        : math.min(usableW / dLon, usableH / dLat);

    Offset _project(LatLng p) {
      final x = (p.longitude - centerLon) * scale + size.width / 2;
      final y = (centerLat - p.latitude) * scale + size.height / 2;
      return Offset(x, y);
    }

    // Ombra traccia
    final ui.Path shadowPath = ui.Path();
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      if (i == 0) {
        shadowPath.moveTo(o.dx, o.dy);
      } else {
        shadowPath.lineTo(o.dx, o.dy);
      }
    }
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(shadowPath.shift(const Offset(2, 2)), shadowPaint);

    // Traccia principale
    final ui.Path trackPath = ui.Path();
    for (int i = 0; i < path.length; i++) {
      final o = _project(path[i]);
      if (i == 0) {
        trackPath.moveTo(o.dx, o.dy);
      } else {
        trackPath.lineTo(o.dx, o.dy);
      }
    }
    final trackPaint = Paint()
      ..color = kBrandColor.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(trackPath, trackPaint);

    // Marker posizione corrente
    if (marker != null) {
      final o = _project(marker!);
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final markerBorder = Paint()
        ..color = kPulseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(o, 7, markerPaint);
      canvas.drawCircle(o, 7, markerBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.marker != marker;
  }
}
