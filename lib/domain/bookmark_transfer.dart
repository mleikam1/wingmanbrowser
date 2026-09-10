import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'models.dart';
import 'search.dart';

class BookmarkImportEntry {
  const BookmarkImportEntry({
    required this.url,
    required this.title,
    this.createdAt,
  });
  final String url;
  final String title;
  final DateTime? createdAt;
}

class BookmarkImportPreview {
  BookmarkImportPreview({
    required Iterable<BookmarkImportEntry> entries,
    required this.duplicateCount,
    required this.rejectedCount,
    this.format = 'Netscape HTML',
  }) : entries = List.unmodifiable(entries);
  final List<BookmarkImportEntry> entries;
  final int duplicateCount;
  final int rejectedCount;
  final String format;
}

/// Inert bookmark-file decoding. No renderer, network client or file access.
/// Only URL, plain text and a validated date survive the import boundary.
class BookmarkTransferCodec {
  static const maximumFileBytes = 2 * 1024 * 1024;
  static const maximumEntries = 5000;
  static const maximumTitleRunes = 512;

  static BookmarkImportPreview parse(
    Uint8List bytes, {
    Iterable<String> existingUrls = const [],
  }) {
    if (bytes.isEmpty || bytes.length > maximumFileBytes) {
      throw const FormatException('Choose a bookmark HTML file up to 2 MiB.');
    }
    final String source;
    try {
      source = utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
    } on FormatException {
      throw const FormatException('The bookmark file must use UTF-8 text.');
    }
    if (!RegExp(
      r'<!DOCTYPE\s+NETSCAPE-Bookmark-file-1\s*>',
      caseSensitive: false,
    ).hasMatch(source)) {
      throw const FormatException(
        'Choose an exported Netscape bookmark HTML file.',
      );
    }
    _checkMarkupBounds(source);
    final Document document;
    try {
      document = html.parse(source);
    } catch (_) {
      throw const FormatException(
        'The bookmark file could not be read. Try exporting it again.',
      );
    }
    final entries = <BookmarkImportEntry>[];
    final seen = <String>{};
    for (final value in existingUrls) {
      try {
        seen.add(requireWebUri(value).toString());
      } on FormatException {
        // Invalid existing records are not eligible duplicate keys.
      }
    }
    var duplicates = 0;
    var rejected = 0;
    var candidates = 0;
    // The preflight bounds tree depth. Iterate instead of retaining an
    // additional querySelectorAll list or recursively joining arbitrary text.
    final pending = <Node>[document];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node is Element && node.localName == 'a') {
        if (++candidates > maximumEntries) {
          throw const FormatException(
            'Import up to 5,000 bookmarks at a time.',
          );
        }
        Uri uri;
        try {
          uri = requireWebUri((node.attributes['href'] ?? '').trim());
        } on FormatException {
          rejected++;
          continue;
        }
        final url = uri.toString();
        if (!seen.add(url)) {
          duplicates++;
          continue;
        }
        entries.add(
          BookmarkImportEntry(
            url: url,
            title: cleanTitle(_anchorText(node), fallback: uri.host),
            createdAt: _date(node.attributes['add_date']),
          ),
        );
      } else if (node is! Element || !_ignoredTags.contains(node.localName)) {
        pending.addAll(node.nodes.reversed);
      }
    }
    return BookmarkImportPreview(
      entries: entries,
      duplicateCount: duplicates,
      rejectedCount: rejected,
    );
  }

  static Uint8List encodeHtml(Iterable<Bookmark> bookmarks) {
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    final output = StringBuffer('''<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Wingman bookmarks</TITLE>
<H1>Wingman bookmarks</H1>
<DL><p>
''');
    var count = 0;
    for (final item in bookmarks) {
      if (++count > maximumEntries) {
        throw const FormatException('Export up to 5,000 bookmarks at a time.');
      }
      final uri = requireWebUri(item.url);
      final date = (item.createdAt.millisecondsSinceEpoch ~/ 1000).clamp(
        0,
        253402300799,
      );
      output.writeln(
        '<DT><A HREF="${escape.convert(uri.toString())}" ADD_DATE="$date">'
        '${escape.convert(cleanTitle(item.title, fallback: uri.host))}</A>',
      );
      // Reject rather than emit a file that this importer cannot safely read.
      if (output.length > maximumFileBytes) {
        throw const FormatException(
          'This export exceeds the 2 MiB file limit.',
        );
      }
    }
    output.write('</DL><p>\n');
    final bytes = Uint8List.fromList(utf8.encode(output.toString()));
    if (bytes.length > maximumFileBytes) {
      throw const FormatException('This export exceeds the 2 MiB file limit.');
    }
    return bytes;
  }

  static String cleanTitle(String value, {required String fallback}) {
    final clean = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return String.fromCharCodes(
      (clean.isEmpty ? fallback : clean).runes.take(maximumTitleRunes),
    );
  }

  static const _ignoredTags = {
    'script',
    'style',
    'template',
    'iframe',
    'object',
    'embed',
    'noscript',
  };

  static String _anchorText(Element anchor) {
    final pending = <Node>[...anchor.nodes.reversed];
    final text = StringBuffer();
    while (pending.isNotEmpty && text.length < 4096) {
      final node = pending.removeLast();
      if (node is Text) {
        text.write(String.fromCharCodes(node.data.runes.take(4096)));
      } else if (node is! Element || !_ignoredTags.contains(node.localName)) {
        pending.addAll(node.nodes.reversed);
      }
    }
    return text.toString();
  }

  static DateTime? _date(String? raw) {
    if (raw == null || raw.length > 12) return null;
    final seconds = int.tryParse(raw);
    if (seconds == null || seconds < 0 || seconds > 253402300799) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static void _checkMarkupBounds(String source) {
    var tags = 0;
    var depth = 0;
    const optionalOrVoid = {
      'dt',
      'dd',
      'p',
      'li',
      'html',
      'head',
      'body',
      'meta',
      'link',
      'br',
      'hr',
      'img',
      'input',
      'area',
      'base',
      'col',
      'embed',
      'param',
      'source',
      'track',
      'wbr',
      'option',
      'optgroup',
      'thead',
      'tbody',
      'tfoot',
      'tr',
      'td',
      'th',
    };
    final tagName = RegExp(r'^<\s*(/?)\s*([a-zA-Z][\w:-]*)\b');
    var offset = 0;
    while (true) {
      final start = source.indexOf('<', offset);
      if (start < 0) break;
      final end = source.indexOf('>', start + 1);
      if (end < 0 || end - start > 16384 || ++tags > 25000) {
        throw const FormatException('The bookmark file is too complex.');
      }
      offset = end + 1;
      final markup = source.substring(start, offset);
      final tag = tagName.firstMatch(markup);
      if (tag == null) continue;
      final name = tag.group(2)!.toLowerCase();
      if (optionalOrVoid.contains(name) || markup.endsWith('/>')) {
        continue;
      }
      depth += tag.group(1)!.isEmpty ? 1 : -1;
      depth = depth.clamp(0, 65);
      if (depth > 64) {
        throw const FormatException('The bookmark file is nested too deeply.');
      }
    }
  }
}
