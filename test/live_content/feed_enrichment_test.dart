import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/live_content/rss_parser.dart';

import 'branding_test.dart' show reviewedBranding;
import 'rss_provider_test.dart' as fixture;

Map<String, Object?> _reviewedSourceJson() {
  const article = 'https://publisher.example/news/one';
  return {
    'id': 'news',
    'name': 'Publisher',
    'homepageUrl': 'https://publisher.example/',
    'language': 'en',
    'topics': ['science', 'travel', 'environment'],
    'allowedArticleHosts': ['publisher.example'],
    'articlePathPrefixes': ['/news/'],
    'eligibilityScope': 'science-reporting',
    'enabled': true,
    'displayMode': 'publisher-link',
    'branding': reviewedBranding(),
    'rights': {'titles': true, 'excerpts': true, 'images': true},
    'imagePolicy': {
      'kind': 'reviewed-article-image',
      'allowedHosts': ['images.publisher.example'],
      'pathPrefixes': ['/article/'],
      'licenseUrl': 'https://publisher.example/rights',
      'licenseLabel': 'Reviewed source terms',
      'credit': 'Publisher',
      'maximumWidth': 800,
      'maximumHeight': 800,
      'reviewedArticles': {
        article: {
          'schemaVersion': 1,
          'url': 'https://images.publisher.example/article/one.jpg?w=640&h=480',
          'articleUrl': article,
          'articleId': rssDigest(article),
          'sourceId': 'news',
          'credit': 'Named illustrator / Publisher',
          'caption': 'Story illustration: a research diagram',
          'licenseUrl': 'https://publisher.example/rights/one',
          'licenseLabel': 'Reviewed illustration permission',
          'basis': 'reviewed-article-image',
          'width': 640,
          'height': 480,
        },
      },
    },
  };
}

void main() {
  test(
    'published story ages out at display time while a permitted saved link remains readable',
    () {
      final original = fixture.parse(fixture.rss()).items.single;
      final item = LiveContentItem.fromJson({
        ...original.toJson(),
        'publishedAt': fixture.now
            .subtract(const Duration(days: 29))
            .toIso8601String(),
      });
      final gate = fixture.gate([fixture.source()]);
      expect(gate.accepts(item, now: fixture.now), isTrue);
      expect(
        gate.accepts(item, now: fixture.now.add(const Duration(days: 2))),
        isFalse,
      );
      expect(
        gate.accepts(
          item,
          now: fixture.now.add(const Duration(days: 2)),
          saved: true,
        ),
        isTrue,
      );
    },
  );

  test(
    'sponsored travel feature keeps its complete reader contract without an excerpt',
    () {
      final source = ApprovedLiveSource.fromJson({
        ..._reviewedSourceJson(),
        'topics': ['travel', 'headlines'],
        'displayMode': 'sponsored-syndication',
        'rights': {
          'titles': true,
          'excerpts': false,
          'images': true,
          'licenseUrl': 'https://publisher.example/syndication',
        },
        'imagePolicy': {
          'kind': 'syndicated-article-photo',
          'allowedHosts': ['images.publisher.example'],
          'pathPrefixes': ['/article/'],
          'licenseUrl': 'https://publisher.example/syndication',
          'licenseLabel': 'Complete feature permission',
          'credit': 'Publisher',
          'maximumWidth': 2048,
          'maximumHeight': 2048,
        },
      });
      final item = fixture
          .parse(
            fixture.rss(
              title: 'Travel planning for your next vacation',
              desc:
                  '<p>By Fixture Author.</p><p>Complete travel feature with a <a href="https://publisher.example/news/source">publisher reference</a>.</p><p>Final disclosure stays here.</p>',
            ),
            approved: source,
          )
          .items
          .single;
      expect(item.topics, {'travel'});
      expect(item.excerpt, isNull);
      expect(item.excerptProvenance, isNull);
      expect(
        item.syndicatedArticle!.plainText,
        endsWith('Final disclosure stays here.'),
      );
      final gate = fixture.gate([source]);
      final sanitized = LiveContentItem.fromJson({
        ...item.toJson(),
        'excerpt': 'Unauthorized summary',
      });
      expect(sanitized.excerpt, isNull);
      expect(gate.accepts(sanitized, now: fixture.now), isTrue);
      expect(
        gate.accepts(
          LiveContentItem.fromJson({
            ...item.toJson(),
            'syndicatedArticle': null,
          }),
          now: fixture.now,
        ),
        isFalse,
      );
    },
  );
  test(
    '256 reviewed sources fit registry snapshots and preferences while item cap remains300',
    () {
      final configs = List.generate(
        256,
        (index) => {
          ..._reviewedSourceJson(),
          'id': 'source-$index',
          'imagePolicy': null,
        },
      );
      final registry = LiveSourceRegistry.fromJson({
        'schemaVersion': 1,
        'sources': configs,
      });
      expect(registry.sources, hasLength(256));
      final ids = registry.sources.keys.toSet();
      final prefs = LiveContentPreferences(
        selectedSourceIds: ids,
        hiddenSourceIds: ids,
      );
      expect(
        LiveContentPreferences.fromJson(prefs.toJson()).selectedSourceIds,
        hasLength(256),
      );
      final snapshot = <String, Object?>{
        'schemaVersion': 1,
        'snapshotId': 'many-sources',
        'generatedAt': fixture.now.toIso8601String(),
        'expiresAt': fixture.now
            .add(const Duration(minutes: 30))
            .toIso8601String(),
        'sources': registry.sources.values
            .map((source) => source.source.toJson())
            .toList(),
        'items': [],
        'revokedSourceIds': ids.toList(),
        'staleSourceIds': ids.toList(),
      };
      expect(LiveSnapshot.fromJson(snapshot).sources, hasLength(256));
      expect(
        () => LiveSourceRegistry.fromJson({
          'schemaVersion': 1,
          'sources': [
            ...configs,
            {...configs.first, 'id': 'source-257'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () =>
            LiveSnapshot.fromJson({...snapshot, 'items': List.filled(301, {})}),
        throwsFormatException,
      );
    },
  );
  test('snapshot URL duplicate detection preserves distinct publishers', () {
    final item = fixture.parse(fixture.rss()).items.single;
    final first = fixture.source().source;
    final second = LiveSource.fromJson({
      ...first.toJson(),
      'id': 'other-publisher',
      'name': 'Independent Publisher',
      'homepageUrl': 'https://other.example/',
    });
    final snapshot = LiveSnapshot.fromJson({
      'schemaVersion': 1,
      'snapshotId': 'cross-publisher',
      'generatedAt': fixture.now.toIso8601String(),
      'expiresAt': fixture.now.add(const Duration(hours: 1)).toIso8601String(),
      'sources': [first.toJson(), second.toJson()],
      'items': [
        item.toJson(),
        {...item.toJson(), 'id': 'independent-story', 'sourceId': second.id},
        {...item.toJson(), 'id': 'same-publisher-duplicate'},
      ],
    });
    expect(snapshot.items.map((item) => item.id), [
      item.id,
      'independent-story',
    ]);
  });
  test(
    'NASA repair is explicit, source-bound and limited to the exact channel self-link',
    () {
      const knownTag =
          '<atom:link href="https://science.nasa.gov/feed/?post_type=post&cat=19797&science_org=19791" rel="self" type="application/rss+xml"/>';
      final config = <String, Object?>{
        ..._reviewedSourceJson(),
        'id': 'nasa-photojournal',
        'imagePolicy': null,
        'feedUrl': 'https://science.nasa.gov/feed/photojournal/latest-content/',
        'feedRedirectHosts': ['science.nasa.gov'],
        'feedCompatibility': 'nasa-photojournal-self-link-v1',
      };
      final source = ApprovedLiveSource.fromJson(config);
      final raw = fixture
          .rss()
          .replaceFirst(
            '<rss ',
            '<rss xmlns:atom="http://www.w3.org/2005/Atom" ',
          )
          .replaceFirst('<channel>', '<channel>$knownTag');
      expect(fixture.parse(raw, approved: source).items, hasLength(1));
      expect(
        fixture
            .parse(
              raw
                  .replaceAll('&cat=', '&amp;cat=')
                  .replaceAll('&science_org=', '&amp;science_org='),
              approved: source,
            )
            .items,
        hasLength(1),
      );
      expect(() => fixture.parse(raw), throwsA(anything));
      for (final invalid in [
        '<!DOCTYPE rss>$raw',
        raw.replaceFirst(knownTag, '$knownTag$knownTag'),
        raw.replaceFirst('&cat=19797', '&cat=OTHER'),
        raw.replaceFirst(knownTag, '<metadata>$knownTag</metadata>'),
        raw.replaceFirst(
          'http://www.w3.org/2005/Atom',
          'https://other.example/namespace',
        ),
        raw
            .replaceFirst(knownTag, '')
            .replaceFirst('<item>', '<item>$knownTag'),
        raw.replaceFirst('</channel>', '<bad value="a&b"/></channel>'),
      ]) {
        expect(
          () => fixture.parse(invalid, approved: source),
          throwsA(anything),
        );
      }
      expect(
        () => ApprovedLiveSource.fromJson({...config, 'id': 'other'}),
        throwsFormatException,
      );
      expect(
        () => ApprovedLiveSource.fromJson({
          ...config,
          'feedUrl': 'https://science.nasa.gov/other/',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'full original headline, longer publisher excerpt and provenance survive normalization',
    () {
      final title = 'Research headline ${'with original wording ' * 14}';
      final summary =
          'Publisher description ${'and its supplied context ' * 25}';
      final item = fixture
          .parse(fixture.rss(title: title, desc: summary))
          .items
          .single;
      expect(item.title, title.trim());
      expect(item.title.length, greaterThan(200));
      expect(item.excerpt, summary.trim());
      expect(item.excerpt!.length, greaterThan(400));
      expect(item.excerptProvenance!.field, 'rss-description');
      expect(item.excerptProvenance!.shortened, isFalse);
      expect(LiveContentItem.fromJson(item.toJson()).toJson(), item.toJson());
      expect(fixture.parse(fixture.rss(title: 'x' * 501)).items, isEmpty);
    },
  );

  test(
    'excerpt shortening is bounded and explicit; Atom updated stays distinct from publication',
    () {
      final item = fixture
          .parse(fixture.rss(desc: '${'Context ' * 210}👩🏽‍🔬'))
          .items
          .single;
      expect(item.excerpt!.length, lessThanOrEqualTo(1600));
      expect(item.excerptProvenance!.shortened, isTrue);
      final atom = fixture
          .parse(
            '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Study</title><link href="https://publisher.example/news/one"/><updated>2026-09-13T10:00:00Z</updated><summary>Publisher summary</summary><content>Not an excerpt</content></entry></feed>',
          )
          .items
          .single;
      expect(atom.publishedAt, isNull);
      expect(atom.updatedAt, DateTime.utc(2026, 9, 13, 10));
      expect(atom.excerpt, 'Publisher summary');
      expect(atom.excerptProvenance!.field, 'atom-summary');
    },
  );

  test(
    'original outbound link retains supplied query without changing stable identity',
    () {
      final parsed = fixture.parse(
        fixture.rss(path: 'one?section=science&amp;utm_source=publisher'),
      );
      final item = parsed.items.single;
      expect(
        item.canonicalUrl.toString(),
        'https://publisher.example/news/one?section=science',
      );
      expect(
        item.originalUrl.toString(),
        'https://publisher.example/news/one?section=science&utm_source=publisher',
      );
      expect(item.openingUrl, item.originalUrl);
      final gate = fixture.gate([fixture.source()]);
      expect(gate.accepts(item, now: fixture.now), isTrue);
      for (final address in [
        'https://evil.example/news/one',
        'https://publisher.example/news/two',
        'https://publisher.example/news/one?section=other',
      ]) {
        expect(
          gate.accepts(
            LiveContentItem.fromJson({
              ...item.toJson(),
              'outboundUrl': address,
            }),
            now: fixture.now,
          ),
          isFalse,
        );
      }
      final blocked = LiveContentEligibility(
        registry: gate.registry,
        canOpenDestination: (uri) =>
            !uri.queryParameters.containsKey('utm_source'),
      );
      expect(blocked.accepts(item, now: fixture.now), isFalse);
    },
  );

  test(
    'approved source branding is separate from feed metadata and invalid branding falls back',
    () {
      final source = ApprovedLiveSource.fromJson(_reviewedSourceJson());
      expect(source.branding, isNotNull);
      expect(source.displayMode, 'publisher-link');
      expect(
        ApprovedLiveSource.fromJson({
          ..._reviewedSourceJson(),
          'branding': {'approved': false},
        }).branding,
        isNull,
      );
      expect(
        () => ApprovedLiveSource.fromJson({
          ..._reviewedSourceJson(),
          'displayMode': 'sponsored-syndication',
        }),
        throwsFormatException,
      );
      expect(liveContentTopicOrder, containsAll(['travel', 'environment']));
      expect(
        LiveContentPreferences.fromJson(
          const LiveContentPreferences(
            selectedTopics: {'travel', 'environment'},
          ).toJson(),
        ).selectedTopics,
        {'travel', 'environment'},
      );
    },
  );

  test(
    'reviewed story image requires exact article, source, all image metadata and rendition',
    () {
      final source = ApprovedLiveSource.fromJson(_reviewedSourceJson());
      final gate = fixture.gate([source]);
      final item = fixture.parse(fixture.rss(), approved: source).items.single;
      final image = gate.imageFor(item)!;
      expect(image.caption, startsWith('Story illustration:'));
      expect(image.articleId, item.id);
      expect(image.url.query, 'w=640&h=480');
      for (final change in <Map<String, Object?>>[
        {
          'url':
              'https://images.publisher.example/article/one.jpg?w=1280&h=960',
        },
        {'url': 'https://images.publisher.example/article/two.jpg?w=640&h=480'},
        {'articleId': 'another'},
        {'articleId': null},
        {'sourceId': 'other'},
        {'caption': 'Another story'},
        {'credit': 'Other credit'},
        {'licenseUrl': 'https://publisher.example/rights'},
        {'licenseLabel': 'Public domain'},
        {'width': 639},
        {'height': 479},
      ]) {
        final altered = LiveContentItem.fromJson({
          ...item.toJson(),
          'image': {...image.toJson(), ...change},
        });
        expect(gate.imageFor(altered), isNull, reason: '$change');
      }
      expect(
        fixture
            .parse(fixture.rss(path: 'two'), approved: source)
            .items
            .single
            .image,
        isNull,
      );
      expect(
        source.imagePolicy!.acceptsUri(
          Uri.parse('${image.url}&visitor=secret'),
        ),
        isFalse,
      );
      expect(
        ApprovedImagePolicy.fromJson(
          source.imagePolicy!.toJson(),
        ).reviewedArticles.values.single.toJson(),
        image.toJson(),
      );
    },
  );
}
