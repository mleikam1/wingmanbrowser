import 'models.dart';

/// A reviewed, packaged photograph. Feed data cannot supply its asset or rights.
class StoryImage {
  const StoryImage({
    required this.asset,
    required this.title,
    required this.credit,
    required this.alternativeText,
    required this.sourceUrl,
    required this.licenseUrl,
    required this.licenseLabel,
    required this.rightsNote,
    this.articleUrl,
    this.sourceId,
    this.contextLabel,
    this.contain = false,
  });
  final String asset, title, credit, alternativeText, sourceUrl;
  final String licenseUrl, licenseLabel, rightsNote;
  final String? articleUrl, sourceId, contextLabel;
  final bool contain;
  bool get isArticleSpecific => articleUrl != null && sourceId != null;
  String get caption =>
      '${contextLabel ?? (isArticleSpecific ? 'Story photo' : 'Topic photo')} · $credit';
}

/// Reviewed article photographs shared by Home, Updates and saved articles.
/// Images remain subject to the calling surface’s article eligibility checks.
abstract final class StoryImages {
  static const krakatau = StoryImage(
    asset: "assets/story_images/story_krakatau.jpg",
    title: "Anak Krakatau satellite image, 5 September 2026",
    credit: "NASA Earth Observatory / Michala Garrison; USGS Landsat data",
    alternativeText:
        "Satellite image from 5 September 2026 showing an ash plume above Anak Krakatau, with surrounding islands and sea.",
    sourceUrl:
        "https://science.nasa.gov/earth/earth-observatory/anak-krakatau-rumbles-again/",
    licenseUrl: "https://www.nasa.gov/nasa-brand-center/images-and-media/",
    licenseLabel: "NASA informational image use",
    rightsNote:
        "Reviewed NASA editorial image with named creator and USGS Landsat data. No third-party copyright notice accompanies this image. No endorsement implied. Publisher-supplied variant; displayed cropped to fit.",
    articleUrl:
        "https://science.nasa.gov/earth/earth-observatory/anak-krakatau-rumbles-again/",
    sourceId: "nasa-technology",
    contextLabel: "Story photo (5 Sep 2026)",
    contain: false,
  );
  static const zebraMussels = StoryImage(
    asset: "assets/story_images/story_zebra_mussels.jpg",
    title: "Zebra mussels, Lake Huron specimens, 1992",
    credit: "USGS / Amy Benson",
    alternativeText:
        "Archive photo of striped zebra-mussel shells collected from Lake Huron, photographed in 1992; not the Utah DNA sampling site.",
    sourceUrl: "https://www.usgs.gov/media/images/zebra-mussels",
    licenseUrl: "https://www.usgs.gov/media/images/zebra-mussels",
    licenseLabel: "Public Domain",
    rightsNote:
        "Individual USGS media page identifies Public Domain and Amy Benson credit. Lake Huron specimens photographed 14 March 1992, used in the linked Utah DNA story. No endorsement implied. Displayed cropped to fit.",
    articleUrl:
        "https://www.usgs.gov/centers/norock/news/environmental-dna-monitoring-leads-early-detection-invasive-zebra-mussel-dna",
    sourceId: "usgs-news",
    contextLabel: "Archive photo (Lake Huron, 1992)",
    contain: false,
  );
  static const maunaiki = StoryImage(
    asset: "assets/story_images/story_maunaiki.jpg",
    title: "Maunaiki eruption archive photographs, 1919–1920",
    credit: "USGS / Hawaiian Volcano Observatory; Thomas Jaggar",
    alternativeText:
        "Two historical black-and-white photographs of a steaming crack and lava channel at Maunaiki, taken in December 1919 and January 1920.",
    sourceUrl:
        "https://www.usgs.gov/media/images/photos-lead-and-eruption-1919-1920-maunaiki-shield-southwest-rift-zone-kilauea",
    licenseUrl:
        "https://www.usgs.gov/media/images/photos-lead-and-eruption-1919-1920-maunaiki-shield-southwest-rift-zone-kilauea",
    licenseLabel: "Public Domain",
    rightsNote:
        "Individual USGS media page identifies Public Domain and Thomas Jaggar credit. Photographs from 22 December 1919 and 14 January 1920. Both panels retained without cropping; no endorsement implied.",
    articleUrl:
        "https://www.usgs.gov/observatories/hvo/news/volcano-watch-remembering-1919-1920-maunaiki-eruption-kilauea",
    sourceId: "usgs-news",
    contextLabel: "Archive photos (1919–1920)",
    contain: true,
  );

  static const garmentWorkers = StoryImage(
    asset: "assets/story_images/story_garment_workers.webp",
    title: "Garment workers in Gazipur, Bangladesh, 2015",
    credit: "Solidarity Center · CC BY 2.0",
    alternativeText:
        "Garment workers at sewing machines in a factory in Gazipur, Bangladesh, photographed in 2015.",
    sourceUrl: "https://www.flickr.com/photos/62762640@N02/29010292884",
    licenseUrl: "https://creativecommons.org/licenses/by/2.0/",
    licenseLabel: "CC BY 2.0",
    rightsNote:
        "Original title: Bangladesh.Gazipur BIGUF.2015.Solidarity Center. Actual lead image used by the linked Global Voices article. Original documentary photograph dated 18 November 2015, licensed CC BY 2.0 by Solidarity Center. Publisher-cropped rendition, displayed cropped to fit. No endorsement implied.",
    articleUrl:
        "https://globalvoices.org/2026/09/04/maternity-leave-is-expanding-in-bangladesh-but-garment-workers-still-struggle-for-childcare/",
    sourceId: "globalvoices-fashion",
    contextLabel: "Archive photo (2015)",
  );

  static const all = <StoryImage>[
    krakatau,
    zebraMussels,
    maunaiki,
    garmentWorkers,
  ];

  /// Exact association only: unknown or new articles stay text-only. Neither
  /// feed image URLs nor topic artwork can become a story photograph.
  static StoryImage? forItem(LiveContentItem item) {
    for (final image in all) {
      if (image.sourceId == item.sourceId &&
          image.articleUrl == item.canonicalUrl.toString()) {
        return image;
      }
    }
    return null;
  }
}
