import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'domain_normalizer.dart';
import 'filter_pack_repository.dart';
import 'guard_database_native.dart'
    if (dart.library.js_interop) 'guard_database_web.dart';
import 'guard_models.dart';
import 'signed_filter_manifest.dart';

class SqliteFilterPackRepository implements FilterPackRepository {
  SqliteFilterPackRepository({
    this.factory,
    this.databasePath = 'guard.db',
    FilterManifestVerifier? verifier,
    AssetBundle? bundle,
    this.updateSource,
    this.installBundled = true,
    DateTime Function()? clock,
    // Keep a public named argument while the mutable field remains private.
    // ignore: prefer_initializing_formals
  }) : _verifier = verifier,
       _bundle = bundle ?? rootBundle,
       _clock = clock ?? DateTime.now;

  final DatabaseFactory? factory;
  final String databasePath;
  final AssetBundle _bundle;
  final FilterPackUpdateSource? updateSource;
  final bool installBundled;
  final DateTime Function() _clock;
  FilterManifestVerifier? _verifier;
  Database? _database;
  Future<void>? _initialization;
  Future<void> _writes = Future<void>.value();
  FilterPackStatus _status = const FilterPackStatus();
  final _cache = <String, ({DateTime at, List<GuardRuleMatch> rules})>{};
  int _cacheEpoch = 0;
  static const maximumCachedHosts = 512;
  static const cacheLifetime = Duration(minutes: 10);
  static const updateInterval = Duration(hours: 24);

  @override
  FilterPackStatus get status => _status;
  @override
  String? get activeDatabasePath =>
      kIsWeb || !_status.integrityVerified ? null : _database?.path;
  String? get nativeDatabasePath => activeDatabasePath;

  @override
  Future<void> init() => _initialization ??= _initializeSafely();

  Future<void> _initializeSafely() async {
    try {
      await _initialize();
    } catch (error) {
      _status = FilterPackStatus(
        errorCode: error is FilterPackValidationException
            ? error.code
            : 'storage-unavailable',
      );
      clearCache();
      // Keep the database and corrupt evidence intact for diagnosis/recovery.
      // An unverified store is never exposed to native policy readers.
    }
  }

  Future<void> _initialize() async {
    if (_verifier == null) {
      final keys =
          jsonDecode(await _bundle.loadString('assets/guard/public_keys.json'))
              as Map<String, dynamic>;
      _verifier = FilterManifestVerifier(
        trustedKeys: {
          for (final entry in keys.entries)
            entry.key: base64Decode(entry.value as String),
        },
        clock: _clock,
      );
    }
    final options = OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE guard_state (
        id INTEGER PRIMARY KEY CHECK(id=1), active_generation INTEGER,
        previous_generation INTEGER, active_version TEXT,
        highest_sequence INTEGER NOT NULL DEFAULT 0, last_check INTEGER)''');
        await db.insert('guard_state', {'id': 1});
        await db.execute('''CREATE TABLE guard_releases (
        generation INTEGER PRIMARY KEY, version TEXT NOT NULL,
        created_at INTEGER NOT NULL, rule_count INTEGER NOT NULL,
        manifest BLOB NOT NULL, pack BLOB NOT NULL)''');
        await db.execute('''CREATE TABLE guard_rules (
        generation INTEGER NOT NULL, host TEXT NOT NULL, kind TEXT NOT NULL,
        category TEXT NOT NULL, include_subdomains INTEGER NOT NULL,
        rule_id TEXT NOT NULL,
        PRIMARY KEY(generation,host,kind,category)) WITHOUT ROWID''');
      },
    );
    _database =
        await (factory?.openDatabase(databasePath, options: options) ??
            openGuardDatabase(options));
    final state = (await _database!.query('guard_state')).single;
    if (state['active_generation'] != null) {
      try {
        await _verifyStored(state['active_generation'] as int);
        await _readStatus();
        return;
      } on FilterPackValidationException {
        final previous = state['previous_generation'] as int?;
        if (previous == null) rethrow;
        final manifest = await _verifyStored(previous);
        await _database!.update('guard_state', {
          'active_generation': previous,
          'previous_generation': null,
          'active_version': manifest.version,
        }, where: 'id=1');
        await _readStatus();
        return;
      }
    }
    if (installBundled) {
      final manifest = (await _bundle.load(
        'assets/guard/manifest.json',
      )).buffer.asUint8List();
      final verified = await _verifier!.verify(manifest);
      final pack = (await _bundle.load(
        'assets/guard/${verified.filename}',
      )).buffer.asUint8List();
      await _import(manifest, pack);
    }
  }

  Future<SignedFilterManifest> _verifyStored(int generation) async {
    final rows = await _database!.query(
      'guard_releases',
      where: 'generation=?',
      whereArgs: [generation],
    );
    if (rows.length != 1) {
      throw const FilterPackValidationException('missing-release');
    }
    final manifest = await _verifier!.verify(
      Uint8List.fromList(rows.single['manifest'] as List<int>),
    );
    await _verifier!.verifyPack(
      manifest,
      Uint8List.fromList(rows.single['pack'] as List<int>),
    );
    if (manifest.sequence != generation ||
        rows.single['version'] != manifest.version ||
        rows.single['created_at'] !=
            manifest.createdAt.millisecondsSinceEpoch ||
        rows.single['rule_count'] != manifest.ruleCount) {
      throw const FilterPackValidationException('release-metadata');
    }
    await _verifyIndexedRows(_database!, manifest);
    return manifest;
  }

  /// The signed digest binds the native-readable index, not only its archive.
  /// Indexed keyset pagination bounds Dart memory to 500 rows at a time.
  Future<void> _verifyIndexedRows(
    DatabaseExecutor db,
    SignedFilterManifest manifest,
  ) async {
    final sink = Sha256().toSync().newHashSink();
    var lastHost = '', lastKind = '', lastCategory = '';
    var count = 0;
    while (true) {
      final rows = await db.rawQuery(
        '''SELECT host,kind,category,include_subdomains,rule_id
        FROM guard_rules WHERE generation=? AND host>=? AND
        (host>? OR (host=? AND kind>?) OR (host=? AND kind=? AND category>?))
        ORDER BY host,kind,category LIMIT 500''',
        [
          manifest.sequence,
          lastHost,
          lastHost,
          lastHost,
          lastKind,
          lastHost,
          lastKind,
          lastCategory,
        ],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        sink.add(
          utf8.encode(
            '${jsonEncode([row['host'], row['kind'], row['category'], row['include_subdomains'], row['rule_id']])}\n',
          ),
        );
        count++;
      }
      final last = rows.last;
      lastHost = last['host'] as String;
      lastKind = last['kind'] as String;
      lastCategory = last['category'] as String;
    }
    sink.close();
    final digest = (await sink.hash()).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (count != manifest.ruleCount || digest != manifest.rulesSha256) {
      throw const FilterPackValidationException('index-integrity');
    }
  }

  @override
  Future<List<GuardRuleMatch>> lookupHost(
    String normalizedHost, {
    bool useCache = true,
  }) async {
    await init();
    DomainNormalizer.validateAsciiHost(normalizedHost);
    if (!_status.integrityVerified) throw StateError('Guard list unavailable.');
    final generation = _status.generation;
    final cacheEpoch = _cacheEpoch;
    final cached = useCache ? _cache.remove(normalizedHost) : null;
    if (cached != null && _clock().difference(cached.at) < cacheLifetime) {
      _cache[normalizedHost] = cached;
      return cached.rules;
    }
    final suffixes = DomainNormalizer.suffixes(normalizedHost);
    final marks = List.filled(suffixes.length, '?').join(',');
    final rows = await _database!.rawQuery(
      '''SELECT r.host,r.kind,r.category,
      r.include_subdomains,r.rule_id FROM guard_rules r
      JOIN guard_state s ON s.id=1 AND r.generation=s.active_generation
      WHERE r.host IN ($marks) AND (r.include_subdomains=1 OR r.host=?)
      ORDER BY length(r.host) DESC,r.kind,r.category''',
      [...suffixes, normalizedHost],
    );
    final rules = List<GuardRuleMatch>.unmodifiable(
      rows.map(
        (row) => GuardRuleMatch(
          host: row['host'] as String,
          kind: row['kind'] as String,
          category: GuardCategory.fromId(row['category'] as String),
          includeSubdomains: row['include_subdomains'] == 1,
          ruleId: row['rule_id'] as String,
        ),
      ),
    );
    if (useCache &&
        generation == _status.generation &&
        cacheEpoch == _cacheEpoch) {
      _cache[normalizedHost] = (at: _clock(), rules: rules);
      while (_cache.length > maximumCachedHosts) {
        _cache.remove(_cache.keys.first);
      }
    }
    return rules;
  }

  @override
  void clearCache() {
    _cache.clear();
    _cacheEpoch++;
  }

  @visibleForTesting
  int get cachedHostCount => _cache.length;

  @override
  Future<FilterPackStatus> importVerified(
    Uint8List manifestBytes,
    Uint8List packBytes,
  ) async {
    // Copy mutable caller input before its first asynchronous verification.
    final envelope = Uint8List.fromList(manifestBytes);
    final pack = Uint8List.fromList(packBytes);
    await init();
    if (_database == null || _verifier == null) {
      throw StateError('Guard storage unavailable.');
    }
    return _serialize(() => _import(envelope, pack));
  }

  Future<FilterPackStatus> _import(Uint8List envelope, Uint8List pack) async {
    final manifest = await _verifier!.verify(envelope);
    await _verifier!.verifyPack(manifest, pack);
    await _database!.transaction((txn) async {
      final current = (await txn.query('guard_state', where: 'id=1')).single;
      if (manifest.sequence <= (current['highest_sequence'] as int)) {
        throw const FilterPackValidationException('replayed-version');
      }
      await txn.insert('guard_releases', {
        'generation': manifest.sequence,
        'version': manifest.version,
        'created_at': manifest.createdAt.millisecondsSinceEpoch,
        'rule_count': manifest.ruleCount,
        'manifest': envelope,
        'pack': pack,
      });
      var count = 0;
      var batch = txn.batch();
      // Decode bounded chunks so importing a large artifact never creates a
      // million-element Dart string/set collection.
      final chunks = Stream<List<int>>.fromIterable([
        for (var i = 0; i < pack.length; i += 65536)
          Uint8List.sublistView(pack, i, (i + 65536).clamp(0, pack.length)),
      ]);
      await for (final line
          in chunks.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        if (line.length > 2048 || ++count > manifest.ruleCount) {
          throw const FilterPackValidationException('record-limit');
        }
        Map<String, dynamic> record;
        try {
          record = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          throw const FilterPackValidationException('record-format');
        }
        batch.insert('guard_rules', _validatedRow(record, manifest.sequence));
        if (count % 500 == 0) {
          await batch.commit(noResult: true);
          batch = txn.batch();
        }
      }
      if (count != manifest.ruleCount) {
        throw const FilterPackValidationException('record-count');
      }
      await batch.commit(noResult: true);
      await _verifyIndexedRows(txn, manifest);
      final previous = current['active_generation'] as int?;
      await txn.update('guard_state', {
        'active_generation': manifest.sequence,
        'previous_generation': previous,
        'active_version': manifest.version,
        'highest_sequence': manifest.sequence,
      }, where: 'id=1');
      final retained = [manifest.sequence, ?previous];
      final marks = List.filled(retained.length, '?').join(',');
      await txn.delete(
        'guard_rules',
        where: 'generation NOT IN ($marks)',
        whereArgs: retained,
      );
      await txn.delete(
        'guard_releases',
        where: 'generation NOT IN ($marks)',
        whereArgs: retained,
      );
    });
    clearCache();
    await _readStatus();
    return _status;
  }

  Map<String, Object?> _validatedRow(
    Map<String, dynamic> record,
    int generation,
  ) {
    try {
      final host = DomainNormalizer.validateAsciiHost(record['host'] as String);
      // Signed packs are distribution data: public suffix-wide rules and local
      // IP ranges are unsupported, while reserved test domains are explicit.
      if (!host.contains('.') ||
          host.contains(':') ||
          RegExp(r'^[0-9.]+$').hasMatch(host)) {
        throw const FilterPackValidationException('record-host');
      }
      final kind = record['kind'] as String;
      final categoryId = record['category'] as String? ?? '';
      final category = GuardCategory.fromId(categoryId);
      final ruleId = record['id'] as String;
      if (!const {
            'category',
            'malware',
            'phishing',
            'harmful-download',
            'support',
          }.contains(kind) ||
          !RegExp(r'^[a-z0-9][a-z0-9_-]{0,79}$').hasMatch(ruleId) ||
          record['includeSubdomains'] is! bool ||
          (kind != 'support' && category == null) ||
          (kind == 'category' && category!.isSecurity) ||
          (kind == 'malware' && category != GuardCategory.malware) ||
          (kind == 'phishing' && category != GuardCategory.phishing) ||
          (kind == 'harmful-download' &&
              category != GuardCategory.harmfulDownloads) ||
          (kind == 'support' && categoryId.isNotEmpty)) {
        throw const FilterPackValidationException('record-policy');
      }
      return {
        'generation': generation,
        'host': host,
        'kind': kind,
        'category': categoryId,
        'include_subdomains': record['includeSubdomains'] == true ? 1 : 0,
        'rule_id': ruleId,
      };
    } on FilterPackValidationException {
      rethrow;
    } catch (_) {
      throw const FilterPackValidationException('record-format');
    }
  }

  Future<void> _readStatus() async {
    final rows = await _database!.rawQuery(
      '''SELECT s.active_generation,
      s.previous_generation,r.version,r.created_at,r.rule_count FROM guard_state s
      JOIN guard_releases r ON r.generation=s.active_generation WHERE s.id=1''',
    );
    if (rows.isEmpty) {
      _status = const FilterPackStatus();
      return;
    }
    final row = rows.single;
    _status = FilterPackStatus(
      version: row['version'] as String,
      generation: row['active_generation'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
      ruleCount: row['rule_count'] as int,
      hasPrevious: row['previous_generation'] != null,
      integrityVerified: true,
    );
  }

  @override
  Future<bool> rollback() async {
    await init();
    if (_database == null || _verifier == null) return false;
    return _serialize(() async {
      final state = (await _database!.query(
        'guard_state',
        where: 'id=1',
      )).single;
      final previous = state['previous_generation'] as int?;
      if (previous == null) return false;
      final manifest = await _verifyStored(previous);
      await _database!.update('guard_state', {
        'active_generation': previous,
        'previous_generation': state['active_generation'],
        'active_version': manifest.version,
      }, where: 'id=1');
      clearCache();
      await _readStatus();
      return true;
    });
  }

  @override
  Future<FilterUpdateResult> checkForUpdates({bool force = false}) async {
    await init();
    if (updateSource == null) {
      return FilterUpdateResult(
        FilterUpdateOutcome.notConfigured,
        status: status,
      );
    }
    if (_database == null || _verifier == null) {
      return FilterUpdateResult(FilterUpdateOutcome.rejected, status: status);
    }
    return _serialize(() async {
      final state = (await _database!.query(
        'guard_state',
        where: 'id=1',
      )).single;
      final last = state['last_check'] as int?;
      if (!force &&
          last != null &&
          _clock().millisecondsSinceEpoch - last <
              updateInterval.inMilliseconds) {
        return FilterUpdateResult(
          FilterUpdateOutcome.throttled,
          status: status,
        );
      }
      await _database!.update('guard_state', {
        'last_check': _clock().millisecondsSinceEpoch,
      }, where: 'id=1');
      try {
        final envelope = await updateSource!.fetchManifest().timeout(
          const Duration(seconds: 15),
        );
        final manifest = await _verifier!.verify(envelope);
        if (manifest.sequence == (state['highest_sequence'] as int)) {
          return FilterUpdateResult(
            FilterUpdateOutcome.current,
            status: status,
          );
        }
        if (manifest.sequence < (state['highest_sequence'] as int)) {
          throw const FilterPackValidationException('replayed-version');
        }
        final pack = await updateSource!
            .fetchPack(manifest.filename, manifest.byteLength)
            .timeout(const Duration(seconds: 60));
        await _import(envelope, pack);
        return FilterUpdateResult(FilterUpdateOutcome.updated, status: status);
      } catch (_) {
        return FilterUpdateResult(FilterUpdateOutcome.rejected, status: status);
      }
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> close() async {
    await _writes;
    await _database?.close();
    _database = null;
    _initialization = null;
    _status = const FilterPackStatus();
    clearCache();
  }
}
