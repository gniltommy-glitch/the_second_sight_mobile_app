import 'widgets/consumer_components.dart';
import 'widgets/orientation_hud.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../services/pairing_config.dart';
import 'pairing_scanner.dart';
import '../main.dart';
import 'widgets/animated_banner.dart';
import 'widgets/compass_widget.dart';
import 'widgets/glass_card.dart';
import 'widgets/hud_metric.dart';
import 'widgets/nav_instruction.dart';

class Home extends StatefulWidget {
  final AppState state;
  final SpeechToText? recognizer;
  final int initialTab;
  const Home({
    super.key,
    required this.state,
    this.recognizer,
    this.initialTab = 0,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late int tab = widget.initialTab;
  final search = TextEditingController();
  final map = MapController();
  late final speech = widget.recognizer ?? SpeechToText();
  List<Place> results = [];
  bool searching = false, listening = false;
  int searchVersion = 0;
  late final AnimationController _tabCtrl;

  static const _hardwareVoice = MethodChannel('secondsight/voice');
  bool _wakeListening = false, _recognizerReady = false;
  Timer? _wakeRetry;
  JourneyState? _lastJourney;
  int _micHazardEpoch = 0;
  (bool, bool, bool, bool)? _nativeVoiceConfiguration;
  bool _nativeVoiceFailed = false, _foregroundWakeFailed = false;
  int _wakeSettingRevision = 0;
  bool _didAutoMoveMap = false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _syncNativeVoice() {
    if (!_android) return;
    final configuration = (
      s.wakeActive &&
          (_foreground || s.navigationVoiceActive) &&
          !_nativeVoiceFailed,
      s.speechPlaying ||
          s.phoneSpeechBlocked ||
          (_foreground && (s.commandMicOpen || _handlingVoice || _openingMic)),
      s.piAudioBlocked,
      s.navigationVoiceActive,
    );
    if (configuration == _nativeVoiceConfiguration) return;
    _nativeVoiceConfiguration = configuration;
    unawaited(
      _hardwareVoice
          .invokeMethod('configureNavigation', {
            'enabled': configuration.$1,
            'blocked': configuration.$2,
            'interrupt': configuration.$3,
            'allowBackground': configuration.$4,
          })
          .catchError((Object error) {
            if (!mounted || !configuration.$1) return;
            _nativeVoiceFailed = true;
            s.reportBackgroundVoiceError(
              'Chưa bật được mic nền. Mở app, kiểm tra quyền micro và thử lại.',
            );
          }),
    );
  }

  Future<void> _nativeVoiceEvent(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'activate':
        _hardwareCommand();
      case 'backgroundListening':
        if (!_foreground) s.setCommandMicOpen(call.arguments == true);
      case 'backgroundMuted':
        await s.setWakeEnabled(false);
        await s.setNavigationWakeEnabled(false);
      case 'backgroundError':
        _nativeVoiceFailed = true;
        s.reportBackgroundVoiceError('${call.arguments}');
      case 'backgroundWake':
        if (s.piAudioBlocked) return;
        if (_foreground) {
          if (s.wakeActive) await listen();
          return;
        }
        if (!s.navigationVoiceActive) return;
        final epoch = s.hazardEpoch;
        await s.say(
          'Aurelia đang nghe. Mời bạn nói nhắc lại, dừng dẫn đường hoặc còn bao xa.',
        );
        if (!mounted ||
            _foreground ||
            !s.navigationVoiceActive ||
            s.piAudioBlocked ||
            epoch != s.hazardEpoch) {
          return;
        }
        await _hardwareVoice.invokeMethod('commandReady', {
          'ticket': call.arguments,
        });
      case 'backgroundCommand':
        s.setCommandMicOpen(false);
        try {
          if (!_foreground) await s.backgroundVoiceCommand('${call.arguments}');
        } finally {
          await _hardwareVoice.invokeMethod('commandFinished');
        }
    }
  }

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_onNavigationChanged);
    s.listenReply = _listenOnce;
    s.cancelReply = _cancelReply;
    s.requestVoiceCommand = _hardwareCommand;
    _lastJourney = s.journey;
    _hardwareVoice.setMethodCallHandler(_nativeVoiceEvent);
    _tabCtrl = AnimationController(vsync: this, duration: 200.ms);
    // Blind users can't find buttons: greet and open the mic on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !s.active &&
          !s.offRoute &&
          s.journey != JourneyState.paused) {
        listen(greet: true);
      }
      _syncNativeVoice();
      _scheduleWake();
      _autoLocate();
    });
  }

  @override
  void dispose() {
    s.removeListener(_onNavigationChanged);
    s.requestVoiceCommand = null;
    if (_android) {
      unawaited(
        _hardwareVoice
            .invokeMethod('configureNavigation', {'enabled': false})
            .catchError((Object _) {}),
      );
    }
    _hardwareVoice.setMethodCallHandler(null);
    _wakeRetry?.cancel();
    s.commandMicOpen = false;
    if (s.listenReply == _listenOnce) s.listenReply = null;
    if (s.cancelReply == _cancelReply) s.cancelReply = null;
    _finishReply(null);
    WidgetsBinding.instance.removeObserver(this);
    _recognitionEnd?.cancel();
    _listenSession++;
    _completeRecognition = null;
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

  void _hardwareCommand() {
    if (!mounted) return;
    if (_foreground) {
      unawaited(listen());
    } else if (s.navigationVoiceActive && _android) {
      unawaited(_hardwareVoice.invokeMethod('activateCommand'));
    }
  }

  void _finishNativeCommand() {
    if (!_android) return;
    _syncNativeVoice();
    unawaited(
      _hardwareVoice.invokeMethod('commandFinished').catchError((Object _) {}),
    );
  }

  void _closeMic() {
    _listenSession++;
    _completeRecognition = null;
    _recognitionEnd?.cancel();
    speech.cancel();
    s.commandMicOpen = false;
    _syncNativeVoice();
    _wakeListening = false;
    _recognizerReady = false;
    _finishReply(null);
    _finishNativeCommand();
    if (mounted) setState(() => listening = false);
  }

  Future<void> _autoLocate() async {
    if (s.demo) return;
    if (s.location != null && !_didAutoMoveMap) {
      _didAutoMoveMap = true;
      try {
        map.move(s.location!, 17);
      } catch (_) {}
    }
    if (!s.freshFix) {
      try {
        await s.perform(() async {
          await s.locate();
          if (mounted && s.location != null && !_didAutoMoveMap) {
            _didAutoMoveMap = true;
            try {
              map.move(s.location!, 17);
            } catch (_) {}
          }
        });
      } catch (_) {}
    }
  }

  void _onNavigationChanged() {
    if (s.location != null && !_didAutoMoveMap) {
      _didAutoMoveMap = true;
      try {
        map.move(s.location!, 17);
      } catch (_) {}
    }
    if (_wakeSettingRevision != s.navigationWakeRevision) {
      _wakeSettingRevision = s.navigationWakeRevision;
      _nativeVoiceFailed = false;
      _foregroundWakeFailed = false;
      _nativeVoiceConfiguration = null;
    }
    final changed = _lastJourney != s.journey;
    _lastJourney = s.journey;
    // A new journey closes an old destination-entry mic. Ordinary GPS ticks
    // must not close a deliberately opened command mic.
    if (listening &&
        ((changed && !_handlingVoice) ||
            s.hazardEpoch != _micHazardEpoch ||
            (_wakeListening &&
                (s.speechPlaying || s.phoneSpeechBlocked || !s.wakeActive)))) {
      _closeMic();
    }
    _syncNativeVoice();
    _scheduleWake();
  }

  void _scheduleWake() {
    // Android owns a continuous local wake stream, without recognizer tones.
    if (_android) return;
    if (_wakeRetry?.isActive == true ||
        !mounted ||
        !_foreground ||
        !s.wakeActive ||
        _foregroundWakeFailed ||
        listening ||
        _openingMic ||
        _handlingVoice ||
        s.speechPlaying ||
        s.phoneSpeechBlocked ||
        s.pendingConfirm != null) {
      return;
    }
    _wakeRetry = Timer(const Duration(seconds: 2), () {
      if (mounted &&
          _foreground &&
          s.wakeActive &&
          !listening &&
          !s.speechPlaying &&
          !s.phoneSpeechBlocked &&
          s.pendingConfirm == null) {
        listen(wake: true);
      }
    });
  }

  bool _speechReady = false;
  bool _openingMic = false, _handlingVoice = false;
  bool _foreground = true;
  int _listenSession = 0;
  Timer? _recognitionEnd;
  void Function()? _completeRecognition;
  String partial = '';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _recognitionEnd?.cancel();
      _wakeRetry?.cancel();
      _closeMic();
    } else {
      _nativeVoiceFailed = false;
      _foregroundWakeFailed = false;
      _nativeVoiceConfiguration = null;
      _scheduleWake();
    }
    _syncNativeVoice();
  }

  // ─── One-shot yes/no reply (destination confirmation) ─────────────
  Completer<String?>? _reply;

  void _finishReply(String? text) {
    final reply = _reply;
    _reply = null;
    if (reply != null && !reply.isCompleted) reply.complete(text);
  }

  /// Open the mic for a short answer. Runs inside a voice command, so
  /// [_handlingVoice] is already true and auto-listen stays off.
  Future<String?> _listenOnce() async {
    if (!mounted || !_foreground) return null;
    speech.statusListener = _recognitionStatus;
    speech.errorListener = _recognitionError;
    if (!_speechReady) {
      _speechReady = await speech.initialize(
        onStatus: _recognitionStatus,
        onError: _recognitionError,
      );
    }
    if (!mounted || !_foreground || s.piAudioBlocked) return null;
    if (!_speechReady) {
      final buttons = _reply = Completer<String?>();
      final reply = await buttons.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
      if (identical(_reply, buttons)) _reply = null;
      return reply;
    }
    _finishReply(null);
    final done = _reply = Completer<String?>();
    final session = ++_listenSession;
    var lastWords = '';
    _completeRecognition = () {
      if (session != _listenSession || !identical(_reply, done)) return;
      _completeRecognition = null;
      _recognitionEnd?.cancel();
      _finishReply(lastWords.isEmpty ? null : lastWords);
    };
    _micHazardEpoch = s.hazardEpoch;
    s.commandMicOpen = true;
    HapticFeedback.mediumImpact();
    setState(() {
      listening = true;
      partial = '';
    });
    try {
      await speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'vi_VN',
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 2),
        ),
        onResult: (r) {
          if (!mounted || session != _listenSession || done.isCompleted) {
            return;
          }
          setState(() => partial = r.recognizedWords);
          if (r.recognizedWords.trim().isNotEmpty) {
            lastWords = r.recognizedWords.trim();
          }
          if (r.finalResult) _completeRecognition?.call();
        },
      );
    } catch (_) {
      if (identical(_reply, done)) _finishReply(null);
    }
    final text = await done.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => lastWords.isEmpty ? null : lastWords,
    );
    if (identical(_reply, done)) _reply = null;
    if (session == _listenSession) {
      _completeRecognition = null;
      _recognitionEnd?.cancel();
      await speech.cancel();
      s.commandMicOpen = false;
      if (mounted) setState(() => listening = false);
    }
    return text;
  }

  /// Close the reply mic because the answer came from a button.
  void _cancelReply() {
    if (_reply == null) return;
    _closeMic();
  }

  void _recognitionStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      setState(() => _recognizerReady = true);
      return;
    }
    if (status == 'done' || status == 'notListening') {
      setState(() => _recognizerReady = false);
      // Some Android engines end the mic before publishing the final text.
      // Keep this session's last partial and allow that final result to arrive.
      if (_completeRecognition != null) {
        _recognitionEnd?.cancel();
        _recognitionEnd = Timer(const Duration(milliseconds: 2500), () {
          _completeRecognition?.call();
        });
      }
    }
  }

  void _recognitionError(dynamic e) {
    if (!mounted) return;
    s.commandMicOpen = false;
    setState(() => listening = false);
    if (e.errorMsg == 'error_no_match' ||
        e.errorMsg == 'error_speech_timeout') {
      _completeRecognition?.call();
    } else {
      _completeRecognition = null;
      _finishReply(null);
      _recognitionEnd?.cancel();
      _wakeRetry?.cancel();
      // Permission/service failures must not produce endless wake retries.
      _foregroundWakeFailed = true;
      unawaited(s.setWakeEnabled(false));
      s.error = 'Aurelia không nghe được. Kiểm tra quyền micro, nhận dạng giọng nói và kết nối mạng.';
      unawaited(s.say(s.error!, urgent: true));
    }
  }

  /// Speak → search → route from GPS → start, without another tap.
  Future<void> listen({bool greet = false, bool wake = false}) async {
    if (_openingMic || _handlingVoice || !_foreground) return;
    _recognitionEnd?.cancel();
    _wakeRetry?.cancel();
    if (s.piAudioBlocked) {
      s.notice = 'Đang có cảnh báo từ kính. Chờ cảnh báo kết thúc rồi gọi mic.';
      setState(() {});
      return;
    }
    if (listening && _wakeListening && !wake) _closeMic();
    if (listening) {
      _listenSession++;
      await speech.cancel();
      s.commandMicOpen = false;
      if (mounted) setState(() => listening = false);
      return;
    }
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
      speech.statusListener = _recognitionStatus;
      speech.errorListener = _recognitionError;
      if (!_speechReady) {
        _speechReady = await speech.initialize(
          onStatus: _recognitionStatus,
          onError: _recognitionError,
        );
      }
      if (!_speechReady) {
        _foregroundWakeFailed = true;
        await s.setWakeEnabled(false);
        s.error =
            'Không bật được nhận dạng giọng nói. Kiểm tra quyền micro '
            'và quyền nhận dạng giọng nói trong cài đặt điện thoại.';
        await s.say(s.error!, urgent: true);
        return;
      }
      if (!mounted || !_foreground || s.piAudioBlocked) return;
      if (!wake && !greet) {
        await s.cancelSpeech();
        await s.say(
          s.active || s.offRoute || s.journey == JourneyState.paused
              ? 'Mời bạn nói lệnh: nhắc lại, dừng dẫn đường, hoặc còn bao xa.'
              : 'Aurelia đang nghe. Mời bạn nói điểm đến.',
        );
      }
      if (!mounted ||
          !_foreground ||
          s.piAudioBlocked ||
          (wake && s.speechPlaying)) {
        return;
      }
      final session = ++_listenSession;
      _micHazardEpoch = s.hazardEpoch;
      _wakeListening = wake;
      _recognizerReady = false;
      s.commandMicOpen = !wake;
      _syncNativeVoice();
      var delivered = false;
      HapticFeedback.mediumImpact();
      setState(() {
        listening = true;
        partial = '';
      });
      var lastWords = '';
      Future<void> deliver() async {
        if (!mounted ||
            !_foreground ||
            session != _listenSession ||
            delivered) {
          return;
        }
        delivered = true;
        _completeRecognition = null;
        _recognitionEnd?.cancel();
        _handlingVoice = true;
        setState(() => listening = false);
        try {
          await speech.cancel();
          if (!mounted || !_foreground || session != _listenSession) return;
          s.commandMicOpen = false;
          _wakeListening = false;
          if (_micHazardEpoch != s.hazardEpoch || lastWords.isEmpty) return;
          final command = wake ? wakeCommand(lastWords) : lastWords;
          if (command == null) return;
          if (command.isEmpty) {
            _handlingVoice = false;
            // The recognizer can callback before listen() itself returns.
            // Queue activation after setup has finished instead of losing it.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && session == _listenSession) unawaited(listen());
            });
            WidgetsBinding.instance.scheduleFrame();
            return;
          }
          final intent = parseIntent(command);
          if (intent.command == VoiceCommand.go) {
            search.text = intent.destination!;
            setState(() => tab = 0);
          }
          HapticFeedback.lightImpact();
          await s.voiceGo(command);
        } finally {
          _handlingVoice = false;
          if (mounted) {
            setState(() {});
            _finishNativeCommand();
            _scheduleWake();
          }
        }
      }

      _completeRecognition = () => unawaited(deliver());
      _recognitionEnd = Timer(const Duration(seconds: 23), () {
        if (session == _listenSession) _completeRecognition?.call();
      });
      await speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'vi_VN',
          partialResults: true,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
        ),
        onResult: (r) {
          if (!mounted ||
              !_foreground ||
              session != _listenSession ||
              delivered) {
            return;
          }
          setState(() => partial = r.recognizedWords);
          if (r.recognizedWords.trim().isNotEmpty) {
            lastWords = r.recognizedWords.trim();
          }
          // A complete wake phrase may be available only as partial text.
          if (r.finalResult || (wake && wakeCommand(lastWords) == '')) {
            unawaited(deliver());
          }
        },
      );
    } catch (_) {
      _recognitionEnd?.cancel();
      s.commandMicOpen = false;
      _foregroundWakeFailed = true;
      await s.setWakeEnabled(false);
      s.error = 'Không mở được micro. Hãy kiểm tra quyền nhận dạng giọng nói.';
      await s.say(s.error!, urgent: true);
      if (mounted) setState(() => listening = false);
    } finally {
      _openingMic = false;
      _syncNativeVoice();
      if (!listening) _scheduleWake();
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
    if (name != null && name.isNotEmpty) {
      await s.perform(() => s.saveFavorite(name));
    }
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
              _SosCallPicker(state: s),
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
        label: 'Chạm đúp để nói điểm đến hoặc lệnh dẫn đường',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Double-tap anywhere opens the mic — no button to find.
          onDoubleTap: () => listen(),
          child: Stack(
            children: [
              _buildBody(isHazard),
              if (s.pendingConfirm != null)
                Positioned.fill(
                  child: _ConfirmOverlay(
                    place: s.pendingConfirm!,
                    question: s.confirmPrompt ?? '',
                    listening: listening,
                    heard: partial,
                    onAnswer: s.answerConfirm,
                  ),
                )
              else if (listening && !_wakeListening)
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
        if (!_android && _wakeListening && listening && _recognizerReady)
          const AnimatedBanner(
            text: 'Mic đang chờ “Hey Aurelia”',
            color: Color(0xFF164E43),
            icon: Icons.hearing,
          ),
        EmergencyBanner(state: s),
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
        key: const Key('command_mic'),
        onPressed: () => listen(),
        tooltip: listening && !_wakeListening
            ? 'Dừng nghe'
            : 'Nói lệnh với Aurelia',
        icon: Icon(
          listening && !_wakeListening ? Icons.mic : Icons.mic_none,
          color: kAccent,
        ),
      ),
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
                  : s.location != null
                  ? 'Vị trí gần đúng ±${s.accuracy.round()} m'
                  : 'Đang lấy vị trí điện thoại',
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
              suffixIcon: IconButton(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        color: kText,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (place.address.isNotEmpty)
                      Text(
                        place.address,
                        style: const TextStyle(
                          color: kTextSub,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                  ],
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
                          s.location != null
                              ? '±${s.accuracy.round()} m${s.freshFix ? '' : ' • gần đúng'}'
                              : 'Chưa có vị trí',
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
                    : 'Bắt đầu với kính',
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
  late final TextEditingController endpoint, token, apiKey;
  final List<_ContactFields> contacts = [];
  bool saved = false;
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    endpoint = TextEditingController(text: s.link.endpoint);
    token = TextEditingController(text: s.link.token);
    apiKey = TextEditingController(text: s.routing.key);
    for (final c in s.emergencyContacts) {
      contacts.add(_ContactFields(c.name, c.phone));
    }
  }

  @override
  void dispose() {
    endpoint.dispose();
    token.dispose();
    apiKey.dispose();
    for (final c in contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _importPairing({required bool camera}) async {
    final raw = camera
        ? await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const PairingScanner()),
          )
        : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted || raw == null) return;
    PairingConfig config;
    try {
      config = PairingConfig.parse(raw);
    } catch (_) {
      await s.perform(() async {
        throw const FormatException(
          'Mã cấu hình không hợp lệ. Nhờ người hỗ trợ tạo lại QR SecondSight.',
        );
      });
      return;
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lưu cấu hình kính?'),
        content: Text(
          'Kính tại ${config.endpoint}\n${config.allowInsecure ? "Kết nối HTTP LAN thử nghiệm. " : ""}Token sẽ được lưu bảo mật.${config.routingKey == null ? " Giữ API key hiện tại." : " Có API key bản đồ."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu cấu hình'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    await s.perform(() async {
      s.link.disconnect();
      s.link.endpoint = config.endpoint;
      s.link.token = config.token;
      s.link.allowInsecure = config.allowInsecure;
      if (config.routingKey != null) s.routing.key = config.routingKey!;
      await s.saveSettings();
      endpoint.text = s.link.endpoint;
      token.text = s.link.token;
      apiKey.text = s.routing.key;
      s.notice = 'Đã lưu cấu hình. Vào Kính để kết nối; những lần sau không cần nhập lại.';
      setState(() => saved = true);
    });
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

      GlassCard(
        child: SwitchListTile(
          title: const Text('Gọi Aurelia trong hành trình'),
          subtitle: const Text(
            'Tự bật khi đang dẫn đường hoặc lệch tuyến. Android tiếp tục nghe khi app ở nền hoặc khóa màn hình, có thông báo mic. Dừng/tạm dừng hành trình sẽ tắt mic nền.',
          ),
          value: s.navigationWakeEnabled,
          onChanged: (value) => s.setNavigationWakeEnabled(value),
        ),
      ),
      const SizedBox(height: 16),
      GlassCard(
        child: SwitchListTile(
          title: const Text('Gọi “Hey Aurelia” ngoài hành trình'),
          subtitle: const Text(
            'Android chờ “Hey Aurelia” bằng bộ nhận dạng cục bộ, không phát âm báo theo chu kỳ. Chỉ hoạt động khi app hiển thị ngoài hành trình; tự ngừng lúc app đọc hoặc có cảnh báo.',
          ),
          value: s.wakeEnabled,
          onChanged: (value) => s.setWakeEnabled(value),
        ),
      ),
      const SizedBox(height: 16),
      // ── Pi connection
      _Section('Kết nối kính'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _importPairing(camera: true),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Quét QR cấu hình một lần'),
      ),
      TextButton.icon(
        onPressed: () => _importPairing(camera: false),
        icon: const Icon(Icons.content_paste),
        label: const Text('Dán cấu hình từ người hỗ trợ'),
      ),
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
      _ContactsEditor(
        contacts: contacts,
        onAdd: () => setState(() => contacts.add(_ContactFields('', ''))),
        onRemove: (c) => setState(() {
          contacts.remove(c);
          c.dispose();
        }),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.warning_amber_rounded, color: kDanger),
        label: const Text(
          'Thử nghiệm luồng khẩn cấp mất kính (Demo)',
          style: TextStyle(color: kDanger, fontWeight: FontWeight.w600),
        ),
        onPressed: () => s.startLostConnectionEmergency(simulated: true),
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
          s.emergencyContacts = [
            for (final c in contacts)
              if (c.phone.text.trim().isNotEmpty)
                EmergencyContact(c.name.text.trim(), c.phone.text.trim()),
          ];
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

// ─── Emergency contacts ──────────────────────────────────────────
class _ContactFields {
  final TextEditingController name, phone;
  _ContactFields(String n, String p)
    : name = TextEditingController(text: n),
      phone = TextEditingController(text: p);
  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

/// Collapsible list so any number of relatives stays compact in Settings.
class _ContactsEditor extends StatelessWidget {
  final List<_ContactFields> contacts;
  final VoidCallback onAdd;
  final ValueChanged<_ContactFields> onRemove;
  const _ContactsEditor({
    required this.contacts,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.contacts_rounded, color: kAccent),
        title: const Text(
          'Số điện thoại người thân',
          style: TextStyle(
            color: kText,
            fontWeight: FontWeight.w600,
            fontFamily: 'BeVietnamPro',
          ),
        ),
        subtitle: Text(
          contacts.isEmpty
              ? 'Chưa có số nào — chạm để thêm'
              : '${contacts.length} người · #1 là người giám hộ tự động gọi khi mất kính',
          style: const TextStyle(
            color: kTextSub,
            fontSize: 12,
            fontFamily: 'BeVietnamPro',
          ),
        ),
        children: [
          for (var i = 0; i < contacts.length; i++)
            Padding(
              key: ObjectKey(contacts[i]),
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: contacts[i].name,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: kText),
                        decoration: InputDecoration(
                          labelText: i == 0
                              ? 'Tên người giám hộ ưu tiên #1'
                              : 'Tên / ghi chú ${i + 1}',
                          hintText: i == 0 ? 'VD: Mẹ' : 'VD: Anh Nam (hàng xóm)',
                        ),
                      ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: contacts[i].phone,
                          keyboardType: TextInputType.phone,
                          autocorrect: false,
                          style: const TextStyle(color: kText),
                          decoration: const InputDecoration(
                            labelText: 'Số điện thoại',
                            hintText: '+84…',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Xóa người thân',
                    icon: const Icon(Icons.delete_outline, color: kTextSub),
                    onPressed: () => onRemove(contacts[i]),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Thêm người thân'),
            ),
          ),
          const Text(
            'Nhấn “Lưu cài đặt” bên dưới để lưu danh sách.',
            style: TextStyle(color: kTextSub, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

/// SOS: pick which relative to call from a dropdown, then open the dialer.
class _SosCallPicker extends StatefulWidget {
  final AppState state;
  const _SosCallPicker({required this.state});
  @override
  State<_SosCallPicker> createState() => _SosCallPickerState();
}

class _SosCallPickerState extends State<_SosCallPicker> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final list = s.emergencyContacts;
    if (list.isEmpty) {
      return const FilledButton(
        onPressed: null,
        child: Text('Chưa đặt số người thân (vào Cài đặt để thêm)'),
      );
    }
    if (selected >= list.length) selected = 0;
    final c = list[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Chọn người thân'),
          dropdownColor: kSurface,
          style: const TextStyle(
            color: kText,
            fontSize: 15,
            fontFamily: 'BeVietnamPro',
          ),
          items: [
            for (var i = 0; i < list.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  list[i].name.trim().isEmpty
                      ? list[i].phone
                      : '${list[i].name.trim()} · ${list[i].phone}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'BeVietnamPro',
                    color: kText,
                    fontSize: 15,
                  ),
                ),
              ),
          ],
          onChanged: (v) => setState(() => selected = v ?? 0),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.call),
          label: Text('Gọi ${c.label}', overflow: TextOverflow.ellipsis),
          onPressed: () => s.perform(() async {
            if (!await launchUrl(Uri(scheme: 'tel', path: c.phone))) {
              throw Exception('Không mở được ứng dụng gọi điện.');
            }
            s.log('sos_dialer', 'Đã mở giao diện gọi người thân: ${c.label}');
          }),
        ),
      ],
    );
  }
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

// ─── Hands-free listening overlay (Siri-style orb) ───────────────
class _ListeningOverlay extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;
  const _ListeningOverlay({required this.text, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Đang nghe. Hãy nói điểm đến hoặc lệnh dẫn đường. Chạm để hủy.',
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

class _ConfirmOverlay extends StatelessWidget {
  final Place place;
  final String question, heard;
  final bool listening;
  final void Function(YesNo) onAnswer;
  const _ConfirmOverlay({
    required this.place,
    required this.question,
    required this.listening,
    required this.heard,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: kBg.withValues(alpha: .96),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                listening ? Icons.mic : Icons.record_voice_over,
                size: 56,
                color: kAccent,
              ),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(
                  question,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
              if (heard.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  heard,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kTextSub),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Nói có, không hoặc hủy. Bạn cũng có thể dùng các nút bên dưới.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSub),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => onAnswer(YesNo.yes),
                  child: const Text('Có'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onAnswer(YesNo.no),
                  child: const Text('Không'),
                ),
              ),
              TextButton(
                onPressed: () => onAnswer(YesNo.cancel),
                child: const Text('Hủy'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class EmergencyBanner extends StatelessWidget {
  final AppState state;
  const EmergencyBanner({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final phase = state.emergencyPhase;
        if (phase == EmergencyPhase.none || phase == EmergencyPhase.cancelled) {
          return const SizedBox.shrink();
        }

    final isCountdown = phase == EmergencyPhase.countdown;
    final isActionTaken = phase == EmergencyPhase.actionTaken;
    final isReconnecting = phase == EmergencyPhase.reconnecting;

    final bgColor = isCountdown
        ? const Color(0xFF881337)
        : (isActionTaken ? const Color(0xFF78350F) : const Color(0xFF7F1D1D));

    final borderColor = isCountdown
        ? const Color(0xFFF43F5E)
        : (isActionTaken ? kWarning : const Color(0xFFEF4444));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: isCountdown ? 0.6 : 0.3),
            blurRadius: isCountdown ? 20 : 10,
            spreadRadius: isCountdown ? 2 : 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCountdown
                      ? Text(
                          '${state.emergencyCountdown}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'BeVietnamPro',
                          ),
                        )
                      : Icon(
                          isActionTaken
                              ? Icons.check_circle_outline_rounded
                              : Icons.sensors_off_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCountdown
                          ? 'KHẨN CẤP: KÍNH MẤT KẾT NỐI'
                          : isActionTaken
                              ? 'ĐÃ GỬI VỊ TRÍ & QUAY SỐ'
                              : 'MẤT KẾT NỐI VỚI KÍNH',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        fontFamily: 'BeVietnamPro',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isCountdown
                          ? 'Tự động gửi SMS tọa độ và gọi người giám hộ sau ${state.emergencyCountdown}s. Nói "HỦY" nếu bạn an toàn!'
                          : isActionTaken
                              ? 'Đã phát cảnh báo SMS kèm GPS tới người thân và gọi người giám hộ ưu tiên.'
                              : 'Đang thử kết nối lại lần ${state.emergencyRetryCount}/5... Xin bạn đứng yên tại vị trí an toàn.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        height: 1.3,
                        fontFamily: 'BeVietnamPro',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isCountdown || isReconnecting) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(
                    isCountdown ? 'HỦY KHẨN CẤP (TÔI ỔN)' : 'Hủy thử lại',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      fontFamily: 'BeVietnamPro',
                    ),
                  ),
                  onPressed: () => state.cancelEmergency(),
                ),
              ] else if (isActionTaken) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text(
                    'Đóng thông báo',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      fontFamily: 'BeVietnamPro',
                    ),
                  ),
                  onPressed: () => state.dismissEmergencyBanner(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
      },
    );
  }
}
