import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/audio_analyzer.dart';
import '../audio/mic_capture_guard.dart';
import '../audio/strum_preview_service.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import '../models/strumming_pattern.dart';
import '../services/strum_pattern_catalog_service.dart';
import 'app_theme.dart';
import 'navigation/app_page_route.dart';
import 'widgets/strumming_help_sheet.dart';
import 'widgets/strumming_pattern_widget.dart';

/// Central hub: pick a core strumming pattern and run the 3-step learning path.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('לימוד פריטות')),
      body: SafeArea(
        child: _buildBody(),
      ),
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
    if (_patterns == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _patterns!.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Text(
            'בחרו דפוס פריטה מרכזי. כל דפוס כולל מסלול של 3 שלבים: '
            'מעברי אקורדים → פריטה בקצב מתגבר → לולאה מלאה.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35),
          );
        }
        final pattern = _patterns![index - 1];
        return Material(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(
                AppPageRoute<void>(
                  page: _PatternGuidedPathScreen(
                    pattern: pattern,
                    chordCatalog: widget.catalog,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        pattern.isArpeggio
                            ? Icons.piano_rounded
                            : Icons.graphic_eq_rounded,
                        color: AppColors.turquoise,
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
                        '${pattern.defaultBpm} BPM',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Guided path for one core pattern
// -----------------------------------------------------------------------------

enum _Step { transitions, gradual, loop }

class _PatternGuidedPathScreen extends StatefulWidget {
  const _PatternGuidedPathScreen({
    required this.pattern,
    required this.chordCatalog,
  });

  final StrummingPattern pattern;
  final ChordCatalog chordCatalog;

  @override
  State<_PatternGuidedPathScreen> createState() =>
      _PatternGuidedPathScreenState();
}

class _PatternGuidedPathScreenState extends State<_PatternGuidedPathScreen> {
  static const int _fftSize = 8192;
  static const int _sampleRate = 44100;
  static const Duration _grace = Duration(milliseconds: 300);

  final AudioAnalyzer _analyzer = AudioAnalyzer(
    sampleRate: _sampleRate,
    fftSize: _fftSize,
  );

  StreamSubscription<ChordFeedback>? _feedbackSub;
  var _step = _Step.transitions;
  var _listening = false;
  var _busy = false;
  var _lifecycleEpoch = 0;
  var _wasPerfect = false;
  var _chordIndex = 0;
  var _strokeIndex = 0;
  var _bpmFactor = 0.6;
  var _successfulRounds = 0;
  var _previewPlaying = false;
  String? _errorMessage;
  ChordFeedback? _feedback;

  late final List<String> _chordIds;

  @override
  void initState() {
    super.initState();
    _chordIds = widget.pattern.practiceChordIds.isNotEmpty
        ? widget.pattern.practiceChordIds
        : const ['g_major', 'c_major', 'd_major', 'g_major'];
    _feedbackSub = _analyzer.feedbackStream.listen(_onFeedback);
    unawaited(StrumPreviewService.instance.ensureReady());
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _lifecycleEpoch++;
    unawaited(StrumPreviewService.instance.stop());
    unawaited(_analyzer.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_analyzer.dispose());
    super.dispose();
  }

  int get _effectiveBpm =>
      max(40, (widget.pattern.defaultBpm * _bpmFactor).round());

  String _label(String id) =>
      widget.chordCatalog.chordById(id)?.displayName ?? id;

  Future<void> _stopAll() async {
    final epoch = ++_lifecycleEpoch;
    await StrumPreviewService.instance.stop();
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
    if (!mounted || epoch != _lifecycleEpoch) return;
    setState(() {
      _listening = false;
      _busy = false;
      _previewPlaying = false;
      _wasPerfect = false;
      _strokeIndex = 0;
    });
  }

  void _goTo(_Step step) {
    unawaited(_stopAll());
    setState(() {
      _step = step;
      _chordIndex = 0;
      _strokeIndex = 0;
      _wasPerfect = false;
      _errorMessage = null;
      _feedback = null;
      if (step == _Step.gradual) {
        _bpmFactor = 0.6;
        _successfulRounds = 0;
      }
    });
  }

  Future<void> _startMicPractice() async {
    if (_busy || _listening || _chordIds.isEmpty) return;
    await StrumPreviewService.instance.stop();
    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _chordIndex = 0;
      _wasPerfect = false;
    });
    try {
      await MicCaptureGuard.instance.claim(this, _stopAll);
      final def = widget.chordCatalog.chordById(_chordIds.first);
      if (def == null) throw StateError('Missing chord');
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
      if (_step == _Step.gradual || _step == _Step.loop) {
        await _startPreviewAt(_effectiveBpm);
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

  Future<void> _startPreviewAt(int bpm) async {
    setState(() => _previewPlaying = true);
    await StrumPreviewService.instance.play(
      pattern: widget.pattern,
      bpm: bpm,
      onStroke: (i) {
        if (!mounted) return;
        setState(() => _strokeIndex = i);
      },
    );
  }

  Future<void> _togglePreviewOnly() async {
    if (_previewPlaying) {
      await StrumPreviewService.instance.stop();
      if (!mounted) return;
      setState(() {
        _previewPlaying = false;
        _strokeIndex = 0;
      });
      return;
    }
    if (_listening) await _stopAll();
    await _startPreviewAt(
      _step == _Step.gradual ? _effectiveBpm : widget.pattern.defaultBpm,
    );
  }

  void _onFeedback(ChordFeedback feedback) {
    if (!mounted || !_listening) return;
    if (_analyzer.isBlanking) return;
    final isPerfect = feedback.matchStatus == ChordMatchStatus.perfect;
    setState(() => _feedback = feedback);

    if (_step == _Step.transitions || _step == _Step.gradual) {
      if (isPerfect && !_wasPerfect) {
        _advanceChord();
      }
    }
    _wasPerfect = isPerfect;
  }

  void _advanceChord() {
    if (_chordIndex >= _chordIds.length - 1) {
      if (_step == _Step.transitions) {
        unawaited(_stopAll());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('שלב 1 הושלם!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _goTo(_Step.gradual);
        return;
      }
      if (_step == _Step.gradual) {
        _onGradualRoundDone();
        return;
      }
    }
    setState(() {
      _chordIndex += 1;
      _wasPerfect = false;
    });
    final def = widget.chordCatalog.chordById(_chordIds[_chordIndex]);
    if (def != null) {
      _analyzer.setTargetChord(
        def,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
        gracePeriod: _grace,
      );
    }
  }

  void _onGradualRoundDone() {
    setState(() {
      _successfulRounds += 1;
      _chordIndex = 0;
      _wasPerfect = false;
    });
    if (_bpmFactor >= 0.98) {
      unawaited(_stopAll());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('שלב 2 הושלם!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _goTo(_Step.loop);
      return;
    }
    setState(() => _bpmFactor = min(1.0, _bpmFactor + 0.1));
    final def = widget.chordCatalog.chordById(_chordIds.first);
    if (def != null) {
      _analyzer.setTargetChord(
        def,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
        gracePeriod: _grace,
      );
    }
    unawaited(() async {
      await StrumPreviewService.instance.stop();
      await _startPreviewAt(_effectiveBpm);
    }());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('סיבוב מוצלח · BPM $_effectiveBpm'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pattern = widget.pattern;
    final activeStroke =
        (_previewPlaying || _listening) ? _strokeIndex : null;

    return Scaffold(
      appBar: AppBar(title: Text(pattern.name)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _StepDots(step: _step),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  StrummingPatternWidget(
                    pattern: pattern,
                    activeIndex: activeStroke,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_togglePreviewOnly()),
                    icon: Icon(
                      _previewPlaying && !_listening
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(
                      _previewPlaying && !_listening
                          ? 'עצור השמעה'
                          : 'השמע פריטה לדוגמה',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._stepBody(),
                ],
              ),
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
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : (_listening
                              ? () => unawaited(_stopAll())
                              : () => unawaited(_startMicPractice())),
                      icon: Icon(
                        _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(
                        _busy
                            ? 'מתחבר…'
                            : (_listening ? 'עצור' : 'התחל שלב זה'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () =>
                        unawaited(showStrummingHelpSheet(context)),
                    icon: const Icon(Icons.help_outline_rounded),
                    color: AppColors.turquoise,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepBody() {
    switch (_step) {
      case _Step.transitions:
        return [
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
            'נגנו את האקורד המודגש. אחרי מעבר נקי מתקדמים הבא.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _chordIds.length; i++)
                Chip(
                  label: Text(_label(_chordIds[i])),
                  backgroundColor: i == _chordIndex
                      ? AppColors.amber.withValues(alpha: 0.3)
                      : (i < _chordIndex
                          ? AppColors.success.withValues(alpha: 0.2)
                          : AppColors.surfaceElevated),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'יעד: ${_label(_chordIds[_chordIndex.clamp(0, _chordIds.length - 1)])}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.amberBright,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
        ];
      case _Step.gradual:
        return [
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
            'BPM תרגול: $_effectiveBpm / ${widget.pattern.defaultBpm} · '
            'סיבובים: $_successfulRounds',
            style: const TextStyle(
              color: AppColors.turquoise,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _bpmFactor.clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Text(
            'יעד: ${_label(_chordIds[_chordIndex.clamp(0, _chordIds.length - 1)])}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.amberBright,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ];
      case _Step.loop:
        return [
          const Text(
            'שלב 3 — לולאת הפריטה',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'תרגלו את הדפוס בלולאה בקצב המלא. אפשר להאזין לדוגמה או לנגן עם המיקרופון על רצף האקורדים.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          Text(
            'BPM מלא: ${widget.pattern.defaultBpm}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.turquoise,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ];
    }
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final index = switch (step) {
      _Step.transitions => 0,
      _Step.gradual => 1,
      _Step.loop => 2,
    };
    const labels = ['מעברים', 'קצב', 'לולאה'];
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
                  color:
                      i == index ? AppColors.textPrimary : AppColors.textMuted,
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
