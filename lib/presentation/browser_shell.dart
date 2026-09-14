import 'dart:async';
import 'components/browser_find_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../browser/companion_navigation.dart';
import 'package:flutter/material.dart';
import '../config/product_edition.dart';
import '../browser/browser_engine.dart';
import '../browser/protected_web_surface.dart';
import '../policy/policy_runtime.dart';
import '../state/browser_state.dart';
import '../signature/signature_services.dart';
import '../signature/launchpad/launchpad.dart';
import 'launchpad/launchpad.dart';
import '../signature/storage/document_store.dart';
import '../signature/workspaces/discovery_session.dart';
import '../signature/workspaces/workspace_controller.dart';
import '../signature/workspaces/workspace_screen.dart';
import '../signature/privacy/privacy_journal.dart';
import '../signature/privacy/trust_receipt_screen.dart';
import '../signature/official_routes/official_routes_screen.dart';
import '../signature/commit_review/commit_review_screen.dart';
import '../signature/compatibility/compatibility_report.dart';
import '../signature/compatibility/compatibility_report_screen.dart';
import '../signature/compatibility/compatibility_profiles.dart';
import '../signature/handoff/handoff_gate.dart';
import '../signature/official_routes/review_request_screen.dart';
import 'components/wingman_components.dart';
import 'components/browser_chrome.dart';
import 'components/wingman_route.dart';
import 'app_route_observer.dart';
import 'home/home_screen.dart';
import 'discovery/visual_discovery_section.dart';
import 'home/focused_search_screen.dart';
import 'home/customize_home_screen.dart';
import 'design_system/ui_preferences.dart';
import 'design_system/app_build_info.dart';
import 'library/library_screen.dart';
import 'library/approved_reader.dart';
import 'settings/settings_screen.dart';
import 'protection/protection_screen.dart';
import 'protection/help_now_screen.dart';
import 'protection/policy_state_view.dart';
import '../live_content/live_content.dart';
import 'live_content/live_content_section.dart';
import 'live_content/live_content_feed_screen.dart';
import 'live_content/live_content_preferences_screen.dart';
import 'live_content/live_reading_list.dart';
import 'live_content/syndicated_article_screen.dart';

const _collections = <String, String>{
  'science': 'Science',
  'creative': 'Create something',
  'learning': 'Learning skills',
  'digital-life': 'Digital life',
  'outdoors': 'Outdoors',
  'support': 'Support',
  'home-projects': 'Home projects',
  'sports': 'Sports',
  'shopping': 'Shopping',
};

/// Offline resources and reviewed native websites share the same tab owner and
/// authoritative policy. Native websites additionally enforce resource scope.
class BrowserShell extends StatefulWidget {
  const BrowserShell({
    super.key,
    required this.state,
    required this.policy,
    this.signatures,
    this.session,
    this.handoff,
    this.liveContent,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final SignatureServices? signatures;
  final DiscoverySession? session;
  final HandoffController? handoff;
  final LiveContentController? liveContent;
  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell>
    with WidgetsBindingObserver {
  final _native = NativeBrowserService();
  final _queryController = TextEditingController();
  late final DiscoverySession _session;
  List<DiscoveryTab> get _tabs => _session.tabs;
  int get _activeTab => _session.active;
  set _activeTab(int v) {
    _session.active = v;
    _syncLiveContentContext();
  }

  int get _destination => _session.destination;
  set _destination(int v) => _session.destination = v;
  String get _query => _session.query;
  set _query(String v) => _session.query = v;
  String? get _collection => _session.collection;
  set _collection(String? v) => _session.collection = v;
  String? get _notice => _session.notice;
  set _notice(String? v) => _session.notice = v;
  bool _officialSearch = false;
  CompatibilityProfileRegistry? _compatibility;
  bool _covered = false;
  ProtectedWebCapabilities _capabilities = const ProtectedWebCapabilities();
  late final Listenable _launchpadChanges;
  final Map<String, ProtectedWebStatus> _webStatuses = {};
  final Map<String, int> _webRevisions = {};
  final Map<String, Uri> _webRequests = {};
  // In-memory ownership only. Window transfer tokens never enter tab restore.
  final Map<String, String> _webWindowTokens = {};
  final Map<String, String> _webWindowOpeners = {};
  final Map<String, BrowserEngine> _webControllers = {};
  final List<String> _liveOrder = [];
  // Four live renderers; other tabs restore their last address on selection.
  static const _maximumLiveTabs = 4;
  DateTime? _lastFeedAttempt;

  int _featureRouteDepth = 0;
  void _recheckLiveContent() => widget.liveContent?.recheckEligibility();

  void _syncLiveContentContext() {
    widget.liveContent?.setContext(
      widget.handoff?.blocksOwner == true
          ? LiveContentContext.handoff
          : _ephemeral
          ? LiveContentContext.private
          : _covered
          ? LiveContentContext.inactive
          : LiveContentContext.owner,
    );
  }

  Future<void> _refreshHomeContent() async {
    final feed = widget.liveContent;
    if (feed == null ||
        !mounted ||
        _ephemeral ||
        _covered ||
        widget.handoff?.blocksOwner == true ||
        (_lastFeedAttempt != null &&
            DateTime.now().difference(_lastFeedAttempt!) <
                const Duration(minutes: 15))) {
      return;
    }
    _lastFeedAttempt = DateTime.now();
    try {
      await feed.initialize();
      if (mounted &&
          !_ephemeral &&
          !_covered &&
          widget.handoff?.blocksOwner != true &&
          _tab.website == null &&
          _tab.resourceId == null &&
          _destination == 0 &&
          _query.isEmpty) {
        await feed.refresh();
      }
    } catch (_) {
      // The feed exposes its own state; browser navigation stays independent.
    }
  }

  void _retainEngine(DiscoveryTab owner, Uri uri) {
    if (!_webRequests.containsKey(owner.id)) _webRequests[owner.id] = uri;
    _liveOrder.remove(owner.id);
    _liveOrder.add(owner.id);
    while (_liveOrder.length > _maximumLiveTabs) {
      final evicted = _liveOrder.removeAt(0);
      _webControllers.remove(evicted);
      _webRequests.remove(evicted);
      _webWindowTokens.remove(evicted);
    }
  }

  void _persistSession() => _session.scheduleSave();
  final Map<String, ScrollController> _scrolls = {};
  ScrollController _scrollFor(String page) {
    final owner = _tab, key = '${_tab.id}:$page';
    // A detached controller creates a new ScrollPosition from its original
    // initial offset. Recreate it from this tab's latest saved position when
    // returning from a native article or another Home tab.
    final previous = _scrolls[key];
    if (previous != null && !previous.hasClients) {
      previous.dispose();
      _scrolls.remove(key);
    }
    return _scrolls.putIfAbsent(key, () {
      final controller = ScrollController(
        initialScrollOffset: owner.scrollOffsets[page] ?? 0,
        keepScrollOffset: false,
      );
      controller.addListener(() {
        if (controller.hasClients && _tabs.contains(owner)) {
          if (owner.scrollOffsets.length >= 52 &&
              !owner.scrollOffsets.containsKey(page)) {
            owner.scrollOffsets.remove(owner.scrollOffsets.keys.first);
          }
          owner.scrollOffsets[page] = controller.offset;
        }
      });
      return controller;
    });
  }

  DiscoveryTab get _tab => _tabs[_activeTab];
  bool get _ephemeral =>
      _tab.isPrivate || productEdition != ProductEdition.consumer;
  ContentContext get _context => productEdition == ProductEdition.consumer
      ? ContentContext.general
      : ContentContext.student;
  AdditionalRestrictions get _additional =>
      widget.state.protectedPreferences.additional;

  bool _eligibleId(String id, {bool? private}) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          id,
          context: _context,
          isPrivate: private ?? _tab.isPrivate,
        ),
        additional: _additional,
      )
      .isAllowed;

  SignatureServices? get _features {
    if (widget.signatures == null) return null;
    if (!_tab.isPrivate) return widget.signatures;
    if (_session.privateServices == null) {
      final service = SignatureServices(
        store: MemorySignatureDocumentStore(),
        eligible: (id) => _eligibleId(id, private: true),
        isPrivate: true,
        launchpadEligibility: LaunchpadEligibilityService(
          resourceEligible: (id) => _eligibleId(id, private: true),
          resourceLookup: widget.policy.resource,
          websiteAvailable: () => widget.policy.liveAvailable(isPrivate: true),
          evaluateWebsite: (uri) => widget.policy.policy.evaluate(
            PolicyRequest.navigation(uri, context: _context, isPrivate: true),
            additional: _additional,
          ),
        ),
      );
      _session.privateServices = service;
      service.addListener(_changed);
      service.workspaces.addListener(_changed);
      service.ui.addListener(_changed);
      service.launchpad.addListener(_changed);
      unawaited(service.initialize());
    }
    return _session.privateServices;
  }

  bool get _toolsReady => _features?.initialized == true;
  Future<void> _pushFeature(
    Widget page, {
    ValueChanged<Route<void>>? onRoute,
  }) async {
    FocusScope.of(context).unfocus();
    final route = WingmanRoute<void>(builder: (_) => page);
    onRoute?.call(route);
    setState(() => _featureRouteDepth++);
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      _featureRouteDepth--;
      if (mounted) setState(() {});
    }
  }

  void _openFeatureResource(String id) {
    if (!mounted) return;
    final r = widget.policy.resource(id);
    if (r == null || !_eligible(r)) {
      _deny(
        widget.policy.policy.evaluate(
          PolicyRequest.bundled(
            id,
            context: _context,
            isPrivate: _tab.isPrivate,
          ),
          additional: _additional,
        ),
      );
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    _open(r);
  }

  void _official([String query = '']) {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final origin = _tab;
    _pushFeature(
      OfficialRoutesScreen(
        policy: widget.policy,
        additional: () => _additional,
        journal: _features!.journal,
        onOpenResource: _openFeatureResource,
        isPrivate: _tab.isPrivate,
        context: _context,
        initialQuery: query,
        canContinue: () => _validOrigin(origin),
      ),
    );
  }

  void _commitReview({ApprovedResource? resource}) {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final service = _features!, private = _ephemeral;
    final origin = _tab;
    _pushFeature(
      CommitReviewScreen(
        policy: widget.policy,
        additional: () => _additional,
        journal: service.journal,
        isPrivate: private,
        context: _context,
        initialResource: resource,
        savedAnalyses: () => service.workspaces.snapshot.analyses,
        onSave: service.workspaces.saveAnalysis,
        onDelete: service.workspaces.deleteAnalysis,
        canContinue: () => _validOrigin(origin),
      ),
    );
  }

  void _receipt() {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final service = _features!, tabId = _tab.id;
    _pushFeature(
      TrustReceiptScreen(
        journal: service.journal,
        configuration: () => service.configuration(widget.policy),
        canContinue: () =>
            mounted &&
            _tab.id == tabId &&
            !(widget.handoff?.blocksOwner ?? false),
      ),
    );
  }

  void _repair() {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final service = _features!, tabId = _tab.id;
    _pushFeature(
      CompatibilityReportScreen(
        journal: service.journal,
        registry: _compatibility,
        diagnostics: CompatibilityDiagnostics(
          appVersion: AppBuildInfo.current.version,
          policyVersion: MandatorySafetyPolicy.version,
          capability: widget.policy.liveAvailable(isPrivate: _tab.isPrivate)
              ? CompatibilityCapability.reviewedScriptlessWeb
              : CompatibilityCapability.bundledReader,
        ),
        canContinue: () =>
            mounted &&
            _tab.id == tabId &&
            !(widget.handoff?.blocksOwner ?? false),
      ),
    );
  }

  void _handoff(List<String> ids) {
    final controller = widget.handoff;
    if (_tab.isPrivate || controller == null || !controller.canStart) {
      _pushFeature(
        const WingmanPage(
          title: 'Hand It Over',
          child: WingmanStatus(
            title: 'Sharing is unavailable in this session',
            message:
                'Hand It Over shares selected reviewed public text on supported native devices. Private content cannot be shared, and this Web companion does not provide verified owner isolation. No owner content has been exposed.',
            tone: WingmanTone.caution,
          ),
        ),
      );
      return;
    }
    if (ids.isEmpty) {
      _chooseHandoff();
      return;
    }
    final preview = controller.preview(ids, additional: _additional);
    if (preview == null) {
      _deny();
      return;
    }
    _pushFeature(HandoffSetupPage(controller: controller, preview: preview));
  }

  Future<void> _chooseHandoff() async {
    final origin = _tab, selected = <String>{};
    final chosen = await showWingmanSheet<List<String>>(
      context: context,
      builder: (sheet) => ListenableBuilder(
        listenable: widget.policy,
        builder: (sheet, _) => StatefulBuilder(
          builder: (sheet, update) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose what to share',
                  style: Theme.of(sheet).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select up to eight reviewed public articles. You will inspect the exact text and set a fresh owner-return code before sharing starts.',
                ),
                for (final resource in widget.policy.catalog.where(_eligible))
                  CheckboxListTile(
                    title: Text(resource.title),
                    value: selected.contains(resource.id),
                    onChanged:
                        !selected.contains(resource.id) && selected.length >= 8
                        ? null
                        : (value) => update(() {
                            value == true
                                ? selected.add(resource.id)
                                : selected.remove(resource.id);
                          }),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheet),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(sheet, selected.toList()),
                      child: const Text('Review selection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != null && _validOrigin(origin)) _handoff(chosen);
  }

  void _workspaces({String? spaceId, String? taskId, bool tasks = false}) {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final service = _features!;
    final origin = _tab;
    var active = true;
    Route<void>? originatingRoute;
    bool currentIntent() =>
        mounted &&
        active &&
        originatingRoute?.isCurrent == true &&
        _tab.id == origin.id;
    unawaited(
      _pushFeature(
        WorkspaceScreen(
          controller: service.workspaces,
          policy: widget.policy,
          additional: () => _additional,
          journal: service.journal,
          readingIds: () => _ephemeral
              ? const []
              : widget.state.protectedPreferences.readingIds.toList(),
          onOpenResource: _openFeatureResource,
          onResumeTask: (task) =>
              _resumeTask(task, service, origin, currentIntent),
          onAssociateCurrentTab: (id) => _associateTask(id, service, origin),
          onFinishTask: (task, close) async {
            await _finishTask(
              task,
              close && currentIntent(),
              private: origin.isPrivate,
            );
          },
          onDetachTab: (task, tab) =>
              _detachTaskTab(task, tab, service, origin.isPrivate),
          onDeleteTask: (task) => _deleteTask(task, service, origin.isPrivate),
          onOfficialSearch: _official,
          onHandoff: !_tab.isPrivate && widget.handoff?.canStart == true
              ? _handoff
              : null,
          initialSpaceId: spaceId,
          initialTaskId: taskId,
          initialTasks: tasks,
          contentContext: _context,
          isPrivate: _ephemeral,
        ),
        onRoute: (route) => originatingRoute = route,
      ).whenComplete(() => active = false),
    );
  }

  Future<void> _associateTask(
    String taskId,
    SignatureServices service,
    DiscoveryTab origin,
  ) async {
    final model = service.workspaces;
    if (origin.taskId != null && origin.taskId != taskId) {
      throw StateError('Detach this tab from its other task first.');
    }
    final resource = origin.resourceId;
    await model.associateTab(
      taskId,
      origin.id,
      resource != null && _eligibleId(resource, private: origin.isPrivate)
          ? resource
          : null,
    );
    if (_tabs.contains(origin)) origin.taskId = taskId;
    if (mounted) setState(() {});
  }

  Future<void> _resumeTask(
    FinishWorkspace task,
    SignatureServices service,
    DiscoveryTab origin,
    bool Function() currentIntent,
  ) async {
    final model = service.workspaces, private = origin.isPrivate;
    if (!currentIntent()) return;
    final references = task.tabs.isEmpty
        ? [const TaskTabReference(tabId: 'new-task-tab')]
        : task.tabs;
    DiscoveryTab? first;
    for (final reference in references) {
      if (!currentIntent()) return;
      var tab = _tabs
          .where(
            (t) =>
                t.id == reference.tabId &&
                t.taskId == task.id &&
                t.isPrivate == private,
          )
          .firstOrNull;
      if (tab == null) {
        if (_tabs.length >= 12) {
          throw StateError('Close a tab before restoring more task tabs.');
        }
        // A restored document never annexes an unrelated live tab with a
        // matching ID. New ownership is established on a fresh tab instead.
        tab = DiscoveryTab(isPrivate: private)..taskId = task.id;
        if (reference.resourceId != null &&
            _eligibleId(reference.resourceId!)) {
          tab.visit(reference.resourceId);
        }
        await model.replaceRestoredTab(
          task.id,
          reference.tabId,
          tab.id,
          tab.resourceId,
        );
        if (!currentIntent()) return;
        _tabs.add(tab);
      }
      first ??= tab;
    }
    if (first != null && mounted && currentIntent()) {
      setState(() {
        _activeTab = _tabs.indexOf(first!);
        _destination = 0;
        _query = '';
        _queryController.clear();
        _notice = null;
      });
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _deleteTask(
    String taskId,
    SignatureServices service,
    bool private,
  ) async {
    await service.workspaces.deleteTask(taskId);
    for (final tab in _tabs.where(
      (t) => t.taskId == taskId && t.isPrivate == private,
    )) {
      tab.taskId = null;
    }
  }

  Future<void> _detachTaskTab(
    String taskId,
    String tabId,
    SignatureServices service,
    bool private,
  ) async {
    await service.workspaces.detachTab(taskId, tabId);
    for (final tab in _tabs.where(
      (t) => t.id == tabId && t.taskId == taskId && t.isPrivate == private,
    )) {
      tab.taskId = null;
    }
  }

  Future<void> _finishTask(
    FinishWorkspace task,
    bool closeTabs, {
    required bool private,
  }) async {
    if (closeTabs) {
      _session.closeTaskTabs(task.id, private: private);
      if (mounted) {
        setState(() {
          _query = '';
          _queryController.clear();
          _destination = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Associated task tabs closed.'),
            action: private || !_session.canUndoTaskClosure
                ? null
                : SnackBarAction(
                    label: 'Undo',
                    onPressed: () {
                      if (!mounted || _tab.isPrivate) return;
                      setState(() => _session.undoTaskClosure(_eligibleId));
                    },
                  ),
          ),
        );
      }
    }
    for (final tab in _tabs.where(
      (t) => t.taskId == task.id && t.isPrivate == private,
    )) {
      tab.taskId = null;
    }
    if (closeTabs && private && !_tabs.any((t) => t.isPrivate)) {
      // Remove the private workspace route before destroying its controllers.
      Navigator.of(context).popUntil((route) => route.isFirst);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _session.clearPrivateServicesIfUnused();
        if (mounted) setState(() {});
      });
    }
  }

  void _recordTaskNavigation() {
    _persistSession();
    final task = _tab.taskId, service = _features;
    if (task != null && service?.initialized == true) {
      unawaited(
        _run(
          () => service!.workspaces.associateTab(task, _tab.id, _current()?.id),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? DiscoverySession();
    _launchpadChanges = Listenable.merge([widget.policy, widget.state]);
    _queryController.text = _query;
    widget.signatures?.addListener(_changed);
    widget.signatures?.workspaces.addListener(_changed);
    widget.signatures?.ui.addListener(_changed);
    widget.signatures?.launchpad.addListener(_changed);
    _session.privateServices?.addListener(_changed);
    _session.privateServices?.workspaces.addListener(_changed);
    _session.privateServices?.ui.addListener(_changed);
    _session.privateServices?.launchpad.addListener(_changed);
    _compatibility = CompatibilityProfileRegistry(policy: widget.policy);
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_changed);
    widget.policy.addListener(_changed);
    widget.state.addListener(_recheckLiveContent);
    widget.policy.addListener(_recheckLiveContent);
    widget.liveContent?.addListener(_changed);
    widget.handoff?.addListener(_syncLiveContentContext);
    _syncLiveContentContext();
    unawaited(widget.liveContent?.initialize());
    unawaited(_bindIncoming());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.liveContent?.removeListener(_changed);
    widget.handoff?.removeListener(_syncLiveContentContext);
    widget.liveContent?.setContext(LiveContentContext.inactive);
    widget.state.removeListener(_changed);
    widget.policy.removeListener(_changed);
    widget.state.removeListener(_recheckLiveContent);
    widget.policy.removeListener(_recheckLiveContent);
    widget.signatures?.removeListener(_changed);
    widget.signatures?.workspaces.removeListener(_changed);
    widget.signatures?.ui.removeListener(_changed);
    widget.signatures?.launchpad.removeListener(_changed);
    _session.privateServices?.removeListener(_changed);
    _session.privateServices?.workspaces.removeListener(_changed);
    _session.privateServices?.ui.removeListener(_changed);
    _session.privateServices?.launchpad.removeListener(_changed);
    if (widget.session == null) _session.dispose();
    _compatibility?.dispose();
    _native.dispose();
    _queryController.dispose();
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    _scrolls.clear();
    super.dispose();
  }

  Future<void> _refreshNativeCapabilities() async {
    if (kIsWeb) return;
    final capabilities = await ProtectedWebBridge.capabilities();
    if (!mounted) return;
    setState(() => _capabilities = capabilities);
    widget.policy.configureLiveBrowsing(
      widget.policy.policy.livePolicy ?? const LiveBrowsingPolicy.unavailable(),
      nativeAvailable: capabilities.supported,
      privateAvailable: capabilities.privateAvailable,
      strictSearchAvailable: capabilities.strictSearchAvailable,
    );
  }

  Future<void> _bindIncoming() async {
    Uri? pending;
    var initialized = false;
    try {
      await _native.initialize(
        onIncomingUri: (uri) {
          if (!initialized) {
            pending = uri;
            return;
          }
          if (mounted && !(widget.handoff?.blocksOwner ?? false)) {
            _navigateWebsite(uri);
          }
        },
      );
      await _refreshNativeCapabilities();
      initialized = true;
      if (pending != null &&
          mounted &&
          !(widget.handoff?.blocksOwner ?? false)) {
        _navigateWebsite(pending!);
      }
    } catch (_) {
      // A capability/link failure cannot grant browsing authority.
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _pruneScrolls() {
    final validTabs = _tabs.map((t) => t.id).toSet();
    _webStatuses.removeWhere((id, _) => !validTabs.contains(id));
    _webRevisions.removeWhere((id, _) => !validTabs.contains(id));
    _webRequests.removeWhere((id, _) => !validTabs.contains(id));
    _webWindowTokens.removeWhere((id, _) => !validTabs.contains(id));
    _webWindowOpeners.removeWhere((id, _) => !validTabs.contains(id));
    _webControllers.removeWhere((id, _) => !validTabs.contains(id));
    _liveOrder.removeWhere((id) => !validTabs.contains(id));
    _persistSession();
    for (final key
        in _scrolls.keys
            .where((k) => !validTabs.contains(k.split(':').first))
            .toList()) {
      _scrolls.remove(key)?.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNativeCapabilities());
    }
    if (state != AppLifecycleState.resumed) unawaited(_session.flush());
    if (mounted) setState(() => _covered = state != AppLifecycleState.resumed);
    _syncLiveContentContext();
  }

  bool _eligible(ApprovedResource r) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          r.id,
          context: _context,
          isPrivate: _tab.isPrivate,
        ),
        additional: _additional,
      )
      .isAllowed;
  ApprovedResource? _current() {
    final id = _tab.resourceId;
    final r = id == null ? null : widget.policy.resource(id);
    return r != null && _eligible(r) ? r : null;
  }

  void _home() {
    setState(() {
      _tab.visit(null);
      _destination = 0;
      _query = '';
      _collection = null;
      _queryController.clear();
      _notice = null;
    });
    _recordTaskNavigation();
  }

  void _open(ApprovedResource r) {
    if (!_eligible(r)) {
      _deny(
        widget.policy.policy.evaluate(
          PolicyRequest.bundled(
            r.id,
            context: _context,
            isPrivate: _tab.isPrivate,
          ),
          additional: _additional,
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _tab.visit(r.id);
      _destination = 0;
      _notice = null;
    });
    _recordTaskNavigation();
  }

  PolicyDecision _websiteDecision(Uri uri, {bool? isPrivate}) =>
      widget.policy.policy.evaluate(
        PolicyRequest.navigation(
          uri,
          context: _context,
          isPrivate: isPrivate ?? _tab.isPrivate,
        ),
        additional: _additional,
      );

  void _navigateWebsite(
    Uri uri, {
    bool newTab = false,
    String? windowToken,
    String? openerTabId,
  }) {
    if (!_validOrigin(_tab)) return;
    try {
      uri =
          const StrictSearchPolicy().rewriteProviderInput(uri.toString()) ??
          uri;
    } on FormatException {
      _deny();
      return;
    }
    if (kIsWeb &&
        productEdition == ProductEdition.consumer &&
        const StrictSearchPolicy().acceptsCanonical(uri) &&
        widget.policy.searchAvailable(additional: _additional)) {
      navigateCompanion(uri);
      return;
    }
    if (kIsWeb && productEdition == ProductEdition.consumer) {
      final decision = widget.policy.consumerProtection.assessNavigation(
        uri,
        additional: _additional,
      );
      if (uri.scheme != 'https' ||
          !decision.isAllowed ||
          widget.policy.policy
              .blockedBrowsingUrls(_additional)
              .contains(uri.toString())) {
        _deny(decision);
        return;
      }
      // A user-selected destination opens top-level in the host browser.
      navigateCompanion(uri);
      return;
    }
    final decision = _websiteDecision(uri);
    if (!decision.isAllowed) {
      _deny(decision);
      return;
    }
    if (newTab && _tabs.length >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The 12-tab limit is reached. Close a tab first.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      if (newTab) {
        _tabs.add(DiscoveryTab(isPrivate: _tab.isPrivate));
        _activeTab = _tabs.length - 1;
        if (windowToken != null) _webWindowTokens[_tab.id] = windowToken;
        if (openerTabId != null) _webWindowOpeners[_tab.id] = openerTabId;
      }
      _tab.visitWebsite(uri);
      _webRequests[_tab.id] = uri;
      _retainEngine(_tab, uri);
      _webStatuses.remove(_tab.id);
      _webRevisions[_tab.id] = (_webRevisions[_tab.id] ?? 0) + 1;
      _destination = 0;
      _query = '';
      _collection = null;
      _queryController.clear();
      _notice = null;
    });
    _recordTaskNavigation();
  }

  Widget _websiteView(DiscoveryTab owner, Uri request, {required bool active}) {
    return ProtectedWebSurface(
      key: ValueKey('live-${owner.id}'),
      tabId: owner.id,
      url: request,
      isPrivate: owner.isPrivate,
      active: active,
      revision: _webRevisions[owner.id] ?? 0,
      windowToken: _webWindowTokens[owner.id],
      restrictions: widget.policy.nativeConsumerConfiguration(_additional),
      policyChanges: _launchpadChanges,
      canOpen: (target) =>
          mounted &&
          _tabs.contains(owner) &&
          !(widget.handoff?.blocksOwner ?? false) &&
          _websiteDecision(target, isPrivate: owner.isPrivate).isAllowed,
      onController: (controller) {
        _webControllers[owner.id] = controller;
        _webWindowTokens.remove(owner.id);
      },
      onNavigation: (target) {
        if (!_validOrigin(owner)) return;
        final destination =
            const StrictSearchPolicy().unwrapResultLink(target) ?? target;
        _navigateWebsite(destination);
      },
      onNewWindowWithToken: (target, token) {
        if (_validOrigin(owner)) {
          _navigateWebsite(
            target,
            newTab: true,
            windowToken: token,
            openerTabId: owner.id,
          );
        }
      },
      onCloseRequested: () {
        if (!mounted ||
            !_tabs.contains(owner) ||
            (widget.handoff?.blocksOwner ?? false)) {
          return;
        }
        final openerId = _webWindowOpeners[owner.id];
        if (openerId == null) return;
        final wasActive = owner == _tab;
        _removeTabs([owner]);
        final openerIndex = _tabs.indexWhere((tab) => tab.id == openerId);
        if (wasActive && openerIndex >= 0) {
          setState(() => _activeTab = openerIndex);
        }
      },
      onBlocked: (message) {
        if (_validOrigin(owner)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
      onStatus: (status) {
        if (!mounted ||
            !_tabs.contains(owner) ||
            (widget.handoff?.blocksOwner ?? false)) {
          return;
        }
        setState(() {
          _webStatuses[owner.id] = status;
          if (status.url != null &&
              status.error == null &&
              owner.website != null) {
            // The engine owns web history. Replace metadata without issuing a
            // second load or adding fake entries for every progress callback.
            owner.trail[owner.position] = 'web:${status.url}';
          }
        });
        if (status.committed) _persistSession();
      },
    );
  }

  Widget _contentBody(ApprovedResource? resource, Uri? website) {
    final showingWeb = _destination == 0 && website != null && _query.isEmpty;
    if (showingWeb && _websiteDecision(website).isAllowed) {
      _retainEngine(_tab, website);
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final owner in _tabs.where(
                (t) =>
                    _webRequests.containsKey(t.id) &&
                    _websiteDecision(
                      _webStatuses[t.id]?.url ?? _webRequests[t.id]!,
                      isPrivate: t.isPrivate,
                    ).isAllowed,
              ))
                Offstage(
                  key: ValueKey('engine-${owner.id}'),
                  offstage: _covered || !showingWeb || owner != _tab,
                  child: _websiteView(
                    owner,
                    _webRequests[owner.id]!,
                    active: !_covered && showingWeb && owner == _tab,
                  ),
                ),
              if (!showingWeb)
                _destination == 0 && resource != null
                    ? _article(resource)
                    : _destination != 0 ||
                          _query.isNotEmpty ||
                          _collection != null
                    ? _results()
                    : _homeView(),
              if (showingWeb && !_websiteDecision(website).isAllowed)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'This destination is blocked or protection needs recovery. Use Home or enter another address.',
                    ),
                  ),
                ),
              if (_covered)
                const ColoredBox(
                  color: Color(0xff07182e),
                  child: Center(
                    child: Icon(
                      Icons.shield_outlined,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _historyStep(bool forward) {
    final engine = _webControllers[_tab.id];
    final status = _webStatuses[_tab.id];
    if (_tab.website != null &&
        engine != null &&
        (forward ? status?.canGoForward == true : status?.canGoBack == true)) {
      unawaited(forward ? engine.forward() : engine.back());
      return;
    }
    final next = _tab.position + (forward ? 1 : -1);
    if (next < 0 || next >= _tab.trail.length) return;
    setState(() {
      _tab.position = next;
      _destination = 0;
      _query = '';
      final website = _tab.website;
      if (website != null && _webStatuses[_tab.id]?.url != website) {
        _webRequests[_tab.id] = website;
        _webRevisions[_tab.id] = (_webRevisions[_tab.id] ?? 0) + 1;
      }
    });
    _recordTaskNavigation();
  }

  void _deny([PolicyDecision? rejected]) {
    FocusScope.of(context).unfocus();
    setState(() {
      _destination = 0;
      _query = '';
      _collection = null;
      _queryController.clear();
      _notice =
          'This destination is blocked by the current protection policy or requires a supported capability.';
    });
    final decision =
        rejected ??
        widget.policy.policy.evaluate(
          PolicyRequest(
            operation: PolicyOperation.navigate,
            context: _context,
            isPrivate: _tab.isPrivate,
          ),
          additional: _additional,
        );
    _pushFeature(
      PolicyStateView(
        decision: decision,
        onHome: _returnHome,
        onExplore: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          _explore();
        },
        onBack: () => Navigator.pop(context),
        onRequestReview: _review,
        onHelpNow: _helpNow,
      ),
    );
  }

  void _search(String input, {bool web = false}) {
    if (_officialSearch && _features?.initialized == true) {
      _official(input);
      return;
    }
    final value = input.trim();
    if (value.contains('%')) {
      // Encoded schemes are not ordinary search terms or address authority.
      // Keep harmless percentage text searchable without decoding the query
      // that will be sent to the provider.
      try {
        final decoded = Uri.decodeComponent(value);
        if (decoded != value &&
            RegExp(
              r'^[a-z][a-z0-9+.-]*:',
              caseSensitive: false,
            ).hasMatch(decoded)) {
          _deny();
          return;
        }
      } on FormatException {
        // The URL/query policy below handles malformed input in its own scope.
      }
    }
    // An address is checked before search; provider options are rebuilt before
    // URI normalization can erase an ambiguous literal path.
    final scheme = RegExp(
      r'^([a-z][a-z0-9+.-]*):',
      caseSensitive: false,
    ).firstMatch(value)?.group(1)?.toLowerCase();
    final addressScheme =
        const {
          'http',
          'https',
          'file',
          'data',
          'javascript',
          'about',
          'intent',
          'blob',
          'mailto',
          'tel',
          'ftp',
          'wingman',
        }.contains(scheme) ||
        value.contains('://');
    final bareAddress =
        !value.contains(RegExp(r'\s')) &&
        RegExp(
          r'^[^\s/]+\.[a-z]{2,}(?:[/?\x23:]|$)',
          caseSensitive: false,
        ).hasMatch(value);
    if (addressScheme || bareAddress) {
      try {
        final explicit = RegExp(
          r'^[a-z][a-z0-9+.-]*:',
          caseSensitive: false,
        ).hasMatch(value);
        final provider = const StrictSearchPolicy().rewriteProviderInput(
          explicit ? value : 'https://$value',
        );
        _navigateWebsite(
          provider ?? Uri.parse(explicit ? value : 'https://$value'),
        );
      } catch (_) {
        _deny();
      }
      return;
    }
    if (web) {
      try {
        _navigateWebsite(const StrictSearchPolicy().buildQuery(input));
      } on FormatException catch (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    FocusScope.of(context).unfocus();
    _features?.journal.record(
      PrivacyActivity.localCatalogSearch,
      PrivacyOutcome.completed,
    );
    setState(() {
      _tab.visit(null);
      _destination = 0;
      _query = value;
      _notice = null;
    });
  }

  bool _validOrigin(DiscoveryTab origin) =>
      mounted &&
      !_covered &&
      _tab.id == origin.id &&
      !(widget.handoff?.blocksOwner ?? false);

  Future<void> _focusedSearch() async {
    final origin = _tab;
    final intent = await Navigator.of(context).push<SearchIntent>(
      MaterialPageRoute(
        builder: (_) => FocusedSearchScreen(
          policy: widget.policy,
          additional: () => _additional,
          contentContext: _context,
          isPrivate: origin.isPrivate,
          localSuggestions: widget.state.settings.localSuggestions,
          initialQuery: _tab.website == null
              ? _query
              : const StrictSearchPolicy().acceptsCanonical(_tab.website!)
              ? _tab.website!.queryParameters['q'] ?? ''
              : _tab.website.toString(),
        ),
      ),
    );
    if (intent == null || !_validOrigin(origin)) return;
    _officialSearch = intent.official;
    _search(intent.query, web: intent.web);
  }

  void _explore() => setState(() {
    _destination = 3;
    _query = '';
    _collection = null;
    _notice = null;
  });

  @override
  Widget build(BuildContext context) {
    final resource = _current();
    final website = _tab.website;
    final websiteAllowed =
        website != null && _websiteDecision(website).isAllowed;
    final wide =
        kIsWeb &&
        MediaQuery.sizeOf(context).width >= WingmanTokens.compact &&
        MediaQuery.sizeOf(context).height >= 640 &&
        MediaQuery.textScalerOf(context).scale(16) < 28;
    final body = Column(
      children: [
        if (!kIsWeb &&
            productEdition == ProductEdition.consumer &&
            !widget.policy.consumerProtection.isUsable)
          _banner(
            'Protection needs recovery. Browsing is closed until a verified baseline is restored. Reopen Wingman or install a verified update.',
          ),
        if (_ephemeral)
          _banner(
            _tab.isPrivate
                ? 'Private session · Same protection, no saved activity'
                : 'Student experience · No account required',
          ),
        Expanded(child: _contentBody(resource, website)),
      ],
    );
    // The main route consumes Back only when browser history can move. A
    // pushed feature route has its own Navigator pop and never advances a tab.
    final canGoBack =
        _tab.position > 0 || _webStatuses[_tab.id]?.canGoBack == true;
    return PopScope<Object?>(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_covered && _featureRouteDepth == 0 && canGoBack) {
          _historyStep(false);
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: null,
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.all(12),
                        child: WingmanBrand(wordmark: false),
                      ),
                      onDestinationSelected: (value) => switch (value) {
                        0 => _home(),
                        1 => _library(),
                        2 => _workspaces(),
                        3 => _showTabs(),
                        _ => _menu(),
                      },
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          label: Text('Home'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.bookmark_border),
                          label: Text('Library'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          label: Text('Spaces'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.tab_outlined),
                          label: Text('Sessions'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.menu),
                          label: Text('Menu'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        ),
        bottomNavigationBar: wide && kIsWeb
            ? null
            : BrowserDock(
                onHome: _home,
                onTabs: _showTabs,
                onMenu: _menu,
                onLibrary: _library,
                onSpaces: () => _workspaces(),
                tabCount: _tabs.length,
                isPrivate: _tab.isPrivate,
                resourceTitle: website != null
                    ? websiteAllowed
                          ? website.host
                          : 'Unavailable website'
                    : resource == null
                    ? null
                    : 'Reviewed offline article',
                isLive: website != null,
                isLoading: _webStatuses[_tab.id]?.loading == true,
                onReload: websiteAllowed
                    ? () {
                        final engine = _webControllers[_tab.id];
                        if (engine == null) {
                          _navigateWebsite(website);
                          return;
                        }
                        unawaited(
                          _webStatuses[_tab.id]?.loading == true
                              ? engine.stop()
                              : engine.reload(),
                        );
                      }
                    : null,
                onAddress: _focusedSearch,
                onPageInfo: () => _pageInfo(resource),
                onBack: canGoBack ? () => _historyStep(false) : null,
                onForward:
                    _tab.position + 1 < _tab.trail.length ||
                        _webStatuses[_tab.id]?.canGoForward == true
                    ? () => _historyStep(true)
                    : null,
              ),
      ),
    );
  }

  Widget _banner(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    color: WingmanTokens.of(context).raised,
    child: Text(text, textAlign: TextAlign.center),
  );

  Widget _homeView() {
    // Owned feature routes can change which Home items remain eligible. Keep
    // its saved offset, but do not lay out a covered, shrinking viewport: that
    // can leave clipped accessibility nodes without geometry in Flutter.
    // _scrollFor restores and clamps the position when Home becomes visible.
    if (_featureRouteDepth > 0) return const SizedBox.shrink();
    if (!_ephemeral) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshHomeContent());
      });
    }
    final model = _features?.workspaces;
    final service = _features;
    final launchpadActions = _launchpadActions();
    final homeOrigin = _tab;
    return HomeScreen(
      launchpad: service?.initialized == true
          ? LaunchpadSection(
              controller: service!.launchpad,
              actions: launchpadActions,
              isPrivate: _ephemeral,
            )
          : const WingmanStatus(
              title: 'Opening your Launchpad',
              message:
                  'Your saved choices will appear when local storage is ready.',
            ),
      contentCollections: service?.initialized == true
          ? LaunchpadContentCollections(
              controller: service!.launchpad,
              actions: launchpadActions,
              isPrivate: _ephemeral,
            )
          : null,
      websiteDiscovery: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_ephemeral) ...[
            LiveContentSection(
              controller: widget.liveContent,
              preview: true,
              canContinue: () => !_ephemeral && _validOrigin(homeOrigin),
              onViewAll: _liveContentFeed,
              onOpen: _openLiveContent,
              onOpenUri: _openLiveContentLicense,
              onPin: _pinLiveContent,
              onPreferences: _liveContentPreferences,
              onReadingList: () => _library(LibrarySection.readingList),
            ),
            const SizedBox(height: 28),
          ],
          VisualDiscoverySection(destinations: _homeInspiration()),
        ],
      ),
      preferences: (_features?.ui.snapshot ?? UiPreferences()).copyWith(
        showSpaces:
            (_features?.ui.snapshot.showSpaces ?? true) &&
            (model?.snapshot.spacesEnabled ?? true),
      ),
      resources: widget.policy.catalog.where(_eligible).toList(),
      onSearch: _focusedSearch,
      onSettings: _settings,
      onProtection: _protection,
      onOfficial: () => _official(),
      onLibrary: _library,
      onCustomize: _customize,
      onExplore: _explore,
      onOpen: _openFeatureResource,
      onSpaces: () => _workspaces(),
      onTask: (id) => _workspaces(taskId: id),
      task: model?.snapshot.tasks
          .where((t) => t.status == FinishStatus.active)
          .firstOrNull,
      spaceCards: model?.snapshot.spacesEnabled == true
          ? [
              for (final space in model!.snapshot.spaces.take(3))
                Card(
                  child: InkWell(
                    onTap: () => _workspaces(spaceId: space.id),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(switch (space.kind) {
                            SpaceKind.homeProjects => Icons.home_work_outlined,
                            SpaceKind.learning => Icons.school_outlined,
                            SpaceKind.sports =>
                              Icons.sports_basketball_outlined,
                          }, color: WingmanTokens.of(context).action),
                          const SizedBox(height: 12),
                          Text(
                            space.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${space.savedIds.length} saved resources',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ]
          : const [],
      isPrivate: _tab.isPrivate,
      policyUsable: widget.policy.status.usable,
      notice: _notice,
      storageError:
          widget.state.storageError ??
          _features?.ui.storageError ??
          _features?.launchpad.storageError ??
          model?.storageError,
      controller: _scrollFor('home'),
    );
  }

  List<LiveSiteRecord> _discoverableWebsites({String query = ''}) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty);
    return widget.policy.liveSites.where((site) {
      // Even a disabled card must not disclose a restricted collection.
      final decision = widget.policy.policy.livePolicy?.assessNavigation(
        Uri.parse(site.entryUrl),
        context: _context,
        additional: _additional,
        now: widget.policy.clock.now(),
      );
      final text =
          '${site.title} ${site.description} ${site.collection} ${site.entryUrl}'
              .toLowerCase();
      return site.enabled &&
          decision?.isAllowed == true &&
          (_collection == null || site.collection == _collection) &&
          terms.every(text.contains);
    }).toList();
  }

  VisualDiscoveryDestination _websiteCard(LiveSiteRecord site) {
    final origin = _tab;
    final uri = Uri.parse(site.entryUrl);
    final allowed = _websiteDecision(uri).isAllowed;
    return VisualDiscoveryDestination(
      id: site.id,
      title: site.title,
      description: site.description,
      kindLabel: 'Live website · ${Uri.parse(site.entryUrl).host}',
      artwork: site.id == 'nasa-moon'
          ? HomeArtwork.earthrise
          : HomeArtwork.none,
      unavailableReason:
          'Use the supported Android or iOS app to open this reviewed website.',
      onOpen: allowed
          ? () {
              if (_validOrigin(origin)) _navigateWebsite(uri);
            }
          : null,
    );
  }

  List<VisualDiscoveryDestination> _homeInspiration() {
    final origin = _tab;
    final destinations = <VisualDiscoveryDestination>[
      if (widget.policy.liveAvailable(isPrivate: origin.isPrivate))
        for (final site in _discoverableWebsites()) _websiteCard(site),
    ];
    for (final entry in const {
      'notice-nature': HomeArtwork.forest,
      'drawing-with-shapes': HomeArtwork.creative,
      'moon-phases': HomeArtwork.earthrise,
    }.entries) {
      if (destinations.length >= 5) break;
      final resource = widget.policy.resource(entry.key);
      if (resource == null || !_eligible(resource)) continue;
      destinations.add(
        VisualDiscoveryDestination(
          id: resource.id,
          title: resource.title,
          description: resource.summary,
          kindLabel:
              'Offline article · ${_collections[resource.collection] ?? 'Explore'}',
          artwork: entry.value,
          onOpen: () {
            if (_validOrigin(origin)) _open(resource);
          },
        ),
      );
    }
    return destinations;
  }

  Widget _results() {
    final websites = _discoverableWebsites(query: _query);
    final resources = widget.policy
        .search(_query, additional: _additional, context: _context)
        .where(_eligible)
        .where((r) => _collection == null || r.collection == _collection)
        .toList();
    return ListView(
      controller: _scrollFor('results'),
      padding: EdgeInsets.all(
        WingmanTokens.gutter(MediaQuery.sizeOf(context).width),
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to Home',
                      onPressed: _home,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        _query.isEmpty
                            ? 'Explore reviewed resources'
                            : 'Search results',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search',
                      onPressed: _focusedSearch,
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _query.isEmpty
                      ? 'Reviewed website scopes and installed articles. Library search stays on this device.'
                      : 'Matches for “$_query” · On this device',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All topics'),
                      selected: _collection == null,
                      onSelected: (_) => setState(() => _collection = null),
                    ),
                    for (final entry in _collections.entries)
                      if (!_additional.blockedCollections.contains(entry.key))
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _collection == entry.key,
                          onSelected: (_) =>
                              setState(() => _collection = entry.key),
                        ),
                  ],
                ),
                const SizedBox(height: 24),
                if (websites.isNotEmpty) ...[
                  Text(
                    'Reviewed websites',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Real pages and images in the native app. Scripts, forms and sign-in are unavailable in this pilot.',
                  ),
                  const SizedBox(height: 12),
                  for (final site in websites)
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(site.title),
                        subtitle: Text(
                          '${site.description}\n${Uri.parse(site.entryUrl).host}',
                        ),
                        trailing: Icon(
                          _websiteDecision(Uri.parse(site.entryUrl)).isAllowed
                              ? Icons.open_in_browser
                              : Icons.lock_outline,
                        ),
                        onTap: () => _navigateWebsite(Uri.parse(site.entryUrl)),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
                if (resources.isNotEmpty) ...[
                  Text(
                    'Offline articles',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                ],
                if (resources.isEmpty && websites.isEmpty)
                  WingmanEmptyState(
                    icon: Icons.search_off,
                    title: 'No approved matches',
                    message:
                        'Try another topic or browse the available collections.',
                    action: OutlinedButton(
                      onPressed: _focusedSearch,
                      child: const Text('Change search'),
                    ),
                  ),
                for (final r in resources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _open(r),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _collections[r.collection] ??
                                    'Reviewed resource',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                r.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(r.summary),
                              const SizedBox(height: 12),
                              const Text('Reviewed · Available offline'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _article(ApprovedResource r) {
    final prefs = widget.state.protectedPreferences;
    final bookmarked = prefs.bookmarkedIds.contains(r.id);
    final saved = prefs.readingIds.contains(r.id);
    return ListView(
      key: ValueKey('article-${r.id}'),
      controller: _scrollFor(r.id),
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_collections[r.collection] ?? 'Reviewed resource'),
                const SizedBox(height: 12),
                Text(
                  r.title,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(r.summary, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                if (!_tab.isPrivate)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _run(
                          () => widget.state.setResourceBookmarked(
                            r.id,
                            !bookmarked,
                            isPrivate: _tab.isPrivate,
                          ),
                        ),
                        icon: Icon(
                          bookmarked ? Icons.bookmark : Icons.bookmark_border,
                        ),
                        label: Text(bookmarked ? 'Bookmarked' : 'Bookmark'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _run(
                          () => widget.state.setResourceReading(
                            r.id,
                            !saved,
                            isPrivate: _tab.isPrivate,
                          ),
                        ),
                        icon: Icon(
                          saved ? Icons.menu_book : Icons.playlist_add,
                        ),
                        label: Text(saved ? 'In reading list' : 'Read later'),
                      ),
                      if (saved)
                        OutlinedButton(
                          onPressed: () => _run(
                            () => widget.state.setResourceRead(
                              r.id,
                              !prefs.readIds.contains(r.id),
                              isPrivate: _tab.isPrivate,
                            ),
                          ),
                          child: Text(
                            prefs.readIds.contains(r.id)
                                ? 'Mark unread'
                                : 'Mark read',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                // Policy is rechecked in the fixed-schema text adapter too.
                CompatibleReaderText(
                  resourceId: r.id,
                  registry: _compatibility!,
                  additional: _additional,
                  context: _context,
                  isPrivate: _tab.isPrivate,
                  style: TextStyle(
                    fontSize: 18 * widget.state.settings.pageScale / 100,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                Text(
                  'Reviewed ${_date(r.reviewedAt)} · Review expires ${_date(r.expiresAt)}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Original Wingman text. References support editorial review; they are not approved live destinations.',
                ),
                const SizedBox(height: 12),
                for (final source in r.sourceUrls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      source,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextButton(
                  onPressed: _review,
                  child: const Text('About content review'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _date(DateTime value) =>
      value.toUtc().toIso8601String().split('T').first;
  Future<void> _showTabs() async {
    var private = _tab.isPrivate, list = false;
    await showWingmanSheet<void>(
      context: context,
      builder: (sheet) => ListenableBuilder(
        listenable: Listenable.merge([widget.policy, widget.state]),
        builder: (sheet, _) => StatefulBuilder(
          builder: (sheet, update) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        kIsWeb ? 'App sessions' : 'Session tabs',
                        style: Theme.of(sheet).textTheme.headlineMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close tabs view',
                      onPressed: () => Navigator.pop(sheet),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Normal tabs restore their last permitted address after restart. Private tabs and search-query pages do not restore. Page forms and navigation stacks may be lost when an inactive tab is released.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(
                        'Normal (${_tabs.where((t) => !t.isPrivate).length})',
                      ),
                      selected: !private,
                      onSelected: (_) => update(() => private = false),
                    ),
                    ChoiceChip(
                      label: Text(
                        'Private (${_tabs.where((t) => t.isPrivate).length})',
                      ),
                      selected: private,
                      onSelected: (_) => update(() => private = true),
                    ),
                    IconButton(
                      tooltip: list ? 'Show tab grid' : 'Show tab list',
                      onPressed: () => update(() => list = !list),
                      icon: Icon(list ? Icons.grid_view : Icons.view_list),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (private)
                  const WingmanStatus(
                    title: 'Private sessions stay separate',
                    message:
                        'No normal saved activity or page previews appear here. Closing private tabs removes their temporary tools and closes their website views. Supported native pages use disposable website data; websites can still see your IP address.',
                  ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        !list &&
                            constraints.maxWidth >= 320 &&
                            MediaQuery.textScalerOf(context).scale(16) < 24
                        ? 2
                        : 1;
                    final visible = _tabs
                        .where((t) => t.isPrivate == private)
                        .toList();
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final tab in visible)
                          SizedBox(
                            width:
                                (constraints.maxWidth - 12 * (columns - 1)) /
                                columns,
                            child: Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: tab == _tab
                                      ? WingmanTokens.of(sheet).action
                                      : WingmanTokens.of(sheet).divider,
                                  width: tab == _tab ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16,
                                        ),
                                        child: Icon(
                                          tab.isPrivate
                                              ? Icons.visibility_off_outlined
                                              : Icons.article_outlined,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        tooltip:
                                            'Close tab ${_tabs.indexOf(tab) + 1}',
                                        onPressed: () async {
                                          final route = ModalRoute.of(sheet);
                                          final service = tab.isPrivate
                                              ? _session.privateServices
                                              : widget.signatures;
                                          if (tab.taskId != null &&
                                              service?.initialized == true &&
                                              !await _run(
                                                () => _detachTaskTab(
                                                  tab.taskId!,
                                                  tab.id,
                                                  service!,
                                                  tab.isPrivate,
                                                ),
                                              )) {
                                            return;
                                          }
                                          if (!mounted ||
                                              !sheet.mounted ||
                                              route?.isCurrent != true) {
                                            return;
                                          }
                                          _removeTabs([tab]);
                                          update(() {});
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _activeTab = _tabs.indexOf(tab);
                                        _destination = 0;
                                        _query = '';
                                        _queryController.clear();
                                        _collection = null;
                                        _notice = null;
                                      });
                                      Navigator.pop(sheet);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        16,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tab.isPrivate
                                                ? 'Private tab'
                                                : _safeTabTitle(tab),
                                            style: Theme.of(
                                              sheet,
                                            ).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            tab == _tab
                                                ? 'Selected'
                                                : 'Open session',
                                          ),
                                          if (tab.taskId != null)
                                            const Text('Finish Mode tab'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (visible.isEmpty)
                          const WingmanEmptyState(
                            icon: Icons.tab_outlined,
                            title: 'No sessions here',
                            message:
                                'Open a new tab to start with the same permanent protection.',
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _tabs.length >= 12
                          ? null
                          : () => _newTab(sheet, private),
                      child: Text(private ? 'New private tab' : 'New tab'),
                    ),
                    if (!private)
                      OutlinedButton(
                        onPressed: _tabs.length >= 12
                            ? null
                            : () => _newTab(sheet, true),
                        child: const Text('New private tab'),
                      ),
                    TextButton(
                      onPressed: _tabs.any((t) => t.isPrivate == private)
                          ? () async {
                              final scope = <DiscoveryTab, String?>{
                                for (final tab in _tabs.where(
                                  (t) => t.isPrivate == private,
                                ))
                                  tab: tab.taskId,
                              };
                              final approved = await showDialog<bool>(
                                context: sheet,
                                builder: (dialog) => AlertDialog(
                                  title: Text(
                                    'Close ${scope.length} ${private ? 'private' : 'normal'} tabs?',
                                  ),
                                  content: Text(
                                    private
                                        ? 'These private sessions and their transient tools will be destroyed. This cannot be undone.'
                                        : 'Only these normal tabs will close. Saved library items and task results remain.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, true),
                                      child: const Text('Close selected tabs'),
                                    ),
                                  ],
                                ),
                              );
                              if (approved != true || !sheet.mounted) return;
                              final route = ModalRoute.of(sheet);
                              for (final entry in scope.entries) {
                                final service = entry.key.isPrivate
                                    ? _session.privateServices
                                    : widget.signatures;
                                if (entry.value != null &&
                                    service != null &&
                                    !await _run(
                                      () => _detachTaskTab(
                                        entry.value!,
                                        entry.key.id,
                                        service,
                                        entry.key.isPrivate,
                                      ),
                                    )) {
                                  return;
                                }
                              }
                              if (!mounted ||
                                  !sheet.mounted ||
                                  route?.isCurrent != true) {
                                return;
                              }
                              _removeTabs(scope.keys);
                              update(() {});
                            }
                          : null,
                      child: Text(
                        'Close all ${private ? 'private' : 'normal'} tabs',
                      ),
                    ),
                  ],
                ),
                if (_tabs.length >= 12)
                  const Text(
                    '12-session limit reached. Close a tab to open another.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _removeTabs(Iterable<DiscoveryTab> selected) {
    final captured = selected.toList(), active = _tab;
    setState(() {
      for (final tab in captured) {
        _tabs.remove(tab);
        tab.dispose();
      }
      if (_tabs.isEmpty) _tabs.add(DiscoveryTab());
      final preserved = _tabs.indexOf(active);
      _activeTab = preserved >= 0
          ? preserved
          : _activeTab.clamp(0, _tabs.length - 1);
      if (captured.contains(active)) {
        _query = '';
        _queryController.clear();
        _collection = null;
        _notice = null;
        _destination = 0;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _session.clearPrivateServicesIfUnused();
      _pruneScrolls();
    });
  }

  String _safeTabTitle(DiscoveryTab tab) {
    final website = tab.website;
    if (website != null) {
      return _websiteDecision(website, isPrivate: tab.isPrivate).isAllowed
          ? website.host
          : 'Unavailable website';
    }
    final r = tab.resourceId == null
        ? null
        : widget.policy.resource(tab.resourceId!);
    return r != null && _eligibleId(r.id, private: tab.isPrivate)
        ? r.title
        : 'Home';
  }

  void _newTab(BuildContext sheet, bool private) {
    setState(() {
      _tabs.add(DiscoveryTab(isPrivate: private));
      _activeTab = _tabs.length - 1;
      _destination = 0;
      _query = '';
      _queryController.clear();
      _collection = null;
      _notice = null;
    });
    Navigator.pop(sheet);
  }

  LaunchpadActions _launchpadActions({bool Function()? stillMatchesPage}) {
    final origin = _tab;
    final service = _features;
    bool current() =>
        _validOrigin(origin) && (stillMatchesPage?.call() ?? true);
    return LaunchpadActions(
      canContinue: current,
      changes: _launchpadChanges,
      catalog: LaunchpadCatalog(
        resources: widget.policy.catalog,
        reviewedSites: widget.policy.liveSites,
      ),
      push: (page) async {
        if (current()) await _pushFeature(page);
      },
      onOpen: (target, {bool newTab = false}) async {
        if (!current() || service == null) return;
        if (target.kind == LaunchpadKind.website) {
          _navigateWebsite(Uri.parse(target.value), newTab: newTab);
          return;
        }
        if (target.kind == LaunchpadKind.resource) {
          final resource = widget.policy.resource(target.value);
          if (resource == null ||
              !_eligibleId(target.value, private: origin.isPrivate)) {
            _deny(
              widget.policy.policy.evaluate(
                PolicyRequest.bundled(
                  target.value,
                  context: _context,
                  isPrivate: origin.isPrivate,
                ),
                additional: _additional,
              ),
            );
            return;
          }
          if (newTab && _tabs.length >= 12) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The 12-tab limit is reached. Close a tab first.',
                ),
              ),
            );
            return;
          }
          Navigator.of(context).popUntil((route) => route.isFirst);
          if (newTab) {
            setState(() {
              _tabs.add(DiscoveryTab(isPrivate: origin.isPrivate));
              _activeTab = _tabs.length - 1;
              _destination = 0;
              _query = '';
              _queryController.clear();
              _collection = null;
              _notice = null;
            });
          }
          _open(resource);
          return;
        }
        if (!service.launchpad.eligibility.assess(target).canOpen) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        switch (target.tool) {
          case LaunchpadTool.explore:
            _explore();
          case LaunchpadTool.officialRoutes:
            _official();
          case LaunchpadTool.library:
            _library();
          case LaunchpadTool.spaces:
            _workspaces();
          case LaunchpadTool.finishMode:
            _workspaces(tasks: true);
          case LaunchpadTool.beforeYouCommit:
            _commitReview();
          case LaunchpadTool.trustReceipt:
            _receipt();
          case LaunchpadTool.compatibility:
            _repair();
          case LaunchpadTool.helpNow:
            _helpNow();
          case null:
            break;
        }
      },
      bookmarks: () {
        if (!current() || origin.isPrivate || _ephemeral) return const [];
        return [
          for (final resource in widget.policy.catalog)
            if (widget.state.protectedPreferences.bookmarkedIds.contains(
                  resource.id,
                ) &&
                _eligibleId(resource.id, private: false))
              LaunchpadPinDraft(
                title: resource.title,
                target: LaunchpadTarget.resource(resource.id),
                localIconKey: 'book',
                fromBookmark: true,
              ),
        ];
      },
      onAddToSpace: (target) async {
        if (!current() ||
            service == null ||
            target.kind != LaunchpadKind.resource ||
            !_eligibleId(target.value, private: origin.isPrivate)) {
          return;
        }
        final chosen = await showWingmanSheet<String>(
          context: context,
          builder: (sheet) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add to Your Spaces',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This saves a separate reviewed reference. Removing the Launchpad shortcut will not remove it from your Space.',
                ),
                for (final space in service.workspaces.snapshot.spaces)
                  TextButton(
                    onPressed: () => Navigator.pop(sheet, space.id),
                    child: Text(space.name),
                  ),
                if (service.workspaces.snapshot.spaces.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Create a Space first, then choose this action again.',
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, '__manage'),
                  child: const Text('Manage Spaces'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
        if (!current() || chosen == null) return;
        if (chosen == '__manage') {
          _workspaces();
          return;
        }
        if (service.workspaces.space(chosen) == null ||
            !_eligibleId(target.value, private: origin.isPrivate)) {
          return;
        }
        final saved = await _run(
          () => service.workspaces.saveToSpace(chosen, target.value),
        );
        if (saved && mounted && current()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Added to your Space.')));
        }
      },
      onManageSpaces: () {
        if (current()) _workspaces();
      },
      onHomeSections: () {
        if (current()) _homeSections();
      },
    );
  }

  void _customize() {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    _pushFeature(
      LaunchpadCustomizeScreen(
        controller: _features!.launchpad,
        actions: _launchpadActions(),
        isPrivate: _ephemeral,
      ),
    );
  }

  void _pinToLaunchpad(
    String id, {
    bool fromBookmark = false,
    bool committedPage = false,
  }) {
    if (!_toolsReady || _ephemeral) return;
    final origin = _tab, resource = widget.policy.resource(id);
    if (resource == null ||
        !_eligibleId(id, private: false) ||
        (committedPage && origin.resourceId != id)) {
      return;
    }
    _pushFeature(
      LaunchpadEditorScreen(
        controller: _features!.launchpad,
        actions: _launchpadActions(
          stillMatchesPage: () =>
              !origin.isPrivate && (!committedPage || origin.resourceId == id),
        ),
        isPrivate: false,
        initialDraft: LaunchpadPinDraft(
          title: resource.title,
          target: LaunchpadTarget.resource(id),
          localIconKey: 'book',
          fromBookmark: fromBookmark,
          fromCurrentPage: committedPage,
        ),
      ),
    );
  }

  void _pinCurrentWebsite(
    DiscoveryTab owner,
    ProtectedWebStatus status,
    int revision,
  ) {
    final uri = owner.website;
    if (!_validOrigin(owner) ||
        (_webRevisions[owner.id] ?? 0) != revision ||
        !_toolsReady ||
        _ephemeral ||
        uri == null ||
        const StrictSearchPolicy().acceptsCanonical(uri) ||
        !status.committed ||
        status.url != uri ||
        !_websiteDecision(uri).isAllowed) {
      return;
    }
    final site = widget.policy.policy.livePolicy?.siteForUri(uri);
    _pushFeature(
      LaunchpadEditorScreen(
        controller: _features!.launchpad,
        actions: _launchpadActions(
          stillMatchesPage: () =>
              owner.website == uri &&
              (_webRevisions[owner.id] ?? 0) == revision &&
              _websiteDecision(uri, isPrivate: false).isAllowed,
        ),
        isPrivate: false,
        initialDraft: LaunchpadPinDraft(
          title: site?.title ?? uri.host,
          target: LaunchpadTarget.website(uri.toString()),
          localIconKey: 'globe',
          fromCurrentPage: true,
        ),
      ),
    );
  }

  void _homeSections() {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final origin = _tab;
    _pushFeature(
      CustomizeHomeScreen(
        controller: _features!.ui,
        policy: widget.policy,
        eligible: (id) => _eligibleId(id, private: origin.isPrivate),
        canContinue: () => _validOrigin(origin),
        onSpaces: () => _workspaces(),
        onLaunchpad: _customize,
        isPrivate: _ephemeral,
      ),
    );
  }

  void _toolsUnavailable() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Local tools are still opening. Your reviewed library remains available.',
      ),
    ),
  );

  void _library([LibrarySection section = LibrarySection.hub]) {
    final origin = _tab;
    _pushFeature(
      LibraryScreen(
        state: widget.state,
        policy: widget.policy,
        isPrivate: _ephemeral,
        canContinue: () => _validOrigin(origin),
        onOpenApprovedResource: _openFeatureResource,
        initialSection: section,
        onPrivacy: _settings,
        liveReadingList: _ephemeral || widget.liveContent == null
            ? null
            : LiveReadingList(
                controller: widget.liveContent!,
                onOpen: _openLiveContent,
                onOpenUri: _openLiveContentLicense,
                onPin: _pinLiveContent,
                canContinue: () => _validOrigin(origin) && !_ephemeral,
              ),
        onPinToLaunchpad: _ephemeral
            ? null
            : (id) => _pinToLaunchpad(id, fromBookmark: true),
      ),
    );
  }

  void _openLiveContent(LiveContentItem item) {
    if (_ephemeral ||
        !_validOrigin(_tab) ||
        widget.liveContent?.canOpen(item) != true) {
      return;
    }
    if (item.syndicatedArticle != null) {
      final origin = _tab;
      final controller = widget.liveContent!;
      _pushFeature(
        SyndicatedArticleScreen(
          item: item,
          controller: controller,
          canContinue: () => !_ephemeral && _validOrigin(origin),
          onOpenUri: (uri) {
            if (_ephemeral ||
                !_validOrigin(origin) ||
                !controller.canOpen(item) ||
                !_websiteDecision(uri).isAllowed) {
              return;
            }
            Navigator.of(context).popUntil((route) => route.isFirst);
            _navigateWebsite(uri);
          },
        ),
      );
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    _navigateWebsite(item.canonicalUrl);
  }

  void _liveContentFeed() {
    final feed = widget.liveContent, origin = _tab;
    if (feed == null || _ephemeral || !_validOrigin(origin)) return;
    _pushFeature(
      LiveContentFeedScreen(
        controller: feed,
        canContinue: () => !_ephemeral && _validOrigin(origin),
        onOpen: _openLiveContent,
        onOpenUri: _openLiveContentLicense,
        onPin: _pinLiveContent,
        onPreferences: _liveContentPreferences,
        onReadingList: () => _library(LibrarySection.readingList),
      ),
    );
  }

  void _openLiveContentLicense(Uri uri) {
    final feed = widget.liveContent;
    if (feed == null ||
        _ephemeral ||
        !_validOrigin(_tab) ||
        !feed.sources.any(
          (source) =>
              source.status != 'revoked' && source.rights.licenseUrl == uri,
        ) ||
        !_websiteDecision(uri).isAllowed) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    _navigateWebsite(uri);
  }

  void _pinLiveContent(LiveContentItem item) {
    if (_ephemeral ||
        !_toolsReady ||
        !_validOrigin(_tab) ||
        widget.liveContent?.canOpen(item) != true) {
      return;
    }
    // Launchpad names have an 80-code-unit storage limit. Keep whole grapheme
    // clusters in this editable prefill; the publisher headline stays intact.
    final name = StringBuffer();
    for (final grapheme in item.title.characters) {
      if (name.length + grapheme.length > 80) break;
      name.write(grapheme);
    }
    final shortcutName = name.isEmpty
        ? 'Publisher article'
        : name.toString().trimRight();
    _pushFeature(
      LaunchpadEditorScreen(
        controller: _features!.launchpad,
        actions: _launchpadActions(),
        isPrivate: false,
        initialDraft: LaunchpadPinDraft(
          title: shortcutName,
          target: LaunchpadTarget.website(item.canonicalUrl.toString()),
          localIconKey: 'globe',
        ),
      ),
    );
  }

  void _liveContentPreferences() {
    final feed = widget.liveContent, origin = _tab;
    if (feed == null || _ephemeral || !_validOrigin(origin)) return;
    _pushFeature(
      LiveContentPreferencesScreen(
        controller: feed,
        canContinue: () => !_ephemeral && _validOrigin(origin),
      ),
    );
  }

  void _protection() {
    final origin = _tab;
    _pushFeature(
      ProtectionScreen(
        state: widget.state,
        policy: widget.policy,
        isPrivate: _ephemeral,
        canContinue: () => _validOrigin(origin),
        onReceipt: _receipt,
        onRequestReview: _review,
        onOpenApprovedResource: _openFeatureResource,
        onHome: _returnHome,
      ),
    );
  }

  void _returnHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _home();
  }

  void _review() {
    if (!_toolsReady) {
      _toolsUnavailable();
      return;
    }
    final origin = _tab;
    _pushFeature(
      RequestReviewScreen(
        journal: _features!.journal,
        isPrivate: _ephemeral,
        canContinue: () => _validOrigin(origin),
      ),
    );
  }

  void _helpNow() {
    final origin = _tab;
    _pushFeature(
      HelpNowScreen(
        policy: widget.policy,
        additional: () => _additional,
        isPrivate: _ephemeral,
        canContinue: () => _validOrigin(origin),
        onHome: _returnHome,
        onOpenApprovedResource: _openFeatureResource,
      ),
    );
  }

  void _settings() {
    final origin = _tab, service = _features;
    _pushFeature(
      SettingsScreen(
        state: widget.state,
        policy: widget.policy,
        isPrivate: _ephemeral,
        canContinue: () => _validOrigin(origin),
        buildInfo: AppBuildInfo.current,
        actions: SettingsActions(
          onHomeCustomization: _customize,
          onSpaces: () => _workspaces(),
          onProtection: _protection,
          onReceipt: _receipt,
          onCompatibility: _repair,
          onHelpNow: _helpNow,
          clearableCategories: {
            PrivacyDataCategory.session,
            if (_toolsReady) PrivacyDataCategory.trustReceipt,
            if (!_ephemeral) ...[
              if (_toolsReady) PrivacyDataCategory.launchpad,
              PrivacyDataCategory.reviewedBookmarks,
              PrivacyDataCategory.readingList,
              PrivacyDataCategory.legacyHistory,
              if (!kIsWeb) PrivacyDataCategory.websiteStorage,
            ],
          },
          onClearData: (selected) => _clearData(selected, origin, service),
          onClearDataScoped: (selected, canReconcile) =>
              _clearData(selected, origin, service, canReconcile: canReconcile),
          pendingDataClear: () =>
              _session.pendingClearIsPrivate == origin.isPrivate
              ? _session.pendingDataClear
              : null,
        ),
      ),
    );
  }

  Future<DataClearOutcome> _clearData(
    Set<PrivacyDataCategory> selected,
    DiscoveryTab origin,
    SignatureServices? service, {
    bool Function()? canReconcile,
  }) async {
    final existing = _session.pendingDataClear;
    if (existing != null &&
        _session.pendingClearIsPrivate != origin.isPrivate) {
      return DataClearOutcome(failed: selected);
    }
    if (existing != null) {
      return existing.timeout(
        const Duration(seconds: 15),
        onTimeout: () => DataClearOutcome(pending: true),
      );
    }
    if (!_validOrigin(origin)) return DataClearOutcome(failed: selected);
    final captured = <DiscoveryTab, String?>{
      if (selected.contains(PrivacyDataCategory.session))
        for (final tab in _tabs.where((t) => t.isPrivate == origin.isPrivate))
          tab: tab.taskId,
    };
    _session.pendingClearIsPrivate = origin.isPrivate;
    final operation = _session.pendingDataClear = _performDataClear(
      Set.of(selected),
      origin,
      service,
      captured,
      canReconcile,
    );
    unawaited(
      operation.then(
        (_) {
          if (identical(_session.pendingDataClear, operation)) {
            _session.pendingDataClear = null;
          }
        },
        onError: (Object _) {
          if (identical(_session.pendingDataClear, operation)) {
            _session.pendingDataClear = null;
          }
        },
      ),
    );
    return operation.timeout(
      const Duration(seconds: 15),
      onTimeout: () => DataClearOutcome(pending: true),
    );
  }

  Future<DataClearOutcome> _performDataClear(
    Set<PrivacyDataCategory> selected,
    DiscoveryTab origin,
    SignatureServices? service,
    Map<DiscoveryTab, String?> captured,
    bool Function()? canReconcile,
  ) async {
    final completed = <PrivacyDataCategory>{}, failed = <PrivacyDataCategory>{};
    for (final category in selected.where(
      (c) => c != PrivacyDataCategory.session,
    )) {
      try {
        if (origin.isPrivate && category != PrivacyDataCategory.trustReceipt) {
          throw StateError('Private scope');
        }
        switch (category) {
          case PrivacyDataCategory.launchpad:
            if (service == null) throw StateError('Launchpad unavailable');
            await service.launchpad.clearSavedData(
              canContinue: () => _validOrigin(origin),
            );
          case PrivacyDataCategory.reviewedBookmarks:
            await widget.state.clearReviewedLibrary(bookmarks: true);
          case PrivacyDataCategory.readingList:
            await widget.state.clearReviewedLibrary(readingList: true);
            await widget.liveContent?.clearSaved();
          case PrivacyDataCategory.legacyHistory:
            await widget.state.clearHistory();
          case PrivacyDataCategory.trustReceipt:
            if (service == null) throw StateError('Journal unavailable');
            await service.journal.clear();
            if (service.journal.storageStatus == JournalStorageStatus.failed) {
              throw StateError('Journal not saved');
            }
          case PrivacyDataCategory.websiteStorage:
            await _native.clearLegacySiteData();
          case PrivacyDataCategory.session:
            break;
        }
        completed.add(category);
      } catch (_) {
        failed.add(category);
      }
    }
    if (selected.contains(PrivacyDataCategory.session)) {
      try {
        for (final entry in captured.entries) {
          final task = entry.value;
          if (task != null && service != null) {
            await _detachTaskTab(task, entry.key.id, service, origin.isPrivate);
          }
        }
        final active = _tab;
        final returnToSession = mounted && (canReconcile?.call() ?? false);
        final removingActive = captured.containsKey(active);
        for (final tab in captured.keys) {
          _tabs.remove(tab);
          tab.dispose();
        }
        if (_tabs.isEmpty) _tabs.add(DiscoveryTab());
        final preserved = _tabs.indexOf(active);
        _activeTab = preserved >= 0
            ? preserved
            : _activeTab.clamp(0, _tabs.length - 1);
        if (removingActive) {
          _destination = 0;
          _query = '';
          _collection = null;
          _notice = null;
          if (mounted) _queryController.clear();
        }
        _session.clearTaskUndo();
        if (mounted) {
          if (origin.isPrivate && removingActive) {
            appRouteObserver.removePrivateFeatureRoutes(Navigator.of(context));
          } else if (active == origin && returnToSession) {
            Navigator.of(context).popUntil((r) => r.isFirst);
          }
          setState(() {});
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _session.clearPrivateServicesIfUnused();
          _pruneScrolls();
        });
        await _session.flush();
        completed.add(PrivacyDataCategory.session);
      } catch (_) {
        failed.add(PrivacyDataCategory.session);
      }
    }
    if (mounted) setState(() {});
    return DataClearOutcome(completed: completed, failed: failed);
  }

  void _reader(ApprovedResource resource) {
    final origin = _tab;
    _pushFeature(
      ListenableBuilder(
        listenable: widget.state,
        builder: (pageContext, _) {
          final prefs = widget.state.protectedPreferences;
          return ApprovedReader(
            resourceId: resource.id,
            policy: widget.policy,
            compatibilityRegistry: _compatibility!,
            additional: _additional,
            contentContext: _context,
            isPrivate: origin.isPrivate,
            pageScale: widget.state.settings.pageScale,
            canContinue: () => _validOrigin(origin),
            onBack: () => Navigator.pop(pageContext),
            bookmarked: prefs.bookmarkedIds.contains(resource.id),
            inReadingList: prefs.readingIds.contains(resource.id),
            onBookmark: () => _run(
              () => widget.state.setResourceBookmarked(
                resource.id,
                !prefs.bookmarkedIds.contains(resource.id),
                isPrivate: origin.isPrivate,
              ),
            ),
            onReading: () => _run(
              () => widget.state.setResourceReading(
                resource.id,
                !prefs.readingIds.contains(resource.id),
                isPrivate: origin.isPrivate,
              ),
            ),
            onCommit: () => _commitReview(resource: resource),
            onScaleChanged: (v) =>
                _run(() => widget.state.saveSettingsPatch(pageScale: v)),
          );
        },
      ),
    );
  }

  void _pageInfo(ApprovedResource? resource) {
    final origin = _tab;
    _sheet('Page information', () {
      if (!_validOrigin(origin) ||
          (resource != null && !_eligible(resource)) ||
          (origin.website != null &&
              !_websiteDecision(origin.website!).isAllowed)) {
        return const [
          WingmanStatus(
            title: 'Page information unavailable',
            message:
                'The originating session or current content review has changed.',
          ),
        ];
      }
      return [
        if (origin.website case final uri?) ...[
          Text(
            const StrictSearchPolicy().acceptsCanonical(uri)
                ? 'DuckDuckGo search · Adult filtering: Strict'
                : uri.toString(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text(
            const StrictSearchPolicy().acceptsCanonical(uri)
                ? 'Wingman requires DuckDuckGo’s Strict adult filter and blocks provider shortcuts that bypass it. Search previews are not fully classified against Wingman’s other content rules. Destination links are checked against the separate category and security policy. Refinement, pagination and forms use the native browser.'
                : 'Permitted by the current filtering policy; not verified safe. Pages connect directly to their websites. Normal sessions support JavaScript, forms, cookies and website storage. Filters can miss content or block legitimate pages.',
          ),
          const SizedBox(height: 12),
          Text(
            const StrictSearchPolicy().acceptsCanonical(uri)
                ? 'Submitting sends the query and your connection information directly to DuckDuckGo. Wingman does not save search terms, provide remote suggestions or use a paid search API. Private mode does not hide requests from the provider. SafeSearch can miss results.'
                : 'Page requests reveal connection information to the requested website. Wingman does not upload your address, page contents or browsing history. Website content can change; this is not a guarantee about every image or word.',
          ),
          if (widget.policy.policy.livePolicy?.siteForUri(uri) case final site?)
            Text(
              'Home suggestion review expires ${_date(site.expiresAt)}; browsing uses separate protection data',
            ),
          const SizedBox(height: 12),
        ] else ...[
          Text(
            resource == null ? 'Wingman Home' : resource.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Text(
            'Installed original text. No live connection, website permission or external authentication is involved.',
          ),
          if (resource != null)
            Text(
              'Reviewed ${_date(resource.reviewedAt)} · Expires ${_date(resource.expiresAt)}',
            ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Content eligibility, official identity, connection security and compatibility are separate checks.',
        ),
      ];
    });
  }

  Future<void> _findInPage(DiscoveryTab origin) async {
    if (!_validOrigin(origin)) return;
    await showDialog<void>(
      context: context,
      routeSettings: const RouteSettings(name: 'wingman-browser-find'),
      builder: (_) => BrowserFindDialog(
        onQuery: (query) {
          if (_validOrigin(origin)) _webControllers[origin.id]?.find(query);
        },
        onNext: (forward) {
          if (_validOrigin(origin)) {
            _webControllers[origin.id]?.findNext(forward: forward);
          }
        },
      ),
    );
  }

  Future<void> _sharePage(DiscoveryTab origin, Uri uri) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy address'),
              onTap: () {
                Navigator.pop(sheet);
                if (_validOrigin(origin) && _websiteDecision(uri).isAllowed) {
                  Clipboard.setData(ClipboardData(text: uri.toString()));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share address'),
              onTap: () {
                Navigator.pop(sheet);
                if (_validOrigin(origin) && _websiteDecision(uri).isAllowed) {
                  _webControllers[origin.id]?.share();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _menu() {
    final origin = _tab;
    final resource = _current();
    final live = origin.website;
    // Menus preserve the renderer; snapshot eligibility is rechecked on action.
    final committed = _webStatuses[origin.id];
    final liveRevision = _webRevisions[origin.id] ?? 0;
    final groups = <String, List<MenuAction>>{
      'Page': [
        MenuAction(
          'Page information',
          Icons.info_outline,
          () => _pageInfo(resource),
        ),
        MenuAction(
          'Add to Launchpad',
          Icons.add_to_home_screen,
          _ephemeral ||
                  !_toolsReady ||
                  (resource == null &&
                      (live == null ||
                          const StrictSearchPolicy().acceptsCanonical(live) ||
                          committed?.committed != true ||
                          committed?.url != live ||
                          !_websiteDecision(live).isAllowed))
              ? null
              : live != null
              ? () => _pinCurrentWebsite(origin, committed!, liveRevision)
              : () => _pinToLaunchpad(resource!.id, committedPage: true),
          subtitle: _ephemeral
              ? 'Unavailable for private or temporary pages'
              : live != null &&
                    const StrictSearchPolicy().acceptsCanonical(live)
              ? 'Search terms are not saved; pin a destination page'
              : live != null
              ? 'Pin this permitted page to Home'
              : resource == null
              ? 'Open an eligible article first'
              : 'Pin this installed article to Home',
        ),
        MenuAction(
          'Reader',
          Icons.chrome_reader_mode_outlined,
          resource == null ? null : () => _reader(resource),
          subtitle: resource == null
              ? 'Open a reviewed article first'
              : 'Read installed text',
        ),
        if (resource != null && !_tab.isPrivate) ...[
          MenuAction(
            'Bookmark',
            Icons.bookmark_border,
            () => _run(
              () => widget.state.setResourceBookmarked(
                resource.id,
                true,
                isPrivate: origin.isPrivate,
              ),
            ),
          ),
          MenuAction(
            'Read later',
            Icons.playlist_add,
            () => _run(
              () => widget.state.setResourceReading(
                resource.id,
                true,
                isPrivate: origin.isPrivate,
              ),
            ),
          ),
        ],
        MenuAction(
          'Find in page',
          Icons.find_in_page_outlined,
          live == null ? null : () => _findInPage(origin),
        ),
        const MenuAction(
          'Desktop site',
          Icons.desktop_windows_outlined,
          null,
          subtitle:
              'Changing website rendering modes is unavailable in this build',
        ),
        MenuAction(
          'Copy or share page address',
          Icons.share_outlined,
          live != null && _websiteDecision(live).isAllowed
              ? () => _sharePage(origin, live)
              : null,
        ),
      ],
      'Wingman tools': [
        MenuAction(
          'Official Routes',
          Icons.account_balance_outlined,
          () => _official(),
        ),
        MenuAction(
          'Before You Commit',
          Icons.fact_check_outlined,
          () => _commitReview(resource: resource),
        ),
        MenuAction(
          'Spaces & Finish Mode',
          Icons.dashboard_outlined,
          () => _workspaces(),
        ),
        MenuAction(
          'Hand It Over',
          Icons.pan_tool_outlined,
          resource == null ? () => _handoff([]) : () => _handoff([resource.id]),
          subtitle: widget.handoff?.canStart == true && !_tab.isPrivate
              ? 'Share reviewed public text'
              : 'Unavailable in this session',
        ),
      ],
      'Your library': [
        MenuAction('Library', Icons.collections_bookmark_outlined, _library),
        MenuAction(
          'Bookmarks',
          Icons.bookmark_border,
          () => _library(LibrarySection.bookmarks),
        ),
        MenuAction(
          'Reading list',
          Icons.menu_book_outlined,
          () => _library(LibrarySection.readingList),
        ),
        MenuAction(
          'History',
          Icons.history,
          () => _library(LibrarySection.history),
        ),
        MenuAction(
          'Downloads',
          Icons.download_outlined,
          () => _library(LibrarySection.downloads),
        ),
      ],
      'Protection & settings': [
        MenuAction('Protection', Icons.shield_outlined, _protection),
        MenuAction('Trust Receipt', Icons.receipt_long_outlined, _receipt),
        MenuAction('Something isn’t working', Icons.build_outlined, _repair),
        MenuAction('Help Now', Icons.favorite_border, _helpNow),
        MenuAction(
          'Default browser',
          Icons.open_in_browser,
          _capabilities.defaultBrowser
              ? () => _run(() async {
                  await _native.requestDefaultBrowser();
                })
              : null,
          subtitle: _capabilities.defaultBrowser
              ? 'Choose Wingman in system settings'
              : 'Unavailable in this build or platform',
        ),
        MenuAction('Settings', Icons.tune, _settings),
      ],
    };
    showBrowserMenu(
      context,
      groups.map(
        (name, actions) => MapEntry(
          name,
          actions
              .map(
                (action) => MenuAction(
                  action.label,
                  action.icon,
                  action.onTap == null
                      ? null
                      : () {
                          if (!_validOrigin(origin)) return;
                          action.onTap!();
                        },
                  subtitle: action.subtitle,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<bool> _run(FutureOr<void> Function() operation) async {
    try {
      await operation();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That change could not be saved. Protection remains active.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _sheet(String title, List<Widget> Function() children) =>
      showWingmanSheet<void>(
        context: context,
        builder: (sheet) => ListenableBuilder(
          listenable: Listenable.merge([widget.policy, widget.state]),
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close page information',
                      onPressed: () => Navigator.pop(sheet),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...children(),
              ],
            ),
          ),
        ),
      );
}

/// Preserve text editing while excluding OS lookup/search/share/process-text.
Widget safeTextContextMenu(BuildContext context, EditableTextState editable) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: editable.contextMenuButtonItems
          .where(
            (item) => const {
              ContextMenuButtonType.cut,
              ContextMenuButtonType.copy,
              ContextMenuButtonType.paste,
              ContextMenuButtonType.selectAll,
            }.contains(item.type),
          )
          .toList(),
    );
