import 'dart:async';

import 'package:web_socket_channel/io.dart';

/// Kênh WebSocket riêng cho Caregiver Relay bằng dart:io (chạy song song độc lập
/// với MethodChannel 'secondsight/okhttp' đang giữ kết nối tới kính Pi 5).
class CaregiverRelaySocket {
  final _ready = Completer<void>();
  final _messages = StreamController<dynamic>();
  StreamSubscription<dynamic>? _sub;
  IOWebSocketChannel? _io;
  bool _closed = false;

  CaregiverRelaySocket._();

  static CaregiverRelaySocket connect(Uri uri, String token) {
    final s = CaregiverRelaySocket._();
    s._open(uri, token);
    return s;
  }

  Future<void> get ready => _ready.future;
  Stream<dynamic> get stream => _messages.stream;

  Future<void> _open(Uri uri, String token) async {
    try {
      _io = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 7),
      );
      await _io!.ready;
      if (_closed) return;
      _sub = _io!.stream.listen(
        _messages.add,
        onError: (Object _) => _fail(),
        onDone: _fail,
      );
      if (!_ready.isCompleted) _ready.complete();
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (_closed) return;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Không kết nối được Caregiver Relay.'));
    }
    unawaited(close());
  }

  void send(String text) {
    if (_closed) return;
    _io?.sink.add(text);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Đã đóng kết nối Caregiver Relay.'));
    }
    await _sub?.cancel();
    await _io?.sink.close();
    unawaited(_messages.close());
  }
}
