import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import '../support/protected_test_support.dart';
import 'handoff_test.dart' show HandoffMemoryStore, HandoffFastDerivation;

void main() {
  for (final corrupt in [false, true]) {
    testWidgets(
      'actual application root never opens owner SQLite behind ${corrupt ? 'corrupt' : 'restored active'} handoff',
      (tester) async {
        final policy = (await tester.runAsync(loadTestPolicy))!;
        final store = HandoffMemoryStore();
        HandoffController controller() => HandoffController(
          store: store,
          discardIncoming: () async {},
          derivation: HandoffFastDerivation(),
          clock: () => DateTime.utc(2026, 9, 11, 12),
          capabilities: () async =>
              const HandoffCapabilities(staticSupported: true),
        )..attachPolicy(policy);
        if (corrupt) {
          store.value = '{"schema":999,"active":false}';
        } else {
          final preparing = controller();
          await preparing.initialize();
          final result = (await tester.runAsync(
            () => preparing.activate(
              preview: preparing.preview(['moon-phases'])!,
              code: '83197246',
              confirmation: '83197246',
            ),
          ))!;
          expect(result.success, isTrue);
          preparing.dispose();
        }
        final restored = controller();
        await restored.initialize();
        expect(restored.blocksOwner, isTrue);
        var ownerStorageCalls = 0;
        const sql = MethodChannel('com.tekartik.sqflite');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sql, (call) async {
              ownerStorageCalls++;
              throw StateError('Owner database must not be opened');
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(sql, null),
        );
        await tester.pumpWidget(
          SignatureApplicationRoot(
            policy: policy,
            handoff: restored,
            handoffJournal: PrivacyJournal(
              sessionKind: PrivacySessionKind.handoff,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WingmanApp), findsNothing);
        expect(find.text('Your Spaces'), findsNothing);
        expect(ownerStorageCalls, 0);
        if (!corrupt) {
          final denied = (await tester.runAsync(
            () => restored.unlock('11111111'),
          ))!;
          expect(denied.success, isFalse);
          await tester.pumpAndSettle();
          expect(find.byType(WingmanApp), findsNothing);
          expect(ownerStorageCalls, 0);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
