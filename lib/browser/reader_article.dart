/// Legacy presentation DTO. Live-page extraction is unavailable in the
/// bundled-content milestone; no JavaScript extraction program is shipped.
class ReaderArticle {
  const ReaderArticle({
    required this.title,
    required this.text,
    required this.sourceUrl,
  });
  final String title;
  final String text;
  final String sourceUrl;
}
