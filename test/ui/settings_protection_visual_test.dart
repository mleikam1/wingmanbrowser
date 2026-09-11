import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/presentation/protection/protection_screen.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';
import 'package:wingman_browser/presentation/design_system/app_build_info.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('WINGMAN_GPL_UI_CAPTURES');
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'settings protection and library actual capture ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final policy = (await tester.runAsync(loadTestPolicy))!;
        final state = BrowserState(
          repository: MemoryBrowserRepository(),
          policyRuntime: policy,
        );
        await state.init();
        await state.setResourceBookmarked('moon-phases', true);
        final key = GlobalKey();
        final pages = <String, Widget>{
          'g01': SettingsScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
            buildInfo: AppBuildInfo.current,
            actions: SettingsActions(
              onHomeCustomization: () {},
              onSpaces: () {},
              onProtection: () {},
              onReceipt: () {},
              onCompatibility: () {},
              onClearData: (_) async => DataClearOutcome(),
              clearableCategories: {},
            ),
          ),
          'p01': ProtectionScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
            onReceipt: () {},
            onRequestReview: () {},
            onOpenApprovedResource: (_) {},
            onHome: () {},
          ),
          'l02': LibraryScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
            onOpenApprovedResource: (_) {},
            initialSection: LibrarySection.bookmarks,
          ),
        };
        for (final scale in [1.0, 2.0]) {
          for (final width
              in scale == 1
                  ? [390.0]
                  : [
                      320.0,
                      360.0,
                      390.0,
                      430.0,
                      600.0,
                      768.0,
                      1024.0,
                      1440.0,
                    ]) {
            tester.view.physicalSize = Size(width, 812);
            for (final entry in pages.entries) {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: WingmanTheme.make(brightness),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    initialRoute: '/scene',
                    routes: {
                      '/': (_) => const SizedBox(),
                      '/scene': (_) => entry.value,
                    },
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${entry.key} $width $scale $brightness',
              );
              expect(find.byType(WingmanPage), findsOneWidget);
              if (capture && scale == 1) {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    'docs/ui/screenshots/gpl-${entry.key}-${brightness.name}.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.pumpWidget(const SizedBox());
            }
          }
        }
        state.dispose();
        policy.dispose();
      },
    );
  }
}
