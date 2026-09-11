import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../support/protected_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local catalog initialization and search measurement',
    () async {
      final initialization = <int>[];
      final searches = <int>[];
      for (var run = 0; run < 10; run++) {
        final watch = Stopwatch()..start();
        final policy = await loadTestPolicy();
        initialization.add(watch.elapsedMicroseconds);
        expect(policy.catalog.length, 18);
        for (var iteration = 0; iteration < 100; iteration++) {
          watch.reset();
          final result = policy.search(
            ['moon', 'drawing', 'support', 'unmatched'][iteration % 4],
          );
          searches.add(watch.elapsedMicroseconds);
          expect(result.length, lessThanOrEqualTo(18));
        }
        policy.dispose();
      }
      initialization.sort();
      searches.sort();
      // Development observations; no synthetic pass/fail performance threshold.
      // ignore: avoid_print
      print(
        jsonEncode({
          'label': 'host-test-development-microseconds',
          'initializations': 10,
          'queries': 1000,
          'init_p50_us': initialization[4],
          'init_p95_us': initialization[9],
          'query_p50_us': searches[499],
          'query_p95_us': searches[949],
        }),
      );
    },
    skip: !const bool.fromEnvironment('WINGMAN_CATALOG_BENCHMARK'),
  );
}
