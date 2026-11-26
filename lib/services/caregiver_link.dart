import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'caregiver_socket.dart';

/// Cầu nối thời gian thực từ ứng dụng người khiếm thị (role=wearer) lên
/// SecondSight Caregiver Relay Server (:8787).
/// Tách biệt hoàn toàn với PiLink để không ảnh hưởng luồng điều hướng cục bộ.
class CaregiverLink {
  CaregiverLink({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  void Function(Map<String, dynamic>)? onMessage;
  void Function(bool)? onConnection;

  CaregiverRelaySocket? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat, _retry;

  bool _wanted = false;
  bool connected = false;
  int _generation = 0;
  int _attempt = 0;
  DateTime _lastPong = DateTime.fromMillisecondsSinceEpoch(0);

  String endpoint = '';
  String token = '';
  bool allowInsecure = false;

  bool get isConfigured =>
      endpoint.trim().isNotEmpty && token.trim().isNotEmpty;

  Uri _uri(String path, {bool ws = false, Map<String, String>? query}) {
    final base = Uri.parse(endpoint.trim());
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery) {
      throw Exception('Địa chỉ Caregiver Relay không hợp lệ.');
    }
    if (base.scheme == 'http' && !allowInsecure) {
      throw Exception(
        'Caregiver Relay HTTP yêu cầu bật Cho phép HTTP LAN thử nghiệm.',
      );
    }
    return base.replace(
      scheme: ws ? (base.scheme == 'https' ? 'wss' : 'ws') : base.scheme,
      path: path,
      queryParameters: (query == null || query.isEmpty) ? null : query,
      fragment: '',
    );
  }

  Future<void> connect() async {
    if (!isConfigured) return;
    _uri('/ws', ws: true, query: const {'role': 'wearer'});
    disconnect();
    _wanted = true;
    _attempt = 0;
    await _open(_generation);
  }

  Future<void> _open(int generation) async {
    if (!_wanted || generation != _generation) return;
    try {
      final wsUri = _uri('/ws', ws: true, query: const {'role': 'wearer'});
      final channel = CaregiverRelaySocket.connect(wsUri, token.trim());
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 7));
      if (!_wanted || generation != _generation || _channel != channel) {
        await channel.close();
        return;
      }

      _lastPong = DateTime.now();
      _attempt = 0;

      _sub = channel.stream.listen(
        (raw) {
          if (generation != _generation) return;
          try {
            if (raw is! String || raw.length > 4 * 1024 * 1024) return;
            final msg = jsonDecode(raw) as Map<String, dynamic>;
            if (msg['type'] == 'pong') _lastPong = DateTime.now();
            onMessage?.call(msg);
          } catch (_) {}
        },
        onDone: () {
          if (_channel == channel) _lost(generation);
        },
        onError: (_) {
          if (_channel == channel) _lost(generation);
        },
        cancelOnError: false,
      );

      connected = true;
      onConnection?.call(true);

      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
        if (DateTime.now().difference(_lastPong).inSeconds > 12) {
          _lost(generation);
          return;
        }
        send({
          'type': 'ping',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
    } catch (_) {
      _lost(generation);
    }
  }

  void _lost(int generation) {
    if (generation != _generation || !_wanted) return;
    _heartbeat?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.close();
    _channel = null;
    if (connected) {
      connected = false;
      onConnection?.call(false);
    }
    if (_retry?.isActive == true) return;
    final wait = min(30, 1 << min(_attempt++, 5));
    _retry = Timer(Duration(seconds: wait), () => _open(generation));
  }

  void send(Map<String, dynamic> j) {
    if (!connected) return;
    try {
      _channel?.send(jsonEncode(j));
    } catch (_) {
      _lost(_generation);
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final r = await _http
        .post(
          _uri(path),
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 7));
    if (r.statusCode != 200) {
      throw Exception('Caregiver Relay từ chối yêu cầu (${r.statusCode}).');
    }
    final decoded = jsonDecode(r.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  void disconnect() {
    _wanted = false;
    _generation++;
    _retry?.cancel();
    _heartbeat?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.close();
    _channel = null;
    final was = connected;
    connected = false;
    if (was) onConnection?.call(false);
  }

  void dispose() {
    disconnect();
    _http.close();
  }
}
