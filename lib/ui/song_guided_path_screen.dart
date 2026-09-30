import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/audio_analyzer.dart';
import '../audio/mic_capture_guard.dart';
import '../audio/strum_preview_service.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import '../models/song_definition.dart';
import 'app_theme.dart';
import 'navigation/app_page_route.dart';
import 'song_player_screen.dart';
import 'widgets/strumming_help_sheet.dart';
import 'widgets/strumming_pattern_widget.dart';

/// Guided 3-step learning path for a song's chords + strumming.
class SongGuidedPathScreen extends StatefulWidget {
  const SongGuidedPathScreen({
    super.key,
    required this.song,
    required this.chordCatalog,
  });

  final SongDefinition song;
  final ChordCatalog chordCatalog;

  @override
  State<SongGuidedPathScreen> createState() => _SongGuidedPathScreenState();
}

enum _GuidedStep {
  transitions,
  gradualStrum,
  fullSong,
}

class _SongGuidedPathScreenState extends State<SongGuidedPathScreen> {
  static const int _fftSize = 8192;
  static const int _sampleRate = 44100;
  static const Duration _grace = Duration(milliseconds: 300);

  final AudioAnalyzer _analyzer = AudioAnalyzer(
    sampleRate: _sampleRate,
    fftSize: _fftSize,
  );

  StreamSubscription<ChordFeedback>? _feedbackSub;
  Timer? _beatTimer;

  var _step = _GuidedStep.transitions;
  var _listening = false;
  var _busy = false;
  var _lifecycleEpoch = 0;
  var _wasPerfect = false;
  var _pairIndex = 0;
  var _seqIndex = 0;
  var _strokeIndex = 0;
  var _bpmFactor = 0.6;
  var _successfulRounds = 0;
  String? _errorMessage;
  ChordFeedback? _feedback;

  late final List<String> _chordIds;
  late final List<_Pair> _pairs;

  @override
  void initState() {
    super.initState();
    _chordIds = widget.song.chordSequence;
    _pairs = _buildPairs(_chordIds);
    _feedbackSub = _analyzer.feedbackStream.listen(
      _onFeedback,
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString();
          _listening = false;
          _busy = false;
        });
        unawaited(_analyzer.stop());
        MicCaptureGuard.instance.release(this);
      },
    );
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _feedbackSub?.cancel();
    _lifecycleEpoch++;
    unawaited(StrumPreviewService.instance.stop());
    unawaited(_analyzer.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_analyzer.dispose());
    super.dispose();
  }

  List<_Pair> _buildPairs(List<String> ids) {
    if (ids.length < 2) {
      return [
        for (final id in ids) _Pair(fromId: id, toId: id),
      ];
    }
    final out = <_Pair>[];
    for (var i = 0; i < ids.length - 1; i++) {
      if (ids[i] == ids[i + 1]) continue;
      out.add(_Pair(fromId: ids[i], toId: ids[i + 1]));
    }
    if (out.isEmpty && ids.isNotEmpty) {
      out.add(_Pair(fromId: ids.first, toId: ids.first));
    }
    return out;
  }

  int get _effectiveBpm =>
      max(40, (widget.song.bpm * _bpmFactor).round());

  String _label(String id) =>
      widget.chordCatalog.chordById(id)?.displayName ?? id;

  void _goToStep(_GuidedStep step) {
    unawaited(_stopAll());
    setState(() {
      _step = step;
      _pairIndex = 0;
      _seqIndex = 0;
      _strokeIndex = 0;
      _wasPerfect = false;
      _errorMessage = null;
      _feedback = null;
      if (step == _GuidedStep.gradualStrum) {
        _bpmFactor = 0.6;
        _successfulRounds = 0;
      }
    });
  }

  Future<void> _stopAll() async {
    _beatTimer?.cancel();
    _beatTimer = null;
    await StrumPreviewService.instance.stop();
    final epoch = ++_lifecycleEpoch;
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
    if (!mounted || epoch != _lifecycleEpoch) return;
    setState(() {
      _listening = false;
      _busy = false;
      _wasPerfect = false;
    });
  }

  Future<void> _startStepPractice() async {
    if (_busy || _listening) return;
    if (_chordIds.isEmpty) return;

    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _wasPerfect = false;
      _pairIndex = 0;
      _seqIndex = 0;
      _strokeIndex = 0;
    });

    try {
      await MicCaptureGuard.instance.claim(this, _stopAll);
      final targetId = _step == _GuidedStep.transitions
          ? (_pairs.isEmpty ? _chordIds.first : _pairs.first.toId)
          : _chordIds.first;
      final def = widget.chordCatalog.chordById(targetId);
      if (def == null) throw StateError('Chord not in catalog: $targetId');

      _analyzer.setTargetChord(
        def,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
      );
      await _analyzer.start();
      if (epoch != _lifecycleEpoch || !mounted) {
        await _analyzer.stop();
        MicCaptureGuard.instance.release(this);
        if (mounted && epoch == _lifecycleEpoch) {
          setState(() => _busy = false);
        }
        return;
      }

      setState(() {
        _listening = true;
        _busy = false;
      });

      if (_step == _GuidedStep.gradualStrum) {
        _startGradualClock();
      }
    } catch (e) {
      MicCaptureGuard.instance.release(this);
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() {
          _errorMessage = e.toString();
          _busy = false;
          _listening = false;
        });
      }
    }
  }

  void _startGradualClock() {
    _beatTimer?.cancel();
    final pattern = widget.song.pattern;
    final slots = pattern.events.length;
    if (slots == 0) return;

    // Audible strum preview ticks at practice BPM.
    unawaited(
      StrumPreviewService.instance.play(
        pattern: pattern,
        bpm: _effectiveBpm,
        onStroke: (i) {
          if (!mounted || !_listening) return;
          setState(() => _strokeIndex = i);
        },
      ),
    );

    // Chord hold timer unused for advance — advance is mic-gated.
    // Keep a light heartbeat only so UI stays alive if needed.
    _beatTimer?.cancel();
    _beatTimer = null;
  }

  void _onFeedback(ChordFeedback feedback) {
    if (!mounted || !_listening) return;
    if (_analyzer.isBlanking) return;

    final isPerfect = feedback.matchStatus == ChordMatchStatus.perfect;
    setState(() => _feedback = feedback);

    if (_step == _GuidedStep.transitions) {
      if (isPerfect && !_wasPerfect) {
        _onTransitionHit();
      }
    } else if (_step == _GuidedStep.gradualStrum) {
      if (isPerfect && !_wasPerfect) {
        _advanceSequenceChord();
      }
    }
    _wasPerfect = isPerfect;
  }

  void _onTransitionHit() {
    if (_pairs.isEmpty) {
      _completeStep1();
      return;
    }
    if (_pairIndex >= _pairs.length - 1) {
      _completeStep1();
      return;
    }
    setState(() {
      _pairIndex += 1;
      _wasPerfect = false;
    });
    final next = _pairs[_pairIndex];
    final def = widget.chordCatalog.chordById(next.toId);
    if (def != null) {
      _analyzer.setTargetChord(
        def,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
        gracePeriod: _grace,
      );
    }
  }

  void _completeStep1() {
    unawaited(_stopAll());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('שלב 1 הושלם! ממשיכים לפריטה בקצב מתגבר.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _goToStep(_GuidedStep.gradualStrum);
  }

  void _advanceSequenceChord() {
    if (_seqIndex >= _chordIds.length - 1) {
      _onRoundComplete();
      return;
    }
    setState(() {
      _seqIndex += 1;
      _wasPerfect = false;
    });
    final def = widget.chordCatalog.chordById(_chordIds[_seqIndex]);
    if (def != null) {
      _analyzer.setTargetChord(
        def,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
        gracePeriod: _grace,
      );
    }
  }

  void _onRoundComplete() {
    setState(() {
      _successfulRounds += 1;
      _seqIndex = 0;
      _wasPerfect = false;
    });

    if (_bpmFactor >= 0.98) {
      unawaited(_stopAll());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שלב 2 הושלם! מוכנים לשיר המלא.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _goToStep(_GuidedStep.fullSong);
      return;
    }

    setState(() {
      _bpmFactor = min(1.0, _bpmFactor + 0.1);
    });
    // Restart clock at new BPM.
    unawaited(StrumPreviewService.instance.stop());
    _beatTimer?.cancel();
    final def = widget.chordCatalog.chordById(_chordIds.first);
    if (def != null) {
      _analyzer.setTargetChord(
        def,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
        gracePeriod: _grace,
      );
    }
    _startGradualClock();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('סיבוב מוצלח! BPM עכשיו $_effectiveBpm'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openFullSong() {
    unawaited(_stopAll());
    Navigator.of(context).pushReplacement(
      AppPageRoute<void>(
        page: SongPlayerScreen(
          song: widget.song,
          chordCatalog: widget.chordCatalog,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;

    return Scaffold(
      appBar: AppBar(
        title: Text('למד לפרוט · ${song.title}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _StepHeader(step: _step),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: switch (_step) {
                _GuidedStep.transitions => _buildTransitions(),
                _GuidedStep.gradualStrum => _buildGradual(),
                _GuidedStep.fullSong => _buildFullSongGate(),
              },
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            if (_feedback != null && _listening)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _feedback!.summary,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _feedback!.matchStatus == ChordMatchStatus.perfect
                        ? AppColors.success
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _buildBottomActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    if (_step == _GuidedStep.fullSong) {
      return FilledButton.icon(
        onPressed: _openFullSong,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('נגן את השיר המלא'),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy
                ? null
                : (_listening
                    ? () => unawaited(_stopAll())
                    : () => unawaited(_startStepPractice())),
            icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(
              _busy
                  ? 'מתחבר…'
                  : (_listening ? 'עצור' : 'התחל שלב זה'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'הסבר פריטה',
          onPressed: () => unawaited(showStrummingHelpSheet(context)),
          icon: const Icon(Icons.help_outline_rounded),
          color: AppColors.turquoise,
        ),
      ],
    );
  }

  Widget _buildTransitions() {
    if (_pairs.isEmpty) {
      return const Center(
        child: Text(
          'אין מעברי אקורדים בשיר זה',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final pair = _pairs[_pairIndex.clamp(0, _pairs.length - 1)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        const Text(
          'שלב 1 — מעברי אקורדים',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'נגנו את האקורד היעד. אחרי מעבר נקי המערכת תתקדם לזוג הבא.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration(
            borderColor: AppColors.amber.withValues(alpha: 0.4),
          ),
          child: Column(
            children: [
              Text(
                'מעבר ${_pairIndex + 1} מתוך ${_pairs.length}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ChordBadge(label: _label(pair.fromId), dim: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: AppColors.amberBright),
                  ),
                  _ChordBadge(label: _label(pair.toId), dim: false),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'יעד: ${_label(pair.toId)}',
                style: const TextStyle(
                  color: AppColors.amberBright,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _pairs.length; i++)
              Chip(
                label: Text(
                  '${_label(_pairs[i].fromId)}→${_label(_pairs[i].toId)}',
                ),
                backgroundColor: i == _pairIndex
                    ? AppColors.amber.withValues(alpha: 0.25)
                    : (i < _pairIndex
                        ? AppColors.success.withValues(alpha: 0.2)
                        : AppColors.surfaceElevated),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGradual() {
    final currentId = _chordIds.isEmpty
        ? ''
        : _chordIds[_seqIndex.clamp(0, _chordIds.length - 1)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        const Text(
          'שלב 2 — פריטה בקצב מתגבר',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'מתחילים ב־${(0.6 * 100).round()}% מה־BPM ומעלים אחרי כל סיבוב מוצלח '
          'עד ${widget.song.bpm}.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'BPM תרגול: $_effectiveBpm / ${widget.song.bpm}',
                style: const TextStyle(
                  color: AppColors.turquoise,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              'סיבובים: $_successfulRounds',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: _bpmFactor.clamp(0.0, 1.0),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 14),
        StrummingPatternWidget(
          pattern: widget.song.pattern,
          activeIndex: _listening ? _strokeIndex : null,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(
            borderColor: AppColors.turquoise.withValues(alpha: 0.35),
          ),
          child: Column(
            children: [
              const Text(
                'אקורד נוכחי',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Text(
                _label(currentId),
                style: const TextStyle(
                  color: AppColors.amberBright,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${_seqIndex + 1} / ${_chordIds.length}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFullSongGate() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_rounded,
              size: 56, color: AppColors.amberBright),
          const SizedBox(height: 16),
          const Text(
            'שלב 3 — השיר המלא',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'מוכנים לנגן את «${widget.song.title}» ב־${widget.song.bpm} BPM '
            'עם דפוס הפריטה שלמדתם.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final _GuidedStep step;

  @override
  Widget build(BuildContext context) {
    final index = switch (step) {
      _GuidedStep.transitions => 0,
      _GuidedStep.gradualStrum => 1,
      _GuidedStep.fullSong => 2,
    };
    const labels = ['מעברים', 'פריטה', 'שיר מלא'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= index
                    ? AppColors.turquoise
                    : AppColors.textMuted.withValues(alpha: 0.25),
              ),
            ),
          Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: i <= index
                    ? AppColors.turquoise
                    : AppColors.surfaceElevated,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: i <= index
                        ? AppColors.onPrimaryDark
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: TextStyle(
                  color: i == index
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChordBadge extends StatelessWidget {
  const _ChordBadge({required this.label, required this.dim});

  final String label;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: dim
            ? AppColors.surfaceElevated
            : AppColors.amber.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dim
              ? AppColors.textMuted.withValues(alpha: 0.3)
              : AppColors.amberBright,
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          label,
          style: TextStyle(
            color: dim ? AppColors.textMuted : AppColors.amberBright,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _Pair {
  const _Pair({required this.fromId, required this.toId});
  final String fromId;
  final String toId;
}
