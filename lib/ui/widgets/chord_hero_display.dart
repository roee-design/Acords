import 'package:flutter/material.dart';

import '../../models/chord_definition.dart';
import '../app_theme.dart';
import 'chord_fretboard_chart.dart';
import 'confetti_burst.dart';

/// Large chord name card with optional fretboard diagram, glow and confetti.
class ChordHeroDisplay extends StatelessWidget {
  const ChordHeroDisplay({
    super.key,
    required this.chordName,
    required this.label,
    this.chord,
    this.successGlow = false,
    this.showConfetti = false,
    this.confettiTick = 0,
    this.subtitle,
    this.showFretboard = true,
    this.compact = false,
  });

  final String chordName;
  final String label;
  final ChordDefinition? chord;
  final bool successGlow;
  final bool showConfetti;
  final int confettiTick;
  final String? subtitle;
  final bool showFretboard;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = chord != null
        ? chordAccentColor(chord!)
        : AppColors.turquoise;
    final radius = compact ? 16.0 : 22.0;
    final pad = compact
        ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
        : const EdgeInsets.fromLTRB(24, 24, 24, 20);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: successGlow
                ? [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.75),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: AppColors.amberBright.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: compact ? 10 : 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Card(
            margin: EdgeInsets.zero,
            color: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: successGlow
                    ? AppColors.success
                    : accent.withValues(alpha: 0.45),
                width: successGlow ? 2.5 : 1.5,
              ),
            ),
            child: Padding(
              padding: pad,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      fontSize: compact ? 12 : 14,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: Text(
                      chordName,
                      key: ValueKey(chordName),
                      style: TextStyle(
                        fontSize: compact ? 36 : 52,
                        fontWeight: FontWeight.bold,
                        color: successGlow
                            ? AppColors.success
                            : AppColors.textPrimary,
                        height: 1,
                        shadows: successGlow
                            ? [
                                Shadow(
                                  color: AppColors.success.withValues(alpha: 0.8),
                                  blurRadius: 16,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                  if (chord != null && showFretboard) ...[
                    const SizedBox(height: 16),
                    ChordFretboardFrame(
                      chord: chord!,
                      accent: accent,
                    ),
                  ] else if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showConfetti)
          Positioned(
            top: 20,
            child: ConfettiBurst(key: ValueKey(confettiTick)),
          ),
      ],
    );
  }
}
