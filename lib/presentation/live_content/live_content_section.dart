import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import 'live_story_image.dart';
import 'live_story_excerpt.dart';
import 'publisher_identity.dart';

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

String liveContentShortDate(DateTime value) {
  final elapsed = DateTime.now().toUtc().difference(value.toUtc());
  if (elapsed.isNegative) return 'Just published';
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
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
  final date = value.toLocal();
  return '${months[date.month - 1]} ${date.day}';
}

String liveContentSourceName(LiveContentController controller, String id) {
  for (final source in controller.sources) {
    if (source.id == id) return source.name;
  }
  return 'Saved publisher';
}

String? liveContentPermittedExcerpt(
  LiveContentController controller,
  LiveContentItem item,
) {
  final approved = controller.eligibility.registry.sources[item.sourceId];
  final excerpt = item.excerpt;
  return controller.canOpen(item) &&
          approved?.source.rights.excerpts == true &&
          item.rights.excerpts &&
          excerpt != null &&
          excerpt.trim().isNotEmpty
      ? excerpt
      : null;
}

/// A finite section. Home uses a three-item preview; the full feed expands only
/// after an explicit action. Images require the controller's source approval.
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
            title: 'Discover',
            action: widget.preview && widget.onViewAll != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('live-feed-reading-list'),
                        tooltip: 'Reading list',
                        onPressed: _action(widget.onReadingList),
                        icon: const Icon(Icons.bookmarks_outlined, size: 20),
                      ),
                      TextButton(
                        key: const ValueKey('live-feed-view-all'),
                        onPressed: _action(widget.onViewAll),
                        child: const Text('See all'),
                      ),
                    ],
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
        if (controller.refreshing || controller.imagesLoading)
          const LinearProgressIndicator(),
        if (!widget.preview)
          Row(
            children: [
              Expanded(
                child: Text(
                  _freshness(controller),
                  key: const ValueKey('live-feed-freshness'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (!widget.showActions) _refresh(controller),
            ],
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
          if (items.isEmpty && controller.imagesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Loading story images…'),
            )
          else if (items.isEmpty && controller.initialized)
            WingmanEmptyState(
              icon: Icons.article_outlined,
              title: controller.configured
                  ? 'No updates match your choices'
                  : 'Live updates are not configured',
              message: controller.configured
                  ? 'No stories with available images match this selection right now. Check your connection, try another topic or review your sources. Saved articles remain in your reading list.'
                  : 'A live feed service has not been connected. Search, shortcuts and your saved articles are still available.',
              action: TextButton(
                onPressed: _action(widget.onPreferences),
                child: const Text('Review topics & sources'),
              ),
            ),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            _card(context, controller, items[index], featured: index == 0),
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
    return '${controller.stale || !controller.configured ? 'Saved updates' : 'Updated'} ${liveContentShortDate(controller.fetchedAt!)}';
  }

  Widget _card(
    BuildContext context,
    LiveContentController controller,
    LiveContentItem item, {
    required bool featured,
  }) {
    final source = liveContentSourceName(controller, item.sourceId);
    final approved = controller.eligibility.registry.sources[item.sourceId];
    final saved = controller.isSaved(item.id),
        allowed = _current && controller.canOpen(item);
    final storyImage = allowed ? StoryImages.forItem(item) : null;
    final topics = item.topics.toList()..sort();
    void open() {
      if (_current && controller.canOpen(item)) widget.onOpen(item);
    }

    final remoteImage = allowed ? controller.imageFor(item) : null;
    final remoteBytes = allowed ? controller.imageBytesFor(item) : null;
    final hero = featured && storyImage != null;
    final theme = Theme.of(context);
    final colors = WingmanTokens.of(context);
    final excerpt = allowed
        ? liveContentPermittedExcerpt(controller, item)
        : null;
    final headline = TextButton(
      key: ValueKey(
        '${widget.preview ? 'live-open' : 'live-title'}-${item.id}',
      ),
      onPressed: allowed ? open : null,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 44),
        alignment: Alignment.centerLeft,
        foregroundColor: colors.text,
        textStyle:
            (hero ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
      ),
      child: Text(item.title),
    );
    final saveButton = IconButton(
      key: ValueKey('live-save-${item.id}'),
      tooltip: saved ? 'Saved to reading list' : 'Save article',
      onPressed: !allowed || saved || _busy
          ? null
          : () => _change(() => controller.save(item)),
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 21),
      color: saved ? colors.action : colors.secondaryText,
    );
    final menu = PopupMenuButton<String>(
      key: ValueKey('live-menu-${item.id}'),
      tooltip: 'Article options',
      enabled: !_busy && _current,
      onSelected: (action) {
        if (!_current) return;
        if (action == 'details') {
          _details(controller, item);
        } else if (action == 'pin') {
          if (controller.canOpen(item)) widget.onPin(item);
        } else if (action == 'hide') {
          _change(() => controller.hideSource(item.sourceId));
        } else if (action == 'dismiss') {
          _change(() => controller.dismiss(item.id));
        } else if (action.startsWith('fewer:')) {
          _change(() => controller.showFewerTopic(action.substring(6)));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'details', child: Text('About this story')),
        PopupMenuItem(
          value: 'pin',
          enabled: allowed,
          child: const Text('Add to Launchpad'),
        ),
        PopupMenuItem(value: 'hide', child: Text('Hide $source')),
        const PopupMenuItem(value: 'dismiss', child: Text('Dismiss item')),
        for (final topic in topics)
          PopupMenuItem(
            value: 'fewer:$topic',
            child: Text('Show fewer: ${liveContentTopicLabel(topic)}'),
          ),
      ],
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LivePublisherIdentity(
          name: source,
          sponsored: item.syndicatedArticle != null,
          branding: allowed && controller.preferences.enabled
              ? approved?.branding
              : null,
        ),
        const SizedBox(height: 4),
        headline,
        if (excerpt != null)
          LiveStoryExcerpt(
            key: ValueKey('live-excerpt-${item.id}'),
            text: excerpt,
          ),
        if (item.attribution?.isNotEmpty == true && item.attribution != source)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(item.attribution!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
    return Card(
      key: ValueKey('live-card-${item.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hero) ...[
            LiveStoryImage(image: storyImage, height: 192),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: LiveStoryImageCaption(image: storyImage),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (remoteImage != null)
                  LivePublisherImageHeader(
                    image: remoteImage,
                    bytes: remoteBytes,
                    child: titleBlock,
                  )
                else if (!hero && storyImage != null)
                  LiveStoryImageHeader(image: storyImage, child: titleBlock)
                else
                  titleBlock,
                if (!allowed)
                  const Text('This article is currently unavailable.'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (topics.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          topics.map(liveContentTopicLabel).join(' · '),
                          key: ValueKey('live-category-${item.id}'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                    Tooltip(
                      message: liveContentPublicationLabel(item),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          item.publishedAt == null
                              ? 'Date unavailable'
                              : liveContentShortDate(item.publishedAt!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.preview)
                      TextButton(
                        key: ValueKey('live-open-${item.id}'),
                        onPressed: allowed ? open : null,
                        child: const Text('Read story'),
                      ),
                    saveButton,
                    menu,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _details(LiveContentController controller, LiveContentItem item) {
    if (!_current || !controller.canOpen(item)) return;
    showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => AlertDialog(
          title: const Text('About this story'),
          scrollable: true,
          content: !_current || !controller.canOpen(item)
              ? const Text('This story is unavailable in this session.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(liveContentPublicationLabel(item)),
                    if (liveContentPermittedExcerpt(controller, item) !=
                        null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Publisher excerpt',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(item.excerpt!),
                    ],
                    const SizedBox(height: 16),
                    LiveContentCredits(
                      controller: controller,
                      item: item,
                      onOpenUri: widget.onOpenUri,
                      canContinue: () => _current,
                    ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

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
