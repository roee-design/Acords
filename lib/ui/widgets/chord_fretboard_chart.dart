import 'package:flutter/material.dart';

import '../../models/chord_definition.dart';
import '../../models/feedback_result.dart';
import '../app_theme.dart';

Color chordAccentColor(ChordDefinition chord) {
  return chord.displayName.endsWith('m')
      ? AppColors.amber
      : AppColors.turquoise;
}

/// Live status color for a fretted / open string on the diagram.
Color liveNoteColor(NoteStatus? status, Color fallback) {
  return switch (status) {
    NoteStatus.detected => AppColors.success,
    NoteStatus.weak || NoteStatus.missing => AppColors.error,
    NoteStatus.idle || NoteStatus.notInChord || null => fallback,
  };
}

/// Framed fretboard chart — scales to available space (no overflow).
class ChordFretboardFrame extends StatelessWidget {
  const ChordFretboardFrame({
    super.key,
    required this.chord,
    this.height,
    this.aspectRatio = 1.35,
    this.accent,
    this.borderRadius = 12,
    this.liveStatuses,
  });

  final ChordDefinition chord;

  /// Optional max height hint for scroll layouts. When null, uses [aspectRatio]
  /// or fills bounded space from a parent (e.g. [Expanded]).
  final double? height;
  final double aspectRatio;
  final Color? accent;
  final double borderRadius;
  final Map<int, NoteStatus>? liveStatuses;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? chordAccentColor(chord);
    final borderColor = liveStatuses == null
        ? color.withValues(alpha: 0.2)
        : color.withValues(alpha: 0.35);

    final viewport = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: _FretboardViewport(
        aspectRatio: aspectRatio,
        child: ChordFretboardChart(
          chord: chord,
          accent: color,
          liveStatuses: liveStatuses,
        ),
      ),
    );

    if (height != null) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: viewport,
      );
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: viewport,
    );
  }
}

/// Scales child fretboard to fit without clipping (LayoutBuilder + FittedBox).
class _FretboardViewport extends StatelessWidget {
  const _FretboardViewport({
    required this.aspectRatio,
    required this.child,
  });

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final designHeight = width / aspectRatio;
        final hasBoundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final height = hasBoundedHeight ? constraints.maxHeight : designHeight;

        return SizedBox(
          width: width,
          height: height,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: width,
              height: designHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Compact legend for O / X / finger dots.
class ChordFretboardLegend extends StatelessWidget {
  const ChordFretboardLegend({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        _LegendDot(color: AppColors.success, label: 'מיתר פתוח (O)'),
        _LegendDot(color: AppColors.error, label: 'מושתק (X)'),
        _LegendDot(color: accent, label: 'אצבע', filled: true),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.filled = false,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Classic guitar chord box diagram — 6 strings, 4 frets, dots, X/O markers.
class ChordFretboardChart extends StatelessWidget {
  const ChordFretboardChart({
    super.key,
    required this.chord,
    required this.accent,
    this.liveStatuses,
  });

  final ChordDefinition chord;
  final Color accent;
  final Map<int, NoteStatus>? liveStatuses;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _FretboardPainter(
          chord: chord,
          accent: accent,
          liveStatuses: liveStatuses,
        ),
      ),
    );
  }
}

class _FretboardPainter extends CustomPainter {
  _FretboardPainter({
    required this.chord,
    required this.accent,
    this.liveStatuses,
  });

  final ChordDefinition chord;
  final Color accent;
  final Map<int, NoteStatus>? liveStatuses;

  static const _fretCount = 4;
  static const _markerRowHeight = 20.0;
  static const _horizontalPadding = 10.0;
  static const _bottomPadding = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fingering = chord.fingering.padRight(6, '0');
    final gridTop = _markerRowHeight;
    final gridBottom = size.height - _bottomPadding;
    final gridHeight = (gridBottom - gridTop).clamp(1.0, double.infinity);
    final gridLeft = _horizontalPadding;
    final gridRight = size.width - _horizontalPadding;
    final gridWidth = (gridRight - gridLeft).clamp(1.0, double.infinity);
    final fretSpacing = gridHeight / _fretCount;

    final stringPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;

    final fretPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    final nutPaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.85)
      ..strokeWidth = 3.5;

    // Nut
    canvas.drawLine(
      Offset(gridLeft, gridTop),
      Offset(gridRight, gridTop),
      nutPaint,
    );

    // Fret wires
    for (var fret = 1; fret <= _fretCount; fret++) {
      final y = gridTop + fret * fretSpacing;
      canvas.drawLine(
        Offset(gridLeft, y),
        Offset(gridRight, y),
        fretPaint,
      );
    }

    // Strings (6 → 1, left to right)
    for (var i = 0; i < 6; i++) {
      final x = gridLeft + (gridWidth / 5) * i;
      canvas.drawLine(
        Offset(x, gridTop),
        Offset(x, gridBottom),
        stringPaint,
      );
    }

    // Open / muted markers above the nut
    for (var i = 0; i < 6; i++) {
      final stringNumber = 6 - i;
      final x = gridLeft + (gridWidth / 5) * i;
      final char = fingering[i].toLowerCase();

      if (char == 'x') {
        _drawMarker(
          canvas,
          Offset(x, _markerRowHeight * 0.45),
          'X',
          AppColors.error,
        );
      } else if (char == '0') {
        final openColor = liveNoteColor(
          liveStatuses?[stringNumber],
          AppColors.success,
        );
        _drawMarker(
          canvas,
          Offset(x, _markerRowHeight * 0.45),
          'O',
          openColor,
        );
      } else {
        final note = chord.noteForString(stringNumber);
        if (note != null && note.fret == 0) {
          final openColor = liveNoteColor(
            liveStatuses?[stringNumber],
            AppColors.success,
          );
          _drawMarker(
            canvas,
            Offset(x, _markerRowHeight * 0.45),
            'O',
            openColor,
          );
        }
      }
    }

    // Finger dots on frets
    for (final note in chord.notes) {
      if (note.fret < 1) continue;

      final stringIndex = 6 - note.string;
      final x = gridLeft + (gridWidth / 5) * stringIndex;
      final y = gridTop + (note.fret - 0.5) * fretSpacing;

      final dotRadius = (fretSpacing * 0.32).clamp(6.0, 11.0);
      final dotColor = liveNoteColor(liveStatuses?[note.string], accent);
      final isLiveGood = liveStatuses?[note.string] == NoteStatus.detected;
      final isLiveBad = liveStatuses?[note.string] == NoteStatus.missing ||
          liveStatuses?[note.string] == NoteStatus.weak;

      final glowPaint = Paint()
        ..color = dotColor.withValues(
          alpha: isLiveGood ? 0.55 : (isLiveBad ? 0.4 : 0.25),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          isLiveGood ? 10 : 6,
        );
      canvas.drawCircle(
        Offset(x, y),
        dotRadius + (isLiveGood ? 4 : 2),
        glowPaint,
      );

      final dotPaint = Paint()..color = dotColor;
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);

      final label = note.fret.toString();
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isLiveBad ? Colors.white : AppColors.onPrimaryDark,
            fontSize: dotRadius * 1.1,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  void _drawMarker(Canvas canvas, Offset center, String label, Color color) {
    if (label == 'O') {
      final ringPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(center, 6, ringPaint);
      return;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter oldDelegate) {
    return oldDelegate.chord.id != chord.id ||
        oldDelegate.accent != accent ||
        !_sameStatuses(oldDelegate.liveStatuses, liveStatuses);
  }

  static bool _sameStatuses(
    Map<int, NoteStatus>? a,
    Map<int, NoteStatus>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
