import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/eligibility.dart';
import 'package:wingman_browser/live_content/image_loader.dart';
import 'package:wingman_browser/live_content/models.dart';
import 'package:wingman_browser/live_content/rss_provider.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';
import 'package:wingman_browser/policy/consumer_protection_policy.dart';

// Explicit opt-in only. This exercises the same DNS-pinned native transport
// without Flutter's widget-test HTTP mock. No cookies, UI or user data is used.
class _ActualHttp extends HttpOverrides {}

// Observe the production transport's result without fetching a second copy or
// bypassing the loader's real MIME, codec, dimensions and cache checks.
class _RecordedImages implements ArticleImageTransport {
  final _native = NativeRssFeedTransport();
  final responses = <String, Map<String, Object?>>{};

  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) async {
    try {
      final response = await _native.fetchImage(
        image,
        source,
        canOpenDestination: canOpenDestination,
      );
      responses[image.cacheKey] = {
        'status': response.status,
        'mimeType': (response.headers['content-type'] ?? '')
            .split(';')
            .first
            .trim()
            .toLowerCase(),
        'receivedBytes': response.body.length,
        'cacheControl': response.headers['cache-control'],
        'age': response.headers['age'],
      };
      return response;
    } catch (error) {
      responses[image.cacheKey] = {
        'error': error is RssFailure ? error.code : 'transport-failure',
      };
      rethrow;
    }
  }

  @override
  void cancel() => _native.cancel();
}

Map<String, Object> _counts(Iterable<LiveContentItem> items) {
  final sources = <String, int>{}, topics = <String, int>{};
  final qualifiers = <String, int>{};
  var count = 0, sponsored = 0;
  for (final item in items) {
    count++;
    if (item.syndicatedArticle != null) sponsored++;
    sources.update(item.sourceId, (n) => n + 1, ifAbsent: () => 1);
    for (final topic in item.topics) {
      topics.update(topic, (n) => n + 1, ifAbsent: () => 1);
    }
    final qualifier = item.image?.displayLabel ?? 'No dynamic publisher image';
    qualifiers.update(qualifier, (n) => n + 1, ifAbsent: () => 1);
  }
  return {
    'items': count,
    'perSource': sources,
    'perCategory': topics,
    'photoQualifiers': qualifiers,
    'sponsored': sponsored,
  };
}

Future<Map<String, Object?>> _captureImages(
  LiveSnapshot snapshot,
  LiveContentEligibility eligibility, {
  bool newsUsaOnly = false,
}) async {
  final directory = Directory('work/content-refresh/images')
    ..createSync(recursive: true);
  final sourceRights = {
    for (final source in snapshot.sources) source.id: source.rights.images,
  };
  final candidates = snapshot.items
      .where(
        (item) =>
            (!newsUsaOnly || item.sourceId == 'newsusa-features') &&
            sourceRights[item.sourceId] == true &&
            !snapshot.revokedItemIds.contains(item.id) &&
            !snapshot.revokedSourceIds.contains(item.sourceId) &&
            eligibility.imageFor(item) != null,
      )
      .toList();
  final transport = _RecordedImages();
  final loader = ArticleImageLoader(
    eligibility: eligibility,
    transport: transport,
  );
  final stopwatch = Stopwatch()..start();
  final rows = <Map<String, Object?>>[], captured = <LiveContentItem>[];
  final validated = <LiveContentItem>[];
  var totalBytes = 0, retainedBytes = 0;
  try {
    await loader.load(candidates, onChanged: () {});
    stopwatch.stop();
    for (final item in candidates) {
      final image = eligibility.imageFor(item)!;
      final response = transport.responses[image.cacheKey];
      final bytes = loader.bytesFor(item);
      final transient = loader.isTransientFor(item);
      final storageProhibited = RegExp(
        r'(?:^|,)\s*(?:no-store|private|no-cache)(?:\s*(?:,|=|$))',
        caseSensitive: false,
      ).hasMatch(response?['cacheControl'] as String? ?? '');
      final row = <String, Object?>{
        'itemId': item.id,
        'sourceId': item.sourceId,
        'articleUrl': item.canonicalUrl.toString(),
        'url': image.url.toString(),
        'caption': image.caption,
        'credit': image.credit,
        'licenseUrl': image.licenseUrl.toString(),
        'licenseLabel': image.licenseLabel,
        'basis': image.basis,
        'photoQualifier': image.displayLabel,
        'sponsored': item.syndicatedArticle != null,
        'topics': item.topics.toList()..sort(),
        'declaredWidth': image.width,
        'declaredHeight': image.height,
        'expiresAt': item.expiresAt.toIso8601String(),
        'captured': false,
        'validatedForDisplay': bytes != null,
        'transient': transient,
        'fixtureStorageProhibited': storageProhibited,
        'transport': response,
      };
      if (bytes != null) {
        final mime = response!['mimeType']! as String;
        final extension = {
          'image/jpeg': 'jpg',
          'image/png': 'png',
          'image/webp': 'webp',
        }[mime];
        expect(extension, isNotNull);
        expect(item.id, matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(bytes.length, inInclusiveRange(1, rssMaximumWireBytes));
        retainedBytes += bytes.length;
        validated.add(item);
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          row['width'] = descriptor.width;
          row['height'] = descriptor.height;
        } finally {
          descriptor.dispose();
          buffer.dispose();
        }
        row.addAll({
          'mimeType': mime,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        });
        if (!newsUsaOnly && !storageProhibited && !transient) {
          final file = File('${directory.path}/${item.id}.$extension');
          await file.writeAsBytes(bytes, flush: true);
          row['file'] = file.path;
          row['captured'] = true;
          totalBytes += bytes.length;
          captured.add(item);
        }
      }
      rows.add(row);
    }
    final currentFiles = rows
        .where((row) => row['captured'] == true)
        .map((row) => row['file']! as String)
        .toSet();
    // This directory contains generated public-image fixtures. Remove only old
    // probe files with this test's exact item-id naming, never other artifacts.
    for (final entry
        in newsUsaOnly ? <FileSystemEntity>[] : directory.listSync()) {
      if (entry is File &&
          RegExp(r'/[a-f0-9]{32}\.(?:jpg|png|webp)$').hasMatch(entry.path) &&
          !currentFiles.contains(entry.path)) {
        await entry.delete();
      }
    }
    final report = <String, Object?>{
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'snapshotGeneratedAt': snapshot.generatedAt.toIso8601String(),
      'snapshotFile': 'work/rss-direct/snapshot.json',
      'sourceFilter': newsUsaOnly ? 'newsusa-features' : null,
      'feedNetworkRequested': !newsUsaOnly,
      'imageElapsedMs': stopwatch.elapsedMilliseconds,
      'requests': transport.responses.length,
      'savedBytes': totalBytes,
      'snapshotCounts': _counts(snapshot.items),
      'approvedMetadataCounts': _counts(candidates),
      'capturedCounts': _counts(captured),
      'validatedForDisplayCounts': _counts(validated),
      'retainedResponseBytes': retainedBytes,
      'scope':
          'Direct RSS and production native image transport/loader. '
          'Publisher thumbnails may include diagrams, archives or illustrations; '
          'these counts do not classify their visual content or assert U.S.-only coverage. '
          'No larger rendition or article-page image scraping. Each candidate is '
          'fetched at most once per run; transient response bytes are not exported.',
      'images': rows.where((row) => row['captured'] == true).toList(),
      'transientImages': rows
          .where(
            (row) =>
                row['validatedForDisplay'] == true && row['transient'] == true,
          )
          .toList(),
      'unavailableImages': rows
          .where((row) => row['validatedForDisplay'] != true)
          .toList(),
    };
    final receiptPath =
        '${directory.parent.path}/${newsUsaOnly ? 'image-transient-receipt' : 'image-receipt'}.json';
    await File(receiptPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    expect(captured.length, lessThanOrEqualTo(ArticleImageLoader.maximumBatch));
    expect(totalBytes, lessThanOrEqualTo(ArticleImageLoader.maximumCacheBytes));
    expect(
      retainedBytes,
      lessThanOrEqualTo(ArticleImageLoader.maximumCacheBytes),
    );
    expect(candidates, isNotEmpty);
    expect(validated, isNotEmpty);
    if (newsUsaOnly) {
      expect(captured, isEmpty);
      expect(totalBytes, 0);
      expect(rows.every((row) => !row.containsKey('file')), isTrue);
    } else {
      expect(captured, isNotEmpty);
    }
    return {
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'approved': candidates.length,
      'captured': captured.length,
      'validatedForDisplay': validated.length,
      'savedBytes': totalBytes,
      'receipt': receiptPath,
    };
  } finally {
    loader.cancel(clear: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'approved native RSS and images produce bounded validated capture fixtures',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final registry = LiveSourceRegistry.fromJson(
        feedMap(
          jsonDecode(
            await File('assets/live_content/sources.json').readAsString(),
          ),
        ),
      );
      final policy = await ConsumerProtectionPolicy.verifyBytes(
        await File(ConsumerProtectionPolicy.assetPath).readAsBytes(),
      );
      expect(policy.isUsable, isTrue);
      final eligibility = LiveContentEligibility(
        registry: registry,
        canOpenDestination: (uri) => policy.assessNavigation(uri).isAllowed,
      );
      // A second, explicit mode diagnoses only NewsUSA image responses from the
      // already-verified public snapshot. It never refreshes feeds or exports
      // no-store image bytes, and leaves reusable capture fixtures untouched.
      if (const bool.fromEnvironment('WINGMAN_RSS_LIVE_IMAGE_ONLY')) {
        final snapshot = LiveSnapshot.fromJson(
          feedMap(
            jsonDecode(
              await File('work/rss-direct/snapshot.json').readAsString(),
            ),
          ),
        );
        final imageReport = await _captureImages(
          snapshot,
          eligibility,
          newsUsaOnly: true,
        );
        // ignore: avoid_print
        print(jsonEncode({'images': imageReport}));
        return;
      }
      final provider = RssFeedProvider(
        registry: registry,
        eligibility: eligibility,
        allowsEditorialText: eligibility.acceptsFeedText,
      );
      addTearDown(provider.cancel);
      final directory = Directory('work/rss-direct')
        ..createSync(recursive: true);
      final snapshotFile = File('${directory.path}/snapshot.json');
      final stateFile = File('${directory.path}/state.json');
      provider.restore(
        snapshot: await snapshotFile.exists()
            ? LiveSnapshot.fromJson(
                feedMap(jsonDecode(await snapshotFile.readAsString())),
              )
            : null,
        state: await stateFile.exists()
            ? feedMap(jsonDecode(await stateFile.readAsString()))
            : null,
      );
      final stopwatch = Stopwatch()..start();
      final response = await provider.fetch();
      stopwatch.stop();
      final snapshot = response.snapshot!;
      // Store the approved attempt's rate-limit checkpoint even on an outage.
      await stateFile.writeAsString(jsonEncode(response.providerState));
      await snapshotFile.writeAsString(jsonEncode(snapshot.toJson()));
      final topics = <String, int>{};
      for (final item in snapshot.items) {
        for (final topic in item.topics) {
          topics[topic] = (topics[topic] ?? 0) + 1;
        }
      }
      final report = {
        'generatedAt': snapshot.generatedAt.toIso8601String(),
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'snapshotBytes': await snapshotFile.length(),
        'itemCount': snapshot.items.length,
        'rejectedCount': snapshot.rejectedItems,
        'topics': topics,
        'sources': snapshot.sources
            .map(
              (source) => {
                'id': source.id,
                'status': source.status,
                'itemCount': snapshot.items
                    .where((item) => item.sourceId == source.id)
                    .length,
                'lastSuccessAt': source.lastSuccessAt?.toIso8601String(),
                'nextRefreshAt': source.nextRefreshAt?.toIso8601String(),
                'error':
                    (feedMap(response.providerState!['sources'])[source.id]
                        as Map)['error'],
              },
            )
            .toList(),
        'warning': response.warning,
      };
      await File(
        '${directory.path}/report.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      // Reporter output includes only counts/statuses, never raw feed content.
      // ignore: avoid_print
      print(jsonEncode(report));
      expect(snapshot.sources, hasLength(registry.sources.length));
      expect(snapshot.items, isNotEmpty);
      expect(snapshot.items.length, lessThanOrEqualTo(300));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 50)));
      expect(
        snapshot.items.every(
          (item) => eligibility.accepts(item, now: DateTime.now().toUtc()),
        ),
        isTrue,
      );
      expect(response.publisherImagesVerified, isTrue);
      final imageReport = await _captureImages(snapshot, eligibility);
      // Public artifact paths and aggregate counts only; no raw article text.
      // ignore: avoid_print
      print(jsonEncode({'images': imageReport}));
    }, _ActualHttp()),
    skip: !const bool.fromEnvironment('WINGMAN_RSS_LIVE_VERIFY'),
    timeout: const Timeout(Duration(seconds: 110)),
  );
}
