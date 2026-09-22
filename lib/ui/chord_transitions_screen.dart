import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../audio/audio_analyzer.dart';
import '../audio/fft_processor.dart';
import '../audio/mic_capture_guard.dart';
import '../chord/chord_matcher.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import 'app_theme.dart';
import 'widgets/chord_fretboard_chart.dart';
import 'widgets/help_sheet.dart';

/// Chord transition practice: metronome-driven alternation between two chords
/// with real-time detection feedback via [AudioAnalyzer].
class ChordTransitionsScreen extends StatefulWidget {
  const ChordTransitionsScreen({
    super.key,
    required this.catalog,
    this.isActive = true,
  });

  final ChordCatalog catalog;

  /// When false, mic + metronome must stop (for consistency with tab screens).
  final bool isActive;

  @override
  State<ChordTransitionsScreen> createState() => _ChordTransitionsScreenState();
}

class _ChordTransitionsScreenState extends State<ChordTransitionsScreen>
    with TickerProviderStateMixin {
  // Metronome-driven chord transition training screen state.
  static const int _fftSize = 8192;
  static const int _sampleRate = 44100;
  static const int _minBpm = 40;
  static const int _maxBpm = 120;
  /// Natural timing window vs nearest metronome tick (strum + FFT lag).
  static const int _timingToleranceMs = 250;

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

  /// Rotating media players for metronome clicks (seek works; lowLatency does not).
  static const int _clickPoolSize = 3;
  final List<AudioPlayer> _clickPlayers = [];
  var _clickIndex = 0;
  var _clickReady = false;
  Future<void>? _clickPrepareFuture;

  StreamSubscription<ChordFeedback>? _feedbackSubscription;
  Timer? _metronomeTimer;
  late final AnimationController _pulseController;

  late ChordDefinition _chordA;
  late ChordDefinition _chordB;
  late ChordDefinition _currentTarget;

  var _bpm = 60;
  var _isRunning = false;
  var _busy = false;
  var _gradualSpeedUp = false;
  var _metronomeSound = true;
  var _currentBeat = 1;
  var _detectedThisMeasure = false;
  var _perfectThisMeasure = false;
  /// True when a correct chord was heard within ±[_timingToleranceMs] of a tick.
  var _onTimeThisMeasure = false;
  var _consecutivePerfect = 0;
  var _consecutiveFailures = 0;
  var _successGlow = false;
  var _showConfetti = false;
  var _confettiTick = 0;
  /// Most recent metronome tick — used to measure distance to nearest beat.
  DateTime? _lastTickAt;
  /// Serializes stop/start so leaving the screen cannot leave mic/metronome on.
  var _lifecycleEpoch = 0;
  String? _measureFeedback;
  ChordFeedback? _feedback;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _clickPrepareFuture = _prepareClickPlayers();

    final chords = widget.catalog.chords;
    _chordA =
        chords.firstWhere((c) => c.id == 'e_minor', orElse: () => chords.first);
    _chordB =
        chords.firstWhere((c) => c.id == 'g_major', orElse: () => chords[1]);
    _currentTarget = _chordA;
    _feedback = _matcher.idleFeedback(_currentTarget);

    _feedbackSubscription = _analyzer.feedbackStream.listen(
      _onChordFeedback,
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _errorMessage = error.toString();
            _isRunning = false;
            _busy = false;
          });
          _stopMetronome();
          unawaited(_stopClickPlayers());
          unawaited(_analyzer.stop());
          MicCaptureGuard.instance.release(this);
        }
      },
    );
  }

  /// Mix with the mic recorder — do not steal exclusive audio focus.
  static AudioContext get _clickAudioContext => AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      );

  Future<void> _prepareClickPlayers() async {
    try {
      for (var i = 0; i < _clickPoolSize; i++) {
        final player = AudioPlayer();
        // mediaPlayer supports seek/replay; lowLatency silently ignores seek.
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setAudioContext(_clickAudioContext);
        await player.setVolume(1);
        await player.setSource(AssetSource('metronome_click.wav'));
        _clickPlayers.add(player);
      }
      _clickReady = _clickPlayers.isNotEmpty;
    } catch (_) {
      _clickReady = false;
      _clickPlayers.clear();
    }
  }

  @override
  void didUpdateWidget(covariant ChordTransitionsScreen oldWidget) {
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
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
    _pulseController.dispose();
    _feedbackSubscription?.cancel();
    for (final player in _clickPlayers) {
      unawaited(player.stop());
      unawaited(player.dispose());
    }
    unawaited(_analyzer.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_analyzer.dispose());
    super.dispose();
  }

  bool get _isCapturing =>
      _isRunning || _busy || _analyzer.isListening || _metronomeTimer != null;

  Future<void> _stopIfCapturing() async {
    if (_isCapturing) {
      await _stopTraining();
    }
  }

  Future<void> _stopClickPlayers() async {
    for (final player in _clickPlayers) {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  ChordDefinition get _nextChord =>
      _currentTarget.id == _chordA.id ? _chordB : _chordA;

  Duration get _beatInterval => Duration(
        milliseconds: (60000 / _bpm).round(),
      );

  void _recordTick(DateTime at) {
    _lastTickAt = at;
  }

  /// Absolute ms from [tDetect] to the nearest metronome tick (previous or next).
  int? _msToNearestTick(DateTime tDetect) {
    final last = _lastTickAt;
    if (last == null) return null;
    final toLast = (tDetect.difference(last).inMilliseconds).abs();
    final next = last.add(_beatInterval);
    final toNext = (tDetect.difference(next).inMilliseconds).abs();
    return toLast < toNext ? toLast : toNext;
  }

  void _onChordFeedback(ChordFeedback feedback) {
    if (!mounted) return;

    setState(() => _feedback = feedback);

    if (!_isRunning) return;
    if (feedback.chordId != _currentTarget.id) return;
    if (feedback.matchStatus == ChordMatchStatus.waiting) return;

    final isChordCorrect = feedback.matchStatus == ChordMatchStatus.perfect;
    if (!isChordCorrect) {
      if (feedback.matchStatus == ChordMatchStatus.close &&
          !_detectedThisMeasure) {
        setState(() => _detectedThisMeasure = true);
      }
      return;
    }

    // Continuous detection: score timing against the nearest tick.
    final tDetect = DateTime.now();
    final distMs = _msToNearestTick(tDetect);
    if (distMs == null) return;

    final onTime = distMs <= _timingToleranceMs;
    // ignore: avoid_print
    print(
      '[Acords Timing] perfect chord=${feedback.chordName} '
      'distNearestTick=${distMs}ms onTime=$onTime '
      '(tol=±${_timingToleranceMs}ms)',
    );

    if (!_perfectThisMeasure || (onTime && !_onTimeThisMeasure)) {
      setState(() {
        _detectedThisMeasure = true;
        _perfectThisMeasure = true;
        if (onTime) {
          _onTimeThisMeasure = true;
        }
      });
    }
  }

  void _restartMetronomeTimer() {
    _metronomeTimer?.cancel();
    if (!_isRunning) return;
    _metronomeTimer = Timer.periodic(_beatInterval, (_) => _onBeatTick());
  }

  void _adjustBpm(int delta) {
    final newBpm = (_bpm + delta).clamp(_minBpm, _maxBpm);
    if (newBpm == _bpm) return;
    _bpm = newBpm;
    _restartMetronomeTimer();
  }

  void _triggerBeatPulse() {
    _pulseController.forward(from: 0);
  }

  void _playMetronomeClick({required bool accent}) {
    // No mic blanking — continuous FFT must hear strums on the tick.
    if (!_metronomeSound) return;
    if (!_clickReady || _clickPlayers.isEmpty) return;

    final volume = accent ? 1.0 : 0.7;
    final player = _clickPlayers[_clickIndex % _clickPlayers.length];
    _clickIndex++;
    unawaited(_fireClick(player, volume));
  }

  Future<void> _fireClick(AudioPlayer player, double volume) async {
    try {
      // stop + seek + resume works with mediaPlayer (not with lowLatency).
      await player.stop();
      await player.setVolume(volume);
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {
      // Last resort: full play() resets the source and starts immediately.
      try {
        await player.play(
          AssetSource('metronome_click.wav'),
          volume: volume,
          ctx: _clickAudioContext,
        );
      } catch (_) {}
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

  void _onBeatTick() {
    if (!mounted) return;
    final tickAt = DateTime.now();
    _recordTick(tickAt);
    _triggerBeatPulse();

    if (_currentBeat == 4) {
      _endMeasure();
      setState(() {
        _currentBeat = 1;
        _currentTarget = _nextChord;
      });
      _playMetronomeClick(accent: true);
      // Retarget without clearing FFT — keep listening continuously.
      _applyAnalyzerTarget(resetAnalysis: false);
    } else {
      setState(() {
        _currentBeat++;
        if (_currentBeat == 2) {
          _measureFeedback = null;
        }
      });
      _playMetronomeClick(accent: false);
    }
  }

  void _applyAnalyzerTarget({bool resetAnalysis = true}) {
    _analyzer.setTargetChord(
      _currentTarget,
      referenceA4Hz: widget.catalog.referenceA4Hz,
      resetAnalysis: resetAnalysis,
    );
  }

  void _endMeasure() {
    final isChordCorrect = _perfectThisMeasure;
    final onTime = _onTimeThisMeasure;

    // ignore: avoid_print
    print(
      '[Acords Timing] measure END isChordCorrect=$isChordCorrect onTime=$onTime',
    );

    if (isChordCorrect && onTime) {
      _measureFeedback = 'בזמן! 🎯';
      _consecutiveFailures = 0;
      _triggerSuccessEffects();

      _consecutivePerfect++;
      if (_gradualSpeedUp && _consecutivePerfect >= 2) {
        _adjustBpm(5);
        _consecutivePerfect = 0;
      }
    } else if (isChordCorrect && !onTime) {
      _consecutivePerfect = 0;
      _measureFeedback = 'אקורד נכון, אבל לא בזמן';
    } else if (_detectedThisMeasure) {
      _consecutivePerfect = 0;
      _measureFeedback = 'האקורד לא מדויק';
    } else {
      _consecutivePerfect = 0;
      _consecutiveFailures++;
      _measureFeedback = 'פספסת את הקצב ⏱️';

      if (_gradualSpeedUp && _consecutiveFailures >= 2) {
        _adjustBpm(-5);
        _consecutiveFailures = 0;
      }
    }

    _detectedThisMeasure = false;
    _perfectThisMeasure = false;
    _onTimeThisMeasure = false;
    setState(() {});
  }

  void _stopMetronome() {
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
  }

  Future<void> _toggleTraining() async {
    if (_busy || !widget.isActive) return;

    if (_isRunning) {
      await _stopTraining();
      return;
    }

    await _startTraining();
  }

  Future<void> _startTraining() async {
    if (!widget.isActive) return;
    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _measureFeedback = null;
      _consecutivePerfect = 0;
      _consecutiveFailures = 0;
      _detectedThisMeasure = false;
      _perfectThisMeasure = false;
      _onTimeThisMeasure = false;
      _successGlow = false;
      _showConfetti = false;
      _currentBeat = 1;
      _currentTarget = _chordA;
    });

    try {
      await MicCaptureGuard.instance.claim(this, _stopTraining);
      // Ensure click players are ready before the first tick.
      await (_clickPrepareFuture ?? _prepareClickPlayers());

      _applyAnalyzerTarget();
      await _analyzer.start();

      if (epoch != _lifecycleEpoch || !mounted || !widget.isActive) {
        _stopMetronome();
        await _stopClickPlayers();
        await _analyzer.stop();
        MicCaptureGuard.instance.release(this);
        if (mounted && epoch == _lifecycleEpoch) {
          setState(() => _busy = false);
        }
        return;
      }

      setState(() {
        _isRunning = true;
        _busy = false;
      });

      final startBeat = DateTime.now();
      _recordTick(startBeat);
      _playMetronomeClick(accent: true);
      _triggerBeatPulse();
      _metronomeTimer = Timer.periodic(_beatInterval, (_) => _onBeatTick());
    } catch (error) {
      _stopMetronome();
      await _stopClickPlayers();
      await _analyzer.stop();
      MicCaptureGuard.instance.release(this);
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() {
          _errorMessage = error.toString();
          _isRunning = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _stopTraining() async {
    final epoch = ++_lifecycleEpoch;
    if (!_isRunning && !_busy && !_analyzer.isListening && _metronomeTimer == null) {
      MicCaptureGuard.instance.release(this);
      return;
    }
    setState(() => _busy = true);
    _stopMetronome();
    await _stopClickPlayers();
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);

    if (mounted && epoch == _lifecycleEpoch) {
      setState(() {
        _isRunning = false;
        _busy = false;
        _currentBeat = 1;
        _currentTarget = _chordA;
        _measureFeedback = null;
        _consecutivePerfect = 0;
        _consecutiveFailures = 0;
        _detectedThisMeasure = false;
        _perfectThisMeasure = false;
        _onTimeThisMeasure = false;
        _lastTickAt = null;
        _successGlow = false;
        _showConfetti = false;
        _feedback = _matcher.idleFeedback(_chordA);
      });
    }
  }

  void _changeBpm(int delta) {
    if (_isRunning) return;
    setState(() {
      _bpm = (_bpm + delta).clamp(_minBpm, _maxBpm);
    });
  }

  @override
  Widget build(BuildContext context) {
    final feedback = _feedback;
    final matchStatus = feedback?.matchStatus ?? ChordMatchStatus.waiting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('אימון מעברי אקורדים'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 8, end: 12),
            child: Center(child: HelpButton(topic: HelpTopic.transitions)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ChordDropdown(
                      label: 'אקורד א\'',
                      value: _chordA,
                      chords: widget.catalog.chords,
                      enabled: !_isRunning && !_busy,
                      showFretboard: false,
                      onChanged: (chord) {
                        if (chord != null) setState(() => _chordA = chord);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChordDropdown(
                      label: 'אקורד ב\'',
                      value: _chordB,
                      chords: widget.catalog.chords,
                      enabled: !_isRunning && !_busy,
                      showFretboard: false,
                      onChanged: (chord) {
                        if (chord != null) setState(() => _chordB = chord);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _BpmSpeedometer(
                bpm: _bpm,
                minBpm: _minBpm,
                maxBpm: _maxBpm,
                enabled: !_isRunning && !_busy,
                compact: true,
                onChanged: (value) => setState(() => _bpm = value),
                onStep: _changeBpm,
              ),
              SwitchListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                title: const Text('האצה הדרגתית', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '5 BPM אחרי 2 מעברים עם תזמון ואקורד נכונים',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                value: _gradualSpeedUp,
                onChanged: _isRunning
                    ? null
                    : (value) => setState(() => _gradualSpeedUp = value),
              ),
              SwitchListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  _metronomeSound
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: _metronomeSound
                      ? AppColors.turquoise
                      : AppColors.textMuted,
                  size: 22,
                ),
                title: const Text('סאונד מטרונום', style: TextStyle(fontSize: 14)),
                value: _metronomeSound,
                onChanged: (value) => setState(() => _metronomeSound = value),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _toggleTraining,
                icon: Icon(
                  _isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(
                  _busy
                      ? 'אנא המתן…'
                      : _isRunning
                          ? 'עצור'
                          : 'התחל אימון',
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _isRunning
                      ? AppColors.error
                      : AppColors.turquoise,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              _OrganicMetronome(
                currentBeat: _currentBeat,
                isRunning: _isRunning,
                pulseAnimation: _pulseController,
                compact: true,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _ChordCardsDisplay(
                  currentChord: _currentTarget,
                  nextChord: _nextChord,
                  isRunning: _isRunning,
                  successGlow: _successGlow,
                  showConfetti: _showConfetti,
                  confettiTick: _confettiTick,
                ),
              ),
              if (_measureFeedback != null) ...[
                const SizedBox(height: 6),
                _MeasureFeedbackBanner(message: _measureFeedback!),
              ],
              const SizedBox(height: 6),
              _DetectionBanner(
                summary: feedback?.summary ?? 'מוכן לאימון',
                matchStatus: matchStatus,
                inputLevel: feedback?.inputLevel ?? 0,
                listening: _isRunning,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChordDropdown extends StatelessWidget {
  const _ChordDropdown({
    required this.label,
    required this.value,
    required this.chords,
    required this.enabled,
    required this.onChanged,
    this.showFretboard = false,
  });

  final String label;
  final ChordDefinition value;
  final List<ChordDefinition> chords;
  final bool enabled;
  final ValueChanged<ChordDefinition?> onChanged;
  final bool showFretboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ChordDefinition>(
          key: ValueKey('${label}_${value.id}'),
          initialValue: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          items: chords
              .map(
                (chord) => DropdownMenuItem(
                  value: chord,
                  child: Text(
                    chord.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
        if (showFretboard) ...[
          const SizedBox(height: 8),
          ChordFretboardFrame(
            chord: value,
          ),
        ],
      ],
    );
  }
}

/// Semi-circular speedometer gauge for BPM selection.
class _BpmSpeedometer extends StatelessWidget {
  const _BpmSpeedometer({
    required this.bpm,
    required this.minBpm,
    required this.maxBpm,
    required this.enabled,
    required this.onChanged,
    required this.onStep,
    this.compact = false,
  });

  final int bpm;
  final int minBpm;
  final int maxBpm;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final void Function(int delta) onStep;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gaugeHeight = compact ? 72.0 : 150.0;
    final bpmFont = compact ? 28.0 : 40.0;

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 16,
          compact ? 8 : 20,
          compact ? 10 : 16,
          compact ? 4 : 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: gaugeHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: _SpeedometerPainter(
                  bpm: bpm,
                  minBpm: minBpm,
                  maxBpm: maxBpm,
                ),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: compact ? 18 : 36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$bpm',
                          style: TextStyle(
                            fontSize: bpmFont,
                            fontWeight: FontWeight.bold,
                            color: AppColors.amberBright,
                            height: 1,
                          ),
                        ),
                        Text(
                          'BPM',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: compact ? 11 : 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundIconButton(
                  icon: Icons.remove,
                  enabled: enabled && bpm > minBpm,
                  onTap: () => onStep(-5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppColors.turquoise,
                      inactiveTrackColor:
                          AppColors.turquoise.withValues(alpha: 0.2),
                      thumbColor: AppColors.amberBright,
                      overlayColor:
                          AppColors.amber.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: bpm.toDouble(),
                      min: minBpm.toDouble(),
                      max: maxBpm.toDouble(),
                      divisions: maxBpm - minBpm,
                      label: '$bpm',
                      onChanged:
                          enabled ? (v) => onChanged(v.round()) : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  icon: Icons.add,
                  enabled: enabled && bpm < maxBpm,
                  onTap: () => onStep(5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.turquoise.withValues(alpha: 0.18)
          : AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 22,
            color: enabled
                ? AppColors.turquoise
                : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  _SpeedometerPainter({
    required this.bpm,
    required this.minBpm,
    required this.maxBpm,
  });

  final int bpm;
  final int minBpm;
  final int maxBpm;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.88);
    final radius = math.min(size.width, size.height) * 0.42;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final trackPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final progress = (bpm - minBpm) / (maxBpm - minBpm);
    final progressPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: [AppColors.turquoiseDim, AppColors.amberBright],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );

    final needleAngle = startAngle + sweepAngle * progress;
    final needleEnd = Offset(
      center.dx + math.cos(needleAngle) * (radius - 8),
      center.dy + math.sin(needleAngle) * (radius - 8),
    );

    final needlePaint = Paint()
      ..color = AppColors.amberBright
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);

    canvas.drawCircle(
      center,
      7,
      Paint()..color = AppColors.amberBright,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) {
    return oldDelegate.bpm != bpm;
  }
}

/// Central breathing circle + beat indicators with smooth pulse animation.
class _OrganicMetronome extends StatelessWidget {
  const _OrganicMetronome({
    required this.currentBeat,
    required this.isRunning,
    required this.pulseAnimation,
    this.compact = false,
  });

  final int currentBeat;
  final bool isRunning;
  final AnimationController pulseAnimation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final circleSize = compact ? 48.0 : 88.0;
    final beatDots = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final beat = index + 1;
        final active = isRunning && beat == currentBeat;
        final isDownbeat = beat == 1;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: active ? (compact ? 11.0 : 14.0) : (compact ? 8.0 : 10.0),
            height: active ? (compact ? 11.0 : 14.0) : (compact ? 8.0 : 10.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? (isDownbeat
                      ? AppColors.amberBright
                      : AppColors.turquoise)
                  : AppColors.textMuted.withValues(alpha: 0.25),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: (isDownbeat
                                ? AppColors.amber
                                : AppColors.turquoise)
                            .withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );

    final pulse = AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final t = Curves.easeOut.transform(pulseAnimation.value);
        final scale = 1.0 + (1.0 - t) * (compact ? 0.22 : 0.35);
        final glowOpacity = (1.0 - t) * 0.55;

        return Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isRunning
                ? [
                    BoxShadow(
                      color: AppColors.turquoise.withValues(alpha: glowOpacity),
                      blurRadius: compact ? 16 : 28,
                      spreadRadius: (compact ? 3 : 6) * (1.0 - t),
                    ),
                  ]
                : null,
          ),
          child: Transform.scale(
            scale: isRunning ? scale : 1.0,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isRunning
                      ? [
                          AppColors.turquoise,
                          AppColors.turquoiseDim,
                        ]
                      : [
                          AppColors.surface,
                          AppColors.surfaceElevated,
                        ],
                ),
                border: Border.all(
                  color: isRunning
                      ? AppColors.turquoise
                      : AppColors.textMuted.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                isRunning ? '$currentBeat' : '♩',
                style: TextStyle(
                  fontSize: compact ? 20 : 32,
                  fontWeight: FontWeight.bold,
                  color: isRunning
                      ? const Color(0xFF042F2E)
                      : AppColors.textMuted,
                ),
              ),
            ),
          ),
        );
      },
    );

    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 8 : 20,
          horizontal: compact ? 12 : 16,
        ),
        child: compact
            ? Row(
                children: [
                  Text(
                    isRunning ? 'פעימה $currentBeat/4' : 'מטרונום',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  beatDots,
                  const SizedBox(width: 12),
                  pulse,
                ],
              )
            : Column(
                children: [
                  Text(
                    isRunning ? 'פעימה $currentBeat מתוך 4' : 'מטרונום',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  pulse,
                  const SizedBox(height: 18),
                  beatDots,
                ],
              ),
      ),
    );
  }
}

class _ChordCardsDisplay extends StatelessWidget {
  const _ChordCardsDisplay({
    required this.currentChord,
    required this.nextChord,
    required this.isRunning,
    required this.successGlow,
    required this.showConfetti,
    required this.confettiTick,
  });

  final ChordDefinition currentChord;
  final ChordDefinition nextChord;
  final bool isRunning;
  final bool successGlow;
  final bool showConfetti;
  final int confettiTick;

  @override
  Widget build(BuildContext context) {
    final currentAccent = chordAccentColor(currentChord);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: successGlow
                ? [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.75),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Card(
            margin: EdgeInsets.zero,
            color: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: successGlow
                    ? AppColors.success
                    : AppColors.turquoise.withValues(alpha: 0.45),
                width: successGlow ? 2.5 : 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRunning ? 'נגן עכשיו' : 'אקורד יעד',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              child: Text(
                                currentChord.displayName,
                                key: ValueKey(currentChord.id),
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isRunning)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.amber.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: AppColors.amber.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'הבא: ${nextChord.displayName}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.amber.withValues(alpha: 0.95),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ChordFretboardFrame(
                      chord: currentChord,
                      accent: currentAccent,
                      borderRadius: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showConfetti)
          Positioned(
            top: 12,
            child: _ConfettiBurst(key: ValueKey(confettiTick)),
          ),
      ],
    );
  }
}

/// Lightweight confetti burst — no external packages.
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst({super.key});

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();

    const colors = [
      AppColors.success,
      AppColors.amberBright,
      AppColors.turquoise,
      Color(0xFFA7F3D0),
    ];

    _particles = List.generate(22, (i) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = 40 + _rng.nextDouble() * 70;
      return _ConfettiParticle(
        color: colors[i % colors.length],
        angle: angle,
        speed: speed,
        size: 5 + _rng.nextDouble() * 5,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 220,
          height: 120,
          child: CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: Curves.easeOut.transform(_controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.color,
    required this.angle,
    required this.speed,
    required this.size,
  });

  final Color color;
  final double angle;
  final double speed;
  final double size;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.7);

    for (final p in particles) {
      final distance = p.speed * progress;
      final x = origin.dx + math.cos(p.angle) * distance;
      final y = origin.dy + math.sin(p.angle) * distance - progress * 30;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, y),
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _MeasureFeedbackBanner extends StatelessWidget {
  const _MeasureFeedbackBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isSuccess = message.contains('🎯');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: isSuccess
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess ? AppColors.success : AppColors.amber,
          width: 1.5,
        ),
        boxShadow: isSuccess
            ? [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isSuccess ? AppColors.success : AppColors.amberBright,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _DetectionBanner extends StatelessWidget {
  const _DetectionBanner({
    required this.summary,
    required this.matchStatus,
    required this.inputLevel,
    required this.listening,
  });

  final String summary;
  final ChordMatchStatus matchStatus;
  final double inputLevel;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.feedbackColors(matchStatus);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            summary,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (listening) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: inputLevel.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.black26,
                color: AppColors.turquoise,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
