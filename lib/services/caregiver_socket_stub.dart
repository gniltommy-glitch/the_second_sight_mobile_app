import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

class CaregiverRelaySocket {
  late final WebSocketChannel _channel;

  CaregiverRelaySocket._(Uri uri) : _channel = WebSocketChannel.connect(uri);

  static CaregiverRelaySocket connect(Uri uri, String _) =>
      CaregiverRelaySocket._(uri);

  Future<void> get ready => _channel.ready;
  Stream<dynamic> get stream => _channel.stream;
  void send(String text) => _channel.sink.add(text);
  Future<void> close() => _channel.sink.close();
}
