import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Large animated navigation instruction display.
class NavInstruction extends StatelessWidget {
  final String action;
  final String text;
  final double distanceM;
  final bool valid;

  const NavInstruction({
    super.key,
    required this.action,
    required this.text,
    required this.distanceM,
    this.valid = true,
  });

  static IconData _iconFor(String action) => switch (action) {
    'turn_right' => Icons.turn_right_rounded,
    'turn_left' => Icons.turn_left_rounded,
    'arrive' => Icons.place_rounded,
    'roundabout' => Icons.roundabout_left_rounded,
    'u_turn' => Icons.u_turn_left_rounded,
    _ => Icons.arrow_upward_rounded,
  };

  static Color _colorFor(String action) => switch (action) {
    'turn_right' || 'turn_left' => const Color(0xFF80F5D2),
    'arrive' => const Color(0xFFFF6B6B),
    'u_turn' => const Color(0xFFFBBF24),
    _ => const Color(0xFF60A5FA),
  };

  @override
  Widget build(BuildContext context) {
    final color = valid ? _colorFor(action) : const Color(0xFF6B7280);
    final icon = _iconFor(action);

    return Animate(
      key: ValueKey('$action-${distanceM.round()}'),
      effects: [
        FadeEffect(duration: 300.ms),
        SlideEffect(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
          duration: 350.ms,
          curve: Curves.easeOutCubic,
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Direction icon with glow
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: valid
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 20,
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: color, size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Distance
                Text(
                  distanceM <= 1 ? 'Ngay bây giờ' : '${distanceM.round()} m',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                // Instruction text
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
