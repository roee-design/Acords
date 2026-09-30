import 'package:flutter/material.dart';

import '../../models/strumming_pattern.dart';
import '../app_theme.dart';

/// Displays a strumming / arpeggio sequence with an optional active highlight.
class StrummingPatternWidget extends StatelessWidget {
  const StrummingPatternWidget({
    super.key,
    required this.pattern,
    this.activeIndex,
    this.compact = false,
  });

  final StrummingPattern pattern;

  /// Index into [pattern.events] to highlight (null = none).
  final int? activeIndex;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final events = pattern.events;
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    final slotW = compact ? 36.0 : 48.0;
    final slotH = compact ? 52.0 : 64.0;
    final fontSize = compact ? 20.0 : 26.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pattern.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              pattern.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < events.length; i++) ...[
                if (i > 0 &&
                    pattern.subdivision > 1 &&
                    i % pattern.subdivision == 0)
                  Container(
                    width: 1,
                    height: slotH * 0.55,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: AppColors.textMuted.withValues(alpha: 0.35),
                  ),
                _EventSlot(
                  event: events[i],
                  width: slotW,
                  height: slotH,
                  fontSize: fontSize,
                  active: activeIndex == i,
                  beatNumber: pattern.subdivision <= 1
                      ? (i + 1)
                      : (i % pattern.subdivision == 0
                          ? (i ~/ pattern.subdivision) + 1
                          : null),
                  andLabel: pattern.subdivision == 2 &&
                      i % pattern.subdivision == 1,
                ),
              ],
            ],
          ),
        ),
        if (pattern.subdivision == 2 && !pattern.isArpeggio)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'ספירה: 1 · ו · 2 · ו · 3 · ו · 4 · ו',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (pattern.isArpeggio)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'ארפג׳ו — מיתרים בודדים (p / i / m / a או 6–1)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _EventSlot extends StatelessWidget {
  const _EventSlot({
    required this.event,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.active,
    this.beatNumber,
    this.andLabel = false,
  });

  final PatternEvent event;
  final double width;
  final double height;
  final double fontSize;
  final bool active;
  final int? beatNumber;
  final bool andLabel;

  Color get _color {
    if (active) return AppColors.amberBright;
    return switch (event.kind) {
      PatternEventKind.down => AppColors.turquoise,
      PatternEventKind.up => AppColors.turquoiseDim,
      PatternEventKind.mute => AppColors.amber,
      PatternEventKind.pause => AppColors.textMuted.withValues(alpha: 0.55),
      PatternEventKind.finger => const Color(0xFFA78BFA),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: active
            ? AppColors.amber.withValues(alpha: 0.22)
            : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppColors.amberBright
              : AppColors.textMuted.withValues(alpha: 0.2),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.amber.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            event.symbol,
            style: TextStyle(
              color: _color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (beatNumber != null) ...[
            const SizedBox(height: 4),
            Text(
              '$beatNumber',
              style: TextStyle(
                color: active
                    ? AppColors.amberBright
                    : AppColors.textMuted.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (andLabel) ...[
            const SizedBox(height: 4),
            Text(
              'ו',
              style: TextStyle(
                color: active
                    ? AppColors.amberBright
                    : AppColors.textMuted.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (event.kind == PatternEventKind.finger &&
              event.stringNumber != null) ...[
            const SizedBox(height: 4),
            Text(
              'מ${event.stringNumber}',
              style: TextStyle(
                color: active
                    ? AppColors.amberBright
                    : AppColors.textMuted.withValues(alpha: 0.75),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
