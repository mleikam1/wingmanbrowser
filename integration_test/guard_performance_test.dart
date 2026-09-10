import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wingman_browser/browser/browser_engine.dart';

// Isolated unsigned synthetic SQLite is copied only into this debug test's path
// by the validation runner. Production imports always verify signed manifests.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('100k native rules and three browser views on Android', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    const channel = MethodChannel('wingman/browser');
    final path = '${await getDatabasesPath()}/guard-native-perf.db';
    expect(
      await File(path).exists(),
      true,
      reason:
          'Install isolated synthetic performance fixture before this debug test.',
    );
    final engine = BrowserEnginePool(
      confirm: (_, _) async => false,
      prompt: (_, _, _) async => null,
      onPageChanged: (_, _, _, _) {},
      onMessage: (_) {},
    );
    await engine.updateGuardPolicy({
      'databasePath': path,
      'guardEnabled': true,
      'enabledCategories': ['adult'],
      'trackingEnabled': true,
      'trackerDomains': ['localhost'],
      'trackerVersion': 'perf-fixture',
    });
    debugPrint(
      'PERF native100k ${await channel.invokeMethod<Map>('guardBenchmarkForTesting')}',
    );
    debugPrint(
      'PERF idle ${await channel.invokeMethod<Map>('memoryForTesting')}',
    );
    if (const bool.fromEnvironment('LOOKUP_ONLY')) {
      debugPrint(
        'PERF native100kRepeat ${await channel.invokeMethod<Map>('guardBenchmarkForTesting')}',
      );
      await engine.updateGuardPolicy({});
      engine.dispose();
      await deleteDatabase(path);
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Performance fixture</title></head><body><h1>Lightweight browser performance fixture</h1><p>Local browser view rendering.</p></body></html>',
      );
      await request.response.close();
    });
    var active = 'tab-0';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: engine,
            builder: (_, _) {
              final ids = engine.liveTabIds;
              return ids.isEmpty
                  ? const SizedBox()
                  : IndexedStack(
                      index: ids.indexOf(active).clamp(0, ids.length - 1),
                      children: [for (final id in ids) engine.view(id)!],
                    );
            },
          ),
        ),
      ),
    );
    final loadTimes = <int>[];
    for (var i = 0; i < 3; i++) {
      active = 'tab-$i';
      final watch = Stopwatch()..start();
      await engine.open(
        tabId: active,
        url: 'http://127.0.0.1:${server.port}/page-$i',
        isPrivate: false,
      );
      while (engine.status(active).isLoading && watch.elapsed.inSeconds < 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(engine.status(active).error, isNull);
      expect(engine.status(active).isLoading, false);
      loadTimes.add(watch.elapsedMilliseconds);
    }
    await tester.pump(const Duration(milliseconds: 500));
    final switches = <int>[];
    for (var i = 0; i < 30; i++) {
      final watch = Stopwatch()..start();
      active = 'tab-${i % 3}';
      engine.activate(active);
      await tester.pump();
      switches.add(watch.elapsedMicroseconds);
    }
    switches.sort();
    debugPrint(
      'PERF loadsMs=$loadTimes switchP50Micros=${switches[15]} switchP95Micros=${switches[28]} liveViews=${engine.liveEngineCount}',
    );
    debugPrint(
      'PERF threeViews ${await channel.invokeMethod<Map>('memoryForTesting')}',
    );
    debugPrint('PERF THREE VIEWS READY');
    // Brief inspection window for adb's complete app/renderer memory snapshot.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(const SizedBox());
    for (final id in engine.liveTabIds) {
      await engine.close(id);
    }
    await engine.updateGuardPolicy({});
    engine.dispose();
    await server.close(force: true);
    await deleteDatabase(path);
  });
}
