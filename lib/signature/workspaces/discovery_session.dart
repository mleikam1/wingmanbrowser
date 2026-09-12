import 'dart:async';
import '../../policy/strict_search_policy.dart';
import '../storage/document_store.dart';
import '../signature_services.dart';
import '../../presentation/settings/settings_actions.dart'
    show DataClearOutcome;

class DiscoveryTab {
  DiscoveryTab({this.isPrivate = false, String? id})
    : id = id ?? 'tab-${DateTime.now().microsecondsSinceEpoch}-${_next++}';
  static int _next = 0;
  final String id;
  final bool isPrivate;
  final List<String?> trail = [null];
  int position = 0;
  String? taskId;
  // Bounded, memory-only positions; owner session survives isolated handoff UI.
  final Map<String, double> scrollOffsets = {};
  String? get currentEntry => trail[position];
  String? get resourceId =>
      currentEntry?.startsWith('web:') == true ? null : currentEntry;
  Uri? get website => currentEntry?.startsWith('web:') == true
      ? Uri.tryParse(currentEntry!.substring(4))
      : null;
  void visitWebsite(Uri uri) => visit('web:$uri');
  void visit(String? id) {
    if (id == currentEntry) return;
    trail.removeRange(position + 1, trail.length);
    trail.add(id);
    position = trail.length - 1;
    if (trail.length > 50) {
      trail.removeAt(0);
      position--;
    }
  }

  DiscoveryTab copyForUndo() {
    if (isPrivate) throw StateError('Private tabs cannot enter undo.');
    return DiscoveryTab(id: id)
      ..trail.clear()
      ..trail.addAll(trail)
      ..position = position
      ..taskId = taskId;
  }

  void dispose() {
    scrollOffsets.clear();
  }
}

/// Owner session objects outlive the UI while static Hand It Over replaces its
/// entire Navigator. Nothing here is written as ordinary browser history.
class DiscoverySession {
  SignatureDocumentStore? _store;
  Timer? _saveTimer;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  String? restorationError;

  /// Address restoration only. Native back/forward stacks and form state are
  /// retained while an engine lives; they are not claimed across process death.
  Future<void> restore(
    SignatureDocumentStore store, {
    required bool Function(Uri) permitted,
    required bool Function(String) resourceEligible,
  }) async {
    _store = store;
    try {
      final saved = await store.readDocument('browserSession');
      if (saved == null || saved['version'] != 1 || saved['tabs'] is! List) {
        return;
      }
      final restored = <DiscoveryTab>[];
      for (final row in (saved['tabs'] as List).take(12)) {
        if (row is! Map ||
            row['id'] is! String ||
            (row['id'] as String).length > 120) {
          continue;
        }
        if (restored.any((tab) => tab.id == row['id'])) continue;
        final tab = DiscoveryTab(id: row['id'] as String);
        final entry = row['entry'];
        if (entry is String && entry.length <= 16384) {
          if (entry.startsWith('web:')) {
            final uri = Uri.tryParse(entry.substring(4));
            if (uri != null && permitted(uri) && !_isSearch(uri)) {
              tab.visitWebsite(uri);
            }
          } else if (resourceEligible(entry)) {
            tab.visit(entry);
          }
        }
        restored.add(tab);
      }
      if (restored.isNotEmpty) {
        tabs.clear();
        tabs.addAll(restored);
        final selected = tabs.indexWhere((tab) => tab.id == saved['active']);
        active = selected < 0 ? 0 : selected;
      }
    } catch (_) {
      restorationError =
          'Saved tabs could not be restored. Your other local data remains available.';
    }
  }

  static bool _isSearch(Uri uri) =>
      const StrictSearchPolicy().acceptsCanonical(uri) ||
      uri.host == 'duckduckgo.com' ||
      uri.host.endsWith('.duckduckgo.com');

  void scheduleSave() {
    if (_disposed || _store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    final store = _store;
    if (store == null) return _writes;
    final normal = tabs.where((tab) => !tab.isPrivate).take(12).toList();
    final value = <String, Object?>{
      'version': 1,
      'active': normal.any((tab) => tab.id == current.id)
          ? current.id
          : normal.firstOrNull?.id,
      'tabs': [
        for (final tab in normal)
          {
            'id': tab.id,
            'entry': tab.website != null && _isSearch(tab.website!)
                ? null
                : tab.currentEntry,
          },
      ],
    };
    _writes = _writes
        .then((_) => store.writeDocument('browserSession', value))
        .catchError((Object _) {
          restorationError = 'Tab restoration could not be saved.';
        });
    return _writes;
  }

  final List<DiscoveryTab> tabs = [DiscoveryTab()];
  int active = 0, destination = 0;
  String query = '';
  String? collection, notice;
  SignatureServices? privateServices;
  Future<DataClearOutcome>? pendingDataClear;
  bool? pendingClearIsPrivate;
  List<DiscoveryTab> _taskUndo = [];
  DiscoveryTab get current => tabs[active];
  List<DiscoveryTab> closeTaskTabs(String taskId, {required bool private}) {
    final selected = tabs
        .where((t) => t.taskId == taskId && t.isPrivate == private)
        .toList();
    // Membership is held by real live tabs, never a document's claimed tab IDs.
    _taskUndo = private ? [] : selected.map((e) => e.copyForUndo()).toList();
    final activeId = current.id;
    tabs.removeWhere(selected.contains);
    for (final tab in selected) {
      tab.dispose();
    }
    if (tabs.isEmpty) tabs.add(DiscoveryTab());
    final preserved = tabs.indexWhere((tab) => tab.id == activeId);
    active = preserved >= 0 ? preserved : active.clamp(0, tabs.length - 1);
    return selected;
  }

  bool get canUndoTaskClosure => _taskUndo.isNotEmpty;
  int undoTaskClosure(bool Function(String id) eligible) {
    var restored = 0;
    for (final saved in _taskUndo) {
      if (tabs.length >= 12 || tabs.any((t) => t.id == saved.id)) continue;
      final tab = DiscoveryTab(id: saved.id);
      // Revalidate every history ID; an expired approval cannot survive undo.
      tab.trail
        ..clear()
        ..addAll(
          saved.trail.map((id) => id != null && eligible(id) ? id : null),
        );
      tab.position = saved.position.clamp(0, tab.trail.length - 1);
      tabs.add(tab);
      restored++;
    }
    _taskUndo = [];
    return restored;
  }

  void clearTaskUndo() {
    _taskUndo = [];
  }

  void clearPrivateServicesIfUnused() {
    if (!tabs.any((t) => t.isPrivate)) {
      privateServices?.dispose();
      privateServices = null;
    }
  }

  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    unawaited(flush());
    for (final tab in tabs) {
      tab.dispose();
    }
    privateServices?.dispose();
    privateServices = null;
    clearTaskUndo();
  }
}
