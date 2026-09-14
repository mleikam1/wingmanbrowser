import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import 'live_content_section.dart';
import 'live_story_image.dart';

/// A native Flutter reader for explicitly licensed complete features. No WebView,
/// HTML widget, remote image widget or publisher JavaScript is instantiated.
class SyndicatedArticleScreen extends StatelessWidget {
  const SyndicatedArticleScreen({
    super.key,
    required this.item,
    required this.controller,
    required this.onOpenUri,
    required this.canContinue,
  });

  final LiveContentItem item;
  final LiveContentController controller;
  final ValueChanged<Uri> onOpenUri;
  final bool Function() canContinue;

  bool get _current =>
      canContinue() &&
      controller.context == LiveContentContext.owner &&
      controller.canOpen(item) &&
      item.syndicatedArticle?.articleUrl == item.canonicalUrl &&
      item.syndicatedArticle?.licenseUrl == item.rights.licenseUrl &&
      acceptsSyndicatedPromotion(item.title);

  void _open(Uri uri) {
    if (_current) onOpenUri(uri);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final article = item.syndicatedArticle;
      final visible = article != null && _current;
      return Scaffold(
        appBar: AppBar(title: const Text('Article')),
        body: SafeArea(
          top: false,
          child: !visible
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: WingmanStatus(
                    title: 'Feature unavailable',
                    message:
                        'This feature is not available in the current session.',
                  ),
                )
              : SelectionArea(
                  child: ListView(
                    key: const PageStorageKey('syndicated-article-scroll'),
                    padding: EdgeInsets.all(
                      WingmanTokens.gutter(MediaQuery.sizeOf(context).width),
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sponsored feature · ${article.publisher}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                item.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                liveContentPublicationLabel(item),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (item.attribution?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 8),
                                Text(item.attribution!),
                              ],
                              const SizedBox(height: 20),
                              _photo(context),
                              for (
                                var i = 0;
                                i < article.paragraphs.length;
                                i++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _ParagraphView(
                                    key: ValueKey('syndicated-paragraph-$i'),
                                    paragraph: article.paragraphs[i],
                                    onOpen: _open,
                                  ),
                                ),
                              const Divider(),
                              Text(
                                'Provided by ${article.publisher}.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (item.rights.attribution.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(item.rights.attribution),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    key: const ValueKey('syndicated-original'),
                                    onPressed: () => _open(article.articleUrl),
                                    icon: const Icon(Icons.open_in_browser),
                                    label: const Text(
                                      'Open original at publisher',
                                    ),
                                  ),
                                  TextButton(
                                    key: const ValueKey('syndicated-license'),
                                    onPressed: () => _open(article.licenseUrl),
                                    child: const Text('Syndication terms'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      );
    },
  );

  Widget _photo(BuildContext context) {
    final image = controller.imageFor(item);
    final bytes = controller.imageBytesFor(item);
    if (image == null || bytes == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              child: LivePublisherImage(
                bytes: bytes,
                key: const ValueKey('syndicated-approved-image'),
                fit: BoxFit.contain,
                semanticLabel: image.caption,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(image.credit, style: Theme.of(context).textTheme.bodySmall),
          if (image.caption.isNotEmpty)
            Text(image.caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ParagraphView extends StatefulWidget {
  const _ParagraphView({
    super.key,
    required this.paragraph,
    required this.onOpen,
  });
  final SyndicatedParagraph paragraph;
  final ValueChanged<Uri> onOpen;

  @override
  State<_ParagraphView> createState() => _ParagraphViewState();
}

class _ParagraphViewState extends State<_ParagraphView> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final theme = Theme.of(context);
    final paragraph = widget.paragraph;
    final spans = <InlineSpan>[];
    if (paragraph.marker != null) {
      spans.add(TextSpan(text: '${paragraph.marker} '));
    }
    for (final run in paragraph.runs) {
      TapGestureRecognizer? recognizer;
      if (run.link != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onOpen(run.link!);
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: run.text,
          recognizer: recognizer,
          style: TextStyle(
            fontWeight: run.bold ? FontWeight.w700 : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            fontFeatures: run.superscript
                ? const [FontFeature.superscripts()]
                : null,
            color: run.link == null ? null : theme.colorScheme.primary,
            decoration: run.link == null ? null : TextDecoration.underline,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: paragraph.kind == SyndicatedParagraphKind.heading
          ? theme.textTheme.titleLarge
          : theme.textTheme.bodyLarge?.copyWith(height: 1.55),
    );
  }
}
