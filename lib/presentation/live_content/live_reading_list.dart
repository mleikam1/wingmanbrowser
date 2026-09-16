import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import 'live_content_section.dart';
import 'live_story_image.dart';
import 'live_story_excerpt.dart';
import 'publisher_identity.dart';

/// Box content for Library's SliverToBoxAdapter; Library owns scrolling.
class LiveReadingList extends StatefulWidget {
  const LiveReadingList({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onPin,
    required this.canContinue,
    this.onOpenUri,
  });
  final LiveContentController controller;
  final ValueChanged<LiveContentItem> onOpen, onPin;
  final bool Function() canContinue;
  final ValueChanged<Uri>? onOpenUri;

  @override
  State<LiveReadingList> createState() => _LiveReadingListState();
}

class _LiveReadingListState extends State<LiveReadingList> {
  bool _busy = false;
  String? _error;

  Future<void> _remove(String id) async {
    if (_busy || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.unsave(id);
    } catch (_) {
      if (mounted && widget.canContinue()) {
        setState(() => _error = 'The article could not be removed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final entries = controller.savedItems;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WingmanSection(title: 'Saved publisher articles'),
          const Text(
            'Keep stories to read again. Publisher links open online; syndicated features include the supplied article.',
          ),
          if (entries.isEmpty)
            const WingmanEmptyState(
              icon: Icons.bookmark_border,
              title: 'No publisher articles saved',
              message:
                  'Use Save on a Home feed card to keep its publisher link here.',
            ),
          for (final saved in entries) ...[
            const SizedBox(height: 12),
            Card(
              key: ValueKey('live-saved-${saved.id}'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _entry(context, controller, saved),
              ),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (controller.storageError != null || _error != null) ...[
            const SizedBox(height: 12),
            WingmanStatus(
              title: 'Change not saved',
              message: controller.storageError ?? _error!,
              tone: WingmanTone.caution,
            ),
          ],
        ],
      );
    },
  );

  Widget _entry(
    BuildContext context,
    LiveContentController controller,
    LiveSavedItem saved,
  ) {
    final item = saved.item;
    final allowed =
        widget.canContinue() && item != null && controller.canOpen(item);
    final savedLinkAllowed =
        widget.canContinue() && controller.canOpenSavedLink(saved);
    final storyImage = allowed ? StoryImages.forItem(item) : null;
    final publisherImage = allowed ? controller.imageFor(item) : null;
    final approved = controller.eligibility.registry.sources[saved.sourceId];
    final excerpt = allowed
        ? liveContentPermittedExcerpt(controller, item)
        : null;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LivePublisherIdentity(
          name:
              item?.publisherName ??
              saved.linkUrl?.host ??
              liveContentSourceName(controller, saved.sourceId),
          sponsored: item?.syndicatedArticle != null,
          branding: allowed && controller.preferences.enabled
              ? approved?.branding
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          item?.title ??
              saved.linkUrl?.toString() ??
              'Saved article unavailable',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (excerpt != null)
          LiveStoryExcerpt(
            key: ValueKey('live-saved-excerpt-${saved.id}'),
            text: excerpt,
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (publisherImage != null)
          LivePublisherImageHeader(
            image: publisherImage,
            bytes: controller.imageBytesFor(item!),
            child: header,
          )
        else if (storyImage != null)
          LiveStoryImageHeader(image: storyImage, child: header)
        else
          header,
        const SizedBox(height: 8),
        Text(
          item == null
              ? 'Saved ${liveContentDate(saved.savedAt)}'
              : liveContentPublicationLabel(item),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (item != null && allowed) ...[
          const SizedBox(height: 8),
          LiveContentCredits(
            controller: controller,
            item: item,
            onOpenUri: widget.onOpenUri,
            canContinue: widget.canContinue,
          ),
        ],
        if ((item == null || !allowed) && !savedLinkAllowed) ...[
          const SizedBox(height: 8),
          Text(
            saved.unavailableReason ??
                'This article is unavailable under the current content or navigation policy.',
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: ValueKey('live-saved-open-${saved.id}'),
              onPressed: allowed
                  ? () {
                      if (widget.canContinue() && controller.canOpen(item)) {
                        widget.onOpen(item);
                      }
                    }
                  : savedLinkAllowed && widget.onOpenUri != null
                  ? () {
                      if (widget.canContinue() &&
                          controller.canOpenSavedLink(saved)) {
                        widget.onOpenUri!(saved.linkUrl!);
                      }
                    }
                  : null,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open'),
            ),
            TextButton.icon(
              key: ValueKey('live-saved-pin-${saved.id}'),
              onPressed: allowed
                  ? () {
                      if (widget.canContinue() && controller.canOpen(item)) {
                        widget.onPin(item);
                      }
                    }
                  : null,
              icon: const Icon(Icons.add_link),
              label: const Text('Add to Launchpad'),
            ),
            TextButton.icon(
              key: ValueKey('live-saved-remove-${saved.id}'),
              onPressed: _busy || !widget.canContinue()
                  ? null
                  : () => _remove(saved.id),
              icon: const Icon(Icons.bookmark_remove_outlined),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}
