import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';

import 'live_content_test.dart' as fixtures;

LiveContentItem itemFor(
  StoryImage image, {
  String? sourceId,
  String? url,
  List<String> topics = const ['science'],
}) => LiveContentItem.fromJson({
  ...fixtures.itemJson(1),
  'sourceId': sourceId ?? image.sourceId,
  'canonicalUrl': url ?? image.articleUrl,
  'topics': topics,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'only exact reviewed source and article associations receive photos',
    () {
      for (final image in StoryImages.all) {
        expect(image.isArticleSpecific, isTrue);
        expect(StoryImages.forItem(itemFor(image)), same(image));
        expect(
          StoryImages.forItem(itemFor(image, sourceId: 'unreviewed-source')),
          isNull,
        );
        for (final suffix in ['?other=story', '/different-story']) {
          expect(
            StoryImages.forItem(
              itemFor(image, url: '${image.articleUrl}$suffix'),
            ),
            isNull,
          );
        }
        expect(
          StoryImages.forItem(itemFor(image, topics: ['food', 'headlines'])),
          same(image),
          reason: 'A chip or topic change must never replace the story photo.',
        );
      }
    },
  );

  test('all topics stay text-only without an individually approved photo', () {
    for (final topic in liveContentTopicOrder) {
      final item = LiveContentItem.fromJson({
        ...fixtures.itemJson(1, topic: topic),
        'image': {'url': 'https://unreviewed.example/image.jpg'},
        'imageUrl': 'https://unreviewed.example/image.jpg',
        'rights': {'titles': true, 'excerpts': true, 'images': true},
      });
      expect(item.imageUrl, isNull);
      expect(StoryImages.forItem(item), isNull, reason: topic);
    }
  });

  test('archive imagery retains its date and location context', () {
    expect(StoryImages.zebraMussels.caption, contains('Lake Huron, 1992'));
    expect(StoryImages.zebraMussels.alternativeText, contains('not the Utah'));
    expect(StoryImages.maunaiki.caption, contains('1919–1920'));
    expect(StoryImages.maunaiki.contain, isTrue);
    expect(StoryImages.krakatau.caption, contains('5 Sep 2026'));
    for (final image in StoryImages.all) {
      expect(image.caption, isNot(contains('Topic photo')));
    }
  });

  test(
    'packaged photos match reviewed provenance and decode within budget',
    () async {
      final manifest =
          jsonDecode(
                File(
                  'assets/story_images/article_manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final records = (manifest['images'] as List).cast<Map<String, dynamic>>();
      expect(records.length, StoryImages.all.length);
      expect(
        StoryImages.all.map((image) => image.asset).toSet().length,
        StoryImages.all.length,
      );
      var totalBytes = 0;
      for (final image in StoryImages.all) {
        final record = records.singleWhere(
          (entry) => entry['asset'] == image.asset,
        );
        expect(record['reviewed'], isTrue);
        expect(record['imageRole'], 'article-photo');
        expect(record['articleUrl'], image.articleUrl);
        expect(record['sourceId'], image.sourceId);
        expect(record['credit'], image.credit);
        expect(record['licenseUrl'], image.licenseUrl);
        expect(image.alternativeText, isNotEmpty);
        expect(image.rightsNote, isNotEmpty);
        expect(Uri.parse(image.sourceUrl).scheme, 'https');
        expect(Uri.parse(image.licenseUrl).scheme, 'https');
        final bytes = File(image.asset).readAsBytesSync();
        totalBytes += bytes.length;
        expect(bytes.length, record['bytes']);
        expect(sha256.convert(bytes).toString(), record['sha256']);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, record['width']);
        expect(frame.image.height, record['height']);
        expect(frame.image.width, lessThanOrEqualTo(2000));
        frame.image.dispose();
        codec.dispose();
      }
      expect(totalBytes, manifest['totalBytes']);
      expect(totalBytes, lessThan(4 * 1024 * 1024));
    },
  );
}
