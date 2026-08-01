import 'package:flutter/material.dart';

import '../models/chord_definition.dart';
import 'app_theme.dart';
import 'widgets/chord_fretboard_chart.dart';
import 'widgets/help_sheet.dart';

/// Ordered display of the chord catalog in a responsive grid.
class ChordLibraryScreen extends StatelessWidget {
  const ChordLibraryScreen({super.key, required this.catalog});

  final ChordCatalog catalog;

  static const _displayOrder = [
    'c_major',
    'd_major',
    'e_major',
    'g_major',
    'a_major',
    'a_minor',
    'e_minor',
    'd_minor',
    'f_major',
    'b_major',
    'b_minor',
    'c_7',
    'g_7',
    'd_7',
    'e_7',
    'a_7',
  ];

  List<ChordDefinition> get _orderedChords {
    final byId = {for (final c in catalog.chords) c.id: c};
    return _displayOrder
        .map((id) => byId[id])
        .whereType<ChordDefinition>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final chords = _orderedChords;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ספריית אקורדים'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 8, end: 12),
            child: Center(child: HelpButton(topic: HelpTopic.chordLibrary)),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  'לחץ על אקורד לצפייה בדיאגרמת הסריגים',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final crossAxisCount = width >= 400 ? 3 : 2;

                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.88,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _ChordGridCard(chord: chords[index]),
                      childCount: chords.length,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact grid tile with a fixed-height fretboard chart — no overflow.
class _ChordGridCard extends StatefulWidget {
  const _ChordGridCard({required this.chord});

  final ChordDefinition chord;

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
    await _ChordDetailSheet.show(context, widget.chord);
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
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
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: accent == AppColors.amber
                                ? AppColors.amberBright
                                : AppColors.turquoise,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.zoom_in_rounded,
                        size: 16,
                        color: AppColors.textMuted.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
  const _ChordDetailSheet({required this.chord});

  final ChordDefinition chord;

  static Future<void> show(BuildContext context, ChordDefinition chord) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChordDetailSheet(chord: chord),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = chordAccentColor(chord);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.48,
        minChildSize: 0.32,
        maxChildSize: 0.72,
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
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
