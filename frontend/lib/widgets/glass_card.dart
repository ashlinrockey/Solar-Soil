import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double borderOpacity;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(20.0),
    this.borderOpacity = 0.8,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8), upperBound: 1000);
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 20.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: widget.borderOpacity),
                    width: 1.0,
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00979D).withValues(alpha: 0.06 + 0.04 * (_ctrl.value / 1000)),
                      Colors.transparent,
                      const Color(0xFF02C39A).withValues(alpha: 0.06 + 0.04 * ((1000 - _ctrl.value) / 1000)),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    child!,
                    // Scan lines overlay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ScanLinePainter(scrollOffset: _ctrl.value),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  final double scrollOffset;

  _ScanLinePainter({required this.scrollOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00979D).withValues(alpha: 0.025)
      ..strokeWidth = 0.5;

    final spacing = 8.0;
    final offset = scrollOffset % spacing;

    double y = offset;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += spacing;
    }
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.scrollOffset != scrollOffset;
}
