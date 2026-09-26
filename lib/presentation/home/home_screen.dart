import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../policy/policy_runtime.dart';
import '../../signature/workspaces/workspace_models.dart';
import '../components/wingman_components.dart';
import '../components/wingman_ribbon.dart';
import '../design_system/ui_preferences.dart';
import '../discovery/discovery_photos.dart';

/// Task-first Home composed exclusively from the captured session's real state.
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
    this.sponsor,
    this.task,
    this.isPrivate = false,
    this.notice,
    this.storageError,
    this.policyUsable = true,
    this.controller,
    this.onStartTask,
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
  final VoidCallback? onStartTask;
  final ValueChanged<String> onOpen, onTask;
  final List<Widget> spaceCards;
  final FinishWorkspace? task;
  final Widget? launchpad, contentCollections, websiteDiscovery, sponsor;
  final bool isPrivate, policyUsable;
  final String? notice, storageError;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final colors = WingmanTokens.of(context);
      final type = Theme.of(context).textTheme;
      final compact = box.maxWidth < 700;
      final scaled = MediaQuery.textScalerOf(context).scale(16) > 24;
      final gutter = WingmanTokens.gutter(box.maxWidth);
      // A thumb-reachable shortcut supplements the ordered task module. It
      // follows the user's task visibility choice and contains only the task
      // supplied by this captured normal/private session.
      final quickTask =
          compact &&
              preferences.showTask &&
              preferences.moduleOrder.contains('task') &&
              task?.status != FinishStatus.finished
          ? task
          : null;
      final modules = <String, Widget>{
        'shortcuts':
            launchpad ??
            WingmanSettingsRow(
              icon: Icons.add_circle_outline,
              title: 'Your Launchpad',
              subtitle: 'Choose the shortcuts that matter to you',
              onTap: onCustomize,
            ),
        if (preferences.showTask)
          'task': TaskResumeCard(
            task: task,
            onResume: task == null
                ? (onStartTask ?? onSpaces)
                : () => onTask(task!.id),
          ),
        if (preferences.showSpaces)
          'spaces': Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Your Spaces', style: type.titleLarge),
                      ),
                      IconButton(
                        tooltip: 'View all Spaces',
                        onPressed: onSpaces,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (spaceCards.isEmpty) ...[
                    Text(
                      'A place for your next good idea.',
                      style: type.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: onSpaces,
                      icon: const Icon(Icons.add),
                      label: const Text('Create a Space'),
                    ),
                  ] else
                    ...spaceCards.take(3),
                  const SizedBox(height: 12),
                  Text(
                    isPrivate
                        ? 'Temporary · this private session'
                        : 'Saved on this device',
                    style: type.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (preferences.showOfficial)
          'official': WingmanSettingsRow(
            icon: Icons.account_balance_outlined,
            title: 'Go straight to the source',
            subtitle: 'Find a reviewed official destination',
            onTap: onOfficial,
          ),
      };
      final ordered = preferences.moduleOrder
          .where(modules.containsKey)
          .toList();
      final children = <Widget>[];
      for (var i = 0; i < ordered.length; i++) {
        final id = ordered[i];
        if (!compact &&
            !scaled &&
            i + 1 < ordered.length &&
            {id, ordered[i + 1]}.containsAll({'task', 'spaces'})) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: modules[id]!),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: modules[ordered[++i]]!),
                ],
              ),
            ),
          );
        } else {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: modules[id]!,
            ),
          );
        }
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.heroStart, colors.heroEnd, colors.canvas],
          ),
        ),
        child: ListView(
          controller: controller,
          key: const ValueKey('protected-discovery'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(gutter, compact ? 12 : 28, gutter, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        if (!compact)
                          TextButton.icon(
                            onPressed: onCustomize,
                            icon: const Icon(Icons.tune),
                            label: const Text('Customize'),
                          ),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: onSettings,
                          icon: const Icon(Icons.tune),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 12 : 32),
                    Stack(
                      children: [
                        if (!scaled)
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            width: compact ? 100 : box.maxWidth * .45,
                            child: WingmanRibbon(compact: compact),
                          ),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 2 : 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPrivate
                                    ? 'A LITTLE SPACE TO YOURSELF.'
                                    : 'YOUR DAY. YOUR DIRECTION.',
                                style: type.labelSmall?.copyWith(
                                  color: colors.secondaryText,
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 14),
                              Text(
                                isPrivate ? 'Your space.' : 'Less noise.',
                                style: type.displaySmall?.copyWith(
                                  fontSize: compact
                                      ? (box.maxWidth < 360 ? 32 : 38)
                                      : 58,
                                  height: 1.06,
                                  letterSpacing: -1.8,
                                ),
                              ),
                              Text(
                                isPrivate ? 'Same boundaries.' : 'More done.',
                                style: type.displaySmall?.copyWith(
                                  fontSize: compact
                                      ? (box.maxWidth < 360 ? 32 : 38)
                                      : 58,
                                  height: 1.1,
                                  letterSpacing: -1.8,
                                  color: colors.action,
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 18),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: compact ? 500 : 430,
                                ),
                                child: Text(
                                  isPrivate
                                      ? 'This private session stays separate from your saved activity.'
                                      : "We've got your back, not your data.",
                                  style: type.bodyMedium?.copyWith(
                                    color: colors.secondaryText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 16 : 30),
                    Semantics(
                      button: true,
                      enabled: true,
                      onTap: onSearch,
                      container: true,
                      excludeSemantics: true,
                      label: 'Search or enter address',
                      child: Material(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          key: const ValueKey('home-search-entry'),
                          onTap: onSearch,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            constraints: BoxConstraints(
                              minHeight: compact ? 60 : 70,
                            ),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colors.action.withValues(alpha: .25),
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.search, color: colors.action),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Search or enter address',
                                    style: type.bodyLarge,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(Icons.arrow_forward, color: colors.action),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      kIsWeb
                          ? 'Web companion · Website links open in your host browser'
                          : 'Submitted searches go to Brave through Wingman. Typing stays here.',
                      style: type.bodySmall,
                    ),
                    if (quickTask != null) ...[
                      const SizedBox(height: 14),
                      _CompactTaskAction(
                        task: quickTask,
                        onResume: () => onTask(quickTask.id),
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
                    ?sponsor,
                    ...children,
                    const SizedBox(height: 22),
                    _ProtectionEntry(onTap: onProtection),
                    if (contentCollections != null) ...[
                      const SizedBox(height: 24),
                      contentCollections!,
                    ],
                    if (websiteDiscovery != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        'A little discovery, on your terms.',
                        style: type.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      websiteDiscovery!,
                    ],
                    const SizedBox(height: 20),
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
        ),
      );
    },
  );
}

/// Keeps an explicit task one tap away on phones without changing the saved
/// Home module order, replacing Launchpad, or inventing an empty-state goal.
class _CompactTaskAction extends StatelessWidget {
  const _CompactTaskAction({required this.task, required this.onResume});
  final FinishWorkspace task;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final tokens = WingmanTokens.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final checked = task.checklist.where((step) => step.done).length;
    return Semantics(
      button: true,
      child: Material(
        color: tokens.selectedTab,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.divider),
        ),
        child: InkWell(
          key: const ValueKey('home-task-quick-resume'),
          onTap: onResume,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.track_changes, color: tokens.action),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue: ${task.goal}',
                        maxLines: largeText ? null : 2,
                        overflow: largeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (task.checklist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '$checked of ${task.checklist.length} steps complete',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward, color: tokens.action),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TaskResumeCard extends StatelessWidget {
  const TaskResumeCard({super.key, required this.task, required this.onResume});
  final FinishWorkspace? task;
  final VoidCallback onResume;
  @override
  Widget build(BuildContext context) {
    final t = WingmanTokens.of(context), type = Theme.of(context).textTheme;
    final count = task?.checklist.where((step) => step.done).length ?? 0;
    final next = task?.checklist.where((step) => !step.done).firstOrNull;
    return Card(
      color: t.selectedTab,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.track_changes, size: 18, color: t.action),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'FINISH MODE',
                    style: type.labelMedium?.copyWith(
                      color: t.action,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(task?.goal ?? 'Start something.', style: type.headlineSmall),
            const SizedBox(height: 10),
            Text(
              task == null
                  ? 'One goal. A few useful steps. Your own pace.'
                  : task!.checklist.isEmpty
                  ? 'Add a first step, or pick up where you left off.'
                  : next == null
                  ? 'Your checklist is complete. Review it when you’re ready.'
                  : 'Next: ${next.text}',
              style: type.bodyMedium?.copyWith(color: t.secondaryText),
            ),
            if (task != null && task!.checklist.isNotEmpty) ...[
              const SizedBox(height: 20),
              // Keep progress semantics separate from the card and its action.
              // Otherwise a web progressbar can absorb the Continue button.
              Semantics(
                container: true,
                child: LinearProgressIndicator(
                  value: count / task!.checklist.length,
                  backgroundColor: t.divider,
                  borderRadius: BorderRadius.circular(8),
                  semanticsLabel:
                      '$count of ${task!.checklist.length} checklist steps complete',
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (task != null)
                  Text(
                    task!.checklist.isEmpty
                        ? 'No checklist yet'
                        : '$count of ${task!.checklist.length} steps complete',
                    style: type.bodySmall,
                  ),
                FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(task == null ? 'Start something' : 'Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtectionEntry extends StatelessWidget {
  const _ProtectionEntry({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => WingmanSettingsRow(
    icon: Icons.verified_user_outlined,
    title: 'Quietly on your side.',
    subtitle: 'Built-in boundaries. Clear privacy controls. No account needed.',
    onTap: onTap,
  );
}
