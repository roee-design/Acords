import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/audio_analyzer.dart';
import '../audio/blitz_sfx_service.dart';
import '../audio/mic_capture_guard.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import '../services/blitz_prefs.dart';
import 'app_theme.dart';
import 'widgets/chord_fretboard_chart.dart';
import 'widgets/chord_hero_display.dart';
import 'widgets/confetti_burst.dart';
import 'widgets/help_sheet.dart';

/// Timed chord-switching challenge — play as many target chords as possible.
class ChordBlitzScreen extends StatefulWidget {
  const ChordBlitzScreen({super.key, required this.catalog});

  final ChordCatalog catalog;

  @override
  State<ChordBlitzScreen> createState() => _ChordBlitzScreenState();
}

enum _BlitzPhase { setup, countdown, playing, gameOver }

enum _PoolMode { level, all, custom }

class _ChordBlitzScreenState extends State<ChordBlitzScreen> {
  static const int _fftSize = 8192;
  static const int _sampleRate = 44100;
  static const int _startSeconds = 30;
  static const Duration _chordGrace = Duration(milliseconds: 350);

  final AudioAnalyzer _analyzer = AudioAnalyzer(
    sampleRate: _sampleRate,
    fftSize: _fftSize,
  );
  final _rng = Random();

  StreamSubscription<ChordFeedback>? _feedbackSubscription;
  Timer? _gameTimer;

  _BlitzPhase _phase = _BlitzPhase.setup;
  _PoolMode _poolMode = _PoolMode.level;
  var _selectedDifficulty = 1;
  List<String> _customChordIds = [];

  late ChordDefinition _targetChord;
  var _timeRemaining = _startSeconds;
  var _score = 0;
  var _streak = 0;
  var _bestStreak = 0;
  var _chordsCleared = 0;
  var _bonusSeconds = 0;
  var _highScore = 0;
  var _wasPerfect = false;
  var _successGlow = false;
  var _showConfetti = false;
  var _showStreakBonus = false;
  var _confettiTick = 0;
  var _busy = false;
  var _lifecycleEpoch = 0;
  var _countdownValue = 3;
  String? _countdownLabel;
  String? _errorMessage;

  String get _highScoreKey {
    switch (_poolMode) {
      case _PoolMode.level:
        return BlitzPrefs.highScoreKeyForLevel(_selectedDifficulty);
      case _PoolMode.all:
        return BlitzPrefs.highScoreKeyAll;
      case _PoolMode.custom:
        return BlitzPrefs.highScoreKeyCustom;
    }
  }

  List<ChordDefinition> get _chordPool {
    switch (_poolMode) {
      case _PoolMode.level:
        return widget.catalog.chordsForDifficulty(_selectedDifficulty);
      case _PoolMode.all:
        return List<ChordDefinition>.of(widget.catalog.chords);
      case _PoolMode.custom:
        final byId = {
          for (final c in widget.catalog.chords) c.id: c,
        };
        return [
          for (final id in _customChordIds)
            if (byId[id] != null) byId[id]!,
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _targetChord = widget.catalog.chords.first;
    _feedbackSubscription = _analyzer.feedbackStream.listen(
      _onFeedback,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _errorMessage = error.toString());
        unawaited(_stopListening());
      },
    );
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final custom = await BlitzPrefs.loadCustomChordIds();
    final hs = await BlitzPrefs.getHighScore(_highScoreKey);
    if (!mounted) return;
    setState(() {
      _customChordIds = custom;
      _highScore = hs;
      _targetChord = _pickRandomChord(excludeId: null);
    });
  }

  Future<void> _refreshHighScore() async {
    final hs = await BlitzPrefs.getHighScore(_highScoreKey);
    if (mounted) setState(() => _highScore = hs);
  }

  @override
  void dispose() {
    _lifecycleEpoch++;
    _gameTimer?.cancel();
    _feedbackSubscription?.cancel();
    unawaited(_analyzer.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_analyzer.dispose());
    super.dispose();
  }

  ChordDefinition _pickRandomChord({required String? excludeId}) {
    final pool = _chordPool;
    if (pool.isEmpty) {
      return widget.catalog.chords.first;
    }
    if (pool.length == 1) {
      return pool.first;
    }
    ChordDefinition next;
    do {
      next = pool[_rng.nextInt(pool.length)];
    } while (excludeId != null && next.id == excludeId);
    return next;
  }

  void _onFeedback(ChordFeedback feedback) {
    if (!mounted || _phase != _BlitzPhase.playing) return;
    if (_analyzer.isBlanking) return;

    final isCorrect = feedback.matchStatus == ChordMatchStatus.perfect;
    if (isCorrect && !_wasPerfect) {
      _onChordCorrect();
      return;
    }
    _wasPerfect = isCorrect;
  }

  void _onChordCorrect() {
    final nextStreak = _streak + 1;
    final streakBonus = nextStreak > 0 && nextStreak % 5 == 0;
    final addedSeconds = 3 + (streakBonus ? 5 : 0);
    final nextChord = _pickRandomChord(excludeId: _targetChord.id);

    if (streakBonus) {
      unawaited(BlitzSfxService.instance.playStreakBonus());
    } else {
      unawaited(BlitzSfxService.instance.playSuccess());
    }

    setState(() {
      _timeRemaining += addedSeconds;
      _bonusSeconds += addedSeconds;
      _score += 100;
      _streak = nextStreak;
      if (nextStreak > _bestStreak) {
        _bestStreak = nextStreak;
      }
      _chordsCleared += 1;
      _wasPerfect = false;
      _successGlow = true;
      _showConfetti = true;
      _showStreakBonus = streakBonus;
      _confettiTick++;
      _targetChord = nextChord;
    });

    _analyzer.setTargetChord(
      nextChord,
      referenceA4Hz: widget.catalog.referenceA4Hz,
      gracePeriod: _chordGrace,
    );

    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || _phase != _BlitzPhase.playing) return;
      setState(() {
        _successGlow = false;
        _showConfetti = false;
        _showStreakBonus = false;
      });
    });
  }

  Future<void> _onStartPressed() async {
    final pool = _chordPool;
    if (pool.isEmpty || _busy || _phase == _BlitzPhase.countdown) {
      if (pool.isEmpty && _poolMode == _PoolMode.custom && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('בחרו לפחות אקורד אחד בקבוצה המותאמת.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _phase = _BlitzPhase.countdown;
      _countdownValue = 3;
      _countdownLabel = '3';
      _errorMessage = null;
      _timeRemaining = _startSeconds;
      _score = 0;
      _streak = 0;
      _bestStreak = 0;
      _chordsCleared = 0;
      _bonusSeconds = 0;
      _wasPerfect = false;
      _successGlow = false;
      _showConfetti = false;
      _showStreakBonus = false;
      _targetChord = _pickRandomChord(excludeId: null);
    });

    await _runCountdown();
    if (!mounted || _phase != _BlitzPhase.countdown) return;

    setState(() => _phase = _BlitzPhase.playing);
    _startGameClock();
    await _startListening();
  }

  Future<void> _runCountdown() async {
    const labels = ['3', '2', '1', 'צא!'];
    for (var i = 0; i < labels.length; i++) {
      if (!mounted || _phase != _BlitzPhase.countdown) return;
      setState(() {
        _countdownValue = 3 - i;
        _countdownLabel = labels[i];
      });
      if (i < 3) {
        unawaited(BlitzSfxService.instance.playCountdownTick());
      } else {
        unawaited(BlitzSfxService.instance.playGo());
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }

  void _startGameClock() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase != _BlitzPhase.playing) return;
      setState(() => _timeRemaining -= 1);
      if (_timeRemaining <= 0) {
        unawaited(_endGame());
      }
    });
  }

  Future<void> _startListening() async {
    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await MicCaptureGuard.instance.claim(this, _stopListening);
      _analyzer.setTargetChord(
        _targetChord,
        referenceA4Hz: widget.catalog.referenceA4Hz,
        gracePeriod: _chordGrace,
      );
      await _analyzer.start();
      if (epoch != _lifecycleEpoch || !mounted || _phase != _BlitzPhase.playing) {
        await _analyzer.stop();
        MicCaptureGuard.instance.release(this);
        if (mounted && epoch == _lifecycleEpoch) {
          setState(() => _busy = false);
        }
        return;
      }
      setState(() => _busy = false);
    } catch (error) {
      MicCaptureGuard.instance.release(this);
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() {
          _errorMessage = error.toString();
          _busy = false;
        });
        await _endGame();
      }
    }
  }

  Future<void> _stopListening() async {
    final epoch = ++_lifecycleEpoch;
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
    if (mounted && epoch == _lifecycleEpoch) {
      setState(() => _busy = false);
    }
  }

  Future<void> _endGame() async {
    if (_phase == _BlitzPhase.gameOver) return;

    _gameTimer?.cancel();
    _gameTimer = null;

    final remainingAtEnd = _timeRemaining.clamp(0, 100000);
    final totalPlayed =
        (_startSeconds + _bonusSeconds - remainingAtEnd).clamp(1, 100000);
    final avgSeconds = _chordsCleared > 0
        ? totalPlayed / _chordsCleared
        : null;
    final grade = _MasteryGrade.fromAverage(avgSeconds);

    unawaited(BlitzSfxService.instance.playGameOver());

    final previousHigh = _highScore;

    if (mounted) {
      setState(() {
        _phase = _BlitzPhase.gameOver;
        _timeRemaining = 0;
        _successGlow = false;
        _showConfetti = false;
        _showStreakBonus = false;
      });
    }

    await BlitzPrefs.saveHighScoreIfBest(_highScoreKey, _score);
    await _refreshHighScore();

    await _stopListening();
    if (!mounted) return;
    await _showGameOverSheet(
      averageSeconds: avgSeconds,
      grade: grade,
      isNewHighScore: _score > previousHigh,
    );
  }

  Future<void> _showGameOverSheet({
    required double? averageSeconds,
    required _MasteryGrade grade,
    required bool isNewHighScore,
  }) async {
    if (!mounted) return;

    final action = await showModalBottomSheet<_GameOverAction>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _GameOverSheet(
        chordsCleared: _chordsCleared,
        score: _score,
        bestStreak: _bestStreak,
        highScore: _highScore,
        isNewHighScore: isNewHighScore,
        averageSeconds: averageSeconds,
        grade: grade,
      ),
    );

    if (!mounted) return;

    if (action == _GameOverAction.playAgain) {
      setState(() => _phase = _BlitzPhase.setup);
      await _refreshHighScore();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _exitToHome() async {
    _gameTimer?.cancel();
    _gameTimer = null;
    await _stopListening();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pauseOrExit() async {
    if (_phase == _BlitzPhase.playing || _phase == _BlitzPhase.countdown) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('לצאת מהאתגר?'),
          content: const Text('ההתקדמות בסיבוב הנוכחי תאבד.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('המשך לשחק'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('יציאה'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        if (_phase == _BlitzPhase.countdown) {
          setState(() => _phase = _BlitzPhase.setup);
        }
        await _exitToHome();
      }
      return;
    }
    await _exitToHome();
  }

  Future<void> _selectPoolMode(_PoolMode mode, {int? level}) async {
    setState(() {
      _poolMode = mode;
      if (level != null) _selectedDifficulty = level;
      _errorMessage = null;
    });
    if (mode == _PoolMode.custom) {
      await _editCustomGroup();
    }
    await _refreshHighScore();
  }

  Future<void> _editCustomGroup() async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CustomChordPickerSheet(
        catalog: widget.catalog,
        initiallySelected: _customChordIds.toSet(),
      ),
    );
    if (selected == null || !mounted) return;
    await BlitzPrefs.saveCustomChordIds(selected);
    setState(() {
      _customChordIds = selected;
      _poolMode = _PoolMode.custom;
    });
    await _refreshHighScore();
  }

  @override
  Widget build(BuildContext context) {
    final blocking = _phase == _BlitzPhase.playing ||
        _phase == _BlitzPhase.countdown;

    return PopScope(
      canPop: !blocking,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          _gameTimer?.cancel();
          unawaited(_stopListening());
          return;
        }
        await _pauseOrExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('אתגר האקורדים'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _pauseOrExit,
          ),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(start: 8, end: 12),
              child: Center(child: HelpButton(topic: HelpTopic.chordBlitz)),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _phase == _BlitzPhase.setup ||
                        _phase == _BlitzPhase.countdown
                    ? _buildSetup()
                    : _buildPlaying(),
              ),
              if (_phase == _BlitzPhase.countdown) _buildCountdownOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              return ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Text(
              _countdownLabel ?? '$_countdownValue',
              key: ValueKey(_countdownLabel),
              style: TextStyle(
                color: _countdownLabel == 'צא!'
                    ? AppColors.amberBright
                    : AppColors.turquoise,
                fontSize: _countdownLabel == 'צא!' ? 72 : 96,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(
            borderColor: AppColors.amber.withValues(alpha: 0.35),
          ),
          child: const Column(
            children: [
              Icon(Icons.flash_on_rounded, color: AppColors.amberBright, size: 32),
              SizedBox(height: 8),
              Text(
                'אתגר האקורדים',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '30 שניות להתחלה. כל אקורד נכון מוסיף זמן ונקודות.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: AppTheme.cardDecoration(
              borderColor: AppColors.turquoise.withValues(alpha: 0.35),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'שיא אישי ברמה זו',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _highScore > 0
                          ? '${_formatScore(_highScore)} נקודות'
                          : 'עדיין אין שיא — תהיו הראשונים!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _highScore > 0
                            ? AppColors.amberBright
                            : AppColors.textMuted,
                        fontSize: _highScore > 0 ? 32 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_poolMode == _PoolMode.custom) ...[
                      const SizedBox(height: 10),
                      Text(
                        _customChordIds.isEmpty
                            ? 'לא נבחרו אקורדים לקבוצה'
                            : '${_customChordIds.length} אקורדים בקבוצה המותאמת',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'בחרו רמת קושי',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var level = ChordDifficultyLevels.min;
                        level <= ChordDifficultyLevels.max;
                        level++)
                      ChoiceChip(
                        label: Text(ChordDifficultyLevels.labelFor(level)),
                        selected: _poolMode == _PoolMode.level &&
                            _selectedDifficulty == level,
                        onSelected: (_) => unawaited(
                          _selectPoolMode(_PoolMode.level, level: level),
                        ),
                        selectedColor:
                            AppColors.turquoise.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: _poolMode == _PoolMode.level &&
                                  _selectedDifficulty == level
                              ? AppColors.turquoise
                              : AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ChoiceChip(
                      label: const Text('כל הרמות'),
                      selected: _poolMode == _PoolMode.all,
                      onSelected: (_) =>
                          unawaited(_selectPoolMode(_PoolMode.all)),
                      selectedColor: AppColors.amber.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: _poolMode == _PoolMode.all
                            ? AppColors.amberBright
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('קבוצה מותאמת'),
                      selected: _poolMode == _PoolMode.custom,
                      onSelected: (_) =>
                          unawaited(_selectPoolMode(_PoolMode.custom)),
                      selectedColor: AppColors.success.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                        color: _poolMode == _PoolMode.custom
                            ? AppColors.success
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (_poolMode == _PoolMode.level) ...[
                  const SizedBox(height: 6),
                  Text(
                    ChordDifficultyLevels.categoryFor(_selectedDifficulty),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_poolMode == _PoolMode.custom) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _editCustomGroup,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('עריכת הקבוצה'),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy || _phase == _BlitzPhase.countdown
                      ? null
                      : _onStartPressed,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _phase == _BlitzPhase.countdown ? 'מתכוננים…' : 'התחל!',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: const Color(0xFF451A03),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed:
                      _phase == _BlitzPhase.countdown ? null : _exitToHome,
                  child: const Text('חזרה לבית'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaying() {
    final urgent = _timeRemaining <= 5;
    final accent = chordAccentColor(_targetChord);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'זמן',
                value: '$_timeRemaining',
                valueColor: urgent ? AppColors.error : AppColors.turquoise,
                emphasize: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'ניקוד',
                value: '$_score',
                valueColor: AppColors.amberBright,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'רצף',
                value: '$_streak',
                valueColor: AppColors.success,
              ),
            ),
          ],
        ),
        if (_showStreakBonus) ...[
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.thumb_up_rounded, color: AppColors.amberBright, size: 22),
              SizedBox(width: 8),
              Text(
                'בונוס רצף! +5 שניות',
                style: TextStyle(
                  color: AppColors.amberBright,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorMessage!,
            style: const TextStyle(color: AppColors.error, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          flex: 2,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              ChordHeroDisplay(
                chordName: _targetChord.displayName,
                label: 'נגנו עכשיו',
                chord: _targetChord,
                showFretboard: false,
                compact: true,
                successGlow: _successGlow,
                showConfetti: false,
                confettiTick: _confettiTick,
              ),
              if (_showConfetti)
                Positioned(
                  top: 8,
                  child: ConfettiBurst(key: ValueKey(_confettiTick)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _successGlow
                    ? AppColors.success
                    : accent.withValues(alpha: 0.35),
                width: _successGlow ? 2.5 : 1,
              ),
              boxShadow: _successGlow
                  ? [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ChordFretboardFrame(
              chord: _targetChord,
              borderRadius: 16,
              accent: accent,
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pauseOrExit,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('יציאה / הפסקה'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textMuted,
            side: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.4)),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.valueColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: AppTheme.cardDecoration(
        borderColor: valueColor.withValues(alpha: 0.3),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: emphasize ? 34 : 26,
              fontWeight: FontWeight.bold,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

enum _GameOverAction { playAgain, goHome }

String _formatScore(int score) {
  final digits = score.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    if (i > 0 && fromEnd % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

enum _MasteryGrade {
  s,
  a,
  b,
  c,
  none;

  static _MasteryGrade fromAverage(double? avg) {
    if (avg == null) return _MasteryGrade.none;
    if (avg < 1.5) return _MasteryGrade.s;
    if (avg < 2.5) return _MasteryGrade.a;
    if (avg < 4.0) return _MasteryGrade.b;
    return _MasteryGrade.c;
  }

  String get letter => switch (this) {
        _MasteryGrade.s => 'S',
        _MasteryGrade.a => 'A',
        _MasteryGrade.b => 'B',
        _MasteryGrade.c => 'C',
        _MasteryGrade.none => '—',
      };

  String get title => switch (this) {
        _MasteryGrade.s => 'מאסטר',
        _MasteryGrade.a => 'מתקדם',
        _MasteryGrade.b => 'בינוני',
        _MasteryGrade.c => 'מתחיל',
        _MasteryGrade.none => 'אין נתונים',
      };

  String get emoji => switch (this) {
        _MasteryGrade.s => '🌟',
        _MasteryGrade.a => '🔥',
        _MasteryGrade.b => '👍',
        _MasteryGrade.c => '🌱',
        _MasteryGrade.none => '❔',
      };

  Color get color => switch (this) {
        _MasteryGrade.s => AppColors.amberBright,
        _MasteryGrade.a => const Color(0xFFFB923C),
        _MasteryGrade.b => AppColors.turquoise,
        _MasteryGrade.c => AppColors.success,
        _MasteryGrade.none => AppColors.textMuted,
      };
}

class _GameOverSheet extends StatelessWidget {
  const _GameOverSheet({
    required this.chordsCleared,
    required this.score,
    required this.bestStreak,
    required this.highScore,
    required this.isNewHighScore,
    required this.averageSeconds,
    required this.grade,
  });

  final int chordsCleared;
  final int score;
  final int bestStreak;
  final int highScore;
  final bool isNewHighScore;
  final double? averageSeconds;
  final _MasteryGrade grade;

  @override
  Widget build(BuildContext context) {
    final avgText = averageSeconds == null
        ? '—'
        : '${averageSeconds!.toStringAsFixed(1)} שניות';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.all(Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 14),
              Text(
                grade.emoji,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 36),
              ),
              const SizedBox(height: 4),
              Text(
                'ציון שליטה: ${grade.letter}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: grade.color,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                grade.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: grade.color.withValues(alpha: 0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'זמן ממוצע לאקורד: $avgText',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'הזמן נגמר!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isNewHighScore) ...[
                const SizedBox(height: 8),
                Text(
                  'שיא חדש! ${_formatScore(score)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.amberBright,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _ResultRow(label: 'אקורדים שנוגנו', value: '$chordsCleared'),
              _ResultRow(
                label: 'ניקוד סופי',
                value: _formatScore(score),
              ),
              _ResultRow(label: 'רצף גבוה ביותר', value: '$bestStreak'),
              _ResultRow(
                label: 'שיא אישי',
                value: _formatScore(highScore),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_GameOverAction.playAgain),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('משחק חדש'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_GameOverAction.goHome),
                icon: const Icon(Icons.home_rounded),
                label: const Text('חזרה לבית'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomChordPickerSheet extends StatefulWidget {
  const _CustomChordPickerSheet({
    required this.catalog,
    required this.initiallySelected,
  });

  final ChordCatalog catalog;
  final Set<String> initiallySelected;

  @override
  State<_CustomChordPickerSheet> createState() =>
      _CustomChordPickerSheetState();
}

class _CustomChordPickerSheetState extends State<_CustomChordPickerSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
  }

  @override
  Widget build(BuildContext context) {
    final chords = widget.catalog.chordsByDifficultyThenName;
    final height = MediaQuery.sizeOf(context).height * 0.78;

    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'בחרו אקורדים לקבוצה',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${_selected.length}',
                  style: const TextStyle(
                    color: AppColors.turquoise,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chords.length,
              itemBuilder: (context, index) {
                final chord = chords[index];
                final checked = _selected.contains(chord.id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selected.add(chord.id);
                      } else {
                        _selected.remove(chord.id);
                      }
                    });
                  },
                  activeColor: AppColors.turquoise,
                  title: Text(
                    chord.displayName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${ChordDifficultyLevels.labelFor(chord.difficulty)} · ${chord.category}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_selected.toList()..sort()),
              child: const Text('שמירת הקבוצה'),
            ),
          ),
        ],
      ),
    );
  }
}
