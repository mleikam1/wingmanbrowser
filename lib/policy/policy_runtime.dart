import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/product_edition.dart';
import 'policy_checkpoint_store.dart';
import 'policy_models.dart';
import 'signed_policy_repository.dart';
import 'live_browsing_policy.dart';
import 'strict_search_policy.dart';
import 'consumer_protection_policy.dart';

export 'policy_models.dart';
export 'signed_policy_repository.dart';
export 'policy_checkpoint_store.dart';
export 'live_browsing_policy.dart';
export 'strict_search_policy.dart';
export 'consumer_protection_policy.dart';

class ContentEligibilityService {
  ContentEligibilityService(this.repository, {this.edition = productEdition});
  final ProductEdition edition;
  ConsumerProtectionPolicy consumerProtection =
      const ConsumerProtectionPolicy.unavailable();
  final SignedPolicyRepository repository;
  LiveBrowsingPolicy? livePolicy;
  bool nativeLiveAvailable = false, privateLiveAvailable = false;
  bool nativeSearchAvailable = false;

  /// A hidden reviewed source subtracts its listed document URLs. This mapping
  /// never permits a URL or depends on review/catalog freshness.
  Set<String> blockedBrowsingUrls(AdditionalRestrictions? additional) => {
    for (final site in livePolicy?.sites ?? const <LiveSiteRecord>[])
      if (additional?.blockedResourceIds.contains(site.id) == true ||
          additional?.blockedCollections.contains(site.collection) == true)
        for (final document in site.documents) document.url,
  };

  PolicyDecision evaluate(
    PolicyRequest request, {
    AdditionalRestrictions? additional,
  }) {
    if (request.operation == PolicyOperation.navigate && request.uri != null) {
      if (!nativeLiveAvailable ||
          (request.isPrivate && !privateLiveAvailable)) {
        return const PolicyDecision(
          PolicyDecisionCode.blockUnsupportedCapability,
        );
      }
      if (edition == ProductEdition.consumer) {
        if (const StrictSearchPolicy().acceptsCanonical(request.uri!) &&
            !nativeSearchAvailable) {
          return const PolicyDecision(
            PolicyDecisionCode.blockUnsupportedCapability,
          );
        }
        final decision = consumerProtection.assessNavigation(
          request.uri!,
          additional: additional,
        );
        if (!decision.isAllowed) return decision;
        // Existing reviewed-site identifiers remain subtractive metadata for
        // saved user restrictions. Their expiry never becomes an allow gate.
        final site = livePolicy?.siteForUri(request.uri!);
        if (site != null &&
            (additional?.blockedResourceIds.contains(site.id) == true ||
                additional?.blockedCollections.contains(site.collection) ==
                    true)) {
          return const PolicyDecision(
            PolicyDecisionCode.blockAdditionalRestriction,
          );
        }
        return decision;
      }
      // Managed school mode remains explicitly allowlisted. Consumer policy
      // cannot silently expand its documents, resources, or search permissions.
      if (!repository.status.usable || livePolicy == null) {
        return const PolicyDecision(PolicyDecisionCode.blockPolicyUnavailable);
      }
      return livePolicy!.assessNavigation(
        request.uri!,
        context: edition == ProductEdition.consumer
            ? request.context
            : ContentContext.student,
        additional: additional,
        now: repository.clock.now(),
      );
    }
    // Browser-owned resource/authentication/download operations are enforced
    // by the native adapter. This service also owns reviewed local documents.
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
    final context = edition == ProductEdition.consumer
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
  ConsumerProtectionPolicy get consumerProtection => policy.consumerProtection;
  bool _consumerUpdatesConfigured = false;
  bool get consumerUpdatesConfigured => _consumerUpdatesConfigured;

  void configureConsumerUpdateAvailability({required bool configured}) {
    _consumerUpdatesConfigured = configured;
    if (!_disposed) notifyListeners();
  }

  bool liveAvailable({bool isPrivate = false}) =>
      policy.nativeLiveAvailable &&
      (!isPrivate || policy.privateLiveAvailable) &&
      (productEdition == ProductEdition.consumer
          ? consumerProtection.isUsable
          : status.usable &&
                (policy.livePolicy?.isUsable(now: clock.now()) ?? false));

  bool searchAvailable({
    bool isPrivate = false,
    AdditionalRestrictions? additional,
  }) =>
      productEdition == ProductEdition.consumer &&
      (kIsWeb ||
          (liveAvailable(isPrivate: isPrivate) &&
              policy.nativeSearchAvailable)) &&
      additional?.blockedCollections.contains('web-search') != true &&
      additional?.blockedResourceIds.contains('web-search') != true &&
      additional?.blockedDomains.any(
            (domain) => hostMatches('safe.duckduckgo.com', domain),
          ) !=
          true;

  void configureConsumerProtection(ConsumerProtectionPolicy protection) {
    policy.consumerProtection = protection;
    if (!_disposed) notifyListeners();
  }

  /// Immutable edition and additive restrictions are the only caller-provided
  /// inputs. Native adapters load mandatory data from their pinned asset.
  Map<String, Object?> nativeConsumerConfiguration(
    AdditionalRestrictions additional,
  ) => {
    'edition': productEdition.name,
    'blockedDomains': additional.blockedDomains.toList()..sort(),
    'blockedUrls': policy.blockedBrowsingUrls(additional).toList()..sort(),
    'blockedCollections': additional.blockedCollections.toList()..sort(),
    'blockedResourceIds': additional.blockedResourceIds.toList()..sort(),
  };

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
    ConsumerProtectionPolicy? consumerProtection,
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
    runtime.policy.consumerProtection =
        consumerProtection ?? await ConsumerProtectionPolicy.load();
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
