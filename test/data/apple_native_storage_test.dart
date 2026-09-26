import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/database_native.dart';
import 'package:wingman_browser/guard/guard_database_native.dart';
import 'package:wingman_browser/policy/checkpoint_database_native.dart';
import 'package:wingman_browser/policy/consumer_update_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('wingman/browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late DatabaseFactory? previousFactory;
  final calls = <MethodCall>[];

  setUp(() async {
    previousFactory = databaseFactoryOrNull;
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('wingman-apple-store-');
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'localDataDirectory') return directory.path;
      throw MissingPluginException();
    });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    databaseFactory = previousFactory;
    await directory.delete(recursive: true);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
      '$platform stores use the explicit native Application Support path',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final opened = <Database>[];
        final updates = SqliteConsumerUpdateStore();
        try {
          opened.add(await openLocalDatabase(OpenDatabaseOptions()));
          opened.add(await openGuardDatabase(OpenDatabaseOptions()));
          opened.add(await openPolicyCheckpointDatabase(OpenDatabaseOptions()));
          expect(opened.map((db) => db.path), [
            path.join(directory.path, 'wingman.db'),
            path.join(directory.path, 'guard.db'),
            path.join(directory.path, 'policy-trust.db'),
          ]);
          await updates.write(ConsumerCacheState(highestSequence: 7));
          await updates.close();
          expect((await updates.load()).highestSequence, 7);
          expect(
            File(
              path.join(directory.path, 'consumer-protection-updates.db'),
            ).existsSync(),
            isTrue,
          );
          expect(
            calls,
            hasLength(5),
          ); // Four opens and one explicit update reopen.
          expect(
            calls.every((call) => call.method == 'localDataDirectory'),
            isTrue,
          );
        } finally {
          for (final db in opened) {
            await db.close();
          }
          await updates.close();
        }
      },
    );

    for (final invalid in [null, '']) {
      test(
        '$platform missing native directory $invalid does not fall back',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          messenger.setMockMethodCallHandler(channel, (_) async => invalid);
          await expectLater(
            openLocalDatabase(OpenDatabaseOptions()),
            throwsStateError,
          );
          await expectLater(
            openGuardDatabase(OpenDatabaseOptions()),
            throwsStateError,
          );
          await expectLater(
            openPolicyCheckpointDatabase(OpenDatabaseOptions()),
            throwsStateError,
          );
          await expectLater(
            SqliteConsumerUpdateStore().load(),
            throwsStateError,
          );
          expect(directory.listSync(), isEmpty);
        },
      );
    }
  }

  test('macOS native storage channel failure stays closed', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'application_support_unavailable');
    });
    final platformError = isA<PlatformException>().having(
      (error) => error.code,
      'code',
      'application_support_unavailable',
    );
    await expectLater(
      openLocalDatabase(OpenDatabaseOptions()),
      throwsA(platformError),
    );
    await expectLater(
      openGuardDatabase(OpenDatabaseOptions()),
      throwsA(platformError),
    );
    await expectLater(
      openPolicyCheckpointDatabase(OpenDatabaseOptions()),
      throwsA(platformError),
    );
    await expectLater(
      SqliteConsumerUpdateStore().load(),
      throwsA(platformError),
    );
    expect(directory.listSync(), isEmpty);
  });
}
