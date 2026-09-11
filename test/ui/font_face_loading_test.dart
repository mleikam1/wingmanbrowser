import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// This checks the screenshot harness against exact bundled faces. It does not
/// alter production font registration or substitute different font files.
void main() {
  testWidgets('dynamic multi-face family preserves bundled weight selection', (
    tester,
  ) async {
    final results = await tester.runAsync(() async {
      final faces = <FontWeight, String>{
        FontWeight.w400: 'Regular',
        FontWeight.w500: 'Medium',
        FontWeight.w700: 'Bold',
      };
      final family = FontLoader('WingmanDiagnosticAll');
      for (final entry in faces.entries) {
        family.addFont(
          rootBundle.load('assets/fonts/Roboto-${entry.value}.ttf'),
        );
        await (FontLoader('WingmanDiagnostic${entry.value}')..addFont(
              rootBundle.load('assets/fonts/Roboto-${entry.value}.ttf'),
            ))
            .load();
      }
      await family.load();
      Future<Uint8List> raster(String fontFamily, FontWeight weight) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.white, BlendMode.src);
        final text = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: 'Wingman body 123 — AaBb',
            style: TextStyle(
              fontFamily: fontFamily,
              fontWeight: weight,
              color: Colors.black,
              fontSize: 28,
              height: 1.5,
            ),
          ),
        )..layout();
        text.paint(canvas, const Offset(8, 8));
        final picture = recorder.endRecording();
        final image = await picture.toImage(600, 80);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final result = Uint8List.fromList(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        text.dispose();
        return result;
      }

      final comparisons = <String, int>{};
      for (final entry in faces.entries) {
        final combined = await raster('WingmanDiagnosticAll', entry.key);
        final exact = await raster(
          'WingmanDiagnostic${entry.value}',
          entry.key,
        );
        comparisons[entry.value] = List.generate(
          combined.length,
          (i) => combined[i] == exact[i] ? 0 : 1,
        ).fold(0, (a, b) => a + b);
      }
      return comparisons;
    });
    expect(
      results,
      {'Regular': 0, 'Medium': 0, 'Bold': 0},
      reason:
          'Each weight should render identical pixels to its exact face loaded under a separate family.',
    );
  });
}
