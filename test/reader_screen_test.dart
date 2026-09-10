import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/reader_article.dart';
import 'package:wingman_browser/presentation/bookmark_files.dart';
import 'package:wingman_browser/presentation/screens/reader_screen.dart';

void main() {
  test('native import worker returns only parsed metadata', () async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><DT><A HREF="https://example.com/article">Article</A></DL>',
      ),
    );
    final preview = await decodeBookmarkFile(bytes, []);
    expect(preview.entries.single.url, 'https://example.com/article');
    expect(preview.entries.single.title, 'Article');
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('reader is selectable plain text with attribution at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.6),
            ),
            child: const ReaderScreen(
              article: ReaderArticle(
                title: 'A local article',
                sourceUrl: 'https://example.com/article',
                text: '<script>Not executable</script>\nA readable paragraph.',
              ),
            ),
          ),
        ),
      );
      expect(find.text('https://example.com/article'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('<script>'),
      );
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byTooltip('Larger reader text'));
      await tester.pump();
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .style!
            .fontSize,
        22,
      );
      await tester.tap(find.byTooltip('Smaller reader text'));
      await tester.pump();
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .style!
            .fontSize,
        20,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
