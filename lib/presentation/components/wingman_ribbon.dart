import 'package:flutter/material.dart';
import '../design_system/wingman_tokens.dart';

/// Original, local vector decoration. No requests, animation or semantic content.
class WingmanRibbon extends StatelessWidget {
  const WingmanRibbon({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: CustomPaint(
        painter: _RibbonPainter(WingmanTokens.of(context), compact),
        size: Size.infinite,
      ),
    ),
  );
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.tokens, this.compact);
  final WingmanTokens tokens;
  final bool compact;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (compact) {
      final center = Offset(size.width * .98, size.height * .52);
      final radius = size.height * .42;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = tokens.ribbonCyan.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * .13,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        .25,
        1.3,
        false,
        Paint()
          ..color = tokens.ribbonBlue.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * .13,
      );
    } else {
      canvas.scale(size.width / 620, size.height / 280);
      final orbit = Paint()
        ..color = tokens.ribbonBlue.withValues(alpha: .09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      for (final r in [105.0, 154.0]) {
        canvas.drawCircle(const Offset(350, 142), r, orbit);
      }
      final ribbon = Path()
        ..moveTo(-35, 284)
        ..cubicTo(136, 309, 130, 126, 229, 129)
        ..cubicTo(333, 130, 422, 227, 472, 133)
        ..cubicTo(492, 93, 514, 19, 531, -24);
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = LinearGradient(
            colors: [tokens.ribbonBlue, tokens.ribbonCyan],
          ).createShader(const Rect.fromLTWH(0, 0, 600, 280))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 62,
      );
      final second = Path()
        ..moveTo(92, 307)
        ..cubicTo(213, 219, 252, -24, 476, 1);
      canvas.drawPath(
        second,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              tokens.ribbonBlue.withValues(alpha: .82),
              tokens.ribbonCyan,
            ],
          ).createShader(const Rect.fromLTWH(70, 0, 430, 280))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 42,
      );
      canvas.drawPath(
        ribbon,
        Paint()
          ..color = tokens.onHeroInk.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        const Offset(323, 33),
        9,
        Paint()..color = tokens.surface,
      );
      canvas.drawCircle(
        const Offset(323, 33),
        4,
        Paint()..color = tokens.ribbonBlue,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.tokens != tokens || old.compact != compact;
}
