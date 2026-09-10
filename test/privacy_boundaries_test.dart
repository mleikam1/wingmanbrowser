import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/monetization/home_ad_slot.dart';
import 'package:wingman_browser/privacy/diagnostic_sanitizer.dart';
import 'package:wingman_browser/privacy/product_analytics.dart';

class SensitiveException implements Exception {
  @override
  String toString() => throw StateError('Raw exception must never be read');
}

void main() {
  test(
    'diagnostics drop host, credentials, searches, fragments and raw errors',
    () {
      const secret =
          'https://user:password@medical.example/results?query=private#token';
      expect(
        DiagnosticSanitizer.transport(Uri.parse(secret)),
        NavigationTransport.https,
      );
      expect(
        DiagnosticSanitizer.failure(
          DiagnosticCode.networkFailure,
          cause: SensitiveException(),
        ),
        'networkFailure',
      );
      expect(
        DiagnosticSanitizer.failure(
          DiagnosticCode.networkFailure,
          cause: secret,
        ),
        isNot(contains('medical')),
      );
    },
  );

  test('optional counters exclude private events and retain totals only', () {
    final counters = LocalAggregateCounters();
    counters.record(ProductEvent.normalTabOpened, isPrivate: false);
    counters.record(ProductEvent.normalTabOpened, isPrivate: false);
    counters.record(ProductEvent.normalTabOpened, isPrivate: true);
    counters.record(ProductEvent.bookmarkCreated, isPrivate: true);
    expect(counters.counts, {ProductEvent.normalTabOpened: 2});
    expect(() => counters.counts.clear(), throwsUnsupportedError);
    counters.clear();
    expect(counters.counts, isEmpty);
  });

  testWidgets('ads disabled by default reserve no space or call native SDK', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            HomeAdSlot(isPrivate: false),
            Text('Browser content is immediately below'),
          ],
        ),
      ),
    );
    expect(find.text('Load test advertisement'), findsNothing);
    expect(tester.getSize(find.byType(HomeAdSlot)).height, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private Home never displays the ad demo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeAdSlot(isPrivate: true)),
    );
    expect(find.text('Load test advertisement'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
