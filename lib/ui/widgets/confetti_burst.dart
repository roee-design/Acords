import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Lightweight confetti burst — no external packages.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();

    const colors = [
      AppColors.success,
      AppColors.amberBright,
      AppColors.turquoise,
      Color(0xFFA7F3D0),
    ];

    _particles = List.generate(22, (i) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = 40 + _rng.nextDouble() * 70;
      return _ConfettiParticle(
        color: colors[i % colors.length],
        angle: angle,
        speed: speed,
        size: 5 + _rng.nextDouble() * 5,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 220,
          height: 120,
          child: CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: Curves.easeOut.transform(_controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.color,
    required this.angle,
    required this.speed,
    required this.size,
  });

  final Color color;
  final double angle;
  final double speed;
  final double size;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.7);

    for (final p in particles) {
      final distance = p.speed * progress;
      final x = origin.dx + math.cos(p.angle) * distance;
      final y = origin.dy + math.sin(p.angle) * distance - progress * 30;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, y),
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
