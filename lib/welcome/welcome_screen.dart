import 'package:flutter/material.dart';

import '../map/evacuation_screen.dart';
import '../models/map_scene.dart';

class WelcomeScreen extends StatelessWidget {
  final MapScene scene;

  const WelcomeScreen({super.key, required this.scene});

  static const Color _background = Color(0xFFF7F9FC);
  static const Color _green = Color(0xFF17835F);
  static const Color _text = Color(0xFF4B5563);
  static const Color _card = Color(0xFFF0F4F8);

  void _openMap(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => EvacuationScreen(scene: scene)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 18 : 36,
                  vertical: compact ? 18 : 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'WELCOME TO SAFEROUTE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 25 : 31,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: compact ? 24 : 34),
                      const Text(
                        'Key Features',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _feature(
                        icon: Icons.map_outlined,
                        color: _green,
                        title: 'CAMPUS MAP NAVIGATION',
                      ),
                      _feature(
                        icon: Icons.route_outlined,
                        color: Color(0xFF2563EB),
                        title: 'ROUTING',
                      ),
                      _feature(
                        icon: Icons.refresh_rounded,
                        color: Color(0xFFF59E0B),
                        title: 'REROUTING',
                      ),
                      _feature(
                        icon: Icons.warning_amber_rounded,
                        color: Color(0xFF7C3AED),
                        title: 'EMERGENCY SIMULATION',
                      ),
                      _feature(
                        icon: Icons.apartment_rounded,
                        color: Color(0xFF6D28D9),
                        title: 'BUILDING & FLOOR ROUTING',
                      ),
                      _feature(
                        icon: Icons.wifi_off_rounded,
                        color: Color(0xFF374151),
                        title: 'OFFLINE',
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: () => _openMap(context),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text(
                            'GET STARTED',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .5,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _feature({
    required IconData icon,
    required Color color,
    required String title,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 27, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                letterSpacing: .15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
