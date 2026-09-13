import 'dart:convert';

import 'package:flutter/material.dart';

import '../../live_content/live_content.dart';
import '../components/wingman_components.dart';
import 'live_content_section.dart';

class LiveContentPreferencesScreen extends StatefulWidget {
  const LiveContentPreferencesScreen({
    super.key,
    required this.controller,
    required this.canContinue,
  });
  final LiveContentController controller;
  final bool Function() canContinue;

  @override
  State<LiveContentPreferencesScreen> createState() =>
      _LiveContentPreferencesScreenState();
}

class _LiveContentPreferencesScreenState
    extends State<LiveContentPreferencesScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _change(Future<void> Function() action) async {
    if (_busy || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && widget.canContinue()) {
        setState(
          () => _error =
              'Your change could not be saved. Your previous choices remain in effect.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _diagnostics() {
    if (!widget.canContinue()) return;
    final controller = widget.controller;
    final preview = const JsonEncoder.withIndent('  ').convert({
      'feedConfigured': controller.configured,
      'initialized': controller.initialized,
      'refreshing': controller.refreshing,
      'cachedOrStale': controller.stale,
      'snapshotGeneratedAt': controller.fetchedAt?.toUtc().toIso8601String(),
      'availableSources': controller.sources.length,
      'visibleItems': controller.items.length,
      'savedItems': controller.savedItems.length,
      'refreshError': controller.error != null,
      'storageError': controller.storageError != null,
    });
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feed diagnostics preview'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This preview stays on this device. It contains counts and feed status, without article addresses, interests or browsing history.',
            ),
            const SizedBox(height: 16),
            SelectableText(preview),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller,
          preferences = controller.preferences;
      final topics = liveContentTopicOrder.where(
        (topic) => topic != 'headlines',
      );
      final sources = controller.sources;
      final languages = controller.availableLanguages.toList()..sort();
      final regions = controller.availableRegions.toList()..sort();
      final canChange = !_busy && widget.canContinue();
      return WingmanPage(
        title: 'Topics & sources',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose what appears in your feed. Preferences, dismissed items and your reading list stay on this device.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Wingman downloads public feeds directly from publishers. Publishers can see your IP address and ordinary connection information. Your browsing history and chosen topics stay on this device. Feed updates stop in private browsing and when the feed is off.',
            ),
            SwitchListTile(
              key: const ValueKey('live-preferences-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show publisher updates'),
              subtitle: const Text(
                'Turning this off keeps your saved articles.',
              ),
              value: preferences.enabled,
              onChanged: canChange
                  ? (enabled) => _change(() => controller.setEnabled(enabled))
                  : null,
            ),
            const WingmanSection(title: 'Topics'),
            if (topics.isEmpty)
              const Text('No supported topics are available yet.'),
            if (topics.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('live-preferences-all-topics'),
                    label: const Text('Headlines'),
                    selected: preferences.selectedTopics.isEmpty,
                    onSelected: canChange
                        ? (_) => _change(() => controller.selectTopics({}))
                        : null,
                  ),
                  for (final topic in topics)
                    ChoiceChip(
                      key: ValueKey('live-preferences-topic-$topic'),
                      label: Text(liveContentTopicLabel(topic)),
                      selected:
                          preferences.selectedTopics.length == 1 &&
                          preferences.selectedTopics.contains(topic),
                      onSelected: canChange
                          ? (_) =>
                                _change(() => controller.selectTopics({topic}))
                          : null,
                    ),
                ],
              ),
            if (preferences.fewerTopics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Shown less often: ${(preferences.fewerTopics.toList()..sort()).map(liveContentTopicLabel).join(', ')}. Reset preferences to restore their usual order.',
              ),
            ],
            const WingmanSection(title: 'Sources'),
            const Text(
              'Follow the publishers you want to see. Hidden sources remain available to follow again here.',
            ),
            if (sources.isEmpty)
              const Text('No approved sources are available.'),
            for (final source in sources)
              SwitchListTile(
                key: ValueKey('live-preferences-source-${source.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(source.name),
                subtitle: Text(
                  source.status == 'revoked'
                      ? 'Currently unavailable'
                      : (source.topics.toList()..sort())
                            .map(liveContentTopicLabel)
                            .join(' · '),
                ),
                value:
                    source.status != 'revoked' &&
                    preferences.follows(source.id),
                onChanged: canChange && source.status != 'revoked'
                    ? (follow) => _change(
                        () => follow
                            ? controller.followSource(source.id)
                            : controller.unfollowSource(source.id),
                      )
                    : null,
              ),
            const WingmanSection(title: 'Language'),
            if (languages.isEmpty)
              const Text('No feed language is available yet.')
            else
              DropdownButtonFormField<String>(
                key: ValueKey('live-language-${preferences.language}'),
                initialValue: languages.contains(preferences.language)
                    ? preferences.language
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Available language',
                ),
                items: [
                  for (final language in languages)
                    DropdownMenuItem(
                      value: language,
                      child: Text(language == 'en' ? 'English' : language),
                    ),
                ],
                onChanged: canChange
                    ? (language) {
                        if (language != null) {
                          _change(() => controller.setLanguage(language));
                        }
                      }
                    : null,
              ),
            const WingmanSection(title: 'Region'),
            if (regions.isEmpty) ...[
              const Text(
                'These sources do not currently provide regional editions. No location is requested.',
              ),
              if (preferences.region != null)
                TextButton(
                  onPressed: canChange
                      ? () => _change(() => controller.setRegion(null))
                      : null,
                  child: const Text('Clear region preference'),
                ),
            ] else
              DropdownButtonFormField<String>(
                key: ValueKey('live-region-${preferences.region}'),
                initialValue: regions.contains(preferences.region)
                    ? preferences.region
                    : '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Optional region'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All regions')),
                  for (final region in regions)
                    DropdownMenuItem(value: region, child: Text(region)),
                ],
                onChanged: canChange
                    ? (region) => _change(
                        () => controller.setRegion(
                          region == null || region.isEmpty ? null : region,
                        ),
                      )
                    : null,
              ),
            const WingmanSection(title: 'Your choices'),
            const Text(
              'Reset restores all supported topics and sources, clears dismissed items and “show fewer” choices, and turns the feed on. Saved articles remain.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('live-preferences-reset'),
              onPressed: canChange
                  ? () => _change(controller.resetPreferences)
                  : null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset feed preferences'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: canChange ? _diagnostics : null,
              icon: const Icon(Icons.info_outline),
              label: const Text('Preview diagnostics'),
            ),
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
        ),
      );
    },
  );
}
