import 'widgets/consumer_components.dart';
import 'widgets/orientation_hud.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../services/voice_intent.dart';
import '../main.dart';
import 'widgets/animated_banner.dart';
import 'widgets/compass_widget.dart';
import 'widgets/glass_card.dart';
import 'widgets/hud_metric.dart';
import 'widgets/nav_instruction.dart';

class Home extends StatefulWidget {
  final AppState state;
  const Home({super.key, required this.state});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int tab = 0;
  final search = TextEditingController();
  final map = MapController();
  final speech = SpeechToText();
  List<Place> results = [];
  bool searching = false, listening = false;
  int searchVersion = 0;
  late final AnimationController _tabCtrl;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_onNavigationChanged);
    _tabCtrl = AnimationController(vsync: this, duration: 200.ms);
    // Blind users can't find buttons: greet and open the mic on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !s.active && s.journey != JourneyState.paused) {
        listen(greet: true);
      }
    });
  }

  @override
  void dispose() {
    s.removeListener(_onNavigationChanged);
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    _listenSession++;
    search.dispose();
    map.dispose();
    speech.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> findPlaces() async {
    final q = search.text.trim();
    if (q.length < 2) return;
    final version = ++searchVersion;
    setState(() => searching = true);
    await s.perform(() async {
      final found = await s.routing.search(q);
      if (!mounted || version != searchVersion) return;
      setState(() => results = found);
      if (found.isEmpty) {
        s.notice = 'Không tìm thấy địa điểm. Thử địa chỉ cụ thể hơn hoặc chọn trên bản đồ.';
      }
    });
    if (mounted && version == searchVersion) setState(() => searching = false);
  }

  void _onNavigationChanged() {
    if (!s.active && !s.offRoute && s.journey != JourneyState.paused) return;
    _retry?.cancel();
    // A manual Start must also close the mic, otherwise spoken directions can
    // be transcribed as a new destination and stop the current journey.
    if (listening && !_handlingVoice) {
      _listenSession++;
      speech.cancel();
      if (mounted) setState(() => listening = false);
    }
  }

  bool _speechReady = false;
  bool _openingMic = false, _handlingVoice = false;
  bool _foreground = true, _autoListen = true;
  int _listenSession = 0;
  Timer? _retry;
  String partial = '';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _retry?.cancel();
      _listenSession++;
      speech.cancel();
      if (mounted) setState(() => listening = false);
    } else {
      _scheduleListen();
    }
  }

  // These are short foreground destination-entry sessions, not a wake-word
  // service. Never reopen while navigation/TTS from a command is running.
  void _scheduleListen() {
    _retry?.cancel();
    if (!mounted ||
        !_foreground ||
        !_autoListen ||
        _handlingVoice ||
        s.active ||
        s.offRoute ||
        s.journey == JourneyState.paused)
      return;
    _retry = Timer(const Duration(seconds: 2), () {
      if (mounted &&
          _foreground &&
          _autoListen &&
          !_handlingVoice &&
          !s.active &&
          !s.offRoute &&
          s.journey != JourneyState.paused) {
        listen(automatic: true);
      }
    });
  }

  /// Speak → search → route from GPS → start, without another tap.
  Future<void> listen({bool greet = false, bool automatic = false}) async {
    if (_openingMic || _handlingVoice || !_foreground) return;
    _retry?.cancel();
    if (listening) {
      if (automatic) return;
      _autoListen = false;
      _listenSession++;
      await speech.cancel();
      if (mounted) setState(() => listening = false);
      return;
    }
    if (!automatic) _autoListen = true;
    _openingMic = true;
    try {
      // The greeting must not depend on a recognizer being installed/allowed.
      if (greet) {
        await s.say(
          'Xin chào, mình là Aurelia. Điểm đi là vị trí GPS hiện tại. '
          'Bạn muốn đến đâu? Hãy nói tên hoặc địa chỉ điểm đến.',
        );
      }
      if (!mounted || !_foreground) return;
      if (!_speechReady) {
        _speechReady = await speech.initialize(
          onStatus: (status) {
            if (!mounted || status == 'listening') return;
            setState(() => listening = false);
            _scheduleListen();
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => listening = false);
            if (e.errorMsg == 'error_no_match' ||
                e.errorMsg == 'error_speech_timeout') {
              _scheduleListen();
            } else {
              _autoListen = false;
              _retry?.cancel();
              s.error =
                  'Aurelia không nghe được. Kiểm tra quyền micro, '
                  'nhận dạng giọng nói và kết nối mạng.';
              s.say(s.error!, urgent: true);
            }
          },
        );
      }
      if (!_speechReady) {
        _autoListen = false;
        s.error =
            'Không bật được nhận dạng giọng nói. Kiểm tra quyền micro '
            'và quyền nhận dạng giọng nói trong cài đặt điện thoại.';
        await s.say(s.error!, urgent: true);
        return;
      }
      if (!mounted || !_foreground || s.active || s.offRoute) return;
      await s.say('Aurelia đang nghe. Mời bạn nói điểm đến.');
      if (!mounted || !_foreground || s.active || s.offRoute) return;
      final session = ++_listenSession;
      var delivered = false;
      HapticFeedback.mediumImpact();
      setState(() {
        listening = true;
        partial = '';
      });
      await speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'vi_VN',
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
        ),
        onResult: (r) async {
          if (!mounted ||
              !_foreground ||
              session != _listenSession ||
              delivered)
            return;
          setState(() => partial = r.recognizedWords);
          if (!r.finalResult || r.recognizedWords.trim().isEmpty) return;
          delivered = true;
          _handlingVoice = true;
          _retry?.cancel();
          setState(() => listening = false);
          try {
            await speech.cancel();
            if (!mounted || !_foreground || session != _listenSession) return;
            final intent = parseIntent(r.recognizedWords);
            search.text = intent.destination ?? r.recognizedWords;
            HapticFeedback.lightImpact();
            await s.voiceGo(r.recognizedWords);
          } finally {
            _handlingVoice = false;
            if (mounted) {
              setState(() {});
              _scheduleListen();
            }
          }
        },
      );
    } catch (_) {
      _autoListen = false;
      _retry?.cancel();
      s.error = 'Không mở được micro. Hãy kiểm tra quyền nhận dạng giọng nói.';
      await s.say(s.error!, urgent: true);
      if (mounted) setState(() => listening = false);
    } finally {
      _openingMic = false;
      if (!listening) _scheduleListen();
    }
  }

  void select(Place p) {
    s.choose(p);
    setState(() => results = []);
    if (tab == 0 && s.location != null) map.move(p.point, 16);
  }

  Future<void> favorite() async {
    final input = TextEditingController(text: s.destination?.name ?? 'Nhà');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lưu địa điểm'),
        content: TextField(
          controller: input,
          decoration: const InputDecoration(
            labelText: 'Tên: Nhà, Trường, Bệnh viện…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null && name.isNotEmpty)
      await s.perform(() => s.saveFavorite(name));
  }

  Future<void> shareText(String text) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box == null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> sos() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Liên hệ khẩn cấp',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                s.demo
                    ? 'Đang mô phỏng. Chia sẻ sẽ ghi rõ vị trí giả lập.'
                    : 'Chọn gọi hoặc chia sẻ. Ứng dụng không tự gửi tin nhắn.',
                style: const TextStyle(color: kTextSub),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.call),
                label: Text(
                  s.emergencyPhone.isEmpty
                      ? 'Chưa đặt số người thân'
                      : 'Gọi ${s.emergencyPhone}',
                ),
                onPressed: s.emergencyPhone.isEmpty
                    ? null
                    : () => s.perform(() async {
                        if (!await launchUrl(
                          Uri(scheme: 'tel', path: s.emergencyPhone),
                        )) {
                          throw Exception('Không mở được ứng dụng gọi điện.');
                        }
                        s.log('sos_dialer', 'Đã mở giao diện gọi người thân');
                      }),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.share_location),
                label: const Text('Chia sẻ vị trí hiện tại'),
                onPressed: () => s.perform(() async {
                  if (!s.freshFix) await s.locate();
                  final p = s.location;
                  if (p == null || !s.freshFix) {
                    throw Exception('Chưa lấy được vị trí mới đủ chính xác.');
                  }
                  await shareText(
                    '${s.demo ? '[MÔ PHỎNG — KHÔNG PHẢI SOS THẬT] ' : ''}'
                    'Tôi cần hỗ trợ. '
                    'Vị trí cập nhật ${s.fixAt!.toLocal()}, sai số khoảng ${s.accuracy.round()} m: '
                    'https://maps.google.com/?q=${p.latitude},${p.longitude}',
                  );
                  s.log(
                    'sos_share_sheet',
                    'Đã mở bảng chia sẻ vị trí; người dùng chọn người nhận',
                  );
                }),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Scaffold ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isHazard =
        s.hazard != null &&
        s.hazardAt != null &&
        DateTime.now().difference(s.hazardAt!).inSeconds < 12;

    return Scaffold(
      backgroundColor: kBg,
      extendBody: false,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Semantics(
        label: 'Chạm đúp bất kỳ đâu để nói điểm đến',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Double-tap anywhere opens the mic — no button to find.
          onDoubleTap: () => listen(),
          child: Stack(
            children: [
              _buildBody(isHazard),
              if (listening)
                Positioned.fill(
                  child: _ListeningOverlay(
                    text: partial,
                    onCancel: () => listen(),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody(bool isHazard) {
    return Column(
      children: [
        // Extend behind status bar.
        SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
        // Banners.
        if (s.demo)
          AnimatedBanner(
            text: 'CHẾ ĐỘ MÔ PHỎNG  •  Không dùng để đi ngoài đường',
            color: const Color(0xFF7C4F00),
            icon: Icons.science_outlined,
          ),
        if (s.error != null)
          AnimatedBanner(
            text: s.error!,
            color: const Color(0xFF7F1D1D),
            icon: Icons.error_outline,
            onClose: () {
              s.error = null;
              setState(() {});
            },
            urgent: true,
          ),
        if (isHazard)
          Semantics(
            liveRegion: true,
            child: AnimatedBanner(
              text: s.hazard!,
              color: const Color(0xFF7F1D1D),
              icon: Icons.warning_amber_rounded,
              urgent: true,
            ),
          ),
        // Page content.
        Expanded(
          child: PageEntrance(
            key: ValueKey(tab),
            child: switch (tab) {
              0 => _NavigatePage(
                state: s,
                onDevice: () => setState(() => tab = 1),
                map: map,
                onSearch: findPlaces,
                onListen: listen,
                onSelect: select,
                onFavorite: favorite,
                results: results,
                searching: searching,
                listening: listening,
                search: search,
              ),
              1 => _DevicePage(state: s),
              2 => _LogsPage(state: s, onShare: shareText),
              _ => _SettingsPage(state: s),
            },
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: kBg,
    centerTitle: false,
    titleSpacing: 20,
    title: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: kAccent.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.visibility_rounded, color: kAccent, size: 22),
        ),
        const SizedBox(width: 10),
        const Text(
          'SecondSight',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
            color: kText,
          ),
        ),
      ],
    ),
    actions: [
      IconButton(
        onPressed: sos,
        tooltip: 'Trợ giúp khẩn cấp',
        icon: const Icon(Icons.sos_rounded, color: kDanger, size: 25),
      ),
      const SizedBox(width: 8),
    ],
  );

  Widget _buildBottomNav() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: kSurface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: kBorder.withValues(alpha: 0.8),
                  width: 1,
                ),
              ),
              child: NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore_rounded),
                    label: 'Dẫn đường',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.visibility_outlined),
                    selectedIcon: Icon(Icons.visibility_rounded),
                    label: 'Kính',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: 'Nhật ký',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune_outlined),
                    selectedIcon: Icon(Icons.tune_rounded),
                    label: 'Cài đặt',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Navigate Page ───────────────────────────────────────────────
class _NavigatePage extends StatelessWidget {
  final AppState state;
  final MapController map;
  final VoidCallback onSearch, onListen, onFavorite, onDevice;
  final void Function(Place) onSelect;
  final List<Place> results;
  final bool searching, listening;
  final TextEditingController search;

  const _NavigatePage({
    required this.state,
    required this.map,
    required this.onSearch,
    required this.onListen,
    required this.onFavorite,
    required this.onDevice,
    required this.onSelect,
    required this.results,
    required this.searching,
    required this.listening,
    required this.search,
  });

  AppState get s => state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        JourneyWelcome(
          connected: s.connected,
          navigating: s.active,
          demo: s.demo,
          onDevice: onDevice,
        ),
        const SizedBox(height: 24),
        // ── Destination search
        const _SectionLabel('Bạn muốn đến đâu?'),
        const SizedBox(height: 10),
        _SearchBar(
          controller: search,
          listening: listening,
          searching: searching,
          onSearch: onSearch,
          onListen: onListen,
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...results.map(
            (p) => _PlaceResult(place: p, onTap: () => onSelect(p)),
          ),
        ],
        if (s.favorites.isNotEmpty) ...[
          const SizedBox(height: 12),
          _FavoritesRow(
            favorites: s.favorites,
            onSelect: onSelect,
            onDelete: (p) => s.perform(() => s.removeFavorite(p)),
          ),
        ],
        const SizedBox(height: 16),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill(
              icon: Icons.my_location_rounded,
              text: s.freshFix
                  ? 'Vị trí chính xác ±${s.accuracy.round()} m'
                  : 'Đang chờ vị trí',
              good: s.freshFix,
            ),
            StatusPill(
              icon: Icons.directions_walk_rounded,
              text: 'Dành cho đi bộ',
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Map
        _MapCard(
          state: s,
          map: map,
          onSelect: onSelect,
          onLocate: () async {
            await s.perform(() async {
              await s.locate();
              if (s.location != null) map.move(s.location!, 17);
            });
          },
        ),
        const SizedBox(height: 20),

        // ── Notice
        if (s.notice != null) _NoticeCard(s.notice!),

        // ── Navigation panel
        _NavPanel(state: s, onFavorite: onFavorite),
        const SizedBox(height: 12),

        // ── Compass + speed row (while navigating)
        if (s.active || s.offRoute) _CompassRow(state: s),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: kText,
    ),
  );
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool listening, searching;
  final VoidCallback onSearch, onListen;
  const _SearchBar({
    required this.controller,
    required this.listening,
    required this.searching,
    required this.onSearch,
    required this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            style: const TextStyle(color: kText),
            decoration: InputDecoration(
              hintText: 'Tìm địa chỉ hoặc địa điểm',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: kTextSub,
                size: 20,
              ),
              suffixIcon: AnimatedSwitcher(
                duration: 250.ms,
                child: IconButton(
                  key: ValueKey(listening),
                  onPressed: onListen,
                  tooltip: listening ? 'Dừng nghe' : 'Tìm bằng giọng nói',
                  icon: Icon(
                    listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: listening ? kDanger : kTextSub,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _IconBtn(
          onTap: searching ? null : onSearch,
          icon: searching
              ? Icons.hourglass_empty_rounded
              : Icons.arrow_forward_rounded,
          color: kAccent,
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final Color color;
  const _IconBtn({
    required this.onTap,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 52,
    child: IconButton.filled(
      onPressed: onTap,
      tooltip: 'Tìm địa điểm',
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: Icon(icon, size: 22),
    ),
  );
}

class _PlaceResult extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;
  const _PlaceResult({required this.place, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: kAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  place.name,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.north_east_rounded, size: 18, color: kTextSub),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FavoritesRow extends StatelessWidget {
  final List<Place> favorites;
  final void Function(Place) onSelect, onDelete;
  const _FavoritesRow({
    required this.favorites,
    required this.onSelect,
    required this.onDelete,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: favorites
        .map(
          (p) => InputChip(
            avatar: const Icon(Icons.star_rounded, size: 14, color: kWarning),
            label: Text(p.name),
            onPressed: () => onSelect(p),
            onDeleted: () => onDelete(p),
            deleteIconColor: kTextSub,
          ),
        )
        .toList(),
  );
}

class _MapCard extends StatelessWidget {
  final AppState state;
  final MapController map;
  final void Function(Place) onSelect;
  final VoidCallback onLocate;
  const _MapCard({
    required this.state,
    required this.map,
    required this.onSelect,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) {
    final s = state;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter:
                    s.location ?? const LatLng(10.762622, 106.660172),
                initialZoom: 15,
                onLongPress: (_, point) =>
                    onSelect(Place('Điểm đã chọn trên bản đồ', point)),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  panBuffer: 0,
                  userAgentPackageName: 'vn.secondsight.secondsight',
                  maxZoom: 19,
                ),
                if (s.route != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: s.route!.points,
                        strokeWidth: 5,
                        color: const Color(0xFF087F73),
                        borderColor: Colors.white.withValues(alpha: 0.85),
                        borderStrokeWidth: 8,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (s.location != null)
                      Marker(
                        point: s.location!,
                        width: 44,
                        height: 44,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: kAccent2,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: kAccent2.withValues(alpha: 0.5),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (s.destination != null)
                      Marker(
                        point: s.destination!.point,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: kDanger,
                          size: 44,
                        ),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Material(
                    color: const Color(0xEEF5FAF8),
                    child: InkWell(
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Text(
                          '© OpenStreetMap contributors',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF1B3C3C),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // GPS chip
            Positioned(
              top: 10,
              left: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kSurface.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: s.freshFix
                            ? kAccent.withValues(alpha: 0.5)
                            : kBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          s.freshFix
                              ? Icons.gps_fixed_rounded
                              : Icons.gps_not_fixed_rounded,
                          color: s.freshFix ? kAccent : kTextSub,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          s.freshFix
                              ? '±${s.accuracy.round()} m'
                              : 'Chưa có GPS',
                          style: const TextStyle(
                            fontSize: 11,
                            color: kText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Locate button
            Positioned(
              right: 10,
              top: 10,
              child: Semantics(
                button: true,
                label: 'Đưa bản đồ về vị trí của tôi',
                child: GestureDetector(
                  onTap: onLocate,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: kSurface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: kAccent,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Journey state badge
            if (s.active || s.offRoute)
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: s.offRoute
                        ? kWarning.withValues(alpha: 0.9)
                        : kAccent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s.offRoute ? 'Lệch tuyến' : 'Đang dẫn đường',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: s.offRoute
                          ? Colors.black
                          : const Color(0xFF001A14),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final String text;
  const _NoticeCard(this.text);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: kAccent.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kAccent.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: kAccent, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: kText, height: 1.4),
          ),
        ),
      ],
    ),
  ).animate().fadeIn(duration: 300.ms);
}

class _NavPanel extends StatelessWidget {
  final AppState state;
  final VoidCallback onFavorite;
  const _NavPanel({required this.state, required this.onFavorite});

  AppState get s => state;

  @override
  Widget build(BuildContext context) {
    final isActiveOrPaused =
        s.active ||
        s.offRoute ||
        s.journey == JourneyState.paused ||
        s.journey == JourneyState.offRoute;

    return GlowCard(
      active: s.active,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Destination header
          Row(
            children: [
              Expanded(
                child: Text(
                  s.destination?.name ?? 'Chọn điểm đến để bắt đầu',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: kText,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (s.destination != null)
                IconButton(
                  onPressed: onFavorite,
                  icon: const Icon(Icons.bookmark_add_outlined, color: kAccent),
                  tooltip: 'Lưu yêu thích',
                  padding: EdgeInsets.zero,
                ),
            ],
          ),

          if (s.route != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _RoutePill(
                  '${(s.route!.distance / 1000).toStringAsFixed(2)} km',
                ),
                const SizedBox(width: 8),
                _RoutePill('${(s.route!.seconds / 60).ceil()} phút'),
                const SizedBox(width: 8),
                _RoutePill('Đi bộ', icon: Icons.directions_walk_rounded),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Lưu lúc ${s.route!.created.toLocal().toString().substring(0, 16)}',
              style: const TextStyle(fontSize: 11, color: kTextSub),
            ),
          ],

          // ── Active navigation instruction
          if (isActiveOrPaused) ...[
            const Divider(height: 24),
            Semantics(liveRegion: true, child: _journeyStatus(context)),
            if (s.progress != null) ...[
              const SizedBox(height: 8),
              _RemainingBar(remaining: s.progress!.remaining, route: s.route!),
            ],
            if (s.syncPending && !s.demo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kWarning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Đang chờ kính xác nhận…',
                      style: TextStyle(color: kWarning, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 16),

          // ── Action buttons
          _ActionButtons(state: s),

          // ── Steps accordion
          if (s.route != null) ...[
            const SizedBox(height: 8),
            _StepsAccordion(route: s.route!, progress: s.progress),
          ],
        ],
      ),
    );
  }

  Widget _journeyStatus(BuildContext context) {
    if (s.journey == JourneyState.arrived) {
      return Row(
        children: [
          const Icon(Icons.place_rounded, color: kAccent, size: 28),
          const SizedBox(width: 12),
          const Text(
            'Đã đến điểm đến!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: kAccent,
            ),
          ),
        ],
      );
    }
    if (s.journey == JourneyState.paused) {
      return const Text(
        'Đã tạm dừng',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: kTextSub,
        ),
      );
    }
    if (!s.freshFix) {
      return const Text(
        'GPS yếu — tạm dừng chỉ dẫn',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: kWarning,
        ),
      );
    }
    if (!s.connected) {
      return const Text(
        'Mất kết nối kính',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: kDanger,
        ),
      );
    }
    if (s.offRoute) {
      return const Text(
        'Lệch tuyến — đang tìm lại',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: kWarning,
        ),
      );
    }
    if (s.instruction != null && s.progress != null) {
      return NavInstruction(
        action: s.instruction!.action,
        text: s.instruction!.text,
        distanceM: s.progress!.distanceToStep,
        valid: s.freshFix && !s.syncPending,
      );
    }
    return const Text(
      'Đang định vị…',
      style: TextStyle(fontSize: 18, color: kTextSub),
    );
  }
}

class _RoutePill extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _RoutePill(this.text, {this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: kAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kAccent.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon!, size: 12, color: kAccent),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: kAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _RemainingBar extends StatelessWidget {
  final double remaining;
  final WalkRoute route;
  const _RemainingBar({required this.remaining, required this.route});
  @override
  Widget build(BuildContext context) {
    final fraction = (remaining / route.distance).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Còn ${remaining.round()} m theo tuyến',
          style: const TextStyle(fontSize: 12, color: kTextSub),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: 1 - fraction,
            backgroundColor: kBorder,
            valueColor: const AlwaysStoppedAnimation(kAccent),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final AppState state;
  const _ActionButtons({required this.state});
  AppState get s => state;

  @override
  Widget build(BuildContext context) {
    final isActiveOrPaused = s.active || s.journey == JourneyState.paused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!s.active &&
            s.journey != JourneyState.paused &&
            s.journey != JourneyState.arrived)
          FilledButton.icon(
            onPressed: s.busy || s.destination == null
                ? null
                : () => s.perform(s.plan),
            icon: s.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF001A14),
                    ),
                  )
                : const Icon(Icons.alt_route_rounded),
            label: Text(
              s.busy
                  ? 'Đang tìm tuyến…'
                  : s.journey == JourneyState.routing
                  ? 'Đang tính toán…'
                  : 'Lấy tuyến đi bộ',
            ),
          ),
        if (s.route != null && !s.active && s.journey != JourneyState.arrived)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton.icon(
              onPressed: s.busy ? null : () => s.perform(s.start),
              icon: const Icon(Icons.navigation_rounded),
              label: Text(
                s.journey == JourneyState.paused
                    ? 'Tiếp tục hành trình'
                    : 'Bắt đầu hành trình',
              ),
            ),
          ),
        if (s.active)
          FilledButton.icon(
            onPressed: () => s.perform(s.pause),
            icon: const Icon(Icons.pause_rounded),
            label: const Text('Tạm dừng'),
            style: FilledButton.styleFrom(
              backgroundColor: kWarning,
              foregroundColor: Colors.black,
            ),
          ),
        if (isActiveOrPaused || s.journey == JourneyState.arrived)
          TextButton.icon(
            onPressed: () => s.perform(s.stop),
            icon: const Icon(Icons.stop_rounded, color: kDanger),
            label: const Text(
              'Kết thúc hành trình',
              style: TextStyle(color: kDanger),
            ),
          ),
      ],
    );
  }
}

class _StepsAccordion extends StatelessWidget {
  final WalkRoute route;
  final NavProgress? progress;
  const _StepsAccordion({required this.route, this.progress});
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text(
      'Các bước chỉ dẫn',
      style: TextStyle(fontSize: 13, color: kTextSub),
    ),
    tilePadding: EdgeInsets.zero,
    iconColor: kTextSub,
    collapsedIconColor: kTextSub,
    children: route.steps.asMap().entries.map((e) {
      final i = e.key;
      final step = e.value;
      final isCurrent = progress?.step == i;
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? kAccent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isCurrent
              ? Border.all(color: kAccent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              _stepIcon(step.action),
              color: isCurrent ? kAccent : kTextSub,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: isCurrent ? kAccent : kText,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (step.street.isNotEmpty)
                    Text(
                      step.street,
                      style: const TextStyle(fontSize: 11, color: kTextSub),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList(),
  );

  IconData _stepIcon(String action) => switch (action) {
    'turn_right' => Icons.turn_right_rounded,
    'turn_left' => Icons.turn_left_rounded,
    'arrive' => Icons.place_rounded,
    'roundabout' => Icons.roundabout_left_rounded,
    'u_turn' => Icons.u_turn_left_rounded,
    _ => Icons.straight_rounded,
  };
}

class _CompassRow extends StatelessWidget {
  final AppState state;
  const _CompassRow({required this.state});
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CompassWidget(
            targetBearing: state.targetBearing,
            deviceHeading: state.stm32Ready ? state.stm32Heading : 0,
            size: 100,
            active: state.active && state.stm32Ready,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hướng mục tiêu: ${state.targetBearing.round()}°',
                  style: const TextStyle(
                    fontSize: 13,
                    color: kText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.stm32Ready
                      ? 'Hướng kính: ${state.stm32Heading.round()}°'
                      : 'Hướng kính: chưa hợp lệ',
                  style: const TextStyle(fontSize: 12, color: kTextSub),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: kAccent2, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${state.speed.toStringAsFixed(1)} m/s',
                      style: const TextStyle(fontSize: 12, color: kTextSub),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Device Page ─────────────────────────────────────────────────
class _DevicePage extends StatelessWidget {
  final AppState state;
  const _DevicePage({required this.state});
  AppState get s => state;

  @override
  Widget build(BuildContext context) {
    final good = s.connected && s.statusFresh;
    String v(String key, [String unit = '']) =>
        good && s.status[key] != null ? '${s.status[key]}$unit' : '—';

    final battPct = good && s.status['battery_percent'] is num
        ? (s.status['battery_percent'] as num).toDouble() / 100
        : null;
    final fps = good && s.status['yolo_fps'] is num
        ? (s.status['yolo_fps'] as num).toDouble() / 30
        : null;
    final temp = good && s.status['cpu_temp'] is num
        ? ((s.status['cpu_temp'] as num).toDouble() / 100).clamp(0, 1.0)
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        // ── Connection card
        GlowCard(
          active: s.link.connected && !s.demo,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kAccent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.visibility_outlined,
                      color: kAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusDot(active: s.link.connected || s.demo),
                            const SizedBox(width: 8),
                            Text(
                              s.demo || s.status['demo'] == true
                                  ? 'Kính mô phỏng'
                                  : s.link.connected
                                  ? 'Đã kết nối'
                                  : 'Chưa kết nối',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: kText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.demo || s.status['demo'] == true
                              ? 'Dữ liệu giả lập'
                              : s.link.endpoint,
                          style: const TextStyle(fontSize: 12, color: kTextSub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: s.demo
                    ? null
                    : () async {
                        if (s.link.connected) {
                          s.link.disconnect();
                        } else {
                          await s.perform(() async {
                            await s.link.connect();
                            if (!s.link.connected) {
                              s.notice =
                                  'Chưa kết nối được. App sẽ tự thử lại.';
                            }
                          });
                        }
                      },
                icon: Icon(
                  s.link.connected
                      ? Icons.link_off_rounded
                      : Icons.link_rounded,
                ),
                label: Text(s.link.connected ? 'Ngắt kết nối' : 'Kết nối kính'),
                style: FilledButton.styleFrom(
                  backgroundColor: s.link.connected
                      ? kDanger.withValues(alpha: 0.15)
                      : null,
                  foregroundColor: s.link.connected ? kDanger : null,
                ),
              ),
              if (!s.demo)
                TextButton(
                  onPressed: () {
                    s.link.disconnect();
                  },
                  child: const Text('Dừng thử kết nối'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── HUD metrics
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.1,
          children: [
            HudMetric(
              label: 'Pin kính',
              value: v('battery_percent', '%'),
              icon: Icons.battery_5_bar_rounded,
              fill: battPct,
              accentColor: _battColor(battPct),
            ),
            HudMetric(
              label: 'YOLO FPS',
              value: v('yolo_fps', ' fps'),
              icon: Icons.speed_rounded,
              fill: fps,
              accentColor: kAccent2,
            ),
            HudMetric(
              label: 'Nhiệt độ Pi',
              value: v('cpu_temp', ' °C'),
              icon: Icons.thermostat_rounded,
              fill: temp?.clamp(0.0, 1.0).toDouble(),
              accentColor: kWarning,
            ),
            HudMetric(
              label: 'Sai số GPS',
              value: s.freshFix ? '${s.accuracy.round()} m' : '—',
              icon: Icons.gps_fixed_rounded,
              fill: s.freshFix ? (1 - (s.accuracy / 25).clamp(0.0, 1.0)) : null,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Sensor status
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              ...{
                'camera_ok': ('Camera (Pi)', Icons.camera_alt_outlined),
                'lidar_ok': (
                  'LiDAR / cảm biến khoảng cách',
                  Icons.radar_outlined,
                ),
                'stm32_ok': (
                  'STM32F411E-DISCO (IMU)',
                  Icons.developer_board_rounded,
                ),
              }.entries.map((e) {
                final ok = good && s.status[e.key] == true;
                final fault = good && s.status[e.key] == false;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        e.value.$2,
                        color: !good
                            ? kTextSub
                            : ok
                            ? kAccent
                            : kDanger,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.value.$1,
                          style: const TextStyle(color: kText, fontSize: 13),
                        ),
                      ),
                      Text(
                        !good
                            ? '—'
                            : ok
                            ? 'Hoạt động'
                            : fault
                            ? 'Lỗi'
                            : '—',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: !good
                              ? kTextSub
                              : ok
                              ? kAccent
                              : kDanger,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // ── STM32 calibration row
              if (good && s.status['stm32_ok'] == true) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Icon(
                      s.stm32Ready
                          ? Icons.verified_outlined
                          : Icons.warning_amber,
                      color: s.stm32Ready ? kAccent : kWarning,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.stm32Ready
                            ? 'IMU đã hiệu chuẩn'
                            : 'IMU chưa hiệu chuẩn — không xác nhận hướng rẽ',
                        style: TextStyle(
                          color: s.stm32Ready ? kAccent : kWarning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(height: 16),
              const Text(
                'Ưu tiên trên kính: nguy hiểm → giao thông → chỉ đường → thông tin phụ. '
                'STM32 mất kết nối hoặc chưa hiệu chuẩn: không xác nhận hướng rẽ. '
                'Cảnh báo vật cản bằng camera và cảm biến vẫn tiếp tục trên Pi.',
                style: TextStyle(fontSize: 11, color: kTextSub, height: 1.4),
              ),
            ],
          ),
        ),

        // ── STM32 heading card (visible when STM32 active)
        const SizedBox(height: 12),
        OrientationHud(
          ready: s.stm32Ready,
          demo: s.demo || s.status['demo'] == true,
          heading: s.stm32Heading,
          pitch: (s.status['stm32_pitch'] as num?)?.toDouble() ?? 0,
          roll: (s.status['stm32_roll'] as num?)?.toDouble() ?? 0,
          title: 'Không gian chuyển động',
          subtitle: s.stm32Ready
              ? 'Pitch ${v('stm32_pitch', '°')}  /  Roll ${v('stm32_roll', '°')}'
              : 'Đang chờ STM32 kết nối và hiệu chuẩn.',
        ),

        if (s.demo) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: s.demoHazard,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Thử cảnh báo mép hụt'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Bật hotspot trong cài đặt điện thoại và cho Pi kết nối cùng mạng. '
          'Nếu secondsight.local không phân giải, nhập IP LAN của Pi trong Cài đặt.',
          style: TextStyle(fontSize: 12, color: kTextSub, height: 1.5),
        ),
        if (s.notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _NoticeCard(s.notice!),
          ),
      ],
    );
  }

  Color _battColor(double? v) {
    if (v == null) return kTextSub;
    if (v > 0.5) return kAccent;
    if (v > 0.2) return kWarning;
    return kDanger;
  }
}

// ─── Logs Page ───────────────────────────────────────────────────
class _LogsPage extends StatelessWidget {
  final AppState state;
  final Future<void> Function(String) onShare;
  const _LogsPage({required this.state, required this.onShare});
  AppState get s => state;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    children: [
      const Text(
        'Nhật ký sự kiện',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: kText,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Lưu tối đa 300 sự kiện. Không ghi video, token hoặc GPS đầy đủ.',
        style: TextStyle(fontSize: 12, color: kTextSub),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => s.perform(
              () =>
                  onShare(const JsonEncoder.withIndent('  ').convert(s.events)),
            ),
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Xuất JSON'),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Xóa nhật ký?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Giữ lại'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Xóa'),
                    ),
                  ],
                ),
              );
              if (ok == true) await s.perform(s.clearLogs);
            },
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: kDanger,
            ),
            label: const Text('Xóa', style: TextStyle(color: kDanger)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (s.events.isEmpty)
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: Text('Chưa có sự kiện.', style: TextStyle(color: kTextSub)),
          ),
        ),
      ...s.events.asMap().entries.map((e) {
        final ev = e.value;
        final isHazard = ev['type'] == 'hazard';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHazard ? kDanger.withValues(alpha: 0.3) : kBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isHazard ? Icons.warning_amber_rounded : Icons.history_rounded,
                color: isHazard ? kDanger : kTextSub,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ev['text']}',
                      style: const TextStyle(fontSize: 13, color: kText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ev['time']}  •  ${ev['type']}',
                      style: const TextStyle(fontSize: 10, color: kTextSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate(delay: (e.key * 30).ms).fadeIn(duration: 200.ms);
      }),
    ],
  );
}

// ─── Settings Page ───────────────────────────────────────────────
class _SettingsPage extends StatefulWidget {
  final AppState state;
  const _SettingsPage({required this.state});
  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController endpoint, token, apiKey, phone;
  bool saved = false;
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    endpoint = TextEditingController(text: s.link.endpoint);
    token = TextEditingController(text: s.link.token);
    apiKey = TextEditingController(text: s.routing.key);
    phone = TextEditingController(text: s.emergencyPhone);
  }

  @override
  void dispose() {
    endpoint.dispose();
    token.dispose();
    apiKey.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    children: [
      const Text(
        'Cài đặt',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: kText,
        ),
      ),
      const SizedBox(height: 18),

      // ── Demo mode
      GlassCard(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Chế độ mô phỏng',
            style: TextStyle(color: kText, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Thử tuyến và chỉ dẫn không cần Pi hoặc API key.',
            style: TextStyle(color: kTextSub, fontSize: 12),
          ),
          value: s.demo,
          activeThumbColor: kAccent,
          onChanged: (v) => s.perform(() => s.setDemo(v)),
        ),
      ),
      const SizedBox(height: 16),

      // ── Pi connection
      _Section('Kết nối kính'),
      const SizedBox(height: 12),
      _Field(
        controller: endpoint,
        label: 'Địa chỉ Pi',
        hint: 'https://secondsight.local:8765',
        keyboard: TextInputType.url,
      ),
      const SizedBox(height: 10),
      _Field(controller: token, label: 'Token ghép đôi', obscure: true),
      const SizedBox(height: 4),
      GlassCard(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Cho phép HTTP LAN thử nghiệm',
            style: TextStyle(
              color: kText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Không mã hóa. Chỉ dùng mạng hotspot tin cậy.',
            style: TextStyle(color: kTextSub, fontSize: 11),
          ),
          value: s.link.allowInsecure,
          activeThumbColor: kWarning,
          onChanged: (v) => setState(() => s.link.allowInsecure = v),
        ),
      ),
      const SizedBox(height: 16),

      // ── Routing
      _Section('Bản đồ & Liên hệ'),
      const SizedBox(height: 12),
      _Field(controller: apiKey, label: 'GraphHopper API key', obscure: true),
      const SizedBox(height: 10),
      _Field(
        controller: phone,
        label: 'Số điện thoại người thân',
        hint: '+84…',
        keyboard: TextInputType.phone,
      ),
      const SizedBox(height: 16),

      // ── Warning level
      _Section('Âm thanh & Cảnh báo'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: s.warningLevel,
        decoration: const InputDecoration(labelText: 'Mức cảnh báo'),
        dropdownColor: kSurface,
        style: const TextStyle(color: kText, fontSize: 14),
        items: const [
          DropdownMenuItem(value: 'low', child: Text('Ít')),
          DropdownMenuItem(value: 'normal', child: Text('Bình thường')),
          DropdownMenuItem(value: 'detailed', child: Text('Chi tiết')),
        ],
        onChanged: (v) => setState(() => s.warningLevel = v!),
      ),
      const SizedBox(height: 14),
      _SliderRow(
        'Âm lượng',
        '${(s.volume * 100).round()}%',
        value: s.volume,
        min: 0,
        max: 1,
        divisions: 10,
        onChanged: (v) => setState(() => s.volume = v),
      ),
      _SliderRow(
        'Tốc độ đọc',
        s.speechRate.toStringAsFixed(1),
        value: s.speechRate,
        min: 0.2,
        max: 0.8,
        divisions: 6,
        onChanged: (v) => setState(() => s.speechRate = v),
      ),
      GlassCard(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Rung khi có cảnh báo',
            style: TextStyle(
              color: kText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          value: s.vibration,
          activeThumbColor: kAccent,
          onChanged: (v) => setState(() => s.vibration = v),
        ),
      ),
      const SizedBox(height: 20),

      // ── Save
      FilledButton.icon(
        onPressed: () => s.perform(() async {
          final nextEndpoint = endpoint.text.trim();
          final nextToken = token.text.trim();
          if (s.link.endpoint != nextEndpoint || s.link.token != nextToken) {
            s.link.disconnect();
          }
          s.link.endpoint = nextEndpoint;
          s.link.token = nextToken;
          s.routing.key = apiKey.text.trim();
          s.emergencyPhone = phone.text.trim();
          await s.saveSettings();
          if (mounted) setState(() => saved = true);
        }),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Lưu cài đặt'),
      ),
      if (saved)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Đã lưu. Cấu hình kính đồng bộ khi kết nối.',
            style: const TextStyle(color: kAccent, fontSize: 12),
          ),
        ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => s.perform(() async {
          await s.configureSpeech();
          await s.say('SecondSight. Chúc bạn có một hành trình an toàn.');
        }),
        icon: const Icon(Icons.volume_up_rounded, size: 16),
        label: const Text('Nghe thử giọng đọc'),
      ),
      TextButton.icon(
        onPressed: () => Geolocator.openAppSettings(),
        icon: const Icon(Icons.settings_rounded, size: 16),
        label: const Text('Mở quyền ứng dụng'),
      ),
      const SizedBox(height: 16),
      const Text(
        'Tuyến lưu dùng được khi mất mạng ngắn hạn. '
        'Kính tự xử lý cảnh báo cục bộ khi mất kết nối điện thoại.',
        style: TextStyle(fontSize: 11, color: kTextSub, height: 1.5),
      ),
      const SizedBox(height: 24),
    ],
  );
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: kAccent,
      letterSpacing: 0.3,
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboard,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    autocorrect: false,
    enableSuggestions: !obscure,
    keyboardType: keyboard,
    style: const TextStyle(color: kText),
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

class _SliderRow extends StatelessWidget {
  final String label, valueTxt;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow(
    this.label,
    this.valueTxt, {
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: kTextSub)),
            const Spacer(),
            Text(
              valueTxt,
              style: const TextStyle(
                fontSize: 13,
                color: kAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

// ─── STM32 Calibration Row ────────────────────────────────────────
class _Stm32CalibrationRow extends StatelessWidget {
  final AppState state;
  final bool good;
  const _Stm32CalibrationRow({required this.state, required this.good});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final calibrated = good && s.status['stm32_calibrated'] == true;
    final color = calibrated ? kAccent : kWarning;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                calibrated
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 13,
              ),
              const SizedBox(width: 5),
              Text(
                calibrated ? 'Đã hiệu chuẩn' : 'Chưa hiệu chuẩn',
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            calibrated
                ? 'Madgwick/Mahony sẵn sàng — heading đang xác nhận rẽ'
                : 'Cảnh báo vật cản bằng camera vẫn hoạt động bình thường',
            style: const TextStyle(fontSize: 11, color: kTextSub, height: 1.35),
          ),
        ),
      ],
    );
  }
}

// ─── STM32 Heading Card ───────────────────────────────────────────
class _Stm32HeadingCard extends StatelessWidget {
  final AppState state;
  const _Stm32HeadingCard({required this.state});

  String _fmt(String key, [String suffix = '']) {
    final v = state.status[key];
    if (v is num) return '${v.toStringAsFixed(1)}$suffix';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final calibrated = s.status['stm32_calibrated'] == true;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: calibrated
          ? kAccent.withValues(alpha: 0.25)
          : kWarning.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.developer_board_rounded,
                color: calibrated ? kAccent : kWarning,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'STM32F411E-DISCO  •  Madgwick / Mahony',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: calibrated ? kAccent : kWarning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ImuCell(label: 'Heading', value: _fmt('stm32_heading', '°')),
              _ImuCell(label: 'Pitch', value: _fmt('stm32_pitch', '°')),
              _ImuCell(label: 'Roll', value: _fmt('stm32_roll', '°')),
            ],
          ),
          if (s.active && calibrated) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: kAccent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  'Target ${s.targetBearing.toStringAsFixed(1)}°  •  '
                  'STM32 ${_fmt('stm32_heading', '°')}  •  '
                  'Δ ${(s.targetBearing - (s.status['stm32_heading'] is num ? (s.status['stm32_heading'] as num).toDouble() : s.targetBearing)).abs().toStringAsFixed(1)}°',
                  style: const TextStyle(fontSize: 11, color: kTextSub),
                ),
              ],
            ),
          ],
          if (!calibrated) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kWarning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kWarning.withValues(alpha: 0.2)),
              ),
              child: const Text(
                'STM32 chưa hiệu chuẩn hoặc mất kết nối — xác nhận hướng rẽ tạm dừng. '
                'Camera và cảm biến vẫn cảnh báo vật cản bình thường.',
                style: TextStyle(fontSize: 11, color: kWarning, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImuCell extends StatelessWidget {
  final String label, value;
  const _ImuCell({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: kText,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: kTextSub)),
      ],
    ),
  );
}

// ─── Hands-free listening overlay (Siri-style orb) ───────────────
class _ListeningOverlay extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;
  const _ListeningOverlay({required this.text, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Đang nghe. Hãy nói điểm đến. Chạm để huỷ.',
      child: GestureDetector(
        onTap: onCancel,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: kBg.withValues(alpha: .78),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (i.isEven ? kAccent : kAccent2)
                                        .withValues(alpha: .5),
                                    width: 2,
                                  ),
                                ),
                              )
                              .animate(onPlay: (c) => c.repeat())
                              .scale(
                                delay: (i * 500).ms,
                                duration: 1500.ms,
                                begin: const Offset(1, 1),
                                end: const Offset(1.7, 1.7),
                              )
                              .fadeOut(delay: (i * 500).ms, duration: 1500.ms),
                        Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const SweepGradient(
                                  colors: [
                                    kAccent,
                                    kAccent2,
                                    Color(0xFFF472B6),
                                    kAccent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kAccent.withValues(alpha: .45),
                                    blurRadius: 40,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.mic_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(
                              duration: 900.ms,
                              curve: Curves.easeInOut,
                              begin: const Offset(.94, .94),
                              end: const Offset(1.06, 1.06),
                            )
                            .rotate(duration: 6.seconds, begin: 0, end: .02),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Đang nghe…',
                    style: TextStyle(
                      color: kAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: 200.ms,
                    child: Text(
                      text.isEmpty ? '“Đưa tôi đến chợ Bến Thành”' : text,
                      key: ValueKey(text),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: text.isEmpty ? kTextSub : kText,
                        fontSize: 26,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  const Text(
                    'Chạm để huỷ',
                    style: TextStyle(color: kTextSub, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
