part of 'controller.dart';

/// A category explanation derived from source outcomes and local visibility.
/// UI copy never turns a missing publisher or a deferred refresh into an
/// assertion about the reader's connection.
class LiveCategoryHealth {
  const LiveCategoryHealth(
    this.reason,
    this.title,
    this.message, {
    this.hasFailure = false,
    this.showNotice = false,
  });
  final String reason, title, message;
  final bool hasFailure, showNotice;
}

extension LiveContentDiagnostics on LiveContentController {
  Map<String, dynamic> _sourceState(String id) {
    final sources = _providerState?['sources'];
    final state = sources is Map ? sources[id] : null;
    return state is Map ? Map<String, dynamic>.from(state) : const {};
  }

  Map<String, dynamic> _sourceHealth(String id) {
    final state = _sourceState(id);
    final diagnostics = state['diagnostics'];
    return diagnostics is Map
        ? Map<String, dynamic>.from(diagnostics)
        : _snapshot?.sources
                  .where((s) => s.id == id)
                  .firstOrNull
                  ?.diagnostics ??
              const {};
  }

  bool _failedSource(String id) {
    final state = _sourceState(id), health = _sourceHealth(id);
    final outcome = health['outcome'];
    if ({'cache-prohibited', 'source-cache-prohibited'}.contains(outcome)) {
      return false;
    }
    if (outcome != null) {
      return {'transport-failure', 'parse-failure'}.contains(outcome) ||
          health['transportError'] != null ||
          health['parserError'] != null;
    }
    if (state['error'] != null) return true;
    return _snapshot?.staleSourceIds.contains(id) == true &&
        _snapshot?.sources.any(
              (s) => s.id == id && s.status == 'unavailable',
            ) ==
            true;
  }

  bool _topicSource(ApprovedLiveSource source, Set<String> topics) =>
      topics.isEmpty ||
      topics.contains('headlines') ||
      source.source.topics.any(topics.contains);

  LiveCategoryHealth get categoryHealth {
    if (!_owner || !_preferences.enabled) {
      return const LiveCategoryHealth(
        'disabled',
        'Discover is off',
        'Saved articles remain in your reading list.',
      );
    }
    if (!configured) {
      return const LiveCategoryHealth(
        'service-not-configured',
        'Live updates are not configured',
        'A shared feed service has not been connected. Search and saved articles remain available.',
      );
    }
    final categorySources = eligibility.registry.sources.values
        .where((s) => _topicSource(s, _preferences.selectedTopics))
        .toList();
    final active = categorySources
        .where(
          (s) =>
              s.enabled &&
              s.source.rights.titles &&
              !_revokedSources.contains(s.source.id),
        )
        .toList();
    if (active.isEmpty) {
      final review = _preferences.selectedTopics
          .map((topic) => eligibility.registry.reviewStatusByTopic[topic])
          .whereType<Map<String, dynamic>>();
      final pending = review.any(
        (r) =>
            (r['permissionRequired'] as num? ?? 0) > 0 ||
            (r['unreviewed'] as num? ?? 0) > 0,
      );
      return pending || categorySources.isNotEmpty
          ? const LiveCategoryHealth(
              'permission-pending',
              'Publisher permission needed',
              'Publishers for this category are awaiting review or display permission. Other categories remain available.',
            )
          : const LiveCategoryHealth(
              'no-production-source',
              'No publishers connected for this category',
              'Wingman has no active editorial source for this category yet. Other categories remain available.',
            );
    }
    if (!active.any((source) => !source.isSponsoredSyndication)) {
      return LiveCategoryHealth(
        'no-production-editorial-source',
        'No editorial publishers connected for this category',
        'This category has no connected editorial publisher yet. Any available sponsored features are labeled separately.',
        showNotice: items.isNotEmpty,
      );
    }
    final followed = active
        .where((s) => _preferences.follows(s.source.id))
        .toList();
    if (followed.isEmpty) {
      return const LiveCategoryHealth(
        'local-filters',
        'No updates match your choices',
        'The publishers for this category are hidden by your source choices. Review topics and sources to show them.',
      );
    }
    final ids = followed.map((s) => s.source.id).toSet();
    final relevant = (_snapshot?.items ?? const <LiveContentItem>[])
        .where(
          (i) =>
              ids.contains(i.sourceId) &&
              (_preferences.selectedTopics.isEmpty ||
                  _matchesTopics(i, _preferences.selectedTopics)),
        )
        .toList();
    final accepted = relevant.where(_accepts).toList();
    final visible = items;
    final failed = followed.where((s) => _failedSource(s.source.id)).length;
    final globalFailure =
        _error != null &&
        (_providerState == null ||
            followed.every((s) => _sourceHealth(s.source.id).isEmpty));
    if (failed > 0 || globalFailure) {
      final all = failed == followed.length || globalFailure;
      return LiveCategoryHealth(
        all ? 'fetch-failure' : 'partial-publisher-failure',
        all ? 'Publisher updates are delayed' : 'Some publishers are delayed',
        visible.isEmpty
            ? 'The publishers for this category could not complete their latest update. Wingman will retry at the scheduled time.'
            : 'Available articles remain below. Publisher updates will retry at the scheduled time.',
        hasFailure: true,
        showNotice: true,
      );
    }
    if (visible.isNotEmpty) {
      return const LiveCategoryHealth('available', 'Updates available', '');
    }
    if (accepted.any((i) => !requiresAssociatedPhoto(i))) {
      return const LiveCategoryHealth(
        'local-filters',
        'No updates match your choices',
        'Your local language, region or dismissed-story choices hide the available articles. Review topics and sources.',
      );
    }
    if (accepted.isNotEmpty) {
      return const LiveCategoryHealth(
        'required-image-unavailable',
        'Story photos are unavailable',
        'These sponsored features require their complete article and associated photo. They will appear when their permitted photos are available.',
      );
    }
    if (followed.any((source) => _cacheProhibited(source.source.id))) {
      return const LiveCategoryHealth(
        'cache-prohibited',
        'Publisher storage is restricted',
        'A publisher currently disallows storing its feed, and no other eligible stories are available in this category. Other categories remain available.',
      );
    }
    final outcomes = followed
        .map((s) => _sourceHealth(s.source.id)['outcome'])
        .toSet();
    if (outcomes.contains('deferred') ||
        outcomes.contains('not-due') ||
        outcomes.contains('publisher-hold') ||
        (_snapshot == null && _error == null)) {
      return const LiveCategoryHealth(
        'scheduled',
        'Updates are scheduled',
        'These publishers are queued or are not due for another check yet. Wingman continues updating while Discover is active.',
      );
    }
    if (relevant.isNotEmpty || outcomes.contains('content-held')) {
      return const LiveCategoryHealth(
        'policy-held',
        'No eligible updates right now',
        'The current stories do not meet the source, date or protection requirements for this category. Other categories remain available.',
      );
    }
    if (outcomes.contains('cache-prohibited')) {
      return const LiveCategoryHealth(
        'cache-prohibited',
        'Publisher storage is restricted',
        'The publisher currently disallows storing this feed. Other publishers remain available.',
      );
    }
    return const LiveCategoryHealth(
      'no-recent-matches',
      'No recent stories in this category',
      'The connected publishers returned no matching recent articles. This is a content-availability gap; other categories remain available.',
    );
  }

  /// Bounded common-content diagnostics. No local topic selection, source hides,
  /// reading-list activity, reader identifier or browsing history is exported.
  Map<String, Object?> diagnostics() {
    if (!_owner || !_preferences.enabled) {
      return const {'schemaVersion': 1, 'status': 'inactive'};
    }
    final sourceRows = <Map<String, Object?>>[];
    for (final approved in eligibility.registry.sources.values.take(256)) {
      final id = approved.source.id,
          state = _sourceState(id),
          health = _sourceHealth(id);
      final rows = (_snapshot?.items ?? const <LiveContentItem>[])
          .where((i) => i.sourceId == id)
          .toList();
      final eligible = rows.where(_accepts).toList();
      final images = eligible.where(hasUsableImage).toList();
      final fallbacks = eligible
          .where((i) => !hasUsableImage(i) && !requiresAssociatedPhoto(i))
          .length;
      final newest = rows
          .map((i) => i.publishedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      final reported = <String, Object?>{};
      for (final key in [
        'countedAt',
        'lastError',
        'lastAttemptOutcome',
        'optionalFieldReasons',
        'checkedAt',
        'attemptedAt',
        'lastSuccessAt',
        'nextDueAt',
        'outcome',
        'httpStatus',
        'transportError',
        'parserError',
        'configured',
        'enabled',
        'due',
        'deferred',
        'requested',
        'fetched',
        'parsedEntries',
        'textEligible',
        'topicMatched',
        'imagePermitted',
        'rejectedEntries',
        'newestPublicationAt',
        'rejectionReasons',
      ]) {
        final value = health[key];
        if (value == null) continue;
        if (value is bool) {
          reported[key] = value;
        } else if (value is num && value.isFinite) {
          reported[key] = value.toInt().clamp(0, 100000);
        } else if (value is String &&
            value.length <= 80 &&
            RegExp(r'^[a-zA-Z0-9:.+Z_-]+$').hasMatch(value)) {
          reported[key] = value;
        } else if (value is Map &&
            {'rejectionReasons', 'optionalFieldReasons'}.contains(key)) {
          reported[key] = {
            for (final entry in value.entries.take(32))
              if (entry.key is String &&
                  RegExp(r'^[a-z][a-z0-9-]{0,79}$').hasMatch(entry.key) &&
                  entry.value is num)
                entry.key: (entry.value as num).toInt().clamp(0, 100000),
          };
        }
      }
      final imageOutcomes = <String, int>{};
      final imageStatuses = <String, int>{};
      DateTime? imageCheckedAt, imageNextDueAt;
      final imageReasons = <String, int>{};
      for (final item in eligible.where((i) => imageFor(i) != null)) {
        final detail = _imageLoader.statusFor(item);
        final status = detail['outcome'] as String? ?? 'not-requested';
        final checked = DateTime.tryParse(detail['checkedAt'] as String? ?? '');
        final next = DateTime.tryParse(detail['nextDueAt'] as String? ?? '');
        if (checked != null &&
            (imageCheckedAt == null || checked.isAfter(imageCheckedAt))) {
          imageCheckedAt = checked;
        }
        if (next != null &&
            (imageNextDueAt == null || next.isBefore(imageNextDueAt))) {
          imageNextDueAt = next;
        }
        if (detail['httpStatus'] is int) {
          final code = detail['httpStatus'].toString();
          imageStatuses[code] = (imageStatuses[code] ?? 0) + 1;
        }
        final reason = detail['reason'];
        if (reason is String &&
            RegExp(r'^[a-z][a-z0-9-]{0,79}$').hasMatch(reason)) {
          imageReasons[reason] = (imageReasons[reason] ?? 0) + 1;
        }
        imageOutcomes[status] = (imageOutcomes[status] ?? 0) + 1;
      }
      sourceRows.add({
        'sourceId': id,
        'publisherId': approved.publisherId ?? approved.source.homepageUrl.host,
        'publisher': approved.source.name,
        'categories': approved.source.topics.toList()..sort(),
        'editorial': !approved.isSponsoredSyndication,
        'configured': approved.feedUri != null,
        'enabled': approved.enabled,
        'nextDueAt': state['nextRefreshAt'],
        ...reported,
        'currentSnapshotItems': rows.length,
        'currentTextEligible': eligible.length,
        'imagePermitted': eligible
            .where((i) => imageFor(i) != null || StoryImages.forItem(i) != null)
            .length,
        'imageLoaded': images.length,
        'visible': images.length + fallbacks,
        'imageCards': images.length,
        'textFallbacks': fallbacks,
        'imageOutcomes': imageOutcomes,
        'imageHttpStatuses': imageStatuses,
        'imageReasons': imageReasons,
        'imageCheckedAt': imageCheckedAt?.toIso8601String(),
        'imageNextDueAt': imageNextDueAt?.toIso8601String(),
        'newestPublicationAt': newest?.toIso8601String(),
        'holdReason': !approved.enabled
            ? 'source-disabled'
            : !approved.source.rights.titles
            ? 'title-permission-denied'
            : _revokedSources.contains(id)
            ? 'source-revoked'
            : health['outcome'],
      });
    }
    final categories = <Map<String, Object?>>[];
    for (final topic in liveContentTopicOrder) {
      final publishers = sourceRows
          .where(
            (s) =>
                topic == 'headlines' ||
                (s['categories'] as List).contains(topic),
          )
          .toList();
      final ids = publishers.map((s) => s['sourceId']).toSet();
      final rows = (_snapshot?.items ?? const <LiveContentItem>[])
          .where(
            (i) =>
                ids.contains(i.sourceId) &&
                (topic == 'headlines' || _matchesTopics(i, {topic})),
          )
          .toList();
      final eligible = rows.where(_accepts).toList();
      final imageCards = eligible.where(hasUsableImage).length;
      final fallbacks = eligible
          .where((i) => !hasUsableImage(i) && !requiresAssociatedPhoto(i))
          .length;
      final editorial = eligible
          .where((i) => !requiresAssociatedPhoto(i))
          .toList();
      final recent = editorial
          .where(
            (i) =>
                i.publishedAt != null &&
                !i.publishedAt!.isBefore(
                  _now.subtract(const Duration(hours: 72)),
                ),
          )
          .toList();
      final newest = rows
          .map((i) => i.publishedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      categories.add({
        'category': topic,
        'configuredSources': publishers.length,
        for (final key in [
          'enabled',
          'due',
          'deferred',
          'requested',
          'fetched',
        ])
          key: publishers.where((s) => s[key] == true).length,
        for (final key in [
          'parsedEntries',
          'textEligible',
          'topicMatched',
          'imagePermitted',
        ])
          key: publishers.fold<int>(
            0,
            (n, s) => n + ((s[key] as num?)?.toInt() ?? 0),
          ),
        'imageLoaded': imageCards,
        'enabledEditorialPublishers': publishers
            .where((s) => s['enabled'] == true && s['editorial'] == true)
            .map((s) => s['publisherId'])
            .toSet()
            .length,
        'fetchedItems': publishers.fold<int>(
          0,
          (n, s) => n + ((s['parsedEntries'] as num?)?.toInt() ?? 0),
        ),
        'eligibleItems': eligible.length,
        'imageCards': imageCards,
        'textFallbacks': fallbacks,
        'visible': imageCards + fallbacks,
        'newestPublicationAt': newest?.toIso8601String(),
        'editorialStoriesWithin72Hours': recent.length,
        'editorialPublishersWithin72Hours': recent
            .map(
              (i) =>
                  eligibility.registry.sources[i.sourceId]?.publisherId ??
                  eligibility
                      .registry
                      .sources[i.sourceId]
                      ?.source
                      .homepageUrl
                      .host,
            )
            .toSet()
            .length,
        'editorialImageCardsWithin72Hours': recent.where(hasUsableImage).length,
        'review': eligibility.registry.reviewStatusByTopic[topic],
      });
    }
    return {
      'schemaVersion': 1,
      'checkedAt': _now.toIso8601String(),
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'buildCommit': const String.fromEnvironment(
        'WINGMAN_BUILD_COMMIT',
        defaultValue: 'not-embedded',
      ),
      'buildVersion': const String.fromEnvironment(
        'WINGMAN_BUILD_VERSION',
        defaultValue: 'not-embedded',
      ),
      'providerMode': provider is SnapshotFeedProvider
          ? 'shared-snapshot'
          : provider is ResumableFeedProvider
          ? 'native-rss'
          : 'unconfigured-or-test',
      'configuredEndpoint': provider is SnapshotFeedProvider
          ? (provider as SnapshotFeedProvider).endpoint.toString()
          : null,
      'registryDigest': eligibility.registry.digest,
      'lastAttemptAt': _lastAttemptAt?.toIso8601String(),
      'lastSuccessAt': _lastSuccessAt?.toIso8601String(),
      'snapshotGeneratedAt': _snapshot?.generatedAt.toIso8601String(),
      'visibilityScope':
          'common eligible catalog before reader preferences and pagination',
      'sources': sourceRows,
      'categories': categories,
      'imageClassification':
          'Approved source/rendition and story checks only; no claim of complete visual classification.',
    };
  }
}
