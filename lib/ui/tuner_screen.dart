import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/frequency_utils.dart';
import '../audio/mic_capture_guard.dart';
import '../audio/pitch_tuner.dart';
import '../models/chord_definition.dart';
import 'app_theme.dart';
import 'widgets/cents_tuner_gauge.dart';
import 'widgets/help_sheet.dart';

/// Standalone pitch tuner — pick a string, play it open, tune by cents.
class TunerScreen extends StatefulWidget {
  const TunerScreen({
    super.key,
    required this.catalog,
    this.isActive = true,
  });

  final ChordCatalog catalog;

  /// When false (e.g. another bottom-nav tab), mic capture must stop.
  final bool isActive;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  final PitchTuner _tuner = PitchTuner();

  StreamSubscription<PitchReading>? _subscription;
  PitchReading _reading = PitchReading.silent();
  var _listening = false;
  var _busy = false;
  /// Serializes stop/start so tab switches cannot leave the mic on.
  var _lifecycleEpoch = 0;
  String? _errorMessage;

  /// `null` = auto mode; otherwise guitar string number 6→1.
  int? _selectedString;

  @override
  void initState() {
    super.initState();
    _tuner.configure(
      referenceA4Hz: widget.catalog.referenceA4Hz,
      openStrings: widget.catalog.strings
          .map((s) => (s.index, s.openMidi, s.name))
          .toList(),
    );
    _subscription = _tuner.readings.listen(
      (reading) {
        if (mounted) setState(() => _reading = reading);
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _errorMessage = error.toString();
            _listening = false;
            _busy = false;
          });
          unawaited(_tuner.stop());
          MicCaptureGuard.instance.release(this);
        }
      },
    );

    // If shell mounts us already inactive, ensure mic is off.
    if (!widget.isActive) {
      unawaited(_tuner.stop());
    }
  }

  @override
  void didUpdateWidget(covariant TunerScreen oldWidget) {
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
    _subscription?.cancel();
    _subscription = null;
    unawaited(_tuner.stop());
    MicCaptureGuard.instance.release(this);
    unawaited(_tuner.dispose());
    super.dispose();
  }

  bool get _isCapturing => _listening || _busy || _tuner.isListening;

  Future<void> _stopIfCapturing() async {
    if (_isCapturing) {
      await _stop();
    }
  }

  void _selectString(int? stringNumber) {
    setState(() => _selectedString = stringNumber);
    _tuner.setTargetString(stringNumber);
  }

  Future<void> _toggle() async {
    if (_busy || !widget.isActive) return;
    if (_listening) {
      await _stop();
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    if (!widget.isActive) return;
    final epoch = ++_lifecycleEpoch;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await MicCaptureGuard.instance.claim(this, _stop);
      await _tuner.start();
      if (epoch != _lifecycleEpoch || !mounted || !widget.isActive) {
        await _tuner.stop();
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

  Future<void> _stop() async {
    final epoch = ++_lifecycleEpoch;
    if (!_listening && !_busy && !_tuner.isListening) {
      MicCaptureGuard.instance.release(this);
      return;
    }
    setState(() => _busy = true);
    await _tuner.stop();
    MicCaptureGuard.instance.release(this);
    if (mounted && epoch == _lifecycleEpoch) {
      setState(() {
        _listening = false;
        _busy = false;
        _reading = PitchReading.silent();
      });
    }
  }

  GuitarStringTuning? get _selectedTuning {
    final selected = _selectedString;
    if (selected == null) return null;
    for (final s in widget.catalog.strings) {
      if (s.index == selected) return s;
    }
    return null;
  }

  String get _headlineNote {
    if (!_listening) return '—';
    if (_reading.isSilent || _reading.awaitingOpenString) return '—';
    return _reading.targetNoteName ?? _reading.noteName ?? '—';
  }

  String get _headlineCaption {
    if (_selectedString != null) return 'יעד (מיתר פתוח)';
    return 'מיתר פתוח';
  }

  String get _directionLabel {
    if (!_listening) return 'ממתין לצליל…';
    if (_reading.awaitingOpenString) {
      return 'נא לנגן מיתר פתוח';
    }
    final cents = _reading.centsOffset;
    if (cents == null || _reading.isSilent) return 'ממתין לצליל…';
    if (cents.abs() <= 5) return 'מכוון היטב!';
    if (cents > 0) return 'גבוה מדי — הורד את הצליל';
    return 'נמוך מדי — העלה את הצליל';
  }

  @override
  Widget build(BuildContext context) {
    final cents = _reading.centsOffset;
    final active = _listening &&
        !_reading.isSilent &&
        !_reading.awaitingOpenString &&
        cents != null;
    final inTune = _reading.isInTune;
    final tipBorderColor = inTune
        ? AppColors.success
        : _reading.awaitingOpenString
            ? AppColors.amber.withValues(alpha: 0.7)
            : !active
                ? AppColors.textMuted.withValues(alpha: 0.25)
                : (cents > 0
                    ? AppColors.amber
                    : AppColors.error.withValues(alpha: 0.7));
    final selectedTuning = _selectedTuning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('טיונר'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 8, end: 12),
            child: Center(child: HelpButton(topic: HelpTopic.tuner)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _selectedString == null
                    ? 'מצב אוטו מזהה רק מיתרים פתוחים — או בחרו מיתר ספציפי'
                    : 'נגנו את המיתר שנבחר פתוח — הסטייה נמדדת מול היעד שלו',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              _StringPicker(
                strings: widget.catalog.strings,
                selectedString: _selectedString,
                onSelected: _selectString,
                compact: true,
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: inTune
                          ? AppColors.success
                          : AppColors.turquoise.withValues(alpha: 0.4),
                      width: inTune ? 2.5 : 1.5,
                    ),
                    boxShadow: inTune
                        ? [
                            BoxShadow(
                              color:
                                  AppColors.success.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _headlineCaption,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _headlineNote,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: inTune
                                ? AppColors.success
                                : AppColors.textPrimary,
                            height: 1,
                          ),
                        ),
                        if (selectedTuning != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'מיתר ${selectedTuning.index} · ${stringLabel(selectedTuning.index)}',
                            style: const TextStyle(
                              color: AppColors.turquoise,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else if (_reading.closestStringLabel != null &&
                            !_reading.awaitingOpenString) ...[
                          const SizedBox(height: 4),
                          Text(
                            'מיתר ${_reading.closestStringNumber} · ${_reading.closestStringLabel}',
                            style: const TextStyle(
                              color: AppColors.turquoise,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (_reading.frequencyHz != null && active) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_reading.frequencyHz!.toStringAsFixed(1)} Hz',
                            style: TextStyle(
                              color: AppColors.textMuted
                                  .withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 5,
                child: CentsTunerGauge(
                  centsOffset: active ? cents : null,
                  active: active,
                  height: 160,
                  compact: true,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 2,
                child: LayoutBuilder(
                  builder: (context, bottomConstraints) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: bottomConstraints.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: tipBorderColor),
                              ),
                              child: Text(
                                _directionLabel,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: inTune
                                      ? AppColors.success
                                      : AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            FilledButton.icon(
                              onPressed: _busy || !widget.isActive
                                  ? null
                                  : _toggle,
                              icon: Icon(
                                _listening
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                              ),
                              label: Text(
                                _busy
                                    ? 'אנא המתן…'
                                    : _listening
                                        ? 'עצור טיונר'
                                        : 'התחל טיונר',
                              ),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: _listening
                                    ? AppColors.error
                                    : AppColors.turquoise,
                                foregroundColor: _listening
                                    ? Colors.white
                                    : AppColors.onPrimaryDark,
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (_listening) ...[
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value:
                                      _reading.inputLevel.clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: Colors.black26,
                                  color: AppColors.turquoise,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: AppTheme.cardDecoration(
                                borderColor: AppColors.textMuted
                                    .withValues(alpha: 0.2),
                              ),
                              child: Text(
                                _selectedString == null
                                    ? 'טיפ: במצב אוטו מזהים רק 6 מיתרים פתוחים. סטייה עד 5 סנט = מכוון.'
                                    : 'טיפ: נגנו מיתר ${_selectedString!} פתוח בלבד. סטייה עד 5 סנט = מכוון.',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StringPicker extends StatelessWidget {
  const _StringPicker({
    required this.strings,
    required this.selectedString,
    required this.onSelected,
    this.compact = false,
  });

  final List<GuitarStringTuning> strings;
  final int? selectedString;
  final ValueChanged<int?> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Display thick→thin (6→1), matching how players usually tune.
    final ordered = [...strings]
      ..sort((a, b) => b.index.compareTo(a.index));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'מיתר לכוונון',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 12 : 13,
          ),
        ),
        SizedBox(height: compact ? 4 : 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: compact ? 5 : 8,
          runSpacing: compact ? 5 : 8,
          children: [
            _StringChip(
              label: 'אוטו',
              selected: selectedString == null,
              compact: compact,
              onTap: () => onSelected(null),
            ),
            for (final s in ordered)
              _StringChip(
                label: '${s.index} · ${s.name}',
                selected: selectedString == s.index,
                compact: compact,
                onTap: () => onSelected(s.index),
              ),
          ],
        ),
      ],
    );
  }
}

class _StringChip extends StatelessWidget {
  const _StringChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.turquoise
          : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            border: Border.all(
              color: selected
                  ? AppColors.turquoise
                  : AppColors.textMuted.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AppColors.onPrimaryDark
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ),
      ),
    );
  }
}
