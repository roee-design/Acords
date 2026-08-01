import 'dart:async';

/// Ensures only one mic capture session is active across the whole app.
///
/// Screens register a full [sessionStop] (same as the stop button) when capture
/// starts. Claiming or [forceStopAll] runs the previous session's stop handler.
class MicCaptureGuard {
  MicCaptureGuard._();

  static final MicCaptureGuard instance = MicCaptureGuard._();

  Object? _owner;
  Future<void> Function()? _sessionStop;

  /// Takes ownership; if another session is active, runs its stop handler first.
  Future<void> claim(Object owner, Future<void> Function() sessionStop) async {
    if (_owner != null && _owner != owner) {
      final previousStop = _sessionStop;
      _owner = null;
      _sessionStop = null;
      if (previousStop != null) {
        await previousStop();
      }
    }
    _owner = owner;
    _sessionStop = sessionStop;
  }

  /// Clears ownership only — does not stop hardware (caller already stopped).
  void release(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _sessionStop = null;
  }

  /// Runs the active session's stop handler (stop button equivalent).
  Future<void> forceStopAll() async {
    final stop = _sessionStop;
    _owner = null;
    _sessionStop = null;
    if (stop != null) {
      await stop();
    }
  }
}
