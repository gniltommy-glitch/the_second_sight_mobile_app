import 'dart:ui';

import 'package:flutter/material.dart';

/// Glassmorphism card — frosted glass look with luminous border.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final double blur;
  final Color? fillColor;
  final List<BoxShadow>? boxShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.borderWidth = 1.0,
    this.borderRadius = 24,
    this.blur = 16,
    this.fillColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: fillColor ?? const Color(0xFF1A1D27).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color:
                  borderColor ??
                  const Color(0xFF80F5D2).withValues(alpha: 0.22),
              width: borderWidth,
            ),
            boxShadow:
                boxShadow ??
                [
                  BoxShadow(
                    color: const Color(0xFF80F5D2).withValues(alpha: 0.06),
                    blurRadius: 24,
                    spreadRadius: 0,
                  ),
                ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glowing version — border pulses with accent color (for active state).
class GlowCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color glowColor;
  final bool active;

  const GlowCard({
    super.key,
    required this.child,
    this.padding,
    this.glowColor = const Color(0xFF80F5D2),
    this.active = false,
  });

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.3,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => GlassCard(
        padding: widget.padding,
        borderColor: widget.active
            ? widget.glowColor.withValues(alpha: _pulse.value)
            : const Color(0xFF80F5D2).withValues(alpha: 0.22),
        borderWidth: widget.active ? 1.5 : 1.0,
        boxShadow: widget.active
            ? [
                BoxShadow(
                  color: widget.glowColor.withValues(alpha: _pulse.value * 0.3),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ]
            : null,
        child: widget.child,
      ),
    );
  }
}
