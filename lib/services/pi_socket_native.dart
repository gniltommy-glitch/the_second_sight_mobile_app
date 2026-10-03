import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';

/// Android: native OkHttp. iOS/desktop: authenticated dart:io WebSocket.
class PiSocket {
  static const _methods = MethodChannel('secondsight/okhttp');
  static const _events = EventChannel('secondsight/okhttp/events');
  static int _nextId = 0;
  final int _id = ++_nextId;
  final _ready = Completer<void>();
  final _messages = StreamController<dynamic>();
  StreamSubscription<dynamic>? _subscription;
  IOWebSocketChannel? _io;
  bool _closed = false;

  PiSocket._();
  static PiSocket connect(Uri uri, String token) {
    final socket = PiSocket._();
    socket._open(uri, token);
    return socket;
  }

  Future<void> get ready => _ready.future;
  Stream<dynamic> get stream => _messages.stream;

  Future<void> _open(Uri uri, String token) async {
    try {
      if (Platform.isAndroid) {
        _subscription = _events.receiveBroadcastStream().listen((
          dynamic event,
        ) {
          if (_closed || event is! Map || event['id'] != _id) return;
          switch (event['type']) {
            case 'open':
              if (!_ready.isCompleted) _ready.complete();
            case 'message':
              _messages.add(event['text']);
            case 'closed':
            case 'failure':
              _fail();
          }
        }, onError: (Object _) => _fail());
        await _methods.invokeMethod<void>('connect', {
          'id': _id,
          'url': uri.toString(),
          'token': token,
        });
      } else {
        _io = IOWebSocketChannel.connect(
          uri,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 7),
        );
        await _io!.ready;
        if (_closed) return;
        _subscription = _io!.stream.listen(
          _messages.add,
          onError: (Object _) => _fail(),
          onDone: _fail,
        );
        _ready.complete();
      }
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (_closed) return;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Không kết nối được kính.'));
    }
    unawaited(close());
  }

  void send(String text) {
    if (_closed) return;
    if (Platform.isAndroid) {
      unawaited(
        _methods
            .invokeMethod<bool>('send', {'id': _id, 'text': text})
            .then((sent) {
              if (sent != true) _fail();
            })
            .catchError((Object _) {
              _fail();
            }),
      );
    } else {
      _io?.sink.add(text);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('Kết nối đã đóng.'));
    }
    await _subscription?.cancel();
    if (Platform.isAndroid) {
      try {
        await _methods.invokeMethod<void>('close', {'id': _id});
      } catch (_) {
        /* engine may already be detached */
      }
    } else {
      await _io?.sink.close();
    }
    unawaited(_messages.close());
  }
}
