import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/audio_analyzer.dart';
import '../audio/mic_capture_guard.dart';
import '../audio/strum_preview_service.dart';
import '../models/chord_definition.dart';
import '../models/feedback_result.dart';
import '../models/song_definition.dart';
import 'app_theme.dart';
import 'widgets/song_lyric_line.dart';
import 'widgets/strumming_help_sheet.dart';
import 'widgets/strumming_pattern_widget.dart';

/// Free song player — play any song directly with mic / BPM accompany.
class SongPlayerScreen extends StatefulWidget {
  const SongPlayerScreen({
    super.key,
    required this.song,
    required this.chordCatalog,
  });

  final SongDefinition song;
  final ChordCatalog chordCatalog;

  @override
  State<SongPlayerScreen> createState() => _SongPlayerScreenState();
}

enum _PlayGate {
  chordGate,
  freeBpm,
}

class _SongPlayerScreenState extends State<SongPlayerScreen> {
  static const int _fftSize = 8192;
  static const int _sampleRate = 44100;
  static const Duration _chordGrace = Duration(milliseconds: 280);

  final AudioAnalyzer _analyzer = AudioAnalyzer(
    sampleRate: _sampleRate,
    fftSize: _fftSize,
  );

  StreamSubscription<ChordFeedback>? _feedbackSub;
  Timer? _beatTimer;

  var _gate = _PlayGate.chordGate;
  var _listening = false;
  var _busy = false;
  var _lifecycleEpoch = 0;
  var _wasPerfect = false;
  var _chordIndex = 0;
  var _strokeIndex = 0;
  var _completed = false;
  var _previewPlaying = false;
  var _previewStrokeIndex = 0;
  String? _errorMessage;
  ChordFeedback? _feedback;

  late final List<_Cursor> _cursors;

  @override
  void initState() {
    super.initState();
    _cursors = _buildCursors(widget.song);
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
    _applyTargetChord(grace: false);
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

  List<_Cursor> _buildCursors(SongDefinition song) {
    final out = <_Cursor>[];
    for (var li = 0; li < song.lines.length; li++) {
      final line = song.lines[li];
      for (var si = 0; si < line.segments.length; si++) {
        final id = line.segments[si].chordId;
        if (id != null && id.isNotEmpty) {
          out.add(_Cursor(lineIndex: li, segmentIndex: si, chordId: id));
        }
      }
    }
    return out;
  }

  ChordDefinition? get _currentChordDef {
    if (_cursors.isEmpty || _chordIndex >= _cursors.length) return null;
    return widget.chordCatalog.chordById(_cursors[_chordIndex].chordId);
  }

  String get _currentChordLabel {
    final def = _currentChordDef;
    if (def != null) return def.displayName;
    if (_chordIndex >= _cursors.length) return '✓';
    return '—';
  }

  void _applyTargetChord({required bool grace}) {
    final def = _currentChordDef;
    if (def == null) return;
    _analyzer.setTargetChord(
      def,
      referenceA4Hz: widget.chordCatalog.referenceA4Hz,
      gracePeriod: grace ? _chordGrace : null,
    );
    _wasPerfect = false;
  }

  void _onFeedback(ChordFeedback feedback) {
    if (!mounted || !_listening || _completed) return;
    if (_gate != _PlayGate.chordGate) {
      setState(() => _feedback = feedback);
      return;
    }
    if (_analyzer.isBlanking) return;

    final isPerfect = feedback.matchStatus == ChordMatchStatus.perfect;
    setState(() => _feedback = feedback);
    if (isPerfect && !_wasPerfect) {
      _advanceChord();
    }
    _wasPerfect = isPerfect;
  }

  void _advanceChord() {
    if (_chordIndex >= _cursors.length - 1) {
      setState(() {
        _completed = true;
        _chordIndex = _cursors.length;
      });
      unawaited(_stopListening());
      return;
    }
    setState(() {
      _chordIndex += 1;
      _wasPerfect = false;
    });
    _applyTargetChord(grace: true);
  }

  void _startBeatClock() {
    _beatTimer?.cancel();
    final pattern = widget.song.pattern;
    final slots = pattern.events.length;
    if (slots == 0) return;
    final msPerSlot = (60000.0 / widget.song.bpm) / pattern.subdivision;
    _strokeIndex = 0;
    _beatTimer = Timer.periodic(
      Duration(milliseconds: msPerSlot.round().clamp(40, 2000)),
      (_) {
        if (!mounted || !_listening) return;
        setState(() => _strokeIndex = (_strokeIndex + 1) % slots);
        if (_gate == _PlayGate.freeBpm &&
            _strokeIndex == 0 &&
            !_completed) {
          _advanceChord();
        }
      },
    );
  }

  Future<void> _startListening() async {
    if (_busy || _listening || _cursors.isEmpty) return;
    await _stopPreviewIfNeeded();
    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _completed = false;
      _chordIndex = 0;
      _strokeIndex = 0;
    });
    try {
      await MicCaptureGuard.instance.claim(this, _stopListening);
      _applyTargetChord(grace: false);
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
      _startBeatClock();
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

  Future<void> _stopListening() async {
    final epoch = ++_lifecycleEpoch;
    _beatTimer?.cancel();
    _beatTimer = null;
    await _analyzer.stop();
    MicCaptureGuard.instance.release(this);
    if (!mounted || epoch != _lifecycleEpoch) return;
    setState(() {
      _listening = false;
      _busy = false;
      _wasPerfect = false;
      _strokeIndex = 0;
    });
  }

  Future<void> _togglePreview() async {
    final preview = StrumPreviewService.instance;
    if (_previewPlaying) {
      await preview.stop();
      if (!mounted) return;
      setState(() {
        _previewPlaying = false;
        _previewStrokeIndex = 0;
      });
      return;
    }
    if (_listening) await _stopListening();
    setState(() => _previewPlaying = true);
    await preview.play(
      pattern: widget.song.pattern,
      bpm: widget.song.bpm,
      onStroke: (i) {
        if (!mounted) return;
        setState(() => _previewStrokeIndex = i);
      },
    );
    if (!mounted) return;
    if (!preview.isPlaying) {
      setState(() {
        _previewPlaying = false;
        _previewStrokeIndex = 0;
      });
    }
  }

  Future<void> _stopPreviewIfNeeded() async {
    if (!_previewPlaying) return;
    await StrumPreviewService.instance.stop();
    if (!mounted) return;
    setState(() {
      _previewPlaying = false;
      _previewStrokeIndex = 0;
    });
  }

  int _lastCompletedOnLine(int lineIndex) {
    var last = -1;
    for (var i = 0; i < _chordIndex && i < _cursors.length; i++) {
      if (_cursors[i].lineIndex == lineIndex) {
        last = _cursors[i].segmentIndex;
      }
    }
    return last;
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final activeStroke =
        _previewPlaying ? _previewStrokeIndex : (_listening ? _strokeIndex : null);

    return Scaffold(
      appBar: AppBar(title: Text(song.title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: AppTheme.cardDecoration(
                  borderColor: AppColors.turquoise.withValues(alpha: 0.35),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              song.artist,
                              '${song.bpm} BPM',
                              if (song.instrumental) 'אימון מנגינה',
                              if (song.publicDomain) 'נחלת הכלל',
                            ].join(' · '),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          _completed ? 'הושלם!' : 'יעד: $_currentChordLabel',
                          style: TextStyle(
                            color: _completed
                                ? AppColors.success
                                : AppColors.amberBright,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StrummingPatternWidget(
                      pattern: song.pattern,
                      activeIndex: activeStroke,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'הסבר על הפריטה',
                          onPressed: () =>
                              unawaited(showStrummingHelpSheet(context)),
                          icon: const Icon(Icons.help_outline_rounded),
                          color: AppColors.turquoise,
                        ),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => unawaited(_togglePreview()),
                            icon: Icon(
                              _previewPlaying
                                  ? Icons.stop_rounded
                                  : Icons.volume_up_rounded,
                            ),
                            label: Text(
                              _previewPlaying
                                  ? 'עצור השמעה'
                                  : 'השמע פריטה לדוגמה',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('זיהוי אקורד'),
                      selected: _gate == _PlayGate.chordGate,
                      onSelected: (_) =>
                          setState(() => _gate = _PlayGate.chordGate),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('ליווי לפי BPM'),
                      selected: _gate == _PlayGate.freeBpm,
                      onSelected: (_) =>
                          setState(() => _gate = _PlayGate.freeBpm),
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: song.lines.length,
                itemBuilder: (context, lineIndex) {
                  return SongLyricLineView(
                    line: song.lines[lineIndex],
                    chordCatalog: widget.chordCatalog,
                    rtl: song.rtl,
                    instrumental: song.instrumental,
                    activeSegment: !_completed &&
                            _chordIndex < _cursors.length &&
                            _cursors[_chordIndex].lineIndex == lineIndex
                        ? _cursors[_chordIndex].segmentIndex
                        : null,
                    completedThrough: _completed
                        ? 999
                        : _lastCompletedOnLine(lineIndex),
                  );
                },
              ),
            ),
            if (_feedback != null && _listening)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _feedback!.summary,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: switch (_feedback!.matchStatus) {
                      ChordMatchStatus.perfect => AppColors.success,
                      ChordMatchStatus.close => AppColors.amberBright,
                      _ => AppColors.textMuted,
                    },
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : (_listening
                        ? () => unawaited(_stopListening())
                        : () => unawaited(_startListening())),
                icon: Icon(
                  _listening ? Icons.stop_rounded : Icons.mic_rounded,
                ),
                label: Text(
                  _busy
                      ? 'מתחבר…'
                      : (_listening ? 'עצור' : 'התחל האזנה'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cursor {
  const _Cursor({
    required this.lineIndex,
    required this.segmentIndex,
    required this.chordId,
  });

  final int lineIndex;
  final int segmentIndex;
  final String chordId;
}
