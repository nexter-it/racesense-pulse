import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/pulse_background.dart';
import '../widgets/pulse_chip.dart';
import 'gps_wait_page.dart';
import 'custom_circuits_page.dart';

class NewPostPage extends StatelessWidget {
  static const routeName = '/new';

  const NewPostPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PulseBackground(
      withTopPadding: true,
      child: Column(
        children: [
          const SizedBox(height: 8),

          // HEADER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Nuova attività',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                const PulseChip(
                  label: Text('AUTO LAP'),
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
          ),

          // BODY
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CARD 1 — Tracking Live
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1C1C1E),
                            const Color(0xFF151515),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: kLineColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 12,
                            spreadRadius: -2,
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed,
                                  color: kBrandColor, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Tracking live',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: const Color.fromRGBO(255, 255, 255, 0.05),
                              border: Border.all(color: kLineColor),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.phone_iphone,
                                    size: 16, color: kMutedColor),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Sorgente dati attuale: GPS/IMU del telefono',
                                    style: TextStyle(
                                      color: kMutedColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: const [
                              Expanded(
                                child: _FeaturePill(
                                  icon: Icons.sensors,
                                  title: 'Tracking',
                                  subtitle: 'GPS ~1Hz con smoothing + IMU',
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _FeaturePill(
                                  icon: Icons.flag_circle_outlined,
                                  title: 'Start/Finish',
                                  subtitle: 'Riconoscimento automatico gate',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: const [
                              Expanded(
                                child: _FeaturePill(
                                  icon: Icons.timer_outlined,
                                  title: 'Telemetria',
                                  subtitle: 'Tempi, giri, delta live',
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _FeaturePill(
                                  icon: Icons.insert_chart_outlined,
                                  title: 'Recap',
                                  subtitle:
                                      'Tracciato e grafici a fine sessione',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 15),

                    // CARD 2 — Dispositivi esterni
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF121212),
                            const Color(0xFF0D0D0D),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: kLineColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bluetooth,
                                  color: kBrandColor, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Dispositivi esterni',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Collega moduli esterni come sensori GPS ad alta frequenza, IMU professionali o sistemi CAN-BUS.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: kMutedColor,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Bottone con icona Bluetooth
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Funzione in arrivo: scansione dispositivi Bluetooth.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.bluetooth_searching),
                              label: const Text('Collega dispositivi tracking'),
                            ),
                          ),
                          const SizedBox(height: 5),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Funzione in arrivo: collegamento dispositivo salute.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.favorite_border),
                              label: const Text('Collega dispositivo salute'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // MAIN BUTTON — Inizia Registrazione
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GpsWaitPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text(
                          'Inizia sessione',
                          style: TextStyle(fontSize: 17),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // CUSTOM CIRCUITS
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CustomCircuitsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.alt_route_outlined),
                        label: const Text(
                          'Circuiti Custom',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 24,
                          ),
                          side: const BorderSide(color: kBrandColor),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeaturePill({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF0f1116),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kBrandColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: kFgColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: kMutedColor,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
