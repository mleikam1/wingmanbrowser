import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show HtmlParser;

/// Sponsored features have no educational/reporting exception for these
/// industries. This supplements the destination policy; it is not a classifier
/// for all possible promotions or a substitute for source admission.
bool acceptsSyndicatedPromotion(String text) {
  if (text.length > SyndicatedArticle.maximumHtmlLength ||
      _unsafeCharacters.hasMatch(text)) {
    return false;
  }
  // A cosmetic marked alcohol-free does not promote alcoholic beverages.
  // Beverage nouns remain independently denied, including alcohol-free beer.
  final reviewed = text.replaceAll(
    RegExp(r'\balcohol[- ]free\b', caseSensitive: false),
    '',
  );
  return !_prohibitedIndustry.hasMatch(reviewed);
}

final _unsafeCharacters = RegExp(
  r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]',
);
final _prohibitedIndustry = RegExp(
  r'\b(?:tobacco|nicotine|cigarettes?|cigars?|vaping|vapes?|e[- ]?cigarettes?|'
  r'alcohol(?:ic)?|liquor|spirits|beers?|wines?|winery|vodka|whisk(?:e)?y|'
  r'bourbon|champagne|cocktails?|brewer(?:y|ies)|'
  r'cannabis|marijuana|hemp|cbd|thc|delta[- ]?(?:8|9)|'
  r'gambl\w*|casinos?|sportsbook\w*|bets?|betting|wagers?|lotter(?:y|ies)|'
  r'porn\w*|adult entertainment|adult dating|sex toys?|sexual wellness|'
  r'drugs?|narcotics?|opioids?|fentanyl|'
  r'cocaine|heroin|methamphetamine|ketamine|psilocybin|retatrutide|'
  r'prescription drugs?|prescription medications?)\b',
  caseSensitive: false,
);

enum SyndicatedParagraphKind { paragraph, heading, bullet, numbered }

class SyndicatedRun {
  const SyndicatedRun._(
    this.text, {
    this.link,
    this.bold = false,
    this.italic = false,
    this.superscript = false,
  });
  final String text;
  final Uri? link;
  final bool bold, italic, superscript;
}

class SyndicatedParagraph {
  SyndicatedParagraph._(this.kind, List<SyndicatedRun> runs, {this.marker})
    : runs = List.unmodifiable(runs);
  final SyndicatedParagraphKind kind;
  final List<SyndicatedRun> runs;
  final String? marker;
  String get text => runs.map((run) => run.text).join();
}

/// A complete, inert article. Only the parsed text/runs may be rendered.
/// Original HTML is retained privately for deterministic cache revalidation.
/// No code in this model performs I/O or exposes an HTML rendering surface.
class SyndicatedArticle {
  SyndicatedArticle._(
    this._html, {
    required this.articleUrl,
    required this.publisher,
    required this.licenseUrl,
    required List<SyndicatedParagraph> paragraphs,
  }) : paragraphs = List.unmodifiable(paragraphs);

  static const maximumHtmlLength = 65536;
  static const maximumParagraphs = 256;
  static const maximumRuns = 2048;

  factory SyndicatedArticle.fromHtml({
    required String html,
    required Uri articleUrl,
    required String publisher,
    required Uri licenseUrl,
  }) {
    if (html.isEmpty ||
        html.length > maximumHtmlLength ||
        _unsafeCharacters.hasMatch(html) ||
        publisher.isEmpty ||
        publisher.length > 160 ||
        _unsafeCharacters.hasMatch(publisher) ||
        RegExp(r'[<>]').hasMatch(publisher) ||
        !_publicWebUri(articleUrl, httpsOnly: true) ||
        !_publicWebUri(licenseUrl, httpsOnly: true)) {
      throw const FormatException('Invalid syndicated article.');
    }
    final dom.DocumentFragment fragment;
    try {
      fragment = HtmlParser(html, strict: true).parseFragment();
    } catch (_) {
      throw const FormatException('Malformed syndicated article.');
    }
    final parser = _ArticleParser(articleUrl);
    parser.container(fragment.nodes);
    final paragraphs = parser.finish();
    final article = SyndicatedArticle._(
      html,
      articleUrl: articleUrl,
      publisher: publisher,
      licenseUrl: licenseUrl,
      paragraphs: paragraphs,
    );
    if (article.plainText.trim().isEmpty ||
        !acceptsSyndicatedPromotion(article.plainText) ||
        !acceptsSyndicatedPromotion(publisher) ||
        article.paragraphs
            .expand((p) => p.runs)
            .any(
              (r) =>
                  r.link != null &&
                  !acceptsSyndicatedPromotion(
                    Uri.decodeFull(r.link.toString()),
                  ),
            )) {
      throw const FormatException('Syndicated article is not eligible.');
    }
    return article;
  }

  factory SyndicatedArticle.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['html'] is! String ||
        json['publisher'] is! String ||
        json['articleUrl'] is! String ||
        json['licenseUrl'] is! String) {
      throw const FormatException('Invalid syndicated article cache.');
    }
    final articleUrl = Uri.tryParse(json['articleUrl'] as String);
    final licenseUrl = Uri.tryParse(json['licenseUrl'] as String);
    if (articleUrl == null || licenseUrl == null) {
      throw const FormatException('Invalid syndicated article addresses.');
    }
    return SyndicatedArticle.fromHtml(
      html: json['html'] as String,
      articleUrl: articleUrl,
      publisher: json['publisher'] as String,
      licenseUrl: licenseUrl,
    );
  }

  final Uri articleUrl, licenseUrl;
  final String publisher, _html;
  final List<SyndicatedParagraph> paragraphs;
  String get plainText => paragraphs
      .map((p) => '${p.marker == null ? '' : '${p.marker} '}${p.text}')
      .join('\n\n');
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'articleUrl': articleUrl.toString(),
    'publisher': publisher,
    'licenseUrl': licenseUrl.toString(),
    'html': _html,
  };
}

bool _publicWebUri(Uri uri, {bool httpsOnly = false}) {
  if ((uri.scheme != 'https' && (httpsOnly || uri.scheme != 'http')) ||
      uri.userInfo.isNotEmpty ||
      uri.toString().length > 4096 ||
      RegExp(r'[\x00-\x20\\]').hasMatch(uri.toString()) ||
      uri.host.endsWith('.') ||
      uri.host.contains('%') ||
      !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(uri.host) ||
      RegExp(r'^[0-9.]+$').hasMatch(uri.host) ||
      uri.host.endsWith('.local') ||
      uri.host.endsWith('.localhost') ||
      (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
    return false;
  }
  return true;
}

class _ArticleParser {
  _ArticleParser(this.articleUrl);
  final Uri articleUrl;
  final _paragraphs = <SyndicatedParagraph>[];
  final _pending = <SyndicatedRun>[];
  var _nodes = 0, _runs = 0;

  void _visit(dom.Node node, int depth) {
    if (++_nodes > 4096 || depth > 24) {
      throw const FormatException('Syndicated article is too complex.');
    }
    if (node is dom.Element) {
      if (node.attributes.keys.any(
            (key) => key.toString().toLowerCase().startsWith('on'),
          ) ||
          node.attributes.containsKey('hidden') ||
          node.attributes.containsKey('aria-hidden')) {
        throw const FormatException('Unsupported article attributes.');
      }
    }
  }

  void container(List<dom.Node> nodes, [int depth = 0]) {
    for (final node in nodes) {
      _visit(node, depth);
      if (node is dom.Comment) continue;
      if (node is dom.Element) {
        final tag = node.localName;
        if (tag == 'div' || tag == 'section' || tag == 'article') {
          _flush();
          container(node.nodes, depth + 1);
          _flush();
          continue;
        }
        if (tag == 'p' || RegExp(r'^h[1-6]$').hasMatch(tag ?? '')) {
          _flush();
          _inlineChildren(node.nodes, _pending, depth + 1);
          _flush(
            kind: tag == 'p'
                ? SyndicatedParagraphKind.paragraph
                : SyndicatedParagraphKind.heading,
          );
          continue;
        }
        if (tag == 'ul' || tag == 'ol') {
          _flush();
          var number = int.tryParse(node.attributes['start'] ?? '1');
          if (number == null ||
              number < 1 ||
              number > 9999 ||
              node.attributes.containsKey('reversed')) {
            throw const FormatException('Unsupported article list.');
          }
          for (final child in node.nodes) {
            if (child is dom.Comment ||
                (child is dom.Text && child.data.trim().isEmpty)) {
              continue;
            }
            _visit(child, depth + 1);
            if (child is! dom.Element || child.localName != 'li') {
              throw const FormatException('Malformed article list.');
            }
            if (child.attributes.containsKey('value')) {
              number = int.tryParse(child.attributes['value']!);
              if (number == null || number < 1 || number > 9999) {
                throw const FormatException('Unsupported article list value.');
              }
            }
            _inlineChildren(child.nodes, _pending, depth + 2);
            _flush(
              kind: tag == 'ol'
                  ? SyndicatedParagraphKind.numbered
                  : SyndicatedParagraphKind.bullet,
              marker: tag == 'ol' ? '${number!}.' : '•',
            );
            number = number! + 1;
          }
          continue;
        }
      }
      _inline(node, _pending, depth);
    }
  }

  void _inlineChildren(
    List<dom.Node> nodes,
    List<SyndicatedRun> output,
    int depth, {
    Uri? link,
    bool bold = false,
    bool italic = false,
    bool superscript = false,
  }) {
    for (final node in nodes) {
      _visit(node, depth);
      _inline(
        node,
        output,
        depth,
        link: link,
        bold: bold,
        italic: italic,
        superscript: superscript,
      );
    }
  }

  void _inline(
    dom.Node node,
    List<SyndicatedRun> output,
    int depth, {
    Uri? link,
    bool bold = false,
    bool italic = false,
    bool superscript = false,
  }) {
    if (node is dom.Comment) return;
    if (node is dom.Text) {
      final text = node.data.replaceAll(RegExp(r'[\t\r\n\f ]+'), ' ');
      if (text.isNotEmpty) {
        if (++_runs > SyndicatedArticle.maximumRuns ||
            _unsafeCharacters.hasMatch(text)) {
          throw const FormatException('Invalid article text.');
        }
        output.add(
          SyndicatedRun._(
            text,
            link: link,
            bold: bold,
            italic: italic,
            superscript: superscript,
          ),
        );
      }
      return;
    }
    if (node is! dom.Element) {
      throw const FormatException('Unsupported article node.');
    }
    final tag = node.localName;
    // NewsUSA explicitly permits omission of its accompanying photos. Neither
    // these image URLs nor tracking pixels are handed to any network API.
    if (tag == 'img') return;
    if (tag == 'br') {
      output.add(const SyndicatedRun._('\n'));
      return;
    }
    // List items can contain paragraphs. Preserve their breaks and disclosures.
    if (tag == 'p') {
      if (output.isNotEmpty && !output.last.text.endsWith('\n')) {
        output.add(const SyndicatedRun._('\n'));
      }
      _inlineChildren(
        node.nodes,
        output,
        depth + 1,
        link: link,
        bold: bold,
        italic: italic,
        superscript: superscript,
      );
      output.add(const SyndicatedRun._('\n'));
      return;
    }
    const allowed = {'a', 'span', 'strong', 'b', 'em', 'i', 'sup', 'small'};
    if (!allowed.contains(tag)) {
      throw const FormatException('Unsupported article content.');
    }
    if (tag == 'a' && node.attributes.containsKey('href')) {
      if (link != null) {
        throw const FormatException('Nested article link.');
      }
      final href = node.attributes['href']!;
      try {
        if (href.isEmpty || RegExp(r'[\x00-\x20\\]').hasMatch(href)) {
          throw const FormatException('Invalid article link.');
        }
        link = articleUrl.resolve(href);
        if (!_publicWebUri(link)) {
          throw const FormatException('Unsafe article link.');
        }
      } catch (_) {
        throw const FormatException('Invalid article link.');
      }
    }
    _inlineChildren(
      node.nodes,
      output,
      depth + 1,
      link: link,
      bold: bold || tag == 'strong' || tag == 'b',
      italic: italic || tag == 'em' || tag == 'i',
      superscript: superscript || tag == 'sup',
    );
  }

  void _flush({
    SyndicatedParagraphKind kind = SyndicatedParagraphKind.paragraph,
    String? marker,
  }) {
    if (_pending.any((run) => run.text.trim().isNotEmpty)) {
      if (_paragraphs.length >= SyndicatedArticle.maximumParagraphs) {
        throw const FormatException('Too many article paragraphs.');
      }
      _paragraphs.add(SyndicatedParagraph._(kind, _pending, marker: marker));
    }
    _pending.clear();
  }

  List<SyndicatedParagraph> finish() {
    _flush();
    return _paragraphs;
  }
}
