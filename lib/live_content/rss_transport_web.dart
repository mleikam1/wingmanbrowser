import 'models.dart';
import 'rss_transport.dart';

/// Browser RSS needs publisher CORS plus a separately reviewed transport model.
/// Never bypass CORS through an arbitrary public proxy or hidden page renderer.
RssFeedTransport createRssTransport() => _UnavailableWebRssTransport();
ArticleImageTransport createArticleImageTransport() =>
    _UnavailableWebImageTransport();

class _UnavailableWebImageTransport implements ArticleImageTransport {
  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) async => throw const RssFailure('native-images-only');
  @override
  void cancel() {}
}

class _UnavailableWebRssTransport implements RssFeedTransport {
  @override
  Future<RssFetchResponse> fetch(
    ApprovedLiveSource source,
    Map<String, String> validators,
  ) async => throw const RssFailure('native-feed-only');
  @override
  void cancel() {}
}
