import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_state.dart';
import '../core/models.dart';

class Home extends StatefulWidget {
  final AppState state;
  const Home({super.key, required this.state});
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  int tab = 0;
  final search = TextEditingController();
  final map = MapController();
  final speech = SpeechToText();
  List<Place> results = [];
  bool searching = false, listening = false;
  int searchVersion = 0;
  AppState get s => widget.state;
  @override
  void dispose() { search.dispose(); map.dispose(); speech.cancel(); super.dispose(); }
  Future<void> findPlaces() async {
    final q = search.text.trim(); if (q.length < 2) return;
    final version = ++searchVersion;
    setState(() => searching = true);
    await s.perform(() async {
      final found = await s.routing.search(q);
      if (!mounted || version != searchVersion) return;
      setState(() => results = found);
      if (found.isEmpty) { s.notice = 'Không tìm thấy địa điểm. Thử địa chỉ cụ thể hơn hoặc chọn trên bản đồ.'; }
    });
    if (mounted && version == searchVersion) setState(() => searching = false);
  }
  Future<void> listen() async {
    await s.perform(() async {
      if (listening) {
        await speech.stop();
        setState(() => listening = false);
        return;
      }
      final ok = await speech.initialize(
        onStatus: (status) {
          if (mounted && status != 'listening') {
            setState(() => listening = false);
          }
        },
        onError: (e) {
          if (mounted) setState(() => listening = false);
        },
      );
      if (!ok) {
        throw Exception(
            'Không có nhận dạng giọng nói. Kiểm tra quyền micro hoặc nhập địa chỉ.');
      }
      setState(() => listening = true);
      await speech.listen(
        localeId: 'vi_VN',
        onResult: (r) {
          if (!mounted) return;
          search.text = r.recognizedWords;
          if (r.finalResult) {
            setState(() => listening = false);
            findPlaces();
          }
        },
      );
    });
  }
  void select(Place p) {
    s.choose(p); setState(() => results = []);
    if (tab == 0) map.move(p.point, 16);
  }
  Future<void> favorite() async {
    final input = TextEditingController(text: s.destination?.name ?? 'Nhà');
    final name = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: const Text('Lưu địa điểm'), content: TextField(controller: input,
        decoration: const InputDecoration(labelText: 'Tên: Nhà, Trường, Bệnh viện…')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(c, input.text.trim()), child: const Text('Lưu'))]));
    input.dispose(); if (name != null && name.isNotEmpty) await s.perform(() => s.saveFavorite(name));
  }
  Future<void> shareText(String text) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(text: text,
      sharePositionOrigin: box == null ? const Rect.fromLTWH(0, 0, 1, 1) : box.localToGlobal(Offset.zero) & box.size));
  }
  Future<void> sos() async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Liên hệ khẩn cấp', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(s.demo ? 'Đang mô phỏng. Chia sẻ sẽ ghi rõ vị trí giả lập.' : 'Chọn gọi hoặc chia sẻ. Ứng dụng không tự gửi tin nhắn.'),
          const SizedBox(height: 20),
          FilledButton.icon(icon: const Icon(Icons.call), label: Text(s.emergencyPhone.isEmpty ? 'Chưa đặt số người thân' : 'Gọi ${s.emergencyPhone}'),
            onPressed: s.emergencyPhone.isEmpty ? null : () => s.perform(() async {
              if (!await launchUrl(Uri(scheme: 'tel', path: s.emergencyPhone))) throw Exception('Không mở được ứng dụng gọi điện.');
              s.log('sos_dialer', 'Đã mở giao diện gọi người thân');
            })),
          const SizedBox(height: 10),
          OutlinedButton.icon(icon: const Icon(Icons.share_location), label: const Text('Chia sẻ vị trí hiện tại'), onPressed: () => s.perform(() async {
            if (!s.freshFix) await s.locate();
            final p = s.location;
            if (p == null || !s.freshFix) throw Exception('Chưa lấy được vị trí mới đủ chính xác.');
            await shareText('${s.demo ? '[MÔ PHỎNG — KHÔNG PHẢI SOS THẬT] ' : ''}Tôi cần hỗ trợ. '
              'Vị trí cập nhật ${s.fixAt!.toLocal()}, sai số khoảng ${s.accuracy.round()} m: '
              'https://maps.google.com/?q=${p.latitude},${p.longitude}');
            s.log('sos_share_sheet', 'Đã mở bảng chia sẻ vị trí; người dùng chọn người nhận');
          })), const SizedBox(height: 12),
        ]))));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Row(children: [Container(padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.visibility_outlined, color: Colors.white)), const SizedBox(width: 10),
      const Text('SecondSight', style: TextStyle(fontWeight: FontWeight.w800))]),
      actions: [TextButton.icon(onPressed: sos, icon: const Icon(Icons.sos, color: Color(0xFFB53E32)),
        label: const Text('SOS', style: TextStyle(color: Color(0xFFB53E32), fontWeight: FontWeight.bold))), const SizedBox(width: 8)]),
    body: SafeArea(child: Column(children: [
      if (s.demo) banner('CHẾ ĐỘ MÔ PHỎNG • Không dùng để đi ngoài đường', const Color(0xFFFFE7B4)),
      if (s.error != null) banner(s.error!, const Color(0xFFFFDAD6), onClose: () { s.error = null; setState(() {}); }),
      if (s.hazard != null && s.hazardAt != null && DateTime.now().difference(s.hazardAt!).inSeconds < 12)
        Semantics(liveRegion: true, child: banner(s.hazard!, const Color(0xFFFFDAD6))),
      Expanded(child: switch (tab) { 0 => navigatePage(), 1 => devicePage(), 2 => logsPage(), _ => SettingsPage(state: s) }),
    ])),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i),
      destinations: const [NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Dẫn đường'),
        NavigationDestination(icon: Icon(Icons.visibility_outlined), label: 'Kính'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Nhật ký'),
        NavigationDestination(icon: Icon(Icons.tune), label: 'Cài đặt')]),
  );
  Widget banner(String text, Color color, {VoidCallback? onClose}) => Container(width: double.infinity,
    color: color, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
      Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
      if (onClose != null) IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: 'Đóng thông báo'),
    ]));
  Widget panel(List<Widget> children) => Container(padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE3E8DF))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  Widget navigatePage() => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
    const Text('Bạn muốn đi đâu?', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6), Text('Điện thoại dẫn đường. Kính quan sát xung quanh.', style: TextStyle(color: Colors.grey.shade700)),
    const SizedBox(height: 18),
    Row(children: [Expanded(child: TextField(controller: search, textInputAction: TextInputAction.search,
      onSubmitted: (_) => findPlaces(), decoration: InputDecoration(hintText: 'Tìm địa chỉ hoặc địa điểm', prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(onPressed: listen, tooltip: listening ? 'Dừng nghe' : 'Tìm bằng giọng nói',
          icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? Colors.red : null))))),
      const SizedBox(width: 8), IconButton.filled(onPressed: searching ? null : findPlaces, tooltip: 'Tìm kiếm', icon: const Icon(Icons.arrow_forward))]),
    if (searching) const LinearProgressIndicator(),
    ...results.map((p) => Card(child: ListTile(title: Text(p.name), leading: const Icon(Icons.place_outlined), onTap: () => select(p)))),
    if (s.favorites.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Wrap(spacing: 8, runSpacing: 8,
      children: s.favorites.map((p) => InputChip(avatar: const Icon(Icons.star_outline, size: 18), label: Text(p.name),
        onPressed: () => select(p), onDeleted: () => s.perform(() => s.removeFavorite(p)))).toList())),
    const SizedBox(height: 14),
    ClipRRect(borderRadius: BorderRadius.circular(24), child: SizedBox(height: 310, child: Stack(children: [
      FlutterMap(mapController: map, options: MapOptions(initialCenter: s.location ?? const LatLng(10.762622, 106.660172),
        initialZoom: 15, onLongPress: (_, point) => select(Place('Điểm đã chọn trên bản đồ', point))), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'vn.secondsight.secondsight', maxZoom: 19),
        if (s.route != null) PolylineLayer(polylines: [Polyline(points: s.route!.points, strokeWidth: 6, color: const Color(0xFF175C45))]),
        MarkerLayer(markers: [
          if (s.location != null) Marker(point: s.location!, width: 44, height: 44,
            child: const Icon(Icons.my_location, color: Color(0xFF235FC5), size: 32)),
          if (s.destination != null) Marker(point: s.destination!.point, width: 48, height: 48,
            child: const Icon(Icons.location_on, color: Color(0xFFB53E32), size: 44)),
        ]),
        RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors',
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))]),
      ]),
      Positioned(top: 12, left: 12, child: Chip(avatar: Icon(s.freshFix ? Icons.gps_fixed : Icons.gps_not_fixed, size: 18),
        label: Text(s.freshFix ? 'GPS ±${s.accuracy.round()} m' : 'Chưa có GPS tốt'))),
      Positioned(right: 12, top: 12, child: IconButton.filled(onPressed: () => s.perform(() async {
        await s.locate(); if (s.location != null) map.move(s.location!, 17);
      }), tooltip: 'Vị trí của tôi', icon: const Icon(Icons.my_location))),
    ]))),
    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nhấn giữ bản đồ để chọn điểm đến.', style: TextStyle(fontSize: 12))),
    if (s.notice != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(s.notice!)),
    panel([
      Row(children: [Expanded(child: Text(s.destination?.name ?? 'Chọn điểm đến để bắt đầu', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19))),
        if (s.destination != null) IconButton(onPressed: favorite, icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Lưu yêu thích')]),
      const SizedBox(height: 8),
      if (s.route != null) Text('${(s.route!.distance / 1000).toStringAsFixed(2)} km  •  ${(s.route!.seconds / 60).ceil()} phút  •  Đi bộ'),
      if (s.route != null) Text('Tuyến lưu: ${s.route!.created.toLocal().toString().substring(0, 16)}', style: const TextStyle(fontSize: 12)),
      if (s.active || s.journey == JourneyState.paused || s.journey == JourneyState.arrived) ...[
        const Divider(height: 28),
        Semantics(liveRegion: true, child: Text(s.journey == JourneyState.arrived ? 'Đã đến điểm đến' : s.journey == JourneyState.paused ? 'Đã tạm dừng' :
          !s.freshFix ? 'GPS yếu — tạm dừng chỉ dẫn' : !s.connected ? 'Mất kết nối kính' : !s.onRoute ? 'Lệch tuyến — đang tìm lại đường' :
          '${s.progress?.distanceToStep.round() ?? 0} m • ${s.instruction?.text ?? 'Đang định vị'}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
        if (s.progress != null) Text('Còn ${s.progress!.remaining.round()} m theo tuyến'),
        if (s.syncPending && !s.demo) const Text('Đang chờ kính xác nhận trạng thái…', style: TextStyle(color: Colors.deepOrange)),
      ],
      const SizedBox(height: 18),
      if (!s.active && s.journey != JourneyState.paused) FilledButton.icon(
        onPressed: s.busy || s.destination == null ? null : () => s.perform(s.plan),
        icon: s.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.alt_route),
        label: Text(s.busy ? 'Đang tìm tuyến…' : 'Lấy tuyến đi bộ')),
      if (s.route != null && !s.active && s.journey != JourneyState.arrived) Padding(padding: const EdgeInsets.only(top: 10),
        child: FilledButton.icon(onPressed: s.busy ? null : () => s.perform(s.start), icon: const Icon(Icons.navigation_outlined),
          label: Text(s.journey == JourneyState.paused ? 'Tiếp tục hành trình' : 'Bắt đầu hành trình'))),
      if (s.active) FilledButton.icon(onPressed: () => s.perform(s.pause), icon: const Icon(Icons.pause), label: const Text('Tạm dừng')),
      if (s.active || s.journey == JourneyState.paused || s.journey == JourneyState.arrived)
        TextButton(onPressed: () => s.perform(s.stop), child: const Text('Kết thúc hành trình')),
      if (s.route != null) ExpansionTile(title: const Text('Các bước chỉ dẫn'), tilePadding: EdgeInsets.zero,
        children: s.route!.steps.map((step) => ListTile(leading: Icon(step.action == 'turn_right' ? Icons.turn_right : step.action == 'turn_left' ? Icons.turn_left : Icons.straight),
          title: Text(step.text), subtitle: Text(step.street))).toList()),
    ]), const SizedBox(height: 16),
    Text(s.demo ? 'Bật/tắt mô phỏng trong Cài đặt.' : 'Cảnh báo vật cản được xử lý và phát trực tiếp trên kính.', style: const TextStyle(fontSize: 13)),
  ]);
  Widget devicePage() {
    final good = s.connected && s.statusFresh;
    String value(String key, [String unit = '']) => good && s.status[key] != null ? '${s.status[key]}$unit' : '—';
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Kính của bạn', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)), const SizedBox(height: 20),
      panel([const Icon(Icons.visibility_outlined, size: 68, color: Color(0xFF175C45)), const SizedBox(height: 16),
        Center(child: Text(s.demo || s.status['demo'] == true ? 'Kính mô phỏng' : s.link.connected ? 'Đã kết nối SecondSight' : 'Chưa kết nối', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        const SizedBox(height: 8), Center(child: Text(s.demo || s.status['demo'] == true ? 'Tất cả số liệu dưới đây là giả lập' : s.link.endpoint)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: s.demo ? null : () => s.perform(() async {
          if (s.link.connected) { s.link.disconnect(); } else { await s.link.connect(); if (!s.link.connected) s.notice = 'Chưa kết nối được. App sẽ tự thử lại; kiểm tra hotspot, địa chỉ và token.'; }
        }), icon: Icon(s.link.connected ? Icons.link_off : Icons.link), label: Text(s.link.connected ? 'Ngắt kết nối' : 'Kết nối kính')),
        if (!s.demo) TextButton(onPressed: () { s.link.disconnect(); setState(() {}); }, child: const Text('Dừng thử kết nối')),
      ]), const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [metric('Pin', value('battery_percent', '%'), Icons.battery_5_bar),
        metric('Nhiệt độ Pi', value('cpu_temp', ' °C'), Icons.thermostat),
        metric('YOLO', value('yolo_fps', ' FPS'), Icons.speed),
        metric('Sai số GPS', s.freshFix ? '${s.accuracy.round()} m' : 'Chưa xác định', Icons.gps_fixed)]),
      const SizedBox(height: 16), panel([
        ...{'camera_ok': 'Camera', 'lidar_ok': 'LiDAR / khoảng cách', 'imu_ok': 'BNO085 / IMU'}.entries.map((e) => ListTile(
          contentPadding: EdgeInsets.zero, title: Text(e.value), trailing: Text(!good ? 'Chưa có dữ liệu' : s.status[e.key] == true ? 'Hoạt động' : s.status[e.key] == false ? 'Lỗi cảm biến' : 'Chưa xác định',
          style: TextStyle(color: good && s.status[e.key] == true ? const Color(0xFF175C45) : Colors.deepOrange)))),
        const Divider(), const Text('Ưu tiên trên kính: nguy hiểm → giao thông → chỉ đường → thông tin phụ.'),
      ]),
      if (s.demo) Padding(padding: const EdgeInsets.only(top: 16), child: OutlinedButton.icon(onPressed: s.demoHazard,
        icon: const Icon(Icons.warning_amber), label: const Text('Thử cảnh báo mép hụt'))),
      const SizedBox(height: 16),
      const Text('Bật hotspot trong cài đặt điện thoại và cho Pi kết nối cùng mạng. App không tự bật hotspot. Nếu tên secondsight.local không phân giải, nhập IP LAN của Pi trong Cài đặt.'),
      if (s.notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(s.notice!)),
    ]);
  }
  Widget metric(String title, String value, IconData icon) => SizedBox(width: (MediaQuery.sizeOf(context).width - 52) / 2,
    child: panel([Icon(icon, color: const Color(0xFF175C45)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(title)]));
  Widget logsPage() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Nhật ký sự kiện', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
    const SizedBox(height: 10), const Text('Lưu tối đa 300 sự kiện trên thiết bị. Không ghi video, token hoặc toàn bộ vị trí GPS vào nhật ký.'),
    Row(children: [TextButton.icon(onPressed: () => s.perform(() => shareText(const JsonEncoder.withIndent('  ').convert(s.events))),
      icon: const Icon(Icons.ios_share), label: const Text('Xuất JSON')),
      TextButton(onPressed: () async {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Xóa nhật ký?'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Giữ lại')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa'))]));
        if (ok == true) await s.perform(s.clearLogs);
      }, child: const Text('Xóa'))]),
    if (s.events.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Chưa có sự kiện.'))),
    ...s.events.map((e) => Card(child: ListTile(leading: Icon(e['type'] == 'hazard' ? Icons.warning_amber : Icons.history),
      title: Text('${e['text']}'), subtitle: Text('${e['time']} • ${e['type']}')))),
  ]);
}

class SettingsPage extends StatefulWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController endpoint, token, apiKey, phone;
  bool saved = false;
  AppState get s => widget.state;
  @override
  void initState() { super.initState(); endpoint = TextEditingController(text: s.link.endpoint);
    token = TextEditingController(text: s.link.token); apiKey = TextEditingController(text: s.routing.key);
    phone = TextEditingController(text: s.emergencyPhone); }
  @override
  void dispose() { endpoint.dispose(); token.dispose(); apiKey.dispose(); phone.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Theo cách của bạn', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
    const SizedBox(height: 18), SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
      title: const Text('Chế độ mô phỏng'), subtitle: const Text('Thử tuyến, chỉ dẫn và cảnh báo mà không cần Pi hoặc API key.'),
      value: s.demo, onChanged: (v) => s.perform(() => s.setDemo(v))),
    const Divider(height: 32), const Text('Kết nối kính', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 14), TextField(controller: endpoint, keyboardType: TextInputType.url, autocorrect: false,
      decoration: const InputDecoration(labelText: 'Địa chỉ Pi', hintText: 'https://secondsight.local:8765')),
    const SizedBox(height: 12), TextField(controller: token, obscureText: true, autocorrect: false, enableSuggestions: false,
      decoration: const InputDecoration(labelText: 'Token ghép đôi')),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Cho phép HTTP LAN thử nghiệm'),
      subtitle: const Text('Không mã hóa. Chỉ dùng mạng hotspot riêng tin cậy. Bản triển khai dùng HTTPS/WSS.'),
      value: s.link.allowInsecure, onChanged: (v) => setState(() => s.link.allowInsecure = v)),
    const Divider(height: 32), const Text('Bản đồ & liên hệ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 14), TextField(controller: apiKey, obscureText: true, autocorrect: false, enableSuggestions: false,
      decoration: const InputDecoration(labelText: 'GraphHopper API key')),
    const SizedBox(height: 12), TextField(controller: phone, keyboardType: TextInputType.phone,
      decoration: const InputDecoration(labelText: 'Số điện thoại người thân', hintText: '+84…')),
    const Divider(height: 32), DropdownButtonFormField<String>(initialValue: s.warningLevel,
      decoration: const InputDecoration(labelText: 'Mức cảnh báo'),
      items: const [DropdownMenuItem(value: 'low', child: Text('Ít')), DropdownMenuItem(value: 'normal', child: Text('Bình thường')),
        DropdownMenuItem(value: 'detailed', child: Text('Chi tiết'))], onChanged: (v) => setState(() => s.warningLevel = v!)),
    const SizedBox(height: 16), Text('Âm lượng: ${(s.volume * 100).round()}%'),
    Slider(value: s.volume, divisions: 10, label: '${(s.volume * 100).round()}%', onChanged: (v) => setState(() => s.volume = v)),
    Text('Tốc độ đọc: ${s.speechRate.toStringAsFixed(1)}'),
    Slider(value: s.speechRate, min: 0.2, max: 0.8, divisions: 6, onChanged: (v) => setState(() => s.speechRate = v)),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: s.vibration, title: const Text('Rung khi có cảnh báo'),
      onChanged: (v) => setState(() => s.vibration = v)),
    FilledButton.icon(onPressed: () => s.perform(() async {
      final nextEndpoint = endpoint.text.trim(), nextToken = token.text.trim();
      if (s.link.endpoint != nextEndpoint || s.link.token != nextToken) s.link.disconnect();
      s.link.endpoint = nextEndpoint; s.link.token = nextToken;
      s.routing.key = apiKey.text.trim(); s.emergencyPhone = phone.text.trim();
      await s.saveSettings(); if (mounted) setState(() => saved = true);
    }), icon: const Icon(Icons.check), label: const Text('Lưu cài đặt')),
    if (saved) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Đã lưu trên điện thoại. Cấu hình kính sẽ đồng bộ khi kết nối.')),
    const SizedBox(height: 12), OutlinedButton(onPressed: () => s.perform(() => s.say('SecondSight. Chúc bạn có một hành trình an toàn.')),
      child: const Text('Nghe thử giọng đọc trên điện thoại')),
    TextButton(onPressed: () => Geolocator.openAppSettings(), child: const Text('Mở quyền ứng dụng')),
    const SizedBox(height: 18), const Text('Tuyến lưu dùng được khi mất mạng ngắn hạn; tìm địa điểm, tính lại tuyến và tải ô bản đồ cần Internet. Kính phải tự xử lý cảnh báo cục bộ khi mất kết nối.'),
    const SizedBox(height: 24),
  ]);
}
