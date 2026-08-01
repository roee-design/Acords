import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_analyzer.dart';
import '../audio/fft_processor.dart';
import '../audio/mic_capture_guard.dart';
import '../chord/chord_matcher.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import 'app_theme.dart';
import 'widgets/chord_coach_tip.dart';
import 'widgets/chord_fretboard_chart.dart';
import 'widgets/chord_hero_display.dart';
import 'widgets/help_sheet.dart';

/// Free chord identification — detects any chord from the catalog in real time.
class FreePlayScreen extends StatefulWidget {
  const FreePlayScreen({
    super.key,
    required this.catalog,
    this.isActive = true,
  });

  final ChordCatalog catalog;

  /// When false (e.g. another bottom-nav tab), mic capture must stop.
  final bool isActive;

  @override
  State<FreePlayScreen> createState() => _FreePlayScreenState();
}

class _FreePlayScreenState extends State<FreePlayScreen> {
  static const int _fftSize = 8192;
  static const int _sampleRate = 44100;

  final AudioAnalyzer _analyzer = AudioAnalyzer(
    sampleRate: _sampleRate,
    fftSize: _fftSize,
  );

  late final ChordMatcher _matcher = ChordMatcher(
    fftProcessor: FftProcessor(
      fftSize: _fftSize,
      sampleRate: _sampleRate.toDouble(),
    ),
  );

  StreamSubscription<ChordFeedback>? _feedbackSubscription;

  ChordFeedback? _feedback;
  var _listening = false;
  var _busy = false;
  var _successGlow = false;
  var _showConfetti = false;
  var _confettiTick = 0;
  var _wasPerfect = false;
  /// Serializes stop/start so tab switches cannot leave the mic on.
  var _lifecycleEpoch = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _feedback = _matcher.freePlayWaiting(0);

    _feedbackSubscription = _analyzer.feedbackStream.listen(
      (feedback) {
        if (!mounted) return;
        final isPerfect = feedback.matchStatus == ChordMatchStatus.perfect;
        if (isPerfect && !_wasPerfect) {
          _triggerSuccessEffects();
        }
        setState(() {
          _feedback = feedback;
          _wasPerfect = isPerfect;
        });
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _errorMessage = error.toString();
            _listening = false;
            _busy = false;
          });
          unawaited(_analyzer.stop());
          MicCaptureGuard.instance.release(this);
        }
      },
    );

    _analyzer.setFreePlayCatalog(
      widget.catalog.chords,
      referenceA4Hz: widget.catalog.referenceA4Hz,
    );
  }

  @override
  void didUpdateWidget(covariant FreePlayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      unawaited(_stopIfCapturing());
    }
  }

  @override
  void deactivate() {
    unawaited(_stopIfCapturing());
    super.deactivate();
  }

  @override
  void dispose() {
    _lifecycleEpoch++;
    _feedbackSubscription?.cancel();
    unawaited(_analyzer.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_analyzer.dispose());
    super.dispose();
  }

  bool get _isCapturing =>
      _listening || _busy || _analyzer.isListening;

  Future<void> _stopIfCapturing() async {
    if (_isCapturing) {
      await _stopListening();
    }
  }

  void _triggerSuccessEffects() {
    setState(() {
      _successGlow = true;
      _showConfetti = true;
      _confettiTick++;
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _successGlow = false;
          _showConfetti = false;
        });
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_busy || !widget.isActive) return;

    if (_listening) {
      await _stopListening();
      return;
    }
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!widget.isActive) return;
    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _wasPerfect = false;
    });

    try {
      await MicCaptureGuard.instance.claim(this, _stopListening);
      _analyzer.setFreePlayCatalog(
        widget.catalog.chords,
        referenceA4Hz: widget.catalog.referenceA4Hz,
      );
      await _analyzer.start();
      if (epoch != _lifecycleEpoch || !mounted || !widget.isActive) {
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
    } catch (error) {
      MicCaptureGuard.instance.release(this);
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() {
          _errorMessage = error.toString();
          _listening = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _stopListening() async {
    final epoch = ++_lifecycleEpoch;
    if (!_listening && !_busy && !_analyzer.isListening) {
      MicCaptureGuard.instance.release(this);
      return;
    }
    setState(() => _busy = true);
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
    if (mounted && epoch == _lifecycleEpoch) {
      setState(() {
        _listening = false;
        _busy = false;
        _wasPerfect = false;
        _successGlow = false;
        _showConfetti = false;
        _feedback = _matcher.freePlayWaiting(0);
      });
    }
  }

  Map<int, NoteStatus>? _liveStatuses(ChordFeedback? feedback) {
    if (!_listening || feedback == null || feedback.stringFeedback.isEmpty) {
      return null;
    }
    return {
      for (final s in feedback.stringFeedback) s.stringNumber: s.status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final feedback = _feedback;
    final matchStatus = feedback?.matchStatus ?? ChordMatchStatus.waiting;
    final detectedName = feedback?.chordName ?? '?';
    final displayName =
        matchStatus == ChordMatchStatus.waiting ? '?' : detectedName;
    final detectedChord = feedback != null && feedback.chordId.isNotEmpty
        ? widget.catalog.chordById(feedback.chordId)
        : null;
    final liveStatuses = _liveStatuses(feedback);
    final tip = ChordCoachTip.fromFeedback(
      listening: _listening,
      feedback: feedback,
      idleMessage:
          'לחץ "התחל זיהוי" ונגן אקורד — הדיאגרמה תאיר לפי הצליל.',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('זיהוי חופשי'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 8, end: 12),
            child: Center(child: HelpButton(topic: HelpTopic.freePlay)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'נגן כל אקורד — האפליקציה תזהה אותו בזמן אמת',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ChordHeroDisplay(
                chordName: displayName,
                label: _listening ? 'זוהה' : 'אקורד מזוהה',
                chord: detectedChord,
                showFretboard: false,
                successGlow: _successGlow,
                showConfetti: _showConfetti,
                confettiTick: _confettiTick,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _toggleListening,
                icon: Icon(
                  _listening ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(
                  _busy
                      ? 'אנא המתן…'
                      : _listening
                          ? 'עצור האזנה'
                          : 'התחל זיהוי',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _listening ? AppColors.error : AppColors.turquoise,
                  foregroundColor:
                      _listening ? Colors.white : AppColors.onPrimaryDark,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (detectedChord != null) ...[
                const SizedBox(height: 20),
                Text(
                  'דיאגרמת ${detectedChord.displayName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                ChordFretboardFrame(
                  chord: detectedChord,
                  borderRadius: 16,
                  liveStatuses: liveStatuses,
                ),
                const SizedBox(height: 10),
                ChordFretboardLegend(
                  accent: chordAccentColor(detectedChord),
                ),
              ],
              const SizedBox(height: 16),
              ChordCoachTipCard(
                tip: tip,
                listening: _listening,
                feedback: feedback,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
