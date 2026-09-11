import 'package:flutter/material.dart';

import '../components/wingman_components.dart';
import '../design_system/ui_preferences.dart';
import 'discovery_photos.dart';

/// Display data and a caller-owned action. Artwork never establishes approval.
@immutable
class VisualDiscoveryDestination {
  const VisualDiscoveryDestination({
    required this.id,
    required this.title,
    required this.description,
    required this.kindLabel,
    required this.artwork,
    this.onOpen,
    this.unavailableReason,
  });

  final String id, title, description, kindLabel;
  final HomeArtwork artwork;
  final VoidCallback? onOpen;
  final String? unavailableReason;
}

class VisualDiscoverySection extends StatelessWidget {
  const VisualDiscoverySection({super.key, required this.destinations});

  final List<VisualDiscoveryDestination> destinations;

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'A little inspiration',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Explore something that interests you, with your ground rules in place.',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
            final columns = constraints.maxWidth >= 580 && !largeText ? 2 : 1;
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final destination in destinations.take(6))
                  SizedBox(
                    key: ValueKey('discovery-${destination.id}'),
                    width: width,
                    child: _DiscoveryCard(destination: destination),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const PhotoCreditsScreen()),
          ),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Photo credits'),
        ),
      ],
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({required this.destination});
  final VisualDiscoveryDestination destination;

  @override
  Widget build(BuildContext context) {
    final photo = DiscoveryPhoto.forArtwork(destination.artwork);
    final theme = Theme.of(context), colors = WingmanTokens.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo != null)
            SizedBox(
              height: 144,
              width: double.infinity,
              child: DiscoveryPhotoView(photo: photo),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.kindLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.action,
                  ),
                ),
                const SizedBox(height: 8),
                Text(destination.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(destination.description),
                if (photo != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Photo: ${photo.credit}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (destination.onOpen == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    destination.unavailableReason ??
                        'This destination is unavailable in this session.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: destination.onOpen,
                  icon: Icon(
                    destination.onOpen == null
                        ? Icons.lock_outline
                        : Icons.arrow_forward,
                  ),
                  label: Text(
                    destination.onOpen == null ? 'Unavailable' : 'Explore',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
