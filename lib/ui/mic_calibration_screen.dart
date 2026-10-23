import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/audio_analyzer.dart';
import '../audio/mic_capture_guard.dart';
import '../audio/onset_detector.dart';
import '../game/latency_calibration.dart';
import '../models/chord_definition.dart';
import '../services/progress_service.dart';
import 'app_theme.dart';

enum _CalPhase { intro, running, result }

/// One-time guitar-mode calibration: strum along a slow flashing circle so
/// the app learns how late this phone's microphone delivers sound.
///
/// Pops `true` when a new latency was saved.
class MicCalibrationScreen extends StatefulWidget {
  const MicCalibrationScreen({super.key, required this.chordCatalog});

  final ChordCatalog chordCatalog;

  @override
  State<MicCalibrationScreen> createState() => _MicCalibrationScreenState();
}

class _MicCalibrationScreenState extends State<MicCalibrationScreen>
    with SingleTickerProviderStateMixin {
  static const double _beatMs = 60000 / 70;
  static const int _warmUpBeats = 2;
  static const int _wanted = 10;
  static const int _maxBeats = 18;

  late final Ticker _ticker = createTicker(_onTick);
  final Stopwatch _clock = Stopwatch();
  final AudioAnalyzer _analyzer =
      AudioAnalyzer(onsetDetector: OnsetDetector.forRhythmGame());
  StreamSubscription<DateTime>? _onsetSub;
  StreamSubscription<dynamic>? _levelSub;

  var _phase = _CalPhase.intro;
  late LatencyCalibrator _cal;
  DateTime _startWall = DateTime.now();
  double _now = 0;
  double _lastHeard = -100000;
  double _level = 0;
  LatencyEstimate? _result;
  String? _error;

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_stopMic());
    unawaited(_analyzer.dispose());
    super.dispose();
  }

  Future<void> _stopMic() async {
    await _onsetSub?.cancel();
    await _levelSub?.cancel();
    _onsetSub = null;
    _levelSub = null;
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
  }

  Future<void> _begin() async {
    setState(() {
      _error = null;
      _result = null;
    });
    _cal = LatencyCalibrator(beatMs: _beatMs, firstCountedBeat: _warmUpBeats);
    _finishing = false;
    try {
      await MicCaptureGuard.instance.claim(this, _stopMic);
      _analyzer.setTargetChord(
        widget.chordCatalog.chords.first,
        referenceA4Hz: widget.chordCatalog.referenceA4Hz,
      );
      await _analyzer.start();
      _onsetSub = _analyzer.onsetStream.listen(_onOnset);
      _levelSub = _analyzer.feedbackStream.listen((f) => _level = f.inputLevel);
    } catch (e) {
      MicCaptureGuard.instance.release(this);
      if (mounted) {
        setState(() => _error = 'לא הצלחנו להפעיל את המיקרופון: $e');
      }
      return;
    }
    if (!mounted) return;
    _clock
      ..reset()
      ..start();
    _startWall = DateTime.now();
    setState(() => _phase = _CalPhase.running);
    _ticker.start();
  }

  void _onOnset(DateTime at) {
    if (_phase != _CalPhase.running) return;
    final heard = at.difference(_startWall).inMicroseconds / 1000.0;
    _lastHeard = _now;
    _cal.addStrum(heard);
  }

  void _onTick(Duration _) {
    _now = _clock.elapsedMicroseconds / 1000.0;
    final beat = (_now / _beatMs).floor();
    if (_cal.count >= _wanted || beat >= _maxBeats) {
      unawaited(_finish());
      return;
    }
    setState(() {});
  }

  var _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker.stop();
    _clock.stop();
    await _stopMic();
    final result = _cal.estimate();
    if (result != null && result.isReliable) {
      ProgressService.instance.setMicLatencyMs(result.latencyMs);
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _phase = _CalPhase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('כיול מיקרופון')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.gameGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_phase) {
              _CalPhase.intro => _intro(),
              _CalPhase.running => _running(),
              _CalPhase.result => _resultView(),
            },
          ),
        ),
      ),
    );
  }

  Widget _intro() {
    final saved = ProgressService.instance.micLatencyMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 56, color: AppColors.turquoise),
        const SizedBox(height: 12),
        const Text(
          'כיול חד־פעמי · כ־15 שניות',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        const Text(
          'המיקרופון של כל טלפון שומע את הגיטרה באיחור קטן. '
          'כדי שהמשחק ישפוט את התזמון נכון, נמדוד את האיחור פעם אחת:\n\n'
          '• החזיקו את הגיטרה ליד הטלפון.\n'
          '• עיגול יהבהב לאט — פרטו פריטה אחת למטה בדיוק כשהוא מהבהב.\n'
          '• שני ההבהובים הראשונים הם רק הכנה.',
          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
        ),
        if (saved != null) ...[
          const SizedBox(height: 12),
          Text(
            'הכיול הנוכחי: $saved ms',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
        ],
        const Spacer(),
        FilledButton.icon(
          onPressed: () => unawaited(_begin()),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.pink,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('התחילו כיול', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  Widget _running() {
    final beat = (_now / _beatMs).floor();
    final sinceBeat = _now - beat * _beatMs;
    final pulse = exp(-sinceBeat / 160);
    final warmUp = beat < _warmUpBeats;
    final heard = _now - _lastHeard < 220;
    return Column(
      children: [
        Text(
          warmUp ? 'התכוננו… (${_warmUpBeats - beat})' : 'פרטו בכל הבהוב!',
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'נמדדו ${_cal.count} מתוך $_wanted',
          style: const TextStyle(color: Colors.white70),
        ),
        Expanded(
          child: Center(
            child: Container(
              width: 120 + 90 * pulse,
              height: 120 + 90 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (warmUp ? AppColors.violet : AppColors.turquoise)
                    .withValues(alpha: 0.25 + 0.65 * pulse),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.turquoise.withValues(alpha: 0.6 * pulse),
                    blurRadius: 40 * pulse + 4,
                  ),
                ],
              ),
            ),
          ),
        ),
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: heard ? AppColors.turquoise : Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                heard ? '🎸 נשמע!' : '🎤',
                style: TextStyle(
                  color: heard ? AppColors.background : Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_level / 0.08).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  color: _level > 0.004 ? AppColors.success : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultView() {
    final r = _result;
    final ok = r != null && r.isReliable;
    final String message;
    if (r == null || r.samples < 6) {
      message = 'לא שמענו מספיק פריטות (${r?.samples ?? 0}). '
          'קרבו את הטלפון לגיטרה, ודאו שיש הרשאת מיקרופון, ופרטו חזק יותר.';
    } else if (!ok) {
      message = 'הפריטות לא היו אחידות מספיק כדי למדוד. '
          'נסו שוב ופרטו בדיוק כשהעיגול מהבהב.';
    } else {
      message = 'המשחק יתקן את התזמון לפי זה אוטומטית.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 72,
          color: ok ? AppColors.success : AppColors.amberBright,
        ),
        const SizedBox(height: 12),
        Text(
          ok ? 'כויל! איחור המיקרופון: ${r.latencyMs} ms' : 'צריך לנסות שוב',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
        ),
        const Spacer(),
        if (ok)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('המשך למשחק'),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() => _phase = _CalPhase.intro),
          child: const Text('כיול מחדש'),
        ),
      ],
    );
  }
}
