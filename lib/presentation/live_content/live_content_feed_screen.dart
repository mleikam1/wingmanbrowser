import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import 'live_content_section.dart';

/// An owned feature route: category controls remain reachable while the finite
/// article list scrolls. No timer, carousel advancement or scroll fetch exists.
class LiveContentFeedScreen extends StatelessWidget {
  const LiveContentFeedScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onPin,
    required this.onPreferences,
    required this.onReadingList,
    required this.canContinue,
    this.onOpenUri,
  });
  final LiveContentController controller;
  final ValueChanged<LiveContentItem> onOpen, onPin;
  final ValueChanged<Uri>? onOpenUri;
  final VoidCallback onPreferences, onReadingList;
  final bool Function() canContinue;

  @override
  Widget build(BuildContext context) {
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
                    if (canContinue()) onPreferences();
                  }
                : null,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            key: const ValueKey('live-feed-reading-list'),
            tooltip: 'Reading list',
            onPressed: canContinue()
                ? () {
                    if (canContinue()) onReadingList();
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
                padding: EdgeInsets.all(
                  WingmanTokens.gutter(MediaQuery.sizeOf(context).width),
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: LiveContentSection(
                        controller: controller,
                        onOpen: onOpen,
                        onPin: onPin,
                        onPreferences: onPreferences,
                        onReadingList: onReadingList,
                        onOpenUri: onOpenUri,
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
