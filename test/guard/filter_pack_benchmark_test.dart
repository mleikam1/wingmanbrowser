import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'guard_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '100k-rule indexed lookup and bounded working set measurement',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'wingman-guard-benchmark-',
      );
      final path = '${directory.path}/guard.db';
      final signer = await TestSigner.create();
      final records = [
        for (var i = 0; i < 100000; i++)
          testRule('host-${i.toString().padLeft(6, '0')}.benchmark.test'),
      ];
      final signed = await signer.sign(records);
      records.clear();
      SqliteFilterPackRepository create() => SqliteFilterPackRepository(
        factory: databaseFactoryFfi,
        databasePath: path,
        verifier: signer.verifier,
        installBundled: false,
        clock: () => testTime,
      );
      var repo = create();
      try {
        await repo.init();
        final beforeImportRss = ProcessInfo.currentRss;
        final timer = Stopwatch()..start();
        await repo.importVerified(signed.manifest, signed.pack);
        final importMs = timer.elapsedMicroseconds / 1000;
        final afterImportRss = ProcessInfo.currentRss;
        await repo.close();
        repo = create();
        timer.reset();
        await repo.init();
        final reopenMs = timer.elapsedMicroseconds / 1000;
        expect(repo.status.integrityVerified, true);
        expect(repo.status.ruleCount, 100000);
        Future<List<int>> measure(bool cached) async {
          final values = <int>[];
          for (var i = 0; i < 1000; i++) {
            final number = cached ? 42 : (i * 97) % 100000;
            final host =
                'sub.host-${number.toString().padLeft(6, '0')}.benchmark.test';
            timer.reset();
            final result = await repo.lookupHost(host, useCache: cached);
            values.add(timer.elapsedMicroseconds);
            expect(result, hasLength(1));
          }
          return values..sort();
        }

        final cold = await measure(false);
        final warm = await measure(true);
        final beforeChurnRss = ProcessInfo.currentRss;
        for (var i = 0; i < 2000; i++) {
          await repo.lookupHost('tab-$i.example.test');
        }
        expect(
          repo.cachedHostCount,
          SqliteFilterPackRepository.maximumCachedHosts,
        );
        final afterChurnRss = ProcessInfo.currentRss;
        final db = await databaseFactoryFfi.openDatabase(path);
        final queryPlan = await db.rawQuery(
          '''EXPLAIN QUERY PLAN SELECT r.host,r.kind FROM guard_rules r
        JOIN guard_state s ON s.id=1 AND r.generation=s.active_generation
        WHERE r.host IN (?,?,?) AND (r.include_subdomains=1 OR r.host=?)''',
          [
            'sub.host-000042.benchmark.test',
            'host-000042.benchmark.test',
            'benchmark.test',
            'sub.host-000042.benchmark.test',
          ],
        );
        final detail = queryPlan.map((r) => r['detail']).join(' | ');
        expect(detail, contains('PRIMARY KEY'));
        expect(detail, isNot(contains('SCAN r')));
        final verifyPlan = await db.rawQuery(
          '''EXPLAIN QUERY PLAN SELECT host,kind,category FROM guard_rules
        WHERE generation=? AND host>=? AND (host>? OR (host=? AND kind>?) OR (host=? AND kind=? AND category>?))
        ORDER BY host,kind,category LIMIT 500''',
          [
            1,
            'host-040000.benchmark.test',
            'host-040000.benchmark.test',
            'host-040000.benchmark.test',
            'category',
            'host-040000.benchmark.test',
            'category',
            'adult',
          ],
        );
        final output = {
          'environment':
              'Flutter host test, macOS ${Platform.operatingSystemVersion}, ${Platform.version}',
          'note':
              'Debug host FFI measurement, not mobile hardware benchmark. RSS includes Flutter test VM, signing fixture construction and allocator history; deltas do not isolate repository memory.',
          'rules': 100000,
          'packBytes': signed.pack.length,
          'databaseBytes': await File(path).length(),
          'importIncludingVerificationMs': importMs,
          'reopenSignedArchiveAndIndexVerificationMs': reopenMs,
          'lookupSamplesEach': 1000,
          'uncachedLookupUs': {
            'p50': cold[500],
            'p95': cold[950],
            'max': cold.last,
          },
          'warmLookupUs': {
            'p50': warm[500],
            'p95': warm[950],
            'max': warm.last,
          },
          'cachedHostLimit': repo.cachedHostCount,
          'cacheTtlSeconds': 600,
          'rssBytes': {
            'beforeImport': beforeImportRss,
            'afterImport': afterImportRss,
            'before2000HostChurn': beforeChurnRss,
            'after2000HostChurn': afterChurnRss,
          },
          'lookupQueryPlan': queryPlan,
          'integrityQueryPlan': verifyPlan,
        };
        final json = const JsonEncoder.withIndent('  ').convert(output);
        // ignore: avoid_print
        print(json);
        const outputPath = String.fromEnvironment('GUARD_BENCHMARK_OUTPUT');
        if (outputPath.isNotEmpty) {
          await File(outputPath).writeAsString('$json\n');
        }
      } finally {
        await repo.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('GUARD_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
