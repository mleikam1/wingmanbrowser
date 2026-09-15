import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'image_headers.dart';
import 'eligibility.dart';
import 'models.dart';
import 'rss_provider.dart' show rssRefreshDelay;
import 'rss_transport.dart';
import 'rss_transport_native.dart'
    if (dart.library.js_interop) 'rss_transport_web.dart'
    as platform;

/// Reject foreign formats and oversized/animated images before returning bytes
/// to a widget. ImageDescriptor inspects dimensions before pixel decoding.
Future<void> validateArticleImage(
  Uint8List bytes,
  LiveArticleImage image,
  String type, {
  int maximumWidth = 2048,
  int maximumHeight = 2048,
}) async {
  if (bytes.isEmpty || bytes.length > 1024 * 1024) {
    throw const RssFailure('image-size');
  }
  late final ArticleImageDimensions header;
  try {
    header = articleImageDimensions(bytes, type);
  } on FormatException {
    throw const RssFailure('image-format-or-dimensions');
  }
  bool dimensionsMatch(int width, int height) =>
      width == header.width &&
      height == header.height &&
      (image.width == 0 || width == image.width) &&
      (image.height == 0 || height == image.height) &&
      width >= 16 &&
      height >= 16 &&
      width <= maximumWidth &&
      height <= maximumHeight &&
      width * height <= 4 * 1024 * 1024;
  if (!dimensionsMatch(header.width, header.height)) {
    throw const RssFailure('image-dimensions');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // Flutter web's encoded ImageDescriptor does not expose dimensions.
    // Header inspection bounds allocation there; native retains its descriptor
    // check, and every platform verifies the actual decoded frame below.
    if (!kIsWeb && !dimensionsMatch(descriptor.width, descriptor.height)) {
      throw const RssFailure('image-dimensions');
    }
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount != 1) throw const RssFailure('animated-image');
    final frame = await codec.getNextFrame();
    try {
      if (!dimensionsMatch(frame.image.width, frame.image.height)) {
        throw const RssFailure('decoded-image-dimensions');
      }
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

class _ImageEntry {
  const _ImageEntry(this.bytes, this.expires);
  final Uint8List bytes;
  final DateTime expires;
}

/// Normal-session memory only. Work is chosen from the common snapshot, never
/// from selected topics, saved items, scrolling, private pages or browser data.
class ArticleImageLoader {
  ArticleImageLoader({
    required this.eligibility,
    ArticleImageTransport? transport,
    DateTime Function()? clock,
    Future<void> Function(Uint8List, LiveArticleImage, String)? validator,
  }) : _transport = transport ?? platform.createArticleImageTransport(),
       _clock = clock ?? DateTime.now,
       _validator =
           validator ??
           ((bytes, image, type) => validateArticleImage(
             bytes,
             image,
             type,
             maximumWidth:
                 eligibility
                     .registry
                     .sources[image.sourceId]
                     ?.imagePolicy
                     ?.maximumWidth ??
                 0,
             maximumHeight:
                 eligibility
                     .registry
                     .sources[image.sourceId]
                     ?.imagePolicy
                     ?.maximumHeight ??
                 0,
           ));
  final LiveContentEligibility eligibility;
  final ArticleImageTransport _transport;
  final DateTime Function() _clock;
  final Future<void> Function(Uint8List, LiveArticleImage, String) _validator;
  final Map<String, _ImageEntry> _cache = {};
  // HTTP no-store/no-cache responses may be displayed freshly, but are never
  // reusable cache entries. Drop their active buffers at every presentation or
  // refresh boundary. The UI must also evict its decoded MemoryImage on detach.
  final Map<String, _ImageEntry> _transient = {};
  final Map<String, DateTime> _retry = {};
  int _epoch = 0;
  static const maximumBatch = 96, maximumCacheBytes = 8 * 1024 * 1024;

  Uint8List? bytesFor(LiveContentItem item) {
    final image = eligibility.imageFor(item);
    if (image == null) return null;
    final cached = _transient[image.cacheKey] ?? _cache[image.cacheKey];
    return cached != null && _clock().toUtc().isBefore(cached.expires)
        ? cached.bytes
        : null;
  }

  bool isTransientFor(LiveContentItem item) =>
      _transient.containsKey(item.image?.cacheKey);

  void cancel({bool clear = false}) {
    _epoch++;
    _transport.cancel();
    _transient.clear();
    if (clear) {
      _cache.clear();
      _retry.clear();
    }
  }

  Future<void> load(
    Iterable<LiveContentItem> commonItems, {
    required void Function() onChanged,
  }) async {
    cancel();
    final epoch = _epoch, now = _clock().toUtc();
    final groups = <String, List<LiveContentItem>>{};
    for (final item in commonItems) {
      if (eligibility.imageFor(item) != null &&
          eligibility.accepts(item, now: now)) {
        (groups[item.sourceId] ??= []).add(item);
      }
    }
    for (final list in groups.values) {
      list.sort(
        (a, b) => (b.publishedAt ?? b.fetchedAt).compareTo(
          a.publishedAt ?? a.fetchedAt,
        ),
      );
    }
    final queue = <LiveContentItem>[];
    // Fixed source interleave avoids one prolific publisher using the budget.
    for (var index = 0; queue.length < maximumBatch; index++) {
      var added = false;
      for (final id in eligibility.registry.sources.keys) {
        final rows = groups[id];
        if (rows != null &&
            index < rows.length &&
            queue.length < maximumBatch) {
          queue.add(rows[index]);
          added = true;
        }
      }
      if (!added) break;
    }
    final keys = queue.map((i) => i.image!.cacheKey).toSet();
    _cache.removeWhere(
      (key, value) => !keys.contains(key) || !now.isBefore(value.expires),
    );
    _retry.removeWhere((key, _) => !keys.contains(key));
    var index = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    final timer = Timer(const Duration(seconds: 30), () {
      if (_epoch == epoch) cancel();
    });
    bool valid() => epoch == _epoch && DateTime.now().isBefore(deadline);
    Future<void> lane() async {
      while (valid() && index < queue.length) {
        final item = queue[index++], image = queue[index - 1].image!;
        if (bytesFor(item) != null ||
            now.isBefore(_retry[image.cacheKey] ?? now)) {
          continue;
        }
        try {
          final response = await _transport
              .fetchImage(
                image,
                eligibility.registry.sources[item.sourceId]!,
                canOpenDestination: eligibility.canOpenDestination,
              )
              .timeout(deadline.difference(DateTime.now()));
          if (!valid()) return;
          if (response.status != 200) throw const RssFailure('image-status');
          final cache = response.headers['cache-control'] ?? '';
          var transient =
              RegExp(
                r'(?:^|,)\s*(?:no-store|private|no-cache)(?:\s*(?:,|=|$))',
                caseSensitive: false,
              ).hasMatch(cache) ||
              (response.headers['pragma'] ?? '').toLowerCase().contains(
                'no-cache',
              );
          var ttl = const Duration(minutes: 30);
          final ages = RegExp(
            r'(?:^|,)\s*max-age\s*=\s*"?(\d+)',
            caseSensitive: false,
          ).allMatches(cache);
          if (ages.isNotEmpty) {
            final seconds = ages
                .map((m) => int.tryParse(m[1]!) ?? 0)
                .reduce((a, b) => a < b ? a : b);
            ttl = Duration(seconds: seconds.clamp(0, 604800));
          }
          final ageText = response.headers['age'] ?? '0';
          if (!RegExp(r'^[0-9]{1,10}$').hasMatch(ageText)) {
            throw const RssFailure('invalid-image-cache-age');
          }
          final age = int.parse(ageText);
          // A cached response already spent part of its lifetime upstream.
          // Never turn an expired positive max-age into a fresh transient image.
          if ((ttl > Duration.zero && age >= ttl.inSeconds) ||
              (ttl <= Duration.zero && age > 0)) {
            throw const RssFailure('stale-image-response');
          }
          if (ttl <= Duration.zero) {
            // Fresh max-age=0/no-store bytes may be displayed for this active
            // presentation only, preserving the NewsUSA transient contract.
            transient = true;
            ttl = const Duration(minutes: 30);
          } else {
            ttl -= Duration(seconds: age);
          }
          final type = (response.headers['content-type'] ?? '')
              .split(';')
              .first
              .trim()
              .toLowerCase();
          await _validator(response.body, image, type);
          if (!valid() || eligibility.imageFor(item) == null) return;
          final total = [
            ..._cache.values,
            ..._transient.values,
          ].fold<int>(0, (n, e) => n + e.bytes.length);
          if (total + response.body.length > maximumCacheBytes) continue;
          final expires = now.add(ttl).isBefore(item.expiresAt)
              ? now.add(ttl)
              : item.expiresAt;
          (transient ? _transient : _cache)[image.cacheKey] = _ImageEntry(
            Uint8List.fromList(response.body).asUnmodifiableView(),
            expires,
          );
          _retry.remove(image.cacheKey);
          onChanged();
        } catch (error) {
          if (!valid()) return;
          if (error is RssFailure) {
            final delay = rssRefreshDelay(error.headers, now, 1800);
            _retry[image.cacheKey] = now.add(
              delay ?? const Duration(days: 366),
            );
          }
        }
      }
    }

    try {
      await Future.wait([lane(), lane()]);
    } finally {
      timer.cancel();
    }
  }
}
