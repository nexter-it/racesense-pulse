import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PREMIUM UI CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════
const Color _kBgColor = Color(0xFF0A0A0A);
const Color _kCardStart = Color(0xFF1A1A1A);
const Color _kCardEnd = Color(0xFF141414);
const Color _kBorderColor = Color(0xFF2A2A2A);

/// Pagina che mostra i dispositivi GPS BLE compatibili con l'app
class CompatibleDevicesPage extends StatelessWidget {
  const CompatibleDevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildIntroCard(),
                  const SizedBox(height: 20),
                  _buildSectionHeader('Dispositivi Compatibili'),
                  const SizedBox(height: 12),
                  _buildDeviceCard(
                    name: 'Racesense Track',
                    description: 'GPS professionale per tracking ad alta precisione',
                    frequency: '30 Hz',
                    accuracy: '<0.5m',
                    features: ['Batteria lunga durata', 'Bluetooth 5.0', 'Impermeabile'],
                  ),
                  const SizedBox(height: 12),
                  _buildDeviceCard(
                    name: 'Racebox Mini',
                    description: 'Dispositivo GPS compatto per motorsport',
                    frequency: '25 Hz',
                    accuracy: '<1m',
                    features: ['Formato tascabile', 'Registrazione integrata', 'App dedicata'],
                  ),
                  const SizedBox(height: 12),
                  _buildDeviceCard(
                    name: 'Racebox Mini S',
                    description: 'Versione avanzata del Mini con maggiore precisione',
                    frequency: '25 Hz',
                    accuracy: '<0.5m',
                    features: ['Alta frequenza', 'Dual antenna', 'Sensori IMU integrati'],
                  ),
                  const SizedBox(height: 12),
                  _buildDeviceCard(
                    name: 'Dragy',
                    description: 'GPS per performance testing e drag racing',
                    frequency: '25 Hz',
                    accuracy: '<1m',
                    features: ['0-100 km/h', 'Performance metrics', 'Display integrato'],
                  ),
                  const SizedBox(height: 24),
                  _buildInfoCard(),
                ],
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
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    kBrandColor.withAlpha(40),
                    kBrandColor.withAlpha(20),
                  ],
                ),
                border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
              ),
              child: const Icon(Icons.arrow_back, color: kBrandColor, size: 20),
            ),
          ),
          const SizedBox(width: 14),
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
              child: Icon(Icons.devices, color: kPulseColor, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Dispositivi Compatibili',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: kFgColor,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [kBrandColor.withAlpha(25), kBrandColor.withAlpha(12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kBrandColor.withAlpha(120), width: 2),
        boxShadow: [
          BoxShadow(
            color: kBrandColor.withAlpha(30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBrandColor.withAlpha(30),
                  border: Border.all(color: kBrandColor.withAlpha(60)),
                ),
                child: Icon(Icons.info_outline, color: kBrandColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'GPS Professionale',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Racesense Pulse è compatibile con dispositivi GPS esterni ad alta precisione per una telemetria professionale. Questi dispositivi offrono frequenze di aggiornamento superiori e precisione sub-metro.',
            style: TextStyle(
              fontSize: 13,
              color: kMutedColor,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: kBrandColor,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: kMutedColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard({
    required String name,
    required String description,
    required String frequency,
    required String accuracy,
    required List<String> features,
  }) {
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        kBrandColor.withAlpha(40),
                        kBrandColor.withAlpha(20),
                      ],
                    ),
                    border: Border.all(color: kBrandColor.withAlpha(80), width: 1.5),
                  ),
                  child: Center(
                    child: Icon(Icons.gps_fixed, color: kBrandColor, size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: kFgColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: kMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: _kBorderColor),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildSpec('Frequenza', frequency, Icons.speed),
                const SizedBox(width: 20),
                _buildSpec('Precisione', accuracy, Icons.my_location),
              ],
            ),
            // const SizedBox(height: 14),
            // Wrap(
            //   spacing: 8,
            //   runSpacing: 8,
            //   children: features.map((feature) => _buildFeatureChip(feature)).toList(),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpec(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withAlpha(4),
          border: Border.all(color: _kBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: kBrandColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: kMutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: kFgColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(String feature) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: kPulseColor.withAlpha(15),
        border: Border.all(color: kPulseColor.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 12, color: kPulseColor),
          const SizedBox(width: 6),
          Text(
            feature,
            style: TextStyle(
              fontSize: 11,
              color: kPulseColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_kCardStart, _kCardEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPulseColor.withAlpha(15),
                  border: Border.all(color: kPulseColor.withAlpha(40)),
                ),
                child: Icon(Icons.help_outline, color: kPulseColor, size: 16),
              ),
              const SizedBox(width: 12),
              const Text(
                'Note importanti',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: kFgColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('I dispositivi devono essere configurati in modalità Bluetooth'),
          const SizedBox(height: 8),
          _buildInfoRow('Assicurati che il dispositivo sia acceso e nelle vicinanze'),
          const SizedBox(height: 8),
          _buildInfoRow('La connessione BLE richiede i permessi di localizzazione'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kMutedColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: kMutedColor,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
