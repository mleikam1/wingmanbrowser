// Synthetic development scenes only. Never import this module from lib/main.dart.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/presentation/design_system/app_build_info.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/presentation/settings/privacy_data_screen.dart';
import 'package:wingman_browser/presentation/protection/protection_screen.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/presentation/protection/help_now_screen.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';
import 'package:wingman_browser/presentation/library/library_transfer_screen.dart';
import 'package:wingman_browser/presentation/library/approved_reader.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/privacy/trust_receipt_screen.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report_screen.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_profiles.dart';
import 'package:wingman_browser/state/browser_state.dart';

enum SettingsLibraryScene {
  settings('G01–G06 · Settings and durable memory preferences'),
  privacy('G04 · Selected clear confirmation'),
  pendingClear('G04 · Pending clear, then completion'),
  failedClear('G04 · Failed clear'),
  protection('P01–P03 · Protection and additional boundaries'),
  unreviewed('P04 · Unreviewed destination'),
  unavailable('P04 · Unavailable policy'),
  tls('P05 · Synthetic TLS error, no bypass'),
  help('P06 · Local pause and reviewed support'),
  library('L01 · Library'),
  bookmarks('L02 · Saved reviewed articles'),
  privateLibrary('L01–L06 · Hidden normal library'),
  importBookmarks('L03 · Reviewed-ID import'),
  exportBookmarks('L03 · Intercepted clipboard export'),
  reading('L04 · Reading list'),
  history('L05 · Quarantined history metadata'),
  downloads('L06 · Unavailable downloads'),
  reader('L07 · Reviewed text'),
  receipt('R01–R02 · Typed local receipt'),
  report('X01–X03 · Local report and correction status');

  const SettingsLibraryScene(this.label);
  final String label;
}

class SettingsLibraryGalleryMenu extends StatelessWidget {
  const SettingsLibraryGalleryMenu({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WingmanSection(title: 'Settings, protection, library & privacy'),
      const Text(
        'SYNTHETIC DEVELOPMENT SCENES · Memory only · No native deletion, owner storage or actual clipboard writes.',
      ),
      for (final scene in SettingsLibraryScene.values)
        ListTile(
          title: Text(scene.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SettingsLibraryGallery(scene: scene),
            ),
          ),
        ),
    ],
  );
}

class SettingsLibraryGallery extends StatefulWidget {
  const SettingsLibraryGallery({super.key, required this.scene});
  final SettingsLibraryScene scene;
  @override
  State<SettingsLibraryGallery> createState() => _SettingsLibraryGalleryState();
}

class _SettingsLibraryGalleryState extends State<SettingsLibraryGallery> {
  late final Future<_Scope> _future;
  @override
  void initState() {
    super.initState();
    _future = _Scope.create(widget.scene);
  }

  @override
  void dispose() {
    unawaited(
      _future.then((s) => s.dispose(), onError: (Object _, StackTrace _) {}),
    );
    super.dispose();
  }

  void _open(Widget page) {
    if (mounted) {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  void _info() => _open(
    const WingmanPage(
      title: 'Development navigation',
      child: Text(
        'This scene intercepts Home and Spaces navigation. Open those functional scenes from the main development menu.',
      ),
    ),
  );
  SettingsActions _actions(_Scope s) => SettingsActions(
    onHomeCustomization: _info,
    onSpaces: _info,
    onProtection: () => _open(_protection(s)),
    onReceipt: () => _open(_receipt(s)),
    onCompatibility: () => _open(_report(s)),
    onHelpNow: () => _open(_help(s)),
    clearableCategories: PrivacyDataCategory.values.toSet(),
    pendingDataClear: () => s.pending,
    onClearData: (selected) async {
      if (widget.scene == SettingsLibraryScene.failedClear) {
        return DataClearOutcome(failed: selected);
      }
      if (selected.contains(PrivacyDataCategory.reviewedBookmarks)) {
        await s.state.clearReviewedLibrary(bookmarks: true);
      }
      if (selected.contains(PrivacyDataCategory.readingList)) {
        await s.state.clearReviewedLibrary(readingList: true);
      }
      if (selected.contains(PrivacyDataCategory.trustReceipt)) {
        await s.journal.clear();
      }
      return DataClearOutcome(completed: selected);
    },
  );
  Widget _reader(_Scope s, String id) => ListenableBuilder(
    listenable: s.state,
    builder: (context, _) => ApprovedReader(
      resourceId: id,
      policy: s.policy,
      compatibilityRegistry: s.registry,
      additional: s.state.protectedPreferences.additional,
      contentContext: ContentContext.general,
      isPrivate: false,
      pageScale: s.state.settings.pageScale,
      onBack: () => Navigator.pop(context),
      canContinue: () => mounted,
      onScaleChanged: (v) =>
          s.state.saveSettingsDurably(s.state.settings.copyWith(pageScale: v)),
    ),
  );
  Widget _help(_Scope s) => HelpNowScreen(
    policy: s.policy,
    additional: () => s.state.protectedPreferences.additional,
    isPrivate: false,
    canContinue: () => mounted,
    onHome: _info,
    onOpenApprovedResource: (id) => _open(_reader(s, id)),
  );
  Widget _protection(_Scope s) => ProtectionScreen(
    state: s.state,
    policy: s.policy,
    isPrivate: false,
    canContinue: () => mounted,
    onReceipt: () => _open(_receipt(s)),
    onRequestReview: () => _open(_report(s)),
    onHome: _info,
    onOpenApprovedResource: (id) => _open(_reader(s, id)),
  );
  Widget _receipt(_Scope s) => TrustReceiptScreen(
    journal: s.journal,
    configuration: () => PrivacyConfiguration(
      historyRecording: PrivacySetting.disabled,
      sync: PrivacySetting.disabled,
      cloudAi: PrivacySetting.disabled,
      liveWebContent: PrivacySetting.disabled,
      policyVersion: 1,
      policyFreshness: s.policy.status.usable
          ? PrivacyPolicyFreshness.current
          : PrivacyPolicyFreshness.unavailable,
    ),
    canContinue: () => mounted,
    copyText: s.copy,
  );
  Widget _report(_Scope s) => CompatibilityReportScreen(
    journal: s.journal,
    registry: s.registry,
    diagnostics: CompatibilityDiagnostics(
      appVersion:
          '${AppBuildInfo.current.version}+${AppBuildInfo.current.build}',
      policyVersion: 1,
      capability: CompatibilityCapability.bundledReader,
    ),
    canContinue: () => mounted,
    copyText: s.copy,
  );
  Widget _screen(_Scope s) => switch (widget.scene) {
    SettingsLibraryScene.settings => SettingsScreen(
      state: s.state,
      policy: s.policy,
      isPrivate: false,
      canContinue: () => mounted,
      actions: _actions(s),
      buildInfo: AppBuildInfo.current,
    ),
    SettingsLibraryScene.privacy ||
    SettingsLibraryScene.pendingClear ||
    SettingsLibraryScene.failedClear => PrivacyDataScreen(
      state: s.state,
      isPrivate: false,
      canContinue: () => mounted,
      actions: _actions(s),
    ),
    SettingsLibraryScene.protection => _protection(s),
    SettingsLibraryScene.unreviewed ||
    SettingsLibraryScene.unavailable => PolicyStateView(
      decision: s.policy.policy.evaluate(
        PolicyRequest.bundled('synthetic-unreviewed'),
      ),
      onHome: _info,
      onExplore: _info,
      onRequestReview: () => _open(_report(s)),
      onHelpNow: () => _open(_help(s)),
    ),
    SettingsLibraryScene.tls => ConnectionErrorScreen(
      kind: ConnectionFailureKind.tls,
      onHome: _info,
    ),
    SettingsLibraryScene.help => _help(s),
    SettingsLibraryScene.reader => _reader(s, 'moon-phases'),
    SettingsLibraryScene.receipt => _receipt(s),
    SettingsLibraryScene.report => _report(s),
    SettingsLibraryScene.importBookmarks ||
    SettingsLibraryScene.exportBookmarks => LibraryTransferScreen(
      state: s.state,
      policy: s.policy,
      isPrivate: false,
      canContinue: () => mounted,
      copyText: s.copy,
      mode: widget.scene == SettingsLibraryScene.importBookmarks
          ? LibraryTransferMode.import
          : LibraryTransferMode.export,
    ),
    _ => LibraryScreen(
      state: s.state,
      policy: s.policy,
      isPrivate: widget.scene == SettingsLibraryScene.privateLibrary,
      canContinue: () => mounted,
      onOpenApprovedResource: (id) => _open(_reader(s, id)),
      initialSection: switch (widget.scene) {
        SettingsLibraryScene.bookmarks ||
        SettingsLibraryScene.privateLibrary => LibrarySection.bookmarks,
        SettingsLibraryScene.reading => LibrarySection.readingList,
        SettingsLibraryScene.history => LibrarySection.history,
        SettingsLibraryScene.downloads => LibrarySection.downloads,
        _ => LibrarySection.hub,
      },
      onPrivacy: () => _open(
        PrivacyDataScreen(
          state: s.state,
          isPrivate: false,
          canContinue: () => mounted,
          actions: _actions(s),
        ),
      ),
    ),
  };
  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return FutureBuilder<_Scope>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const WingmanPage(
            title: 'Synthetic scene unavailable',
            child: WingmanStatus(
              title: 'Fixture unavailable',
              message: 'No owner storage was opened.',
            ),
          );
        }
        final scope = snapshot.data;
        if (scope == null) {
          return const WingmanPage(
            title: 'Loading memory fixture',
            child: CircularProgressIndicator(),
          );
        }
        return Column(
          children: [
            Material(
              color: WingmanTokens.of(context).raised,
              child: const SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'SYNTHETIC G/P/L/R/X · Memory only · Clipboard intercepted',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            Expanded(child: _screen(scope)),
          ],
        );
      },
    );
  }
}

class _Scope {
  _Scope(this.policy, this.state)
    : registry = CompatibilityProfileRegistry(policy: policy);
  final PolicyRuntime policy;
  final BrowserState state;
  final CompatibilityProfileRegistry registry;
  final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
  Future<DataClearOutcome>? pending;
  Timer? timer;
  final copies = <String>[];
  static Future<_Scope> create(SettingsLibraryScene scene) async {
    final policy = await PolicyRuntime.initialize(
      repository: SignedPolicyRepository(
        clock: PolicyClock(wallClock: () => DateTime.utc(2026, 9, 11, 12)),
      ),
      checkpointStore: _MemoryTrust(),
    );
    final state = BrowserState(
      repository: _MemoryBrowser(),
      policyRuntime: policy,
    );
    await state.init();
    await state.setResourceBookmarked('moon-phases', true);
    await state.setResourceReading('moon-phases', true);
    final scope = _Scope(policy, state);
    scope.journal.record(
      PrivacyActivity.localAnalysis,
      PrivacyOutcome.completed,
    );
    scope.journal.record(PrivacyActivity.analysisSaved, PrivacyOutcome.failed);
    if (scene == SettingsLibraryScene.unavailable) {
      policy.repository.restrict('synthetic-unavailable');
    }
    if (scene == SettingsLibraryScene.pendingClear) {
      final completion = Completer<DataClearOutcome>();
      scope.pending = completion.future;
      scope.timer = Timer(const Duration(seconds: 8), () {
        completion.complete(
          DataClearOutcome(completed: [PrivacyDataCategory.websiteStorage]),
        );
        scope.pending = null;
      });
    }
    return scope;
  }

  Future<void> copy(String text) async {
    copies.add(text);
  }

  void dispose() {
    timer?.cancel();
    journal.dispose();
    registry.dispose();
    state.dispose();
    policy.dispose();
    copies.clear();
  }
}

class _MemoryTrust implements PolicyCheckpointStore {
  PolicyCheckpoint value = PolicyCheckpoint();
  @override
  Future<PolicyCheckpoint> load() async => value;
  @override
  Future<void> save(PolicyCheckpoint checkpoint) async {
    value = checkpoint;
  }

  @override
  Future<void> close() async {}
}

class _MemoryBrowser implements BrowserRepository {
  BrowserSettings settings = const BrowserSettings(onboardingComplete: true);
  @override
  Future<BrowserData> load() async => BrowserData(settings: settings);
  @override
  Future<void> saveSettings(BrowserSettings value) async {
    settings = value;
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
