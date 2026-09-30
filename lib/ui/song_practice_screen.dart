import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chord_definition.dart';
import '../models/song_definition.dart';
import '../services/song_catalog_service.dart';
import 'app_theme.dart';
import 'navigation/app_page_route.dart';
import 'song_player_screen.dart';

/// Song library — free player entry (also used as bottom-nav tab).
class SongPracticeScreen extends StatefulWidget {
  const SongPracticeScreen({
    super.key,
    required this.catalog,
    this.asTab = false,
  });

  final ChordCatalog catalog;

  /// When true, hides the back-capable AppBar title chrome used for push routes.
  final bool asTab;

  @override
  State<SongPracticeScreen> createState() => _SongPracticeScreenState();
}

class _SongPracticeScreenState extends State<SongPracticeScreen> {
  final SongCatalogService _songService = SongCatalogService();

  SongCatalog? _songs;
  String? _loadError;
  var _selectedDifficulty = 0; // 0 = all

  @override
  void initState() {
    super.initState();
    unawaited(_loadSongs());
  }

  Future<void> _loadSongs() async {
    try {
      final catalog = await _songService.load();
      if (!mounted) return;
      setState(() {
        _songs = catalog;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  List<SongDefinition> get _filtered {
    final all = _songs?.songs ?? const [];
    if (_selectedDifficulty == 0) return List.of(all);
    return all.where((s) => s.difficulty == _selectedDifficulty).toList();
  }

  void _openSong(SongDefinition song) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        page: SongPlayerScreen(
          song: song,
          chordCatalog: widget.catalog,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('שירים'),
        automaticallyImplyLeading: !widget.asTab,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'נגן חופשי — אקורדים, BPM, פריטה ומילים (כשזמינות)',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('הכל'),
                    selected: _selectedDifficulty == 0,
                    onSelected: (_) =>
                        setState(() => _selectedDifficulty = 0),
                  ),
                  for (var level = 1; level <= 5; level++)
                    ChoiceChip(
                      label: Text('רמה $level'),
                      selected: _selectedDifficulty == level,
                      onSelected: (_) =>
                          setState(() => _selectedDifficulty = level),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'שגיאה בטעינת שירים',
              style: TextStyle(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(_loadSongs()),
              child: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }

    if (_songs == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'אין שירים בסינון זה',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final song = list[index];
        return Material(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openSong(song),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.turquoise.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.turquoise.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      song.instrumental
                          ? Icons.grid_on_rounded
                          : Icons.menu_book_rounded,
                      color: AppColors.turquoise,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            song.artist,
                            '${song.bpm} BPM',
                            if (song.instrumental) 'אימון מנגינה',
                            if (song.publicDomain) 'נחלת הכלל',
                            if (song.rtl) 'עברית',
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.turquoise,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
