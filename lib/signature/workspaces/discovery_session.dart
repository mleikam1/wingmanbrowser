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
  String? get resourceId => trail[position];
  void visit(String? id) {
    if (id == resourceId) return;
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
    for (final tab in tabs) {
      tab.dispose();
    }
    privateServices?.dispose();
    privateServices = null;
    clearTaskUndo();
  }
}
