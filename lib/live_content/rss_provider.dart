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
    var nextIndex = 0, anyFailure = false, rejected = 0;
    final end = DateTime.now().add(const Duration(seconds: 45));
    final timer = Timer(const Duration(seconds: 45), _transport.cancel);
    Future<void> sourceWork(ApprovedLiveSource source) async {
      valid();
      final id = source.source.id;
      final raw = priorStates[id];
      final prior = raw is Map ? feedMap(raw) : <String, dynamic>{};
      final state = Map<String, dynamic>.of(prior);
      states[id] = state;
      final old = (_snapshot?.items ?? const <LiveContentItem>[])
          .where(
            (i) =>
                i.sourceId == id &&
                i.expiresAt.isAfter(now) &&
                eligibility.accepts(i, now: now) &&
                (i.publishedAt == null ||
                    !i.publishedAt!.isBefore(
                      now.subtract(const Duration(days: 30)),
                    )),
          )
          .toList();
      rows[id] = old;
      DateTime? date(Object? value) {
        try {
          return value == null ? null : feedDate(value);
        } catch (_) {
          return null;
        }
      }

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
      } else if (!DateTime.now().isBefore(end)) {
        anyFailure = true;
        state['nextRefreshAt'] = now
            .add(Duration(seconds: source.minRefreshSeconds))
            .toIso8601String();
        state['error'] = 'refresh-deadline';
      } else {
        final configKey = rssDigest(
          jsonEncode({
            'version': 2,
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
            'retention': source.retentionSeconds,
          }),
        );
        final compatible = prior['configKey'] == configKey;
        final validators = <String, String>{};
        if (compatible && old.isNotEmpty) {
          for (final key in ['etag', 'lastModified']) {
            final value = prior[key];
            if (value is String &&
                value.length <= 512 &&
                !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
              validators[key == 'etag'
                      ? 'If-None-Match'
                      : 'If-Modified-Since'] =
                  value;
            }
          }
        }
        try {
          final response = await _transport
              .fetch(source, validators)
              .timeout(end.difference(DateTime.now()));
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
      while (nextIndex < approved.length) {
        final source = approved[nextIndex++];
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
          unique.putIfAbsent(item.id, () => item);
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
    final state = <String, dynamic>{'schemaVersion': 1, 'sources': states};
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
