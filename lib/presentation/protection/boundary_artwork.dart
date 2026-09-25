import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../components/wingman_components.dart';

/// Local, decorative artwork. No animation, image fetch, or protection claim.
class BoundaryArtwork extends StatelessWidget {
  const BoundaryArtwork({super.key, this.size = 220});
  final double size;
  @override
  Widget build(BuildContext context) {
    final tokens = WingmanTokens.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _Orbits(tokens.action),
          child: Center(
            child: Transform.rotate(
              angle: .13,
              child: Container(
                width: size * .5,
                height: size * .57,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * .14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tokens.action, WingmanTokens.navy],
                  ),
                  border: Border.all(
                    color: tokens.action.withValues(alpha: .5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.action.withValues(alpha: .12),
                      blurRadius: 36,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: size * .28,
                  color: WingmanTokens.cyan,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Orbits extends CustomPainter {
  _Orbits(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 6);
    for (final factor in [.74, .92, 1.1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * factor,
          height: size.height * factor * .68,
        ),
        Paint()
          ..color = color.withValues(alpha: .13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_Orbits oldDelegate) => oldDelegate.color != color;
}
