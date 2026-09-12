import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import '../design_system/ui_preferences.dart';
import '../discovery/discovery_photos.dart';

String liveContentTopicLabel(String topic) => topic
    .replaceAll('-', ' ')
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

String liveContentDate(DateTime value) {
  final date = value.toUtc();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}, '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} UTC';
}

String liveContentPublicationLabel(LiveContentItem item) =>
    item.publishedAt == null
    ? 'Date not supplied; fetched ${liveContentDate(item.fetchedAt)}'
    : 'Published ${liveContentDate(item.publishedAt!)}';

String liveContentSourceName(LiveContentController controller, String id) {
  for (final source in controller.sources) {
    if (source.id == id) return source.name;
  }
  return 'Saved publisher';
}

/// A finite section in the existing Home scroll view. No network artwork,
/// automatic pagination, or second scroll controller is introduced here.
class LiveContentSection extends StatefulWidget {
  const LiveContentSection({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onPin,
    required this.onPreferences,
    required this.onReadingList,
  });

  final LiveContentController? controller;
  final ValueChanged<LiveContentItem> onOpen, onPin;
  final VoidCallback onPreferences, onReadingList;

  @override
  State<LiveContentSection> createState() => _LiveContentSectionState();
}

class _LiveContentSectionState extends State<LiveContentSection> {
  bool _busy = false;
  String? _actionError;

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = 'This change could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return const WingmanStatus(
        title: 'Publisher updates unavailable',
        message:
            'The feed is not available in this session. Search and shortcuts still work.',
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _content(context, controller),
    );
  }

  Widget _content(BuildContext context, LiveContentController controller) {
    final topics = controller.availableTopics.toList()..sort();
    final enabled = controller.preferences.enabled;
    final items = controller.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'From your sources',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Publisher updates selected on this device.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('live-feed-refresh'),
              onPressed:
                  !enabled ||
                      !controller.configured ||
                      controller.refreshing ||
                      _busy
                  ? null
                  : () => _change(controller.refresh),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            TextButton.icon(
              key: const ValueKey('live-feed-preferences'),
              onPressed: widget.onPreferences,
              icon: const Icon(Icons.tune),
              label: const Text('Topics & sources'),
            ),
            TextButton.icon(
              key: const ValueKey('live-feed-reading-list'),
              onPressed: widget.onReadingList,
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('Reading list'),
            ),
          ],
        ),
        if (controller.refreshing) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          _freshness(controller),
          key: const ValueKey('live-feed-freshness'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (controller.error != null) ...[
          const SizedBox(height: 12),
          WingmanStatus(
            title: 'Refresh unavailable',
            message: controller.error!,
            tone: WingmanTone.caution,
          ),
        ],
        if (controller.storageError != null || _actionError != null) ...[
          const SizedBox(height: 12),
          WingmanStatus(
            title: 'Change not saved',
            message: controller.storageError ?? _actionError!,
            tone: WingmanTone.caution,
          ),
        ],
        if (!enabled) ...[
          const SizedBox(height: 12),
          const Text(
            'The feed is off. Saved articles remain in your reading list.',
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _change(() => controller.setEnabled(true)),
            child: const Text('Turn on feed'),
          ),
        ] else ...[
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('All topics'),
                  selected: controller.preferences.selectedTopics.isEmpty,
                  onSelected: _busy
                      ? null
                      : (_) => _change(() => controller.selectTopics({})),
                ),
                for (final topic in topics)
                  FilterChip(
                    key: ValueKey('live-topic-$topic'),
                    label: Text(liveContentTopicLabel(topic)),
                    selected: controller.preferences.selectedTopics.contains(
                      topic,
                    ),
                    onSelected: _busy
                        ? null
                        : (selected) {
                            final next = {
                              ...controller.preferences.selectedTopics,
                            };
                            selected ? next.add(topic) : next.remove(topic);
                            _change(() => controller.selectTopics(next));
                          },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (items.isEmpty && controller.initialized)
            WingmanEmptyState(
              icon: Icons.article_outlined,
              title: controller.configured
                  ? 'No updates match your choices'
                  : 'Live updates are not configured',
              message: controller.configured
                  ? 'Try another topic or follow a source. Refresh keeps usable cached articles when a source is unavailable.'
                  : 'A live feed service has not been connected. Search, shortcuts and your saved articles are still available.',
              action: TextButton(
                onPressed: widget.onPreferences,
                child: const Text('Review topics & sources'),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 580 &&
                      MediaQuery.textScalerOf(context).scale(16) < 24
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final item in items)
                    SizedBox(
                      key: ValueKey('live-card-${item.id}'),
                      width: width,
                      child: _card(context, controller, item),
                    ),
                ],
              );
            },
          ),
          if (controller.hasMore) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('live-feed-load-more'),
              onPressed: _busy ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more'),
            ),
          ] else if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'End of this selection.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }

  String _freshness(LiveContentController controller) {
    if (!controller.initialized) return 'Loading saved updates…';
    if (controller.fetchedAt == null) {
      return 'No feed snapshot is available yet.';
    }
    return '${controller.stale || !controller.configured ? 'Cached updates' : 'Snapshot from'} · '
        '${liveContentDate(controller.fetchedAt!)}';
  }

  Widget _card(
    BuildContext context,
    LiveContentController controller,
    LiveContentItem item,
  ) {
    final source = liveContentSourceName(controller, item.sourceId);
    final approvedSources = controller.sources.where(
      (value) => value.id == item.sourceId,
    );
    final credit = item.rights.attribution.isNotEmpty
        ? item.rights.attribution
        : approvedSources.isEmpty
        ? ''
        : approvedSources.first.rights.attribution;
    final saved = controller.isSaved(item.id),
        allowed = controller.canOpen(item);
    final artwork = item.topics.contains('environment')
        ? HomeArtwork.forest
        : item.topics.contains('technology')
        ? HomeArtwork.creative
        : item.topics.contains('science')
        ? HomeArtwork.earthrise
        : null;
    final photo = artwork == null ? null : DiscoveryPhoto.forArtwork(artwork);
    final topics = item.topics.toList()..sort();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo != null)
            SizedBox(
              height: 112,
              width: double.infinity,
              child: DiscoveryPhotoView(photo: photo, decorative: true),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        source,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    PopupMenuButton<String>(
                      key: ValueKey('live-menu-${item.id}'),
                      tooltip: 'Article options',
                      enabled: !_busy,
                      onSelected: (action) {
                        if (action == 'pin') {
                          if (controller.canOpen(item)) widget.onPin(item);
                        } else if (action == 'hide') {
                          _change(() => controller.hideSource(item.sourceId));
                        } else if (action == 'dismiss') {
                          _change(() => controller.dismiss(item.id));
                        } else if (action.startsWith('fewer:')) {
                          _change(
                            () =>
                                controller.showFewerTopic(action.substring(6)),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'pin',
                          enabled: allowed,
                          child: const Text('Add to Launchpad'),
                        ),
                        PopupMenuItem(
                          value: 'hide',
                          child: Text('Hide $source'),
                        ),
                        const PopupMenuItem(
                          value: 'dismiss',
                          child: Text('Dismiss item'),
                        ),
                        for (final topic in topics)
                          PopupMenuItem(
                            value: 'fewer:$topic',
                            child: Text(
                              'Show fewer: ${liveContentTopicLabel(topic)}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Text(
                  liveContentPublicationLabel(item),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (item.rights.excerpts &&
                    item.excerpt?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Publisher excerpt',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(item.excerpt!),
                ],
                if (credit.isNotEmpty && credit != source) ...[
                  const SizedBox(height: 8),
                  Text(credit, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (item.attribution?.isNotEmpty == true &&
                    item.attribution != credit &&
                    item.attribution != source) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.attribution!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (photo != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Category image · ${photo.credit}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!allowed) ...[
                  const SizedBox(height: 8),
                  const Text('This article is currently unavailable.'),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: ValueKey('live-open-${item.id}'),
                      onPressed: allowed
                          ? () {
                              if (controller.canOpen(item)) widget.onOpen(item);
                            }
                          : null,
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open'),
                    ),
                    TextButton.icon(
                      key: ValueKey('live-save-${item.id}'),
                      onPressed: !allowed || saved || _busy
                          ? null
                          : () => _change(() => controller.save(item)),
                      icon: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_add_outlined,
                      ),
                      label: Text(saved ? 'Saved' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
