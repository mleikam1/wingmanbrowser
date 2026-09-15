import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'rss_transport.dart';
import 'transport.dart';
import 'transport_native.dart'
    if (dart.library.js_interop) 'transport_web.dart'
    as platform;
export 'transport.dart' show FeedFailure, FeedTransport, FeedTransportResponse;

class FeedResponse {
  const FeedResponse({
    this.snapshot,
    this.notModified = false,
    this.etag,
    this.lastModified,
    this.providerState,
    this.warning,
    this.publisherImagesVerified = false,
  });
  final LiveSnapshot? snapshot;
  final bool notModified;
  final String? etag, lastModified;
  final Map<String, dynamic>? providerState;
  final String? warning;

  /// Set by the publisher parser or configured shared provider, never JSON.
  final bool publisherImagesVerified;
}

abstract interface class FeedProvider {
  Future<FeedResponse> fetch({String? etag, String? lastModified});
  void cancel();
}

abstract interface class ResumableFeedProvider {
  void restore({LiveSnapshot? snapshot, Map<String, dynamic>? state});
}

class SnapshotFeedProvider implements FeedProvider {
  SnapshotFeedProvider({
    required Uri endpoint,
    FeedTransport? transport,
    bool allowLocal = false,
  }) : endpoint = validateEndpoint(endpoint, allowLocal: allowLocal),
       _allowLocal = allowLocal,
       _transport = transport ?? platform.createFeedTransport();
  final Uri endpoint;
  final bool _allowLocal;
  final FeedTransport _transport;
  ArticleImageTransport createImageTransport({
    FeedTransport Function()? factory,
  }) => SnapshotImageTransport(
    endpoint,
    factory: factory,
    allowLocal: _allowLocal,
  );
  static FeedProvider? fromEnvironment() {
    const value = String.fromEnvironment('WINGMAN_FEED_URL');
    const allowLocal = bool.fromEnvironment('WINGMAN_FEED_ALLOW_LOCAL');
    if (value.isEmpty) return null;
    return SnapshotFeedProvider(
      endpoint: Uri.parse(value),
      allowLocal: allowLocal && !kReleaseMode,
    );
  }

  static Uri validateEndpoint(Uri uri, {bool allowLocal = false}) {
    final host = uri.host.toLowerCase();
    final loopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    final publicHost =
        RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(host) &&
        !RegExp(r'^[0-9.]+$').hasMatch(host) &&
        !host.endsWith('.local') &&
        !host.endsWith('.localhost');
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/v1/snapshot.json' ||
        (loopback
            ? !allowLocal || !{'http', 'https'}.contains(uri.scheme)
            : uri.scheme != 'https' ||
                  !publicHost ||
                  (uri.hasPort && uri.port != 443))) {
      throw const FormatException(
        'Headlines need an approved HTTPS snapshot endpoint.',
      );
    }
    return uri;
  }

  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (_safeHeader(etag)) headers['If-None-Match'] = etag!;
    if (_safeHeader(lastModified)) headers['If-Modified-Since'] = lastModified!;
    try {
      final response = await _transport.get(endpoint, headers);
      if (response.statusCode == 304) {
        return FeedResponse(
          notModified: true,
          etag: _header(response.headers['etag']) ?? etag,
          lastModified:
              _header(response.headers['last-modified']) ?? lastModified,
        );
      }
      if (response.statusCode != 200) {
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        throw FeedFailure(
          'Headlines could not be refreshed. Saved articles are still available.',
          retryAfter: seconds == null
              ? null
              : Duration(seconds: seconds.clamp(30, 86400)),
        );
      }
      final contentType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.bytes.length > maximumFeedBytes ||
          contentType != 'application/json') {
        throw const FeedFailure('The headline response could not be read.');
      }
      return FeedResponse(
        snapshot: LiveSnapshot.fromJson(
          feedMap(jsonDecode(utf8.decode(response.bytes))),
        ),
        etag: _header(response.headers['etag']),
        lastModified: _header(response.headers['last-modified']),
        publisherImagesVerified: true,
      );
    } on FeedFailure {
      rethrow;
    } catch (_) {
      throw const FeedFailure(
        'Headlines could not be refreshed. Saved articles are still available.',
      );
    }
  }

  bool _safeHeader(String? value) =>
      value != null &&
      value.length <= 512 &&
      !RegExp(r'[\r\n\x00]').hasMatch(value);
  String? _header(String? value) => _safeHeader(value) ? value : null;
  @override
  void cancel() => _transport.cancel();
}

/// Only immutable ingested media identities on the configured snapshot origin.
/// No publisher URL is sent as a parameter, and reads never trigger ingestion.
class SnapshotImageTransport implements ArticleImageTransport {
  SnapshotImageTransport(
    Uri endpoint, {
    FeedTransport Function()? factory,
    bool allowLocal = false,
  }) : endpoint = SnapshotFeedProvider.validateEndpoint(
         endpoint,
         allowLocal: allowLocal,
       ),
       _factory = factory ?? platform.createFeedTransport;
  final Uri endpoint;
  final FeedTransport Function() _factory;
  final Set<FeedTransport> _active = {};
  int _epoch = 0;

  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) async {
    checkedImageUri(image.url, source);
    if (image.sourceId != source.source.id ||
        !canOpenDestination(image.url) ||
        !canOpenDestination(image.articleUrl) ||
        _active.length >= 2) {
      throw const RssFailure('unapproved-shared-image');
    }
    final epoch = _epoch;
    final transport = _factory();
    _active.add(transport);
    try {
      final response = await transport.get(
        endpoint.replace(path: '/v1/media/${image.cacheKey}'),
        const {'Accept': 'image/jpeg, image/png, image/webp'},
      );
      if (epoch != _epoch || response.bytes.length > 1024 * 1024) {
        throw const RssFailure('shared-image-cancelled-or-size');
      }
      return RssFetchResponse(
        response.statusCode,
        response.bytes,
        response.headers,
      );
    } finally {
      _active.remove(transport);
      transport.cancel();
    }
  }

  @override
  void cancel() {
    _epoch++;
    for (final transport in _active.toList()) {
      transport.cancel();
    }
    _active.clear();
  }
}
