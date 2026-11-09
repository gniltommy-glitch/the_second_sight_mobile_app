import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native Android state; Flutter's accessibleNavigation remains the fallback.
class AndroidAccessibility extends ChangeNotifier with WidgetsBindingObserver {
  static const channel = MethodChannel('secondsight/accessibility');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool? touchExplorationEnabled;
  bool? talkBackEnabled;
  bool _disposed = false;
  bool get systemReaderActive =>
      touchExplorationEnabled == true || talkBackEnabled == true;

  void start() {
    if (!supported) return;
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'stateChanged') _update(call.arguments);
    });
    unawaited(refresh());
  }

  void _update(dynamic value) {
    if (_disposed || value is! Map) return;
    final touch = value['touchExplorationEnabled'];
    final talkBack = value['talkBackEnabled'];
    if (touch is! bool || talkBack is! bool) return;
    if (touchExplorationEnabled == touch && talkBackEnabled == talkBack) return;
    touchExplorationEnabled = touch;
    talkBackEnabled = talkBack;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!supported || _disposed) return;
    try {
      _update(await channel.invokeMethod<Object?>('getState'));
    } on PlatformException {
      // Keep the last state and the Flutter accessibility signal.
    } on MissingPluginException {
      // Widget tests and older hosts can still use Flutter semantics.
    }
  }

  Future<bool> openSettings() async {
    if (!supported || _disposed) return false;
    try {
      return await channel.invokeMethod<bool>('openSettings') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void didChangeAccessibilityFeatures() => unawaited(refresh());

  @override
  void dispose() {
    _disposed = true;
    if (supported) {
      WidgetsBinding.instance.removeObserver(this);
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}

class AndroidAccessibilityScope
    extends InheritedNotifier<AndroidAccessibility> {
  const AndroidAccessibilityScope({
    super.key,
    required AndroidAccessibility service,
    required super.child,
  }) : super(notifier: service);

  static AndroidAccessibility? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AndroidAccessibilityScope>()
      ?.notifier;
}
