import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/branding.dart';
import 'package:wingman_browser/presentation/live_content/publisher_identity.dart';
import 'package:wingman_browser/presentation/theme.dart';

import '../live_content/branding_test.dart' show reviewedBranding;

class _BrandBundle extends CachingAssetBundle {
  final requested = <String>[];
  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    if (key.startsWith('assets/publisher_logos/fixture')) {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwKFjwHwAEVAJA4zks+QAAAABJRU5ErkJggg==',
      );
      return ByteData.sublistView(bytes);
    }
    return rootBundle.load(key);
  }
}

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: WingmanTheme.make(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  testWidgets(
    'unapproved publishers have neutral initials and a readable name, never a remote logo',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const LivePublisherIdentity(name: 'Fixture Science Publisher')),
      );
      expect(find.text('Fixture Science Publisher'), findsOneWidget);
      expect(find.text('FS'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Neutral publisher initials for Fixture Science Publisher',
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      semantics.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'reviewed ${brightness.name} logo preserves aspect/colors with long names at 200%',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bundle = _BrandBundle();
        final brand = PublisherBranding.tryFromJson(reviewedBranding())!;
        const name =
            'A Long Fixture Publisher Name for Science and International Reporting';
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: bundle,
            child: _app(
              LivePublisherIdentity(
                name: name,
                branding: brand,
                sponsored: true,
                now: DateTime.utc(2026, 9, 15),
              ),
              brightness: brightness,
              scale: 2,
            ),
          ),
        );
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.fit, BoxFit.contain);
        expect(image.color, isNull);
        expect(
          (image.image as AssetImage).assetName,
          brand.assetFor(dark: brightness == Brightness.dark),
        );
        expect(find.text('Sponsored feature · $name'), findsOneWidget);
        expect(find.text('Fixture publisher'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'expired and missing approved logos return the honest initials fallback',
    (tester) async {
      final brand = PublisherBranding.tryFromJson(reviewedBranding())!;
      await tester.pumpWidget(
        _app(
          LivePublisherIdentity(
            name: 'Fixture Publisher',
            branding: brand,
            now: DateTime.utc(2026, 10, 1),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('FP'), findsOneWidget);
      final absent = PublisherBranding.tryFromJson({
        ...reviewedBranding(),
        'asset': 'assets/publisher_logos/absent.png',
      })!;
      await tester.pumpWidget(
        _app(
          LivePublisherIdentity(
            name: 'Fixture Publisher',
            branding: absent,
            now: DateTime.utc(2026, 9, 15),
          ),
        ),
      );
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('publisher-initials-Fixture Publisher')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
