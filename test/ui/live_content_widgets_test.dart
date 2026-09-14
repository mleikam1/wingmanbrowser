import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/presentation/live_content/live_content_preferences_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_content_feed_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_content_section.dart';
import 'package:wingman_browser/presentation/live_content/live_reading_list.dart';
import 'package:wingman_browser/presentation/live_content/live_story_image.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

// Entirely synthetic publisher data: these fixtures never ship in app assets.
final _now = DateTime.utc(2026, 9, 11, 12);
final _rights = LiveContentRights(
  titles: true,
  excerpts: true,
  images: false,
  attribution: 'Fixture publisher credit',
  licenseUrl: Uri.parse('https://fixture.example/rights'),
);
final _source = LiveSource(
  id: 'fixture-source',
  name: 'Fixture Science Publisher',
  homepageUrl: Uri.parse('https://fixture.example/'),
  language: 'en',
  topics: {'science', 'environment'},
  rights: _rights,
);
LiveContentItem _item(int index) => LiveContentItem(
  id: 'fixture-$index',
  sourceId: _source.id,
  title: 'Fixture article $index',
  canonicalUrl: Uri.parse('https://fixture.example/articles/$index'),
  publishedAt: index == 1 ? null : _now.subtract(Duration(hours: index)),
  fetchedAt: _now,
  language: 'en',
  topics: {index == 2 ? 'environment' : 'science'},
  region: index == 2 ? 'region-b' : 'region-a',
  rights: _rights,
  attribution: 'Fixture author $index',
  eligibilityState: 'eligible',
  eligibilityBasis: 'curated-source-scope',
  eligibilityScope: 'science-reporting',
  expiresAt: _now.add(const Duration(days: 7)),
  excerpt: 'A licensed fixture publisher excerpt for article $index.',
);

class _Provider implements FeedProvider {
  _Provider(this.snapshot);
  final LiveSnapshot snapshot;
  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async =>
      FeedResponse(snapshot: snapshot);
  @override
  void cancel() {}
}

class _FailingStore extends MemorySignatureDocumentStore {
  bool failSaved = false;
  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    if (failSaved && key == 'liveContentSaved') throw StateError('fixture');
    await super.writeDocument(key, value);
  }
}

Future<LiveContentController> _controller({
  MemorySignatureDocumentStore? store,
  bool configured = true,
  int pageSize = 2,
  bool revoked = false,
  int itemCount = 3,
}) async {
  final controller = LiveContentController(
    store: store ?? MemorySignatureDocumentStore(),
    eligibility: LiveContentEligibility(
      registry: LiveSourceRegistry([
        ApprovedLiveSource(
          source: _source,
          allowedArticleHosts: {'fixture.example'},
          articlePathPrefixes: {'/'},
          eligibilityScope: 'science-reporting',
          enabled: true,
        ),
      ]),
      canOpenDestination: (_) => true,
    ),
    provider: configured
        ? _Provider(
            LiveSnapshot(
              snapshotId: 'fixture-snapshot',
              generatedAt: _now,
              expiresAt: _now.add(const Duration(hours: 1)),
              sources: [_source],
              items: [for (var i = 1; i <= itemCount; i++) _item(i)],
              revokedSourceIds: revoked ? {_source.id} : {},
            ),
          )
        : null,
    clock: () => _now,
    pageSize: pageSize,
  )..setContext(LiveContentContext.owner);
  await controller.initialize();
  if (configured) await controller.refresh();
  return controller;
}

Widget _app(
  Widget child, {
  bool scroll = true,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: WingmanTheme.make(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
);
Widget _section(
  LiveContentController controller, {
  ValueChanged<LiveContentItem>? onOpen,
  ValueChanged<LiveContentItem>? onPin,
}) => LiveContentSection(
  controller: controller,
  onOpen: onOpen ?? (_) {},
  onPin: onPin ?? (_) {},
  onPreferences: () {},
  onReadingList: () {},
);
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('full feed reflows at 200% text in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          LiveContentFeedScreen(
            controller: controller,
            onOpen: (_) {},
            onPin: (_) {},
            onPreferences: () {},
            onReadingList: () {},
            canContinue: () => true,
          ),
          scroll: false,
          textScale: 2,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _key('live-topic-environment'));
      expect(controller.preferences.selectedTopics, {'environment'});
      expect(find.byType(LiveStoryImage), findsNothing);
      await _tap(tester, _key('live-save-fixture-2'));
      expect(controller.isSaved('fixture-2'), isTrue);
      expect(
        tester.getSize(_key('live-save-fixture-2')).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.getTopLeft(_key('live-topic-scroll')).dy, lessThan(220));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Home preview stays finite and full feed uses fixed single-topic choices',
    (tester) async {
      final controller = await _controller(pageSize: 5, itemCount: 7);
      addTearDown(controller.dispose);
      var viewAll = 0;
      await tester.pumpWidget(
        _app(
          LiveContentSection(
            controller: controller,
            preview: true,
            onViewAll: () => viewAll++,
            onOpen: (_) {},
            onPin: (_) {},
            onPreferences: () {},
            onReadingList: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fixture article 3'), findsOneWidget);
      expect(find.text('Fixture article 4'), findsNothing);
      expect(_key('live-feed-load-more'), findsNothing);
      expect(find.byType(LiveStoryImage), findsNothing);
      expect(find.textContaining('Topic photo'), findsNothing);
      await _tap(tester, _key('live-feed-view-all'));
      expect(viewAll, 1);
      await tester.pumpWidget(
        _app(
          LiveContentFeedScreen(
            controller: controller,
            onOpen: (_) {},
            onPin: (_) {},
            onPreferences: () {},
            onReadingList: () {},
            canContinue: () => true,
          ),
          scroll: false,
        ),
      );
      await tester.pumpAndSettle();
      for (final topic in liveContentTopicOrder) {
        expect(_key('live-topic-$topic'), findsOneWidget);
      }
      final headerY = tester.getTopLeft(_key('live-topic-scroll')).dy;
      await _tap(tester, _key('live-topic-environment'));
      expect(controller.preferences.selectedTopics, {'environment'});
      expect(find.text('Fixture article 2'), findsOneWidget);
      expect(find.text('Fixture article 1'), findsNothing);
      await _tap(tester, _key('live-topic-science'));
      expect(controller.preferences.selectedTopics, {'science'});
      expect(find.text('Fixture article 2'), findsNothing);
      await _tap(tester, _key('live-topic-fashion'));
      expect(controller.preferences.selectedTopics, {'fashion'});
      expect(find.text('No updates match your choices'), findsOneWidget);
      await _tap(tester, _key('live-topic-headlines'));
      expect(controller.preferences.selectedTopics, isEmpty);
      await _tap(tester, _key('live-feed-load-more'));
      expect(find.text('Fixture article 7'), findsOneWidget);
      expect(tester.getTopLeft(_key('live-topic-scroll')).dy, headerY);
      expect(_key('live-feed-load-more'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'title and approved credit links use callbacks and reject stale context',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      var current = true;
      final opened = <String>[];
      final licenses = <Uri>[];
      await tester.pumpWidget(
        _app(
          LiveContentSection(
            controller: controller,
            onOpen: (item) => opened.add(item.id),
            onPin: (_) {},
            onPreferences: () {},
            onReadingList: () {},
            canContinue: () => current,
            onOpenUri: licenses.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _key('live-title-fixture-1'));
      expect(opened, ['fixture-1']);
      await _tap(tester, _key('live-menu-fixture-1'));
      await _tap(tester, find.text('About this story'));
      await _tap(tester, find.text('Source rights').first);
      expect(licenses, [_rights.licenseUrl]);
      await _tap(tester, find.text('Done'));
      final stale = tester
          .widget<TextButton>(_key('live-title-fixture-1'))
          .onPressed!;
      current = false;
      stale();
      expect(opened, ['fixture-1']);
      controller.setContext(LiveContentContext.private);
      await tester.pumpAndSettle();
      expect(find.text('Fixture article 1'), findsNothing);
    },
  );

  testWidgets('compact cards retain full dates and excerpts in story details', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_section(controller)));
    await tester.pumpAndSettle();
    expect(find.text('Fixture article 1'), findsOneWidget);
    expect(find.text('Fixture article 2'), findsOneWidget);
    expect(find.text('Fixture article 3'), findsNothing);
    expect(find.text('Date unavailable'), findsOneWidget);
    expect(find.text('Publisher excerpt'), findsNothing);
    expect(find.text('Fixture author 1'), findsOneWidget);
    expect(find.byType(LiveStoryImage), findsNothing);
    expect(find.textContaining('Topic photo'), findsNothing);
    expect(find.byKey(const ValueKey('live-feed-freshness')), findsOneWidget);
    await _tap(tester, _key('live-menu-fixture-1'));
    await _tap(tester, find.text('About this story'));
    expect(find.textContaining('Date not supplied; fetched'), findsOneWidget);
    expect(find.text('Publisher excerpt'), findsOneWidget);
    expect(find.text(_item(1).excerpt!), findsOneWidget);
    await _tap(tester, find.text('Done'));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      final provider = image.image;
      expect(
        provider is AssetImage ||
            provider is ResizeImage && provider.imageProvider is AssetImage,
        isTrue,
      );
    }
    await _tap(tester, _key('live-feed-load-more'));
    expect(find.text('Fixture article 3'), findsOneWidget);
    expect(_key('live-feed-load-more'), findsNothing);
    expect(find.text('End of this selection.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'card actions open, save, pin, reduce topic and dismiss locally',
    (tester) async {
      final store = MemorySignatureDocumentStore();
      final controller = await _controller(store: store);
      addTearDown(controller.dispose);
      final opened = <String>[], pinned = <String>[];
      await tester.pumpWidget(
        _app(
          _section(
            controller,
            onOpen: (item) => opened.add(item.id),
            onPin: (item) => pinned.add(item.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _key('live-open-fixture-1'));
      expect(opened, ['fixture-1']);
      await _tap(tester, _key('live-save-fixture-1'));
      expect(controller.isSaved('fixture-1'), isTrue);
      expect(await store.readDocument('liveContentSaved'), isNotNull);
      await _tap(tester, _key('live-menu-fixture-1'));
      await _tap(tester, find.text('Add to Launchpad'));
      expect(pinned, ['fixture-1']);
      await _tap(tester, _key('live-menu-fixture-1'));
      await _tap(tester, find.text('Show fewer: Science'));
      expect(controller.preferences.fewerTopics, {'science'});
      await _tap(tester, _key('live-menu-fixture-1'));
      await _tap(tester, find.text('Dismiss item'));
      expect(find.text('Fixture article 1'), findsNothing);
      expect(controller.isSaved('fixture-1'), isTrue);
      await _tap(tester, _key('live-menu-fixture-2'));
      await _tap(tester, find.text('Hide Fixture Science Publisher'));
      expect(find.text('No updates match your choices'), findsOneWidget);
      expect(controller.preferences.hiddenSourceIds, {_source.id});
    },
  );

  testWidgets(
    'preferences use available choices, persist locally and reset keeps saved',
    (tester) async {
      final store = MemorySignatureDocumentStore();
      final controller = await _controller(store: store, pageSize: 1);
      addTearDown(controller.dispose);
      await controller.save(_item(1));
      await controller.setRegion('region-a');
      await tester.pumpWidget(
        _app(
          LiveContentPreferencesScreen(
            controller: controller,
            canContinue: () => true,
          ),
          scroll: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sports'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);
      final region = tester.widget<DropdownButtonFormField<String>>(
        _key('live-region-region-a'),
      );
      expect(region, isNotNull);
      await _tap(tester, _key('live-region-region-a'));
      expect(find.text('region-b'), findsOneWidget);
      await _tap(tester, find.text('region-b'));
      expect(controller.preferences.region, 'region-b');
      await _tap(tester, _key('live-preferences-source-fixture-source'));
      expect(controller.preferences.follows(_source.id), isFalse);
      await _tap(tester, _key('live-preferences-enabled'));
      expect(controller.preferences.enabled, isFalse);
      final restored = await _controller(store: store, configured: false);
      expect(restored.preferences.enabled, isFalse);
      expect(restored.preferences.follows(_source.id), isFalse);
      restored.dispose();
      await _tap(tester, _key('live-preferences-reset'));
      expect(controller.preferences.enabled, isTrue);
      expect(controller.preferences.hiddenSourceIds, isEmpty);
      expect(controller.preferences.region, isNull);
      expect(controller.isSaved('fixture-1'), isTrue);
      await _tap(tester, find.text('Preview diagnostics'));
      expect(find.text('Feed diagnostics preview'), findsOneWidget);
      final preview = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(preview, contains('snapshotGeneratedAt'));
      expect(preview, isNot(contains('fixture.example')));
      expect(preview, isNot(contains('Fixture article')));
      expect(find.text('Upload'), findsNothing);
      expect(find.text('Send'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved links persist, tombstones disable opening and stale callbacks are guarded',
    (tester) async {
      final store = MemorySignatureDocumentStore();
      final first = await _controller(store: store);
      await first.save(_item(1));
      first.dispose();
      final document = (await store.readDocument('liveContentSaved'))!;
      (document['items']! as List).add(
        LiveSavedItem(
          id: 'fixture-withdrawn',
          item: null,
          sourceId: _source.id,
          savedAt: _now,
          unavailableReason: 'Fixture publisher withdrew this item.',
        ).toJson(),
      );
      await store.writeDocument('liveContentSaved', document);
      final controller = await _controller(store: store, configured: false);
      addTearDown(controller.dispose);
      var canContinue = true;
      final opened = <String>[], pinned = <String>[];
      await tester.pumpWidget(
        _app(
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: LiveReadingList(
                  controller: controller,
                  canContinue: () => canContinue,
                  onOpen: (item) => opened.add(item.id),
                  onPin: (item) => pinned.add(item.id),
                ),
              ),
            ],
          ),
          scroll: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsOneWidget);
      expect(find.text('Fixture article 1'), findsOneWidget);
      expect(find.text('Saved article unavailable'), findsOneWidget);
      expect(find.byType(LiveStoryImage), findsNothing);
      expect(
        find.descendant(
          of: _key('live-saved-fixture-withdrawn'),
          matching: find.byType(LiveStoryImage),
        ),
        findsNothing,
      );
      final tombstone = tester.widget<OutlinedButton>(
        _key('live-saved-open-fixture-withdrawn'),
      );
      expect(tombstone.onPressed, isNull);
      await _tap(tester, _key('live-saved-open-fixture-1'));
      await _tap(tester, _key('live-saved-pin-fixture-1'));
      expect(opened, ['fixture-1']);
      expect(pinned, ['fixture-1']);
      final staleCallback = tester
          .widget<OutlinedButton>(_key('live-saved-open-fixture-1'))
          .onPressed!;
      canContinue = false;
      staleCallback();
      expect(opened, ['fixture-1']);
      canContinue = true;
      await _tap(tester, _key('live-saved-remove-fixture-withdrawn'));
      expect(find.text('Saved article unavailable'), findsNothing);
      controller.setContext(LiveContentContext.private);
      await tester.pumpAndSettle();
      expect(find.byType(LiveStoryImage), findsNothing);
    },
  );

  testWidgets(
    'save failures stay visible and do not claim an article was saved',
    (tester) async {
      final store = _FailingStore();
      final controller = await _controller(store: store);
      addTearDown(controller.dispose);
      store.failSaved = true;
      await tester.pumpWidget(_app(_section(controller)));
      await tester.pumpAndSettle();
      await _tap(tester, _key('live-save-fixture-1'));
      expect(controller.isSaved('fixture-1'), isFalse);
      expect(find.text('Change not saved'), findsOneWidget);
      expect(
        tester.widget<IconButton>(_key('live-save-fixture-1')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'compact large text remains usable and revoked sources are unavailable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(_section(controller), textScale: 2));
      await tester.pumpAndSettle();
      await _tap(tester, _key('live-save-fixture-1'));
      expect(controller.isSaved('fixture-1'), isTrue);
      expect(tester.takeException(), isNull);
      final revoked = await _controller(revoked: true);
      addTearDown(revoked.dispose);
      await tester.pumpWidget(
        _app(
          LiveContentPreferencesScreen(
            controller: revoked,
            canContinue: () => true,
          ),
          scroll: false,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final sourceSwitch = tester.widget<SwitchListTile>(
        _key('live-preferences-source-fixture-source'),
      );
      expect(sourceSwitch.onChanged, isNull);
      expect(sourceSwitch.value, isFalse);
      expect(find.text('Currently unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
