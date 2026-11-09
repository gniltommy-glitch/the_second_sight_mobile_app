import 'dart:async';

/// Serialize ordinary speech; only explicit cancellation/urgent alerts interrupt.
/// Bound native completion waits so an unavailable engine cannot block the mic.
class SpeechOutput {
  SpeechOutput({
    required this.speak,
    required this.stop,
    required this.onError,
    this.onActivity,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<dynamic> Function(String) speak;
  final Future<dynamic> Function() stop;
  final void Function(Object) onError;
  final Duration timeout;
  final void Function(bool)? onActivity;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _disposed = false;
  int _ordinaryPending = 0;
  int _explorationRevision = 0;
  bool _exploring = false;

  Future<void> cancelExploration() async {
    if (_exploring) await cancel();
  }

  Future<void> cancel() async {
    _explorationRevision++;
    _exploring = false;
    await _cancel();
  }

  Future<void> _cancel() async {
    _generation++;
    onActivity?.call(false);
    _tail = Future.value();
    try {
      await stop().timeout(timeout);
    } catch (e) {
      if (!_disposed) onError(e);
    }
  }

  /// Read the current touch target, replacing only earlier exploration speech.
  /// Directions and warnings always take precedence and are never interrupted.
  Future<void> explore(String text) async {
    if (_disposed || _ordinaryPending > 0) return;
    final revision = ++_explorationRevision;
    if (_exploring) await _cancel();
    if (_disposed || revision != _explorationRevision || _ordinaryPending > 0) {
      return;
    }
    _exploring = true;
    try {
      await _say(text);
    } finally {
      if (revision == _explorationRevision) _exploring = false;
    }
  }

  Future<void> say(String text, {bool urgent = false}) async {
    if (_disposed) return;
    _ordinaryPending++;
    _explorationRevision++;
    try {
      final interrupted = _exploring;
      _exploring = false;
      final ready = interrupted ? _cancel() : Future<void>.value();
      await _say(text, urgent: urgent, ready: ready);
    } finally {
      _ordinaryPending--;
    }
  }

  Future<void> _say(
    String text, {
    bool urgent = false,
    Future<void>? ready,
  }) async {
    if (_disposed) return;
    if (urgent) await cancel();
    final generation = _generation;
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      await ready;
      if (_disposed || generation != _generation) return;
      onActivity?.call(true);
      final result = await speak(text).timeout(timeout);
      if (result == 0 && generation == _generation && !_disposed) {
        onError(StateError('Dịch vụ đọc giọng nói từ chối phát âm thanh.'));
      }
    } catch (e) {
      if (!_disposed && generation == _generation) {
        onError(e);
        await cancel();
      }
    } finally {
      if (!_disposed && generation == _generation) onActivity?.call(false);
      done.complete();
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _tail = Future.value();
    // Disposal is fire-and-forget; do not leave a completion timer alive.
    unawaited(stop().then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
}
