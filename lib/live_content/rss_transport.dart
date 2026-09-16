import 'dart:typed_data';
import 'models.dart';
import 'provider.dart';

const rssMaximumWireBytes = 1024 * 1024;
const rssMaximumXmlBytes = 2 * 1024 * 1024;
const rssDeadline = Duration(seconds: 25);

class RssFetchResponse {
  const RssFetchResponse(this.status, this.body, this.headers);
  final int status;
  final Uint8List body;
  final Map<String, String> headers;
}

class RssFailure extends FeedFailure {
  const RssFailure(this.code, {this.headers = const {}, this.status})
    : super('A publisher could not be refreshed.');
  final String code;
  final Map<String, String> headers;
  final int? status;
}

abstract interface class RssFeedTransport {
  Future<RssFetchResponse> fetch(
    ApprovedLiveSource source,
    Map<String, String> validators,
  );
  void cancel();
}

abstract interface class ArticleImageTransport {
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  });
  void cancel();
}

Uri checkedImageUri(Uri uri, ApprovedLiveSource source) {
  if (!source.enabled ||
      !source.source.rights.images ||
      !(source.imagePolicy?.acceptsUri(uri) ?? false)) {
    throw const RssFailure('unapproved-image-address');
  }
  return uri;
}

Uri checkedRssUri(Uri uri, ApprovedLiveSource source) {
  final text = uri.toString();
  if (text.length > 4096 ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(text) ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.hasPort && uri.port != 443) ||
      uri.host.endsWith('.') ||
      !source.feedRedirectHosts.contains(uri.host) ||
      !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(uri.host)) {
    throw const RssFailure('unapproved-feed-address');
  }
  return uri;
}
