import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import '../design_system/ui_preferences.dart';
import '../live_content/live_story_image.dart';

@immutable
class DiscoveryPhoto {
  const DiscoveryPhoto({
    required this.artwork,
    required this.asset,
    required this.title,
    required this.credit,
    required this.alternativeText,
    required this.source,
    required this.license,
  });

  final HomeArtwork artwork;
  final String asset, title, credit, alternativeText, source, license;

  static const all = [
    DiscoveryPhoto(
      artwork: HomeArtwork.earthrise,
      asset: 'assets/discovery/earthrise.jpg',
      title: 'Earthrise',
      credit: 'NASA / Apollo 8',
      alternativeText:
          'Earth rises above the gray lunar horizon against black space.',
      source: 'science.nasa.gov/resource/image-earthrise/',
      license:
          'NASA image-use guidelines permit credited informational use. This photograph does not imply NASA endorsement of Wingman.',
    ),
    DiscoveryPhoto(
      artwork: HomeArtwork.forest,
      asset: 'assets/discovery/forest.jpg',
      title: 'Misty evergreen forest',
      credit: 'Le Mucky / Unsplash',
      alternativeText:
          'Green evergreen trees cover a hillside beneath soft mist.',
      source:
          'unsplash.com/photos/misty-evergreen-forest-on-a-cloudy-day-CSBE_qbKlY0',
      license:
          'Unsplash License. Free commercial and personal use. The photographs are not offered for resale or as a stock-image service.',
    ),
    DiscoveryPhoto(
      artwork: HomeArtwork.creative,
      asset: 'assets/discovery/creative.jpg',
      title: 'Pencils on blue table',
      credit: 'Joanna Kosinska / Unsplash',
      alternativeText:
          'Pencils, a ruler, clips and patterned tape on a deep blue work surface.',
      source: 'unsplash.com/photos/pencils-on-blue-table-7ACuHoezUYk',
      license:
          'Unsplash License. Free commercial and personal use. The photographs are not offered for resale or as a stock-image service.',
    ),
  ];

  static DiscoveryPhoto? forArtwork(HomeArtwork artwork) {
    for (final photo in all) {
      if (photo.artwork == artwork) return photo;
    }
    return null;
  }
}

/// Loads only the finite packaged asset catalog, never a remote fallback.
class DiscoveryPhotoView extends StatelessWidget {
  const DiscoveryPhotoView({
    super.key,
    required this.photo,
    this.decorative = false,
    this.fit = BoxFit.cover,
  });

  final DiscoveryPhoto photo;
  final bool decorative;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.asset(
    photo.asset,
    fit: fit,
    alignment: photo.artwork == HomeArtwork.creative
        ? Alignment.centerLeft
        : Alignment.center,
    semanticLabel: decorative ? null : photo.alternativeText,
    excludeFromSemantics: decorative,
    cacheWidth: 900,
    errorBuilder: (context, error, stack) => ColoredBox(
      color: WingmanTokens.of(context).raised,
      child: const Center(
        child: Icon(Icons.landscape_outlined, semanticLabel: 'Artwork'),
      ),
    ),
  );
}

/// Artwork has its own surface; no copy or controls are layered over the photo.
class HomeArtworkPanel extends StatelessWidget {
  const HomeArtworkPanel({super.key, required this.artwork});
  final HomeArtwork artwork;

  @override
  Widget build(BuildContext context) {
    final photo = DiscoveryPhoto.forArtwork(artwork);
    if (photo == null) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 144,
            width: double.infinity,
            child: DiscoveryPhotoView(photo: photo),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '${photo.title} · ${photo.credit}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoCreditsScreen extends StatelessWidget {
  const PhotoCreditsScreen({super.key});

  @override
  Widget build(BuildContext context) => WingmanPage(
    title: 'Photo credits',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'These photographs are packaged with Wingman. Viewing them makes no request to the photographer or an image service.',
        ),
        for (final photo in DiscoveryPhoto.all) ...[
          WingmanSection(title: photo.title),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: DiscoveryPhotoView(photo: photo),
            ),
          ),
          const SizedBox(height: 12),
          Text(photo.credit, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(photo.source),
          const SizedBox(height: 8),
          Text(photo.license),
        ],
        for (final photo in StoryImages.all.where(
          (image) => !DiscoveryPhoto.all.any((old) => old.asset == image.asset),
        )) ...[
          WingmanSection(title: photo.title),
          LiveStoryImage(image: photo, height: 180),
          const SizedBox(height: 12),
          Text(photo.caption, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(photo.sourceUrl.toString()),
          const SizedBox(height: 8),
          Text(photo.licenseLabel),
          Text(photo.licenseUrl.toString()),
          const SizedBox(height: 8),
          Text(photo.rightsNote),
        ],
        const SizedBox(height: 24),
        const Text(
          'Credits and usage notes describe the packaged files. Photographers and source organizations do not sponsor Wingman.',
        ),
      ],
    ),
  );
}
