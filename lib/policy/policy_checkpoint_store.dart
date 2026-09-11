import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'checkpoint_database_native.dart'
    if (dart.library.js_interop) 'checkpoint_database_web.dart';
import 'signed_policy_repository.dart';

abstract interface class PolicyCheckpointStore {
  Future<PolicyCheckpoint> load();
  Future<void> save(PolicyCheckpoint checkpoint);
  Future<void> close();
}

class SqlitePolicyCheckpointStore implements PolicyCheckpointStore {
  SqlitePolicyCheckpointStore({
    this.factory,
    this.databasePath = 'policy-trust.db',
  });
  final DatabaseFactory? factory;
  final String databasePath;
  Future<Database>? _database;
  Future<Database> get _db => _database ??= _open();
  Future<Database> _open() {
    final options = OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE trust(id INTEGER PRIMARY KEY CHECK(id=1),sequence INTEGER NOT NULL,seen_at INTEGER NOT NULL,revoked TEXT NOT NULL)',
        );
      },
    );
    return factory?.openDatabase(databasePath, options: options) ??
        openPolicyCheckpointDatabase(options);
  }

  PolicyCheckpoint _decode(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return PolicyCheckpoint();
    if (rows.length != 1) throw StateError('Invalid trust record');
    final row = rows.single;
    final sequence = row['sequence'] as int;
    final timestamp = row['seen_at'] as int;
    final ids = (jsonDecode(row['revoked'] as String) as List).cast<String>();
    if (sequence < 1 || ids.length > 10000 || timestamp <= 0) {
      throw StateError('Invalid trust record');
    }
    return PolicyCheckpoint(
      minimumSequence: sequence,
      seenAt: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      revokedIds: ids,
    );
  }

  @override
  Future<PolicyCheckpoint> load() async =>
      _decode(await (await _db).query('trust'));
  @override
  Future<void> save(PolicyCheckpoint checkpoint) async {
    final db = await _db;
    await db.transaction((txn) async {
      final old = _decode(await txn.query('trust'));
      final oldTime = old.seenAt?.millisecondsSinceEpoch ?? 0;
      final time = checkpoint.seenAt?.millisecondsSinceEpoch ?? oldTime;
      await txn.insert('trust', {
        'id': 1,
        'sequence': checkpoint.minimumSequence > old.minimumSequence
            ? checkpoint.minimumSequence
            : old.minimumSequence,
        'seen_at': time > oldTime ? time : oldTime,
        'revoked': jsonEncode(
          {...old.revokedIds, ...checkpoint.revokedIds}.toList()..sort(),
        ),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> close() async {
    await (await _database)?.close();
    _database = null;
  }
}

class MemoryPolicyCheckpointStore implements PolicyCheckpointStore {
  MemoryPolicyCheckpointStore([PolicyCheckpoint? checkpoint])
    : value = checkpoint ?? PolicyCheckpoint();
  PolicyCheckpoint value;
  @override
  Future<PolicyCheckpoint> load() async => value;
  @override
  Future<void> save(PolicyCheckpoint checkpoint) async {
    final old = value;
    value = PolicyCheckpoint(
      minimumSequence: checkpoint.minimumSequence > old.minimumSequence
          ? checkpoint.minimumSequence
          : old.minimumSequence,
      seenAt: old.seenAt != null && old.seenAt!.isAfter(checkpoint.seenAt!)
          ? old.seenAt
          : checkpoint.seenAt,
      revokedIds: {...old.revokedIds, ...checkpoint.revokedIds},
    );
  }

  @override
  Future<void> close() async {}
}
