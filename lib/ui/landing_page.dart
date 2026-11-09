import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../main.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Universal Tween Engine Easing Functions
/// Inspired by Universal Tween Engine (Aurelien Ribon / xaguzman/tween-engine-dart)
/// ─────────────────────────────────────────────────────────────────────────────
class TweenEquations {
  const TweenEquations._();

  static double linear(double t) => t.clamp(0.0, 1.0);

  static double quadOut(double t) {
    t = t.clamp(0.0, 1.0);
    return -t * (t - 2.0);
  }

  static double cubicOut(double t) {
    t = t.clamp(0.0, 1.0) - 1.0;
    return t * t * t + 1.0;
  }

  static double cubicInOut(double t) {
    t = (t.clamp(0.0, 1.0)) * 2.0;
    if (t < 1.0) return 0.5 * t * t * t;
    t -= 2.0;
    return 0.5 * (t * t * t + 2.0);
  }

  static double sineInOut(double t) {
    t = t.clamp(0.0, 1.0);
    return -0.5 * (math.cos(math.pi * t) - 1.0);
  }

  static double backOut(double t, [double s = 1.70158]) {
    t = t.clamp(0.0, 1.0) - 1.0;
    return t * t * ((s + 1.0) * t + s) + 1.0;
  }

  static double elasticOut(double t, [double a = 1.0, double p = 0.3]) {
    t = t.clamp(0.0, 1.0);
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;
    final s = p / (2.0 * math.pi) * math.asin(1.0 / a);
    return a *
            math.pow(2.0, -10.0 * t) *
            math.sin((t - s) * (2.0 * math.pi) / p) +
        1.0;
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Spine-Inspired Skeletal Kinematics & Cybernetic Optical Iris
/// Inspired by Spine 2D runtime (FedeOmoto/spine) articulated bones & IK waves
/// ─────────────────────────────────────────────────────────────────────────────
class SpineKinematicPainter extends CustomPainter {
  final double introProgress; // 0.0 -> 1.0 intro entry
  final double loopTime; // continuous looping seconds
  final double dilation; // iris dilation (0.0 -> 1.0)
  final Color accentColor;
  final Color glowColor;

  SpineKinematicPainter({
    required this.introProgress,
    required this.loopTime,
    required this.dilation,
    required this.accentColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.46;

    // 1. Ambient Background Pulse Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: 0.35 * introProgress),
          accentColor.withValues(alpha: 0.12 * introProgress),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxR * 1.35));
    canvas.drawCircle(center, maxR * 1.35, glowPaint);

    if (introProgress <= 0.01) return;

    // 2. HUD Framing Reticle (Corner Brackets)
    _drawCornerBrackets(canvas, center, maxR * 1.15, introProgress);

    // 3. Concentric Rotating Calibrated Dials (Degrees & Ticks)
    _drawCalibratedDial(canvas, center, maxR * 0.95);

    // 4. Spine Articulated Bone Chain (12 Vertebrae Bones with IK undulation)
    _drawSpineBoneChain(canvas, center, maxR * 0.72);

    // 5. Assistive Vision Radar / LiDAR Sweep Cone
    _drawRadarSweep(canvas, center, maxR * 0.70);

    // 6. Cybernetic Optical Iris Aperture Blades
    _drawIrisAperture(canvas, center, maxR * 0.40);

    // 7. Central Assistive Pupil Beacon
    _drawCentralPupil(canvas, center, maxR * 0.16);
  }

  void _drawCornerBrackets(Canvas canvas, Offset center, double r, double t) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.4 * t)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final bracketLen = r * 0.22;
    final offsets = [
      Offset(center.dx - r, center.dy - r), // Top-Left
      Offset(center.dx + r, center.dy - r), // Top-Right
      Offset(center.dx + r, center.dy + r), // Bottom-Right
      Offset(center.dx - r, center.dy + r), // Bottom-Left
    ];

    final signs = [
      [1.0, 1.0],
      [-1.0, 1.0],
      [-1.0, -1.0],
      [1.0, -1.0],
    ];

    for (var i = 0; i < 4; i++) {
      final corner = offsets[i];
      final sx = signs[i][0];
      final sy = signs[i][1];
      final path = Path()
        ..moveTo(corner.dx + sx * bracketLen, corner.dy)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(corner.dx, corner.dy + sy * bracketLen);
      canvas.drawPath(path, paint);

      // Micro crosshair
      final crossPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.6 * t)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(corner.dx - 4, corner.dy),
        Offset(corner.dx + 4, corner.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(corner.dx, corner.dy - 4),
        Offset(corner.dx, corner.dy + 4),
        crossPaint,
      );
    }
  }

  void _drawCalibratedDial(Canvas canvas, Offset center, double radius) {
    final dialScale = TweenEquations.backOut(introProgress);
    final r = radius * dialScale;
    final rotation = loopTime * 0.35; // smooth slow rotation

    // Outer subtle circle
    final circlePaint = Paint()
      ..color = kBorder.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, r, circlePaint);

    final tickPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const totalTicks = 48;
    for (var i = 0; i < totalTicks; i++) {
      final angle = rotation + (i * 2 * math.pi / totalTicks);
      final isMajor = i % 6 == 0;
      final len = isMajor ? 8.0 : 4.0;
      final p1 = Offset(
        center.dx + (r - len) * math.cos(angle),
        center.dy + (r - len) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      tickPaint.color = isMajor
          ? accentColor.withValues(alpha: 0.75)
          : accentColor.withValues(alpha: 0.25);
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  /// Spine-style multi-jointed skeletal chain:
  /// Vertebrae interconnected with fluid cubic beziers and pulsating offsets.
  void _drawSpineBoneChain(Canvas canvas, Offset center, double baseRadius) {
    const boneCount = 12;
    final r = baseRadius * TweenEquations.elasticOut(introProgress);
    final bonePositions = <Offset>[];

    // Compute articulated bone positions with kinematic phase lag
    for (var i = 0; i < boneCount; i++) {
      final baseAngle = (i * 2 * math.pi / boneCount) - (loopTime * 0.5);
      // Spine kinematic oscillation (sine wave travelling across vertebrae)
      final wave = math.sin((loopTime * 3.0) + (i * 0.65)) * 9.0;
      final boneR = r + wave;
      final pos = Offset(
        center.dx + boneR * math.cos(baseAngle),
        center.dy + boneR * math.sin(baseAngle),
      );
      bonePositions.add(pos);
    }

    // Connect vertebrae with organic glowing bezier curves
    final spinePath = Path();
    for (var i = 0; i < boneCount; i++) {
      final current = bonePositions[i];
      final next = bonePositions[(i + 1) % boneCount];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );

      if (i == 0) {
        spinePath.moveTo(mid.dx, mid.dy);
      } else {
        spinePath.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
    }
    spinePath.close();

    // Glow underlay
    final glowSpinePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(spinePath, glowSpinePaint);

    // Crisp spine track
    final crispSpinePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(spinePath, crispSpinePaint);

    // Vertebrae bone nodes (joints)
    final nodePaint = Paint()..style = PaintingStyle.fill;
    final nodeCorePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var i = 0; i < boneCount; i++) {
      final pos = bonePositions[i];
      final isAccentJoint = i % 3 == 0;
      nodePaint.color = isAccentJoint ? accentColor : kAccent2;

      // Outer joint halo
      canvas.drawCircle(pos, isAccentJoint ? 4.5 : 3.2, nodePaint);
      // Inner joint core
      canvas.drawCircle(pos, isAccentJoint ? 2.0 : 1.4, nodeCorePaint);
    }
  }

  /// Assistive radar / LiDAR sweep cone representing environmental perception
  void _drawRadarSweep(Canvas canvas, Offset center, double radius) {
    final sweepAngle = (loopTime * 2.2) % (2 * math.pi);
    final r = radius * TweenEquations.cubicOut(introProgress);

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0.0,
        endAngle: 2 * math.pi,
        colors: [
          Colors.transparent,
          accentColor.withValues(alpha: 0.0),
          accentColor.withValues(alpha: 0.05),
          accentColor.withValues(alpha: 0.28),
        ],
        stops: const [0.0, 0.70, 0.88, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: r));

    canvas.drawCircle(center, r, sweepPaint);

    // Leading edge beam
    final beamP2 = Offset(
      center.dx + r * math.cos(sweepAngle),
      center.dy + r * math.sin(sweepAngle),
    );
    final beamPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.75)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, beamP2, beamPaint);
  }

  /// Cybernetic Optical Iris Blades
  void _drawIrisAperture(Canvas canvas, Offset center, double radius) {
    const bladeCount = 6;
    final r = radius * (0.85 + (0.15 * dilation));
    final bladeRotation = loopTime * 0.45;

    final bladePaint = Paint()
      ..color = kSurface.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final bladeEdgePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < bladeCount; i++) {
      final angle = bladeRotation + (i * 2 * math.pi / bladeCount);
      final p1 = Offset(
        center.dx + (r * 0.45) * math.cos(angle),
        center.dy + (r * 0.45) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + r * math.cos(angle + 0.45),
        center.dy + r * math.sin(angle + 0.45),
      );
      final p3 = Offset(
        center.dx + r * math.cos(angle + 1.0),
        center.dy + r * math.sin(angle + 1.0),
      );

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();

      canvas.drawPath(path, bladePaint);
      canvas.drawPath(path, bladeEdgePaint);
    }
  }

  /// Central glowing optic pupil (Assistive Sensor Focus)
  void _drawCentralPupil(Canvas canvas, Offset center, double radius) {
    final pupilR = radius * (0.7 + (0.3 * dilation)) * introProgress;

    // Glowing core
    final pupilPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          accentColor,
          accentColor.withValues(alpha: 0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: pupilR));
    canvas.drawCircle(center, pupilR, pupilPaint);

    // Cross reticle in pupil
    final reticlePaint = Paint()
      ..color = kBg.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(center.dx - 6, center.dy),
      Offset(center.dx + 6, center.dy),
      reticlePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 6),
      Offset(center.dx, center.dy + 6),
      reticlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant SpineKinematicPainter old) => true;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Landing & Loading Page for SecondSight
/// Features a choreographed cinematic entrance, live telemetry, and smooth
/// transition to Home.
/// ─────────────────────────────────────────────────────────────────────────────
class LandingPage extends StatefulWidget {
  final AppState state;
  final VoidCallback? onEnter;

  const LandingPage({super.key, required this.state, this.onEnter});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late final AnimationController _timelineCtrl;
  late final AnimationController _loopCtrl;

  late final Animation<double> _introAnim;
  late final Animation<double> _contentSlideAnim;
  late final Animation<double> _contentOpacityAnim;
  late final Animation<double> _dilationAnim;

  int _statusStep = 0;
  Timer? _statusTimer;
  bool _canProceed = false;

  final List<String> _statusMessages = [
    'Khởi tạo hệ thống giác quan...',
    'Tự động định vị tọa độ GPS...',
    'Đang nạp mô hình nhận dạng giọng nói...',
    'Hệ thống trợ thị SecondSight sẵn sàng.',
  ];

  @override
  void initState() {
    super.initState();

    // 1. Timeline Controller (Intro choreographed entry: 1.8 seconds)
    _timelineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 2. Loop Controller (Continuous kinematic motion: 12 seconds per cycle)
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // Tweens using Universal Tween Engine equations
    _introAnim = CurvedAnimation(
      parent: _timelineCtrl,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
    );

    _contentSlideAnim = CurvedAnimation(
      parent: _timelineCtrl,
      curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
    );

    _contentOpacityAnim = CurvedAnimation(
      parent: _timelineCtrl,
      curve: const Interval(0.30, 0.75, curve: Curves.easeOut),
    );

    _dilationAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.2,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.2,
        ).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 50,
      ),
    ]).animate(_loopCtrl);

    // Start intro timeline
    _timelineCtrl.forward();

    // Cycle through system status messages
    _statusTimer = Timer.periodic(const Duration(milliseconds: 550), (timer) {
      if (!mounted) return;
      if (_statusStep < _statusMessages.length - 1) {
        setState(() => _statusStep++);
      } else {
        timer.cancel();
      }
    });

    // Check when ready to transition
    _timelineCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _canProceed = true);
        _maybeAutoTransition();
      }
    });
  }

  void _maybeAutoTransition() {
    if (widget.state.loaded && _canProceed && widget.onEnter != null) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) widget.onEnter?.call();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.state.loaded && widget.state.loaded) {
      _maybeAutoTransition();
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _timelineCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLoaded = widget.state.loaded;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // ── Background Ambient Cyberfield ──────────────────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [Color(0xFF131F2E), Color(0xFF0B1017), kBg],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // ── Subtle Background Grid Matrix ───────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _BackgroundMatrixPainter()),
          ),

          // ── Main Interactive Content ────────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableH = constraints.maxHeight;
                final eyeSize = math.min(
                  (availableH * 0.32).clamp(140.0, 270.0),
                  size.width * 0.72,
                );

                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: availableH),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 12.0,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top HUD Telemetry Bar
                          AnimatedBuilder(
                            animation: _contentOpacityAnim,
                            builder: (context, _) => Opacity(
                              opacity: _contentOpacityAnim.value,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildTelemetryBadge(
                                    icon: Icons.lens_blur_rounded,
                                    label: 'CORE v1.2.4',
                                  ),
                                  _buildTelemetryBadge(
                                    icon: Icons.wifi_tethering_rounded,
                                    label: 'LOCAL OFFLINE',
                                    color: kAccent,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Center Spine Kinematic Bionic Eye (Animated Canvas)
                          Center(
                            child: SizedBox(
                              width: eyeSize,
                              height: eyeSize,
                              child: AnimatedBuilder(
                                animation: Listenable.merge([
                                  _timelineCtrl,
                                  _loopCtrl,
                                ]),
                                builder: (context, _) {
                                  return CustomPaint(
                                    painter: SpineKinematicPainter(
                                      introProgress: _introAnim.value,
                                      loopTime: _loopCtrl.value * 12.0,
                                      dilation: _dilationAnim.value,
                                      accentColor: kAccent,
                                      glowColor: kAccent2,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Bottom Branding & Status Column
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _contentSlideAnim,
                              _contentOpacityAnim,
                            ]),
                            builder: (context, _) {
                              final slideOffset =
                                  (1.0 - _contentSlideAnim.value) * 32.0;
                              return Transform.translate(
                                offset: Offset(0, slideOffset),
                                child: Opacity(
                                  opacity: _contentOpacityAnim.value,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Holographic Title
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: kAccent.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                              color: kAccent.withValues(
                                                alpha: 0.1,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.visibility_rounded,
                                              color: kAccent,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text(
                                            'SecondSight',
                                            style: TextStyle(
                                              fontFamily: 'BeVietnamPro',
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.5,
                                              color: kText,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'TẦM NHÌN THỨ HAI · HỖ TRỢ ĐỊNH VỊ CỤC BỘ',
                                        style: TextStyle(
                                          fontFamily: 'BeVietnamPro',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.2,
                                          color: kAccent.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 24),

                                      // Real-time Loading Status Bar
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kSurface.withValues(
                                            alpha: 0.7,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(color: kBorder),
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              children: [
                                                // Neon pulsing beacon
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isLoaded
                                                        ? kAccent
                                                        : kWarning,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color:
                                                            (isLoaded
                                                                    ? kAccent
                                                                    : kWarning)
                                                                .withValues(
                                                                  alpha: 0.6,
                                                                ),
                                                        blurRadius: 6,
                                                        spreadRadius: 2,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                // Vital for widget test: 'Đang khởi động...'
                                                Expanded(
                                                  child: Text(
                                                    isLoaded
                                                        ? 'Hệ thống đã sẵn sàng'
                                                        : 'Đang khởi động...',
                                                    style: const TextStyle(
                                                      fontFamily:
                                                          'BeVietnamPro',
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: kText,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '${((isLoaded ? 1.0 : (_introAnim.value * 0.95)) * 100).toInt()}%',
                                                  style: const TextStyle(
                                                    fontFamily: 'BeVietnamPro',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: kTextSub,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),

                                            // Cybernetic Animated Progress Line
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: SizedBox(
                                                height: 4,
                                                child: LinearProgressIndicator(
                                                  value: isLoaded
                                                      ? 1.0
                                                      : (_introAnim.value *
                                                            0.9),
                                                  backgroundColor: kCard2,
                                                  valueColor:
                                                      const AlwaysStoppedAnimation<
                                                        Color
                                                      >(kAccent),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),

                                            // Dynamic Subtitle Ticker
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                isLoaded
                                                    ? (widget.state.location !=
                                                              null
                                                          ? 'Vị trí GPS: Đã xác định (±${widget.state.accuracy.round()}m).'
                                                          : 'Cảm biến và dẫn đường đã kết nối.')
                                                    : _statusMessages[_statusStep],
                                                style: const TextStyle(
                                                  fontFamily: 'BeVietnamPro',
                                                  fontSize: 11,
                                                  color: kTextSub,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 18),

                                      // Enter Button (visible when ready or loaded)
                                      if (_canProceed && isLoaded)
                                        FilledButton.icon(
                                          onPressed: widget.onEnter,
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('BẮT ĐẦU NGAY'),
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              72,
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            backgroundColor: kAccent,
                                            foregroundColor: const Color(
                                              0xFF001A14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                        )
                                      else
                                        const SizedBox(height: 72),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryBadge({
    required IconData icon,
    required String label,
    Color color = kTextSub,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'BeVietnamPro',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle cybernetic dot matrix background
class _BackgroundMatrixPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = kBorder.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    const spacing = 36.0;
    for (double x = 18; x < size.width; x += spacing) {
      for (double y = 18; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
