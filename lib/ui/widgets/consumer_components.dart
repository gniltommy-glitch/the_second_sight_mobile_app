import 'package:flutter/material.dart';

const _accent = Color(0xFF80E8C8);
const _muted = Color(0xFFA8B5C5);

/// Native interpretation of React Bits Spotlight Card / Glare Hover.
/// Pointer light and a small perspective tilt; touch never captures scrolling.
class SpotlightSurface extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tilt;
  const SpotlightSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.tilt = false,
  });
  @override
  State<SpotlightSurface> createState() => _SpotlightSurfaceState();
}

class _SpotlightSurfaceState extends State<SpotlightSurface> {
  Alignment _light = const Alignment(-.8, -.9);
  bool _hover = false;

  void _point(Offset point, double width) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(() {
      _light = Alignment(
        (point.dx / width * 2 - 1).clamp(-1, 1),
        (point.dy / 240 * 2 - 1).clamp(-1, 1),
      );
      _hover = true;
    });
  }

  void _reset() => setState(() {
    _hover = false;
    _light = const Alignment(-.8, -.9);
  });
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, bounds) => MouseRegion(
        onHover: (event) => _point(event.localPosition, bounds.maxWidth),
        onExit: (_) => _reset(),
        child: Listener(
          onPointerDown: (event) =>
              _point(event.localPosition, bounds.maxWidth),
          onPointerUp: (_) => _reset(),
          onPointerCancel: (_) => _reset(),
          child: AnimatedContainer(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            transformAlignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .001)
              ..rotateX(widget.tilt && _hover ? -_light.y * .025 : 0)
              ..rotateY(widget.tilt && _hover ? _light.x * .025 : 0),
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _accent.withValues(alpha: _hover ? .35 : .16),
              ),
              gradient: RadialGradient(
                center: _light,
                radius: 1.6,
                colors: [
                  Color.lerp(
                    const Color(0xFF254B49),
                    const Color(0xFF315B58),
                    _hover ? 1 : 0,
                  )!,
                  const Color(0xFF15242B),
                  const Color(0xFF151C29),
                ],
                stops: const [0, .5, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .16),
                  offset: const Offset(0, 8),
                  blurRadius: 24,
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class JourneyWelcome extends StatelessWidget {
  final bool connected, navigating, demo;
  final VoidCallback onDevice;
  const JourneyWelcome({
    super.key,
    required this.connected,
    required this.navigating,
    required this.demo,
    required this.onDevice,
  });
  @override
  Widget build(BuildContext context) => SpotlightSurface(
    tilt: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'CHUYỂN ĐỘNG CÙNG BẠN',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
            const Icon(Icons.auto_awesome_outlined, size: 16, color: _accent),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    navigating
                        ? 'Cùng bạn trên\ntừng bước đi.'
                        : 'Tự tin đi.\nAn tâm đến.',
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: Color(0xFFF4FAF8),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Dẫn đường dễ dàng.\nLuôn có bạn đồng hành.',
                    style: TextStyle(
                      color: Color(0xFFB7C9CD),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width < 360 ? 66 : 100,
                height: 120,
                child: CustomPaint(painter: _WayfinderArt()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(height: 1, color: Colors.white.withValues(alpha: .09)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              connected ? Icons.link_rounded : Icons.link_off_rounded,
              color: connected ? _accent : _muted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                demo
                    ? 'Đang dùng kính mô phỏng'
                    : connected
                    ? 'Kính đã kết nối'
                    : 'Kết nối kính để bắt đầu',
                style: const TextStyle(fontSize: 12, color: Color(0xFFD4E1E5)),
              ),
            ),
            TextButton(
              onPressed: onDevice,
              child: Text(
                connected ? 'Xem kính' : 'Kết nối',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// An abstract dimensional wayfinding mark, not a map or a sensor reading.
class _WayfinderArt extends CustomPainter {
  const _WayfinderArt();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .52);
    canvas.drawCircle(
      center,
      43,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _accent.withValues(alpha: .22),
            _accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 43)),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy + 25);
    canvas.rotate(-.3);
    for (final r in [35.0, 46.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * .72),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _accent.withValues(alpha: .18),
      );
    }
    canvas.restore();
    final top = Offset(size.width * .62, 10),
        left = Offset(15, 85),
        middle = Offset(54, 64),
        right = Offset(83, 100);
    final face = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(middle.dx, middle.dy)
      ..close();
    canvas.drawPath(
      face,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0FFF2), Color(0xFF83E4C3), Color(0xFF329B85)],
        ).createShader(Offset.zero & size),
    );
    final side = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(middle.dx, middle.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      side,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF83E4C3), Color(0xFF22685E)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawLine(
      top,
      middle,
      Paint()
        ..color = Colors.white.withValues(alpha: .7)
        ..strokeWidth = 1.1,
    );
    canvas.drawCircle(const Offset(86, 32), 2, Paint()..color = _accent);
    canvas.drawCircle(
      const Offset(19, 40),
      1.5,
      Paint()..color = _accent.withValues(alpha: .5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PageEntrance extends StatelessWidget {
  final Widget child;
  const PageEntrance({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class StatusPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool good;
  const StatusPill({
    super.key,
    required this.icon,
    required this.text,
    this.good = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: good ? _accent.withValues(alpha: .08) : const Color(0xFF171F2A),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: good ? _accent : _muted),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: good ? _accent : _muted),
          ),
        ),
      ],
    ),
  );
}
