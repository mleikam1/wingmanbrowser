import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';
import 'models.dart';
import 'eligibility.dart';
import 'rss_transport.dart';
import 'syndicated_article.dart';

String rssDigest(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 32);

/// The XML package preserves unknown/bare entities by default. Feed documents
/// require XML entities; HTML character references belong inside CDATA only.
class _StrictFeedEntities extends XmlDefaultEntityMapping {
  const _StrictFeedEntities() : super.xml();
  @override
  String decode(String input) {
    if (RegExp(
      r'&(?!amp;|lt;|gt;|quot;|apos;|#x[0-9a-fA-F]+;|#[0-9]+;)',
    ).hasMatch(input)) {
      throw const RssFailure('invalid-xml-entity');
    }
    for (final match in RegExp(
      r'&#(x[0-9a-fA-F]+|[0-9]+);',
    ).allMatches(input)) {
      final raw = match[1]!;
      final code = int.tryParse(
        raw.startsWith('x') ? raw.substring(1) : raw,
        radix: raw.startsWith('x') ? 16 : 10,
      );
      if (code == null ||
          !(code == 9 ||
              code == 10 ||
              code == 13 ||
              code >= 0x20 && code <= 0xd7ff ||
              code >= 0xe000 && code <= 0xfffd ||
              code >= 0x10000 && code <= 0x10ffff)) {
        throw const RssFailure('invalid-xml-character');
      }
    }
    return super.decode(input);
  }
}

String rssPlain(
  String text, {
  int limit = 100000,
  bool omitUnusedPhotoCaptions = false,
}) {
  if (text.length > 100000) throw const RssFailure('text-too-large');
  final fragment = html.parseFragment(text);
  fragment
      .querySelectorAll(
        'script,style,iframe,svg,noscript,object,embed,nav,footer',
      )
      .forEach((n) => n.remove());
  if (omitUnusedPhotoCaptions) {
    // A caption attached to an actual photo describes that photo's rights,
    // not necessarily the surrounding article. This is only used when the
    // source forbids images and permits normalizing its optional excerpt.
    for (final figure in fragment.querySelectorAll('figure')) {
      if (figure.querySelector('img') != null) {
        figure.querySelectorAll('figcaption').forEach((n) => n.remove());
      }
    }
  }
  final value = (fragment.text ?? '')
      .replaceAll(
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (value.length <= limit) return value;
  final truncated = StringBuffer();
  for (final character in value.characters) {
    if (truncated.length + character.length >= limit) break;
    truncated.write(character);
  }
  return '${truncated.toString().trimRight()}…';
}

DateTime? rssDate(String? text, DateTime now) {
  if (text == null || text.length > 100) return null;
  DateTime? value;
  final iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[tT](\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:[zZ]|([+-])(\d{2}):?(\d{2}))$',
  ).firstMatch(text.trim());
  if (iso != null) {
    final year = int.parse(iso[1]!),
        month = int.parse(iso[2]!),
        day = int.parse(iso[3]!);
    final calendar = DateTime.utc(year, month, day);
    if (calendar.year == year &&
        calendar.month == month &&
        calendar.day == day &&
        int.parse(iso[4]!) < 24 &&
        int.parse(iso[5]!) < 60 &&
        int.parse(iso[6]!) < 60 &&
        (iso[8] == null ||
            (int.parse(iso[8]!) < 24 && int.parse(iso[9]!) < 60))) {
      value = DateTime.tryParse(text.trim());
    }
  }
  if (value == null) {
    final m = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s+([A-Za-z]{1,5}|[+-]\d{4})$',
    ).firstMatch(text.trim());
    if (m != null) {
      const months = [
        'jan',
        'feb',
        'mar',
        'apr',
        'may',
        'jun',
        'jul',
        'aug',
        'sep',
        'oct',
        'nov',
        'dec',
      ];
      const zones = {
        'UT': 0,
        'UTC': 0,
        'GMT': 0,
        'EST': -300,
        'EDT': -240,
        'CST': -360,
        'CDT': -300,
        'MST': -420,
        'MDT': -360,
        'PST': -480,
        'PDT': -420,
      };
      final month = months.indexOf(m[2]!.toLowerCase()) + 1,
          zone = m[7]!.toUpperCase();
      int? offset = zones[zone];
      if (RegExp(r'^[+-]\d{4}$').hasMatch(zone)) {
        final hours = int.parse(zone.substring(1, 3)),
            minutes = int.parse(zone.substring(3));
        if (hours <= 23 && minutes <= 59) {
          offset = (hours * 60 + minutes) * (zone.startsWith('-') ? -1 : 1);
        }
      }
      if (month > 0 && offset != null) {
        final day = int.parse(m[1]!),
            hour = int.parse(m[4]!),
            minute = int.parse(m[5]!),
            second = int.parse(m[6] ?? '0');
        if (day >= 1 && day <= 31 && hour < 24 && minute < 60 && second < 60) {
          final local = DateTime.utc(
            int.parse(m[3]!),
            month,
            day,
            hour,
            minute,
            second,
          );
          if (local.month == month) {
            value = local.subtract(Duration(minutes: offset));
          }
        }
      }
    }
  }
  if (value == null ||
      value.year < 1990 ||
      value.isAfter(now.add(const Duration(hours: 24)))) {
    return null;
  }
  return value.toUtc();
}

Uri? rssCanonical(String raw, ApprovedLiveSource source) {
  try {
    final decoded = (html.parseFragment(raw).text ?? '').trim();
    final uri = feedArticleUri(decoded);
    if (!source.allowedArticleHosts.contains(uri.host)) return null;
    final path = Uri.decodeComponent(uri.path.isEmpty ? '/' : uri.path);
    if (path.contains('\\') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(path) ||
        path.split('/').any((p) => p == '.' || p == '..')) {
      return null;
    }
    if (!source.articlePathPrefixes.any(
      (p) =>
          p == '/' || path == p || path.startsWith(p.endsWith('/') ? p : '$p/'),
    )) {
      return null;
    }
    if (source.articleUrlFormat == 'dated-story' &&
        !RegExp(r'^/\d{4}/\d{2}/\d{2}/[^/]+/?$').hasMatch(path)) {
      return null;
    }
    if (uri.queryParametersAll.length > 40) return null;
    return feedCanonicalIdentity(uri);
  } catch (_) {
    return null;
  }
}

class RssParsedFeed {
  const RssParsedFeed(
    this.items,
    this.guidToItem,
    this.revokedIds,
    this.deletedRefs,
    this.rejected, {
    this.parsedEntries = 0,
    this.textEligible = 0,
    this.topicMatched = 0,
    this.imagePermitted = 0,
    this.rejectionReasons = const {},
    this.optionalFieldReasons = const {},
    this.newestPublicationAt,
  });
  final List<LiveContentItem> items;
  final Map<String, String> guidToItem;
  final Set<String> revokedIds, deletedRefs;
  final int rejected;
  final int parsedEntries, textEligible, topicMatched, imagePermitted;

  /// Fixed reason keys and counts only: no article text or reader information.
  final Map<String, int> rejectionReasons;
  final Map<String, int> optionalFieldReasons;
  final DateTime? newestPublicationAt;
}

Set<String> _featureTopics(String title) {
  const terms = <String, String>{
    'business':
        r'\b(?:business|financial|finance|retirement|investing|banking|savings)\b',
    'technology':
        r'\b(?:technology|quantum|software|gaming|digital|computers?)\b',
    'sports': r'\b(?:sports?|football|basketball|baseball|soccer|athletes?)\b',
    'entertainment': r'\b(?:books?|movies?|music|entertainment|novels?)\b',
    'food': r'\b(?:foods?|recipes?|cooking|nutrition|meals?|kitchen)\b',
    'health': r'\b(?:health|flu|wellness|vaccines?|medical|fitness|sleep)\b',
    'fashion': r'\b(?:fashion|clothing|skincare|skin care|beauty|facial)\b',
    'travel': r'\b(?:travel|vacation|tourism|destinations?|sightseeing)\b',
  };
  final topics = terms.entries
      .where((e) => RegExp(e.value, caseSensitive: false).hasMatch(title))
      .map((e) => e.key)
      .toSet();
  return topics.isEmpty ? {'headlines'} : topics;
}

LiveArticleImage? rssThumbnail(
  XmlElement entry,
  ApprovedLiveSource source,
  Uri article,
) {
  final policy = source.imagePolicy;
  if (!source.source.rights.images || policy == null) {
    return null;
  }
  if (policy.kind == 'reviewed-article-image') {
    // A reviewed story association is the only authority for this kind; feed
    // enclosures, HTML images and alternate renditions cannot expand it.
    return policy.reviewedArticles[article.toString()];
  }
  if (policy.kind == 'syndicated-article-photo') {
    for (final node in entry.childElements.where(
      (n) => n.name.local == 'enclosure',
    )) {
      try {
        final uri = feedArticleUri(node.getAttribute('url'));
        if (!policy.acceptsUri(uri) ||
            !{
              'image/jpeg',
              'image/png',
              'image/webp',
            }.contains(node.getAttribute('type'))) {
          continue;
        }
        return LiveArticleImage(
          url: uri,
          articleUrl: article,
          sourceId: source.source.id,
          credit: policy.credit,
          caption: 'Photo supplied with this sponsored feature',
          licenseUrl: policy.licenseUrl,
          licenseLabel: policy.licenseLabel,
          basis: policy.kind,
          width: 0,
          height: 0,
        );
      } catch (_) {}
    }
    return null;
  }
  LiveArticleImage? thumbnail(
    String? raw,
    String? rawWidth,
    String? rawHeight,
  ) {
    try {
      final uri = feedArticleUri(raw);
      final width = int.tryParse(rawWidth ?? ''),
          height = int.tryParse(rawHeight ?? '');
      if (!policy.acceptsUri(uri) ||
          width == null ||
          height == null ||
          width != 90 ||
          height != 90 ||
          width > policy.maximumWidth ||
          height > policy.maximumHeight) {
        return null;
      }
      return LiveArticleImage(
        url: uri,
        articleUrl: article,
        sourceId: source.source.id,
        credit: policy.credit,
        caption: 'Publisher thumbnail',
        licenseUrl: policy.licenseUrl,
        licenseLabel: policy.licenseLabel,
        basis: policy.kind,
        width: width,
        height: height,
      );
    } catch (_) {
      /* An unusable thumbnail leaves the article intact. */
      return null;
    }
  }

  const mediaNamespace = 'http://search.yahoo.com/mrss/';
  const imageTypes = {'image/jpeg', 'image/png', 'image/webp'};
  final directMedia = entry.childElements
      .where((node) => node.namespaceUri == mediaNamespace)
      .toList();
  final nestedMedia = directMedia
      .where((node) => {'group', 'content'}.contains(node.name.local))
      .expand((node) => node.descendantElements)
      .where((node) => node.namespaceUri == mediaNamespace)
      .toList();
  // Prefer explicit thumbnails to other publisher-supplied item image formats.
  // This never examines the channel logo, srcset or a larger derived rendition.
  for (final node in [
    ...directMedia,
    ...nestedMedia,
  ].where((node) => node.name.local == 'thumbnail')) {
    final image = thumbnail(
      node.getAttribute('url'),
      node.getAttribute('width'),
      node.getAttribute('height'),
    );
    if (image != null) return image;
  }
  for (final node in [
    ...directMedia,
    ...nestedMedia,
  ].where((node) => node.name.local == 'content')) {
    if (!imageTypes.contains(node.getAttribute('type')?.toLowerCase()) ||
        (node.getAttribute('medium') != null &&
            node.getAttribute('medium') != 'image')) {
      continue;
    }
    final image = thumbnail(
      node.getAttribute('url'),
      node.getAttribute('width'),
      node.getAttribute('height'),
    );
    if (image != null) return image;
  }
  for (final node in entry.childElements.where(
    (node) =>
        node.name.local == 'enclosure' &&
        (node.namespaceUri == null || node.namespaceUri == ''),
  )) {
    if (!imageTypes.contains(node.getAttribute('type')?.toLowerCase())) {
      continue;
    }
    final image = thumbnail(
      node.getAttribute('url'),
      node.getAttribute('width'),
      node.getAttribute('height'),
    );
    if (image != null) return image;
  }
  final description = entry.childElements
      .where(
        (node) =>
            node.name.local == 'description' &&
            (node.namespaceUri == null || node.namespaceUri == ''),
      )
      .firstOrNull
      ?.innerText;
  if (description != null && description.length <= 100000) {
    final fragment = html.parseFragment(description);
    fragment
        .querySelectorAll(
          'script,style,iframe,svg,noscript,object,embed,template,nav,footer',
        )
        .forEach((node) => node.remove());
    for (final node in fragment.querySelectorAll('img')) {
      final image = thumbnail(
        node.attributes['src'],
        node.attributes['width'],
        node.attributes['height'],
      );
      if (image != null) return image;
    }
  }
  return null;
}

RssParsedFeed parseRssFeed(
  Uint8List bytes,
  ApprovedLiveSource source,
  DateTime now,
  LiveContentEligibility eligibility,
  bool Function(String, String) allowsEditorialText,
) {
  if (bytes.length > rssMaximumXmlBytes) {
    throw const RssFailure('xml-too-large');
  }
  var text = utf8.decode(bytes, allowMalformed: false);
  if (RegExp(
    r'<!\s*(?:DOCTYPE|ENTITY)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    throw const RssFailure('xml-declarations-forbidden');
  }
  if (source.feedCompatibility == 'nasa-photojournal-self-link-v1' &&
      source.source.id == 'nasa-photojournal' &&
      source.feedUri?.toString() ==
          'https://science.nasa.gov/feed/photojournal/latest-content/') {
    const knownTag =
        '<atom:link href="https://science.nasa.gov/feed/?post_type=post&cat=19797&science_org=19791" rel="self" type="application/rss+xml"/>';
    final at = text.indexOf(knownTag);
    final channel = text.indexOf('<channel>');
    final firstItem = text.indexOf('<item');
    if (at >= 0 &&
        channel >= 0 &&
        at > channel &&
        firstItem > at &&
        text.indexOf(knownTag, at + knownTag.length) < 0) {
      var directSelfLink = false, inspected = 0;
      // The package's default decoder is used only to locate the malformed
      // known node. The strict decoder still checks the entire repaired XML.
      for (final event in parseEvents(
        text,
        withLocation: true,
        withParent: true,
        withNamespace: true,
      )) {
        if (++inspected > 20000) throw const RssFailure('xml-node-limit');
        if ((event.start ?? text.length) > at) break;
        if (event.start == at) {
          directSelfLink =
              event is XmlStartElementEvent &&
              event.name == 'atom:link' &&
              event.namespaceUri == 'http://www.w3.org/2005/Atom' &&
              event.parent?.name == 'channel' &&
              event.parent?.parent?.name == 'rss' &&
              event.stop == at + knownTag.length;
          break;
        }
      }
      if (directSelfLink) {
        // Only the two bare '&' in this source's exact channel self-link change.
        text = text.replaceRange(
          at,
          at + knownTag.length,
          knownTag.replaceAll('&', '&amp;'),
        );
      }
    }
  }
  var nodes = 0, depth = 0;
  for (final event in parseEvents(
    text,
    entityMapping: const _StrictFeedEntities(),
  )) {
    if (++nodes > 20000 || event is XmlDoctypeEvent) {
      throw const RssFailure('xml-node-limit');
    }
    if (event is XmlStartElementEvent) {
      if (event.attributes.length > 64) {
        throw const RssFailure('xml-attribute-limit');
      }
      if (!event.isSelfClosing && ++depth > 64) {
        throw const RssFailure('xml-depth-limit');
      }
    } else if (event is XmlEndElementEvent) {
      depth--;
    }
  }
  final root = XmlDocument.parse(
    text,
    entityMapping: const _StrictFeedEntities(),
  ).rootElement;
  final atom =
      root.name.local == 'feed' &&
      root.namespaceUri == 'http://www.w3.org/2005/Atom';
  if (!atom && root.name.local != 'rss') {
    throw const RssFailure('unknown-feed-format');
  }
  if (!atom && root.getElement('channel') == null) {
    throw const RssFailure('missing-rss-channel');
  }
  final entries =
      (atom
              ? root.childElements.where((n) => n.name.local == 'entry')
              : root
                        .getElement('channel')
                        ?.childElements
                        .where((n) => n.name.local == 'item') ??
                    const <XmlElement>[])
          .toList();
  if (entries.length > 500) throw const RssFailure('entry-limit');
  String field(XmlElement entry, Set<String> names) =>
      entry.childElements
          .where((n) => names.contains(n.name.local))
          .map((n) => n.innerText)
          .firstOrNull ??
      '';
  final items = <LiveContentItem>[],
      guids = <String, String>{},
      revoked = <String>{},
      deleted = <String>{};
  var rejected = 0, textEligible = 0, topicMatched = 0, imagePermitted = 0;
  DateTime? newestPublicationAt;
  final reasons = <String, int>{};
  final optionalReasons = <String, int>{};
  void reason(String code, {bool reject = true}) {
    if (reject) rejected++;
    (reject ? reasons : optionalReasons).update(
      code,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  for (final node in root.descendantElements) {
    if (node.name.local == 'deleted-entry' &&
        node.namespaceUri == 'http://purl.org/atompub/tombstones/1.0') {
      final ref = node.getAttribute('ref');
      if (ref != null && ref.length <= 4096) deleted.add(rssDigest(ref));
    }
  }
  for (final entry in entries) {
    Uri? url;
    Uri? original;
    final links = atom
        ? entry.childElements
              .where(
                (n) =>
                    n.name.local == 'link' &&
                    n.namespaceUri == 'http://www.w3.org/2005/Atom' &&
                    (n.getAttribute('rel') ?? 'alternate') == 'alternate',
              )
              .map((n) => n.getAttribute('href') ?? '')
        : entry.childElements
              .where(
                (n) =>
                    n.name.local == 'link' &&
                    (n.namespaceUri == null || n.namespaceUri == ''),
              )
              .map((n) => n.innerText);
    for (final link in links) {
      url = rssCanonical(link, source);
      if (url != null) {
        original = feedArticleUri((html.parseFragment(link).text ?? '').trim());
        break;
      }
    }
    if (url == null) {
      reason('missing-or-unapproved-link');
      continue;
    }
    final id = rssDigest(url.toString()),
        guid = field(entry, atom ? {'id'} : {'guid'});
    try {
      final title = rssPlain(field(entry, {'title'}));
      if (title.isEmpty || title.length > 500) {
        reason(title.isEmpty ? 'missing-title' : 'oversized-title');
        continue;
      }
      final isSyndicated = source.isSponsoredSyndication;
      final body = isSyndicated
          ? SyndicatedArticle.fromHtml(
              html: field(entry, atom ? {'summary'} : {'description'}),
              articleUrl: url,
              publisher: source.source.name,
              licenseUrl: source.source.rights.licenseUrl!,
            )
          : null;
      // Only publisher description/summary, never content:encoded or Atom content.
      final rawExcerpt = field(entry, atom ? {'summary'} : {'description'});
      // Do not sidestep full-metadata policy by truncating prior to inspection.
      // Only this entry is held if its metadata exceeds the parser work bound.
      if (!isSyndicated && rawExcerpt.length > 100000) {
        reason('oversized-entry-metadata');
        continue;
      }
      final policyExcerpt = isSyndicated ? '' : rssPlain(rawExcerpt);
      final excerpt =
          !isSyndicated &&
              !source.source.rights.images &&
              !source.preserveFeedText
          ? rssPlain(rawExcerpt, omitUnusedPhotoCaptions: true)
          : policyExcerpt;
      if (excerpt != policyExcerpt) {
        reason('unused-photo-caption-omitted', reject: false);
      }
      // Explicit article rights remain authoritative, including multiple
      // fields. Never discard them as optional image metadata.
      final rights = rssPlain(
        entry.childElements
            .where((n) => {'rights', 'copyright'}.contains(n.name.local))
            .map((n) => n.innerText)
            .join(' '),
      );
      var author = field(entry, {'creator', 'author'});
      if (atom) {
        author = entry.childElements
            .where((n) => n.name.local == 'author')
            .map((n) => field(n, {'name'}))
            .where((s) => s.isNotEmpty)
            .join(', ');
      }
      author = author.length > 100000 ? '' : rssPlain(author);
      if (author.length > 200) {
        author = '';
        reason('optional-byline-omitted', reject: false);
      }
      if (isSyndicated && author.isEmpty) author = source.source.name;
      final combined = '$title $excerpt'.toLowerCase();
      if (source.requiresAttribution && author.isEmpty) {
        reason('required-attribution-missing');
        continue;
      }
      if (isSyndicated
          ? !acceptsSyndicatedPromotion(title)
          : !allowsEditorialText(title, policyExcerpt)) {
        revoked.add(id);
        reason('policy-held');
        continue;
      }
      if (RegExp(
        r'\b(?:all rights reserved|third.party copyright|used (?:by|with) permission|courtesy of|getty images|associated press)\b',
        caseSensitive: false,
      ).hasMatch('$rights $excerpt')) {
        revoked.add(id);
        reason('rights-held');
        continue;
      }
      if (!source.enabled || !source.source.rights.titles) {
        reason('text-permission-missing');
        continue;
      }
      textEligible++;
      // Rights and safety withdrawals above apply to the story everywhere.
      // A section's topic mismatch only omits this source's candidate.
      if (source.requiredTopicTerms.isNotEmpty &&
          !source.requiredTopicTerms.any(
            (term) => RegExp(
              '\\b${RegExp.escape(term)}\\b',
              caseSensitive: false,
            ).hasMatch(combined),
          )) {
        reason('topic-mismatch');
        continue;
      }
      final published = rssDate(
        field(entry, atom ? {'published'} : {'pubDate', 'date'}),
        now.add(const Duration(days: 366)),
      );
      final updated = atom ? rssDate(field(entry, {'updated'}), now) : null;
      if (published != null &&
          (newestPublicationAt == null ||
              published.isAfter(newestPublicationAt))) {
        newestPublicationAt = published;
      }
      if (published != null &&
          published.isAfter(
            isSyndicated ? now : now.add(const Duration(hours: 24)),
          )) {
        reason('future-publication');
        continue;
      }
      if (published != null &&
          published.isBefore(now.subtract(const Duration(days: 30)))) {
        reason('publication-too-old');
        continue;
      }
      final topics = isSyndicated
          ? _featureTopics(title)
          : source.source.id == 'phys-org' &&
                entry.childElements.any(
                  (e) =>
                      e.name.local == 'category' &&
                      e.innerText == 'Economics & Business',
                )
          ? <String>{'business'}
          : source.source.id == 'phys-org'
          ? <String>{'science'}
          : source.source.id == 'nasa-technology' &&
                !(url.host == 'www.nasa.gov' &&
                    url.path.startsWith('/technology/'))
          ? <String>{'science'}
          : source.source.topics;
      // Contracts requiring unchanged excerpts allow omitting an optional
      // excerpt; they do not authorize truncating it or changing the headline.
      final displayExcerpt = source.preserveFeedText && excerpt.length > 1600
          ? ''
          : excerpt;
      if (displayExcerpt.isEmpty && excerpt.isNotEmpty) {
        reason('optional-excerpt-omitted', reject: false);
      }
      final item = LiveContentItem(
        id: id,
        sourceId: source.source.id,
        title: feedText(title, max: 500),
        canonicalUrl: url,
        originalUrl: original,
        outboundUrl: original,
        excerpt: source.source.rights.excerpts && displayExcerpt.isNotEmpty
            ? (source.preserveFeedText
                  ? feedText(displayExcerpt, max: 1600)
                  : rssPlain(displayExcerpt, limit: 1600))
            : null,
        excerptProvenance:
            source.source.rights.excerpts && displayExcerpt.isNotEmpty
            ? LiveExcerptProvenance(
                field: atom ? 'atom-summary' : 'rss-description',
                shortened: !source.preserveFeedText && excerpt.length > 1600,
              )
            : null,
        attribution: author.isEmpty ? null : author,
        publishedAt: published,
        updatedAt: updated,
        fetchedAt: now,
        language: source.source.language,
        topics: topics,
        rights: source.source.rights,
        eligibilityState: 'eligible',
        eligibilityBasis: 'curated-source-scope',
        eligibilityScope: source.eligibilityScope,
        reviewedAt: source.verifiedAt,
        expiresAt: now.add(Duration(seconds: source.retentionSeconds)),
        image: rssThumbnail(entry, source, url),
        syndicatedArticle: body,
        region: isSyndicated ? 'us' : null,
      );
      if (!eligibility.matchesTopicScope(
        item.title,
        item.excerpt ?? '',
        source.requiredTopicTerms,
      )) {
        reason('topic-mismatch');
        continue;
      }
      if (!eligibility.accepts(item, now: now)) {
        // Normalization/configuration/date failures are holds for this
        // representation, not publisher tombstones or permanent withdrawals.
        reason('eligibility-held');
        continue;
      }
      topicMatched++;
      if (eligibility.imageFor(item) != null) imagePermitted++;
      if (guid.isNotEmpty && guid.length <= 4096) guids[rssDigest(guid)] = id;
      if (!items.any((prior) => prior.id == id)) items.add(item);
    } catch (_) {
      reason('malformed-entry');
    }
  }
  return RssParsedFeed(
    items,
    guids,
    revoked,
    deleted,
    rejected,
    parsedEntries: entries.length,
    textEligible: textEligible,
    topicMatched: topicMatched,
    imagePermitted: imagePermitted,
    rejectionReasons: reasons,
    optionalFieldReasons: optionalReasons,
    newestPublicationAt: newestPublicationAt,
  );
}
