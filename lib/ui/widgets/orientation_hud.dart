import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

const _mint = Color(0xFF80F5D2);
const _ink = Color(0xFF0B1118);
const _muted = Color(0xFF9AAFB9);

/// Perspective-projected geometry, rendered locally with no web view or assets.
/// The camera orbit is decorative; the orientation comes exclusively from IMU.
class OrientationHud extends StatefulWidget {
  final bool ready, demo;
  final double heading, pitch, roll;
  final String title, subtitle;
  const OrientationHud({
    super.key,
    required this.ready,
    required this.demo,
    this.heading = 0,
    this.pitch = 0,
    this.roll = 0,
    this.title = 'Tầm nhìn thứ hai',
    this.subtitle = 'Sẵn sàng cho hành trình mới',
  });
  @override
  State<OrientationHud> createState() => _OrientationHudState();
}

class _OrientationHudState extends State<OrientationHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  bool _motion = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  void _updateMotion() {
    if (_motion && !MediaQuery.of(context).disableAnimations) {
      _orbit.repeat();
    } else {
      _orbit.stop();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.ready;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17322F), _ink, Color(0xFF141D2B)],
          stops: [0, .5, 1],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _mint.withValues(alpha: .23)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            offset: const Offset(0, 12),
            blurRadius: 24,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '視界   /   SECOND SIGHT',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.1,
                      color: _mint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _motion ? 'Dừng hiệu ứng 3D' : 'Bật hiệu ứng 3D',
                  onPressed: () {
                    setState(() => _motion = !_motion);
                    _updateMotion();
                  },
                  icon: Icon(
                    _motion
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    color: _muted,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 27,
                height: 1.2,
                letterSpacing: -.8,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF2F6F3),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              widget.subtitle,
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.5),
            ),
          ),
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: ClipRect(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _orbit,
                          builder: (context, _) => CustomPaint(
                            painter: _OrbitalPainter(
                              phase: _orbit.value * math.pi * 2,
                              heading: live ? widget.heading : 0,
                              pitch: live ? widget.pitch : 0,
                              roll: live ? widget.roll : 0,
                              ready: live,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 18,
                  child: Text(
                    'ORIENTATION\n${widget.demo
                        ? 'DEMO'
                        : live
                        ? 'LIVE'
                        : 'STANDBY'}',
                    style: const TextStyle(
                      fontSize: 9,
                      height: 1.8,
                      letterSpacing: 1.5,
                      color: _muted,
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 18,
                  child: Text(
                    live ? '${widget.heading.toStringAsFixed(0)}°' : '—°',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -1,
                      color: _mint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .20),
              border: Border(
                top: BorderSide(color: _mint.withValues(alpha: .15)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  live ? Icons.check_circle_outline : Icons.sensors_off,
                  color: live ? _mint : const Color(0xFFEABF79),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.demo
                        ? 'Mô phỏng • Dữ liệu minh họa'
                        : live
                        ? 'Đã hiệu chuẩn • Đang nhận hướng từ kính'
                        : 'Chưa có hướng hợp lệ • Không xác nhận hướng rẽ',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitalPainter extends CustomPainter {
  final double phase, heading, pitch, roll;
  final bool ready;
  const _OrbitalPainter({
    required this.phase,
    required this.heading,
    required this.pitch,
    required this.roll,
    required this.ready,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .51, size.height * .50);
    final scale = math.min(size.width * .35, 113.0);
    final camera = v.Matrix4.identity()
      ..rotateX(.98 + math.sin(phase) * .06)
      ..rotateZ(-.28 + math.cos(phase) * .06);
    final attitude = v.Matrix4.identity()
      ..rotateZ(heading * math.pi / 180)
      ..rotateY(pitch * math.pi / 180)
      ..rotateX(roll * math.pi / 180);
    Offset project(v.Vector3 point, {bool body = false}) {
      final p = point.clone();
      if (body) attitude.transform3(p);
      camera.transform3(p);
      final perspective = 4.5 / (4.5 + p.z);
      return center + Offset(p.x, p.y) * scale * perspective;
    }

    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void path(
      List<v.Vector3> points,
      Color color, {
      bool body = false,
      double width = 1,
    }) {
      final shape = Path();
      for (var i = 0; i < points.length; i++) {
        final p = project(points[i], body: body);
        if (i == 0) {
          shape.moveTo(p.dx, p.dy);
        } else {
          shape.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        shape,
        ink
          ..color = color
          ..strokeWidth = width,
      );
    }

    // Ground plane: faint instrument grid, not a fabricated map.
    for (var i = -4; i <= 4; i++) {
      final d = i * .34;
      path([
        v.Vector3(-1.5, d, .30),
        v.Vector3(1.5, d, .30),
      ], _mint.withValues(alpha: .06));
      path([
        v.Vector3(d, -1.5, .30),
        v.Vector3(d, 1.5, .30),
      ], _mint.withValues(alpha: .06));
    }
    for (final radius in [.95, 1.16, 1.24]) {
      path(
        List.generate(97, (i) {
          final a = i / 96 * math.pi * 2;
          return v.Vector3(math.cos(a) * radius, math.sin(a) * radius, 0);
        }),
        _mint.withValues(alpha: radius == 1.16 ? .6 : .16),
      );
    }
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2;
      final r = i % 5 == 0 ? 1.03 : 1.09;
      path([
        v.Vector3(math.cos(a) * r, math.sin(a) * r, 0),
        v.Vector3(math.cos(a) * 1.16, math.sin(a) * 1.16, 0),
      ], _mint.withValues(alpha: .5));
    }
    for (var axis = 0; axis < 2; axis++) {
      path(
        List.generate(97, (i) {
          final a = i / 96 * math.pi * 2;
          return axis == 0
              ? v.Vector3(math.cos(a) * .75, 0, math.sin(a) * .75)
              : v.Vector3(0, math.cos(a) * .75, math.sin(a) * .75);
        }),
        (axis == 0 ? _mint : const Color(0xFF9CAEE7)).withValues(alpha: .40),
        body: true,
      );
    }
    final vertices = [
      v.Vector3(0, -.73, 0),
      v.Vector3(-.25, .3, 0),
      v.Vector3(0, .13, -.2),
      v.Vector3(.25, .3, 0),
      v.Vector3(0, .13, .2),
    ];
    for (final face in [
      [0, 1, 2],
      [0, 2, 3],
      [0, 3, 4],
      [0, 4, 1],
      [1, 4, 3, 2],
    ]) {
      final points = face.map((i) => project(vertices[i], body: true)).toList();
      final shape = Path()..addPolygon(points, true);
      canvas.drawPath(
        shape,
        Paint()..color = _mint.withValues(alpha: ready ? .16 : .06),
      );
      canvas.drawPath(
        shape,
        ink
          ..strokeWidth = 1.4
          ..color = _mint.withValues(alpha: ready ? .95 : .35),
      );
    }
    final north = project(v.Vector3(0, -1.43, 0));
    final label = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: _mint,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, north - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(_OrbitalPainter old) =>
      phase != old.phase ||
      heading != old.heading ||
      pitch != old.pitch ||
      roll != old.roll ||
      ready != old.ready;
}
