import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Widget da usare come root di ogni pagina per replicare lo sfondo
class PulseBackground extends StatelessWidget {
  final Widget child;
  final bool withTopPadding;

  const PulseBackground({
    super.key,
    required this.child,
    this.withTopPadding = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient base
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.3,
              colors: [
                Color.fromRGBO(192, 255, 3, 0.18),
                kBgColor,
              ],
            ),
          ),
        ),
        // Glow verde in alto a sinistra
        Positioned(
          top: -120,
          left: -120,
          child: _GlowCircle(
            color: const Color(0xFF2CFF86),
            size: 380,
          ),
        ),
        // Glow verde in basso a destra
        Positioned(
          bottom: -160,
          right: -160,
          child: _GlowCircle(
            color: kBrandColor,
            size: 460,
          ),
        ),
        // Leggera griglia (simil bg-grid)
        CustomPaint(
          size: Size.infinite,
          painter: _GridPainter(),
        ),
        // Blur leggero per dare effetto glassy
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.black.withOpacity(0.35)),
        ),
        // Contenuto
        SafeArea(
          child: Padding(
            padding: EdgeInsets.only(top: withTopPadding ? 8 : 0),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowCircle({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.45),
            color.withOpacity(0.0),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 24.0;
    final paint = Paint()
      ..color = kLineColor.withOpacity(0.3)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
