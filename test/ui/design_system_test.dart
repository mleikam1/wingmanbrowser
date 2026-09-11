import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/presentation/design_system/app_build_info.dart';
import '../../tool/ui_gallery.dart';

void main() {
  test('semantic text and control roles meet handoff contrast targets', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    for (final t in [WingmanTokens.light, WingmanTokens.dark]) {
      for (final surface in [t.canvas, t.surface, t.raised]) {
        expect(contrast(t.text, surface), greaterThanOrEqualTo(4.5));
        expect(contrast(t.secondaryText, surface), greaterThanOrEqualTo(4.5));
        expect(contrast(t.controlOutline, surface), greaterThanOrEqualTo(3));
      }
      expect(contrast(t.action, t.onAction), greaterThanOrEqualTo(4.5));
      expect(contrast(t.success, t.successSurface), greaterThanOrEqualTo(4.5));
      expect(contrast(t.caution, t.cautionSurface), greaterThanOrEqualTo(4.5));
      expect(contrast(t.danger, t.dangerSurface), greaterThanOrEqualTo(4.5));
    }
  });
  test(
    'display version matches the actual pubspec and brand originals remain exact',
    () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains(
          'version: ${AppBuildInfo.current.version}+${AppBuildInfo.current.build}',
        ),
      );
      expect(
        File(
          'assets/brand/source/wingman-logo-reference.png',
        ).readAsBytesSync(),
        File(
          'Wingman_UI_Design_Handoff/wingman-logo-reference.png',
        ).readAsBytesSync(),
      );
      expect(
        File('assets/brand/wingman-mark.png').readAsBytesSync(),
        File(
          'Wingman_UI_Design_Handoff/wingman-logo-cropped.png',
        ).readAsBytesSync(),
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'component reflow ${brightness.name}, all handoff widths and 200% text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final width in [
          320.0,
          360.0,
          390.0,
          430.0,
          600.0,
          768.0,
          1024.0,
          1440.0,
        ]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 640);
            await tester.pumpWidget(
              MaterialApp(
                theme: WingmanTheme.make(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const WingmanPage(
                  title: 'Component states',
                  child: WingmanComponentGallery(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$width / $scale / $brightness',
            );
            final button = tester.getRect(
              find.widgetWithText(FilledButton, 'Try an action'),
            );
            expect(button.height, greaterThanOrEqualTo(52));
          }
        }
      },
    );
  }
}
