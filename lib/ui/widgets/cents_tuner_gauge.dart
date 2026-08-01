import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Visual arc tuner — needle sweeps left/right with signed cents deviation.
class CentsTunerGauge extends StatelessWidget {
  const CentsTunerGauge({
    super.key,
    required this.centsOffset,
    this.maxCents = 50,
    this.active = true,
    this.height = 160,
  });

  final double? centsOffset;
  final double maxCents;
  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cents = centsOffset?.clamp(-maxCents, maxCents);
    final absCents = cents?.abs();
    final isInTune = absCents != null && absCents <= 25;
    final isClose = absCents != null && absCents > 25 && absCents <= 45;

    final accent = !active || cents == null
        ? AppColors.textMuted
        : isInTune
            ? AppColors.success
            : isClose
                ? AppColors.amberBright
                : AppColors.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          children: [
            const Text(
              'דיוק כוונון',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(
                painter: _CentsGaugePainter(
                  cents: cents,
                  maxCents: maxCents,
                  accent: accent,
                  active: active,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: accent,
                        height: 1,
                      ),
                      child: Text(
                        centsOffset == null
                            ? '—'
                            : '${centsOffset! > 0 ? '+' : ''}${centsOffset!.toStringAsFixed(0)}',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cents == null
                  ? 'ממתין לצליל…'
                  : 'סנט',
              style: TextStyle(
                color: accent.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'נמוך',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                Container(
                  width: 2,
                  height: 10,
                  color: AppColors.success.withValues(alpha: 0.6),
                ),
                Text(
                  'גבוה',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CentsGaugePainter extends CustomPainter {
  _CentsGaugePainter({
    required this.cents,
    required this.maxCents,
    required this.accent,
    required this.active,
  });

  final double? cents;
  final double maxCents;
  final Color accent;
  final bool active;

  static const _startAngle = math.pi * 0.85;
  static const _sweepAngle = math.pi * 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.72);
    final radius = math.min(size.width, size.height) * 0.42;

    final trackPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      trackPaint,
    );

    final gradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + _sweepAngle,
      colors: const [
        AppColors.error,
        AppColors.amber,
        AppColors.success,
        AppColors.amber,
        AppColors.error,
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      progressPaint,
    );

    if (active && cents != null) {
      final t = ((cents! + maxCents) / (maxCents * 2)).clamp(0.0, 1.0);
      final needleAngle = _startAngle + _sweepAngle * t;
      final needleEnd = Offset(
        center.dx + math.cos(needleAngle) * (radius - 6),
        center.dy + math.sin(needleAngle) * (radius - 6),
      );

      final glowPaint = Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(needleEnd, 10, glowPaint);

      final needlePaint = Paint()
        ..color = accent
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, needleEnd, needlePaint);

      canvas.drawCircle(
        center,
        8,
        Paint()..color = accent,
      );
      canvas.drawCircle(
        center,
        4,
        Paint()..color = AppColors.background,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CentsGaugePainter oldDelegate) {
    return oldDelegate.cents != cents ||
        oldDelegate.accent != accent ||
        oldDelegate.active != active;
  }
}
