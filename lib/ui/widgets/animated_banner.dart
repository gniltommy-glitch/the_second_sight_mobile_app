import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Slide-in animated banner for hazards, errors, and notices.
class AnimatedBanner extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final IconData icon;
  final VoidCallback? onClose;
  final bool urgent;

  const AnimatedBanner({
    super.key,
    required this.text,
    required this.color,
    this.textColor = Colors.white,
    this.icon = Icons.info_outline,
    this.onClose,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Animate(
      effects: [
        SlideEffect(
          begin: const Offset(0, -1),
          end: Offset.zero,
          duration: 320.ms,
          curve: Curves.easeOutCubic,
        ),
        FadeEffect(duration: 250.ms),
      ],
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          border: urgent
              ? Border(
                  bottom: BorderSide(
                    color: textColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                )
              : null,
          boxShadow: urgent
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            if (onClose != null)
              GestureDetector(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.close,
                    color: textColor.withValues(alpha: 0.7),
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing dot indicating connection status.
class StatusDot extends StatefulWidget {
  final bool active;
  final Color color;
  final double size;

  const StatusDot({
    super.key,
    required this.active,
    this.color = const Color(0xFF80F5D2),
    this.size = 10,
  });

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF4B5563),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Transform.scale(
        scale: _scale.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
