import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/strumming_pattern.dart';
import '../app_theme.dart';

/// Animated "how to strum" demo: a guitar seen from the player's point of
/// view, zooming from the whole instrument to the strumming area, with a hand
/// and pick performing [pattern] at [bpm].
///
/// ↓ the pick sweeps from the thick (top) string to the thin one, ↑ it comes
/// back up through the 3–4 thin strings, ✕ the palm lands on the strings and
/// mutes them, p/i/m/a a thumb or finger plucks one string. Every string the
/// pick crosses vibrates. [onEvent] fires on each sounding stroke (for sound).
class GuitarStrumAnimation extends StatefulWidget {
  const GuitarStrumAnimation({
    super.key,
    required this.pattern,
    required this.bpm,
    required this.playing,
    this.closeUp = true,
    this.onEvent,
    this.onSlot,
  });

  final StrummingPattern pattern;
  final int bpm;
  final bool playing;

  /// true = zoomed on the strumming area, false = whole guitar.
  final bool closeUp;
  final void Function(PatternEvent event)? onEvent;

  /// Current slot index in the pattern (for highlighting outside).
  final void Function(int slot)? onSlot;

  @override
  State<GuitarStrumAnimation> createState() => _GuitarStrumAnimationState();
}

class _GuitarStrumAnimationState extends State<GuitarStrumAnimation>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  final _AnimState _state = _AnimState();
  Duration _last = Duration.zero;
  double _patternTime = 0; // ms, advances only while playing
  int _lastSlot = -1;

  @override
  void initState() {
    super.initState();
    // Starts on the whole guitar and glides into the close-up.
    _state.zoom = 0;
    _state.targetZoom = widget.closeUp ? 1 : 0;
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(covariant GuitarStrumAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _state.targetZoom = widget.closeUp ? 1 : 0;
    if (oldWidget.pattern != widget.pattern) {
      _patternTime = 0;
      _lastSlot = -1;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1000.0;
    _last = elapsed;
    _state.wallMs += dt;
    // Smooth camera.
    _state.zoom += (_state.targetZoom - _state.zoom) * min(1.0, dt / 350);

    final events = widget.pattern.events;
    if (widget.playing && events.isNotEmpty) {
      _patternTime += dt;
      final slotMs = 60000.0 / widget.bpm / widget.pattern.subdivision;
      final slot = (_patternTime / slotMs).floor();
      if (slot != _lastSlot) {
        _lastSlot = slot;
        final index = slot % events.length;
        final event = events[index];
        _state.startStroke(event, _state.wallMs, min(slotMs * 0.7, 230.0));
        widget.onSlot?.call(index);
        if (event.isSounding) widget.onEvent?.call(event);
      }
    }
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: CustomPaint(
        painter: _GuitarPainter(_state, repaint: _repaint),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Mutable animation state shared with the painter.
class _AnimState {
  double wallMs = 0;
  double zoom = 0;
  double targetZoom = 1;

  PatternEvent? stroke;
  double strokeStart = -10000;
  double strokeDuration = 200;

  /// Last time each string (index 0 = string 6 … 5 = string 1) was struck.
  final List<double> struck = List.filled(6, -10000);

  /// Strings damped by a palm mute until this time.
  double mutedUntil = -1;

  void startStroke(PatternEvent event, double now, double duration) {
    stroke = event;
    strokeStart = now;
    strokeDuration = duration;
    switch (event.kind) {
      case PatternEventKind.down:
        for (var i = 0; i < 6; i++) {
          struck[i] = now + duration * (0.15 + 0.7 * i / 5);
        }
      case PatternEventKind.up:
        // Thin strings only, from string 1 upwards.
        for (var k = 0; k < 4; k++) {
          struck[5 - k] = now + duration * (0.15 + 0.7 * k / 3);
        }
      case PatternEventKind.mute:
        mutedUntil = now + duration * 1.4;
      case PatternEventKind.finger:
        final s = event.stringNumber ?? 3;
        struck[6 - s] = now + duration * 0.45;
      case PatternEventKind.pause:
        break;
    }
  }
}

class _GuitarPainter extends CustomPainter {
  _GuitarPainter(this.s, {required Listenable repaint}) : super(repaint: repaint);

  final _AnimState s;

  // World geometry (guitar lying horizontally, neck to the left, player's view:
  // thick string at the top).
  static const double _nutX = 40;
  static const double _bridgeX = 820;
  static const double _strumX = 690;
  static double stringY(int i) => 266 + i * 13.5; // i = 0 → string 6

  static const Rect _wide = Rect.fromLTRB(-20, 60, 1000, 540);
  static const Rect _close = Rect.fromLTRB(560, 220, 830, 380);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1B5E), Color(0xFF0E1230)],
        ).createShader(Offset.zero & size),
    );

    // Camera: interpolate the visible world rect and fit (cover) the widget.
    final z = Curves.easeInOut.transform(s.zoom.clamp(0.0, 1.0));
    final view = Rect.lerp(_wide, _close, z)!;
    final scale = max(size.width / view.width, size.height / view.height);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-view.center.dx, -view.center.dy);

    _paintGuitar(canvas);
    _paintStrings(canvas);
    _paintHand(canvas, scale);
    canvas.restore();

    _paintCaption(canvas, size);
  }

  void _paintGuitar(Canvas canvas) {
    // Neck + headstock.
    final neck = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-10, 252, 520, 348),
      const Radius.circular(6),
    );
    canvas.drawRRect(neck, Paint()..color = const Color(0xFF5B3A1E));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-90, 240, 0, 360),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFF3F2814),
    );
    final fret = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 3;
    var x = _nutX;
    for (var i = 0; i < 12; i++) {
      canvas.drawLine(Offset(x, 254), Offset(x, 346), fret);
      x += 44 * pow(0.944, i).toDouble();
    }
    for (final dot in const [3, 5, 7, 9]) {
      var fx = _nutX;
      for (var i = 0; i < dot - 1; i++) {
        fx += 44 * pow(0.944, i).toDouble();
      }
      final next = fx + 44 * pow(0.944, dot - 1).toDouble();
      canvas.drawCircle(
        Offset((fx + next) / 2, 300),
        6,
        Paint()..color = const Color(0xFFF5E6C8),
      );
    }

    // Body: upper bout, lower bout, waist.
    final body = Path()
      ..addOval(Rect.fromCircle(center: const Offset(560, 300), radius: 150))
      ..addOval(Rect.fromCircle(center: const Offset(770, 300), radius: 190));
    canvas.drawPath(
      body.shift(const Offset(6, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.1, -0.2),
          radius: 0.9,
          colors: [Color(0xFFE7B36A), Color(0xFFB9772F), Color(0xFF7A4A1C)],
        ).createShader(const Rect.fromLTRB(410, 110, 960, 490)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFF3F2814),
    );
    // Soundhole + rosette.
    const hole = Offset(585, 300);
    for (final (r, c) in const [
      (64.0, Color(0xFF3F2814)),
      (58.0, Color(0xFFF5E6C8)),
      (54.0, Color(0xFF14532D)),
      (50.0, Color(0xFFF5E6C8)),
    ]) {
      canvas.drawCircle(hole, r, Paint()..color = c);
    }
    canvas.drawCircle(hole, 46, Paint()..color = const Color(0xFF120A04));
    // Fingerboard end over the soundhole.
    canvas.drawRect(
      const Rect.fromLTRB(500, 254, 540, 346),
      Paint()..color = const Color(0xFF3B2410),
    );
    // Bridge + saddle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(812, 236, 852, 364),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF2B1A0B),
    );
    canvas.drawLine(
      const Offset(_bridgeX, 254),
      const Offset(_bridgeX, 346),
      Paint()
        ..color = const Color(0xFFF5F5F4)
        ..strokeWidth = 3,
    );
  }

  void _paintStrings(Canvas canvas) {
    final now = s.wallMs;
    final muted = now < s.mutedUntil;
    for (var i = 0; i < 6; i++) {
      final y = stringY(i);
      final age = now - s.struck[i];
      var amp = age >= 0 ? 4.5 * exp(-age / (muted ? 40 : 420)) : 0.0;
      if (muted) amp = min(amp, 0.6);
      final thickness = 3.4 - i * 0.45;
      final color = i < 3 ? const Color(0xFFD9B26F) : const Color(0xFFE5E7EB);
      final path = Path()..moveTo(_nutX, y);
      const n = 60;
      for (var k = 1; k <= n; k++) {
        final x = _nutX + (_bridgeX - _nutX) * k / n;
        final env = sin(pi * k / n);
        final wobble = amp * env * sin(age / 7 + k * 0.6);
        path.lineTo(x, y + wobble);
      }
      if (amp > 0.3) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness + amp * 1.6
            ..color = AppColors.turquoise.withValues(alpha: min(0.5, amp / 8))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..color = color,
      );
    }
    // String labels near the nut.
    const names = ['E', 'A', 'D', 'G', 'B', 'e'];
    for (var i = 0; i < 6; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: names[i],
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_strumX + 95, stringY(i) - tp.height / 2));
    }
  }

  void _paintHand(Canvas canvas, double scale) {
    final stroke = s.stroke;
    final now = s.wallMs;
    final t = stroke == null
        ? 1.0
        : ((now - s.strokeStart) / s.strokeDuration).clamp(0.0, 1.6);
    final eased = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final topY = stringY(0) - 22;
    final bottomY = stringY(5) + 22;
    final upStopY = stringY(2) - 10;

    var pickY = topY;
    var showPick = true;
    var palm = false;
    Offset? fingerAt;
    String? fingerLabel;

    switch (stroke?.kind) {
      case PatternEventKind.down:
        pickY = topY + (bottomY - topY) * eased;
      case PatternEventKind.up:
        pickY = bottomY + (upStopY - bottomY) * eased;
      case PatternEventKind.mute:
        palm = t < 1.4;
        pickY = topY - 10;
      case PatternEventKind.finger:
        showPick = false;
        final sn = stroke!.stringNumber ?? 3;
        final y = stringY(6 - sn);
        // Finger presses into the string, then releases past it.
        fingerAt = Offset(_strumX, y - 10 + 18 * eased);
        fingerLabel = stroke.fingerLabel;
      case PatternEventKind.pause:
      case null:
        // Hand waits above the strings, still moving with the beat.
        pickY = topY - 6;
    }

    // Motion trail for strums.
    final kind = stroke?.kind;
    if (showPick &&
        (kind == PatternEventKind.down || kind == PatternEventKind.up) &&
        t < 1.3) {
      final from = kind == PatternEventKind.down ? topY : bottomY;
      final trail = Rect.fromLTRB(
        _strumX - 9,
        min(from, pickY),
        _strumX + 9,
        max(from, pickY),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(trail, const Radius.circular(9)),
        Paint()
          ..color = (kind == PatternEventKind.down
                  ? AppColors.turquoise
                  : AppColors.amberBright)
              .withValues(alpha: 0.35 * (1 - (t / 1.3)))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    const skin = Color(0xFFF2C9A0);
    const skinShade = Color(0xFFD9A57A);

    if (palm) {
      // Palm landing on the strings near the bridge.
      final land = Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0));
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(_strumX + 20, 240 + 15 * land, _strumX + 120, 350),
        const Radius.circular(30),
      );
      canvas.drawRRect(r, Paint()..color = skin.withValues(alpha: 0.95));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = skinShade,
      );
      return;
    }

    if (fingerAt != null) {
      // Forearm from below, finger tip on the string.
      final arm = Path()
        ..moveTo(fingerAt.dx + 70, 420)
        ..quadraticBezierTo(fingerAt.dx + 40, fingerAt.dy + 40, fingerAt.dx + 6, fingerAt.dy + 6)
        ..lineTo(fingerAt.dx - 8, fingerAt.dy + 10)
        ..quadraticBezierTo(fingerAt.dx + 10, fingerAt.dy + 60, fingerAt.dx + 30, 420)
        ..close();
      canvas.drawPath(arm, Paint()..color = skin);
      canvas.drawCircle(fingerAt, 9, Paint()..color = skinShade);
      if (fingerLabel != null) {
        _worldText(canvas, fingerLabel, fingerAt.translate(-28, -4), AppColors.violet, 18);
      }
      return;
    }

    if (!showPick) return;
    // Hand (fist) holding the pick, coming from the right side.
    final pickTip = Offset(_strumX, pickY);
    final fist = Rect.fromCenter(
      center: pickTip.translate(34, -6),
      width: 58,
      height: 46,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fist, const Radius.circular(22)),
      Paint()..color = skin,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fist, const Radius.circular(22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = skinShade,
    );
    // Wrist going off to the right.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(fist.right - 12, fist.top + 6, fist.right + 140, fist.bottom - 4),
        const Radius.circular(18),
      ),
      Paint()..color = skin,
    );
    // Pick (rounded triangle) pointing at the strings.
    final pick = Path()
      ..moveTo(pickTip.dx - 3, pickTip.dy)
      ..quadraticBezierTo(pickTip.dx + 6, pickTip.dy - 16, pickTip.dx + 20, pickTip.dy - 14)
      ..quadraticBezierTo(pickTip.dx + 22, pickTip.dy + 4, pickTip.dx + 8, pickTip.dy + 12)
      ..close();
    canvas.drawPath(pick, Paint()..color = AppColors.pink);
  }

  void _worldText(Canvas canvas, String text, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at.translate(-tp.width / 2, -tp.height / 2));
  }

  void _paintCaption(Canvas canvas, Size size) {
    final stroke = s.stroke;
    if (stroke == null) return;
    final age = s.wallMs - s.strokeStart;
    if (age > 600) return;
    final text = switch (stroke.kind) {
      PatternEventKind.down => '↓',
      PatternEventKind.up => '↑',
      PatternEventKind.mute => '✕',
      PatternEventKind.finger => stroke.fingerLabel ?? '•',
      PatternEventKind.pause => '',
    };
    if (text.isEmpty) return;
    final color = switch (stroke.kind) {
      PatternEventKind.down => AppColors.turquoise,
      PatternEventKind.up => AppColors.amberBright,
      PatternEventKind.finger => AppColors.violet,
      _ => Colors.white,
    };
    final a = (1 - age / 600).clamp(0.0, 1.0);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: a),
          fontSize: 44,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: color.withValues(alpha: a * 0.6), blurRadius: 14)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(14, size.height - tp.height - 6));
  }

  @override
  bool shouldRepaint(covariant _GuitarPainter oldDelegate) => false;
}
