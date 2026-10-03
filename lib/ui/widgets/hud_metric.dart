import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Compact bento-style metric tile — inspired by reactbits.dev card grid.
class HudMetric extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  /// 0.0–1.0 arc fill. Null = hide arc.
  final double? fill;

  const HudMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor = const Color(0xFF00E5A0),
    this.fill,
  });

  @override
  State<HudMetric> createState() => _HudMetricState();
}

class _HudMetricState extends State<HudMetric>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _arc;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _arc = Tween<double>(begin: 0, end: widget.fill ?? 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    if (widget.fill != null) _ctrl.forward();
  }

  @override
  void didUpdateWidget(HudMetric old) {
    super.didUpdateWidget(old);
    if (old.fill != widget.fill && widget.fill != null) {
      _arc = Tween<double>(begin: _arc.value, end: widget.fill!)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
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
      animation: _arc,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1E2A),
              const Color(0xFF141720),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.accentColor.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accentColor.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: CustomPaint(
                painter: _ArcPainter(
                    fill: _arc.value, color: widget.accentColor),
                child: Center(
                  child: Icon(widget.icon,
                      color: widget.accentColor, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: widget.accentColor,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B7A8D),
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate()
      .fadeIn(duration: 400.ms)
      .slideY(begin: 0.06, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

class _ArcPainter extends CustomPainter {
  final double fill;
  final Color color;
  const _ArcPainter({required this.fill, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(4),
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    if (fill > 0) {
      canvas.drawArc(
        rect.deflate(4),
        -math.pi / 2,
        2 * math.pi * fill,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fill != fill || old.color != color;
}
