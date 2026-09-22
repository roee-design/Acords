import 'package:flutter/material.dart';

import '../models/chord_definition.dart';
import 'app_theme.dart';
import 'chord_blitz_screen.dart';
import 'navigation/app_page_route.dart';
import 'practice_screen.dart';
import 'widgets/help_sheet.dart';

/// Entry point for choosing a practice mode.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.catalog,
  });

  final ChordCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: const HelpButton(topic: HelpTopic.home),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.turquoise.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AppColors.turquoise.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.turquoise.withValues(alpha: 0.15),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 40,
                        color: AppColors.turquoise,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Chord Trainer',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'תרגל אקורדים עם משוב בזמן אמת',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const Text(
                    'בחר מצב אימון',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'אימון ממוקד לפי רמת קושי מהספרייה',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  _ModeCard(
                    icon: Icons.music_note_rounded,
                    accentColor: AppColors.turquoise,
                    title: 'אימון אקורד בודד',
                    description:
                        'בחר אקורד לפי רמה וקבל משוב בזמן אמת על כל מיתר',
                    badge: 'מדויק',
                    onTap: () {
                      Navigator.of(context).push(
                        AppPageRoute<void>(
                          page: PracticeScreen(catalog: catalog),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _ModeCard(
                    icon: Icons.flash_on_rounded,
                    accentColor: AppColors.amber,
                    title: 'אתגר האקורדים',
                    description:
                        '30 שניות — נגנו אקורדים מהר, צברו ניקוד ורצפים',
                    badge: 'משחק',
                    onTap: () {
                      Navigator.of(context).push(
                        AppPageRoute<void>(
                          page: ChordBlitzScreen(catalog: catalog),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(
                      borderColor: AppColors.textMuted.withValues(alpha: 0.2),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.tips_and_updates_outlined,
                          color: AppColors.amberBright,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'טיפ: בספריית האקורדים תמצאו חלוקה ל־5 רמות קושי. התחילו ברמה 1 והתקדמו בהדרגה.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.description,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String description;
  final String badge;
  final VoidCallback onTap;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _pressController.reverse();
    await _pressController.forward();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Card(
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(widget.icon, size: 32, color: widget.accentColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: widget.accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.badge,
                              style: TextStyle(
                                color: widget.accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
