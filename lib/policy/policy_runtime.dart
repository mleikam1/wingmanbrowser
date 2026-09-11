import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/product_edition.dart';
import 'policy_checkpoint_store.dart';
import 'policy_models.dart';
import 'signed_policy_repository.dart';

export 'policy_models.dart';
export 'signed_policy_repository.dart';
export 'policy_checkpoint_store.dart';

class ContentEligibilityService {
  ContentEligibilityService(this.repository);
  final SignedPolicyRepository repository;
  PolicyDecision evaluate(
    PolicyRequest request, {
    AdditionalRestrictions? additional,
  }) {
    // Capability is compiled, not granted by a role, JSON field or signed host.
    if (request.operation != PolicyOperation.renderBundled ||
        request.uri != null) {
      return const PolicyDecision(
        PolicyDecisionCode.blockUnsupportedCapability,
      );
    }
    if (!repository.status.usable) {
      return const PolicyDecision(PolicyDecisionCode.blockPolicyUnavailable);
    }
    final record = repository.resources
        .where((r) => r.id == request.resourceId)
        .firstOrNull;
    if (record == null) {
      return const PolicyDecision(PolicyDecisionCode.blockUnreviewed);
    }
    final context = productEdition == ProductEdition.consumer
        ? request.context
        : ContentContext.student;
    if (!record.contexts.contains(context)) {
      return const PolicyDecision(PolicyDecisionCode.blockUnreviewed);
    }
    // The small support directory remains available when otherwise eligible.
    if (record.collection != 'support' &&
        (additional?.blockedResourceIds.contains(record.id) == true ||
            additional?.blockedCollections.contains(record.collection) ==
                true)) {
      return PolicyDecision(
        PolicyDecisionCode.blockAdditionalRestriction,
        resourceId: record.id,
        safeTitle: record.title,
      );
    }
    return PolicyDecision(
      PolicyDecisionCode.allowApproved,
      resourceId: record.id,
      safeTitle: record.title,
    );
  }
}

class PolicyRuntime extends ChangeNotifier {
  PolicyRuntime._(this.repository, this._checkpointStore)
    : policy = ContentEligibilityService(repository);
  final SignedPolicyRepository repository;
  final PolicyCheckpointStore _checkpointStore;
  final ContentEligibilityService policy;
  Timer? _timer;
  bool _disposed = false;
  Future<void> _checkpointWrites = Future.value();
  bool _checkpointPending = false;
  List<ApprovedResource> get catalog => repository.resources;
  PolicyStatus get status => repository.status;
  PolicyClock get clock => repository.clock;
  ApprovedResource? resource(String id) =>
      catalog.where((r) => r.id == id).firstOrNull;

  static Future<PolicyRuntime> initialize({
    SignedPolicyRepository? repository,
    PolicyCheckpointStore? checkpointStore,
    DateTime Function()? clock,
  }) async {
    final store = checkpointStore ?? SqlitePolicyCheckpointStore();
    PolicyCheckpoint checkpoint;
    var checkpointFailed = false;
    try {
      checkpoint = await store.load();
    } catch (_) {
      checkpoint = PolicyCheckpoint();
      checkpointFailed = true;
    }
    final repo =
        repository ??
        SignedPolicyRepository(
          checkpoint: checkpoint,
          clock: PolicyClock(wallClock: clock, checkpoint: checkpoint.seenAt),
        );
    final runtime = PolicyRuntime._(repo, store);
    repo.beforeActivation = store.save;
    repo.addListener(runtime._repositoryChanged);
    if (checkpointFailed) {
      repo.restrict('checkpoint-unavailable');
      return runtime;
    }
    repo.adoptCheckpoint(checkpoint);
    await repo.init();
    if (repo.status.usable) await runtime.flushCheckpoint();
    runtime._schedule();
    return runtime;
  }

  List<ApprovedResource> search(
    String query, {
    AdditionalRestrictions? additional,
    ContentContext context = ContentContext.general,
  }) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(20)
        .toList();
    if (query.length > 1000) return const [];
    return catalog
        .where((r) {
          if (!policy
              .evaluate(
                PolicyRequest.bundled(r.id, context: context),
                additional: additional,
              )
              .isAllowed) {
            return false;
          }
          final text = '${r.title} ${r.summary} ${r.collection} ${r.body}'
              .toLowerCase();
          return terms.every(text.contains);
        })
        .take(100)
        .toList(growable: false);
  }

  Future<void> flushCheckpoint() {
    if (_checkpointPending) return _checkpointWrites;
    _checkpointPending = true;
    final next = _checkpointWrites
        .then((_) async {
          try {
            await _checkpointStore.save(repository.checkpoint);
          } catch (_) {
            repository.restrict('checkpoint-unavailable');
          }
          if (!_disposed) notifyListeners();
        })
        .whenComplete(() => _checkpointPending = false);
    _checkpointWrites = next;
    return next;
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    if (!status.usable || catalog.isEmpty) return;
    var wait = const Duration(minutes: 1);
    final expires = repository.nextExpiry;
    if (expires != null) {
      final remaining = expires.difference(clock.now());
      if (remaining.isNegative || remaining == Duration.zero) {
        notifyListeners();
        return;
      }
      if (remaining < wait) wait = remaining;
    }
    _timer = Timer(wait, () {
      // Invalidate displayed content synchronously. Disk I/O cannot extend an
      // approval's visible lifetime while a checkpoint save is pending.
      if (!_disposed) notifyListeners();
      // Expiry scheduling is independent of storage completion. At most one
      // checkpoint write remains pending while its database is slow/stalled.
      _schedule();
      if (!_checkpointPending) unawaited(flushCheckpoint());
    });
  }

  void _repositoryChanged() {
    if (_disposed) return;
    _schedule();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    repository.removeListener(_repositoryChanged);
    unawaited(_checkpointWrites.then((_) => _checkpointStore.close()));
    super.dispose();
  }
}
