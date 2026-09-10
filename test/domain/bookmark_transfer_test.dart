import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/domain/bookmark_transfer.dart';
import 'package:wingman_browser/domain/models.dart';

Uint8List bookmarkFile(String body) => Uint8List.fromList(
  utf8.encode('<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p>$body</DL><p>'),
);

void main() {
  test('Netscape folders flatten into ordered validated metadata', () {
    final preview = BookmarkTransferCodec.parse(
      bookmarkFile('''
<DT><H3>Folder</H3><DL><p>
<DT><A HREF="https://EXAMPLE.com/path?a=1&amp;b=2" ADD_DATE="1700000000">A &amp; B 📚</A>
<DT><A HREF="https://second.test"> </A></DL><p>
'''),
    );
    expect(preview.format, 'Netscape HTML');
    expect(preview.entries.map((entry) => entry.url), [
      'https://example.com/path?a=1&b=2',
      'https://second.test',
    ]);
    expect(preview.entries.first.title, 'A & B 📚');
    expect(preview.entries.last.title, 'second.test');
    expect(
      preview.entries.first.createdAt?.millisecondsSinceEpoch,
      1700000000000,
    );
    expect(preview.rejectedCount, 0);
  });

  test(
    'existing and file duplicates are counted without title replacement',
    () {
      final preview = BookmarkTransferCodec.parse(
        bookmarkFile('''
<DT><A HREF="https://existing.test">Existing</A>
<DT><A HREF="https://new.test">First</A>
<DT><A HREF="https://NEW.test">Replacement</A>
'''),
        existingUrls: ['https://existing.test'],
      );
      expect(preview.entries.single.title, 'First');
      expect(preview.duplicateCount, 2);
      expect(() => preview.entries.clear(), throwsUnsupportedError);
    },
  );

  test('untrusted markup contributes only safe URL and plain title', () {
    final preview = BookmarkTransferCodec.parse(
      bookmarkFile('''
<SCRIPT>fetch('https://secret.test');</SCRIPT>
<BASE HREF="https://secret.test/">
<IMG SRC="https://secret.test/pixel" ONERROR="alert(1)">
<DT><A HREF="https://safe.test" onclick="alert(2)"><b>Safe</b><script>secret</script></A>
<DT><A HREF="javascript:alert(1)">JS</A>
<DT><A HREF="data:text/html,secret">Data</A>
<DT><A HREF="file:///etc/passwd">File</A>
<DT><A HREF="https://name:password@secret.test">Credentials</A>
<DT><A HREF="relative.html">Relative</A>
<DT><A HREF="https://bad.test&#10;/path">Control</A>
'''),
    );
    expect(preview.entries.single.url, 'https://safe.test');
    expect(preview.entries.single.title, 'Safe');
    expect(preview.rejectedCount, 6);
  });

  test('export escapes attributes and text and round trips Unicode', () {
    final date = DateTime.utc(2026, 9, 10);
    final bytes = BookmarkTransferCodec.encodeHtml([
      Bookmark(
        id: 'one',
        url: 'https://safe.test/?a=%22&b=2',
        title: '<script>"Hello" & \'世界\' 📚</script>',
        createdAt: date,
      ),
    ]);
    final text = utf8.decode(bytes);
    expect(text, contains('&lt;script&gt;'));
    expect(text, contains('&amp;b=2'));
    expect(text, isNot(contains('<script>')));
    final imported = BookmarkTransferCodec.parse(bytes).entries.single;
    expect(imported.title, '<script>"Hello" & \'世界\' 📚</script>');
    expect(imported.url, 'https://safe.test/?a=%22&b=2');
    expect(imported.createdAt, date);
  });

  test('titles and invalid dates are bounded without splitting a rune', () {
    final title = List.filled(600, '📚').join();
    final preview = BookmarkTransferCodec.parse(
      bookmarkFile(
        '<DT><A HREF="https://safe.test" ADD_DATE="999999999999">$title</A>',
      ),
    );
    expect(preview.entries.single.title.runes.length, 512);
    expect(preview.entries.single.title, isNot(contains('\uFFFD')));
    expect(preview.entries.single.createdAt, isNull);
  });

  test('empty, wrong format and invalid UTF-8 files fail closed', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([0xff, 0xfe]),
      Uint8List.fromList(
        utf8.encode('<html><a href="https://safe.test">x</a></html>'),
      ),
      Uint8List.fromList(utf8.encode('{"bookmarks": []}')),
    ]) {
      expect(() => BookmarkTransferCodec.parse(bytes), throwsFormatException);
    }
  });

  test('byte, candidate and nesting bounds reject whole file', () {
    expect(
      () => BookmarkTransferCodec.parse(
        Uint8List(BookmarkTransferCodec.maximumFileBytes + 1),
      ),
      throwsFormatException,
    );
    expect(
      () => BookmarkTransferCodec.parse(
        bookmarkFile(
          List.filled(5001, '<DT><A HREF="https://same.test">Same</A>').join(),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => BookmarkTransferCodec.parse(
        bookmarkFile(
          '${List.filled(65, '<div>').join()}x${List.filled(65, '</div>').join()}',
        ),
      ),
      throwsFormatException,
    );
    // Repeated unterminated starts must not make the preflight rescan the
    // remaining megabyte once for each '<' (quadratic malformed-input work).
    expect(
      () => BookmarkTransferCodec.parse(
        bookmarkFile(List.filled(250000, '<div').join()),
      ),
      throwsFormatException,
    );
  });

  test('export refuses invalid URLs and outputs above import bounds', () {
    Bookmark item(int id, String url) => Bookmark(
      id: '$id',
      url: url,
      title: 'Title',
      createdAt: DateTime.utc(2026),
    );
    expect(
      () => BookmarkTransferCodec.encodeHtml([
        item(0, 'https://name:password@secret.test'),
      ]),
      throwsFormatException,
    );
    expect(
      () => BookmarkTransferCodec.encodeHtml([
        for (var i = 0; i < 5001; i++) item(i, 'https://safe.test/$i'),
      ]),
      throwsFormatException,
    );
    final longUrl = 'https://safe.test/${List.filled(8000, 'x').join()}';
    expect(
      () => BookmarkTransferCodec.encodeHtml([
        for (var i = 0; i < 400; i++) item(i, '$longUrl$i'),
      ]),
      throwsFormatException,
    );
  });
}
