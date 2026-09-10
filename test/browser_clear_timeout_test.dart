import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/browser_engine.dart';

void main() {
  testWidgets(
    'a late native clear cannot report success or race new page writes',
    (tester) async {
      const channel = MethodChannel('wingman/browser');
      final pending = Completer<void>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'clearData') {
              calls++;
              await pending.future;
            }
            return null;
          });
      final notices = <String>[];
      final engine = BrowserEnginePool(
        confirm: (_, _) async => false,
        prompt: (_, _, _) async => null,
        onPageChanged: (_, _, _, _) {},
        onMessage: notices.add,
      );
      final clear = engine.clearData(
        cookies: false,
        cache: true,
        storage: false,
      );
      final failure = expectLater(clear, throwsA(isA<TimeoutException>()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      await failure;
      expect(engine.isClearingSiteData, isTrue);
      await engine.open(
        tabId: 'paused',
        url: 'https://example.test',
        isPrivate: false,
      );
      expect(engine.liveEngineCount, 0);
      expect(notices.single, contains('still being cleared'));
      expect(calls, 1);
      await expectLater(
        engine.clearData(cookies: true, cache: false, storage: false),
        throwsA(isA<StateError>()),
      );
      expect(
        calls,
        1,
        reason:
            'A different retry must not succeed with the earlier narrower deletion',
      );
      pending.complete();
      await tester.pump();
      expect(engine.isClearingSiteData, isFalse);
      engine.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
