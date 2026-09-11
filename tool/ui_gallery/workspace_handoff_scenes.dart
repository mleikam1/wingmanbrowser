// DEVELOPMENT FIXTURES ONLY. Never import from lib/main.dart or production UI.
// The handoff secure-store and KDF below are deliberately synthetic, memory-only
// presentation doubles. They provide no device protection or persisted gate.
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wingman_browser/guard_pin/pin_derivation.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';

enum WorkspaceHandoffScene {
  spaces('S01–S02 · Spaces hub and customization'),
  emptySpaces('S01 · Empty Spaces'),
  homeProjects('S03 · Home Projects'),
  learning('S04 · Learning'),
  sports('S05 · Sports'),
  activeTask('T01–T03 · Active task and finish choices'),
  pausedTask('T02 · Paused task'),
  finishedTask('T03 · Finished result'),
  privateWorkspace('S/T · Temporary private workspace'),
  preview('H01 · Exact reviewed-text preview'),
  sharedAndReturn('H02–H03 · Shared view and owner return'),
  revokedHandoff('H02 · Eligibility withdrawn'),
  corruptHandoff('H03 · Unreadable gate'),
  failedHandoffWrite('H01–H03 · Unconfirmed storage write'),
  unsupportedHandoff('H01 · Unsupported capability');

  const WorkspaceHandoffScene(this.label);
  final String label;
}

class WorkspaceHandoffGalleryMenu extends StatelessWidget {
  const WorkspaceHandoffGalleryMenu({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WingmanSection(title: 'Spaces, Finish Mode & Hand It Over'),
      const Text(
        'SYNTHETIC DEVELOPMENT SCENES · Memory only. No owner data, native secure storage, clipboard or network content. Handoff is a visual simulation here, not device protection.',
      ),
      for (final scene in WorkspaceHandoffScene.values)
        ListTile(
          title: Text(scene.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorkspaceHandoffGallery(scene: scene),
            ),
          ),
        ),
    ],
  );
}

class WorkspaceHandoffGallery extends StatefulWidget {
  const WorkspaceHandoffGallery({super.key, required this.scene});
  final WorkspaceHandoffScene scene;
  @override
  State<WorkspaceHandoffGallery> createState() =>
      _WorkspaceHandoffGalleryState();
}

class _WorkspaceHandoffGalleryState extends State<WorkspaceHandoffGallery> {
  late final Future<_Scope> _scope;
  @override
  void initState() {
    super.initState();
    _scope = _Scope.create(widget.scene);
  }

  @override
  void dispose() {
    unawaited(
      _scope.then(
        (scope) => scope.dispose(),
        onError: (Object _, StackTrace _) {},
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return FutureBuilder<_Scope>(
      future: _scope,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const WingmanPage(
            title: 'Synthetic scene unavailable',
            child: WingmanStatus(
              title: 'Fixture failed to initialize',
              message: 'No owner data was opened. Return to the gallery.',
            ),
          );
        }
        final scope = snapshot.data;
        if (scope == null) {
          return const WingmanPage(
            title: 'Loading synthetic scene',
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Verifying signed bundled assets into memory only.'),
              ],
            ),
          );
        }
        return Column(
          children: [
            Material(
              color: WingmanTokens.of(context).raised,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'SYNTHETIC S/T/H · Memory only · Demo code: 24681357',
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Leave gallery scene'),
                      ),
                    ],
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

  Widget _screen(_Scope scope) {
    if (widget.scene.index >= WorkspaceHandoffScene.preview.index) {
      if (widget.scene == WorkspaceHandoffScene.unsupportedHandoff) {
        return const WingmanPage(
          title: 'Hand It Over',
          child: WingmanStatus(
            title: 'Unavailable on this platform',
            message:
                'This fixture represents the unsupported state. The actual web app cannot create a secure owner-return gate.',
          ),
        );
      }
      return HandoffGate(
        controller: scope.handoff,
        ownerBuilder: (_) {
          if (scope.handoffPreview != null && !scope.handoffStarted) {
            // Match the real two-route preview flow without putting the gallery
            // navigator inside the protected guest. A successful setup pop is
            // local to this synthetic owner stack, so the fixture stays alive.
            return Navigator(
              initialRoute: '/preview',
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => settings.name == '/preview'
                    ? HandoffSetupPage(
                        controller: scope.handoff,
                        preview: scope.handoffPreview!,
                      )
                    : const WingmanPage(
                        title: 'Synthetic owner',
                        child: Text('Memory-only preview stack.'),
                      ),
              ),
            );
          }
          return const WingmanPage(
            title: 'Synthetic owner returned',
            child: WingmanStatus(
              title: 'Return confirmed in memory',
              message:
                  'This demonstrates the UI flow only. No real secure-store or device-authentication operation occurred.',
            ),
          );
        },
      );
    }
    final private = widget.scene == WorkspaceHandoffScene.privateWorkspace;
    return WorkspaceScreen(
      controller: scope.workspaces,
      policy: scope.policy,
      additional: AdditionalRestrictions.new,
      journal: scope.journal,
      initialSpaceId: switch (widget.scene) {
        WorkspaceHandoffScene.homeProjects ||
        WorkspaceHandoffScene.privateWorkspace =>
          scope.spaces[SpaceKind.homeProjects],
        WorkspaceHandoffScene.learning => scope.spaces[SpaceKind.learning],
        WorkspaceHandoffScene.sports => scope.spaces[SpaceKind.sports],
        _ => null,
      },
      initialTaskId: switch (widget.scene) {
        WorkspaceHandoffScene.activeTask ||
        WorkspaceHandoffScene.pausedTask ||
        WorkspaceHandoffScene.finishedTask => scope.taskId,
        _ => null,
      },
      contentContext: ContentContext.general,
      isPrivate: private,
      readingIds: () => const ['moon-phases'],
      onOpenResource: (_) =>
          _notice('Synthetic guide action intercepted; no browser opens.'),
      onOfficialSearch: (_) => _notice(
        'Synthetic source action intercepted; no external application opens.',
      ),
      onHandoff: private
          ? null
          : (_) => _notice(
              'Use the dedicated Handoff gallery scenes. No native handoff begins here.',
            ),
      onResumeTask: (_) async =>
          _notice('Synthetic task resumed. No actual browser tab was created.'),
      onAssociateCurrentTab: (task) =>
          scope.workspaces.associateTab(task, 'gallery-tab', 'moon-phases'),
      onDetachTab: (task, tab) => scope.workspaces.detachTab(task, tab),
      onDeleteTask: scope.workspaces.deleteTask,
      onFinishTask: (_, close) async => _notice(
        close
            ? 'Synthetic finish saved. There are no real tabs to close.'
            : 'Synthetic finish saved; tab-close choice was off.',
      ),
    );
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _Scope {
  _Scope(this.policy, this.workspaces, this.journal, this.handoff);
  final PolicyRuntime policy;
  final WorkspaceController workspaces;
  final PrivacyJournal journal;
  final HandoffController handoff;
  final Map<SpaceKind, String> spaces = {};
  String? taskId;
  HandoffPreview? handoffPreview;
  bool handoffStarted = false;

  static Future<_Scope> create(WorkspaceHandoffScene scene) async {
    final policy = await PolicyRuntime.initialize(
      repository: SignedPolicyRepository(
        clock: PolicyClock(wallClock: () => DateTime.utc(2026, 9, 11, 12)),
      ),
      checkpointStore: _MemoryTrust(),
    );
    final private = scene == WorkspaceHandoffScene.privateWorkspace;
    final workspaces = WorkspaceController(
      store: MemorySignatureDocumentStore(),
      eligible: (id) =>
          policy.policy.evaluate(PolicyRequest.bundled(id)).isAllowed,
      ephemeral: private,
    );
    final journal = PrivacyJournal(
      sessionKind: private
          ? PrivacySessionKind.private
          : PrivacySessionKind.normal,
    );
    final store = _SyntheticHandoffStore()
      ..supported = scene != WorkspaceHandoffScene.unsupportedHandoff
      ..value = scene == WorkspaceHandoffScene.corruptHandoff
          ? 'SYNTHETIC-CORRUPT-MARKER'
          : null;
    late final _Scope scope;
    final handoff = HandoffController(
      store: store,
      derivation: const _SyntheticDerivation(),
      capabilities: () async =>
          const HandoffCapabilities(staticSupported: true),
      discardIncoming: () async {},
      onStarted: () => scope.handoffStarted = true,
    )..attachPolicy(policy);
    scope = _Scope(policy, workspaces, journal, handoff);
    try {
      await workspaces.initialize();
      await handoff.initialize();
      if (scene != WorkspaceHandoffScene.emptySpaces) {
        for (final kind in SpaceKind.values) {
          scope.spaces[kind] = await workspaces.createSpace(kind);
        }
        await workspaces.updateSpace(
          scope.spaces[SpaceKind.learning]!,
          choices: ['Science'],
        );
        await workspaces.updateSpace(
          scope.spaces[SpaceKind.sports]!,
          choices: ['Basketball', 'Cycling'],
        );
      }
      scope.taskId = await workspaces.createTask('Plan one small project');
      await workspaces.addChecklist(
        scope.taskId!,
        'Read the planning guide',
        isTask: true,
      );
      await workspaces.addChecklist(
        scope.taskId!,
        'Write the next step',
        isTask: true,
      );
      await workspaces.changeChecklist(
        scope.taskId!,
        workspaces.task(scope.taskId!)!.checklist.first.id,
        isTask: true,
      );
      await workspaces.associateTab(
        scope.taskId!,
        'gallery-task-tab',
        'plan-a-small-project',
      );
      if (scene == WorkspaceHandoffScene.pausedTask) {
        await workspaces.updateTask(scope.taskId!, status: FinishStatus.paused);
      }
      if (scene == WorkspaceHandoffScene.finishedTask) {
        await workspaces.finishTask(scope.taskId!, saveTabResources: true);
      }
      if (scene == WorkspaceHandoffScene.preview ||
          scene == WorkspaceHandoffScene.failedHandoffWrite) {
        scope.handoffPreview = handoff.preview(['moon-phases']);
        store.ignoreWrites = scene == WorkspaceHandoffScene.failedHandoffWrite;
      }
      if (scene == WorkspaceHandoffScene.sharedAndReturn ||
          scene == WorkspaceHandoffScene.revokedHandoff) {
        final result = await handoff.activate(
          preview: handoff.preview(['moon-phases'])!,
          code: '24681357',
          confirmation: '24681357',
        );
        if (!result.success) throw StateError('Synthetic activation failed');
        if (scene == WorkspaceHandoffScene.revokedHandoff) {
          policy.repository.restrict('synthetic-gallery-policy-unavailable');
        }
      }
      return scope;
    } catch (_) {
      scope.dispose();
      rethrow;
    }
  }

  void dispose() {
    handoff.dispose();
    workspaces.dispose();
    journal.dispose();
    policy.dispose();
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

class _SyntheticHandoffStore implements HandoffStore {
  @override
  bool supported = true;
  String? value;
  bool ignoreWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (!ignoreWrites) value = next;
  }
}

class _SyntheticDerivation implements PinDerivation {
  const _SyntheticDerivation();
  @override
  Future<List<int>> derive(String pin, List<int> salt) async =>
      (await Sha256().hash([...salt, ...utf8.encode(pin)])).bytes;
}
