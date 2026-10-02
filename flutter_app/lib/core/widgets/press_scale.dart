import 'package:flutter/material.dart';

/// Shrinks its child slightly while a pointer is held down.
///
/// The pointer is observed with [Listener], which does not consume the event,
/// so the child keeps whatever tap or ink behaviour it already had. That makes
/// this safe to wrap around a card that contains its own buttons.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = 0.975,
    this.enabled = true,
  });

  final Widget child;

  /// How far to shrink. 1.0 disables the effect.
  final double scale;

  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool value) {
    if (!widget.enabled || _down == value) {
      return;
    }
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}
