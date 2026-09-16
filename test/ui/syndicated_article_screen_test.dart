import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/presentation/live_content/syndicated_article_screen.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

// Explicit synthetic fixtures. This controller performs no HTTP requests.
final _date = DateTime.utc(2026, 9, 13);
final _uri = Uri.parse('https://fixture.example/story');
final _license = Uri.parse('https://fixture.example/terms');
final _article = SyndicatedArticle.fromHtml(
  html:
      '<p>By Fixture Author.</p><p><a href="https://reference.example/details">Source link</a></p>'
      '<p>All original fixture paragraphs remain here.</p><p>Final disclosure retained.</p>',
  articleUrl: _uri,
  publisher: 'Fixture Publisher',
  licenseUrl: _license,
);
final _item = LiveContentItem(
  id: 'fixture-syndicated',
  sourceId: 'fixture-source',
  title: 'Complete fixture feature',
  canonicalUrl: _uri,
  publishedAt: _date,
  fetchedAt: _date,
  language: 'en',
  topics: {'food'},
  rights: LiveContentRights(
    titles: true,
    excerpts: true,
    images: true,
    attribution: 'Fixture Publisher attribution',
    licenseUrl: _license,
  ),
  eligibilityState: 'eligible',
  eligibilityBasis: 'curated-source-scope',
  eligibilityScope: 'public-information',
  expiresAt: _date.add(const Duration(days: 7)),
  attribution: 'Fixture Author',
  syndicatedArticle: _article,
);

class _Controller extends LiveContentController {
  _Controller()
    : super(
        store: MemorySignatureDocumentStore(),
        eligibility: LiveContentEligibility(
          registry: LiveSourceRegistry([]),
          canOpenDestination: (_) => true,
        ),
      ) {
    setContext(LiveContentContext.owner);
  }
  bool readable = true, showImage = false;
  void photoAvailable(bool available) {
    showImage = available;
    notifyListeners();
  }

  @override
  bool canOpen(LiveContentItem item) => readable;
  void revoke() {
    readable = false;
    notifyListeners();
  }

  @override
  LiveArticleImage? imageFor(LiveContentItem item) => !showImage
      ? null
      : LiveArticleImage(
          url: Uri.parse('https://images.fixture.example/approved.png'),
          articleUrl: _uri,
          sourceId: item.sourceId,
          credit: 'Fixture photographer',
          caption: 'Approved fixture photo',
          licenseUrl: _license,
          licenseLabel: 'Fixture license',
          basis: 'fixture',
          width: 1,
          height: 1,
        );
  @override
  Uint8List? imageBytesFor(LiveContentItem item) => !showImage
      ? null
      : base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVQImWNgAAAAAgAB4iG8MwAAAABJRU5ErkJggg==',
        );
}

Widget _app(_Controller controller, List<Uri> opened, bool Function() guard) =>
    MaterialApp(
      theme: WingmanTheme.make(Brightness.light),
      home: SyndicatedArticleScreen(
        item: _item,
        controller: controller,
        canContinue: guard,
        onOpenUri: opened.add,
      ),
    );

void main() {
  testWidgets(
    'complete reader labels source and routes every link through callback',
    (tester) async {
      final controller = _Controller()..showImage = true;
      addTearDown(controller.dispose);
      final opened = <Uri>[];
      await tester.pumpWidget(_app(controller, opened, () => true));
      expect(
        find.text('Sponsored feature · Fixture Publisher'),
        findsOneWidget,
      );
      expect(find.text('Complete fixture feature'), findsOneWidget);
      expect(
        find.textContaining('Final disclosure retained.', findRichText: true),
        findsWidgets,
      );
      await tester.ensureVisible(
        find.text('Source link', findRichText: true).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source link', findRichText: true).last);
      expect(opened.single, Uri.parse('https://reference.example/details'));
      for (final key in ['syndicated-original', 'syndicated-license']) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
      }
      expect(opened, [
        Uri.parse('https://reference.example/details'),
        _uri,
        _license,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale callbacks recheck owner lease without relying on a rebuild',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.dispose);
      final opened = <Uri>[];
      var allowed = true;
      await tester.pumpWidget(_app(controller, opened, () => allowed));
      final original = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('syndicated-original')),
      );
      allowed = false;
      original.onPressed!();
      expect(opened, isEmpty);
      allowed = true;
      controller.setContext(LiveContentContext.private);
      original.onPressed!();
      expect(opened, isEmpty);
      await tester.pump();
      expect(find.text('Feature unavailable'), findsOneWidget);
      expect(find.text('Complete fixture feature'), findsNothing);
    },
  );

  testWidgets('revocation removes body and image from an already open reader', (
    tester,
  ) async {
    final controller = _Controller()..showImage = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, [], () => true));
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('syndicated-approved-image')),
        matching: find.byType(Image),
      ),
    );
    expect(image.image, isA<MemoryImage>());
    controller.revoke();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('syndicated-approved-image')),
      findsNothing,
    );
    expect(
      find.textContaining('Final disclosure retained.', findRichText: true),
      findsNothing,
    );
    expect(find.text('Feature unavailable'), findsOneWidget);
  });

  testWidgets(
    'saved complete article without its photo offers only protected original link',
    (tester) async {
      final controller = _Controller();
      addTearDown(controller.dispose);
      final opened = <Uri>[];
      await tester.pumpWidget(_app(controller, opened, () => true));
      expect(find.text('Feature photo unavailable'), findsOneWidget);
      expect(
        find.textContaining('Final disclosure retained.', findRichText: true),
        findsNothing,
      );
      expect(find.text('Complete fixture feature'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('syndicated-original')));
      expect(opened, [_uri]);
      controller.photoAvailable(true);
      await tester.pumpAndSettle();
      expect(find.text('Feature photo unavailable'), findsNothing);
      expect(
        find.byKey(const ValueKey('syndicated-approved-image')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Final disclosure retained.', findRichText: true),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'expired or cancelled photo removes already open syndicated body',
    (tester) async {
      final controller = _Controller()..showImage = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller, [], () => true));
      expect(
        find.byKey(const ValueKey('syndicated-approved-image')),
        findsOneWidget,
      );
      controller.photoAvailable(false);
      await tester.pump();
      expect(find.text('Feature photo unavailable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('syndicated-approved-image')),
        findsNothing,
      );
      expect(
        find.textContaining('Final disclosure retained.', findRichText: true),
        findsNothing,
      );
    },
  );
}
