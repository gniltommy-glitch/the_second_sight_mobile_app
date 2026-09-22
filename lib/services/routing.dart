import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../core/models.dart';

class RoutingService {
  final http.Client client;
  RoutingService({http.Client? client}) : client = client ?? http.Client();
  String key = '';
  static const base = 'https://graphhopper.com/api/1';
  Future<Map<String, dynamic>> _get(Uri uri) async {
    if (key.isEmpty) throw Exception('Nhập GraphHopper API key trong Cài đặt.');
    late http.Response r;
    try { r = await client.get(uri).timeout(const Duration(seconds: 18)); }
    on TimeoutException { throw Exception('Dịch vụ bản đồ phản hồi quá chậm. Thử lại khi mạng ổn định.'); }
    on http.ClientException { throw Exception('Không kết nối được dịch vụ bản đồ. Kiểm tra Internet.'); }
    if (r.statusCode != 200) throw Exception('Dịch vụ bản đồ trả lỗi ${r.statusCode}. Kiểm tra key, hạn mức và mạng.');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
  Future<List<Place>> search(String q) async {
    final j = await _get(Uri.parse('$base/geocode').replace(queryParameters: {
      'key': key, 'q': q, 'locale': 'vi', 'limit': '7',
    }));
    return (j['hits'] as List).where((h) => h['point'] != null).map((h) => Place(
      [h['name'], h['street'], h['city'], h['country']].whereType<String>().toSet().join(', '),
      LatLng((h['point']['lat'] as num).toDouble(), (h['point']['lng'] as num).toDouble()),
    )).toList();
  }
  Future<WalkRoute> route(LatLng from, Place to) async {
    final j = await _get(Uri.parse('$base/route').replace(queryParameters: {
      'key': key, 'point': ['${from.latitude},${from.longitude}', '${to.point.latitude},${to.point.longitude}'],
      'profile': 'foot', 'locale': 'vi', 'instructions': 'true', 'points_encoded': 'false',
    }));
    final p = (j['paths'] as List).first;
    final points = (p['points']['coordinates'] as List).map(coordinate).toList();
    final steps = (p['instructions'] as List).map((s) => Maneuver(
      s['text'] ?? '', s['street_name'] ?? '', Maneuver.actionFor(s['sign']), (s['interval'][0] as num).toInt(),
    )).toList();
    if (points.length < 2 || steps.isEmpty || steps.any((s) => s.index < 0 || s.index >= points.length)) {
      throw Exception('Dữ liệu tuyến đường không hợp lệ.');
    }
    return WalkRoute(id: const Uuid().v4(), destination: to, points: points, steps: steps,
      distance: (p['distance'] as num).toDouble(), seconds: (p['time'] as num).toDouble() / 1000,
      created: DateTime.now());
  }
  void dispose() => client.close();
}

WalkRoute demoRoute() {
  const a = LatLng(10.762622, 106.660172);
  final points = <LatLng>[];
  for (var i = 0; i <= 30; i++) { points.add(LatLng(a.latitude + i * 0.00005, a.longitude)); }
  for (var i = 1; i <= 25; i++) { points.add(LatLng(a.latitude + 0.0015, a.longitude + i * 0.00005)); }
  return WalkRoute(id: const Uuid().v4(), destination: Place('Điểm đến mô phỏng', points.last),
    points: points, steps: const [Maneuver('Đi thẳng', '', 'continue', 0),
      Maneuver('Rẽ phải', 'Đường mô phỏng', 'turn_right', 30),
      Maneuver('Đã đến điểm đến', '', 'arrive', 55)], distance: 304, seconds: 240,
    created: DateTime.now(), demo: true);
}
