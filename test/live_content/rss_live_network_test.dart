import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/eligibility.dart';
import 'package:wingman_browser/live_content/models.dart';
import 'package:wingman_browser/live_content/rss_provider.dart';
import 'package:wingman_browser/policy/consumer_protection_policy.dart';

// Explicit opt-in only. This exercises the same DNS-pinned native transport
// without Flutter's widget-test HTTP mock. No cookies, UI or user data is used.
class _ActualHttp extends HttpOverrides {}

void main() {
  test(
    'approved native RSS publishers produce an eligible bounded snapshot',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final registry = LiveSourceRegistry.fromJson(
        feedMap(
          jsonDecode(
            await File('assets/live_content/sources.json').readAsString(),
          ),
        ),
      );
      final policy = await ConsumerProtectionPolicy.verifyBytes(
        await File(ConsumerProtectionPolicy.assetPath).readAsBytes(),
      );
      expect(policy.isUsable, isTrue);
      final eligibility = LiveContentEligibility(
        registry: registry,
        canOpenDestination: (uri) => policy.assessNavigation(uri).isAllowed,
      );
      final provider = RssFeedProvider(
        registry: registry,
        eligibility: eligibility,
        allowsEditorialText: eligibility.acceptsFeedText,
      );
      final directory = Directory('work/rss-direct')
        ..createSync(recursive: true);
      final snapshotFile = File('${directory.path}/snapshot.json');
      final stateFile = File('${directory.path}/state.json');
      provider.restore(
        snapshot: await snapshotFile.exists()
            ? LiveSnapshot.fromJson(
                feedMap(jsonDecode(await snapshotFile.readAsString())),
              )
            : null,
        state: await stateFile.exists()
            ? feedMap(jsonDecode(await stateFile.readAsString()))
            : null,
      );
      final stopwatch = Stopwatch()..start();
      final response = await provider.fetch();
      stopwatch.stop();
      final snapshot = response.snapshot!;
      // Store the approved attempt's rate-limit checkpoint even on an outage.
      await stateFile.writeAsString(jsonEncode(response.providerState));
      await snapshotFile.writeAsString(jsonEncode(snapshot.toJson()));
      final topics = <String, int>{};
      for (final item in snapshot.items) {
        for (final topic in item.topics) {
          topics[topic] = (topics[topic] ?? 0) + 1;
        }
      }
      final report = {
        'generatedAt': snapshot.generatedAt.toIso8601String(),
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'snapshotBytes': await snapshotFile.length(),
        'itemCount': snapshot.items.length,
        'rejectedCount': snapshot.rejectedItems,
        'topics': topics,
        'sources': snapshot.sources
            .map(
              (source) => {
                'id': source.id,
                'status': source.status,
                'itemCount': snapshot.items
                    .where((item) => item.sourceId == source.id)
                    .length,
                'lastSuccessAt': source.lastSuccessAt?.toIso8601String(),
                'nextRefreshAt': source.nextRefreshAt?.toIso8601String(),
                'error':
                    (feedMap(response.providerState!['sources'])[source.id]
                        as Map)['error'],
              },
            )
            .toList(),
        'warning': response.warning,
      };
      await File(
        '${directory.path}/report.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      // Reporter output includes only counts/statuses, never raw feed content.
      // ignore: avoid_print
      print(jsonEncode(report));
      expect(snapshot.sources, hasLength(registry.sources.length));
      expect(snapshot.items, isNotEmpty);
      expect(snapshot.items.length, lessThanOrEqualTo(300));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 50)));
      expect(
        snapshot.items.every(
          (item) => eligibility.accepts(item, now: DateTime.now().toUtc()),
        ),
        isTrue,
      );
      expect(snapshot.items.every((item) => item.imageUrl == null), isTrue);
      provider.cancel();
    }, _ActualHttp()),
    skip: !const bool.fromEnvironment('WINGMAN_RSS_LIVE_VERIFY'),
    timeout: const Timeout(Duration(seconds: 75)),
  );
}
