import 'package:flutter/material.dart';

import '../../models/chord_definition.dart';
import '../../models/song_definition.dart';
import '../app_theme.dart';

/// Song line: lyrics under chords, or empty bars `| C | G |` for instrumental.
class SongLyricLineView extends StatelessWidget {
  const SongLyricLineView({
    super.key,
    required this.line,
    required this.chordCatalog,
    required this.rtl,
    required this.instrumental,
    this.activeSegment,
    this.completedThrough = -1,
  });

  final SongLine line;
  final ChordCatalog chordCatalog;
  final bool rtl;
  final bool instrumental;
  final int? activeSegment;
  final int completedThrough;

  @override
  Widget build(BuildContext context) {
    if (instrumental) {
      return _InstrumentalBars(
        line: line,
        chordCatalog: chordCatalog,
        activeSegment: activeSegment,
        completedThrough: completedThrough,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Wrap(
          spacing: 6,
          runSpacing: 12,
          alignment: WrapAlignment.start,
          children: [
            for (var i = 0; i < line.segments.length; i++)
              _ChordLyricCell(
                segment: line.segments[i],
                chordCatalog: chordCatalog,
                rtl: rtl,
                isActive: activeSegment == i,
                isDone: i <= completedThrough,
              ),
          ],
        ),
      ),
    );
  }
}

/// Empty musical bars with chords above — no fake lyrics.
class _InstrumentalBars extends StatelessWidget {
  const _InstrumentalBars({
    required this.line,
    required this.chordCatalog,
    required this.activeSegment,
    required this.completedThrough,
  });

  final SongLine line;
  final ChordCatalog chordCatalog;
  final int? activeSegment;
  final int completedThrough;

  @override
  Widget build(BuildContext context) {
    final segs = line.segments
        .where((s) => s.chordId != null && s.chordId!.isNotEmpty)
        .toList();
    if (segs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                '|',
                style: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
              for (var i = 0; i < segs.length; i++) ...[
                _BarCell(
                  chordName: chordCatalog
                          .chordById(segs[i].chordId!)
                          ?.displayName ??
                      segs[i].chordId!,
                  isActive: activeSegment == line.segments.indexOf(segs[i]),
                  isDone: line.segments.indexOf(segs[i]) <= completedThrough,
                ),
                Text(
                  '|',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarCell extends StatelessWidget {
  const _BarCell({
    required this.chordName,
    required this.isActive,
    required this.isDone,
  });

  final String chordName;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 72,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.amber.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(color: AppColors.amberBright, width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          Text(
            chordName,
            style: TextStyle(
              color: isActive
                  ? AppColors.amberBright
                  : (isDone ? AppColors.success : AppColors.turquoise),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.textMuted.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 10),
          Text(
            '·  ·  ·  ·',
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.45),
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChordLyricCell extends StatelessWidget {
  const _ChordLyricCell({
    required this.segment,
    required this.chordCatalog,
    required this.rtl,
    required this.isActive,
    required this.isDone,
  });

  final SongChordLyric segment;
  final ChordCatalog chordCatalog;
  final bool rtl;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final chordId = segment.chordId;
    final chordName = chordId == null
        ? ''
        : (chordCatalog.chordById(chordId)?.displayName ?? chordId);
    final lyric = segment.lyrics.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.amber.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(color: AppColors.amberBright, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment:
            rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (chordName.isNotEmpty)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                chordName,
                style: TextStyle(
                  color: isActive
                      ? AppColors.amberBright
                      : (isDone ? AppColors.success : AppColors.turquoise),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          if (lyric.isNotEmpty)
            Text(
              lyric,
              textAlign: rtl ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textPrimary.withValues(alpha: 0.92),
                fontSize: 20,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
  }
}
