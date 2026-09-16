import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'models.dart';
import 'rss_transport.dart';

RssFeedTransport createRssTransport() => NativeRssFeedTransport();
ArticleImageTransport createArticleImageTransport() => NativeRssFeedTransport();

typedef RssResolver = Future<List<InternetAddress>> Function(String host);

/// Reject the entire DNS answer set, including mapped and translation ranges.
bool isPublicRssAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    if (b.take(10).every((x) => x == 0) && b[10] == 255 && b[11] == 255) {
      return isPublicRssAddress(InternetAddress.fromRawAddress(b.sublist(12)));
    }
    // Public native IPv6 unicast only; reject special-use 2001::/23,
    // 2002::/16, documentation 2001:db8::/32 and 3fff::/20.
    if (b[0] & 0xe0 != 0x20 ||
        (b[0] == 0x20 && b[1] == 1 && b[2] < 2) ||
        (b[0] == 0x20 && b[1] == 1 && b[2] == 0x0d && b[3] == 0xb8) ||
        (b[0] == 0x20 && b[1] == 2) ||
        (b[0] == 0x3f && b[1] == 0xff && b[2] < 16)) {
      return false;
    }
    return true;
  }
  if (b.length != 4) return false;
  return !(b[0] == 0 ||
      b[0] == 10 ||
      b[0] == 127 ||
      b[0] >= 224 ||
      (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
      (b[0] == 169 && b[1] == 254) ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 &&
          (b[1] == 168 ||
              (b[1] == 0 && (b[2] == 0 || b[2] == 2)) ||
              (b[1] == 88 && b[2] == 99))) ||
      (b[0] == 198 &&
          (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
      (b[0] == 203 && b[1] == 0 && b[2] == 113));
}

class NativeRssFeedTransport
    implements RssFeedTransport, ArticleImageTransport {
  NativeRssFeedTransport({RssResolver? resolver})
    : _resolver = resolver ?? InternetAddress.lookup;
  final RssResolver _resolver;
  final Set<HttpClient> _clients = {};
  final Set<void Function()> _cancelConnections = {};
  int _epoch = 0;
  // DNS itself is an OS future. A timed-out lookup keeps its slot until actual
  // completion, preventing cancelled/retried refreshes accumulating resolvers.
  static int _resolving = 0;
  Future<List<InternetAddress>> _resolve(String host) async {
    if (_resolving >= 4) throw const RssFailure('dns-capacity');
    _resolving++;
    final lookup = Future<List<InternetAddress>>.sync(() => _resolver(host));
    return lookup
        .whenComplete(() => _resolving--)
        .timeout(const Duration(seconds: 4));
  }

  /// Fixed configured service resource, using the same public DNS pinning as
  /// publisher traffic. A redirect cannot change this reviewed service origin.
  Future<RssFetchResponse> fetchSharedResource(
    Uri endpoint,
    Map<String, String> validators,
  ) => _fetch(
    initialUri: endpoint,
    checkUri: (uri) {
      if (uri != endpoint ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.hasPort && uri.port != 443) ||
          !(uri.path == '/v1/snapshot.json' ||
              RegExp(r'^/v1/media/[a-f0-9]{64}$').hasMatch(uri.path))) {
        throw const RssFailure('unapproved-shared-resource');
      }
      return uri;
    },
    validators: validators,
    acceptedTypes: const {
      'application/json',
      'image/jpeg',
      'image/png',
      'image/webp',
    },
    accept: 'application/json, image/jpeg, image/png, image/webp',
    maximumBytes: 2 * 1024 * 1024,
  );

  @override
  Future<RssFetchResponse> fetch(
    ApprovedLiveSource source,
    Map<String, String> validators,
  ) => _fetch(
    initialUri: source.feedUri ?? (throw const RssFailure('missing-feed')),
    checkUri: (uri) => checkedRssUri(uri, source),
    validators: validators,
    acceptedTypes: const {
      'application/rss+xml',
      'application/atom+xml',
      'application/xml',
      'text/xml',
    },
    accept:
        'application/rss+xml, application/atom+xml, application/xml, text/xml',
    maximumBytes: rssMaximumWireBytes,
    maximumDecodedBytes: rssMaximumXmlBytes,
  );

  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) => _fetch(
    initialUri: image.url,
    checkUri: (uri) {
      if (!canOpenDestination(uri)) {
        throw const RssFailure('image-destination-denied');
      }
      return checkedImageUri(uri, source);
    },
    validators: const {},
    acceptedTypes: const {'image/jpeg', 'image/png', 'image/webp'},
    accept: 'image/jpeg, image/png, image/webp',
    maximumBytes: 1024 * 1024,
  );

  Future<RssFetchResponse> _fetch({
    required Uri initialUri,
    required Uri Function(Uri) checkUri,
    required Map<String, String> validators,
    required Set<String> acceptedTypes,
    required String accept,
    required int maximumBytes,
    int? maximumDecodedBytes,
  }) async {
    final generation = _epoch;
    final deadline = DateTime.now().add(rssDeadline);
    void valid() {
      if (generation != _epoch) throw const RssFailure('cancelled');
      if (!DateTime.now().isBefore(deadline)) throw const RssFailure('timeout');
    }

    var uri = checkUri(initialUri);
    var conditional = Map<String, String>.of(validators);
    HttpClient? active;
    final localStops = <void Function()>{};
    final timer = Timer(rssDeadline, () {
      for (final stop in localStops.toList()) {
        stop();
      }
      active?.close(force: true);
    });
    try {
      for (var hop = 0; hop <= 3; hop++) {
        valid();
        if (!DateTime.now().isBefore(deadline)) {
          throw const RssFailure('timeout');
        }
        List<InternetAddress> addresses;
        try {
          addresses = await _resolve(uri.host);
        } on SocketException {
          valid();
          throw const RssFailure('dns-failed');
        } on TimeoutException {
          valid();
          throw const RssFailure('dns-timeout');
        }
        valid();
        if (addresses.isEmpty || addresses.any((a) => !isPublicRssAddress(a))) {
          throw const RssFailure('non-public-dns');
        }
        addresses.sort(
          (a, b) => a.type == InternetAddressType.IPv4
              ? (b.type == a.type ? 0 : -1)
              : 1,
        );
        final address = addresses.first, origin = uri;
        final client = HttpClient()
          ..autoUncompress = false
          ..findProxy = ((_) => 'DIRECT')
          ..connectionTimeout = const Duration(seconds: 8);
        active = client;
        _clients.add(client);
        client.connectionFactory = (url, proxyHost, proxyPort) async {
          valid();
          if (url.host != origin.host ||
              proxyHost != null ||
              proxyPort != null) {
            throw const RssFailure('connection-origin');
          }
          final tcp = await Socket.startConnect(address, 443);
          Socket? connected;
          final completion = Completer<Socket>();
          void stop() {
            tcp.cancel();
            try {
              connected?.destroy();
            } catch (_) {}
            if (!completion.isCompleted) {
              completion.completeError(const RssFailure('cancelled'));
            }
          }

          _cancelConnections.add(stop);
          localStops.add(stop);
          unawaited(() async {
            try {
              connected = await tcp.socket;
              valid();
              final tls = await SecureSocket.secure(
                connected!,
                host: origin.host,
              );
              connected = tls;
              valid();
              if (completion.isCompleted) {
                tls.destroy();
                return;
              }
              completion.complete(tls);
            } catch (error, stack) {
              try {
                connected?.destroy();
              } catch (_) {}
              if (!completion.isCompleted) {
                completion.completeError(error, stack);
              }
            } finally {
              _cancelConnections.remove(stop);
              localStops.remove(stop);
            }
          }());
          if (generation != _epoch) stop();
          return ConnectionTask.fromSocket(completion.future, stop);
        };
        try {
          final request = await client.getUrl(origin);
          valid();
          request.followRedirects = false;
          request.persistentConnection = false;
          request.headers.set('Accept', accept);
          request.headers.set('Accept-Encoding', 'gzip, deflate, identity');
          request.headers.set(
            'User-Agent',
            'Wingman/0.13 (public editorial feed reader)',
          );
          for (final entry in conditional.entries) {
            if ({'If-None-Match', 'If-Modified-Since'}.contains(entry.key) &&
                entry.value.length <= 512 &&
                !RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value)) {
              request.headers.set(entry.key, entry.value);
            }
          }
          final response = await request.close();
          valid();
          var headerBytes = 0;
          final headers = <String, String>{};
          response.headers.forEach((key, values) {
            headerBytes +=
                key.length + values.fold<int>(0, (n, s) => n + s.length);
            final name = key.toLowerCase();
            if (name == 'cache-control') {
              // Cache-Control is a list field: dropping repeated values could
              // accidentally discard a publisher's no-store directive.
              headers[name] = values.join(',');
            } else if (values.length == 1) {
              headers[name] = values.single;
            } else if (name == 'retry-after') {
              throw const RssFailure(
                'ambiguous-retry-after',
                headers: {'retry-after': '31622401'},
              );
            } else if ({
              'content-type',
              'content-encoding',
              'content-length',
              'location',
            }.contains(name)) {
              throw const RssFailure('ambiguous-response-header');
            }
          });
          if (headerBytes > 32768) throw const RssFailure('headers-too-large');
          if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
            if (hop == 3 || headers['location'] == null) {
              throw const RssFailure('redirect-limit');
            }
            uri = checkUri(origin.resolve(headers['location']!));
            conditional = {};
            continue;
          }
          if (response.statusCode == 304) {
            return RssFetchResponse(304, Uint8List(0), headers);
          }
          if (response.statusCode != 200) {
            throw RssFailure(
              'http-${response.statusCode}',
              headers: headers,
              status: response.statusCode,
            );
          }
          final type = (headers['content-type'] ?? '')
              .split(';')
              .first
              .trim()
              .toLowerCase();
          if (!acceptedTypes.contains(type)) {
            throw RssFailure(
              'invalid-content-type',
              headers: headers,
              status: response.statusCode,
            );
          }
          if (response.contentLength > maximumBytes) {
            throw RssFailure(
              'body-too-large',
              headers: headers,
              status: response.statusCode,
            );
          }
          Uint8List bytes;
          try {
            bytes = await readBoundedRssBody(
              response,
              encoding: headers['content-encoding'] ?? '',
              maximumWireBytes: maximumBytes,
              maximumDecodedBytes: maximumDecodedBytes ?? maximumBytes,
              validateDeadline: valid,
            );
          } on RssFailure catch (error) {
            throw RssFailure(
              error.code,
              headers: {...headers, ...error.headers},
              status: response.statusCode,
            );
          }
          valid();
          return RssFetchResponse(200, bytes, headers);
        } finally {
          client.close(force: true);
          _clients.remove(client);
          if (identical(active, client)) active = null;
        }
      }
      throw const RssFailure('redirect-limit');
    } on RssFailure {
      rethrow;
    } catch (error) {
      valid();
      if (error is TimeoutException) throw const RssFailure('timeout');
      if (error is HandshakeException) throw const RssFailure('tls-failed');
      throw const RssFailure('connection-failed');
    } finally {
      timer.cancel();
      active?.close(force: true);
    }
  }

  @override
  void cancel() {
    _epoch++;
    for (final stop in _cancelConnections.toList()) {
      stop();
    }
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

/// Standard HTTP compression is decoded in a streaming pipeline with separate
/// wire/output limits. Splitting compressed input bounds work before every
/// deadline/cancellation check; no full compressed or expanded copy is kept.
Future<Uint8List> readBoundedRssBody(
  Stream<List<int>> input, {
  required String encoding,
  required int maximumWireBytes,
  required int maximumDecodedBytes,
  required void Function() validateDeadline,
}) async {
  final normalized = encoding.trim().toLowerCase();
  if (!{'', 'identity', 'gzip', 'deflate'}.contains(normalized)) {
    throw const RssFailure('unsupported-encoding');
  }
  var wireBytes = 0;
  Stream<List<int>> boundedWire() async* {
    await for (final chunk in input) {
      validateDeadline();
      wireBytes += chunk.length;
      if (wireBytes > maximumWireBytes) {
        throw const RssFailure('body-too-large');
      }
      for (var start = 0; start < chunk.length; start += 1024) {
        validateDeadline();
        final end = start + 1024 < chunk.length ? start + 1024 : chunk.length;
        yield chunk.sublist(start, end);
      }
    }
  }

  Stream<List<int>> decoded = boundedWire();
  if (normalized == 'gzip' || normalized == 'deflate') {
    decoded = decoded.transform(ZLibDecoder(gzip: normalized == 'gzip'));
  }
  final output = BytesBuilder(copy: false);
  try {
    await for (final chunk in decoded) {
      validateDeadline();
      if (output.length + chunk.length > maximumDecodedBytes) {
        throw const RssFailure('decoded-body-too-large');
      }
      output.add(chunk);
    }
    validateDeadline();
    return output.takeBytes();
  } on RssFailure {
    rethrow;
  } on FormatException {
    throw const RssFailure('invalid-compression');
  }
}
