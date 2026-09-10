import 'package:flutter/material.dart';
import '../theme.dart';

/// Original provisional geometry. Replace this widget to roll out final artwork.
class WingmanMark extends StatelessWidget {
  const WingmanMark({super.key, this.size = 40, this.isPrivate = false});
  final double size;
  final bool isPrivate;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Wingman',
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPrivate ? const Color(0xff665080) : WingmanTheme.green,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: CustomPaint(painter: _WingPainter()),
    ),
  );
}

class _WingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .18, size.height * .34)
      ..lineTo(size.width * .4, size.height * .46)
      ..lineTo(size.width * .79, size.height * .24)
      ..lineTo(size.width * .62, size.height * .66)
      ..lineTo(size.width * .47, size.height * .77)
      ..lineTo(size.width * .34, size.height * .61)
      ..close();
    canvas.drawPath(path, Paint()..color = WingmanTheme.gold);
    canvas.drawLine(
      Offset(size.width * .4, size.height * .56),
      Offset(size.width * .67, size.height * .37),
      Paint()
        ..color = WingmanTheme.green
        ..strokeWidth = size.width * .035
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WingPainter oldDelegate) => false;
}

class WingmanWordmark extends StatelessWidget {
  const WingmanWordmark({super.key, this.large = false});
  final bool large;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      WingmanMark(size: large ? 54 : 36),
      const SizedBox(width: 11),
      Text(
        'wingman',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: large ? 34 : 24,
          letterSpacing: -1.1,
        ),
      ),
    ],
  );
}
