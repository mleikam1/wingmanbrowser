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

/// A finite section. Home uses a three-item preview; the full feed expands only
/// after an explicit action. Artwork comes only from the packaged catalog.
class LiveContentSection extends StatefulWidget {
  const LiveContentSection({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onPin,
    required this.onPreferences,
    required this.onReadingList,
    this.preview = false,
    this.onViewAll,
    this.canContinue,
    this.onOpenUri,
    this.showHeading = true,
    this.showTopics = true,
    this.showActions = true,
  });
  final LiveContentController? controller;
  final ValueChanged<LiveContentItem> onOpen, onPin;
  final VoidCallback onPreferences, onReadingList;
  final bool preview, showHeading, showTopics, showActions;
  final VoidCallback? onViewAll;
  final bool Function()? canContinue;
  final ValueChanged<Uri>? onOpenUri;

  @override
  State<LiveContentSection> createState() => _LiveContentSectionState();
}

class _LiveContentSectionState extends State<LiveContentSection> {
  bool _busy = false;
  String? _actionError;
  bool get _current =>
      mounted &&
      widget.controller?.context == LiveContentContext.owner &&
      (widget.canContinue?.call() ?? true);

  VoidCallback? _action(VoidCallback? action) => action == null || !_current
      ? null
      : () {
          if (_current) action();
        };

  Future<void> _change(Future<void> Function() action) async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && _current) {
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
    final enabled = controller.preferences.enabled;
    final items = widget.preview
        ? controller.items.take(3).toList()
        : controller.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeading) ...[
          WingmanSection(
            title: 'Publisher updates',
            action: widget.preview && widget.onViewAll != null
                ? TextButton(
                    key: const ValueKey('live-feed-view-all'),
                    onPressed: _action(widget.onViewAll),
                    child: const Text('View all'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
        ],
        if (widget.showActions && !widget.preview)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _refresh(controller),
              TextButton.icon(
                key: const ValueKey('live-feed-preferences'),
                onPressed: _action(widget.onPreferences),
                icon: const Icon(Icons.tune),
                label: const Text('Topics & sources'),
              ),
              TextButton.icon(
                key: const ValueKey('live-feed-reading-list'),
                onPressed: _action(widget.onReadingList),
                icon: const Icon(Icons.bookmarks_outlined),
                label: const Text('Reading list'),
              ),
            ],
          ),
        if (!widget.showActions && !widget.preview) _refresh(controller),
        if (controller.refreshing) const LinearProgressIndicator(),
        Text(
          _freshness(controller),
          key: const ValueKey('live-feed-freshness'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!widget.preview) ...[
          const SizedBox(height: 8),
          Text(
            'Public feeds load directly from publishers, who can see your IP address. Topic choices and browsing history stay on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
            onPressed: _busy || !_current
                ? null
                : () => _change(() => controller.setEnabled(true)),
            child: const Text('Turn on feed'),
          ),
        ] else ...[
          if (widget.showTopics && !widget.preview) ...[
            const SizedBox(height: 16),
            LiveContentTopicBar(
              controller: controller,
              canContinue: () => _current,
            ),
          ],
          const SizedBox(height: 12),
          if (items.isEmpty && controller.initialized)
            WingmanEmptyState(
              icon: Icons.article_outlined,
              title: controller.configured
                  ? 'No updates match your choices'
                  : 'Live updates are not configured',
              message: controller.configured
                  ? 'No eligible articles are available for this selection right now. Try another topic or review your sources.'
                  : 'A live feed service has not been connected. Search, shortcuts and your saved articles are still available.',
              action: TextButton(
                onPressed: _action(widget.onPreferences),
                child: const Text('Review topics & sources'),
              ),
            ),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            _card(
              context,
              controller,
              items[index],
              featured: !widget.preview && index == 0,
            ),
          ],
          if (!widget.preview && controller.hasMore) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('live-feed-load-more'),
              onPressed: _busy || !_current ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more'),
            ),
          ] else if (!widget.preview && items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'End of this selection.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
        if (widget.preview)
          TextButton.icon(
            key: const ValueKey('live-feed-reading-list'),
            onPressed: _action(widget.onReadingList),
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Reading list'),
          ),
      ],
    );
  }

  Widget _refresh(LiveContentController controller) => TextButton.icon(
    key: const ValueKey('live-feed-refresh'),
    onPressed:
        !_current ||
            !controller.preferences.enabled ||
            !controller.configured ||
            controller.refreshing ||
            _busy
        ? null
        : () => _change(controller.refresh),
    icon: const Icon(Icons.refresh),
    label: const Text('Refresh'),
  );

  String _freshness(LiveContentController controller) {
    if (!controller.initialized) return 'Loading saved updates…';
    if (controller.fetchedAt == null) {
      return 'Updates haven’t loaded yet.';
    }
    return '${controller.stale || !controller.configured ? 'Cached updates' : 'Last checked'} · ${liveContentDate(controller.fetchedAt!)}';
  }

  Widget _card(
    BuildContext context,
    LiveContentController controller,
    LiveContentItem item, {
    required bool featured,
  }) {
    final source = liveContentSourceName(controller, item.sourceId);
    final saved = controller.isSaved(item.id),
        allowed = _current && controller.canOpen(item);
    final artwork = item.topics.contains('environment')
        ? HomeArtwork.forest
        : item.topics.contains('technology')
        ? HomeArtwork.creative
        : item.topics.contains('science')
        ? HomeArtwork.earthrise
        : null;
    final photo = artwork == null ? null : DiscoveryPhoto.forArtwork(artwork);
    final topics = item.topics.toList()..sort();
    void open() {
      if (_current && controller.canOpen(item)) widget.onOpen(item);
    }

    final excerpt = item.excerpt ?? '';
    final excerptLimit = featured ? 480 : 180;
    final shortened = excerpt.characters.length > excerptLimit;
    final visibleExcerpt = shortened
        ? '${excerpt.characters.take(excerptLimit).toString().trimRight()}…'
        : excerpt;
    final headline = TextButton(
      key: ValueKey(
        '${widget.preview ? 'live-open' : 'live-title'}-${item.id}',
      ),
      onPressed: allowed ? open : null,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
        foregroundColor: WingmanTokens.of(context).text,
      ),
      child: Text(
        item.title,
        style: featured
            ? Theme.of(context).textTheme.titleLarge
            : Theme.of(context).textTheme.titleMedium,
      ),
    );
    final saveButton = TextButton.icon(
      key: ValueKey('live-save-${item.id}'),
      onPressed: !allowed || saved || _busy
          ? null
          : () => _change(() => controller.save(item)),
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_add_outlined),
      label: Text(saved ? 'Saved' : 'Save'),
    );
    return Card(
      key: ValueKey('live-card-${item.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (featured && photo != null) ...[
            SizedBox(
              height: 144,
              width: double.infinity,
              child: DiscoveryPhotoView(photo: photo, decorative: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Category image · ${photo.credit}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          if (widget.preview) headline,
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      key: ValueKey('live-menu-${item.id}'),
                      tooltip: 'Article options',
                      enabled: !_busy && _current,
                      onSelected: (action) {
                        if (!_current) return;
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
                if (!widget.preview)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: headline),
                      if (!featured &&
                          MediaQuery.textScalerOf(context).scale(16) < 24) ...[
                        const SizedBox(width: 12),
                        ExcludeSemantics(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: WingmanTokens.of(context).raised,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              liveContentTopicIcon(topics.firstOrNull),
                              color: WingmanTokens.of(context).action,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                Text(
                  liveContentPublicationLabel(item),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!widget.preview &&
                    item.rights.excerpts &&
                    visibleExcerpt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    shortened
                        ? 'Publisher excerpt · shortened'
                        : 'Publisher excerpt',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(visibleExcerpt),
                ],
                const SizedBox(height: 8),
                LiveContentCredits(
                  controller: controller,
                  item: item,
                  onOpenUri: widget.onOpenUri,
                  canContinue: () => _current,
                  actions: widget.preview ? [saveButton] : const [],
                ),
                if (!allowed)
                  const Text('This article is currently unavailable.'),
                if (!widget.preview) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        key: ValueKey('live-open-${item.id}'),
                        onPressed: allowed ? open : null,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Open'),
                      ),
                      saveButton,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData liveContentTopicIcon(String? topic) => switch (topic) {
  'sports' => Icons.sports_basketball_outlined,
  'entertainment' => Icons.theaters_outlined,
  'technology' => Icons.memory_outlined,
  'business' => Icons.business_center_outlined,
  'fashion' => Icons.checkroom_outlined,
  'science' => Icons.science_outlined,
  'food' => Icons.restaurant_outlined,
  'health' => Icons.favorite_outline,
  'environment' => Icons.eco_outlined,
  _ => Icons.article_outlined,
};

/// Fast single-topic selection. The catalog remains visible even when a topic
/// temporarily has no eligible stories; empty content is stated honestly.
class LiveContentTopicBar extends StatefulWidget {
  const LiveContentTopicBar({
    super.key,
    required this.controller,
    required this.canContinue,
  });
  final LiveContentController controller;
  final bool Function() canContinue;
  @override
  State<LiveContentTopicBar> createState() => _LiveContentTopicBarState();
}

class _LiveContentTopicBarState extends State<LiveContentTopicBar> {
  bool _busy = false;
  Future<void> _select(String? topic) async {
    if (_busy || !widget.canContinue()) return;
    setState(() => _busy = true);
    try {
      await widget.controller.selectTopics(topic == null ? {} : {topic});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => SingleChildScrollView(
      key: const ValueKey('live-topic-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final topic in <String?>[
            null,
            ...liveContentTopicOrder.where((topic) => topic != 'headlines'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey(
                  topic == null ? 'live-topic-headlines' : 'live-topic-$topic',
                ),
                label: Text(
                  topic == null ? 'Headlines' : liveContentTopicLabel(topic),
                ),
                selected: topic == null
                    ? widget.controller.preferences.selectedTopics.isEmpty
                    : widget.controller.preferences.selectedTopics.length ==
                              1 &&
                          widget.controller.preferences.selectedTopics.contains(
                            topic,
                          ),
                onSelected: _busy || !widget.canContinue()
                    ? null
                    : (_) => _select(topic),
              ),
            ),
        ],
      ),
    ),
  );
}

class LiveContentCredits extends StatelessWidget {
  const LiveContentCredits({
    super.key,
    required this.controller,
    required this.item,
    this.onOpenUri,
    this.canContinue,
    this.actions = const [],
  });
  final LiveContentController controller;
  final LiveContentItem item;
  final ValueChanged<Uri>? onOpenUri;
  final bool Function()? canContinue;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final approved = controller.sources
        .where((source) => source.id == item.sourceId)
        .firstOrNull;
    final source = approved?.name ?? 'Publisher';
    final credit = item.rights.attribution.isNotEmpty
        ? item.rights.attribution
        : approved?.rights.attribution ?? '';
    // Only the locally approved source license may create a navigation action.
    final license = approved?.rights.licenseUrl;
    final canOpen =
        onOpenUri != null &&
        license != null &&
        (canContinue?.call() ?? true) &&
        controller.canOpen(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.attribution?.isNotEmpty == true &&
            item.attribution != source &&
            item.attribution != credit)
          Text(item.attribution!, style: Theme.of(context).textTheme.bodySmall),
        if (credit.isNotEmpty && credit != source)
          Text(credit, style: Theme.of(context).textTheme.bodySmall),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (license != null)
              canOpen
                  ? TextButton(
                      onPressed: () {
                        if ((canContinue?.call() ?? true) &&
                            controller.canOpen(item)) {
                          onOpenUri!(license);
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(
                        license.host == 'creativecommons.org'
                            ? 'License · ${license.path.contains('/by/3.0') ? 'CC BY 3.0' : 'Creative Commons'}'
                            : 'Source rights',
                      ),
                    )
                  : Text(
                      license.toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ...actions,
          ],
        ),
      ],
    );
  }
}
