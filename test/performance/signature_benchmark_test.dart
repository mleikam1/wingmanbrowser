import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/official_routes/official_route.dart';
import 'package:wingman_browser/signature/commit_review/commit_review.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bounded signature workloads report measured host timings', () async {
    final catalog = OfficialRouteCatalog.decode(
      await File('assets/signature/official_routes.json').readAsString(),
    );
    final store = MemorySignatureDocumentStore();
    final model = WorkspaceController(store: store, eligible: (_) => true);
    await model.initialize();
    for (final type in SpaceKind.values) {
      await model.createSpace(type);
    }
    for (var i = 0; i < 12; i++) {
      final task = await model.createTask('Synthetic timing goal $i');
      await model.associateTab(task, 'synthetic-tab-$i', 'moon-phases');
    }
    Future<Map<String, Object>> measure(
      String label,
      int samples,
      Future<void> Function() operation,
    ) async {
      final values = <int>[];
      for (var i = 0; i < samples; i++) {
        final watch = Stopwatch()..start();
        await operation();
        values.add(watch.elapsedMicroseconds);
      }
      values.sort();
      return {
        'operation': label,
        'samples': samples,
        'medianUs': values[values.length ~/ 2],
        'p95Us':
            values[(values.length * .95).floor().clamp(0, values.length - 1)],
      };
    }

    final results = [
      await measure('official-local-search-18', 100, () async {
        expect(catalog.search('support'), isNotEmpty);
      }),
      await measure('restore-3-spaces-12-tasks-memory-document', 30, () async {
        final restored = WorkspaceController(
          store: store,
          eligible: (_) => true,
        );
        await restored.initialize();
        expect(restored.snapshot.tasks.length, 12);
        restored.dispose();
      }),
      await measure('local-terms-analysis-practice', 30, () async {
        final report = await const CommitReviewAnalyzer().analyze(
          const CommitReviewInput(text: practiceTerms),
          checkedAt: DateTime.utc(2026, 9, 11),
        );
        expect(report.findings.length, 6);
      }),
      await measure('switch-12-in-memory-tabs-1000-times', 30, () async {
        final session = DiscoverySession();
        for (var i = 0; i < 11; i++) {
          session.tabs.add(DiscoveryTab());
        }
        for (var i = 0; i < 1000; i++) {
          session.active = i % 12;
          expect(session.current, isNotNull);
        }
        session.dispose();
      }),
    ];
    // Reproducible observed timings, not physical-device or rendering claims.
    // ignore: avoid_print
    print(
      'SIGNATURE_PERF ${jsonEncode({'host': Platform.operatingSystem, 'runtime': Platform.version, 'mode': 'flutter-test-host', 'results': results})}',
    );
    model.dispose();
  });
}
