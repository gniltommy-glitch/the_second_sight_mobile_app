import 'dart:async';

/// Serialize ordinary speech; only explicit cancellation/urgent alerts interrupt.
/// Bound native completion waits so an unavailable engine cannot block the mic.
class SpeechOutput {
  SpeechOutput({
    required this.speak,
    required this.stop,
    required this.onError,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<dynamic> Function(String) speak;
  final Future<dynamic> Function() stop;
  final void Function(Object) onError;
  final Duration timeout;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _disposed = false;

  Future<void> cancel() async {
    _generation++;
    _tail = Future.value();
    try {
      await stop().timeout(timeout);
    } catch (e) {
      if (!_disposed) onError(e);
    }
  }

  Future<void> say(String text, {bool urgent = false}) async {
    if (_disposed) return;
    if (urgent) await cancel();
    final generation = _generation;
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      if (_disposed || generation != _generation) return;
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
