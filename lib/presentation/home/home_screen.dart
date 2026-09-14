import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../policy/policy_runtime.dart';
import '../../signature/workspaces/workspace_models.dart';
import '../components/wingman_components.dart';
import '../design_system/ui_preferences.dart';
import '../discovery/discovery_photos.dart';

/// Home composes real session data. Reference artwork never supplies records.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.preferences,
    required this.resources,
    required this.onSearch,
    required this.onSettings,
    required this.onProtection,
    required this.onOfficial,
    required this.onLibrary,
    required this.onCustomize,
    required this.onExplore,
    required this.onOpen,
    required this.onSpaces,
    required this.onTask,
    required this.spaceCards,
    this.launchpad,
    this.contentCollections,
    this.websiteDiscovery,
    this.task,
    this.isPrivate = false,
    this.notice,
    this.storageError,
    this.policyUsable = true,
    this.controller,
  });
  final UiPreferences preferences;
  final List<ApprovedResource> resources;
  final VoidCallback onSearch,
      onSettings,
      onProtection,
      onOfficial,
      onLibrary,
      onCustomize,
      onExplore,
      onSpaces;
  final ValueChanged<String> onOpen, onTask;
  final List<Widget> spaceCards;
  final FinishWorkspace? task;
  final Widget? launchpad, contentCollections, websiteDiscovery;
  final bool isPrivate, policyUsable;
  final String? notice, storageError;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = WingmanTokens.of(context);
    final modules = <String, Widget>{
      'shortcuts': Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          launchpad ??
              WingmanSettingsRow(
                icon: Icons.add_circle_outline,
                title: 'Your Launchpad',
                subtitle: 'Choose the shortcuts that matter to you',
                onTap: onCustomize,
              ),
          if (websiteDiscovery != null) ...[
            const SizedBox(height: 20),
            websiteDiscovery!,
          ],
          if (contentCollections != null) ...[
            const SizedBox(height: 20),
            contentCollections!,
          ],
        ],
      ),
      if (preferences.showOfficial)
        'official': Card(
          child: InkWell(
            onTap: onOfficial,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.raised,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_outlined,
                      color: colors.action,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Go straight to the source',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find a reviewed official destination',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
        ),
      if (preferences.showTask && task != null)
        'task': Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick up where you left off',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: colors.raised,
              child: InkWell(
                onTap: () => onTask(task!.id),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FINISH MODE',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.action,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task!.goal,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              '${task!.checklist.where((s) => s.done).length} of ${task!.checklist.length} steps complete',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              'Continue',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.action,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (task!.checklist.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(
                            backgroundColor: colors.divider,
                            value:
                                task!.checklist.where((s) => s.done).length /
                                task!.checklist.length,
                            semanticsLabel: 'Task checklist progress',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      if (preferences.showSpaces)
        'spaces': Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Spaces',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(onPressed: onSpaces, child: const Text('View all')),
              ],
            ),
            const SizedBox(height: 8),
            if (spaceCards.isEmpty)
              WingmanSettingsRow(
                icon: Icons.add_circle_outline,
                title: 'Make room for what matters',
                subtitle: 'Choose a Space to get started',
                onTap: onSpaces,
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 320 &&
                          MediaQuery.textScalerOf(context).scale(16) < 24
                      ? 2
                      : 1;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final card in spaceCards.take(3))
                        SizedBox(
                          width:
                              (constraints.maxWidth - 12 * (columns - 1)) /
                              columns,
                          child: card,
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
    };
    return ListView(
      controller: controller,
      key: const ValueKey('protected-discovery'),
      padding: EdgeInsets.all(
        WingmanTokens.gutter(MediaQuery.sizeOf(context).width),
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(child: WingmanBrand()),
                    IconButton(
                      key: const ValueKey('home-protection'),
                      tooltip: policyUsable
                          ? 'Protection overview'
                          : 'Protection needs attention',
                      onPressed: onProtection,
                      icon: Icon(
                        policyUsable
                            ? Icons.shield_outlined
                            : Icons.warning_amber_rounded,
                        color: colors.action,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: onSettings,
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
                if (isPrivate) ...[
                  const SizedBox(height: 12),
                  Text(
                    'A little space to yourself.',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  isPrivate
                      ? 'Same protection. This private session stays separate from your saved activity.'
                      : "We've got your back, not your data.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  enabled: true,
                  onTap: onSearch,
                  container: true,
                  excludeSemantics: true,
                  label: 'Search or enter address',
                  child: InkWell(
                    key: const ValueKey('home-search-entry'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: onSearch,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.divider),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: colors.secondaryText),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Search or enter address',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          const Icon(Icons.keyboard_return, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Web companion · Website links open in your host browser',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (!policyUsable) ...[
                  const SizedBox(height: 16),
                  const WingmanStatus(
                    title: 'Reviewed library unavailable',
                    message:
                        'Content stays closed until a valid policy is installed. Settings and local tools remain accessible.',
                    tone: WingmanTone.caution,
                  ),
                ],
                if (notice != null) ...[
                  const SizedBox(height: 16),
                  WingmanStatus(
                    title: 'Destination unavailable',
                    message: notice!,
                  ),
                ],
                if (storageError != null) ...[
                  const SizedBox(height: 16),
                  WingmanStatus(
                    title: 'Local storage needs attention',
                    message: storageError!,
                    tone: WingmanTone.caution,
                  ),
                ],
                if (preferences.homeArtwork != HomeArtwork.none) ...[
                  const SizedBox(height: 20),
                  HomeArtworkPanel(artwork: preferences.homeArtwork),
                ],
                for (final key in preferences.moduleOrder)
                  if (modules[key] != null) ...[
                    SizedBox(height: key == 'spaces' ? 8 : 20),
                    modules[key]!,
                  ],
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: onCustomize,
                  icon: const Icon(Icons.tune),
                  label: const Text('Customize Home'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
