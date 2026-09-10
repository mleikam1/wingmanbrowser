import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/guard_pin/guard_pin_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native protected PIN verifier survives service replacement',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Guard PIN verification'))),
      );
      final store = PlatformGuardPinStore.forTesting();
      expect(store.supported, isTrue);
      // This adapter has a separate fixed test key, never the production key.
      await store.delete();
      final service = GuardPinService(store: store);
      final watch = Stopwatch()..start();
      try {
        await service.initialize();
        expect(service.status, GuardPinStatus.notConfigured);
        expect((await service.setPin('761935')).success, isTrue);
        final record = await store.read();
        expect(record, isNotNull);
        expect(record, isNot(contains('761935')));
        expect((jsonDecode(record!) as Map)['iterations'], 600000);
        expect(service.isLocked, isTrue);

        final replacement = GuardPinService(store: store);
        try {
          await replacement.initialize();
          expect(replacement.status, GuardPinStatus.locked);
          expect(
            (await replacement.unlock('000000')).reason,
            GuardPinReason.incorrectPin,
          );
          expect(replacement.isLocked, isTrue);
          expect((await replacement.unlock('761935')).success, isTrue);
          replacement.lock();
          expect(replacement.isLocked, isTrue);
          expect((await replacement.removePin('761935')).success, isTrue);
          expect(await store.read(), isNull);
        } finally {
          replacement.dispose();
        }
        watch.stop();
        // Fixed booleans and duration only; no credential, identifiers or URLs.
        // ignore: avoid_print
        print(
          'WINGMAN_PIN_SMOKE_RESULT ${jsonEncode({'platform': defaultTargetPlatform.name, 'secureStoreRoundTrip': true, 'serviceReplacementLocked': true, 'wrongPinDenied': true, 'plaintextAbsent': true, 'testKeyRemoved': true, 'durationMs': watch.elapsedMilliseconds})}',
        );
      } finally {
        service.dispose();
        await store.delete();
      }
    },
    skip:
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS),
  );
}
