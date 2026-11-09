import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Uses the same labels and bounds as assistive technology, including dialogs,
/// icon buttons, editable fields and text. Does not claim drag/tap gestures.
class TouchExplorer extends StatefulWidget {
  const TouchExplorer({
    super.key,
    required this.onRead,
    required this.child,
    this.systemReaderActive = false,
    this.onSystemReaderActivated,
  });

  final bool systemReaderActive;
  final Future<void> Function()? onSystemReaderActivated;

  final Future<void> Function(String) onRead;
  final Widget child;

  @override
  State<TouchExplorer> createState() => _TouchExplorerState();
}

class _TouchExplorerState extends State<TouchExplorer> {
  late final SemanticsHandle _semantics;
  Timer? _timer;
  int? _pointer;
  String? _lastTarget;
  String? _pendingText;
  bool _wasScreenReader = false;

  @override
  void initState() {
    super.initState();
    _semantics = SemanticsBinding.instance.ensureSemantics();
  }

  // TalkBack/VoiceOver already perform touch exploration. Let them announce
  // semantics without adding a second overlapping voice from the application.
  bool get _screenReader =>
      widget.systemReaderActive || MediaQuery.of(context).accessibleNavigation;

  void _syncReader() {
    final active = _screenReader;
    if (active != _wasScreenReader) {
      _timer?.cancel();
      _pendingText = null;
      _lastTarget = null;
      if (active) {
        final cancel = widget.onSystemReaderActivated;
        if (cancel != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _screenReader) unawaited(cancel());
          });
        }
      }
    }
    _wasScreenReader = active;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncReader();
  }

  @override
  void didUpdateWidget(covariant TouchExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncReader();
  }

  void _inspect(Offset position, {bool immediate = false}) {
    if (_screenReader) return;
    final view = View.of(context);
    SemanticsNode? root;
    for (final renderView in RendererBinding.instance.renderViews) {
      if (renderView.flutterView == view) {
        root = renderView.owner?.semanticsOwner?.rootSemanticsNode;
        break;
      }
    }
    if (root == null) return;
    // The root semantics transform maps logical coordinates to physical pixels.
    final target = _find(root, position * view.devicePixelRatio);
    final text = target == null ? null : _describe(target.getSemanticsData());
    final identity = text == null ? null : '${target!.id}:$text';
    if (identity == _lastTarget) return;
    _lastTarget = identity;
    _timer?.cancel();
    _pendingText = text;
    if (text == null) return;
    if (immediate) {
      _flush();
    } else {
      // Briefly stabilize the target when the user sweeps across boundaries.
      _timer = Timer(const Duration(milliseconds: 70), _flush);
    }
  }

  SemanticsNode? _find(SemanticsNode node, Offset pointInParent) {
    if (node.getSemanticsData().flagsCollection.isHidden) return null;
    var point = pointInParent;
    final transform = node.transform;
    if (transform != null) {
      final inverse = Matrix4.tryInvert(transform);
      if (inverse == null) return null;
      point = MatrixUtils.transformPoint(inverse, point);
    }
    if (!node.rect.contains(point)) return null;
    if (!node.mergeAllDescendantsIntoThisNode) {
      final children = <SemanticsNode>[];
      node.visitChildren((child) {
        children.add(child);
        return true;
      });
      // Children are stored in inverse hit-test order: the last painted
      // sibling (for example a dialog above its barrier) wins.
      for (final child in children.reversed) {
        final hit = _find(child, point);
        if (hit != null) return hit;
      }
    }
    return _describe(node.getSemanticsData()) == null ? null : node;
  }

  String? _describe(SemanticsData data) {
    final parts = <String>[
      if (data.label.trim().isNotEmpty) data.label.trim(),
      if (data.value.trim().isNotEmpty) data.value.trim(),
    ];
    if (parts.isEmpty && data.tooltip.trim().isNotEmpty) {
      parts.add(data.tooltip.trim());
    }
    if (parts.isEmpty) return null;
    if (data.flagsCollection.isButton) parts.add('Nút');
    if (data.flagsCollection.isEnabled == Tristate.isFalse) {
      parts.add('Hiện chưa khả dụng');
    }
    return parts.join('. ');
  }

  void _flush() {
    _timer?.cancel();
    final text = _pendingText;
    _pendingText = null;
    if (mounted && !_screenReader && text != null) {
      unawaited(widget.onRead(text));
    }
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null || event.kind != PointerDeviceKind.touch) return;
    _pointer = event.pointer;
    _lastTarget = null;
    _inspect(event.position, immediate: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: (event) {
      if (event.pointer == _pointer) _inspect(event.position);
    },
    onPointerUp: (event) {
      if (event.pointer != _pointer) return;
      _flush();
      _pointer = null;
    },
    onPointerCancel: (event) {
      if (event.pointer != _pointer) return;
      _timer?.cancel();
      _pendingText = null;
      _pointer = null;
    },
    child: widget.child,
  );
}
