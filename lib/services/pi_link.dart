import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// No video. Authentication occurs in headers, never in a URL or event log.
class PiLink {
  void Function(Map<String, dynamic>)? onMessage;
  void Function(bool)? onConnection;
  WebSocket? _socket;
  Timer? _heartbeat, _retry;
  bool _wanted = false, connected = false;
  int _generation = 0, _attempt = 0;
  DateTime _lastPong = DateTime.fromMillisecondsSinceEpoch(0);
  String endpoint = 'http://secondsight.local:8765', token = '';
  bool allowInsecure = false;
  final http.Client _http = http.Client();
  Uri _uri(String path, {bool ws = false}) {
    final base = Uri.parse(endpoint);
    if (!['http', 'https'].contains(base.scheme) || base.host.isEmpty || base.userInfo.isNotEmpty || base.hasQuery) {
      throw Exception('Địa chỉ phải là https://tên-kính:cổng hoặc HTTP LAN thử nghiệm.');
    }
    if (base.scheme == 'http' && !allowInsecure) throw Exception('Bật HTTP LAN thử nghiệm hoặc dùng HTTPS/WSS.');
    return base.replace(scheme: ws ? (base.scheme == 'https' ? 'wss' : 'ws') : base.scheme, path: path, fragment: '');
  }
  Future<void> connect() async {
    _uri('/ws');
    if (token.trim().isEmpty) throw Exception('Nhập token ghép đôi của Pi.');
    disconnect(); _wanted = true; _attempt = 0;
    await _open(_generation);
  }
  Future<void> _open(int generation) async {
    if (!_wanted || generation != _generation) return;
    try {
      final socket = await WebSocket.connect(_uri('/ws', ws: true).toString(),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 7));
      if (!_wanted || generation != _generation) { await socket.close(); return; }
      _socket = socket; _lastPong = DateTime.now(); _attempt = 0;
      socket.listen((raw) {
        if (generation != _generation) return;
        try {
          if (raw is! String || raw.length > 262144) return;
          final msg = jsonDecode(raw) as Map<String, dynamic>;
          if (msg['type'] == 'pong') _lastPong = DateTime.now();
          onMessage?.call(msg);
        } catch (_) { /* malformed peer frames are ignored */ }
      }, onDone: () { if (identical(_socket, socket)) _lost(generation); },
        onError: (Object _) { if (identical(_socket, socket)) _lost(generation); });
      connected = true; onConnection?.call(true);
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
        if (DateTime.now().difference(_lastPong).inSeconds > 5) { _lost(generation); return; }
        send({'type': 'ping', 'sent_at': DateTime.now().toUtc().toIso8601String()});
      });
    } catch (_) { _lost(generation); }
  }
  void _lost(int generation) {
    if (generation != _generation || !_wanted) return;
    _heartbeat?.cancel(); _socket?.close(); _socket = null;
    if (connected) { connected = false; onConnection?.call(false); }
    if (_retry?.isActive == true) return;
    final wait = min(30, 1 << min(_attempt++, 5));
    _retry = Timer(Duration(seconds: wait), () => _open(generation));
  }
  void send(Map<String, dynamic> j) {
    if (connected) { try { _socket?.add(jsonEncode(j)); } catch (_) { _lost(_generation); } }
  }
  Future<void> post(String path, Map<String, dynamic> data) async {
    final r = await _http.post(_uri(path), headers: {
      'Authorization': 'Bearer $token', 'Content-Type': 'application/json',
    }, body: jsonEncode(data)).timeout(const Duration(seconds: 7));
    if (r.statusCode != 200) throw Exception('Pi từ chối lệnh (${r.statusCode}).');
  }
  void disconnect() {
    _wanted = false; _generation++; _retry?.cancel(); _heartbeat?.cancel();
    _socket?.close(); _socket = null;
    final was = connected; connected = false;
    if (was) onConnection?.call(false);
  }
  void dispose() { disconnect(); _http.close(); }
}
