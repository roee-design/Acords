import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/game_sound_service.dart';
import '../game/rhythm_chart.dart';
import '../models/chord_definition.dart';
import '../models/song_definition.dart';
import '../models/strumming_pattern.dart';
import '../services/progress_service.dart';
import '../services/song_catalog_service.dart';
import 'app_theme.dart';
import 'navigation/app_page_route.dart';
import 'rhythm_game_screen.dart';
import 'widgets/guitar_strum_animation.dart';
import 'widgets/strumming_pattern_widget.dart';

/// One strumming pattern, taught in three steps:
/// 1. watch an animated close-up of the hand on the guitar,
/// 2. play it in the rhythm game at three speeds (each unlocks the next),
/// 3. play an example song with the pattern.
class StrumLessonScreen extends StatefulWidget {
  const StrumLessonScreen({
    super.key,
    required this.pattern,
    required this.chordCatalog,
  });

  final StrummingPattern pattern;
  final ChordCatalog chordCatalog;

  @override
  State<StrumLessonScreen> createState() => _StrumLessonScreenState();
}

class _Level {
  const _Level(this.name, this.factor);
  final String name;
  final double factor;
}

const _levels = [
  _Level('איטי', 0.6),
  _Level('בינוני', 0.8),
  _Level('בקצב המקורי', 1.0),
];

class _StrumLessonScreenState extends State<StrumLessonScreen> {
  var _playing = true;
  var _closeUp = true;
  var _sound = true;
  var _speed = 0.6;
  var _slot = 0;
  SongDefinition? _exampleSong;

  StrummingPattern get _pattern => widget.pattern;

  List<String> get _chordIds => _pattern.practiceChordIds.isNotEmpty
      ? _pattern.practiceChordIds
      : const ['g_major', 'c_major', 'd_major', 'g_major'];

  ChordDefinition? get _demoChord =>
      widget.chordCatalog.chordById(_chordIds.first);

  @override
  void initState() {
    super.initState();
    final chord = _demoChord;
    if (chord != null) unawaited(GameSoundService.instance.prepare([chord]));
    unawaited(_loadExample());
  }

  @override
  void dispose() {
    unawaited(GameSoundService.instance.stopAll());
    super.dispose();
  }

  Future<void> _loadExample() async {
    final id = _pattern.exampleSongId;
    if (id == null) return;
    try {
      final songs = await SongCatalogService().load();
      if (!mounted) return;
      setState(() => _exampleSong = songs.byId(id));
    } catch (_) {}
  }

  void _onAnimationEvent(PatternEvent event) {
    if (!_sound) return;
    final chord = _demoChord;
    if (chord == null) return;
    final sounds = GameSoundService.instance;
    switch (event.kind) {
      case PatternEventKind.down:
        unawaited(sounds.playStrum(chord, down: true));
      case PatternEventKind.up:
        unawaited(sounds.playStrum(chord, down: false));
      case PatternEventKind.mute:
        unawaited(sounds.playMute());
      case PatternEventKind.finger:
        unawaited(sounds.playString(chord, event.stringNumber ?? 6));
      case PatternEventKind.pause:
        break;
    }
  }

  String _levelKey(int i) => 'pattern:${_pattern.id}:$i';

  bool _unlocked(int i) =>
      i == 0 || ProgressService.instance.gameStars(_levelKey(i - 1)) > 0;

  Future<void> _playLevel(int i) async {
    setState(() => _playing = false);
    final level = _levels[i];
    final bpm = (_pattern.defaultBpm * level.factor).round().clamp(40, 220);
    final stars = await Navigator.of(context).push<int>(
      AppPageRoute<int>(
        page: RhythmGameScreen(
          title: '${_pattern.name} · ${level.name}',
          subtitle: 'שלב ${i + 1} מתוך 3',
          chart: RhythmChart.forPattern(
            pattern: _pattern,
            chordIds: _chordIds,
            bpm: bpm,
          ),
          chordCatalog: widget.chordCatalog,
          progressKey: _levelKey(i),
        ),
      ),
    );
    if (stars != null && stars > 0) {
      ProgressService.instance.recordStrumStage(_pattern.id, i + 1);
    }
    if (mounted) setState(() {});
  }

  Future<void> _playSong() async {
    final song = _exampleSong;
    if (song == null) return;
    setState(() => _playing = false);
    final bpm = (song.bpm * 0.85).round().clamp(40, 200);
    final stars = await Navigator.of(context).push<int>(
      AppPageRoute<int>(
        page: RhythmGameScreen(
          title: song.title,
          subtitle: 'בפריטת «${_pattern.name}»',
          chart: RhythmChart.forSong(song: song, pattern: _pattern, bpm: bpm),
          chordCatalog: widget.chordCatalog,
          progressKey: 'song:${song.id}',
        ),
      ),
    );
    if (stars != null && stars > 0) {
      ProgressService.instance.recordSongCompleted(song.id);
    }
    if (mounted) setState(() {});
  }

  /// Plain-language explanation of the stroke currently shown.
  String _explain(PatternEvent e) {
    switch (e.kind) {
      case PatternEventKind.down:
        return '↓ למטה: מהמיתר העבה (למעלה) אל הדק, תנועה מפרק היד — לא מהכתף.';
      case PatternEventKind.up:
        return '↑ למעלה: חוזרים דרך 3–4 המיתרים הדקים בלבד, יד רפויה וקלה.';
      case PatternEventKind.mute:
        return '✕ השתקה: מניחים את כף היד על המיתרים ליד הגשר — "צ׳ק" קצר בלי צליל.';
      case PatternEventKind.pause:
        return '— הפסקה: היד ממשיכה לזוז בקצב באוויר, בלי לגעת במיתרים.';
      case PatternEventKind.finger:
        final label = e.fingerLabel ?? '';
        if (label == 'p') return 'p — אגודל: פורט את מיתר הבס של האקורד.';
        const fingers = {'i': 'מורה', 'm': 'אמה', 'a': 'קמיצה'};
        final finger = fingers[label] ?? '';
        return '$label — אצבע $finger: מושכת את מיתר ${e.stringNumber ?? ''} כלפי כף היד.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _pattern.events;
    final current = events.isEmpty ? null : events[_slot % events.length];
    final bpm = (_pattern.defaultBpm * _speed).round().clamp(30, 220);

    return Scaffold(
      appBar: AppBar(title: Text(_pattern.name)),
      body: ListenableBuilder(
        listenable: ProgressService.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            if (_pattern.description.isNotEmpty)
              Text(
                _pattern.description,
                style: const TextStyle(color: AppColors.textMuted, height: 1.35),
              ),
            const SizedBox(height: 12),
            const _StepTitle(number: 1, text: 'צפו איך זה נראה', color: AppColors.sky),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 10,
              child: GuitarStrumAnimation(
                pattern: _pattern,
                bpm: bpm,
                playing: _playing,
                closeUp: _closeUp,
                onEvent: _onAnimationEvent,
                onSlot: (i) {
                  if (mounted) setState(() => _slot = i);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filled(
                  tooltip: _playing ? 'עצור' : 'נגן',
                  onPressed: () => setState(() => _playing = !_playing),
                  icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.4, label: Text('לאט מאוד')),
                      ButtonSegment(value: 0.6, label: Text('לאט')),
                      ButtonSegment(value: 1.0, label: Text('רגיל')),
                    ],
                    selected: {_speed},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _speed = v.first),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _closeUp = !_closeUp),
                  icon: Icon(_closeUp ? Icons.zoom_out_map_rounded : Icons.zoom_in_rounded),
                  label: Text(_closeUp ? 'כל הגיטרה' : 'תקריב'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _sound = !_sound),
                  icon: Icon(_sound ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                  label: Text(_sound ? 'צליל פועל' : 'צליל כבוי'),
                ),
              ],
            ),
            StrummingPatternWidget(
              pattern: _pattern,
              activeIndex: _playing ? _slot % (events.isEmpty ? 1 : events.length) : null,
            ),
            if (current != null) ...[
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Text(
                  _explain(current),
                  key: ValueKey(_slot),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            const _StepTitle(number: 2, text: 'שחקו בקצב', color: AppColors.pink),
            const SizedBox(height: 4),
            const Text(
              'פריטות מתקרבות אליכם — פרטו (או החליקו) בדיוק כשהן מגיעות למיתרים. '
              'כוכב אחד פותח את המהירות הבאה.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _levels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LevelCard(
                  title: 'שלב ${i + 1} · ${_levels[i].name}',
                  subtitle:
                      '${(_pattern.defaultBpm * _levels[i].factor).round()} BPM · '
                      '${_chordIds.map((id) => widget.chordCatalog.chordById(id)?.displayName ?? id).join(' → ')}',
                  stars: ProgressService.instance.gameStars(_levelKey(i)),
                  locked: !_unlocked(i),
                  color: [AppColors.turquoise, AppColors.amberBright, AppColors.pink][i],
                  onTap: () => unawaited(_playLevel(i)),
                ),
              ),
            const SizedBox(height: 14),
            const _StepTitle(number: 3, text: 'שיר לדוגמה', color: AppColors.amberBright),
            const SizedBox(height: 8),
            if (_exampleSong == null)
              const Text(
                'אין שיר לדוגמה לדפוס הזה.',
                style: TextStyle(color: AppColors.textMuted),
              )
            else
              _LevelCard(
                title: '🎵 ${_exampleSong!.title}',
                subtitle:
                    '${_exampleSong!.artist} · ${_exampleSong!.chordSequence.length} תיבות'
                    '${_exampleSong!.instrumental ? ' · אקורדים בלבד' : ' · עם מילים'}',
                stars: ProgressService.instance.gameStars('song:${_exampleSong!.id}'),
                locked: !_unlocked(1),
                lockedText: 'פתחו את שלב 2 כדי לנגן את השיר',
                color: AppColors.violet,
                onTap: () => unawaited(_playSong()),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.text, required this.color});

  final int number;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.background,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.title,
    required this.subtitle,
    required this.stars,
    required this.locked,
    required this.color,
    required this.onTap,
    this.lockedText = 'השיגו כוכב בשלב הקודם',
  });

  final String title;
  final String subtitle;
  final int stars;
  final bool locked;
  final Color color;
  final VoidCallback onTap;
  final String lockedText;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: locked ? null : onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(
                  locked ? Icons.lock_rounded : Icons.sports_esports_rounded,
                  color: color,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locked ? lockedText : subtitle,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < 3; i++)
                  Icon(
                    i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                    color: i < stars
                        ? AppColors.amberBright
                        : AppColors.textMuted.withValues(alpha: 0.4),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
