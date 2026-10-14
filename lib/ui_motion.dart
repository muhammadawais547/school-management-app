import 'package:flutter/material.dart';

/// Small desktop hover feedback for cards and controls that can be clicked.
/// It only changes paint scale; it does not affect layout or interaction logic.
class HoverMotion extends StatefulWidget {
  final Widget child;
  final double hoverScale;

  const HoverMotion({super.key, required this.child, this.hoverScale = 1.012});

  @override
  State<HoverMotion> createState() => _HoverMotionState();
}

class _HoverMotionState extends State<HoverMotion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: AnimatedScale(
        scale: _hovered ? widget.hoverScale : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
