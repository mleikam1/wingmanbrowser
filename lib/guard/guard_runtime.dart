import 'domain_normalizer.dart';
import 'filter_pack_repository.dart';
import 'navigation_policy_service.dart';
import 'safe_search_policy.dart';
import 'sqlite_filter_pack_repository.dart';

export 'domain_normalizer.dart';
export 'filter_pack_repository.dart';
export 'guard_models.dart';
export 'https_filter_pack_update_source.dart';
export 'navigation_policy_service.dart';
export 'safe_search_policy.dart';
export 'signed_filter_manifest.dart';
export 'sqlite_filter_pack_repository.dart';

class GuardRuntime {
  GuardRuntime._(this.repository, this.normalizer)
    : policy = NavigationPolicyService(
        repository: repository,
        normalizer: normalizer,
      );
  final FilterPackRepository repository;
  final DomainNormalizer normalizer;
  final NavigationPolicyService policy;
  final SafeSearchPolicy safeSearch = const SafeSearchPolicy();

  static Future<GuardRuntime> initialize({
    FilterPackRepository? repository,
    DomainNormalizer? normalizer,
  }) async {
    final storage = repository ?? SqliteFilterPackRepository();
    await storage.init();
    return GuardRuntime._(storage, normalizer ?? DomainNormalizer());
  }
}
