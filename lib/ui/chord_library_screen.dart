import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/chord_audio_service.dart';
import '../models/chord_definition.dart';
import 'app_theme.dart';
import 'widgets/chord_fretboard_chart.dart';
import 'widgets/help_sheet.dart';

/// Chord catalog grid, filtered by difficulty / technique level.
class ChordLibraryScreen extends StatefulWidget {
  const ChordLibraryScreen({super.key, required this.catalog});

  final ChordCatalog catalog;

  @override
  State<ChordLibraryScreen> createState() => _ChordLibraryScreenState();
}

class _ChordLibraryScreenState extends State<ChordLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: ChordDifficultyLevels.max,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ספריית אקורדים'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 8, end: 12),
            child: Center(child: HelpButton(topic: HelpTopic.chordLibrary)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.turquoise,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.turquoise,
          tabs: [
            for (var level = ChordDifficultyLevels.min;
                level <= ChordDifficultyLevels.max;
                level++)
              Tab(
                height: 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ChordDifficultyLevels.labelFor(level),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      ChordDifficultyLevels.categoryFor(level),
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            for (var level = ChordDifficultyLevels.min;
                level <= ChordDifficultyLevels.max;
                level++)
              _DifficultyChordGrid(
                chords: widget.catalog.chordsForDifficulty(level),
                category: ChordDifficultyLevels.categoryFor(level),
                referenceA4Hz: widget.catalog.referenceA4Hz,
              ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyChordGrid extends StatelessWidget {
  const _DifficultyChordGrid({
    required this.chords,
    required this.category,
    required this.referenceA4Hz,
  });

  final List<ChordDefinition> chords;
  final String category;
  final double referenceA4Hz;

  @override
  Widget build(BuildContext context) {
    if (chords.isEmpty) {
      return Center(
        child: Text(
          'אין אקורדים ברמה זו עדיין',
          style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.8)),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              category,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final crossAxisCount = width >= 420 ? 3 : 2;

              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ChordGridCard(
                    chord: chords[index],
                    referenceA4Hz: referenceA4Hz,
                  ),
                  childCount: chords.length,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Compact grid tile with a fixed-height fretboard chart — no overflow.
class _ChordGridCard extends StatefulWidget {
  const _ChordGridCard({
    required this.chord,
    required this.referenceA4Hz,
  });

  final ChordDefinition chord;
  final double referenceA4Hz;

  @override
  State<_ChordGridCard> createState() => _ChordGridCardState();
}

class _ChordGridCardState extends State<_ChordGridCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    await _scaleController.reverse();
    await _scaleController.forward();
    if (!mounted) return;
    await _ChordDetailSheet.show(
      context,
      widget.chord,
      referenceA4Hz: widget.referenceA4Hz,
    );
  }

  void _playChord() {
    unawaited(
      ChordAudioService.instance.playChord(
        widget.chord,
        referenceA4Hz: widget.referenceA4Hz,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chord = widget.chord;
    final accent = chordAccentColor(chord);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: DecoratedBox(
        decoration: AppTheme.cardDecoration(
          borderColor: accent.withValues(alpha: 0.25),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            chord.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: accent == AppColors.amber
                                  ? AppColors.amberBright
                                  : AppColors.turquoise,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'השמע אקורד',
                        onPressed: _playChord,
                        icon: const Icon(Icons.volume_up_rounded, size: 18),
                        color: AppColors.turquoise,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                      Icon(
                        Icons.zoom_in_rounded,
                        size: 15,
                        color: AppColors.textMuted.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ChordFretboardFrame(
                      chord: chord,
                      accent: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet — enlarged fretboard only, no text list.
class _ChordDetailSheet extends StatelessWidget {
  const _ChordDetailSheet({
    required this.chord,
    required this.referenceA4Hz,
  });

  final ChordDefinition chord;
  final double referenceA4Hz;

  static Future<void> show(
    BuildContext context,
    ChordDefinition chord, {
    required double referenceA4Hz,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChordDetailSheet(
        chord: chord,
        referenceA4Hz: referenceA4Hz,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = chordAccentColor(chord);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.32,
        maxChildSize: 0.75,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          chord.displayName,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: accent == AppColors.amber
                                ? AppColors.amberBright
                                : AppColors.turquoise,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'השמע אקורד',
                        onPressed: () {
                          unawaited(
                            ChordAudioService.instance.playChord(
                              chord,
                              referenceA4Hz: referenceA4Hz,
                            ),
                          );
                        },
                        icon: const Icon(Icons.volume_up_rounded),
                        color: AppColors.turquoise,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${ChordDifficultyLevels.labelFor(chord.difficulty)} · ${chord.category}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ChordFretboardFrame(
                    chord: chord,
                    accent: accent,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 12),
                  ChordFretboardLegend(accent: accent),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
