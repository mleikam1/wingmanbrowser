import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../design_system/app_build_info.dart';
import '../design_system/ui_preferences.dart';
import '../components/wingman_components.dart';
import 'appearance_screen.dart';
import 'privacy_data_screen.dart';
import 'settings_information.dart';
import 'settings_actions.dart';
export 'settings_actions.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
    required this.actions,
    required this.buildInfo,
    this.uiPreferences,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final SettingsActions actions;
  final AppBuildInfo buildInfo;
  final UiPreferencesController? uiPreferences;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;
  String? _error;
  void _open(Widget page) {
    if (widget.canContinue()) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  void _act(VoidCallback action) {
    if (widget.canContinue()) action();
  }

  Future<void> _save(Future<void> Function() operation) async {
    if (_saving || !widget.canContinue()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The change could not be saved. Your previous preference is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, widget.uiPreferences]),
    builder: (context, _) {
      final t = WingmanTokens.of(context);
      final actions = widget.actions;
      final preferences = widget.uiPreferences;
      final local = preferences?.snapshot;
      final personalization = _SettingsGroup(
        title: 'Home & your Wingman',
        children: [
          _SettingsLink(
            icon: Icons.dashboard_outlined,
            title: 'Home & Spaces',
            subtitle: 'Artwork, shortcuts, density, and the modules you choose',
            onTap: () => _act(actions.onHomeCustomization),
          ),
          _SettingsLink(
            icon: Icons.folder_outlined,
            title: 'Your Spaces',
            subtitle: 'Saved resources, notes, and next steps',
            onTap: () => _act(actions.onSpaces),
          ),
          if (actions.onFinishMode != null)
            _SettingsLink(
              icon: Icons.track_changes,
              title: 'Finish Mode',
              subtitle: 'Your goal, checklist, timer, and focus preferences',
              onTap: () => _act(actions.onFinishMode!),
            ),
          if (actions.onCommitReview != null)
            _SettingsLink(
              icon: Icons.fact_check_outlined,
              title: 'Before You Commit',
              subtitle: 'A local check of the terms you supply',
              onTap: () => _act(actions.onCommitReview!),
            ),
          if (actions.onUpdates != null && !widget.isPrivate)
            _SettingsLink(
              icon: Icons.newspaper_outlined,
              title: 'Updates',
              subtitle: 'Choose topics and sources, or turn Updates off',
              onTap: () => _act(actions.onUpdates!),
            ),
          if (local != null) ...[
            const SizedBox(height: 18),
            Text(
              'Companion tone',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Optional local wording. Tone does not change permissions, protection, or data access.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tone in CompanionTone.values)
                  ChoiceChip(
                    label: Text(switch (tone) {
                      CompanionTone.gary => 'Gary · direct',
                      CompanionTone.wallace => 'Wallace · calm',
                      CompanionTone.betty => 'Betty · warm',
                    }),
                    selected: local.companionTone == tone,
                    onSelected: _saving
                        ? null
                        : (_) => _save(
                            () => preferences!.update(
                              (current) =>
                                  current.copyWith(companionTone: tone),
                            ),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion'),
              subtitle: const Text(
                'Keep transitions quiet. Your device’s reduced-motion setting is always respected.',
              ),
              value: local.reduceMotion,
              onChanged: _saving
                  ? null
                  : (value) => _save(
                      () => preferences!.update(
                        (current) => current.copyWith(reduceMotion: value),
                      ),
                    ),
            ),
            if (widget.isPrivate)
              const Text(
                'These local tool choices last only for this private session.',
              ),
          ],
        ],
      );
      final privacy = _SettingsGroup(
        title: 'Privacy, protection & essentials',
        children: [
          _SettingsLink(
            icon: Icons.shield_outlined,
            title: 'Protection',
            subtitle: 'Installed rules, observed activity, and limitations',
            onTap: () => _act(actions.onProtection),
          ),
          _SettingsLink(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & data',
            subtitle: widget.isPrivate
                ? 'This private session'
                : 'Local storage, retention, and clearing',
            onTap: () => _open(
              PrivacyDataScreen(
                state: widget.state,
                isPrivate: widget.isPrivate,
                canContinue: widget.canContinue,
                actions: actions,
              ),
            ),
          ),
          _SettingsLink(
            icon: Icons.receipt_long_outlined,
            title: 'Trust Receipt',
            subtitle: 'Review feature activity before any export',
            onTap: () => _act(actions.onReceipt),
          ),
          _SettingsLink(
            icon: Icons.search,
            title: 'Search',
            subtitle: 'Strict web filtering and on-device search',
            onTap: () => _open(
              SearchSettingsScreen(
                state: widget.state,
                policy: widget.policy,
                isPrivate: widget.isPrivate,
                canContinue: widget.canContinue,
              ),
            ),
          ),
          _SettingsLink(
            icon: Icons.tune,
            title: 'Website permissions',
            subtitle: 'Current platform capability',
            onTap: () => _open(const PermissionsScreen()),
          ),
          _SettingsLink(
            icon: Icons.accessibility_new,
            title: 'Accessibility',
            subtitle: 'Reading size and device accessibility',
            onTap: () => _open(
              AppearanceScreen(
                state: widget.state,
                canContinue: widget.canContinue,
                accessibility: true,
                isPrivate: widget.isPrivate,
              ),
            ),
          ),
          _SettingsLink(
            icon: Icons.help_outline,
            title: 'Help & About',
            subtitle: 'Version, licenses, and capabilities',
            onTap: () => _open(
              AboutScreen(
                buildInfo: widget.buildInfo,
                policy: widget.policy,
                canContinue: widget.canContinue,
                actions: actions,
              ),
            ),
          ),
        ],
      );
      return WingmanPage(
        title: 'Settings',
        maxWidth: 1360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MAKE IT YOURS',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: t.action,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your browser. Your way.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Personalize the experience while keeping the built-in boundaries.',
            ),
            const SizedBox(height: 28),
            _SettingsGroup(
              title: 'A look that feels like you.',
              children: [
                _SettingsLink(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: widget.isPrivate
                      ? 'Saved appearance is read-only in private'
                      : 'Light, dark, or follow your device',
                  onTap: () => _open(
                    AppearanceScreen(
                      state: widget.state,
                      canContinue: widget.canContinue,
                      isPrivate: widget.isPrivate,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ThemePreviewChoices(
                  value: widget.state.settings.themeMode,
                  onChanged: _saving || widget.isPrivate
                      ? null
                      : (mode) => _save(
                          () => widget.state.saveSettingsPatch(themeMode: mode),
                        ),
                ),
              ],
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: WingmanStatus(
                  title: 'Saving not confirmed',
                  message: _error!,
                  tone: WingmanTone.caution,
                ),
              ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= 900 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: personalization),
                        const SizedBox(width: 24),
                        Expanded(child: privacy),
                      ],
                    )
                  : Column(
                      children: [
                        personalization,
                        const SizedBox(height: 24),
                        privacy,
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            WingmanStatus(
              title: 'Built-in protection is not a preference.',
              message:
                  'Core content and known-threat rules have no off switch. Coverage varies by platform and request path.',
              action: TextButton(
                onPressed: () => _act(actions.onProtection),
                child: const Text('View rules'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    color: WingmanTokens.of(context).surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: WingmanTokens.of(context).divider),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = WingmanTokens.of(context);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 14,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: t.action, size: 23),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
