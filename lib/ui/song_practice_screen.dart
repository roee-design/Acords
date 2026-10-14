import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chord_definition.dart';
import '../models/song_definition.dart';
import '../services/progress_service.dart';
import '../services/song_catalog_service.dart';
import 'app_theme.dart';
import 'navigation/app_page_route.dart';
import 'song_player_screen.dart';

enum _LanguageFilter { all, hebrew, english }

/// Song library — search, language / genre / level filters, grouped by genre.
/// Also used as the "שירים" bottom-nav tab.
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
  final TextEditingController _search = TextEditingController();

  SongCatalog? _songs;
  String? _loadError;
  var _language = _LanguageFilter.all;
  String? _genre; // null = all
  var _difficulty = 0; // 0 = all

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_loadSongs());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    final query = _search.text.trim().toLowerCase();
    return [
      for (final s in _songs?.songs ?? const <SongDefinition>[])
        if ((_language == _LanguageFilter.all ||
                (_language == _LanguageFilter.hebrew) == s.isHebrew) &&
            (_genre == null || s.genre == _genre) &&
            (_difficulty == 0 || s.difficulty == _difficulty) &&
            (query.isEmpty || s.searchText.contains(query)))
          s,
    ];
  }

  /// Genres present in the catalog, in [SongGenres] order.
  List<String> get _genresInCatalog {
    final present = {for (final s in _songs?.songs ?? const []) s.genre};
    return [
      for (final g in SongGenres.labels.keys)
        if (present.contains(g)) g,
      for (final g in present)
        if (!SongGenres.labels.containsKey(g)) g,
    ];
  }

  void _openSong(SongDefinition song) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      AppPageRoute<void>(
        page: SongPlayerScreen(
          song: song,
          chordCatalog: widget.catalog,
        ),
      ),
    );
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _language = _LanguageFilter.all;
      _genre = null;
      _difficulty = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('שירים'),
        automaticallyImplyLeading: !widget.asTab,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'חיפוש לפי שם, אמן או מילים…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'נקה',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _search.clear,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_LanguageFilter>(
                segments: const [
                  ButtonSegment(
                    value: _LanguageFilter.all,
                    label: Text('הכל'),
                  ),
                  ButtonSegment(
                    value: _LanguageFilter.hebrew,
                    label: Text('עברית'),
                  ),
                  ButtonSegment(
                    value: _LanguageFilter.english,
                    label: Text('אנגלית'),
                  ),
                ],
                selected: {_language},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _language = v.first),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'כל הז׳אנרים',
                    color: AppColors.turquoise,
                    selected: _genre == null,
                    onTap: () => setState(() => _genre = null),
                  ),
                  for (final g in _genresInCatalog)
                    _FilterChip(
                      label: SongGenres.labelFor(g),
                      icon: AppTheme.genreStyle(g).$2,
                      color: AppTheme.genreStyle(g).$1,
                      selected: _genre == g,
                      onTap: () =>
                          setState(() => _genre = _genre == g ? null : g),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChip(
                    label: 'כל הרמות',
                    color: AppColors.amberBright,
                    selected: _difficulty == 0,
                    onTap: () => setState(() => _difficulty = 0),
                  ),
                  for (var level = 1; level <= 5; level++)
                    _FilterChip(
                      label: 'רמה $level',
                      color: AppColors.amberBright,
                      selected: _difficulty == level,
                      onTap: () => setState(
                        () => _difficulty = _difficulty == level ? 0 : level,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildBody()),
          ],
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            const Text(
              'לא נמצאו שירים',
              style: TextStyle(color: AppColors.textMuted),
            ),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('נקה סינון'),
            ),
          ],
        ),
      );
    }

    // Group by genre (catalog order inside each group: easiest first).
    final groups = <String, List<SongDefinition>>{};
    for (final g in _genresInCatalog) {
      final songs = list.where((s) => s.genre == g).toList()
        ..sort((a, b) {
          final byLevel = a.difficulty.compareTo(b.difficulty);
          return byLevel != 0 ? byLevel : a.title.compareTo(b.title);
        });
      if (songs.isNotEmpty) groups[g] = songs;
    }

    return ListenableBuilder(
      listenable: ProgressService.instance,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${list.length} שירים',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          for (final entry in groups.entries) ...[
            _GenreHeader(genre: entry.key, count: entry.value.length),
            for (final song in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SongTile(song: song, onTap: () => _openSong(song)),
              ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        avatar: icon == null
            ? null
            : Icon(icon, size: 16, color: selected ? AppColors.background : color),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          color: selected ? AppColors.background : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        selectedColor: color,
        backgroundColor: color.withValues(alpha: 0.12),
        side: BorderSide(color: color.withValues(alpha: selected ? 1 : 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _GenreHeader extends StatelessWidget {
  const _GenreHeader({required this.genre, required this.count});

  final String genre;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = AppTheme.genreStyle(genre);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            SongGenres.labelFor(genre),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: color.withValues(alpha: 0.25)),
          ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({required this.song, required this.onTap});

  final SongDefinition song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = AppTheme.genreStyle(song.genre);
    final progress = ProgressService.instance.song(song.id);
    final stars = ProgressService.instance.gameStars('song:${song.id}');
    final hasLyrics =
        !song.instrumental && song.lines.any((l) => l.text.trim().isNotEmpty);

    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Tag(song.isHebrew ? 'עברית' : 'English'),
                        _Tag('רמה ${song.difficulty}'),
                        _Tag('${song.bpm} BPM'),
                        _Tag(
                          hasLyrics ? 'מילים מלאות' : 'אקורדים בלבד',
                          color: hasLyrics ? AppColors.turquoise : null,
                        ),
                        if (progress.isCompleted)
                          const _Tag('✓ נוגן', color: AppColors.success),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Icon(
                          i < stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 14,
                          color: i < stars
                              ? AppColors.amberBright
                              : AppColors.textMuted.withValues(alpha: 0.4),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Icon(Icons.play_circle_fill_rounded, color: color, size: 30),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
