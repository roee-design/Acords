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

/// Main practice UI: chord picker, live fretboard feedback, and coaching tip.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.catalog,
    this.isActive = true,
  });

  final ChordCatalog catalog;

  /// When false, mic capture must stop (for consistency with tab screens).
  final bool isActive;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
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

  late ChordDefinition _selectedChord;
  ChordFeedback? _feedback;
  var _listening = false;
  var _busy = false;
  var _successGlow = false;
  var _showConfetti = false;
  var _confettiTick = 0;
  var _wasPerfect = false;
  /// Serializes stop/start so tab/nav switches cannot leave the mic on.
  var _lifecycleEpoch = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedChord = widget.catalog.chords.first;
    _feedback = _matcher.idleFeedback(_selectedChord);

    _feedbackSubscription = _analyzer.feedbackStream.listen(
      (feedback) {
        if (!mounted) return;
        final isPerfect = feedback.matchStatus == ChordMatchStatus.perfect;
        if (isPerfect && !_wasPerfect && _listening) {
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

    _analyzer.setTargetChord(
      _selectedChord,
      referenceA4Hz: widget.catalog.referenceA4Hz,
    );
  }

  @override
  void didUpdateWidget(covariant PracticeScreen oldWidget) {
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

  Future<void> _onChordChanged(ChordDefinition? chord) async {
    if (chord == null || chord.id == _selectedChord.id) {
      return;
    }

    final wasListening = _listening;
    if (wasListening) {
      await _analyzer.stop();
    }

    setState(() {
      _selectedChord = chord;
      _feedback = _matcher.idleFeedback(chord);
      _errorMessage = null;
      _listening = false;
      _wasPerfect = false;
      _successGlow = false;
      _showConfetti = false;
    });

    _analyzer.setTargetChord(
      chord,
      referenceA4Hz: widget.catalog.referenceA4Hz,
    );

    if (wasListening) {
      await _startListening();
    }
  }

  Future<void> _toggleListening() async {
    if (_busy || !widget.isActive) {
      return;
    }

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
      _analyzer.setTargetChord(
        _selectedChord,
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
        _feedback = _matcher.idleFeedback(_selectedChord);
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
    final liveStatuses = _liveStatuses(feedback);
    final tip = ChordCoachTip.fromFeedback(
      listening: _listening,
      feedback: feedback,
      idleMessage:
          'לחץ "התחל האזנה" ונגן את ${_selectedChord.displayName} — הדיאגרמה תאיר לפי הצליל.',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('אימון אקורד בודד'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 8, end: 12),
            child: Center(child: HelpButton(topic: HelpTopic.practice)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChordHeroDisplay(
                chordName: _selectedChord.displayName,
                label: 'אקורד יעד',
                chord: _selectedChord,
                showFretboard: false,
                successGlow: _successGlow,
                showConfetti: _showConfetti,
                confettiTick: _confettiTick,
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'בחר אקורד',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<ChordDefinition>(
                        key: ValueKey(_selectedChord.id),
                        initialValue: _selectedChord,
                        isExpanded: true,
                        dropdownColor: AppColors.surfaceElevated,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        items: widget.catalog.chords
                            .map(
                              (chord) => DropdownMenuItem(
                                value: chord,
                                child: Text(chord.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: _busy ? null : _onChordChanged,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                          : 'התחל האזנה',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _listening
                      ? AppColors.error
                      : AppColors.turquoise,
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
              const SizedBox(height: 20),
              Text(
                'דיאגרמת ${_selectedChord.displayName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              ChordFretboardFrame(
                chord: _selectedChord,
                borderRadius: 16,
                liveStatuses: liveStatuses,
              ),
              const SizedBox(height: 10),
              ChordFretboardLegend(
                accent: chordAccentColor(_selectedChord),
              ),
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
