import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chord_definition.dart';
import '../models/strumming_pattern.dart';
import '../services/progress_service.dart';
import '../services/strum_pattern_catalog_service.dart';
import 'app_theme.dart';
import 'navigation/app_page_route.dart';
import 'strum_lesson_screen.dart';
import 'widgets/strumming_help_sheet.dart';
import 'widgets/strumming_pattern_widget.dart';

/// Strumming hub: pick a pattern → animated lesson, rhythm game, example song.
class StrummingLearningScreen extends StatefulWidget {
  const StrummingLearningScreen({super.key, required this.catalog});

  final ChordCatalog catalog;

  @override
  State<StrummingLearningScreen> createState() =>
      _StrummingLearningScreenState();
}

class _StrummingLearningScreenState extends State<StrummingLearningScreen> {
  final _service = StrumPatternCatalogService();
  List<StrummingPattern>? _patterns;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final list = await _service.load();
      if (!mounted) return;
      setState(() {
        _patterns = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Stars over the three game speeds of a pattern (0–9).
  int _patternStars(StrummingPattern p) {
    var total = 0;
    for (var i = 0; i < 3; i++) {
      total += ProgressService.instance.gameStars('pattern:${p.id}:$i');
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('לימוד פריטות'),
        actions: [
          IconButton(
            tooltip: 'מה אומרים הסימנים?',
            onPressed: () => unawaited(showStrummingHelpSheet(context)),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: AppColors.error)),
        ),
      );
    }
    final patterns = _patterns;
    if (patterns == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: ProgressService.instance,
      builder: (context, _) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: patterns.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'כל דפוס: 🎬 אנימציה שמראה איך פורטים  →  🎮 משחק קצב ב-3 מהירויות  →  🎵 שיר לדוגמה.',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            );
          }
          final pattern = patterns[index - 1];
          return _PatternCard(
            pattern: pattern,
            stars: _patternStars(pattern),
            onTap: () {
              Navigator.of(context).push(
                AppPageRoute<void>(
                  page: StrumLessonScreen(
                    pattern: pattern,
                    chordCatalog: widget.catalog,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({
    required this.pattern,
    required this.stars,
    required this.onTap,
  });

  final StrummingPattern pattern;
  final int stars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = pattern.isArpeggio ? AppColors.violet : AppColors.turquoise;
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    pattern.isArpeggio
                        ? Icons.piano_rounded
                        : Icons.graphic_eq_rounded,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pattern.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    '$stars/9',
                    style: TextStyle(
                      color: stars > 0 ? AppColors.amberBright : AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Icon(
                    stars > 0 ? Icons.star_rounded : Icons.star_border_rounded,
                    color: stars > 0 ? AppColors.amberBright : AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
              if (pattern.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  pattern.description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              StrummingPatternWidget(pattern: pattern, compact: true),
              const SizedBox(height: 6),
              Text(
                '${pattern.defaultBpm} BPM',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
