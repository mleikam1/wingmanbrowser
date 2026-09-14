import 'dart:convert';
import 'dart:typed_data';
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
String rssPlain(String text, {int limit = 100000}) {
  if (text.length > 100000) throw const RssFailure('text-too-large');
  final fragment = html.parseFragment(text);
  fragment
      .querySelectorAll('script,style,iframe,svg,noscript,object,embed')
      .forEach((n) => n.remove());
  final value = (fragment.text ?? '')
      .replaceAll(
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return value.length <= limit
      ? value
      : '${value.substring(0, limit - 1).trimRight()}…';
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
    final query = <String, dynamic>{};
    if (uri.queryParametersAll.length > 40) return null;
    uri.queryParametersAll.forEach((key, values) {
      if (!key.toLowerCase().startsWith('utm_') &&
          !{
            'fbclid',
            'gclid',
            'mc_cid',
            'mc_eid',
          }.contains(key.toLowerCase())) {
        query[key] = values;
      }
    });
    // Uri.replace(null) retains the original component, and an empty fragment
    // serializes a trailing '#'. Build the canonical URI with absent components.
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    );
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
    this.rejected,
  );
  final List<LiveContentItem> items;
  final Map<String, String> guidToItem;
  final Set<String> revokedIds, deletedRefs;
  final int rejected;
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
  for (final node in entry.childElements) {
    if (node.namespaceUri != 'http://search.yahoo.com/mrss/' ||
        node.name.local != 'thumbnail') {
      continue;
    }
    try {
      final uri = feedArticleUri(node.getAttribute('url'));
      final width = int.tryParse(node.getAttribute('width') ?? ''),
          height = int.tryParse(node.getAttribute('height') ?? '');
      if (!policy.acceptsUri(uri) ||
          width == null ||
          height == null ||
          width < 1 ||
          height < 1 ||
          width > policy.maximumWidth ||
          height > policy.maximumHeight) {
        continue;
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
  final text = utf8.decode(bytes, allowMalformed: false);
  if (RegExp(
    r'<!\s*(?:DOCTYPE|ENTITY)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    throw const RssFailure('xml-declarations-forbidden');
  }
  var nodes = 0, depth = 0;
  for (final event in parseEvents(text)) {
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
  final root = XmlDocument.parse(text).rootElement;
  final atom =
      root.name.local == 'feed' &&
      root.namespaceUri == 'http://www.w3.org/2005/Atom';
  if (!atom && root.name.local != 'rss') {
    throw const RssFailure('unknown-feed-format');
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
  var rejected = 0;
  for (final node in root.descendantElements) {
    if (node.name.local == 'deleted-entry' &&
        node.namespaceUri == 'http://purl.org/atompub/tombstones/1.0') {
      final ref = node.getAttribute('ref');
      if (ref != null && ref.length <= 4096) deleted.add(rssDigest(ref));
    }
  }
  for (final entry in entries) {
    Uri? url;
    final links = atom
        ? entry.childElements
              .where(
                (n) =>
                    n.name.local == 'link' &&
                    (n.getAttribute('rel') ?? 'alternate') == 'alternate',
              )
              .map((n) => n.getAttribute('href') ?? '')
        : <String>[
            field(entry, {'link'}),
          ];
    for (final link in links) {
      url = rssCanonical(link, source);
      if (url != null) break;
    }
    if (url == null) {
      rejected++;
      continue;
    }
    final id = rssDigest(url.toString()),
        guid = field(entry, atom ? {'id'} : {'guid'});
    try {
      final title = rssPlain(field(entry, {'title'}));
      final isSyndicated =
          source.imagePolicy?.kind == 'syndicated-article-photo';
      final body = isSyndicated
          ? SyndicatedArticle.fromHtml(
              html: field(entry, atom ? {'summary'} : {'description'}),
              articleUrl: url,
              publisher: source.source.name,
              licenseUrl: source.source.rights.licenseUrl!,
            )
          : null;
      // Only publisher description/summary, never content:encoded or Atom content.
      final excerpt = isSyndicated
          ? ''
          : rssPlain(field(entry, atom ? {'summary'} : {'description'}));
      final rights = rssPlain(field(entry, {'rights', 'copyright'}));
      var author = field(entry, {'creator', 'author'});
      if (atom) {
        author = entry.childElements
            .where((n) => n.name.local == 'author')
            .map((n) => field(n, {'name'}))
            .where((s) => s.isNotEmpty)
            .join(', ');
      }
      author = rssPlain(author, limit: 200);
      if (isSyndicated && author.isEmpty) author = source.source.name;
      final combined = '$title $excerpt'.toLowerCase();
      if (title.isEmpty ||
          (source.requiresAttribution && author.isEmpty) ||
          (isSyndicated
              ? !acceptsSyndicatedPromotion(title)
              : !allowsEditorialText(title, excerpt)) ||
          RegExp(
            r'\b(?:all rights reserved|third.party copyright|used (?:by|with) permission|courtesy of|getty images|associated press)\b',
            caseSensitive: false,
          ).hasMatch('$rights $excerpt')) {
        revoked.add(id);
        rejected++;
        continue;
      }
      // Rights and safety withdrawals above apply to the story everywhere.
      // A section's topic mismatch only omits this source's candidate.
      if (source.requiredTopicTerms.isNotEmpty &&
          !source.requiredTopicTerms.any(
            (term) => RegExp(
              '\\b${RegExp.escape(term)}\\b',
              caseSensitive: false,
            ).hasMatch(combined),
          )) {
        rejected++;
        continue;
      }
      final published = rssDate(
        field(entry, atom ? {'published'} : {'pubDate', 'date'}),
        isSyndicated ? now.add(const Duration(days: 366)) : now,
      );
      if (isSyndicated && published != null && published.isAfter(now)) {
        rejected++;
        continue;
      }
      if (published != null &&
          published.isBefore(now.subtract(const Duration(days: 30)))) {
        rejected++;
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
      final item = LiveContentItem(
        id: id,
        sourceId: source.source.id,
        title: source.preserveFeedText
            ? feedText(title, max: 500)
            : rssPlain(title, limit: 200),
        canonicalUrl: url,
        excerpt: source.source.rights.excerpts && excerpt.isNotEmpty
            ? (source.preserveFeedText
                  ? feedText(excerpt, max: 1600)
                  : rssPlain(excerpt, limit: 400))
            : null,
        attribution: author.isEmpty ? null : author,
        publishedAt: published,
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
        rejected++;
        continue;
      }
      if (!eligibility.accepts(item, now: now)) {
        revoked.add(id);
        rejected++;
        continue;
      }
      if (guid.isNotEmpty && guid.length <= 4096) guids[rssDigest(guid)] = id;
      if (!items.any((prior) => prior.id == id)) items.add(item);
    } catch (_) {
      revoked.add(id);
      rejected++;
    }
  }
  return RssParsedFeed(items, guids, revoked, deleted, rejected);
}
