// Development fixtures only. This file is never imported by lib/main.dart.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_screen.dart';
import 'package:wingman_browser/signature/official_routes/official_routes_screen.dart';
import 'package:wingman_browser/signature/official_routes/review_request_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';

enum OfficialCommitScene {
  officialCatalog('O01–O02 · Catalog and evidence'),
  officialEmpty('O01 · No matching identity'),
  officialExpired('O02 · Expired identity evidence'),
  officialRevoked('O02 · Revoked identity evidence'),
  policyUnavailable('O02 · Policy unavailable'),
  request('O03 · Local request and validation'),
  analysis('C01–C04 · Local findings and export'),
  privateAnalysis('C01–C04 · Private temporary analysis'),
  pendingAnalysis('C02 · Pending check and cancellation'),
  failedSave('C04 · Failed local save'),
  failedCopy('C04 · Unconfirmed clipboard export');

  const OfficialCommitScene(this.label);
  final String label;
}

class OfficialCommitGalleryMenu extends StatelessWidget {
  const OfficialCommitGalleryMenu({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WingmanSection(title: 'Official Routes & Before You Commit'),
      const Text(
        'SYNTHETIC DEVELOPMENT SCENES · No owner data. No actual clipboard writes. Use the real controls to inspect each state.',
      ),
      for (final scene in OfficialCommitScene.values)
        ListTile(
          title: Text(scene.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OfficialCommitGallery(scene: scene),
            ),
          ),
        ),
    ],
  );
}

class OfficialCommitGallery extends StatefulWidget {
  const OfficialCommitGallery({super.key, required this.scene});
  final OfficialCommitScene scene;
  @override
  State<OfficialCommitGallery> createState() => _OfficialCommitGalleryState();
}

class _OfficialCommitGalleryState extends State<OfficialCommitGallery> {
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
              message:
                  'No owner storage was opened. Return to the development gallery.',
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
                Text('Verifying bundled assets into memory only.'),
              ],
            ),
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
                    'SYNTHETIC O/C SCENE · Memory only · Clipboard intercepted',
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

  Widget _screen(_Scope scope) => switch (widget.scene) {
    OfficialCommitScene.officialCatalog ||
    OfficialCommitScene.officialEmpty ||
    OfficialCommitScene.officialExpired ||
    OfficialCommitScene.officialRevoked ||
    OfficialCommitScene.policyUnavailable => OfficialRoutesScreen(
      policy: scope.policy,
      additional: AdditionalRestrictions.new,
      journal: scope.journal,
      catalog: scope.catalog,
      copyReviewRequest: scope.copy,
      initialQuery: widget.scene == OfficialCommitScene.officialEmpty
          ? 'synthetic-no-matching-identity'
          : widget.scene == OfficialCommitScene.officialCatalog
          ? ''
          : 'Apple',
      onOpenResource: (_) {
        /* Local-guide navigation is intercepted in this fixture. */
      },
    ),
    OfficialCommitScene.request => RequestReviewScreen(
      journal: scope.journal,
      copyText: scope.copy,
    ),
    _ => CommitReviewScreen(
      policy: scope.policy,
      additional: AdditionalRestrictions.new,
      journal: scope.journal,
      isPrivate: widget.scene == OfficialCommitScene.privateAnalysis,
      analyzer: widget.scene == OfficialCommitScene.pendingAnalysis
          ? _PendingAnalyzer()
          : const CommitReviewAnalyzer(),
      savedAnalyses: () => scope.saved,
      onSave: (record) async {
        if (widget.scene == OfficialCommitScene.failedSave) {
          throw StateError('Synthetic storage failure');
        }
        scope.saved.add(record);
      },
      onDelete: (id) async =>
          scope.saved.removeWhere((record) => record['id'] == id),
      copyText: widget.scene == OfficialCommitScene.failedCopy
          ? (_) async => throw StateError('Synthetic clipboard failure')
          : scope.copy,
    ),
  };
}

class _Scope {
  _Scope(this.policy, this.catalog, this.journal);
  final PolicyRuntime policy;
  final OfficialRouteCatalog catalog;
  final PrivacyJournal journal;
  final List<Map<String, Object?>> saved = [];
  final List<String> interceptedCopies = [];

  static Future<_Scope> create(OfficialCommitScene scene) async {
    final date = scene == OfficialCommitScene.officialExpired
        ? DateTime.utc(2026, 12, 11, 12)
        : DateTime.utc(2026, 9, 11, 12);
    final policy = await PolicyRuntime.initialize(
      repository: SignedPolicyRepository(
        clock: PolicyClock(wallClock: () => date),
      ),
      checkpointStore: _MemoryTrust(),
    );
    try {
      final raw =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/signature/official_routes.json',
                ),
              )
              as Map<String, dynamic>;
      if (scene == OfficialCommitScene.officialRevoked) {
        for (final row in raw['routes'] as List) {
          if (row['id'] == 'apple-support') row['revoked'] = true;
        }
      }
      final catalog = OfficialRouteCatalog.decode(jsonEncode(raw));
      if (scene == OfficialCommitScene.policyUnavailable) {
        policy.repository.restrict('synthetic-gallery-unavailable');
      }
      return _Scope(
        policy,
        catalog,
        PrivacyJournal(
          sessionKind: scene == OfficialCommitScene.privateAnalysis
              ? PrivacySessionKind.private
              : PrivacySessionKind.normal,
        ),
      );
    } catch (_) {
      policy.dispose();
      rethrow;
    }
  }

  Future<void> copy(String text) async {
    interceptedCopies.add(text);
  }

  void dispose() {
    journal.dispose();
    policy.dispose();
    saved.clear();
    interceptedCopies.clear();
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

class _PendingAnalyzer extends CommitReviewAnalyzer {
  @override
  Future<CommitReviewReport> analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) => Completer<CommitReviewReport>().future;
}
