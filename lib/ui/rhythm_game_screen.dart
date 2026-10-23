import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/audio_analyzer.dart';
import '../audio/game_sound_service.dart';
import '../audio/mic_capture_guard.dart';
import '../audio/onset_detector.dart';
import '../game/latency_calibration.dart';
import '../game/rhythm_chart.dart';
import '../game/rhythm_game_painter.dart';
import '../game/rhythm_judge.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import '../models/strumming_pattern.dart';
import '../services/progress_service.dart';
import 'app_theme.dart';
import 'mic_calibration_screen.dart';
import 'navigation/app_page_route.dart';
import 'widgets/strumming_pattern_widget.dart';

enum GameInputMode { guitar, touch }

enum _Phase { setup, countIn, playing, results }

/// Rhythm game: strokes travel down a highway towards the strings; strum (on
/// the guitar, heard by the mic) or swipe the screen when they arrive.
///
/// Pops with the number of stars earned (0–3), or null if left early.
class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({
    super.key,
    required this.title,
    required this.chart,
    required this.chordCatalog,
    required this.progressKey,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final RhythmChart chart;
  final ChordCatalog chordCatalog;

  /// Key for best score / stars in [ProgressService].
  final String progressKey;

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  // Sensitive strum detection: soft finger strums on nylon must count.
  final AudioAnalyzer _analyzer =
      AudioAnalyzer(onsetDetector: OnsetDetector.forRhythmGame());

  /// Live mic level (0–1 RMS) and time of the last heard strum, for the HUD.
  final ValueNotifier<double> _micLevel = ValueNotifier(0);
  final ValueNotifier<double> _lastHeardMs = ValueNotifier(-100000);
  StreamSubscription<ChordFeedback>? _levelSub;
  double _quietSinceMs = 0;

  /// Fine-tuning around the calibrated mic latency during a run.
  LatencyTrim _trim = LatencyTrim();
  final Random _rng = Random();

  late RhythmJudge _judge;
  late GameView _view;
  var _phase = _Phase.setup;
  var _mode = GameInputMode.touch;
  var _metronome = true;
  var _busy = false;
  String? _error;

  DateTime _startWall = DateTime.now();
  double _leadInMs = 0;
  /// Latency correction for this run: measured mic latency (guitar) or 0.
  int _calibration = 0;
  int _lastBeatTicked = -1000;
  int _currentBar = -1;
  StreamSubscription<DateTime>? _onsetSub;
  StreamSubscription<ChordHit>? _hitSub;
  final Map<int, (double, double, int?)> _pointers = {}; // id → (t, y, note)
  var _newBest = false;
  var _lastFeedbackSetState = 0.0;
  Size? _playSize;

  RhythmChart get _chart => widget.chart;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _resetRun();
    final chords = {
      for (final b in _chart.bars) widget.chordCatalog.chordById(b.chordId),
    }.whereType<ChordDefinition>();
    unawaited(GameSoundService.instance.prepare(chords));
  }

  void _resetRun() {
    // The mic adds jitter a touch screen does not: slightly wider windows.
    final mic = _mode == GameInputMode.guitar;
    _judge = RhythmJudge(
      _chart,
      perfectWindowMs: mic ? 80 : 70,
      goodWindowMs: mic ? 170 : 140,
    );
    _trim = LatencyTrim();
    _quietSinceMs = 0;
    _view = GameView(
      chart: _chart,
      judge: _judge,
      chordName: (id) => widget.chordCatalog.chordById(id)?.displayName ?? id,
    );
    _lastBeatTicked = -1000;
    _currentBar = -1;
    _newBest = false;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _onsetSub?.cancel();
    _hitSub?.cancel();
    _levelSub?.cancel();
    _micLevel.dispose();
    _lastHeardMs.dispose();
    unawaited(_analyzer.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_analyzer.dispose());
    unawaited(WakelockPlus.disable());
    _frame.dispose();
    super.dispose();
  }

  // --- Run control -----------------------------------------------------------

  int get _countInBeats =>
      _chart.pattern.beatsPerBar >= 3 ? _chart.pattern.beatsPerBar : 4;

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_mode == GameInputMode.guitar &&
        ProgressService.instance.micLatencyMs == null) {
      // First guitar game: measure this phone's mic latency once.
      final saved = await _openCalibration();
      if (!saved) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    _resetRun();
    _calibration = _mode == GameInputMode.guitar
        ? (ProgressService.instance.micLatencyMs ?? 150)
        : 0;

    if (_mode == GameInputMode.guitar) {
      try {
        await MicCaptureGuard.instance.claim(this, _stopMic);
        _analyzer.setTargetChord(
          widget.chordCatalog.chordById(_chart.bars.first.chordId)!,
          referenceA4Hz: widget.chordCatalog.referenceA4Hz,
        );
        await _analyzer.start();
        _onsetSub = _analyzer.onsetStream.listen(_onOnset);
        _hitSub = _analyzer.hitStream.listen(_onChordHit);
        _levelSub = _analyzer.feedbackStream.listen(
          (f) => _micLevel.value = f.inputLevel,
        );
      } catch (e) {
        MicCaptureGuard.instance.release(this);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'לא הצלחנו להפעיל את המיקרופון. אפשר לשחק במצב מסך.';
        });
        return;
      }
    }
    if (!mounted) return;
    unawaited(WakelockPlus.enable());
    _leadInMs = _countInBeats * _chart.beatMs;
    _clock
      ..reset()
      ..start();
    _startWall = DateTime.now();
    setState(() {
      _busy = false;
      _phase = _Phase.countIn;
    });
    _ticker.start();
  }

  /// Opens the calibration screen; true when a latency was saved.
  Future<bool> _openCalibration() async {
    final saved = await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(
        page: MicCalibrationScreen(chordCatalog: widget.chordCatalog),
      ),
    );
    if (mounted) setState(() {});
    return saved ?? false;
  }

  Future<void> _stopMic() async {
    await _onsetSub?.cancel();
    await _hitSub?.cancel();
    await _levelSub?.cancel();
    _onsetSub = null;
    _hitSub = null;
    _levelSub = null;
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
  }

  Future<void> _finish() async {
    _ticker.stop();
    _clock.stop();
    unawaited(WakelockPlus.disable());
    if (_mode == GameInputMode.guitar) await _stopMic();
    _newBest = ProgressService.instance.recordGameResult(
      widget.progressKey,
      stars: _judge.stars,
      score: _judge.score,
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.results);
  }

  double get _nowMs => _clock.elapsedMicroseconds / 1000.0 - _leadInMs;

  void _onTick(Duration _) {
    final now = _nowMs;
    _view.nowMs = now;

    // Metronome / count-in ticks.
    final beat = (now / _chart.beatMs).floor();
    if (beat != _lastBeatTicked && now >= beat * _chart.beatMs) {
      _lastBeatTicked = beat;
      final countIn = now < 0;
      if ((countIn && (_metronome || _mode == GameInputMode.touch)) ||
          (!countIn && _metronome)) {
        final perBar = _chart.pattern.beatsPerBar;
        unawaited(
          GameSoundService.instance.playTick(accent: beat % perBar == 0),
        );
      }
    }

    if (_phase == _Phase.countIn && now >= 0) {
      setState(() => _phase = _Phase.playing);
    }

    // Bar change → listen for the new chord.
    final bar = _chart.barAt(max(0.0, now + 60));
    if (bar != null && bar.index != _currentBar) {
      _currentBar = bar.index;
      if (_mode == GameInputMode.guitar) {
        final chord = widget.chordCatalog.chordById(bar.chordId);
        if (chord != null) {
          _analyzer.setTargetChord(
            chord,
            referenceA4Hz: widget.chordCatalog.referenceA4Hz,
            resetAnalysis: false,
          );
        }
      }
      setState(() {});
    }

    // Misses (judge a little behind "now" so late swipes still count).
    final missed = _judge.advance(now - 30);
    if (missed.isNotEmpty) {
      _popup('פספוס', AppColors.error, now);
      setState(() {});
    }

    if (_mode == GameInputMode.guitar && _micLevel.value > 0.004) {
      _quietSinceMs = now;
    }

    if (_phase == _Phase.playing && now > _chart.durationMs + 900) {
      unawaited(_finish());
    }
    _frame.value++;
  }

  // --- Input -------------------------------------------------------------------

  void _onOnset(DateTime at) {
    final heard = at.difference(_startWall).inMicroseconds / 1000.0 - _leadInMs;
    final t = heard - _calibration - _trim.correctionMs;
    _lastHeardMs.value = _nowMs;
    if (_phase == _Phase.playing) {
      // Small, bounded fine-tuning from strokes close to a note.
      final nearest = _nearestNoteOffset(t);
      if (nearest != null) _trim.add(nearest);
    }
    _stroke(t, null);
  }

  double? _nearestNoteOffset(double t) {
    double? best;
    for (final note in _chart.notes) {
      final d = t - note.timeMs;
      if (d < -200) break;
      if (best == null || d.abs() < best.abs()) best = d;
    }
    return best;
  }

  void _onChordHit(ChordHit hit) {
    final bar = _chart.barAt(max(0.0, _nowMs));
    if (bar == null || hit.chordId != bar.chordId) return;
    if (_view.verifiedBars.add(bar.index)) {
      _judge.addBonus(50);
      setState(() {});
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_phase != _Phase.countIn && _phase != _Phase.playing) return;
    final t = _nowMs - _calibration;
    final note = _stroke(t, null);
    _pointers[e.pointer] = (t, e.localPosition.dy, note?.index);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final entry = _pointers[e.pointer];
    if (entry == null) return;
    final dy = e.localPosition.dy - entry.$2;
    if (dy.abs() < 18) return;
    _pointers.remove(e.pointer);
    final noteIndex = entry.$3;
    if (noteIndex == null) return;
    final dir = dy > 0 ? StrokeDirection.down : StrokeDirection.up;
    if (_judge.applyDirection(noteIndex, dir)) {
      _popup('כיוון!', AppColors.amberBright, _nowMs);
      setState(() {});
    }
  }

  void _onPointerUp(PointerEvent e) => _pointers.remove(e.pointer);

  /// Judges one stroke at chart time [t]; returns the note hit, if any.
  RhythmNote? _stroke(double t, StrokeDirection? direction) {
    final now = _nowMs;
    if (t < -_chart.beatMs * 0.5 && _phase == _Phase.countIn) {
      // Strokes during the count-in are not judged.
      _view
        ..lastStrokeMs = now
        ..lastStrokeDown = true;
      if (_mode == GameInputMode.touch) _playStrokeSound(null, true);
      return null;
    }

    final outcome = _judge.input(t, direction: direction);
    final note = outcome.note;
    final down = note == null || note.kind != PatternEventKind.up;
    _view
      ..lastStrokeMs = now
      ..lastStrokeDown = down;
    if (_mode == GameInputMode.touch) _playStrokeSound(note, down);

    if (note == null) {
      if (outcome.onRest) _popup('שקט כאן!', AppColors.textMuted, now);
    } else {
      final r = outcome.result!;
      if (r.judgement == Judgement.perfect) {
        _popup('מושלם!', AppColors.turquoise, now);
        if (_mode == GameInputMode.touch) unawaited(HapticFeedback.lightImpact());
      } else {
        final early = (r.offsetMs ?? 0) < 0;
        _popup(early ? 'טוב · מוקדם' : 'טוב · מאוחר', AppColors.amberBright, now);
      }
      _burst(note, r.judgement == Judgement.perfect, now);
    }
    // Avoid rebuilding the HUD on every mic onset burst.
    if (now - _lastFeedbackSetState > 30) {
      _lastFeedbackSetState = now;
      setState(() {});
    }
    return note;
  }

  void _playStrokeSound(RhythmNote? note, bool down) {
    final bar = _chart.barAt(max(0.0, _nowMs));
    final chord = widget.chordCatalog
        .chordById(bar?.chordId ?? _chart.bars.first.chordId);
    if (chord == null) return;
    final sounds = GameSoundService.instance;
    switch (note?.kind) {
      case PatternEventKind.mute:
        unawaited(sounds.playMute());
      case PatternEventKind.finger:
        unawaited(sounds.playString(chord, note!.stringNumber ?? 6));
      default:
        unawaited(sounds.playStrum(chord, down: down));
    }
  }

  void _popup(String text, Color color, double now) {
    _view.popups.add(GamePopup(text, color, now));
    if (_view.popups.length > 4) _view.popups.removeAt(0);
  }

  void _burst(RhythmNote note, bool perfect, double now) {
    final size = _playSize;
    if (size == null) return;
    final color = noteColor(note.kind);
    // Same geometry as the painter: lanes at ±half of the hit-line width.
    final lane = switch (note.kind) {
      PatternEventKind.down => -0.5,
      PatternEventKind.up => 0.5,
      _ => 0.0,
    };
    final x = size.width / 2 + lane * min(size.width * 0.44, 210.0);
    final y = size.height * 0.8;
    final count = perfect ? 18 : 9;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final speed = 0.15 + _rng.nextDouble() * 0.35;
      _view.particles.add(
        GameParticle(
          x: x,
          y: y,
          vx: cos(a) * speed,
          vy: sin(a) * speed - 0.15,
          bornMs: now,
          color: i.isEven ? color : Colors.white,
        ),
      );
    }
  }

  // --- UI ----------------------------------------------------------------------

  String _chordName(String id) =>
      widget.chordCatalog.chordById(id)?.displayName ?? id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.gameGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  if (_phase == _Phase.countIn || _phase == _Phase.playing)
                    _hud(),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerUp,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              _playSize = constraints.biggest;
                              return CustomPaint(
                                painter: RhythmGamePainter(
                                  _view,
                                  repaint: _frame,
                                ),
                              );
                            },
                          ),
                          if (_phase == _Phase.countIn) _countInOverlay(),
                        ],
                      ),
                    ),
                  ),
                  if (_phase == _Phase.countIn || _phase == _Phase.playing)
                    _bottomHint(),
                ],
              ),
              if (_phase == _Phase.setup) _setupOverlay(),
              if (_phase == _Phase.results) _resultsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'יציאה',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_phase == _Phase.playing || _phase == _Phase.countIn)
            Text(
              '${_judge.score}',
              style: const TextStyle(
                color: AppColors.amberBright,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }

  Widget _hud() {
    final now = max(0.0, _view.nowMs);
    final bar = _chart.barAt(now) ?? _chart.bars.first;
    final next = bar.index + 1 < _chart.bars.length
        ? _chart.bars[bar.index + 1]
        : null;
    final progress =
        _chart.durationMs <= 0 ? 0.0 : (now / _chart.durationMs).clamp(0.0, 1.0);
    final combo = _judge.combo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              color: AppColors.pink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chordBubble(bar),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (next != null)
                      Text(
                        'הבא: ${_chordName(next.chordId)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      combo >= 3
                          ? 'קומבו $combo  ×${_judge.multiplier}'
                          : 'דיוק ${(100 * _judge.accuracy).round()}%',
                      style: TextStyle(
                        color: combo >= 3 ? AppColors.pink : Colors.white70,
                        fontSize: combo >= 3 ? 18 : 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_mode == GameInputMode.guitar) _micMeter(),
          if (_chart.song != null) _lyricsCard(bar),
        ],
      ),
    );
  }

  /// Live mic level + a flash on every strum the game heard, so it is
  /// obvious whether the guitar reaches the microphone at all.
  Widget _micMeter() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ValueListenableBuilder<double>(
        valueListenable: _lastHeardMs,
        builder: (context, heardAt, _) {
          final flash = _nowMs - heardAt < 220;
          final quiet = _phase == _Phase.playing &&
              _view.nowMs - _quietSinceMs > 3000;
          return Column(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: flash
                          ? AppColors.turquoise
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      flash ? '🎸 נשמע!' : '🎤',
                      style: TextStyle(
                        color: flash ? AppColors.background : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _micLevel,
                      builder: (context, level, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (level / 0.08).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          color: level > 0.004
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (quiet)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'לא שומעים את הגיטרה — קרבו את הטלפון לגיטרה ובדקו הרשאת מיקרופון',
                    style: TextStyle(color: AppColors.amberBright, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chordBubble(RhythmBar bar) {
    final verified = _view.verifiedBars.contains(bar.index);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 66,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (verified ? AppColors.success : AppColors.violet)
            .withValues(alpha: 0.22),
        border: Border.all(
          color: verified ? AppColors.success : AppColors.violet,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (verified ? AppColors.success : AppColors.violet)
                .withValues(alpha: 0.4),
            blurRadius: 16,
          ),
        ],
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _chordName(bar.chordId) + (verified ? ' ✓' : ''),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _lyricsCard(RhythmBar bar) {
    final song = _chart.song!;
    final li = bar.lineIndex;
    if (li == null || li >= song.lines.length) return const SizedBox.shrink();
    final line = song.lines[li];
    if (line.text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Directionality(
        textDirection: song.rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < line.segments.length; i++)
                TextSpan(
                  text: line.segments[i].lyrics,
                  style: TextStyle(
                    color: i == bar.segmentIndex
                        ? AppColors.amberBright
                        : Colors.white.withValues(alpha: 0.75),
                    fontWeight: i == bar.segmentIndex
                        ? FontWeight.w900
                        : FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _bottomHint() {
    final text = _mode == GameInputMode.guitar
        ? '🎸 פרטו על הגיטרה כשהחץ מגיע למיתרים'
        : '👆 החליקו למטה ↓ או למעלה ↑ כשהחץ מגיע למיתרים';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60, fontSize: 12),
      ),
    );
  }

  Widget _countInOverlay() {
    final now = _view.nowMs;
    final beatsLeft = (-now / _chart.beatMs).ceil();
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              beatsLeft > 0 ? '$beatsLeft' : '!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 84,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'מתחילים בעוד… התחילו לפרוט כשהחץ הראשון מגיע למיתרים',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupOverlay() {
    final best = ProgressService.instance.gameBestScore(widget.progressKey);
    final stars = ProgressService.instance.gameStars(widget.progressKey);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.violet.withValues(alpha: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                const SizedBox(height: 12),
                StrummingPatternWidget(pattern: _chart.pattern),
                const SizedBox(height: 8),
                Text(
                  '${_chart.bpm} BPM · ${_chart.bars.length} תיבות'
                  '${best > 0 ? ' · שיא $best' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (stars > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _Stars(count: stars, size: 22),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'איך לשחק?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<GameInputMode>(
                  segments: const [
                    ButtonSegment(
                      value: GameInputMode.guitar,
                      icon: Icon(Icons.mic_rounded),
                      label: Text('עם גיטרה'),
                    ),
                    ButtonSegment(
                      value: GameInputMode.touch,
                      icon: Icon(Icons.swipe_vertical_rounded),
                      label: Text('על המסך'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() {
                    _mode = v.first;
                    // Speaker ticks would be "heard" as strums by the mic.
                    _metronome = _mode == GameInputMode.touch;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  _mode == GameInputMode.guitar
                      ? 'המיקרופון שומע את הפריטה ובודק גם שהאקורד נכון (✓ = בונוס).'
                      : 'החליקו למטה/למעלה בכיוון החץ — ותשמעו את האקורד.',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (_mode == GameInputMode.guitar)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: AppColors.turquoise, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ProgressService.instance.micLatencyMs == null
                                ? 'כיול מיקרופון: עוד לא בוצע (ייפתח לפני המשחק)'
                                : 'כיול מיקרופון: ${ProgressService.instance.micLatencyMs} ms',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_openCalibration()),
                          child: Text(
                            ProgressService.instance.micLatencyMs == null
                                ? 'כייל עכשיו'
                                : 'כייל מחדש',
                          ),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _metronome,
                  onChanged: (v) => setState(() => _metronome = v),
                  title: const Text(
                    'מטרונום',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: _mode == GameInputMode.guitar
                      ? const Text(
                          'עם גיטרה — רק עם אוזניות, אחרת המיקרופון שומע אותו',
                          style: TextStyle(fontSize: 11),
                        )
                      : null,
                ),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_start()),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.pink,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: Text(
                    _busy ? 'מתחבר…' : 'יאללה, מתחילים!',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultsOverlay() {
    final j = _judge;
    final offset = j.medianOffsetMs;
    String? tendency;
    if (_mode == GameInputMode.guitar) {
      // Mic latency is calibrated away, so the median says little here.
    } else if (offset != null && offset.abs() >= 35) {
      tendency = offset < 0
          ? 'נוטים להקדים בכ-${offset.abs().round()}ms — חכו רגע לחץ'
          : 'נוטים לאחר בכ-${offset.round()}ms — נסו לפרוט קצת קודם';
    } else if (offset != null) {
      tendency = 'התזמון שלכם מדויק 👌';
    }
    final verified = _view.verifiedBars.length;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.amberBright.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  j.stars >= 1 ? (j.stars == 3 ? 'מדהים!' : 'כל הכבוד!') : 'כמעט…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _Stars(count: j.stars, size: 46, animate: true),
                const SizedBox(height: 10),
                Text(
                  '${j.score}',
                  style: const TextStyle(
                    color: AppColors.amberBright,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_newBest)
                  const Text(
                    'שיא חדש! 🏆',
                    style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w800),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _StatChip('דיוק', '${(100 * j.finalAccuracy).round()}%', AppColors.sky),
                    _StatChip('מושלם', '${j.perfects}', AppColors.turquoise),
                    _StatChip('טוב', '${j.goods}', AppColors.amberBright),
                    _StatChip('פספוס', '${j.misses + (_chart.notes.length - j.judgedCount)}', AppColors.error),
                    _StatChip('קומבו', '${j.maxCombo}', AppColors.pink),
                    if (_mode == GameInputMode.guitar)
                      _StatChip('אקורדים ✓', '$verified/${_chart.bars.length}', AppColors.success),
                  ],
                ),
                if (tendency != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    tendency,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                if (_mode == GameInputMode.guitar) ...[
                  const SizedBox(height: 8),
                  Text(
                    'איחור מיקרופון: ${_calibration + _trim.correctionMs.round()} ms',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  if (j.finalAccuracy < 0.6)
                    TextButton.icon(
                      onPressed: () async {
                        await _openCalibration();
                        if (mounted) setState(() => _phase = _Phase.setup);
                      },
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('הפריטות לא נקלטו בזמן? כיילו מחדש'),
                    ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _phase = _Phase.setup),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('שוב'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(j.stars),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('סיום'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count, this.size = 24, this.animate = false});

  final int count;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: animate ? 0.0 : 1.0, end: 1.0),
            duration: Duration(milliseconds: animate ? 350 + i * 250 : 1),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(
              scale: i < count ? v : 1,
              child: child,
            ),
            child: Icon(
              i < count ? Icons.star_rounded : Icons.star_border_rounded,
              size: size,
              color: i < count
                  ? AppColors.amberBright
                  : Colors.white.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
