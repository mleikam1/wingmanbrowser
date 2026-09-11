import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wingman_browser/data/database_close_coordinator.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/policy/policy_checkpoint_store.dart';

class _ClosingDatabase implements Database {
  _ClosingDatabase(this.onClose);
  final Future<void> Function() onClose;
  @override
  Future<void> close() => onClose();
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #query || call.memberName == #rawQuery) {
      return Future.value(<Map<String, Object?>>[]);
    }
    return super.noSuchMethod(call);
  }
}

class _ClosingFactory implements DatabaseFactory {
  _ClosingFactory(this.databases);
  final Map<String, Database> databases;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => databases[path]!;
  @override
  dynamic noSuchMethod(Invocation call) => super.noSuchMethod(call);
}

void main() {
  test(
    'browser and policy owners await one native close before dispatching the next',
    () async {
      final firstEntered = Completer<void>(), releaseFirst = Completer<void>();
      final operations = <String>[];
      var outstanding = 0;
      Future<void> close(String owner) async {
        outstanding++;
        expect(
          outstanding,
          1,
          reason: 'Native final closes must never overlap.',
        );
        operations.add('$owner:start');
        if (owner == 'browser') {
          firstEntered.complete();
          await releaseFirst.future;
        }
        operations.add('$owner:completed');
        outstanding--;
      }

      final factory = _ClosingFactory({
        'browser': _ClosingDatabase(() => close('browser')),
        'policy': _ClosingDatabase(() => close('policy')),
      });
      final browser = SqliteBrowserRepository(
        factory: factory,
        databasePath: 'browser',
      );
      final policy = SqlitePolicyCheckpointStore(
        factory: factory,
        databasePath: 'policy',
      );
      await browser.readDocument('workspace');
      await policy.load();
      final browserClose = browser.close();
      final policyClose = policy.close();
      await firstEntered.future;
      await Future<void>.delayed(Duration.zero);
      expect(operations, ['browser:start']);
      releaseFirst.complete();
      await Future.wait([browserClose, policyClose]);
      expect(operations, [
        'browser:start',
        'browser:completed',
        'policy:start',
        'policy:completed',
      ]);
      expect(outstanding, 0);
      await Future.wait([browser.close(), policy.close()]);
      expect(
        operations,
        hasLength(4),
        reason: 'Closed owners do not dispatch again.',
      );
    },
  );

  test(
    'close failure reaches its caller while the next owner still progresses',
    () async {
      final queue = DatabaseCloseCoordinator();
      final entered = Completer<void>(), release = Completer<void>();
      var nextCompleted = false;
      final failure = StateError('Synthetic close failure');
      final first = queue.run(() async {
        entered.complete();
        await release.future;
        throw failure;
      });
      final observedFailure = expectLater(first, throwsA(same(failure)));
      final second = queue.run(() async {
        nextCompleted = true;
      });
      await entered.future;
      expect(nextCompleted, isFalse);
      release.complete();
      await Future.wait([observedFailure, second]);
      expect(nextCompleted, isTrue);
    },
  );
}
