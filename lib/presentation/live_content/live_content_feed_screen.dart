import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import 'live_content_section.dart';

/// An owned feature route: category controls remain reachable while the finite
/// article list scrolls. No timer, carousel advancement or scroll fetch exists.
class LiveContentFeedScreen extends StatefulWidget {
  const LiveContentFeedScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onPin,
    required this.onPreferences,
    required this.onReadingList,
    required this.canContinue,
    this.onOpenUri,
    this.initialScrollOffset = 0,
    this.onScrollOffsetChanged,
  });
  final LiveContentController controller;
  final ValueChanged<LiveContentItem> onOpen, onPin;
  final ValueChanged<Uri>? onOpenUri;
  final VoidCallback onPreferences, onReadingList;
  final bool Function() canContinue;
  final double initialScrollOffset;
  final ValueChanged<double>? onScrollOffsetChanged;

  @override
  State<LiveContentFeedScreen> createState() => _LiveContentFeedScreenState();
}

class _LiveContentFeedScreenState extends State<LiveContentFeedScreen> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.initialScrollOffset,
    keepScrollOffset: false,
  )..addListener(_rememberScroll);

  void _rememberScroll() {
    if (_scroll.hasClients && widget.canContinue()) {
      widget.onScrollOffsetChanged?.call(_scroll.offset);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canContinue = widget.canContinue;
    final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        toolbarHeight: scale > 1.4 ? 64 * scale : 64,
        actions: [
          IconButton(
            key: const ValueKey('live-feed-preferences'),
            tooltip: 'Topics & sources',
            onPressed: canContinue()
                ? () {
                    if (canContinue()) widget.onPreferences();
                  }
                : null,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            key: const ValueKey('live-feed-reading-list'),
            tooltip: 'Reading list',
            onPressed: canContinue()
                ? () {
                    if (canContinue()) widget.onReadingList();
                  }
                : null,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: LiveContentTopicBar(
                controller: controller,
                canContinue: canContinue,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                key: const PageStorageKey('live-content-feed-scroll'),
                controller: _scroll,
                padding: EdgeInsets.all(
                  WingmanTokens.gutter(MediaQuery.sizeOf(context).width),
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: LiveContentSection(
                        controller: controller,
                        onOpen: widget.onOpen,
                        onPin: widget.onPin,
                        onPreferences: widget.onPreferences,
                        onReadingList: widget.onReadingList,
                        onOpenUri: widget.onOpenUri,
                        canContinue: canContinue,
                        showHeading: false,
                        showTopics: false,
                        showActions: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
