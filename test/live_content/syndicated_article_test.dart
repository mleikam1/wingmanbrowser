import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/syndicated_article.dart';

// Synthetic content only; no publisher article is bundled in these fixtures.
final _url = Uri.parse('https://publisher.example/features/testing');
final _license = Uri.parse('https://publisher.example/syndication');
SyndicatedArticle _parse(String html) => SyndicatedArticle.fromHtml(
  html: html,
  articleUrl: _url,
  publisher: 'Fixture Publisher',
  licenseUrl: _license,
);

void main() {
  test('alcohol-free cosmetics do not authorize beverage promotion', () {
    expect(
      acceptsSyndicatedPromotion('An alcohol-free skin-care treatment.'),
      isTrue,
    );
    expect(acceptsSyndicatedPromotion('Try alcohol-free beer.'), isFalse);
    expect(
      acceptsSyndicatedPromotion('Research explains alcohol benefits.'),
      isFalse,
    );
  });
  test('publisher list paragraphs retain complete text and links', () {
    final article = _parse(
      '<ul><li><p>First paragraph.</p>'
      '<p>Second <a href="https://reference.example/a">reference</a>.</p></li>'
      '<li><p>Last disclosure.</p></li></ul>',
    );
    expect(article.paragraphs, hasLength(2));
    expect(article.paragraphs.first.kind, SyndicatedParagraphKind.bullet);
    expect(
      article.paragraphs.first.text,
      'First paragraph.\nSecond reference.\n',
    );
    expect(article.paragraphs.last.text, 'Last disclosure.\n');
    expect(
      article.paragraphs.first.runs.singleWhere((r) => r.link != null).link,
      Uri.parse('https://reference.example/a'),
    );
  });
  test(
    'retains complete paragraphs, byline, emphasis, footnotes and links',
    () {
      final article = _parse(
        '<p>By A. Author (Fixture Publisher)</p>'
        '<h2>A complete fixture feature</h2>'
        '<p>First <strong>important</strong> paragraph with '
        '<a href="https://reference.example/detail">a source</a> and '
        '<em>more detail</em><sup>1</sup>.</p>'
        '<p>Second paragraph.<br>Next line &amp; final sentence.</p>'
        '<ol start="3"><li>First item.</li><li value="7">Second item.</li></ol>'
        '<p>1. Footnote with <a href="#note">the original reference</a>.</p>',
      );
      expect(article.plainText, contains('By A. Author (Fixture Publisher)'));
      expect(
        article.plainText,
        contains('First important paragraph with a source and more detail1.'),
      );
      expect(
        article.plainText,
        contains('Second paragraph.\nNext line & final sentence.'),
      );
      expect(article.plainText, contains('3. First item.\n\n7. Second item.'));
      expect(
        article.plainText,
        endsWith('1. Footnote with the original reference.'),
      );
      final runs = article.paragraphs.expand((p) => p.runs).toList();
      expect(runs.singleWhere((r) => r.text == 'important').bold, isTrue);
      expect(runs.singleWhere((r) => r.text == 'more detail').italic, isTrue);
      expect(runs.singleWhere((r) => r.text == '1').superscript, isTrue);
      expect(runs.where((r) => r.link != null).map((r) => r.link.toString()), [
        'https://reference.example/detail',
        'https://publisher.example/features/testing#note',
      ]);
    },
  );

  test(
    'text beyond card excerpt limits remains intact through cache restore',
    () {
      final ending = 'This closing disclosure must never disappear.';
      final html =
          '<p>By Fixture Author.</p><p>${'Complete text. ' * 800}</p><p>$ending</p>';
      final article = _parse(html);
      final restored = SyndicatedArticle.fromJson(article.toJson());
      expect(restored.plainText, article.plainText);
      expect(restored.plainText.length, greaterThan(10000));
      expect(restored.plainText, endsWith(ending));
      expect(restored.toJson(), article.toJson());
    },
  );

  test('HTML photos and pixels expose no image or executable run', () {
    final article = _parse(
      '<p>Before<img src="https://trackit.newsusa.com/track.gif?id=1" alt>'
      '<img src="https://image.example/photo.jpg" alt="Optional photo">After</p>',
    );
    expect(article.plainText, 'BeforeAfter');
    expect(
      article.paragraphs.expand((p) => p.runs).every((r) => r.link == null),
      isTrue,
    );
    expect(article.plainText, isNot(contains('trackit')));
  });

  for (final html in [
    '<p>Complete</p><script>alert(1)</script>',
    '<p>Complete</p><iframe>Required video explanation</iframe>',
    '<p>Complete</p><table><tr><td>Required disclosure</td></tr></table>',
    '<p>Complete</p><form>Required eligibility conditions</form>',
    '<p>Complete</p><svg><text>Important</text></svg>',
    '<p onclick="bad()">Complete</p>',
    '<p hidden>Required disclosure</p>',
    '<p>Broken <strong>format</p></strong>',
  ]) {
    test('rejects unsupported/malformed meaningful content: $html', () {
      expect(() => _parse(html), throwsFormatException);
    });
  }

  for (final href in [
    'javascript:alert(1)',
    'data:text/html,hello',
    'file:///tmp/private',
    'https://user:password@publisher.example/a',
    'http://127.0.0.1/a',
    'http://localhost/a',
    'https://intranet.local/a',
    'https://publisher.example:444/a',
    ' https://publisher.example/a',
  ]) {
    test('rejects unsafe embedded link $href', () {
      expect(
        () => _parse('<p>Read <a href="$href">the source</a>.</p>'),
        throwsFormatException,
      );
    });
  }

  test(
    'preserves ordinary HTTP and relative links for protected navigation',
    () {
      final article = _parse(
        '<p><a href="http://reference.example/story">Original HTTP</a>'
        ' <a href="/more">Relative source</a></p>',
      );
      expect(
        article.paragraphs.single.runs
            .where((r) => r.link != null)
            .map((r) => r.link.toString()),
        ['http://reference.example/story', 'https://publisher.example/more'],
      );
    },
  );

  for (final industry in [
    'tobacco',
    'nicotine',
    'vaping',
    'wine',
    'cocktails',
    'cannabis',
    'CBD',
    'THC',
    'sportsbook',
    'betting',
    'casino',
    'pornography',
    'drug',
    'opioids',
    'retatrutide',
  ]) {
    test('sponsored industry gate has no reporting exception: $industry', () {
      final body =
          '<p>Sponsored research and education about $industry benefits.</p>';
      expect(acceptsSyndicatedPromotion('Research about $industry'), isFalse);
      expect(() => _parse(body), throwsFormatException);
      final cached = _parse('<p>Ordinary fitness advice.</p>').toJson();
      cached['html'] = body;
      expect(() => SyndicatedArticle.fromJson(cached), throwsFormatException);
    });
  }

  test('encoded text and promotion links cannot evade the industry gate', () {
    expect(() => _parse('<p>Buy nicot&#105;ne.</p>'), throwsFormatException);
    expect(
      () => _parse(
        '<p>Try our <a href="https://offers.example/casino">new offer</a>.</p>',
      ),
      throwsFormatException,
    );
    expect(acceptsSyndicatedPromotion('nico\u200btine'), isFalse);
    expect(
      acceptsSyndicatedPromotion('Sponsored: try this school lunch recipe.'),
      isTrue,
    );
  });

  test('bounds HTML, paragraphs and nesting without truncating', () {
    expect(() => _parse('<p>${'x' * 65536}</p>'), throwsFormatException);
    expect(() => _parse('<p>text</p>' * 257), throwsFormatException);
    expect(
      () => _parse('${'<span>' * 26}text${'</span>' * 26}'),
      throwsFormatException,
    );
    expect(
      () => _parse('<img src="https://image.example/photo.jpg">'),
      throwsFormatException,
    );
  });

  test(
    'cache cannot replace validated structure with arbitrary block data',
    () {
      expect(
        () => SyndicatedArticle.fromJson({
          'schemaVersion': 1,
          'paragraphs': ['Injected'],
        }),
        throwsFormatException,
      );
      final cache = _parse('<p>Complete article.</p>').toJson();
      cache['articleUrl'] = 'file:///private';
      expect(() => SyndicatedArticle.fromJson(cache), throwsFormatException);
    },
  );
}
