import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models.dart';
import '../services/pi_link.dart';
import '../services/location_policy.dart';
import '../services/routing.dart';
import '../services/voice_intent.dart';
import '../services/speech_output.dart';

// ────────────────────────────────────────────────────────────────
//  Navigation State Machine
//  IDLE → ROUTING → READY → NAVIGATING ↔ OFF_ROUTE → ARRIVED
// ────────────────────────────────────────────────────────────────
enum JourneyState {
  idle,
  routing,
  ready,
  navigating,
  offRoute,
  paused,
  arrived,
}

/// Maximum GPS accuracy (m) accepted for navigation decisions.
const double _kMaxAccuracyM = 20.0;

class AppState extends ChangeNotifier {
  final routing = RoutingService();
  final link = PiLink();
  final tts = FlutterTts();
  late final _speechOutput = SpeechOutput(
    speak: (text) => speechReady ? tts.speak(text) : Future.value(),
    stop: tts.stop,
    onError: _reportSpeechError,
  );

  bool speechReady = false;
  String? speechIssue;

  void _reportSpeechError(Object detail) {
    speechReady = false;
    speechIssue = detail is TimeoutException
        ? 'Bộ đọc không phản hồi. Đã dừng thử đọc tự động. '
              'Kiểm tra dịch vụ đọc giọng nói của điện thoại, rồi chọn Nghe thử giọng đọc.'
        : 'Không khởi động được giọng đọc tiếng Việt. '
              'Bộ đọc hiện tại có thể chưa hỗ trợ hoặc chưa tải giọng tiếng Việt. '
              'Chọn bộ đọc hỗ trợ tiếng Việt trong cài đặt điện thoại, '
              'tải giọng tiếng Việt rồi chọn Nghe thử giọng đọc.';
    error = speechIssue;
    log('tts_error', '$speechIssue ($detail)');
    notifyListeners();
  }

  Future<void> configureSpeech() async {
    speechReady = false;
    try {
      var language = await tts
          .setLanguage('vi-VN')
          .timeout(const Duration(seconds: 8));
      if (language != 1) {
        // Some engines expose Vietnamese as "vi" or a voice-specific locale.
        final voices = await tts.getVoices.timeout(const Duration(seconds: 8));
        if (voices is List) {
          final vietnamese = voices.whereType<Map>().where((voice) {
            final locale = '${voice['locale']}'
                .replaceAll('_', '-')
                .toLowerCase();
            return locale == 'vi' || locale.startsWith('vi-');
          }).toList();
          // Prefer installed offline voices over voices requiring a network.
          vietnamese.sort(
            (a, b) => ('${a['network_required']}' == 'true' ? 1 : 0).compareTo(
              '${b['network_required']}' == 'true' ? 1 : 0,
            ),
          );
          for (final voice in vietnamese) {
            if (voice['name'] is! String || voice['locale'] is! String)
              continue;
            language = await tts
                .setLanguage(voice['locale'] as String)
                .timeout(const Duration(seconds: 8));
            if (language != 1) continue;
            final selected = await tts
                .setVoice({
                  'name': voice['name'] as String,
                  'locale': voice['locale'] as String,
                })
                .timeout(const Duration(seconds: 8));
            if (selected == 1) break;
            language = 0;
          }
        }
      }
      if (language != 1) {
        throw StateError(
          'Bộ đọc hiện tại từ chối vi-VN và không có giọng tiếng Việt khả dụng.',
        );
      }
      await tts.setVolume(volume).timeout(const Duration(seconds: 8));
      await tts.setSpeechRate(speechRate).timeout(const Duration(seconds: 8));
      await tts.awaitSpeakCompletion(true).timeout(const Duration(seconds: 8));
      speechReady = true;
      if (error == speechIssue) error = null;
      speechIssue = null;
      notifyListeners();
    } catch (e) {
      _reportSpeechError(e);
    }
  }

  final secure = const FlutterSecureStorage();
  late SharedPreferences prefs;

  bool loaded = false, busy = false, demo = false, vibration = true;
  bool syncing = false, syncPending = false;
  String? error, notice, hazard;
  DateTime? hazardAt, statusAt, fixAt;
  String warningLevel = 'normal', emergencyPhone = '';
  double volume = 0.8, speechRate = 0.5, accuracy = double.infinity;

  /// Speed from Fused Location Provider (m/s). Updated every GPS fix.
  double speed = 0;

  /// Raw GPS bearing (course over ground), degrees 0-360, from FLP.
  /// Only valid when speed > 0.5 m/s; use [targetBearing] for UI compass.
  double gpsBearing = 0;

  /// Target bearing computed by Haversine to the next maneuver waypoint.
  double targetBearing = 0;

  /// Fused heading from STM32F411E-DISCO (Madgwick/Mahony), degrees 0-360.
  /// Received in [device_status] messages from Pi's STM32IMUReceiverThread.
  double stm32Heading = 0;

  /// True when STM32 is connected AND its calibration flag is set.
  bool get stm32Ready =>
      connected &&
      statusFresh &&
      status['stm32_ok'] == true &&
      status['stm32_calibrated'] == true &&
      status['stm32_heading'] is num &&
      (status['stm32_heading'] as num).isFinite;

  LatLng? location;
  Place? destination;
  WalkRoute? route;
  NavProgress? progress;
  JourneyState journey = JourneyState.idle;
  Map<String, dynamic> status = {};
  List<Place> favorites = [];
  List<Map<String, dynamic>> events = [];

  StreamSubscription<Position>? _gps;
  Timer? _ticker;
  int _segment = 0, _offRouteCount = 0, _demoIndex = 0, _revision = 0, _seq = 0;
  int _routeGeneration = 0;
  bool _hasProjection = false, _gpsWarned = false;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  String _session = const Uuid().v4(), _lastSpoken = '';
  DateTime _phoneBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Track which milestone was last announced to avoid repeating.
  int _lastMilestone = -1;

  bool get onRoute => _offRouteCount == 0;
  void startupFailed(Object e) {
    error = 'Khởi tạo thất bại: $e';
    loaded = true;
    notifyListeners();
  }

  bool get active => journey == JourneyState.navigating;
  bool get offRoute => journey == JourneyState.offRoute;

  /// A GPS fix is "fresh" if it arrived within 8 s and has sufficient accuracy.
  bool get freshFix =>
      fixAt != null &&
      !DateTime.now().isBefore(fixAt!) &&
      DateTime.now().difference(fixAt!) <= const Duration(seconds: 8) &&
      accuracy <= _kMaxAccuracyM;

  bool get statusFresh =>
      statusAt != null && DateTime.now().difference(statusAt!).inSeconds < 6;
  bool get connected => demo || link.connected;
  Maneuver? get instruction =>
      route == null || progress == null ? null : route!.steps[progress!.step];

  // ─── Init ───────────────────────────────────────────────────────
  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    try {
      routing.key = await secure.read(key: 'routing_key') ?? '';
      link.token = await secure.read(key: 'pi_token') ?? '';
      link.endpoint = prefs.getString('endpoint') ?? link.endpoint;
      link.allowInsecure = prefs.getBool('allow_insecure') ?? false;
      emergencyPhone = prefs.getString('emergency_phone') ?? '';
      volume = prefs.getDouble('volume') ?? 0.8;
      speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      vibration = prefs.getBool('vibration') ?? true;
      warningLevel = prefs.getString('warning_level') ?? 'normal';
      favorites = (jsonDecode(prefs.getString('favorites') ?? '[]') as List)
          .map((j) => Place.fromJson(j))
          .toList();
      events = (jsonDecode(prefs.getString('events') ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final cached = prefs.getString('route');
      if (cached != null) {
        route = WalkRoute.fromJson(jsonDecode(cached));
        destination = route!.destination;
        demo = route!.demo;
        journey = JourneyState.ready;
        notice = 'Đã khôi phục tuyến lưu. Kiểm tra tuyến và nhấn Bắt đầu để tiếp tục.';
      }
      demo = prefs.getBool('demo_mode') ?? demo;
      if (demo) {
        if (route == null || !route!.demo) route = demoRoute();
        destination = route!.destination;
        location = route!.points.first;
        accuracy = 3;
        fixAt = DateTime.now();
        journey = JourneyState.ready;
        notice =
            'MÔ PHỎNG: vị trí, tuyến và trạng thái kính là dữ liệu giả lập.';
      }
    } catch (_) {
      error =
          'Không đọc được một phần cấu hình đã lưu. Vui lòng kiểm tra Cài đặt.';
    }
    await configureSpeech();

    link.onConnection = (ok) {
      if (ok) {
        log('connection', 'Đã kết nối kính');
        syncPending = true;
        unawaited(sync());
      } else {
        status = {};
        statusAt = null;
        syncPending = true;
        log('connection_lost', 'Mất kết nối kính; chỉ dẫn trên kính tạm dừng.');
        unawaited(say('Mất kết nối kính. Chỉ dẫn trên kính đang tạm dừng.'));
      }
      notifyListeners();
    };
    link.onMessage = _message;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    loaded = true;
    notifyListeners();
  }

  // ─── Helpers ────────────────────────────────────────────────────
  Future<void> perform(Future<void> Function() task) async {
    try {
      error = null;
      await task();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> say(String text, {bool urgent = false}) async {
    if (!speechReady) return;
    if (urgent) {
      _phoneBlockedUntil = DateTime.now().add(const Duration(seconds: 6));
    } else if (DateTime.now().isBefore(_phoneBlockedUntil)) {
      return;
    }
    await _speechOutput.say(text, urgent: urgent);
  }

  void log(String type, String text) {
    events.insert(0, {
      'time': DateTime.now().toIso8601String(),
      'type': type,
      'text': text,
    });
    if (events.length > 300) events.removeRange(300, events.length);
    if (loaded) unawaited(prefs.setString('events', jsonEncode(events)));
  }

  // ─── WebSocket messages from Pi ─────────────────────────────────
  void _message(Map<String, dynamic> j) {
    if (j['type'] == 'device_status') {
      j = Map<String, dynamic>.from(j);
      for (final key in ['stm32_heading', 'stm32_pitch', 'stm32_roll']) {
        final value = j[key];
        final valid =
            value is num &&
            value.isFinite &&
            (key == 'stm32_heading'
                ? value >= 0 && value < 360
                : value.abs() <= 180);
        if (!valid) {
          j[key] = null;
          j['stm32_calibrated'] = false;
        }
      }
      final old = status;
      status = j;
      statusAt = DateTime.now();

      // Check sensor faults: camera, LiDAR, STM32 IMU.
      for (final sensor in ['camera_ok', 'lidar_ok', 'stm32_ok']) {
        if (j[sensor] == false && old[sensor] != false) {
          log('sensor_fault', '$sensor: mất tín hiệu');
        }
      }

      // STM32 calibration lost — warn once.
      if (j['stm32_ok'] == true &&
          j['stm32_calibrated'] == false &&
          old['stm32_calibrated'] != false) {
        log(
          'stm32_uncal',
          'STM32 chưa hiệu chuẩn — xác nhận hướng rẽ tạm dừng.',
        );
      }

      // Extract STM32 fused heading from Pi's STM32IMUReceiverThread.
      if (j['stm32_heading'] is num) {
        stm32Heading = (j['stm32_heading'] as num).toDouble();
      }

      if (j['yolo_fps'] is num &&
          (j['yolo_fps'] as num) < 10 &&
          (old['yolo_fps'] is! num || (old['yolo_fps'] as num) >= 10)) {
        log('low_fps', 'FPS nhận diện dưới 10');
      }
    } else if (j['type'] == 'hazard') {
      hazard = '${j['message'] ?? j['hazard_class'] ?? 'Nguy hiểm phía trước'}';
      hazardAt = DateTime.now();
      log('hazard', hazard!);
      if (vibration) unawaited(HapticFeedback.heavyImpact());
      // Pi owns spoken hazards; mobile only displays + vibrates.
    } else if (j['type'] == 'system_error') {
      log('system_error', '${j['message'] ?? 'Lỗi Pi'}');
    }
    notifyListeners();
  }

  // ─── GPS — Fused Location Provider (Android only) ───────────────
  //
  // Priority strategy (Fused Location Provider):
  //   • Navigating  → PRIORITY_HIGH_ACCURACY (GPS + Wi-Fi + cellular, max accuracy)
  //   • Idle / ready → PRIORITY_BALANCED_POWER_ACCURACY (Wi-Fi + cellular, battery-saving)
  // ─────────────────────────────────────────────────────────────────
  Future<void> _applyGpsPriority() async {
    if (demo || _gps == null) return;
    await _restartGps();
  }

  Future<void> _restartGps() async {
    await _gps?.cancel();
    _gps =
        Geolocator.getPositionStream(
          locationSettings: locationSettingsFor(active || offRoute),
        ).listen(
          _position,
          onError: (Object e) {
            fixAt = null;
            error = 'GPS gián đoạn. Kiểm tra quyền vị trí.';
            log('gps_error', error!);
            notifyListeners();
          },
        );
  }

  Future<void> locate() async {
    if (demo) {
      location = (route ?? demoRoute()).points.first;
      accuracy = 3;
      speed = 0;
      fixAt = DateTime.now();
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Hãy bật dịch vụ vị trí trên điện thoại.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Quyền vị trí bị chặn. Mở Cài đặt ứng dụng để cho phép.');
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Cần quyền vị trí để chỉ đường.');
    }

    await _restartGps();
    final p = await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        forceLocationManager: false,
        accuracy: active || offRoute
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      ),
    );
    _position(p);
    if (!freshFix) {
      throw Exception('Đang chờ vị trí mới có sai số không quá 20 m.');
    }
  }

  void _position(Position p) {
    if (!acceptsPosition(p, DateTime.now(), previous: fixAt)) return;
    location = LatLng(p.latitude, p.longitude);
    accuracy = p.accuracy;
    speed = p.speed.isFinite && p.speed >= 0 ? p.speed : 0;
    gpsBearing = p.heading.isFinite && p.heading >= 0 ? p.heading % 360 : 0;
    fixAt = p.timestamp;

    if ((active || offRoute) && freshFix) _advance();
    notifyListeners();
  }

  // ─── Destination / Route ─────────────────────────────────────────
  void choose(Place p) {
    if (active || journey == JourneyState.paused) {
      error = 'Kết thúc hành trình trước khi đổi điểm đến.';
      notifyListeners();
      return;
    }
    _routeGeneration++;
    destination = p;
    route = null;
    progress = null;
    journey = JourneyState.idle;
    notifyListeners();
  }

  Future<void> plan() async {
    if (destination == null) throw Exception('Chọn điểm đến trước.');
    if (active || journey == JourneyState.paused) {
      throw Exception('Kết thúc hành trình trước khi lập tuyến mới.');
    }
    final generation = ++_routeGeneration;
    journey = JourneyState.routing;
    busy = true;
    notifyListeners();
    try {
      if (!freshFix) await locate();
      if (!freshFix)
        throw Exception('GPS chưa đủ chính xác. Ra nơi thoáng rồi thử lại.');
      final planned = demo
          ? demoRoute()
          : await routing.route(location!, destination!);
      if (generation != _routeGeneration) return;
      route = planned;
      destination = planned.destination;
      _resetProgress();
      journey = JourneyState.ready;
      await prefs.setString('route', jsonEncode(planned.toJson()));
    } finally {
      busy = false;
      if (journey == JourneyState.routing) journey = JourneyState.idle;
      notifyListeners();
    }
  }

  void _resetProgress() {
    _segment = 0;
    _hasProjection = false;
    _offRouteCount = 0;
    progress = null;
    _lastSpoken = '';
    _lastMilestone = -1;
  }

  Future<void> start() async {
    if (route == null) throw Exception('Lấy tuyến đường trước.');
    if (route!.demo != demo)
      throw Exception('Tuyến mô phỏng không dùng được với kính thật.');
    if (!demo && !link.connected)
      throw Exception('Kết nối kính trước khi bắt đầu.');
    if (!freshFix) await locate();
    if (!freshFix) throw Exception('GPS yếu hoặc cũ. Chưa thể bắt đầu.');
    if (journey != JourneyState.paused) {
      _session = const Uuid().v4();
      _seq = 0;
      _resetProgress();
      _demoIndex = 0;
    }
    journey = JourneyState.navigating;
    _revision++;
    syncPending = true;
    // Switch FLP to PRIORITY_HIGH_ACCURACY for navigation.
    await _applyGpsPriority();
    await WakelockPlus.enable();
    _advance();
    await sync();
    log('navigation_start', demo ? 'Bắt đầu mô phỏng' : 'Bắt đầu hành trình');
    notifyListeners();
    if (demo && instruction != null && !_voiceBusy) {
      await say('Bắt đầu mô phỏng. ${instruction!.text}');
    }
  }

  // ─── Hands-free voice flow ────────────────────────────────────────
  /// Last thing the voice assistant heard (shown on screen).
  String heard = '';

  /// Turn a spoken sentence into a running journey with no taps:
  /// parse → favorites/geocode → plan from GPS → start.
  Future<void> voiceGo(String spoken) async {
    if (_voiceBusy) return;
    _voiceBusy = true;
    try {
      await _handleVoice(spoken);
    } finally {
      _voiceBusy = false;
    }
  }

  bool _voiceBusy = false;

  Future<void> _handleVoice(String spoken) async {
    heard = spoken;
    error = null;
    final intent = parseIntent(spoken);
    switch (intent.command) {
      case VoiceCommand.stop:
        if (active || journey == JourneyState.paused) {
          await stop();
          await say('Đã kết thúc hành trình.');
        } else {
          await say('Hiện không có hành trình nào.');
        }
        return;
      case VoiceCommand.repeat:
        await say(instruction?.text ?? 'Chưa có chỉ dẫn nào.');
        return;
      case VoiceCommand.where:
        await say(
          destination == null
              ? 'Chưa có điểm đến.'
              : 'Đang đi đến ${destination!.name}'
                    '${progress == null ? '' : ', còn ${progress!.remaining.round()} mét'}.',
        );
        return;
      case VoiceCommand.unknown:
        await say(
          'Mình chưa nghe rõ điểm đến. Hãy nói tên hoặc địa chỉ nơi bạn muốn tới.',
        );
        return;
      case VoiceCommand.go:
        break;
    }
    final query = intent.destination!;
    try {
      if (active || journey == JourneyState.paused) await stop();
      await say('Đang tìm $query.');
      // Favorites first ("về nhà" → saved "Nhà"), then online geocode.
      final key = fold(query);
      Place? place;
      for (final f in favorites) {
        if (fold(f.name) == key) place = f;
      }
      if (place == null) {
        final found = demo ? <Place>[] : await routing.search(query);
        if (found.isEmpty && !demo) {
          throw Exception('Không tìm thấy $query. Hãy nói tên cụ thể hơn.');
        }
        place = found.isEmpty ? null : found.first;
      }
      if (place != null && !demo) choose(place);
      if (!demo && destination == null)
        throw Exception('Chưa chọn được điểm đến.');
      if (!demo) await plan();
      final r = route ?? (throw Exception('Chưa lập được tuyến đường.'));
      await start();
      await say(
        'Tuyến đến ${r.destination.name}, ${r.distance.round()} mét, '
        'khoảng ${(r.seconds / 60).ceil()} phút. Bắt đầu dẫn đường.',
      );
      log('voice_go', 'Giọng nói: "$spoken" → ${r.destination.name}');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      error = msg;
      notifyListeners();
      await say(msg, urgent: true);
    }
  }

  Future<void> pause() async {
    journey = JourneyState.paused;
    _revision++;
    syncPending = true;
    await _applyGpsPriority();
    await WakelockPlus.disable();
    await _speechOutput.cancel();
    await sync();
    notifyListeners();
  }

  Future<void> stop() async {
    _routeGeneration++;
    journey = route == null ? JourneyState.idle : JourneyState.ready;
    _revision++;
    syncPending = true;
    await _speechOutput.cancel();
    await WakelockPlus.disable();
    await _applyGpsPriority();
    await sync();
    log('navigation_stop', 'Đã kết thúc hành trình');
    notifyListeners();
  }

  Future<void> setDemo(bool value) async {
    await stop();
    await _gps?.cancel();
    _gps = null;
    link.disconnect();
    demo = value;
    await prefs.setBool('demo_mode', value);
    status = {};
    statusAt = null;
    location = null;
    fixAt = null;
    route = null;
    progress = null;
    destination = null;
    journey = JourneyState.idle;
    await prefs.remove('route');
    if (value) {
      route = demoRoute();
      destination = route!.destination;
      location = route!.points.first;
      accuracy = 3;
      fixAt = DateTime.now();
      journey = JourneyState.ready;
      notice = 'MÔ PHỎNG: vị trí, tuyến và trạng thái kính là dữ liệu giả lập.';
    } else {
      notice = null;
    }
    notifyListeners();
  }

  // ─── Navigation advance ──────────────────────────────────────────
  void _advance() {
    if (route == null || location == null || !freshFix) return;
    final p = project(
      route!,
      location!,
      previous: _hasProjection ? _segment : null,
    );
    _segment = p.segment;
    _hasProjection = true;
    progress = progressFor(route!, p, location!);

    // Compute target bearing to the step waypoint.
    if (progress!.step < route!.steps.length) {
      final step = route!.steps[progress!.step];
      final stepPt = route!.points[step.index];
      final turning = [
        'turn_left',
        'turn_right',
        'u_turn',
        'roundabout',
      ].contains(step.action);
      var next = step.index + 1;
      while (next < route!.points.length &&
          meters(stepPt, route!.points[next]) < 1) {
        next++;
      }
      targetBearing = turning && next < route!.points.length
          ? bearingTo(stepPt, route!.points[next])
          : bearingTo(location!, stepPt);
    }

    // ── State machine: off-route detection.
    if (p.offRoute > 35) {
      _offRouteCount++;
      if (_offRouteCount >= 2) journey = JourneyState.offRoute;
      if (_offRouteCount >= 4 &&
          !demo &&
          !busy &&
          DateTime.now().difference(_lastReroute).inSeconds >= 25) {
        unawaited(perform(_reroute));
      }
    } else {
      _offRouteCount = 0;
      if (journey == JourneyState.offRoute) journey = JourneyState.navigating;
    }

    // ── State machine: arrived.
    if (progress!.arrived && (active || offRoute)) {
      journey = JourneyState.arrived;
      _revision++;
      syncPending = true;
      unawaited(sync());
      unawaited(WakelockPlus.disable());
      unawaited(_applyGpsPriority());
      if (demo) unawaited(say('Đã đến điểm đến mô phỏng.'));
      log('arrived', 'Đã đến điểm đến');
    }
  }

  Future<void> _reroute() async {
    if (destination == null || location == null) return;
    _lastReroute = DateTime.now();
    busy = true;
    final generation = ++_routeGeneration;
    log('off_route', 'Lệch tuyến; đang tìm lại đường đi bộ');
    notifyListeners();
    try {
      final result = await routing.route(location!, destination!);
      if ((!active && !offRoute) || generation != _routeGeneration) return;
      route = result;
      _resetProgress();
      _revision++;
      syncPending = true;
      await prefs.setString('route', jsonEncode(result.toJson()));
      journey = JourneyState.navigating;
      _advance();
      await sync();
      notice = 'Đã cập nhật tuyến đi bộ.';
    } catch (_) {
      notice = 'Chưa tìm lại được tuyến. Tuyến lưu vẫn hiển thị; chỉ dẫn rẽ tạm dừng.';
      log('reroute_failed', notice!);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ─── Milestone TTS (30 m / 10 m / 0 m) ─────────────────────────
  void _checkMilestone() {
    if (!active || progress == null || instruction == null) return;
    if (!freshFix || _offRouteCount > 0) return;
    final dist = progress!.distanceToStep;
    int milestone = -1;
    if (dist <= 2)
      milestone = 0;
    else if (dist <= 12)
      milestone = 10;
    else if (dist <= 35)
      milestone = 30;
    if (milestone >= 0 && milestone != _lastMilestone) {
      _lastMilestone = milestone;
      final dirWord = switch (instruction!.action) {
        'turn_right' => 'rẽ phải',
        'turn_left' => 'rẽ trái',
        'arrive' => 'đến nơi',
        'roundabout' => 'vào vòng xuyến',
        'u_turn' => 'quay đầu',
        _ => 'đi thẳng',
      };
      final phrase = switch (milestone) {
        0 => '${_cap(dirWord)} ngay bây giờ.',
        10 => 'Sắp $dirWord.',
        _ => '$milestone mét nữa $dirWord.',
      };
      unawaited(say(phrase));
    }
    // Reset when user is well past the turn.
    if (dist > 45 && _lastMilestone >= 0) _lastMilestone = -1;
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ─── Settings ────────────────────────────────────────────────────
  Map<String, dynamic> get settings => {
    'warning_level': warningLevel,
    'volume': volume,
    'speech_rate': speechRate,
    'vibration': vibration,
  };

  Map<String, dynamic> get snapshot => {
    'protocol': 1,
    'session_id': _session,
    'revision': _revision,
    'state': journey.name,
    'route': route?.toJson(),
    'position': location == null ? null : xy(location!),
    'gps_valid': freshFix,
    'step_index': progress?.step ?? 0,
  };

  Future<void> sync() async {
    if (demo) {
      syncPending = false;
      return;
    }
    if (!link.connected || syncing) return;
    syncing = true;
    final sentRevision = _revision;
    try {
      await link.post('/navigation/state', snapshot);
      await link.post('/settings', settings);
      syncPending = sentRevision != _revision;
    } catch (_) {
      syncPending = true;
      notice = 'Chưa xác nhận được trạng thái trên kính. Đang thử lại.';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // ─── Tick (every 1 s) ────────────────────────────────────────────
  void _tick() {
    if (!loaded) return;
    if (demo) {
      status = {
        'yolo_fps': 18.4,
        'cpu_temp': 62,
        'battery_percent': 76,
        'camera_ok': true,
        'lidar_ok': true,
        'stm32_ok': true,
        'stm32_calibrated': true,
        'stm32_heading': 87.5,
        'stm32_pitch': -2.1,
        'stm32_roll': 0.8,
        'demo': true,
      };
      stm32Heading = 87.5;
      statusAt = DateTime.now();
      fixAt = DateTime.now();
      if (active && route != null) {
        _demoIndex = (_demoIndex + 1)
            .clamp(0, route!.points.length - 1)
            .toInt();
        location = route!.points[_demoIndex];
        accuracy = 3;
        speed = 1.2;
        _advance();
      }
    }
    if (syncPending && connected) unawaited(sync());
    if (active && !freshFix && !_gpsWarned) {
      _gpsWarned = true;
      log('gps_stale', 'GPS yếu hoặc cũ. Tạm dừng chỉ dẫn rẽ.');
    }
    if (freshFix) _gpsWarned = false;

    // Milestone TTS check.
    if (!_voiceBusy) _checkMilestone();

    // Send navigation instruction to Pi via WebSocket.
    if ((active || offRoute) && instruction != null && location != null) {
      final valid = freshFix && _offRouteCount == 0 && !syncPending;
      final m = <String, dynamic>{
        'type': 'navigation_instruction',
        'protocol': 1,
        'session_id': _session,
        'revision': _revision,
        'sequence': ++_seq,
        'route_id': route!.id,
        'valid_for_ms': 3000,
        'gps_valid': valid,
        'action': valid ? instruction!.action : 'hold',
        'text': valid ? instruction!.text : 'Tạm dừng chỉ dẫn đường',
        'street': instruction!.street,
        'distance_m': progress!.distanceToStep.round(),
        'step_index': progress!.step,
        'position': xy(location!),
        // STM32F411E-DISCO heading comparison on Pi (STM32IMUReceiverThread).
        // Pi reads current_heading from STM32 and compares with target_bearing
        // to confirm the user has turned. If stm32_ready is false, Pi skips
        // heading confirmation but continues all obstacle warnings.
        'target_bearing': double.parse(targetBearing.toStringAsFixed(1)),
        'gps_bearing': double.parse(gpsBearing.toStringAsFixed(1)),
        'stm32_heading_valid': stm32Ready,
        'current_speed_ms': double.parse(speed.toStringAsFixed(2)),
        'accuracy_m': accuracy.round(),
        'gps_timestamp': fixAt?.toUtc().toIso8601String(),
      };
      if (!demo) link.send(m);
      if (demo &&
          !_voiceBusy &&
          valid &&
          DateTime.now().isAfter(_phoneBlockedUntil)) {
        final key =
            '${progress!.step}:${progress!.distanceToStep < 20 ? 'near' : 'far'}';
        if (key != _lastSpoken) {
          _lastSpoken = key;
          unawaited(
            say(
              '${progress!.distanceToStep.round()} mét. ${instruction!.text}',
            ),
          );
        }
      }
    }
    notifyListeners();
  }

  void demoHazard() {
    if (!demo) return;
    _message({
      'type': 'hazard',
      'hazard_class': 'drop_off',
      'message': 'Mô phỏng: Dừng lại — có mép hụt phía trước.',
    });
    unawaited(say(hazard!, urgent: true));
  }

  Future<void> saveSettings() async {
    await secure.write(key: 'routing_key', value: routing.key.trim());
    await secure.write(key: 'pi_token', value: link.token.trim());
    await prefs.setString('endpoint', link.endpoint.trim());
    await prefs.setBool('allow_insecure', link.allowInsecure);
    await prefs.setString('emergency_phone', emergencyPhone);
    await prefs.setDouble('volume', volume);
    await prefs.setDouble('speech_rate', speechRate);
    await prefs.setBool('vibration', vibration);
    await prefs.setString('warning_level', warningLevel);
    await tts.setVolume(volume);
    await tts.setSpeechRate(speechRate);
    syncPending = true;
    await sync();
    notifyListeners();
  }

  Future<void> saveFavorite(String label) async {
    if (destination == null) return;
    favorites.removeWhere((p) => p.name == label);
    favorites.add(Place(label, destination!.point));
    await prefs.setString(
      'favorites',
      jsonEncode(favorites.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> removeFavorite(Place p) async {
    favorites.remove(p);
    await prefs.setString(
      'favorites',
      jsonEncode(favorites.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> clearLogs() async {
    events.clear();
    await prefs.remove('events');
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _gps?.cancel();
    link.onConnection = null;
    link.dispose();
    routing.dispose();
    _speechOutput.dispose();
    super.dispose();
  }
}
