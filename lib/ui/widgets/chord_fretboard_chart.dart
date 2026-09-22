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

/// Short note name for string columns (E A D G B e).
String diagramStringNote(int stringNumber) {
  return switch (stringNumber) {
    6 => 'E',
    5 => 'A',
    4 => 'D',
    3 => 'G',
    2 => 'B',
    1 => 'e',
    _ => '?',
  };
}

/// Framed fretboard chart — scales to available space (no overflow).
class ChordFretboardFrame extends StatelessWidget {
  const ChordFretboardFrame({
    super.key,
    required this.chord,
    this.height,
    this.aspectRatio = 1.15,
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

    // Fill Expanded/Flexible parents; fall back to aspect ratio in scroll layouts.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight &&
            constraints.maxHeight.isFinite) {
          return SizedBox(
            width: double.infinity,
            height: constraints.maxHeight,
            child: viewport,
          );
        }
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: viewport,
        );
      },
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

/// Compact legend for O / X / finger numbers.
class ChordFretboardLegend extends StatelessWidget {
  const ChordFretboardLegend({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        _LegendDot(color: AppColors.success, label: 'פתוח (O)'),
        _LegendDot(color: AppColors.error, label: 'מושתק (X)'),
        _LegendDot(
          color: accent,
          label: '1 מורה · 2 אמה · 3 קמיצה · 4 זרת',
          filled: true,
        ),
        _LegendDot(
          color: accent,
          label: 'בארה (פס)',
          filled: true,
          wide: true,
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.filled = false,
    this.wide = false,
  });

  final Color color;
  final String label;
  final bool filled;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: wide ? 28 : 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: wide ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: wide ? BorderRadius.circular(7) : null,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.5),
          ),
          child: filled
              ? Text(
                  wide ? '1' : '1',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onPrimaryDark,
                    height: 1,
                  ),
                )
              : null,
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

class _BarreSpan {
  const _BarreSpan({
    required this.fret,
    required this.finger,
    required this.minStringIndex,
    required this.maxStringIndex,
    required this.notes,
  });

  final int fret;
  final int finger;
  final int minStringIndex;
  final int maxStringIndex;
  final List<ChordNote> notes;
}

/// Classic guitar chord box — finger numbers, side frets, sliding window.
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
  static const _markerRowHeight = 22.0;
  static const _stringLabelHeight = 16.0;
  /// Room for absolute fret numbers, clear of finger dots / glow.
  static const _fretLabelWidth = 30.0;
  static const _fretLabelGap = 8.0;
  static const _horizontalPadding = 6.0;
  static const _bottomPadding = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fingering = chord.fingering.padRight(6, 'x');
    final baseFret = chord.diagramBaseFret;
    final showNut = baseFret == 1;

    final gridTop = _markerRowHeight;
    final gridBottom = size.height - _bottomPadding - _stringLabelHeight;
    final gridHeight = (gridBottom - gridTop).clamp(1.0, double.infinity);
    final gridLeft = _horizontalPadding;
    final gridRight =
        size.width - _horizontalPadding - _fretLabelWidth - _fretLabelGap;
    final gridWidth = (gridRight - gridLeft).clamp(1.0, double.infinity);
    final fretSpacing = gridHeight / _fretCount;
    final fretLabelX = gridRight + _fretLabelGap + _fretLabelWidth * 0.5;

    final stringPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;

    final fretPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    final nutPaint = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.85)
      ..strokeWidth = 3.5;

    // Top cap: nut or thin line when window starts mid-neck.
    if (showNut) {
      canvas.drawLine(
        Offset(gridLeft, gridTop),
        Offset(gridRight, gridTop),
        nutPaint,
      );
    } else {
      canvas.drawLine(
        Offset(gridLeft, gridTop),
        Offset(gridRight, gridTop),
        fretPaint,
      );
      // Base-fret badge in the RIGHT gutter (same row as X/O, clear of string 1).
      _drawText(
        canvas,
        'סריג $baseFret',
        Offset(fretLabelX, _markerRowHeight * 0.42),
        fontSize: 10,
        color: AppColors.amberBright,
        bold: true,
      );
    }

    // Fret wires + absolute fret numbers (right gutter, outside glow reach).
    for (var i = 1; i <= _fretCount; i++) {
      final y = gridTop + i * fretSpacing;
      canvas.drawLine(
        Offset(gridLeft, y),
        Offset(gridRight, y),
        fretPaint,
      );

      final absoluteFret = baseFret + i - 1;
      final labelY = gridTop + (i - 0.5) * fretSpacing;
      _drawText(
        canvas,
        '$absoluteFret',
        Offset(fretLabelX, labelY),
        fontSize: 12,
        color: AppColors.textMuted,
        bold: i == 1 && !showNut,
      );
    }

    // Strings (6 → 1, left to right).
    for (var i = 0; i < 6; i++) {
      final x = gridLeft + (gridWidth / 5) * i;
      canvas.drawLine(
        Offset(x, gridTop),
        Offset(x, gridBottom),
        stringPaint,
      );
    }

    // String identity under each string: number + note (E A D G B e).
    for (var i = 0; i < 6; i++) {
      final stringNumber = 6 - i;
      final x = gridLeft + (gridWidth / 5) * i;
      _drawText(
        canvas,
        '$stringNumber·${diagramStringNote(stringNumber)}',
        Offset(x, gridBottom + _stringLabelHeight * 0.55),
        fontSize: 9,
        color: AppColors.textMuted,
        bold: true,
      );
    }

    // Open / muted markers above the nut.
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
      } else if (char == '0' ||
          (chord.noteForString(stringNumber)?.fret == 0)) {
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

    final barres = _detectBarres();
    final barreNoteKeys = <String>{
      for (final barre in barres)
        for (final note in barre.notes) _noteKey(note),
    };

    // Continuous barre bars (same fret + finger across ≥2 strings).
    for (final barre in barres) {
      final relative = barre.fret - baseFret + 1;
      if (relative < 1 || relative > _fretCount) continue;

      final y = gridTop + (relative - 0.5) * fretSpacing;
      final leftX = gridLeft + (gridWidth / 5) * barre.minStringIndex;
      final rightX = gridLeft + (gridWidth / 5) * barre.maxStringIndex;
      final barHeight = (fretSpacing * 0.42).clamp(10.0, 16.0);
      final barRadius = Radius.circular(barHeight / 2);
      final rect = Rect.fromLTRB(
        leftX - barHeight * 0.35,
        y - barHeight / 2,
        rightX + barHeight * 0.35,
        y + barHeight / 2,
      );

      final barreColor = _barreColor(barre);
      final glowPaint = Paint()
        ..color = barreColor.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(2), barRadius), glowPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, barRadius),
        Paint()..color = barreColor,
      );

      final fingerLabel = barre.finger.toString();
      final textPainter = TextPainter(
        text: TextSpan(
          text: fingerLabel,
          style: TextStyle(
            color: AppColors.onPrimaryDark,
            fontSize: barHeight * 0.85,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          rect.center.dx - textPainter.width / 2,
          rect.center.dy - textPainter.height / 2,
        ),
      );
    }

    // Finger dots for non-barre fretted notes (higher frets / other fingers).
    for (final note in chord.notes) {
      if (note.fret < 1) continue;
      if (barreNoteKeys.contains(_noteKey(note))) continue;
      final relative = note.fret - baseFret + 1;
      if (relative < 1 || relative > _fretCount) continue;

      final stringIndex = 6 - note.string;
      final x = gridLeft + (gridWidth / 5) * stringIndex;
      final y = gridTop + (relative - 0.5) * fretSpacing;

      // Keep dots inside the grid so glow does not cover side fret labels.
      final dotRadius = (fretSpacing * 0.28).clamp(6.0, 10.0);
      final glowExtra = stringIndex >= 5 ? 1.0 : 2.0;
      final dotColor = liveNoteColor(liveStatuses?[note.string], accent);
      final isLiveGood = liveStatuses?[note.string] == NoteStatus.detected;
      final isLiveBad = liveStatuses?[note.string] == NoteStatus.missing ||
          liveStatuses?[note.string] == NoteStatus.weak;

      final glowPaint = Paint()
        ..color = dotColor.withValues(
          alpha: isLiveGood ? 0.45 : (isLiveBad ? 0.35 : 0.2),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          isLiveGood ? 8 : 5,
        );
      canvas.drawCircle(
        Offset(x, y),
        dotRadius + (isLiveGood ? glowExtra + 1 : glowExtra),
        glowPaint,
      );

      canvas.drawCircle(Offset(x, y), dotRadius, Paint()..color = dotColor);

      final fingerLabel = (note.finger ?? _fallbackFinger(note)).toString();
      final textPainter = TextPainter(
        text: TextSpan(
          text: fingerLabel,
          style: TextStyle(
            color: isLiveBad ? Colors.white : AppColors.onPrimaryDark,
            fontSize: dotRadius * 1.15,
            fontWeight: FontWeight.bold,
            height: 1,
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

  String _noteKey(ChordNote note) => '${note.string}:${note.fret}';

  /// Groups of ≥2 notes sharing fret + finger → one continuous barre bar.
  List<_BarreSpan> _detectBarres() {
    final groups = <String, List<ChordNote>>{};
    for (final note in chord.notes) {
      if (note.fret < 1) continue;
      final finger = note.finger ?? _fallbackFinger(note);
      final key = '${note.fret}:$finger';
      groups.putIfAbsent(key, () => []).add(note);
    }

    final barres = <_BarreSpan>[];
    for (final entry in groups.entries) {
      final notes = entry.value;
      if (notes.length < 2) continue;
      final parts = entry.key.split(':');
      final fret = int.parse(parts[0]);
      final finger = int.parse(parts[1]);
      var minIndex = 5;
      var maxIndex = 0;
      for (final note in notes) {
        final index = 6 - note.string;
        if (index < minIndex) minIndex = index;
        if (index > maxIndex) maxIndex = index;
      }
      // Require a real span across strings (not two stacked on one string).
      if (maxIndex <= minIndex) continue;
      barres.add(
        _BarreSpan(
          fret: fret,
          finger: finger,
          minStringIndex: minIndex,
          maxStringIndex: maxIndex,
          notes: notes,
        ),
      );
    }
    return barres;
  }

  Color _barreColor(_BarreSpan barre) {
    NoteStatus? worst;
    for (final note in barre.notes) {
      final status = liveStatuses?[note.string];
      if (status == NoteStatus.missing || status == NoteStatus.weak) {
        return liveNoteColor(status, accent);
      }
      if (status == NoteStatus.detected) {
        worst ??= status;
      }
    }
    return liveNoteColor(worst, accent);
  }

  /// When JSON omits finger, prefer lower frets → lower finger numbers.
  int _fallbackFinger(ChordNote note) {
    final fretted = chord.notes.where((n) => n.fret > 0).toList()
      ..sort((a, b) {
        final byFret = a.fret.compareTo(b.fret);
        if (byFret != 0) return byFret;
        return b.string.compareTo(a.string);
      });
    final index = fretted.indexWhere(
      (n) => n.string == note.string && n.fret == note.fret,
    );
    return (index < 0 ? 0 : index % 4) + 1;
  }

  void _drawText(
    Canvas canvas,
    String label,
    Offset center, {
    required double fontSize,
    required Color color,
    bool bold = false,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: 1,
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
