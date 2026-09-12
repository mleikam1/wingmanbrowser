
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../data/database_close_coordinator.dart';

final class CachedConsumerRelease {
  CachedConsumerRelease(Uint8List envelope, Uint8List data)
    : envelope = Uint8List.fromList(envelope).asUnmodifiableView(),
      data = Uint8List.fromList(data).asUnmodifiableView();
  final Uint8List envelope, data;
}

final class ConsumerCacheState {
  ConsumerCacheState({
    this.highestSequence = 1,
    this.activeSequence,
    this.previousSequence,
    this.pendingSequence,
    this.lastCheck,
    Map<int, CachedConsumerRelease> releases = const {},
  }) : releases = Map.unmodifiable(releases);
  final int highestSequence;
  final int? activeSequence, previousSequence, pendingSequence;
  final DateTime? lastCheck;
  final Map<int, CachedConsumerRelease> releases;

  void validate() {
    if (highestSequence < 1 ||
        highestSequence > 2147483647 ||
        releases.length > 3 ||
        releases.keys.any((value) => value < 2 || value > 2147483647) ||
        [
          activeSequence,
          previousSequence,
          pendingSequence,
        ].whereType<int>().any((sequence) => !releases.containsKey(sequence)) ||
        (activeSequence != null && activeSequence! > highestSequence) ||
        (previousSequence != null && previousSequence! > highestSequence)) {
      throw StateError('Invalid consumer update cache.');
    }
  }
}

abstract interface class ConsumerUpdateStore {
  Future<ConsumerCacheState> load();
  Future<void> write(ConsumerCacheState state);
  Future<void> close();
}

class MemoryConsumerUpdateStore implements ConsumerUpdateStore {
  ConsumerCacheState state = ConsumerCacheState();
  @override
  Future<ConsumerCacheState> load() async => state;
  @override
  Future<void> write(ConsumerCacheState value) async {
    value.validate();
    state = value;
  }

  @override
  Future<void> close() async {}
}

/// The pointer, high-water sequence, pending release and blobs are one SQLite
/// transaction. A killed writer exposes either the previous or next state.
class SqliteConsumerUpdateStore implements ConsumerUpdateStore {
  SqliteConsumerUpdateStore({this.factory, this.databasePath});
  final DatabaseFactory? factory;
  final String? databasePath;
  Future<Database>? _database;
  Future<Database> get _db => _database ??= _open();

  Future<Database> _open() async {
    var target = databasePath;
    if (target == null) {
      final String directory;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final value = await const MethodChannel(
          'wingman/browser',
        ).invokeMethod<String>('localDataDirectory');
        if (value == null || value.isEmpty) {
          throw StateError('No local update store.');
        }
        directory = value;
      } else {
        directory = await getDatabasesPath();
      }
      target = path.join(directory, 'consumer-protection-updates.db');
    }
    return (factory ?? databaseFactory).openDatabase(
      target,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE consumer_state (id INTEGER PRIMARY KEY CHECK(id=1), highest_sequence INTEGER NOT NULL, active_sequence INTEGER, previous_sequence INTEGER, pending_sequence INTEGER, last_check INTEGER)',
          );
          await db.insert('consumer_state', {'id': 1, 'highest_sequence': 1});
          await db.execute(
            'CREATE TABLE consumer_releases (sequence INTEGER PRIMARY KEY, envelope BLOB NOT NULL, data BLOB NOT NULL)',
          );
        },
      ),
    );
  }

  @override
  Future<ConsumerCacheState> load() async {
    final db = await _db;
    return db.transaction((txn) async {
      final row = (await txn.query('consumer_state')).single;
      final blobs = await txn.query('consumer_releases');
      final timestamp = row['last_check'] as int?;
      final state = ConsumerCacheState(
        highestSequence: row['highest_sequence'] as int,
        activeSequence: row['active_sequence'] as int?,
        previousSequence: row['previous_sequence'] as int?,
        pendingSequence: row['pending_sequence'] as int?,
        lastCheck: timestamp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        releases: {
          for (final blob in blobs)
            blob['sequence'] as int: CachedConsumerRelease(
              Uint8List.fromList(blob['envelope'] as List<int>),
              Uint8List.fromList(blob['data'] as List<int>),
            ),
        },
      );
      state.validate();
      return state;
    });
  }

  @override
  Future<void> write(ConsumerCacheState state) async {
    state.validate();
    await (await _db).transaction((txn) async {
      await txn.delete('consumer_releases');
      for (final release in state.releases.entries) {
        await txn.insert('consumer_releases', {
          'sequence': release.key,
          'envelope': release.value.envelope,
          'data': release.value.data,
        });
      }
      await txn.update('consumer_state', {
        'highest_sequence': state.highestSequence,
        'active_sequence': state.activeSequence,
        'previous_sequence': state.previousSequence,
        'pending_sequence': state.pendingSequence,
        'last_check': state.lastCheck?.millisecondsSinceEpoch,
      }, where: 'id=1');
    });
  }

  @override
  Future<void> close() async {
    final database = _database;
    if (database == null) return;
    await databaseCloseCoordinator.run(() async => (await database).close());
    if (identical(_database, database)) _database = null;
  }
}
