import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../presentation/design_system/ui_preferences.dart';
import '../storage/document_store.dart';
import 'launchpad_eligibility.dart';
import 'launchpad_models.dart';

class LaunchpadException implements Exception {
  const LaunchpadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Session-only deletion token; never a persisted permission or prior snapshot.
class LaunchpadUndo {
  LaunchpadUndo._(
    this._owner,
    this._shortcuts,
    this._folders, [
    this._moved = const [],
  ]);
  final Object _owner;
  final List<LaunchpadShortcut> _shortcuts;
  final List<LaunchpadFolder> _folders;
  final List<LaunchpadShortcut> _moved;
  bool _used = false, _pending = false;
}

class LaunchpadController extends ChangeNotifier {
  LaunchpadController({
    required SignatureDocumentStore store,
    required this.eligibility,
    this.ephemeral = false,
    DateTime Function()? clock,
  }) : _store = SessionSignatureDocumentStore(store, ephemeral: ephemeral),
       _clock = clock ?? DateTime.now;
  final SignatureDocumentStore _store;
  final LaunchpadEligibilityService eligibility;
  final bool ephemeral;
  final DateTime Function() _clock;
  Object _owner = Object();
  static int _serial = 0;
  LaunchpadSnapshot _snapshot = LaunchpadSnapshot();
  LaunchpadSnapshot get snapshot => _snapshot;
  bool initialized = false, _closed = false, _restoreFailed = false;
  String? storageError;
  Future<void> _writes = Future.value();
  Future<void>? _initialization;
  String _id(String prefix) =>
      '$prefix-${_clock().microsecondsSinceEpoch}-${_serial++}';
  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      final row = await _store.readDocument('launchpad');
      if (_closed) return;
      if (row != null) {
        _snapshot = LaunchpadSnapshot.fromJson(row);
      } else {
        final legacy = await _store.readDocument('ui');
        if (_closed) return;
        final old = legacy == null
            ? UiPreferences()
            : UiPreferences.fromJson(legacy);
        final now = _clock().toUtc();
        final imported = old.shortcutIds.indexed
            .map(
              (entry) => LaunchpadShortcut(
                id: _id('shortcut'),
                title:
                    eligibility.resourceLookup?.call(entry.$2)?.title ??
                    'Saved resource',
                target: LaunchpadTarget.resource(entry.$2),
                localIconKey: 'book',
                order: entry.$1,
                source: LaunchpadSource.legacy,
                createdAt: now,
                updatedAt: now,
              ),
            )
            .toList();
        final first = LaunchpadSnapshot(
          shortcuts: imported,
          setup: imported.isEmpty
              ? LaunchpadSetup.notStarted
              : LaunchpadSetup.completed,
        );
        LaunchpadSnapshot.fromJson(first.toJson());
        await _store.writeDocument('launchpad', first.toJson());
        if (!_closed) _snapshot = first;
      }
    } catch (_) {
      _restoreFailed = true;
      storageError =
          'Launchpad could not be restored. Existing local data is preserved.';
    }
    initialized = true;
    if (!_closed) notifyListeners();
  }

  Future<void> flush() => _writes;
  void _check(bool Function()? canContinue) {
    if (_closed || !initialized || _restoreFailed) {
      throw const LaunchpadException(
        'Launchpad is unavailable in this session.',
      );
    }
    if (canContinue != null && !canContinue()) {
      throw const LaunchpadException(
        'This action was canceled because its session changed.',
      );
    }
  }

  Future<T> _change<T>(
    ({LaunchpadSnapshot next, T value}) Function(LaunchpadSnapshot) transform, {
    bool Function()? canContinue,
    VoidCallback? onCommitted,
  }) {
    final next = _writes.then((_) async {
      _check(canContinue);
      final result = transform(_snapshot);
      final checked = LaunchpadSnapshot.fromJson(result.next.toJson());
      _check(canContinue);
      try {
        await _store.writeDocument('launchpad', checked.toJson());
      } catch (_) {
        storageError =
            'The Launchpad change could not be saved. Your previous layout is retained.';
        if (!_closed) notifyListeners();
        throw const LaunchpadException(
          'The Launchpad change could not be saved. Try again.',
        );
      }
      onCommitted?.call();
      if (!_closed) {
        _snapshot = checked;
        storageError = null;
        notifyListeners();
      }
      return result.value;
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  LaunchpadTarget _target(LaunchpadTarget target) => LaunchpadTarget.fromJson(
    (target.kind == LaunchpadKind.website
            ? LaunchpadTarget.website(normalizeLaunchpadWebsite(target.value))
            : target)
        .toJson(),
  );
  void _require(LaunchpadTarget target, bool retainInactiveWebsite) {
    final result = eligibility.assess(target);
    if (result.canOpen) return;
    if (target.kind == LaunchpadKind.website &&
        retainInactiveWebsite &&
        result.canRetainInactive) {
      return;
    }
    throw LaunchpadException(
      target.kind == LaunchpadKind.website && result.canRetainInactive
          ? 'Confirm that this website is saved only as an inactive local review record.'
          : result.message,
    );
  }

  LaunchpadShortcut _fromDraft(
    LaunchpadSnapshot s,
    LaunchpadDraft draft,
    String id, {
    bool retainInactiveWebsite = false,
    LaunchpadShortcut? previous,
  }) {
    final target = _target(draft.target);
    _require(target, retainInactiveWebsite);
    if (draft.folderId != null &&
        !s.folders.any((f) => f.id == draft.folderId)) {
      throw const LaunchpadException('Choose an existing folder.');
    }
    if (s.shortcuts.any((e) => e.id != id && e.target == target)) {
      throw const LaunchpadException(
        'This destination is already on your Launchpad.',
      );
    }
    final changed = previous != null && previous.target != target;
    final now = _clock().toUtc();
    final created = previous?.createdAt ?? now;
    final item = LaunchpadShortcut(
      id: id,
      title: draft.title.trim(),
      target: target,
      localIconKey: draft.localIconKey,
      folderId: draft.folderId,
      order:
          previous?.order ??
          (draft.folderId == null
              ? s.rootItems.length
              : s.folderItems(draft.folderId!).length),
      source: changed ? LaunchpadSource.user : previous?.source ?? draft.source,
      catalogEntryId: changed
          ? null
          : previous?.catalogEntryId ?? draft.catalogEntryId,
      createdAt: created,
      updatedAt: now.isBefore(created) ? created : now,
    );
    return LaunchpadShortcut.fromJson(item.toJson());
  }

  Future<String> addShortcut(
    LaunchpadDraft draft, {
    bool retainInactiveWebsite = false,
    bool Function()? canContinue,
  }) => _change((s) {
    if (s.shortcuts.length >= LaunchpadSnapshot.maximumShortcuts) {
      throw const LaunchpadException('The 64-shortcut limit is reached.');
    }
    final item = _fromDraft(
      s,
      draft,
      _id('shortcut'),
      retainInactiveWebsite: retainInactiveWebsite,
    );
    return (
      next: s.copyWith(
        shortcuts: [...s.shortcuts, item],
        setup: LaunchpadSetup.completed,
      ),
      value: item.id,
    );
  }, canContinue: canContinue);
  Future<List<String>> addSelected(
    List<LaunchpadDraft> drafts, {
    bool retainInactiveWebsite = false,
    bool Function()? canContinue,
  }) {
    drafts = List<LaunchpadDraft>.unmodifiable(drafts);
    return _change((s) {
      if (drafts.length > LaunchpadSnapshot.maximumShortcuts) {
        throw const LaunchpadException('Select at most 64 shortcuts at once.');
      }
      var next = s;
      final ids = <String>[];
      for (final draft in drafts) {
        final target = _target(draft.target);
        if (next.shortcuts.any((e) => e.target == target)) continue;
        if (next.shortcuts.length >= LaunchpadSnapshot.maximumShortcuts) {
          throw const LaunchpadException('The 64-shortcut limit is reached.');
        }
        final item = _fromDraft(
          next,
          draft,
          _id('shortcut'),
          retainInactiveWebsite: retainInactiveWebsite,
        );
        next = next.copyWith(shortcuts: [...next.shortcuts, item]);
        ids.add(item.id);
      }
      return (
        next: next.copyWith(setup: LaunchpadSetup.completed),
        value: List<String>.unmodifiable(ids),
      );
    }, canContinue: canContinue);
  }

  Future<void> editShortcut(
    String id,
    LaunchpadDraft draft, {
    bool retainInactiveWebsite = false,
    bool Function()? canContinue,
  }) => _change<void>((s) {
    final old = s.shortcuts.where((e) => e.id == id).firstOrNull;
    if (old == null) {
      throw const LaunchpadException('This shortcut is no longer available.');
    }
    var item = _fromDraft(
      s,
      draft,
      id,
      previous: old,
      retainInactiveWebsite: retainInactiveWebsite,
    );
    if (item.folderId != old.folderId) {
      item = item.placed(
        item.folderId,
        item.folderId == null
            ? s.rootItems.length
            : s.folderItems(item.folderId!).length,
      );
    }
    return (
      next: _normalized(
        s.copyWith(shortcuts: s.shortcuts.map((e) => e.id == id ? item : e)),
      ),
      value: null,
    );
  }, canContinue: canContinue);

  Future<String> createFolder(
    String title, {
    String localIconKey = 'folder',
    bool Function()? canContinue,
  }) => _change((s) {
    if (s.folders.length >= LaunchpadSnapshot.maximumFolders) {
      throw const LaunchpadException('The 12-folder limit is reached.');
    }
    final folder = LaunchpadFolder(
      id: _id('folder'),
      title: title.trim(),
      localIconKey: localIconKey,
      order: s.rootItems.length,
    );
    return (
      next: s.copyWith(folders: [...s.folders, folder]),
      value: folder.id,
    );
  }, canContinue: canContinue);
  Future<void> renameFolder(
    String id,
    String title, {
    String? localIconKey,
    bool Function()? canContinue,
  }) => _change<void>((s) {
    if (!s.folders.any((f) => f.id == id)) {
      throw const LaunchpadException('This folder is no longer available.');
    }
    return (
      next: s.copyWith(
        folders: s.folders.map(
          (f) => f.id == id
              ? LaunchpadFolder(
                  id: id,
                  title: title.trim(),
                  localIconKey: localIconKey ?? f.localIconKey,
                  order: f.order,
                )
              : f,
        ),
      ),
      value: null,
    );
  }, canContinue: canContinue);
  Future<void> reorderRoot(List<String> ids, {bool Function()? canContinue}) {
    final captured = List<String>.unmodifiable(ids);
    return _change<void>(
      (s) => (next: _ordered(s, null, captured), value: null),
      canContinue: canContinue,
    );
  }

  Future<void> reorderFolder(
    String folderId,
    List<String> ids, {
    bool Function()? canContinue,
  }) {
    ids = List<String>.unmodifiable(ids);
    return _change<void>((s) {
      if (!s.folders.any((f) => f.id == folderId)) {
        throw const LaunchpadException('This folder is no longer available.');
      }
      return (next: _ordered(s, folderId, ids), value: null);
    }, canContinue: canContinue);
  }

  Future<void> moveShortcut(
    String id, {
    String? folderId,
    required int index,
    bool Function()? canContinue,
  }) => _change<void>((s) {
    final old = s.shortcuts.where((e) => e.id == id).firstOrNull;
    if (old == null ||
        folderId != null && !s.folders.any((f) => f.id == folderId)) {
      throw const LaunchpadException(
        'The shortcut or folder is no longer available.',
      );
    }
    var next = _normalized(
      s.copyWith(shortcuts: s.shortcuts.where((e) => e.id != id)),
    );
    final ids = (folderId == null ? next.rootItems : next.folderItems(folderId))
        .map((e) => e.id)
        .toList();
    if (index < 0 || index > ids.length) {
      throw const LaunchpadException('Choose an available position.');
    }
    next = next.copyWith(
      shortcuts: [...next.shortcuts, old.placed(folderId, ids.length)],
    );
    ids.insert(index, id);
    return (next: _ordered(next, folderId, ids), value: null);
  }, canContinue: canContinue);
  LaunchpadSnapshot _ordered(
    LaunchpadSnapshot s,
    String? folder,
    List<String> ids,
  ) {
    final current = (folder == null ? s.rootItems : s.folderItems(folder))
        .map((e) => e.id)
        .toSet();
    if (ids.length != current.length ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !current.contains(id))) {
      throw const LaunchpadException(
        'The Launchpad changed. Review its current order and try again.',
      );
    }
    final order = {for (final e in ids.indexed) e.$2: e.$1};
    return s.copyWith(
      shortcuts: s.shortcuts.map(
        (e) => e.folderId == folder ? e.placed(folder, order[e.id]!) : e,
      ),
      folders: folder == null
          ? s.folders.map((e) => e.placed(order[e.id]!))
          : s.folders,
    );
  }

  LaunchpadSnapshot _normalized(LaunchpadSnapshot s) {
    var next = s;
    next = _ordered(next, null, next.rootItems.map((e) => e.id).toList());
    for (final f in next.folders) {
      next = _ordered(
        next,
        f.id,
        next.folderItems(f.id).map((e) => e.id).toList(),
      );
    }
    return next;
  }

  Future<LaunchpadUndo> removeShortcut(
    String id, {
    bool Function()? canContinue,
  }) => _change((s) {
    final item = s.shortcuts.where((e) => e.id == id).firstOrNull;
    if (item == null) {
      throw const LaunchpadException('This shortcut is no longer available.');
    }
    return (
      next: _normalized(
        s.copyWith(shortcuts: s.shortcuts.where((e) => e.id != id)),
      ),
      value: LaunchpadUndo._(_owner, [item], []),
    );
  }, canContinue: canContinue);
  Future<LaunchpadUndo> removeFolder(
    String id, {
    required bool removeContents,
    bool Function()? canContinue,
  }) => _change((s) {
    final folder = s.folders.where((e) => e.id == id).firstOrNull;
    if (folder == null) {
      throw const LaunchpadException('This folder is no longer available.');
    }
    final contents = s.folderItems(id);
    var position = s.rootItems.length;
    final shortcuts = s.shortcuts
        .where((e) => !removeContents || e.folderId != id)
        .map((e) => e.folderId == id ? e.placed(null, position++) : e)
        .toList();
    return (
      next: _normalized(
        s.copyWith(
          shortcuts: shortcuts,
          folders: s.folders.where((f) => f.id != id),
        ),
      ),
      value: LaunchpadUndo._(_owner, removeContents ? contents : [], [
        folder,
      ], removeContents ? [] : contents),
    );
  }, canContinue: canContinue);
  Future<void> undo(LaunchpadUndo token, {bool Function()? canContinue}) async {
    if (!identical(token._owner, _owner) || token._used || token._pending) {
      throw const LaunchpadException('This undo is no longer available.');
    }
    token._pending = true;
    try {
      await _change<void>((s) {
        if (!identical(token._owner, _owner) || token._used) {
          throw const LaunchpadException('This undo is no longer available.');
        }
        final ids = {
          ...s.shortcuts.map((e) => e.id),
          ...s.folders.map((e) => e.id),
        };
        if ([
          ...token._shortcuts.map((e) => e.id),
          ...token._folders.map((e) => e.id),
        ].any(ids.contains)) {
          throw const LaunchpadException(
            'The Launchpad changed. This removal cannot be undone.',
          );
        }
        for (final item in token._shortcuts) {
          _require(item.target, item.target.kind == LaunchpadKind.website);
          if (s.shortcuts.any((e) => e.target == item.target)) {
            throw const LaunchpadException(
              'This destination was already added again.',
            );
          }
          if (item.folderId != null &&
              !s.folders.any((f) => f.id == item.folderId) &&
              !token._folders.any((f) => f.id == item.folderId)) {
            throw const LaunchpadException(
              'The original folder no longer exists.',
            );
          }
        }
        for (final item in token._moved) {
          final current = s.shortcuts.where((e) => e.id == item.id).firstOrNull;
          if (current == null ||
              current.folderId != null ||
              jsonEncode(current.placed(item.folderId, item.order).toJson()) !=
                  jsonEncode(item.toJson())) {
            throw const LaunchpadException(
              'A moved shortcut changed. This folder removal cannot be undone.',
            );
          }
          _require(item.target, item.target.kind == LaunchpadKind.website);
        }
        var next = s.copyWith(
          shortcuts: [
            ...s.shortcuts.map(
              (e) =>
                  token._moved.where((old) => old.id == e.id).firstOrNull ?? e,
            ),
            ...token._shortcuts,
          ],
          folders: [...s.folders, ...token._folders],
        );
        final roots = s.rootItems
            .where((e) => !token._moved.any((m) => m.id == e.id))
            .map((e) => e.id)
            .toList();
        final restoredRoots = <LaunchpadItem>[
          ...token._folders,
          ...token._shortcuts.where((e) => e.folderId == null),
        ]..sort((a, b) => a.order.compareTo(b.order));
        for (final item in restoredRoots) {
          roots.insert(item.order.clamp(0, roots.length), item.id);
        }
        next = _ordered(next, null, roots);
        for (final folder in next.folders) {
          final siblings = s.folderItems(folder.id).map((e) => e.id).toList();
          final restored =
              [
                  ...token._shortcuts,
                  ...token._moved,
                ].where((e) => e.folderId == folder.id).toList()
                ..sort((a, b) => a.order.compareTo(b.order));
          for (final item in restored) {
            siblings.insert(item.order.clamp(0, siblings.length), item.id);
          }
          next = _ordered(next, folder.id, siblings);
        }
        // Merge only removed items with current data, never an old document.
        return (next: next, value: null);
      }, canContinue: canContinue);
      token._used = true;
    } finally {
      token._pending = false;
    }
  }

  Future<void> updatePreferences({
    bool? showShortcuts,
    bool? showCollections,
    LaunchpadDensity? density,
    bool Function()? canContinue,
  }) => _change<void>(
    (s) => (
      next: s.copyWith(
        showShortcuts: showShortcuts,
        showCollections: showCollections,
        density: density,
      ),
      value: null,
    ),
    canContinue: canContinue,
  );
  Future<void> completeSetup({
    bool dismissed = false,
    bool Function()? canContinue,
  }) => _change<void>(
    (s) => (
      next: s.copyWith(
        setup: dismissed ? LaunchpadSetup.dismissed : LaunchpadSetup.completed,
      ),
      value: null,
    ),
    canContinue: canContinue,
  );

  /// Reopens suggestions after confirmation; never restores removed tiles or erases edits.
  Future<void> resetConfirmed({bool Function()? canContinue}) => _change<void>(
    (s) => (next: s.copyWith(setup: LaunchpadSetup.notStarted), value: null),
    canContinue: canContinue,
  );

  /// Explicit local deletion retains the migration marker so legacy shortcuts
  /// cannot return. Prior undo tokens cannot recreate the cleared records.
  Future<void> clearSavedData({bool Function()? canContinue}) => _change<void>(
    (_) =>
        (next: LaunchpadSnapshot(setup: LaunchpadSetup.dismissed), value: null),
    canContinue: canContinue,
    onCommitted: () => _owner = Object(),
  );
  Future<void> setCollection(
    HomeCollectionPreference preference, {
    bool retainInactiveWebsite = false,
    bool Function()? canContinue,
  }) => updateCollection(
    preference.kind,
    (_) => preference,
    retainInactiveWebsite: retainInactiveWebsite,
    canContinue: canContinue,
  );

  Future<void> updateCollection(
    LaunchpadCollection kind,
    HomeCollectionPreference Function(HomeCollectionPreference? latest)
    transform, {
    bool retainInactiveWebsite = false,
    bool Function()? canContinue,
  }) => _change<void>((s) {
    final old = s.collections.where((c) => c.kind == kind).firstOrNull;
    final preference = transform(old);
    if (preference.kind != kind || preference.sources.length > 24) {
      throw const LaunchpadException(
        'Choose at most 24 sources for the selected collection.',
      );
    }
    HomeCollectionPreference.fromJson(preference.toJson());
    for (final source in preference.sources) {
      if (old?.sources.any((e) => e.target == source.target) != true) {
        _require(source.target, retainInactiveWebsite);
      }
    }
    final list = [...s.collections.where((c) => c.kind != kind), preference]
      ..sort((a, b) => a.order.compareTo(b.order));
    return (
      next: s.copyWith(
        collections: list.indexed.map(
          (e) => HomeCollectionPreference(
            kind: e.$2.kind,
            visible: e.$2.visible,
            order: e.$1,
            sources: e.$2.sources,
          ),
        ),
      ),
      value: null,
    );
  }, canContinue: canContinue);

  Future<void> reorderCollections(
    List<LaunchpadCollection> kinds, {
    bool Function()? canContinue,
  }) {
    kinds = List<LaunchpadCollection>.unmodifiable(kinds);
    return _change<void>((s) {
      if (kinds.length != s.collections.length ||
          kinds.toSet().length != kinds.length ||
          kinds.any((kind) => !s.collections.any((c) => c.kind == kind))) {
        throw const LaunchpadException(
          'The collections changed. Review their current order.',
        );
      }
      return (
        next: s.copyWith(
          collections: kinds.indexed.map((e) {
            final current = s.collections.firstWhere((c) => c.kind == e.$2);
            return HomeCollectionPreference(
              kind: current.kind,
              visible: current.visible,
              order: e.$1,
              sources: current.sources,
            );
          }),
        ),
        value: null,
      );
    }, canContinue: canContinue);
  }

  Future<void> removeCollection(
    LaunchpadCollection kind, {
    bool Function()? canContinue,
  }) => _change<void>((s) {
    final remaining = s.collections.where((c) => c.kind != kind).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return (
      next: s.copyWith(
        collections: remaining.indexed.map(
          (e) => HomeCollectionPreference(
            kind: e.$2.kind,
            visible: e.$2.visible,
            order: e.$1,
            sources: e.$2.sources,
          ),
        ),
      ),
      value: null,
    );
  }, canContinue: canContinue);
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
