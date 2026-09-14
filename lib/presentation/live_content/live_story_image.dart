import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';

/// Reviewed bundle artwork only. A feed-supplied image URL never reaches this
/// widget, including when a packaged asset fails to decode.
class LiveStoryImage extends StatelessWidget {
  const LiveStoryImage({
    super.key,
    required this.image,
    this.width,
    this.height = 168,
  });

  final StoryImage image;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Image.asset(
        image.asset,
        key: ValueKey('story-image-asset-${image.asset}'),
        fit: image.contain ? BoxFit.contain : BoxFit.cover,
        cacheWidth: width == null ? 900 : 264,
        semanticLabel: image.alternativeText,
        errorBuilder: (context, error, stack) => Semantics(
          label: 'Photo unavailable',
          child: ExcludeSemantics(
            child: ColoredBox(
              color: WingmanTokens.of(context).raised,
              child: const Center(
                child: Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class LiveStoryImageCaption extends StatelessWidget {
  const LiveStoryImageCaption({super.key, required this.image});
  final StoryImage image;

  @override
  Widget build(BuildContext context) =>
      Text(image.caption, style: Theme.of(context).textTheme.bodySmall);
}

/// Keep the headline's type and complete text when space is tight. Images stack
/// above it rather than competing with a large-text reading column.
class LiveStoryImageHeader extends StatelessWidget {
  const LiveStoryImageHeader({
    super.key,
    required this.image,
    required this.child,
  });
  final StoryImage image;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inline =
          constraints.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(16) < 24;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inline)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: child),
                const SizedBox(width: 12),
                LiveStoryImage(image: image, width: 88, height: 72),
              ],
            )
          else ...[
            LiveStoryImage(image: image, height: 112),
            const SizedBox(height: 8),
            child,
          ],
          const SizedBox(height: 8),
          LiveStoryImageCaption(image: image),
        ],
      );
    },
  );
}

/// The controller supplies already checked bytes. Building a card never starts
/// an image request, and a missing image never substitutes unrelated artwork.
class LivePublisherImageHeader extends StatelessWidget {
  const LivePublisherImageHeader({
    super.key,
    required this.image,
    required this.bytes,
    required this.child,
  });
  final LiveArticleImage image;
  final Uint8List? bytes;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final thumbnail = image.width > 0 && image.width <= 90;
      final inline =
          thumbnail &&
          constraints.maxWidth >= 270 &&
          MediaQuery.textScalerOf(context).scale(16) < 24;
      final visual = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: thumbnail ? 88 : double.infinity,
          height: thumbnail ? 88 : 192,
          child: bytes == null
              ? ColoredBox(color: WingmanTokens.of(context).raised)
              : LivePublisherImage(
                  bytes: bytes!,
                  key: ValueKey('live-publisher-image-${image.url}'),
                  fit: BoxFit.contain,
                  semanticLabel: image.caption,
                ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inline)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: child),
                const SizedBox(width: 14),
                visual,
              ],
            )
          else ...[
            visual,
            const SizedBox(height: 12),
            child,
          ],
          const SizedBox(height: 6),
          Text(image.credit, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    },
  );
}

/// Dispose decoded pixels with their presentation, including publisher images
/// whose HTTP response permits fresh display but forbids storage or reuse.
class LivePublisherImage extends StatefulWidget {
  const LivePublisherImage({
    super.key,
    required this.bytes,
    this.fit = BoxFit.contain,
    this.semanticLabel,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  State<LivePublisherImage> createState() => _LivePublisherImageState();
}

class _LivePublisherImageState extends State<LivePublisherImage> {
  late MemoryImage _image = MemoryImage(widget.bytes);

  @override
  void didUpdateWidget(LivePublisherImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _image.evict();
      _image = MemoryImage(widget.bytes);
    }
  }

  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _image,
    fit: widget.fit,
    semanticLabel: widget.semanticLabel,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
