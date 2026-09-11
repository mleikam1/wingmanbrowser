import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/product_edition.dart';
import 'policy_checkpoint_store.dart';
import 'policy_models.dart';
import 'signed_policy_repository.dart';
import 'live_browsing_policy.dart';
import 'strict_search_policy.dart';

export 'policy_models.dart';
export 'signed_policy_repository.dart';
export 'policy_checkpoint_store.dart';
export 'live_browsing_policy.dart';
export 'strict_search_policy.dart';

class ContentEligibilityService {
  ContentEligibilityService(this.repository);
  final SignedPolicyRepository repository;
  LiveBrowsingPolicy? livePolicy;
  bool nativeLiveAvailable = false, privateLiveAvailable = false;
  bool nativeSearchAvailable = false;
  PolicyDecision evaluate(
    PolicyRequest request, {
    AdditionalRestrictions? additional,
  }) {
    if (request.operation == PolicyOperation.navigate && request.uri != null) {
      if (!nativeLiveAvailable ||
          (request.isPrivate && !privateLiveAvailable) ||
          livePolicy == null) {
        return const PolicyDecision(
          PolicyDecisionCode.blockUnsupportedCapability,
        );
      }
      if (!repository.status.usable) {
        return const PolicyDecision(PolicyDecisionCode.blockPolicyUnavailable);
      }
      // Provider search is a separate capability with adult SafeSearch fixed
      // by the publisher. It does not classify its previews against the other
      // Wingman categories or grant permission to any result destination.
      if (const StrictSearchPolicy().acceptsCanonical(request.uri!)) {
        if (!nativeSearchAvailable) {
          return const PolicyDecision(
            PolicyDecisionCode.blockUnsupportedCapability,
          );
        }
        if (!livePolicy!.isUsable(now: repository.clock.now())) {
          return const PolicyDecision(
            PolicyDecisionCode.blockPolicyUnavailable,
          );
        }
        if (additional?.blockedCollections.contains('web-search') == true ||
            additional?.blockedResourceIds.contains('web-search') == true) {
          return const PolicyDecision(
            PolicyDecisionCode.blockAdditionalRestriction,
          );
        }
        return const PolicyDecision(
          PolicyDecisionCode.allowApproved,
          resourceId: 'web-search',
          safeTitle: 'DuckDuckGo search',
        );
      }
      return livePolicy!.assessNavigation(
        request.uri!,
        context: productEdition == ProductEdition.consumer
            ? request.context
            : ContentContext.student,
        additional: additional,
        now: repository.clock.now(),
      );
    }
    // Other capabilities remain unavailable; live navigation has its separate
    // immutable reviewed scope plus independent native resource enforcement.
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
  List<LiveSiteRecord> get liveSites => policy.livePolicy?.sites ?? const [];
  bool liveAvailable({bool isPrivate = false}) =>
      status.usable &&
      policy.nativeLiveAvailable &&
      (!isPrivate || policy.privateLiveAvailable) &&
      (policy.livePolicy?.isUsable(now: clock.now()) ?? false);

  bool searchAvailable({
    bool isPrivate = false,
    AdditionalRestrictions? additional,
  }) =>
      liveAvailable(isPrivate: isPrivate) &&
      policy.nativeSearchAvailable &&
      additional?.blockedCollections.contains('web-search') != true &&
      additional?.blockedResourceIds.contains('web-search') != true;

  /// Native capability is observed after startup quarantine; it is never loaded
  /// from preferences, a Launchpad record, user role or remote allow flag.
  void configureLiveBrowsing(
    LiveBrowsingPolicy reviewed, {
    required bool nativeAvailable,
    required bool privateAvailable,
    bool strictSearchAvailable = false,
  }) {
    policy.livePolicy = reviewed;
    policy.nativeLiveAvailable = nativeAvailable;
    policy.privateLiveAvailable = privateAvailable;
    policy.nativeSearchAvailable = strictSearchAvailable;
    _schedule();
    if (!_disposed) notifyListeners();
  }

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
    final now = clock.now();
    final expiries = [
      ?repository.nextExpiry,
      ?policy.livePolicy?.expiresAt,
      for (final site in liveSites.where((site) => site.enabled))
        site.expiresAt,
    ].where((expiry) => expiry.isAfter(now)).toList()..sort();
    final expires = expiries.firstOrNull;
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
