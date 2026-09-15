import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'eligibility.dart';
import 'models.dart';
import 'provider.dart';
import 'rss_parser.dart';
import 'ordering.dart';
import 'rss_transport.dart';
import 'rss_transport_native.dart'
    if (dart.library.js_interop) 'rss_transport_web.dart'
    as platform;
export 'rss_transport.dart';

/// No user interests, searches, browser cookies, history or account identifiers
/// enter this provider. A fixed approved source set is refreshed with three lanes.
class RssFeedProvider implements FeedProvider, ResumableFeedProvider {
  RssFeedProvider({
    required this.registry,
    required this.eligibility,
    required this.allowsEditorialText,
    RssFeedTransport? transport,
    DateTime Function()? clock,
  }) : _transport = transport ?? platform.createRssTransport(),
       _clock = clock ?? DateTime.now;
  static bool get supported => !kIsWeb;
  static const maximumEndpointAttempts = 12;
  final LiveSourceRegistry registry;
  final LiveContentEligibility eligibility;
  final bool Function(String, String) allowsEditorialText;
  final RssFeedTransport _transport;
  final DateTime Function() _clock;
  Map<String, dynamic> _state = {};
  LiveSnapshot? _snapshot;
  int _epoch = 0;
  @override
  void restore({LiveSnapshot? snapshot, Map<String, dynamic>? state}) {
    // Restore only a bounded JSON tree; controller owns all durable writes.
    if (state != null &&
        (state['schemaVersion'] != 1 ||
            utf8.encode(jsonEncode(state)).length > 450 * 1024 ||
            state['sources'] is! Map)) {
      throw const FormatException('Invalid publisher refresh state.');
    }
    final scheduler = state?['scheduler'];
    if (scheduler != null &&
        (scheduler is! Map ||
            scheduler['schemaVersion'] != 1 ||
            (scheduler['cursorAfter'] != null &&
                (scheduler['cursorAfter'] is! String ||
                    (scheduler['cursorAfter'] as String).length > 16384)))) {
      throw const FormatException('Invalid publisher scheduling cursor.');
    }
    _snapshot = snapshot;
    _state = state == null
        ? <String, dynamic>{}
        : feedMap(jsonDecode(jsonEncode(state)));
  }

  @override
  void cancel() {
    _epoch++;
    _transport.cancel();
  }

  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async {
    final epoch = _epoch, now = _clock().toUtc();
    void valid() {
      if (epoch != _epoch) throw const RssFailure('cancelled');
    }

    final approved = registry.sources.values.toList();
    final priorStates = feedMap(_state['sources'] ?? {});
    final states = <String, dynamic>{},
        health = <String, LiveSource>{},
        rows = <String, List<LiveContentItem>>{};
    final revoked = <String>{...?_snapshot?.revokedItemIds},
        revokedSources = <String>{...?_snapshot?.revokedSourceIds};
    DateTime? date(Object? value) {
      try {
        return value == null ? null : feedDate(value);
      } catch (_) {
        return null;
      }
    }

    Map<String, dynamic> priorFor(ApprovedLiveSource source) {
      final raw = priorStates[source.source.id];
      return raw is Map ? feedMap(raw) : <String, dynamic>{};
    }

    List<LiveContentItem> oldFor(ApprovedLiveSource source) =>
        (_snapshot?.items ?? const <LiveContentItem>[])
            .where(
              (i) =>
                  i.sourceId == source.source.id &&
                  i.expiresAt.isAfter(now) &&
                  eligibility.accepts(i, now: now) &&
                  (i.publishedAt == null ||
                      !i.publishedAt!.isBefore(
                        now.subtract(const Duration(days: 30)),
                      )),
            )
            .toList();

    String configKeyFor(ApprovedLiveSource source) => rssDigest(
      jsonEncode({
        'version': 3,
        'url': source.feedUri.toString(),
        'hosts': source.feedRedirectHosts.toList()..sort(),
        'articleHosts': source.allowedArticleHosts.toList()..sort(),
        'paths': source.articlePathPrefixes.toList()..sort(),
        'rights': source.source.rights.toJson(),
        'topics': source.source.topics.toList()..sort(),
        'terms': source.requiredTopicTerms.toList()..sort(),
        'format': source.articleUrlFormat,
        'requiresAuthor': source.requiresAttribution,
        'imagePolicy': source.imagePolicy?.toJson(),
        'preserveFeedText': source.preserveFeedText,
        'displayMode': source.displayMode,
        'feedCompatibility': source.feedCompatibility,
        'retention': source.retentionSeconds,
      }),
    );

    Map<String, String> validatorsFor(ApprovedLiveSource source) {
      final prior = priorFor(source), validators = <String, String>{};
      if (prior['configKey'] == configKeyFor(source) &&
          oldFor(source).isNotEmpty) {
        for (final key in ['etag', 'lastModified']) {
          final value = prior[key];
          if (value is String &&
              value.length <= 512 &&
              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
            validators[key == 'etag' ? 'If-None-Match' : 'If-Modified-Since'] =
                value;
          }
        }
      }
      return validators;
    }

    bool active(ApprovedLiveSource source) =>
        source.enabled &&
        source.feedUri != null &&
        priorFor(source)['revoked'] != true &&
        !revokedSources.contains(source.source.id);
    bool due(ApprovedLiveSource source) {
      final prior = priorFor(source),
          next = date(priorFor(source)['nextRefreshAt']);
      return active(source) &&
          prior['paused'] != true &&
          (next == null || !now.isBefore(next));
    }

    final groups = <String, List<ApprovedLiveSource>>{};
    for (final source in approved) {
      if (source.feedUri != null) {
        (groups[source.feedUri.toString()] ??= []).add(source);
      }
    }
    final endpointOrder = groups.keys.toList();
    final scheduler = _state['scheduler'] is Map
        ? feedMap(_state['scheduler'])
        : <String, dynamic>{};
    final previousCursor = scheduler['cursorAfter'] as String?;
    final start = endpointOrder.isEmpty
        ? 0
        : (endpointOrder.indexOf(previousCursor ?? '') + 1) %
              endpointOrder.length;
    final orderedEndpoints = [
      ...endpointOrder.skip(start),
      ...endpointOrder.take(start),
    ];
    // Every active alias must be due: one alias cannot bypass another alias's
    // Retry-After or HTTP freshness hold for the identical representation.
    final dueEndpoints = orderedEndpoints.where((url) {
      final members = groups[url]!.where(active).toList();
      return members.isNotEmpty && members.every(due);
    }).toList();
    final selected = dueEndpoints.take(maximumEndpointAttempts).toSet();
    final orderedSources = [
      for (final url in orderedEndpoints) ...groups[url]!,
      ...approved.where((source) => source.feedUri == null),
    ];
    final sharedResponses = <String, Future<RssFetchResponse>>{};
    final sharedValidators = <String, Map<String, String>>{};
    final attempted = <String>{}, deferredSources = <String>{};
    String? cursorAfter = previousCursor;
    var nextIndex = 0,
        anyFailure = false,
        rejected = 0,
        deadlineReached = false;
    final end = DateTime.now().add(const Duration(seconds: 45));
    final timer = Timer(const Duration(seconds: 45), () {
      deadlineReached = true;
      _transport.cancel();
    });
    Future<RssFetchResponse> endpointWork(ApprovedLiveSource source) {
      final url = source.feedUri.toString();
      return sharedResponses.putIfAbsent(url, () {
        final members = groups[url]!.where(active).toList();
        var validators = validatorsFor(members.first);
        if (members.any(
          (member) => !mapEquals(validators, validatorsFor(member)),
        )) {
          validators = <String, String>{};
        }
        sharedValidators[url] = validators;
        final hosts = members
            .map((member) => member.feedRedirectHosts)
            .reduce((a, b) => a.intersection(b));
        // A shared network response may not widen another source's redirect
        // authority. Normalization/rights/topic decisions still run per source.
        final transportSource = ApprovedLiveSource(
          source: source.source,
          allowedArticleHosts: source.allowedArticleHosts,
          articlePathPrefixes: source.articlePathPrefixes,
          eligibilityScope: source.eligibilityScope,
          enabled: source.enabled,
          feedUri: source.feedUri,
          feedRedirectHosts: hosts,
        );
        cursorAfter = url;
        attempted.add(url);
        return _transport
            .fetch(transportSource, validators)
            .timeout(end.difference(DateTime.now()));
      });
    }

    Future<void> sourceWork(ApprovedLiveSource source) async {
      valid();
      final id = source.source.id;
      final prior = priorFor(source);
      final state = Map<String, dynamic>.of(prior);
      states[id] = state;
      final old = oldFor(source);
      rows[id] = old;
      final due = date(prior['nextRefreshAt']);
      var lastSuccess = date(prior['lastSuccessAt']);
      var status = old.isEmpty ? 'unavailable' : 'cached';
      final priorRevoked = prior['revokedIds'];
      if (priorRevoked is List && priorRevoked.length <= 5000) {
        revoked.addAll(
          priorRevoked.whereType<String>().where(
            (v) => RegExp(r'^[a-f0-9]{32}$').hasMatch(v),
          ),
        );
      }
      if (!source.enabled ||
          prior['revoked'] == true ||
          revokedSources.contains(id)) {
        status = 'revoked';
        revokedSources.add(id);
        rows[id] = [];
      } else if (source.feedUri == null) {
        anyFailure = true;
      } else if (prior['paused'] == true ||
          (due != null && now.isBefore(due))) {
        anyFailure =
            anyFailure ||
            prior['paused'] == true ||
            prior['error'] != null ||
            old.isEmpty;
        status = old.isEmpty
            ? 'unavailable'
            : (lastSuccess != null && prior['error'] == null
                  ? 'fresh'
                  : 'cached');
      } else if (!selected.contains(source.feedUri.toString()) ||
          (!sharedResponses.containsKey(source.feedUri.toString()) &&
              (deadlineReached || !DateTime.now().isBefore(end)))) {
        // Deferred is not a failed attempt. Keep original pacing and cached
        // content; next common refresh resumes after the last started endpoint.
        deferredSources.add(id);
      } else {
        final configKey = configKeyFor(source);
        final compatible = prior['configKey'] == configKey;
        try {
          final response = await endpointWork(source);
          final validators = sharedValidators[source.feedUri.toString()]!;
          valid();
          final cache =
              response.headers['cache-control'] ??
              (response.status == 304
                  ? prior['cacheControl'] as String? ?? ''
                  : '');
          if (RegExp(
            r'(?:^|,)\s*(?:no-store|private)(?:\s*(?:,|=|$))',
            caseSensitive: false,
          ).hasMatch(cache)) {
            for (final item in old) {
              revoked.add(item.id);
            }
            rows[id] = [];
            throw const RssFailure('cache-prohibited');
          }
          if (response.status == 304) {
            if (old.isEmpty || !compatible || validators.isEmpty) {
              throw const RssFailure('unconditional-304');
            }
            rows[id] = old
                .map(
                  (i) => LiveContentItem.fromJson({
                    ...i.toJson(),
                    'fetchedAt': now.toIso8601String(),
                    'expiresAt': now
                        .add(Duration(seconds: source.retentionSeconds))
                        .toIso8601String(),
                  }),
                )
                .toList();
          } else if (response.status == 200) {
            final parsed = parseRssFeed(
              response.body,
              source,
              now,
              eligibility,
              allowsEditorialText,
            );
            rows[id] = parsed.items;
            rejected += parsed.rejected;
            revoked.addAll(parsed.revokedIds);
            final oldGuids = prior['guids'] is Map
                ? feedMap(prior['guids'])
                : <String, dynamic>{};
            for (final hash in parsed.deletedRefs) {
              final oldId = oldGuids[hash];
              if (oldId is String) revoked.add(oldId);
            }
            // Match tombstones against the previous finite feed, then retain
            // only this generation's bounded identity map.
            state['guids'] = parsed.guidToItem;
          } else {
            throw RssFailure(
              'http-${response.status}',
              headers: response.headers,
            );
          }
          final delay = rssRefreshDelay(
            {...response.headers, 'cache-control': cache},
            now,
            source.minRefreshSeconds,
          );
          state.addAll({
            'configKey': configKey,
            'lastSuccessAt': now.toIso8601String(),
            'nextRefreshAt': delay == null
                ? null
                : now.add(delay).toIso8601String(),
            'paused': delay == null,
            'failures': 0,
            'error': null,
            'cacheControl': cache,
            'etag':
                response.headers['etag'] ??
                (response.status == 304 ? prior['etag'] : null),
            'lastModified':
                response.headers['last-modified'] ??
                (response.status == 304 ? prior['lastModified'] : null),
          });
          lastSuccess = now;
          if (status != 'revoked') status = 'fresh';
        } catch (error) {
          valid();
          anyFailure = true;
          final count =
              ((prior['failures'] is int ? prior['failures'] as int : 0) + 1)
                  .clamp(1, 12);
          final ceiling = source.minRefreshSeconds > 21600
              ? source.minRefreshSeconds
              : 21600;
          final floor = (source.minRefreshSeconds * (1 << (count - 1))).clamp(
            source.minRefreshSeconds,
            ceiling,
          );
          final delay = rssRefreshDelay(
            error is RssFailure ? error.headers : const {},
            now,
            floor,
          );
          state.addAll({
            'nextRefreshAt': delay == null
                ? null
                : now.add(delay).toIso8601String(),
            'paused': delay == null,
            'failures': count,
            'error': error is RssFailure ? error.code : 'invalid-feed',
          });
          status = rows[id]!.isEmpty ? 'unavailable' : 'cached';
        }
      }
      state['revokedIds'] = revoked
          .where(
            (v) =>
                (priorRevoked is List && priorRevoked.contains(v)) ||
                old.any((i) => i.id == v) ||
                rows[id]!.any((i) => i.id == v),
          )
          .toList();
      health[id] = LiveSource(
        id: id,
        name: source.source.name,
        homepageUrl: source.source.homepageUrl,
        language: source.source.language,
        topics: source.source.topics,
        rights: source.source.rights,
        status: status,
        fetchedAt: lastSuccess,
        lastSuccessAt: lastSuccess,
        nextRefreshAt: date(state['nextRefreshAt']),
      );
    }

    Future<void> lane() async {
      while (nextIndex < orderedSources.length) {
        final source = orderedSources[nextIndex++];
        await sourceWork(source);
      }
    }

    try {
      await Future.wait(List.generate(3, (_) => lane()));
      valid();
    } finally {
      timer.cancel();
    }
    final unique = <String, LiveContentItem>{};
    for (final source in approved) {
      for (final item in rows[source.source.id] ?? const <LiveContentItem>[]) {
        if (!revoked.contains(item.id) &&
            !revokedSources.contains(item.sourceId)) {
          final existing = unique[item.id];
          if (existing == null ||
              (existing.canonicalUrl == item.canonicalUrl &&
                  eligibility.imageFor(existing) == null &&
                  eligibility.imageFor(item) != null)) {
            // Keep the complete reviewed source record. A duplicate title-only
            // feed must not hide an independently approved story photograph.
            unique[item.id] = item;
          }
        }
      }
    }
    var items = balancedLiveItems(unique.values, registry.sources.keys);
    items = items.take(300).toList();
    if (revoked.length > 5000) {
      revokedSources.addAll(approved.map((s) => s.source.id));
      revoked.clear();
      items = [];
      for (final state in states.values) {
        (state as Map)['revoked'] = true;
      }
    }
    LiveSnapshot build() => LiveSnapshot(
      snapshotId: rssDigest(
        '${now.toIso8601String()}:${items.map((i) => i.id).join(',')}',
      ),
      generatedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
      sources: approved.map((s) => health[s.source.id]!).toList(),
      items: List.of(items),
      revokedItemIds: revoked,
      revokedSourceIds: revokedSources,
      staleSourceIds: health.values
          .where((s) => s.status != 'fresh')
          .map((s) => s.id)
          .toSet(),
      rejectedItems: rejected,
    );
    var snapshot = build();
    while (utf8.encode(jsonEncode(snapshot.toJson())).length > 450 * 1024 &&
        items.isNotEmpty) {
      items.removeLast();
      snapshot = build();
    }
    final state = <String, dynamic>{
      'schemaVersion': 1,
      'sources': states,
      'scheduler': {
        'schemaVersion': 1,
        'cursorAfter': cursorAfter,
        'lastBatchAt': now.toIso8601String(),
        'configuredEndpoints': groups.length,
        'dueEndpoints': dueEndpoints.length,
        'attemptedEndpoints': attempted.length,
        'deferredSources': deferredSources.length,
        'maximumEndpointAttempts': maximumEndpointAttempts,
      },
    };
    if (utf8.encode(jsonEncode(state)).length > 450 * 1024) {
      throw const RssFailure('refresh-state-limit');
    }
    return FeedResponse(
      snapshot: snapshot,
      publisherImagesVerified: true,
      providerState: state,
      warning: anyFailure
          ? 'Some publishers could not be refreshed. Available and cached articles are shown.'
          : null,
    );
  }
}

Duration? rssRefreshDelay(
  Map<String, String> headers,
  DateTime now,
  int floor,
) {
  var seconds = floor;
  for (final match in RegExp(
    r'(?:^|,)\s*(?:s-maxage|max-age)\s*=\s*"?(\d+)',
    caseSensitive: false,
  ).allMatches(headers['cache-control'] ?? '')) {
    final n = int.tryParse(match[1]!);
    if (n == null || n > 31622400) return null;
    if (n > seconds) seconds = n;
  }
  final retry = headers['retry-after'];
  if (retry != null) {
    final value = retry.trim();
    final number = int.tryParse(value);
    if (RegExp(r'^\d+$').hasMatch(value) && number == null) return null;
    final date = rssDate(retry, now.add(const Duration(days: 366)));
    final n = number ?? (date?.difference(now).inSeconds ?? 0);
    if (n > 31622400) return null;
    if (n > seconds) seconds = n;
  }
  return Duration(seconds: seconds);
}
