import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated compass ring showing target bearing and device heading.
class CompassWidget extends StatefulWidget {
  /// Target bearing to the next waypoint (degrees, 0 = North).
  final double targetBearing;

  /// Current device heading from magnetometer (degrees, 0 = North).
  final double deviceHeading;
  final double size;
  final bool active;

  const CompassWidget({
    super.key,
    required this.targetBearing,
    this.deviceHeading = 0,
    this.size = 120,
    this.active = false,
  });

  @override
  State<CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<CompassWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _targetAnim;
  late Animation<double> _headingAnim;
  double _prevTarget = 0, _prevHeading = 0;

  @override
  void initState() {
    super.initState();
    _prevTarget = widget.targetBearing;
    _prevHeading = widget.deviceHeading;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _targetAnim = AlwaysStoppedAnimation(widget.targetBearing);
    _headingAnim = AlwaysStoppedAnimation(widget.deviceHeading);
  }

  @override
  void didUpdateWidget(CompassWidget old) {
    super.didUpdateWidget(old);
    if (old.targetBearing != widget.targetBearing) {
      _targetAnim = Tween<double>(
        begin: _prevTarget,
        end: widget.targetBearing,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _prevTarget = widget.targetBearing;
      _ctrl.forward(from: 0);
    }
    if (old.deviceHeading != widget.deviceHeading) {
      _headingAnim = Tween<double>(
        begin: _prevHeading,
        end: widget.deviceHeading,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _prevHeading = widget.deviceHeading;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _CompassPainter(
            targetBearing: _targetAnim.value,
            deviceHeading: _headingAnim.value,
            active: widget.active,
          ),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double targetBearing, deviceHeading;
  final bool active;
  const _CompassPainter({
    required this.targetBearing,
    required this.deviceHeading,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = cx - 8;

    // ── Outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFF1E2530)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFF80F5D2)
            .withValues(alpha: active ? 0.35 : 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Cardinal tick marks
    final tickPaint = Paint()
      ..color = const Color(0xFF4A5568)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 72; i++) {
      final angle = i * math.pi / 36;
      final isMajor = i % 18 == 0;
      final inner = isMajor ? r - 10 : r - 5;
      final outer = r - 1;
      canvas.drawLine(
        Offset(cx + inner * math.sin(angle), cy - inner * math.cos(angle)),
        Offset(cx + outer * math.sin(angle), cy - outer * math.cos(angle)),
        tickPaint
          ..color = isMajor ? const Color(0xFF6B7280) : const Color(0xFF374151),
      );
    }

    // ── N label
    const textStyle = TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 9,
      fontWeight: FontWeight.w700,
    );
    final tp = TextPainter(
      text: const TextSpan(text: 'N', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - r + 12));

    // ── Device heading needle (white, thin)
    _drawNeedle(
      canvas,
      cx,
      cy,
      r - 14,
      deviceHeading,
      const Color(0xFFCBD5E1),
      2,
    );

    // ── Target bearing arrow (accent green, thicker)
    _drawArrow(canvas, cx, cy, r - 10, targetBearing, const Color(0xFF80F5D2));

    // ── Center dot
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()..color = const Color(0xFF80F5D2),
    );
  }

  void _drawNeedle(
    Canvas canvas,
    double cx,
    double cy,
    double len,
    double bearing,
    Color color,
    double width,
  ) {
    final rad = bearing * math.pi / 180;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + len * math.sin(rad), cy - len * math.cos(rad)),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawArrow(
    Canvas canvas,
    double cx,
    double cy,
    double len,
    double bearing,
    Color color,
  ) {
    final rad = bearing * math.pi / 180;
    final tipX = cx + len * math.sin(rad);
    final tipY = cy - len * math.cos(rad);

    final path = Path();
    // Arrow tip
    path.moveTo(tipX, tipY);
    // Shaft base
    final baseX = cx + (len - 18) * math.sin(rad);
    final baseY = cy - (len - 18) * math.cos(rad);
    // Wing offsets perpendicular to bearing
    final wx = 6 * math.cos(rad);
    final wy = 6 * math.sin(rad);
    path.lineTo(baseX + wx, baseY + wy);
    path.lineTo(baseX - wx, baseY - wy);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    // Shaft
    canvas.drawLine(
      Offset(cx, cy),
      Offset(baseX, baseY),
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.targetBearing != targetBearing ||
      old.deviceHeading != deviceHeading ||
      old.active != active;
}
