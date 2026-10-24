import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models.dart';
import '../services/pi_link.dart';
import '../services/location_policy.dart';
import '../services/routing.dart';
import '../services/voice_intent.dart';
import '../services/speech_output.dart';

// ────────────────────────────────────────────────────────────────
//  Emergency State Machine
// ────────────────────────────────────────────────────────────────
enum EmergencyPhase {
  none,
  reconnecting,
  countdown,
  actionTaken,
  cancelled,
}

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
  AppState({PiLink? piLink, RoutingService? routingService})
    : link = piLink ?? PiLink(),
      routing = routingService ?? RoutingService();
  final RoutingService routing;
  final PiLink link;
  final tts = FlutterTts();
  late final _speechOutput = SpeechOutput(
    speak: (text) => speechReady ? tts.speak(text) : Future.value(),
    stop: tts.stop,
    onError: _reportSpeechError,
    onActivity: (playing) {
      speechPlaying = playing;
      notifyListeners();
    },
  );

  bool speechReady = false;
  bool speechPlaying = false, commandMicOpen = false, wakeEnabled = false;
  bool navigationWakeEnabled = true;
  int navigationWakeRevision = 0;
  bool get navigationVoiceActive =>
      navigationWakeEnabled &&
      (active ||
          offRoute ||
          emergencyPhase == EmergencyPhase.countdown ||
          emergencyPhase == EmergencyPhase.reconnecting);
  bool get wakeActive => wakeEnabled || navigationVoiceActive;

  void setCommandMicOpen(bool value) {
    if (commandMicOpen == value) return;
    commandMicOpen = value;
    notifyListeners();
  }

  void reportBackgroundVoiceError(String message) {
    notice = message;
    log('background_voice_error', message);
    _healthPending['background_voice'] = message;
    notifyListeners();
  }

  Future<void> setNavigationWakeEnabled(bool value) async {
    navigationWakeEnabled = value;
    navigationWakeRevision++;
    if (loaded) await prefs.setBool('navigation_wake_enabled', value);
    notifyListeners();
  }

  void Function()? requestVoiceCommand;
  int get hazardEpoch => _hazardEpoch;
  DateTime _piBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get piAudioBlocked => DateTime.now().isBefore(_piBlockedUntil);

  Future<void> cancelSpeech() =>
      speechReady ? _speechOutput.cancel() : Future<void>.value();

  Future<void> setWakeEnabled(bool value) async {
    wakeEnabled = value;
    if (loaded) await prefs.setBool('wake_enabled', value);
    notifyListeners();
  }

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
            if (voice['name'] is! String || voice['locale'] is! String) {
              continue;
            }
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
  bool _disposed = false;
  DateTime? hazardAt, statusAt, fixAt;
  String warningLevel = 'normal';
  List<EmergencyContact> emergencyContacts = [];
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

  // ─── Pi hazard priority ─────────────────────────────────────────────
  /// Fallback silence window when a Pi hazard frame carries no `hold_ms`.
  static const _defaultHazardHold = Duration(seconds: 6);

  /// Pause between the end of a Pi hazard and the phone speaking again.
  static const _hazardGap = Duration(milliseconds: 600);

  /// Hazard currently owning the audio channel (cleared by `hazard_clear`).
  String? _hazardId;

  /// Bumped on every hazard; a mic reply captured across a bump is discarded.
  int _hazardEpoch = 0;

  /// Turn guidance was cut or suppressed by a hazard and must be re-spoken.
  bool _reannounce = false;

  /// True while the phone must stay silent (Pi hazard or urgent phone alert).
  bool get phoneSpeechBlocked => DateTime.now().isBefore(_phoneBlockedUntil);

  // ─── Emergency & Loss of Connection State ───────────────────────
  EmergencyPhase emergencyPhase = EmergencyPhase.none;
  int emergencyRetryCount = 0;
  int emergencyCountdown = 10;
  Timer? _emergencyCountdownTimer;
  Timer? _reconnectLoopTimer;
  bool _emergencyDispatched = false;
  bool get emergencyDispatched => _emergencyDispatched;

  @visibleForTesting
  Future<bool> Function(Uri uri)? urlLauncherOverride;
  @visibleForTesting
  Future<void> Function(String text)? shareOverride;

  bool get onRoute => _offRouteCount == 0;
  void startupFailed(Object e) {
    error = 'Khởi tạo thất bại: $e';
    loaded = true;
    notifyListeners();
    if (!demo) unawaited(_primeLocation());
  }

  Future<void> _primeLocation() async {
    try {
      await locate();
    } catch (e) {
      if (_disposed || demo) return;
      log('gps_initial', e.toString().replaceFirst('Exception: ', ''));
    }
  }

  bool get active => journey == JourneyState.navigating;
  bool get offRoute => journey == JourneyState.offRoute;

  /// A GPS fix is "fresh" if it arrived within 8 s and has sufficient accuracy.
  bool get freshFix =>
      fixAt != null &&
      !DateTime.now().isBefore(fixAt!) &&
      DateTime.now().difference(fixAt!) <= const Duration(seconds: 8) &&
      accuracy <= _kMaxAccuracyM;

  /// A coarse current position may preview a route without trusting turns.
  bool get routePreviewFix =>
      location != null &&
      fixAt != null &&
      !DateTime.now().isBefore(fixAt!) &&
      DateTime.now().difference(fixAt!) <= const Duration(seconds: 30) &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      accuracy <= 100;

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
      emergencyContacts = EmergencyContact.decode(
        prefs.getString('emergency_contacts'),
        legacy: prefs.getString('emergency_phone') ?? '',
      );
      volume = prefs.getDouble('volume') ?? 0.8;
      speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      vibration = prefs.getBool('vibration') ?? true;
      wakeEnabled = prefs.getBool('wake_enabled') ?? false;
      navigationWakeEnabled = prefs.getBool('navigation_wake_enabled') ?? true;
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
        if (emergencyPhase == EmergencyPhase.reconnecting ||
            emergencyPhase == EmergencyPhase.countdown) {
          unawaited(resolveEmergencyReconnected());
        }
        unawaited(sync());
      } else {
        status = {};
        statusAt = null;
        syncPending = true;
        log('connection_lost', 'Mất kết nối kính; chỉ dẫn trên kính tạm dừng.');
        final isNavigatingAndNotArrived =
            (active || offRoute || journey == JourneyState.navigating || journey == JourneyState.paused) &&
            journey != JourneyState.arrived;
        if (!demo && isNavigatingAndNotArrived && emergencyPhase == EmergencyPhase.none) {
          unawaited(startLostConnectionEmergency());
        } else {
          unawaited(say('Mất kết nối kính. Chỉ dẫn trên kính đang tạm dừng.'));
        }
      }
      notifyListeners();
    };
    link.onMessage = handlePiMessage;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    loaded = true;
    notifyListeners();
    if (!demo) unawaited(_primeLocation());
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
    if (!speechReady || piAudioBlocked || commandMicOpen) return;
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
  @visibleForTesting
  void handlePiMessage(Map<String, dynamic> j) {
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
      // Pi owns spoken hazards; the phone must go silent immediately so the
      // two devices never talk over each other.
      _yieldToPiHazard(j);
    } else if (j['type'] == 'hazard_hold') {
      if (j['hazard_id'] != null && j['hazard_id'].toString() == _hazardId) {
        final until = DateTime.now().add(const Duration(seconds: 3));
        _piBlockedUntil = until;
        if (until.isAfter(_phoneBlockedUntil)) _phoneBlockedUntil = until;
      }
    } else if (j['type'] == 'hazard_clear') {
      final id = j['hazard_id']?.toString();
      if (id != null && id == _hazardId) {
        _hazardId = null;
        final resume = DateTime.now().add(_hazardGap);
        if (resume.isBefore(_phoneBlockedUntil)) _phoneBlockedUntil = resume;
        _piBlockedUntil = resume;
      }
    } else if (j['type'] == 'voice_button') {
      requestVoiceCommand?.call();
    } else if (j['type'] == 'system_error') {
      final message = '${j['message'] ?? 'Lỗi Pi'}';
      log('system_error', message);
      _healthPending['system'] =
          'Kính báo lỗi: $message. Hỗ trợ trên kính có thể gián đoạn.';
    }
    notifyListeners();
  }

  /// Cut phone speech mid-sentence and stay silent for `hold_ms` (TTL) or
  /// until the matching `hazard_clear`, whichever comes first.
  void _yieldToPiHazard(Map<String, dynamic> j) {
    final holdMs = j['hold_ms'];
    final hold = holdMs is num && holdMs.isFinite
        ? Duration(milliseconds: holdMs.toInt().clamp(1000, 10000))
        : _defaultHazardHold;
    _hazardId = j['hazard_id']?.toString();
    _hazardEpoch++;
    final until = DateTime.now().add(hold);
    if (until.isAfter(_phoneBlockedUntil)) _phoneBlockedUntil = until;
    _piBlockedUntil = until;
    // Whatever the user was told may have been cut off: repeat current
    // guidance (recomputed from the latest position) once the Pi is done.
    if (active || offRoute) _reannounce = true;
    unawaited(
      cancelSpeech().then((_) {
        if (j['hazard_id'] != null) {
          link.send({'type': 'audio_yielded', 'hazard_id': j['hazard_id']});
        }
      }),
    );
  }

  // ─── GPS — Fused Location Provider (Android only) ───────────────
  //
  // Request accurate fixes in both modes. Idle updates are less frequent and
  // do not use a foreground location notification or CPU wake lock.
  // ─────────────────────────────────────────────────────────────────
  Future<void> _applyGpsPriority() async {
    if (demo || _gps == null) return;
    await _restartGps();
  }

  Future<void> _restartGps() async {
    await _gps?.cancel();
    if (_disposed) return;
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
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 20),
      ),
    );
    _position(p);
    if (location == null) {
      throw Exception(
        'Chưa nhận được vị trí hiện tại. Kiểm tra quyền vị trí chính xác và ra nơi thoáng.',
      );
    }
  }

  void _position(Position p) {
    if (_disposed || demo) return;
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
    error = null;
    journey = JourneyState.routing;
    busy = true;
    notifyListeners();
    try {
      if (!routePreviewFix) await locate();
      if (!routePreviewFix) {
        throw Exception(
          'Chưa có vị trí đủ mới để lấy tuyến. Kiểm tra quyền vị trí chính xác và ra nơi thoáng.',
        );
      }
      if (!freshFix) {
        notice =
            'Tuyến xem trước dùng vị trí gần đúng, sai số khoảng ${accuracy.round()} m. Chờ GPS tốt hơn trước khi chỉ dẫn rẽ.';
      }
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
    _reannounce = false;
  }

  final Map<String, String> _healthPending = {};
  final Set<String> _healthFaults = {};
  bool _healthSpeaking = false;

  void _checkHealth() {
    if (!(active || offRoute || journey == JourneyState.paused)) return;
    final faults = <String, String>{
      if (!freshFix)
        'gps': 'GPS yếu hoặc dữ liệu vị trí quá cũ. Chỉ dẫn rẽ đang tạm dừng.',
      if (!connected) 'link': 'Mất kết nối kính. Không nhận được cảnh báo từ kính trên điện thoại.',
      if (connected && !statusFresh && !demo) 'status': 'Dữ liệu kính quá cũ. Chưa thể xác nhận camera và LiDAR còn hoạt động.',
      if (statusFresh && status['camera_ok'] != true) 'camera': 'Camera chưa hoạt động. Nhận diện vật cản bằng camera đang gián đoạn.',
      if (statusFresh && status['lidar_ok'] != true) 'lidar': 'LiDAR chưa hoạt động. Hỗ trợ đo khoảng cách vật cản đang gián đoạn.',
      if (statusFresh && !stm32Ready) 'imu': 'Cảm biến hướng chưa sẵn sàng. Xác nhận hướng rẽ trên kính đang gián đoạn.',
      if (statusFresh &&
          status['yolo_fps'] is num &&
          (status['yolo_fps'] as num) < 10)
        'fps': 'Nhận diện vật cản đang chậm. Cảnh báo camera có thể đến muộn.',
    };
    for (final entry in faults.entries) {
      if (_healthFaults.add(entry.key)) {
        _healthPending[entry.key] = entry.value;
        log('support_degraded', entry.value);
      }
    }
    for (final key in _healthFaults.toList()) {
      if (!faults.containsKey(key)) {
        _healthFaults.remove(key);
        _healthPending.remove(key);
      }
    }
    if (_healthPending.isEmpty ||
        phoneSpeechBlocked ||
        commandMicOpen ||
        _voiceBusy ||
        _healthSpeaking ||
        speechPlaying) {
      return;
    }
    final reports = Map<String, String>.from(_healthPending);
    _healthPending.clear();
    _healthSpeaking = true;
    final epoch = _hazardEpoch;
    unawaited(
      say(reports.values.join(' ')).whenComplete(() {
        _healthSpeaking = false;
        if (epoch != _hazardEpoch) _healthPending.addAll(reports);
      }),
    );
  }

  /// Checks both readiness and that the user actually heard both outputs.
  Future<void> preflight() async {
    final issues = <String>[
      if (!statusFresh) 'Dữ liệu kính chưa có hoặc quá cũ. Chờ dữ liệu mới.',
      if (statusFresh && status['camera_ok'] != true) 'Camera chưa hoạt động.',
      if (statusFresh && status['lidar_ok'] != true) 'LiDAR chưa hoạt động.',
      if (!speechReady) 'Giọng đọc điện thoại chưa sẵn sàng.',
      if (volume <= 0) 'Âm lượng trong app đang bằng không.',
    ];
    if (issues.isNotEmpty) {
      throw Exception('Chưa thể bắt đầu. ${issues.join(" ")}');
    }
    if (phoneSpeechBlocked) {
      throw Exception('Đang có cảnh báo. Chờ cảnh báo kết thúc rồi thử lại.');
    }
    await say('Kiểm tra âm thanh điện thoại.');
    if (!speechReady) throw Exception('Giọng đọc điện thoại bị lỗi.');
    await link.post('/audio/test', {});
    final answer = await _askYesNo(
      'Bạn có nghe rõ câu thử từ điện thoại và từ kính không? Hãy nói có hoặc không.',
      destination ?? route!.destination,
    );
    if (answer != YesNo.yes) {
      throw Exception('Chưa xác nhận âm thanh. Chưa bắt đầu dẫn đường.');
    }
    if (!link.connected ||
        !statusFresh ||
        status['camera_ok'] != true ||
        status['lidar_ok'] != true ||
        !freshFix ||
        !speechReady) {
      throw Exception(
        'Thiết bị hoặc GPS vừa gián đoạn. Kiểm tra lại trước khi bắt đầu.',
      );
    }
    if (!stm32Ready) {
      await say(
        'Cảm biến hướng chưa sẵn sàng. Xác nhận hướng rẽ trên kính tạm dừng.',
      );
    }
  }

  bool _starting = false;
  Future<void> start() async {
    if (_starting) throw Exception('Đang kiểm tra trước khi bắt đầu.');
    _starting = true;
    try {
      await _startChecked();
    } finally {
      _starting = false;
    }
  }

  Future<void> _startChecked() async {
    final generation = _routeGeneration;
    if (route == null) throw Exception('Lấy tuyến đường trước.');
    if (route!.demo != demo) {
      throw Exception('Tuyến mô phỏng không dùng được với kính thật.');
    }
    if (!demo && !link.connected) {
      throw Exception('Kết nối kính trước khi bắt đầu.');
    }
    if (!freshFix) await locate();
    if (!freshFix) {
      throw Exception(
        'Đã có vị trí nhưng chưa đủ chính xác để đọc lệnh rẽ${accuracy.isFinite ? ' (sai số khoảng ${accuracy.round()} m)' : ''}. Hãy bật vị trí chính xác và ra nơi thoáng.',
      );
    }
    if (!demo) await preflight();
    if (generation != _routeGeneration) {
      throw Exception('Hành trình đã thay đổi. Chưa bắt đầu dẫn đường.');
    }
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

  Future<void> backgroundVoiceCommand(String text) async {
    if (!navigationVoiceActive || piAudioBlocked || text.trim().isEmpty) return;
    final command = parseIntent(text).command;
    if (!{
      VoiceCommand.stop,
      VoiceCommand.repeat,
      VoiceCommand.remaining,
      VoiceCommand.where,
      VoiceCommand.cancelEmergency,
      VoiceCommand.shareLocation,
      VoiceCommand.call,
      VoiceCommand.endCall,
    }.contains(command)) {
      await say(
        'Mình chưa hiểu lệnh. Hãy nói nhắc lại, dừng dẫn đường, gọi người thân hoặc chia sẻ vị trí.',
      );
      return;
    }
    await voiceGo(text);
  }

  bool _voiceBusy = false;

  Future<void> _handleVoice(String spoken) async {
    heard = spoken;
    error = null;
    final intent = parseIntent(spoken);
    switch (intent.command) {
      case VoiceCommand.cancelEmergency:
        if (emergencyPhase == EmergencyPhase.countdown ||
            emergencyPhase == EmergencyPhase.reconnecting) {
          await cancelEmergency();
        } else {
          await say('Hiện không có chế độ khẩn cấp nào đang hoạt động.');
        }
        return;
      case VoiceCommand.shareLocation:
        await triggerShareLocation(intent.recipient);
        return;
      case VoiceCommand.call:
        await triggerCall(intent.recipient);
        return;
      case VoiceCommand.endCall:
        await say('Đã kết thúc cuộc gọi.');
        log('call_ended', 'Kết thúc cuộc gọi qua khẩu lệnh Aurelia.');
        return;
      case VoiceCommand.stop:
        if (emergencyPhase == EmergencyPhase.countdown ||
            emergencyPhase == EmergencyPhase.reconnecting) {
          await cancelEmergency();
          return;
        }
        if (active || offRoute || journey == JourneyState.paused) {
          await stop();
          await say('Đã kết thúc hành trình.');
        } else {
          await say('Hiện không có hành trình nào.');
        }
        return;
      case VoiceCommand.repeat:
        await say(
          !freshFix && (active || offRoute)
              ? 'GPS yếu hoặc cũ. Chỉ dẫn rẽ đang tạm dừng.'
              : offRoute
              ? 'Bạn đang lệch tuyến. Đang chờ tuyến mới.'
              : instruction == null
              ? 'Chưa có chỉ dẫn nào.'
              : '${spokenDistance(progress!.distanceToStep)}. ${instruction!.text}',
        );
        return;
      case VoiceCommand.remaining:
        await say(
          (active || offRoute || journey == JourneyState.paused) &&
                  progress != null
              ? 'Còn khoảng ${spokenDistance(progress!.remaining)} đến ${destination?.name ?? "điểm đến"}.'
              : 'Hiện không có hành trình nào.',
        );
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
          'Mình chưa nghe rõ. Bạn có thể nói tên địa chỉ điểm đến, gọi người thân, hoặc chia sẻ vị trí.',
        );
        return;
      case VoiceCommand.go:
        break;
    }
    final query = intent.destination!;
    try {
      if (active || offRoute || journey == JourneyState.paused) {
        await say(
          'Bạn đang có hành trình. Hãy nói dừng dẫn đường trước khi chọn điểm đến mới.',
        );
        return;
      }
      await say('Đang tìm $query.');
      final candidates = await _candidatesFor(query);
      // Never start on the first search hit: same-name places are common
      // and speech recognition mishears. Require an explicit "có".
      final place = await _confirmDestination(candidates);
      if (place == null) {
        log(
          'voice_unconfirmed',
          'Giọng nói: "$spoken" → chưa xác nhận điểm đến',
        );
        return;
      }
      if (!demo) choose(place);
      if (!demo && destination == null) {
        throw Exception('Chưa chọn được điểm đến.');
      }
      if (!demo) await plan();
      final r = route ?? (throw Exception('Chưa lập được tuyến đường.'));
      if (!demo && !link.connected) {
        await say(
          'Đã lấy tuyến đi bộ đến ${r.destination.name}, ${r.distance.round()} mét, khoảng ${(r.seconds / 60).ceil()} phút. Bạn có thể xem tuyến. Kết nối kính khi muốn bắt đầu hành trình với kính.',
        );
        log('voice_route_preview', 'Đã lấy tuyến đi bộ, chưa bắt đầu với kính');
        return;
      }
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

  // ─── Spoken destination confirmation ──────────────────────────
  /// Set by the UI: opens the mic once and returns the final transcript, or
  /// `null` on silence/error. Tests replace it with a scripted reply.
  Future<String?> Function()? listenReply;

  /// Set by the UI: closes a mic opened by [listenReply] (on a tapped answer).
  void Function()? cancelReply;

  /// Candidate currently awaiting yes/no, and the question that was read.
  Place? pendingConfirm;
  String? confirmPrompt;
  Completer<YesNo>? _confirmTap;

  /// Answer the pending confirmation from the on-screen buttons.
  void answerConfirm(YesNo answer) {
    final tap = _confirmTap;
    if (tap == null || tap.isCompleted) return;
    tap.complete(answer);
    if (speechReady) unawaited(_speechOutput.cancel());
  }

  /// Max candidates offered one by one before asking for a better name.
  static const _maxCandidates = 3;

  Future<List<Place>> _candidatesFor(String query) async {
    // Favorites first ("về nhà" → saved "Nhà"), then online geocode.
    final key = fold(query);
    Place? favorite;
    for (final f in favorites) {
      if (fold(f.name) == key) favorite = f;
    }
    if (favorite != null) return [favorite];
    if (demo) return [(route ?? demoRoute()).destination];
    final found = await routing.search(query, near: location);
    if (found.isEmpty) {
      throw Exception('Không tìm thấy $query. Hãy nói tên cụ thể hơn.');
    }
    return found;
  }

  /// Offer candidates one at a time; return the one the user said yes to.
  Future<Place?> _confirmDestination(List<Place> found) async {
    final options = found.take(_maxCandidates).toList();
    for (var i = 0; i < options.length; i++) {
      final p = options[i];
      final sameName = found.where((o) => fold(o.name) == fold(p.name)).length;
      final question = confirmQuestion(
        p.name,
        address: p.address,
        distanceM: location == null ? null : meters(location!, p.point),
        sameName: i == 0 ? sameName : 1,
        alternative: i > 0,
      );
      final answer = await _askYesNo(question, p);
      if (answer == YesNo.yes) return p;
      if (answer == YesNo.cancel) {
        await say('Đã hủy. Chạm đúp màn hình để nói lại điểm đến.');
        return null;
      }
      if (answer == YesNo.unclear) {
        await say(
          'Mình chưa nghe được câu trả lời nên chưa bắt đầu dẫn đường. '
          'Chạm đúp màn hình để nói lại.',
        );
        return null;
      }
    }
    await say(
      'Mình chưa tìm đúng nơi bạn muốn. '
      'Hãy nói tên cụ thể hơn, kèm tên đường hoặc quận.',
    );
    return null;
  }

  Future<YesNo> _askYesNo(String question, Place place) async {
    pendingConfirm = place;
    confirmPrompt = question;
    notifyListeners();
    try {
      await _waitForPiSilence();
      if (phoneSpeechBlocked) return YesNo.unclear;
      final epoch = _hazardEpoch;
      final tap = _confirmTap = Completer<YesNo>();
      await say(question);
      final reply = await _awaitAnswer(tap);
      if (reply.text != null) heard = reply.text!;
      // Interrupted speech is never consent. Leave the next attempt to the
      // user; no repeated spoken invitation after silence or unclear speech.
      if (reply.byVoice && epoch != _hazardEpoch) return YesNo.unclear;
      return reply.answer;
    } finally {
      pendingConfirm = null;
      confirmPrompt = null;
      _confirmTap = null;
      notifyListeners();
    }
  }

  Future<({YesNo answer, bool byVoice, String? text})> _awaitAnswer(
    Completer<YesNo> tap,
  ) async {
    if (tap.isCompleted) {
      return (answer: await tap.future, byVoice: false, text: null);
    }
    final listener = listenReply;
    final tapped = tap.future.then(
      (a) => (answer: a, byVoice: false, text: null as String?),
    );
    final voice = listener == null
        // No recognizer: wait for the on-screen buttons only.
        ? tap.future
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () => YesNo.unclear,
              )
              .then((a) => (answer: a, byVoice: false, text: null as String?))
        : listener().then(
            (t) => (
              answer: t == null ? YesNo.unclear : parseYesNo(t),
              byVoice: true,
              text: t,
            ),
            onError: (Object _) =>
                (answer: YesNo.unclear, byVoice: true, text: null as String?),
          );
    final result = await Future.any([tapped, voice]);
    if (!result.byVoice) cancelReply?.call();
    return result;
  }

  Future<void> _waitForPiSilence() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (phoneSpeechBlocked && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
    if (_confirmTap != null && !_confirmTap!.isCompleted) {
      _confirmTap!.complete(YesNo.cancel);
      cancelReply?.call();
    }
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
    if (_disposed) return;
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
  static int _milestoneFor(double dist) => dist <= 2
      ? 0
      : dist <= 12
      ? 10
      : dist <= 35
      ? 30
      : -1;

  static String _dirWord(String action) => switch (action) {
    'turn_right' => 'rẽ phải',
    'turn_left' => 'rẽ trái',
    'arrive' => 'đến nơi',
    'roundabout' => 'vào vòng xuyến',
    'u_turn' => 'quay đầu',
    _ => 'đi thẳng',
  };

  void _checkMilestone() {
    if (!active || progress == null || instruction == null) return;
    if (!freshFix || _offRouteCount > 0) return;
    final dist = progress!.distanceToStep;
    final milestone = _milestoneFor(dist);
    if (milestone >= 0 && milestone != _lastMilestone) {
      if (phoneSpeechBlocked) {
        // The Pi is reading a hazard. Do NOT mark this milestone as spoken,
        // otherwise the turn is silently lost; re-announce when it is done.
        _reannounce = true;
      } else {
        _lastMilestone = milestone;
        final dirWord = _dirWord(instruction!.action);
        final phrase = switch (milestone) {
          0 => '${_cap(dirWord)} ngay bây giờ.',
          10 => 'Sắp $dirWord.',
          _ => '$milestone mét nữa $dirWord.',
        };
        unawaited(say(phrase));
      }
    }
    // Reset when user is well past the turn.
    if (dist > 45 && _lastMilestone >= 0) _lastMilestone = -1;
  }

  /// After a hazard, say where the next turn is *now* — never replay the
  /// sentence that was cut off, it may already be wrong.
  void _reannounceGuidance() {
    _reannounce = false;
    if (!active || progress == null || instruction == null) return;
    if (!freshFix || _offRouteCount > 0) return;
    final dist = progress!.distanceToStep;
    if (dist > 45) return; // Nothing imminent; the next milestone will speak.
    _lastMilestone = _milestoneFor(dist);
    final dirWord = _dirWord(instruction!.action);
    final d = dist.round();
    unawaited(
      say(d <= 2 ? '${_cap(dirWord)} ngay bây giờ.' : 'Còn $d mét, $dirWord.'),
    );
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

    // Milestone TTS check. A hazard-interrupted turn is re-spoken first.
    _checkHealth();
    if (!_voiceBusy && !commandMicOpen) {
      if (_reannounce && !phoneSpeechBlocked) {
        _reannounceGuidance();
      } else {
        _checkMilestone();
      }
    }

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
          !commandMicOpen &&
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

  /// Run one 1-second navigation tick synchronously (tests only).
  @visibleForTesting
  void debugTick() => _tick();

  void demoHazard() {
    if (!demo) return;
    handlePiMessage({
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
    emergencyContacts = emergencyContacts
        .where((c) => c.phone.trim().isNotEmpty)
        .map((c) => EmergencyContact(c.name.trim(), c.phone.trim()))
        .toList();
    await prefs.setString(
      'emergency_contacts',
      EmergencyContact.encode(emergencyContacts),
    );
    await prefs.remove('emergency_phone');
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

  // ─── Emergency & Guardian Automation ───────────────────────
  EmergencyContact? matchEmergencyContact(String? query) {
    if (query == null || query.trim().isEmpty) {
      return emergencyContacts.isNotEmpty ? emergencyContacts.first : null;
    }
    final q = query.trim();
    // 1. Phone number match
    final digitsOnly = q.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isNotEmpty) {
      for (final c in emergencyContacts) {
        final cDigits = c.phone.replaceAll(RegExp(r'\D'), '');
        if (cDigits == digitsOnly ||
            (cDigits.isNotEmpty && digitsOnly.endsWith(cDigits)) ||
            (digitsOnly.length >= 7 && cDigits.endsWith(digitsOnly))) {
          return c;
        }
      }
    }
    // 2. Name matching with fold()
    final foldedQ = fold(q);
    for (final c in emergencyContacts) {
      final foldedName = fold(c.name);
      if (foldedName == foldedQ ||
          foldedName.contains(foldedQ) ||
          foldedQ.contains(foldedName)) {
        return c;
      }
    }
    return null;
  }

  Future<void> triggerCall(String? recipientName) async {
    final query = recipientName?.trim();
    String? phoneToCall;
    String displayName = '';

    final digitsOnly = query?.replaceAll(RegExp(r'\D'), '') ?? '';
    final isEmergencyNumber = query != null &&
        (query.startsWith(RegExp(r'11[345]')) ||
            query.startsWith('911') ||
            (digitsOnly.length >= 3 &&
                digitsOnly.length <= 5 &&
                !query.contains(RegExp(r'[a-zA-Zà-ỹÀ-Ỹ]'))) ||
            (digitsOnly.length >= 9 && !query.contains(RegExp(r'[a-zA-Zà-ỹÀ-Ỹ]'))));

    if (isEmergencyNumber) {
      phoneToCall = query;
      displayName = query;
    } else {
      final match = matchEmergencyContact(query);
      if (match != null) {
        phoneToCall = match.phone;
        displayName = match.name.isNotEmpty ? match.name : match.phone;
      } else if (query != null && query.isNotEmpty) {
        await say(
          'Không tìm thấy người thân $query trong danh sách khẩn cấp. Bạn có thể thêm số trong phần Cài đặt.',
        );
        return;
      } else {
        await say('Chưa có số người thân nào được cài đặt trong danh sách khẩn cấp.');
        return;
      }
    }

    if (phoneToCall.isEmpty) {
      await say('Số điện thoại không hợp lệ.');
      return;
    }

    await say('Đang gọi cho $displayName.');
    final uri = Uri.parse('tel:$phoneToCall');
    try {
      if (urlLauncherOverride != null) {
        await urlLauncherOverride!(uri);
      } else {
        await launchUrl(uri);
      }
      log('call_initiated', 'Gọi điện tới $displayName ($phoneToCall)');
    } catch (e) {
      log('call_error', 'Lỗi khi gọi tới $displayName: $e');
      await say('Không thể thực hiện cuộc gọi. Vui lòng kiểm tra lại quyền điện thoại.');
    }
  }

  Future<void> triggerShareLocation(String? recipientName) async {
    if (location == null) {
      await say('Chưa xác định được vị trí GPS hiện tại.');
      return;
    }
    final lat = location!.latitude.toStringAsFixed(6);
    final lng = location!.longitude.toStringAsFixed(6);
    final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
    final shareText = 'Vị trí hiện tại của tôi: $mapsUrl';

    final query = recipientName?.trim();
    final isShareAll = query == null ||
        query.isEmpty ||
        fold(query).contains('tat ca') ||
        fold(query).contains('moi nguoi') ||
        fold(query).contains('toan bo');

    if (!isShareAll) {
      final contact = matchEmergencyContact(query);
      if (contact != null) {
        await say('Đang gửi vị trí cho ${contact.name.isNotEmpty ? contact.name : contact.phone}.');
        final smsUri = Uri(
          scheme: 'sms',
          path: contact.phone,
          queryParameters: {'body': shareText},
        );
        try {
          if (urlLauncherOverride != null) {
            await urlLauncherOverride!(smsUri);
          } else {
            await launchUrl(smsUri);
          }
          log('share_location_sms', 'Gửi vị trí SMS tới ${contact.name} (${contact.phone})');
          return;
        } catch (e) {
          log('share_location_error', 'Lỗi gửi SMS tới ${contact.name}: $e');
        }
      }
    }

    await say(isShareAll
        ? 'Đang chia sẻ vị trí hiện tại tới người thân.'
        : 'Đang mở chia sẻ vị trí cho $query.');

    try {
      if (shareOverride != null) {
        await shareOverride!(shareText);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: shareText,
            subject: 'Vị trí của tôi - SecondSight',
          ),
        );
      }
      log('share_location', 'Chia sẻ vị trí $lat, $lng');
    } catch (e) {
      log('share_location_error', 'Lỗi chia sẻ vị trí: $e');
      await say('Không thể chia sẻ vị trí. Vui lòng thử lại.');
    }
  }

  Future<void> startLostConnectionEmergency({bool simulated = false}) async {
    if (emergencyPhase == EmergencyPhase.reconnecting ||
        emergencyPhase == EmergencyPhase.countdown) {
      return;
    }
    emergencyPhase = EmergencyPhase.reconnecting;
    emergencyRetryCount = 0;
    _emergencyDispatched = false;
    notifyListeners();

    log('emergency_started', 'Mất kết nối kính trong khi đang dẫn đường. Bắt đầu thử kết nối lại.');
    await say(
      'Đã mất kết nối với kính. Xin hãy đứng yên tại chỗ để nhanh chóng thiết lập lại kết nối.',
      urgent: true,
    );

    _reconnectLoopTimer?.cancel();
    _reconnectLoopTimer = Timer.periodic(const Duration(milliseconds: 2500), (t) async {
      if (_disposed || emergencyPhase != EmergencyPhase.reconnecting) {
        t.cancel();
        return;
      }
      if (!simulated && link.connected) {
        t.cancel();
        await resolveEmergencyReconnected();
        return;
      }
      emergencyRetryCount++;
      notifyListeners();

      if (emergencyRetryCount < 5) {
        if (!simulated && link.token.trim().isNotEmpty && !link.connected) {
          unawaited(link.connect().catchError((_) {}));
        }
      } else {
        t.cancel();
        await _startEmergencyCountdown();
      }
    });
  }

  Future<void> resolveEmergencyReconnected() async {
    _reconnectLoopTimer?.cancel();
    _emergencyCountdownTimer?.cancel();
    emergencyPhase = EmergencyPhase.none;
    emergencyRetryCount = 0;
    notifyListeners();
    log('emergency_reconnected', 'Đã kết nối lại kính thành công. Tiếp tục dẫn đường.');
    await say('Đã kết nối lại với kính. Bạn có thể tiếp tục hành trình.');
  }

  Future<void> _startEmergencyCountdown() async {
    emergencyPhase = EmergencyPhase.countdown;
    emergencyCountdown = 10;
    notifyListeners();

    if (vibration) {
      HapticFeedback.heavyImpact();
    }
    log('emergency_countdown', 'Thử kết nối 5 lần thất bại. Đếm ngược 10 giây khẩn cấp.');
    await say(
      'Kính đã hoàn toàn mất kết nối. Xin bạn hãy ở yên chỗ đang đứng, tìm một vị trí an toàn để đứng. '
      'Hệ thống sẽ tự động gửi vị trí khẩn cấp và gọi người giám hộ sau 10 giây. Hãy nói HỦY nếu bạn an toàn.',
      urgent: true,
    );

    _emergencyCountdownTimer?.cancel();
    _emergencyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_disposed || emergencyPhase != EmergencyPhase.countdown) {
        t.cancel();
        return;
      }
      emergencyCountdown--;
      if (emergencyCountdown > 0) {
        if (vibration && emergencyCountdown <= 3) {
          HapticFeedback.mediumImpact();
        }
        notifyListeners();
      } else {
        t.cancel();
        await _executeEmergencyAutomatedActions();
      }
    });
  }

  Future<void> cancelEmergency() async {
    _reconnectLoopTimer?.cancel();
    _emergencyCountdownTimer?.cancel();
    emergencyPhase = EmergencyPhase.cancelled;
    notifyListeners();
    log('emergency_cancelled', 'Người dùng đã hủy chế độ khẩn cấp.');
    await say('Đã hủy chế độ khẩn cấp.');
  }

  Future<void> _executeEmergencyAutomatedActions() async {
    emergencyPhase = EmergencyPhase.actionTaken;
    _emergencyDispatched = true;
    notifyListeners();

    log('emergency_automated_actions', 'Hết thời gian đếm ngược. Tự động gửi SMS vị trí và gọi người giám hộ ưu tiên số 1.');

    final lat = location?.latitude.toStringAsFixed(6);
    final lng = location?.longitude.toStringAsFixed(6);
    final mapLink = lat != null ? 'https://maps.google.com/?q=$lat,$lng' : 'GPS chưa xác định';
    final sosText = 'SOS KHẨN CẤP! Thiết bị SecondSight của tôi mất kết nối khi đang di chuyển. Vị trí hiện tại: $mapLink';

    // 1. Send SMS to all ICE contacts
    if (emergencyContacts.isNotEmpty) {
      final phoneNumbers = emergencyContacts
          .map((c) => c.phone.trim())
          .where((p) => p.isNotEmpty)
          .join(',');
      if (phoneNumbers.isNotEmpty) {
        final smsUri = Uri(
          scheme: 'sms',
          path: phoneNumbers,
          queryParameters: {'body': sosText},
        );
        try {
          if (urlLauncherOverride != null) {
            await urlLauncherOverride!(smsUri);
          } else {
            await launchUrl(smsUri);
          }
          log('emergency_sms_sent', 'Đã bắn tin nhắn SMS khẩn cấp tới $phoneNumbers');
        } catch (e) {
          log('emergency_sms_error', 'Lỗi gửi SMS khẩn cấp: $e');
          try {
            if (shareOverride != null) {
              await shareOverride!(sosText);
            }
          } catch (_) {}
        }
      }
    } else {
      log('emergency_warning', 'Danh sách người giám hộ ICE trống, không thể gửi SMS.');
    }

    // 2. Call Primary Guardian (Priority #1)
    final primary = emergencyContacts.isNotEmpty ? emergencyContacts.first : null;
    if (primary != null && primary.phone.trim().isNotEmpty) {
      await say(
        'Đã gửi vị trí khẩn cấp. Đang tự động gọi cho người giám hộ ${primary.name.isNotEmpty ? primary.name : "số 1"}.',
        urgent: true,
      );
      final telUri = Uri.parse('tel:${primary.phone.trim()}');
      try {
        if (urlLauncherOverride != null) {
          await urlLauncherOverride!(telUri);
        } else {
          await launchUrl(telUri);
        }
        log('emergency_call_primary', 'Tự động quay số cho ${primary.name} (${primary.phone})');
      } catch (e) {
        log('emergency_call_error', 'Lỗi quay số cho người giám hộ: $e');
        await say('Không thể tự động quay số. Xin hãy gọi khẩn cấp bằng tay.');
      }
    } else {
      await say('Đã gửi vị trí khẩn cấp. Không có số người giám hộ ưu tiên để gọi.');
    }
  }

  void dismissEmergencyBanner() {
    emergencyPhase = EmergencyPhase.none;
    emergencyRetryCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _reconnectLoopTimer?.cancel();
    _emergencyCountdownTimer?.cancel();
    _gps?.cancel();
    link.onConnection = null;
    link.dispose();
    routing.dispose();
    _speechOutput.dispose();
    super.dispose();
  }
}
