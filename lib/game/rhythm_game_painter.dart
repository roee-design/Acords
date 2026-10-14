import 'dart:math';

import 'package:flutter/material.dart';

import '../models/strumming_pattern.dart';
import '../ui/app_theme.dart';
import 'rhythm_chart.dart';
import 'rhythm_judge.dart';

/// Short-lived spark spawned on a hit.
class GameParticle {
  GameParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.bornMs,
    required this.color,
  });

  final double x;
  final double y;
  final double vx; // px per ms
  final double vy;
  final double bornMs;
  final Color color;
}

/// Floating "מושלם!" / "טוב" / "פספוס" text.
class GamePopup {
  GamePopup(this.text, this.color, this.bornMs);

  final String text;
  final Color color;
  final double bornMs;
}

/// Everything the painter needs for one frame (owned by the game screen).
class GameView {
  GameView({required this.chart, required this.judge, required this.chordName});

  final RhythmChart chart;
  final RhythmJudge judge;
  final String Function(String chordId) chordName;

  /// Chart time of this frame (negative during the count-in).
  double nowMs = -1;
  final List<GameParticle> particles = [];
  final List<GamePopup> popups = [];

  /// Chart time of the last stroke (strings vibrate) and its direction.
  double lastStrokeMs = -100000;
  bool lastStrokeDown = true;

  /// Bars whose chord the microphone confirmed.
  final Set<int> verifiedBars = {};

  /// How far ahead notes become visible.
  double get lookaheadMs => max(1800.0, chart.beatMs * 3.2);
}

Color noteColor(PatternEventKind kind) => switch (kind) {
      PatternEventKind.down => AppColors.turquoise,
      PatternEventKind.up => AppColors.amberBright,
      PatternEventKind.mute => const Color(0xFF94A3B8),
      PatternEventKind.finger => AppColors.violet,
      PatternEventKind.pause => Colors.transparent,
    };

/// Perspective highway: notes come from the far end towards the strings.
class RhythmGamePainter extends CustomPainter {
  RhythmGamePainter(this.view, {required Listenable repaint})
      : super(repaint: repaint);

  final GameView view;

  static const double _hitFraction = 0.80;
  static const double _topFraction = 0.04;

  double hitY(Size size) => size.height * _hitFraction;

  /// 0 at the horizon … 1 at the hit line, for a note [dtMs] in the future.
  double _depth(double dtMs) => 1 - dtMs / view.lookaheadMs;

  /// Perspective curve: far notes move slowly, near notes rush in.
  double _curve(double p) => pow(p.clamp(0.0, 1.2), 1.6).toDouble();

  double _yFor(Size size, double dtMs) {
    final top = size.height * _topFraction;
    final hit = hitY(size);
    if (dtMs >= 0) return top + (hit - top) * _curve(_depth(dtMs));
    // Past the line: keep moving at arrival speed.
    final speed = 1.6 * (hit - top) / view.lookaheadMs;
    return hit + (-dtMs) * speed;
  }

  double _halfWidthAt(Size size, double y) {
    final top = size.height * _topFraction;
    final hit = hitY(size);
    final full = min(size.width * 0.44, 210.0);
    final t = ((y - top) / (hit - top)).clamp(0.0, 1.4);
    return full * (0.32 + 0.68 * t);
  }

  double _laneOffset(PatternEventKind kind) => switch (kind) {
        PatternEventKind.down => -0.5,
        PatternEventKind.up => 0.5,
        _ => 0.0,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final now = view.nowMs;
    final cx = size.width / 2;
    final hit = hitY(size);
    final top = size.height * _topFraction;

    _paintHighway(canvas, size, cx, top, hit);
    _paintBeatLines(canvas, size, cx, now);
    _paintStrings(canvas, size, cx, hit, now);
    _paintNotes(canvas, size, cx, now);
    _paintParticles(canvas, now);
    _paintPopups(canvas, size, cx, hit, now);
  }

  void _paintHighway(Canvas canvas, Size size, double cx, double top, double hit) {
    final bottom = size.height;
    final wTop = _halfWidthAt(size, top);
    final wHit = _halfWidthAt(size, hit);
    final wBottom = _halfWidthAt(size, bottom);
    final path = Path()
      ..moveTo(cx - wTop, top)
      ..lineTo(cx + wTop, top)
      ..lineTo(cx + wBottom, bottom)
      ..lineTo(cx - wBottom, bottom)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.05),
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
    );
    // Beat pulse glow on the floor.
    final beatPhase = view.nowMs < -100000
        ? 0.0
        : (view.nowMs / view.chart.beatMs) - (view.nowMs / view.chart.beatMs).floor();
    final pulse = (1 - beatPhase).clamp(0.0, 1.0);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.violet.withValues(alpha: 0.45 + 0.4 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);
    canvas.drawLine(Offset(cx - wTop, top), Offset(cx - wBottom, bottom), edge);
    canvas.drawLine(Offset(cx + wTop, top), Offset(cx + wBottom, bottom), edge);
    // Lane dividers.
    final lane = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    for (final f in const [-0.25, 0.25]) {
      canvas.drawLine(
        Offset(cx + wTop * f * 2, top),
        Offset(cx + wHit * f * 2, hit),
        lane,
      );
    }
  }

  void _paintBeatLines(Canvas canvas, Size size, double cx, double now) {
    final chart = view.chart;
    final beat = chart.beatMs;
    final first = (now / beat).ceil();
    final last = ((now + view.lookaheadMs) / beat).floor();
    for (var b = first; b <= last; b++) {
      final t = b * beat;
      if (t < 0 || t > chart.durationMs) continue;
      final y = _yFor(size, t - now);
      final half = _halfWidthAt(size, y);
      final isBar = (t / chart.barMs - (t / chart.barMs).round()).abs() < 1e-6;
      canvas.drawLine(
        Offset(cx - half, y),
        Offset(cx + half, y),
        Paint()
          ..strokeWidth = isBar ? 2.5 : 1
          ..color = Colors.white.withValues(alpha: isBar ? 0.35 : 0.12),
      );
      if (isBar) {
        final bar = chart.barAt(t + 1);
        if (bar != null) {
          final scale = 0.5 + 0.5 * _curve(_depth(t - now));
          _label(
            canvas,
            view.chordName(bar.chordId),
            Offset(cx - half - 10, y),
            color: view.verifiedBars.contains(bar.index)
                ? AppColors.success
                : Colors.white,
            fontSize: 22 * scale,
            alignRight: true,
          );
        }
      }
    }
  }

  void _paintStrings(Canvas canvas, Size size, double cx, double hit, double now) {
    final half = _halfWidthAt(size, hit) + 18;
    // Glow band.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, hit), width: half * 2 + 20, height: 46),
        const Radius.circular(23),
      ),
      Paint()
        ..color = AppColors.turquoise.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final age = now - view.lastStrokeMs;
    final energy = age < 0 ? 0.0 : exp(-age / 180);
    for (var s = 0; s < 6; s++) {
      // Down strokes reach the low strings first, up strokes the high ones.
      final order = view.lastStrokeDown ? s : 5 - s;
      final local = (age - order * 12).clamp(0.0, 10000.0);
      final amp = energy > 0.01 ? 5.0 * exp(-local / 160) * (age >= order * 12 ? 1 : 0) : 0.0;
      final y = hit - 15 + s * 6;
      final path = Path()..moveTo(cx - half, y);
      const segments = 24;
      for (var i = 1; i <= segments; i++) {
        final x = cx - half + 2 * half * i / segments;
        final env = sin(pi * i / segments);
        final wobble = amp * env * sin(local / 9 + i * 0.9);
        path.lineTo(x, y + wobble);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 - s * 0.4
          ..color = Color.lerp(
            const Color(0xFFE2C79A),
            Colors.white,
            min(1.0, amp / 5),
          )!
              .withValues(alpha: 0.9),
      );
    }
  }

  void _paintNotes(Canvas canvas, Size size, double cx, double now) {
    final notes = view.chart.notes;
    final results = view.judge.results;
    for (final note in notes) {
      final dt = note.timeMs - now;
      final result = results[note.index];
      if (dt > view.lookaheadMs) break;
      if (result == null && dt < -400) continue;

      var y = _yFor(size, result == null ? dt : max(dt, -1.0));
      var alpha = 1.0;
      var extraScale = 1.0;
      var color = noteColor(note.kind);

      if (result != null) {
        final age = now - result.atMs;
        if (age > 420) continue;
        if (result.judgement == Judgement.miss) {
          y = _yFor(size, dt);
          color = const Color(0xFF64748B);
          alpha = (1 - age / 420).clamp(0.0, 1.0);
        } else {
          // Hit: the note flies off in its stroke direction.
          final dir = note.kind == PatternEventKind.up ? -1.0 : 1.0;
          y = hitY(size) + dir * age * 0.9;
          extraScale = 1 + age / 500;
          alpha = (1 - age / 300).clamp(0.0, 1.0);
        }
      }
      if (alpha <= 0) continue;

      final half = _halfWidthAt(size, y);
      final x = cx + _laneOffset(note.kind) * half;
      final scale = (0.35 + 0.65 * ((y - size.height * _topFraction) /
                  (hitY(size) - size.height * _topFraction))
              .clamp(0.0, 1.3)) *
          extraScale;
      _drawNote(canvas, Offset(x, y), scale, note, color, alpha);
    }
  }

  void _drawNote(
    Canvas canvas,
    Offset c,
    double scale,
    RhythmNote note,
    Color color,
    double alpha,
  ) {
    final w = 70.0 * scale;
    final h = 54.0 * scale;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: w, height: h),
      Radius.circular(14 * scale),
    );
    canvas.drawRRect(
      rect.inflate(4 * scale),
      Paint()
        ..color = color.withValues(alpha: 0.35 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.25)!.withValues(alpha: alpha),
            color.withValues(alpha: alpha),
          ],
        ).createShader(rect.outerRect),
    );
    final ink = Paint()
      ..color = const Color(0xFF0E1230).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (note.kind) {
      case PatternEventKind.down:
      case PatternEventKind.up:
        final dir = note.kind == PatternEventKind.down ? 1.0 : -1.0;
        final len = h * 0.30;
        canvas.drawLine(
          c.translate(0, -dir * len),
          c.translate(0, dir * len),
          ink,
        );
        final head = Path()
          ..moveTo(c.dx - len * 0.8, c.dy + dir * len * 0.15)
          ..lineTo(c.dx, c.dy + dir * len)
          ..lineTo(c.dx + len * 0.8, c.dy + dir * len * 0.15);
        canvas.drawPath(head, ink);
      case PatternEventKind.mute:
        final d = h * 0.22;
        canvas.drawLine(c.translate(-d, -d), c.translate(d, d), ink);
        canvas.drawLine(c.translate(d, -d), c.translate(-d, d), ink);
      case PatternEventKind.finger:
        _label(
          canvas,
          note.fingerLabel ?? '${note.stringNumber ?? ''}',
          c.translate(0, -h * 0.08),
          color: const Color(0xFF0E1230).withValues(alpha: alpha),
          fontSize: 24 * scale,
          center: true,
        );
        if (note.stringNumber != null) {
          _label(
            canvas,
            'מיתר ${note.stringNumber}',
            c.translate(0, h * 0.30),
            color: const Color(0xFF0E1230).withValues(alpha: alpha),
            fontSize: 10 * scale,
            center: true,
          );
        }
      case PatternEventKind.pause:
        break;
    }
  }

  void _paintParticles(Canvas canvas, double now) {
    view.particles.removeWhere((p) => now - p.bornMs > 550);
    for (final p in view.particles) {
      final age = now - p.bornMs;
      final x = p.x + p.vx * age;
      final y = p.y + p.vy * age + 0.0006 * age * age;
      final a = (1 - age / 550).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x, y),
        3.5 * a + 1,
        Paint()..color = p.color.withValues(alpha: a),
      );
    }
  }

  void _paintPopups(Canvas canvas, Size size, double cx, double hit, double now) {
    view.popups.removeWhere((p) => now - p.bornMs > 650);
    if (view.popups.isEmpty) return;
    final p = view.popups.last;
    final age = now - p.bornMs;
    final pop = age < 120 ? 1.5 - 0.5 * (age / 120) : 1.0;
    final a = age < 450 ? 1.0 : (1 - (age - 450) / 200).clamp(0.0, 1.0);
    _label(
      canvas,
      p.text,
      Offset(cx, hit - 110 - age * 0.04),
      color: p.color.withValues(alpha: a),
      fontSize: 30 * pop,
      center: true,
      shadow: true,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    required Color color,
    required double fontSize,
    bool center = false,
    bool alignRight = false,
    bool shadow = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          shadows: shadow
              ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 12)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center
        ? at.dx - tp.width / 2
        : (alignRight ? at.dx - tp.width : at.dx);
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant RhythmGamePainter oldDelegate) =>
      oldDelegate.view != view;
}
