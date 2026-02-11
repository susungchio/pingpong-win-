import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 예선/본선 화면에서 Ctrl+마우스 휠로만 5% 단위 확대·축소 (Ctrl 없이 휠은 스크롤만)
class CtrlWheelZoomScope extends StatefulWidget {
  final Widget child;
  /// 확대·축소 시 기준점. center면 축소 시 전체가 보이고, topLeft면 좌상단 기준
  final AlignmentGeometry scaleAlignment;

  const CtrlWheelZoomScope({
    super.key,
    required this.child,
    this.scaleAlignment = Alignment.topLeft,
  });

  @override
  State<CtrlWheelZoomScope> createState() => _CtrlWheelZoomScopeState();
}

class _CtrlWheelZoomScopeState extends State<CtrlWheelZoomScope> {
  static const double _zoomMin = 0.5;
  static const double _zoomMax = 2.0;
  static const double _zoomStep = 0.05; // 5% 단위
  double _zoom = 1.0;

  bool get _isControlPressed =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.control) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent || !_isControlPressed) return;
        final scrollEvent = event as PointerScrollEvent;
        final dy = scrollEvent.scrollDelta.dy;
        setState(() {
          _zoom = (_zoom + (dy > 0 ? -_zoomStep : _zoomStep)).clamp(_zoomMin, _zoomMax);
        });
      },
      child: Transform.scale(
        scale: _zoom,
        alignment: widget.scaleAlignment,
        child: widget.child,
      ),
    );
  }
}
