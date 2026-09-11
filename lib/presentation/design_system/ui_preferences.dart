import 'package:flutter/foundation.dart';
import '../../policy/policy_models.dart';
import '../../signature/storage/document_store.dart';

@immutable
class UiPreferences {
  UiPreferences({
    this.showOfficial = true,
    this.showTask = true,
    this.showSpaces = true,
    Iterable<String> shortcutIds = const [],
    Iterable<String> moduleOrder = modules,
  }) : shortcutIds = List.unmodifiable(shortcutIds),
       moduleOrder = List.unmodifiable(moduleOrder);
  static const modules = ['shortcuts', 'official', 'task', 'spaces'];
  final bool showOfficial, showTask, showSpaces;
  final List<String> shortcutIds, moduleOrder;
  UiPreferences copyWith({
    bool? showOfficial,
    bool? showTask,
    bool? showSpaces,
    Iterable<String>? shortcutIds,
    Iterable<String>? moduleOrder,
  }) => UiPreferences(
    showOfficial: showOfficial ?? this.showOfficial,
    showTask: showTask ?? this.showTask,
    showSpaces: showSpaces ?? this.showSpaces,
    shortcutIds: shortcutIds ?? this.shortcutIds,
    moduleOrder: moduleOrder ?? this.moduleOrder,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'showOfficial': showOfficial,
    'showTask': showTask,
    'showSpaces': showSpaces,
    'shortcutIds': shortcutIds,
    'moduleOrder': moduleOrder,
  };
  factory UiPreferences.fromJson(Map<String, Object?> row) {
    const keys = {
      'version',
      'showOfficial',
      'showTask',
      'showSpaces',
      'shortcutIds',
      'moduleOrder',
    };
    if (row.keys.toSet().difference(keys).isNotEmpty ||
        row.length != keys.length ||
        row['version'] != 1 ||
        row['showOfficial'] is! bool ||
        row['showTask'] is! bool ||
        row['showSpaces'] is! bool ||
        row['shortcutIds'] is! List ||
        row['moduleOrder'] is! List) {
      throw const FormatException('Invalid Home preferences.');
    }
    final ids = row['shortcutIds'] as List, order = row['moduleOrder'] as List;
    if (ids.length > 6 ||
        ids.any((id) => id is! String || !validResourceId(id)) ||
        ids.toSet().length != ids.length ||
        order.length != modules.length ||
        order.toSet().length != modules.length ||
        order.any((id) => !modules.contains(id))) {
      throw const FormatException('Invalid Home layout.');
    }
    return UiPreferences(
      showOfficial: row['showOfficial'] as bool,
      showTask: row['showTask'] as bool,
      showSpaces: row['showSpaces'] as bool,
      shortcutIds: ids.cast<String>(),
      moduleOrder: order.cast<String>(),
    );
  }
}

class UiPreferencesController extends ChangeNotifier {
  UiPreferencesController({
    required SignatureDocumentStore store,
    required bool ephemeral,
  }) : _store = SessionSignatureDocumentStore(store, ephemeral: ephemeral);
  final SignatureDocumentStore _store;
  UiPreferences _snapshot = UiPreferences();
  UiPreferences get snapshot => _snapshot;
  String? storageError;
  bool initialized = false, _closed = false, _restoreFailed = false;
  Future<void> _writes = Future.value();
  Future<void> initialize() async {
    try {
      final row = await _store.readDocument('ui');
      if (row != null) _snapshot = UiPreferences.fromJson(row);
    } catch (_) {
      _restoreFailed = true;
      storageError =
          'Home preferences could not be read. The saved layout is preserved.';
    }
    initialized = true;
    if (!_closed) notifyListeners();
  }

  Future<void> update(UiPreferences Function(UiPreferences) change) {
    if (_closed || !initialized || _restoreFailed) {
      return Future.error(StateError('Home preferences are unavailable.'));
    }
    final next = _writes.then((_) async {
      if (_closed) throw StateError('This session has ended.');
      final value = UiPreferences.fromJson(change(_snapshot).toJson());
      try {
        await _store.writeDocument('ui', value.toJson());
        _snapshot = value;
        storageError = null;
        if (!_closed) notifyListeners();
      } catch (_) {
        storageError =
            'The Home change could not be saved. Your previous layout is retained.';
        if (!_closed) notifyListeners();
        rethrow;
      }
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> flush() => _writes;

  /// Only an explicitly confirmed reset may replace a malformed saved layout.
  Future<void> reset() {
    if (_closed || !initialized) {
      return Future.error(StateError('Home preferences are unavailable.'));
    }
    final next = _writes.then((_) async {
      if (_closed) throw StateError('This session has ended.');
      final defaults = UiPreferences();
      await _store.writeDocument('ui', defaults.toJson());
      _snapshot = defaults;
      _restoreFailed = false;
      storageError = null;
      if (!_closed) notifyListeners();
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
