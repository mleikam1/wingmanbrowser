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
