import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../design_system/app_build_info.dart';
import '../components/wingman_components.dart';
import 'appearance_screen.dart';
import 'privacy_data_screen.dart';
import 'settings_information.dart';
import 'settings_actions.dart';
export 'settings_actions.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
    required this.actions,
    required this.buildInfo,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final SettingsActions actions;
  final AppBuildInfo buildInfo;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) {
      if (!canContinue()) return;
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    void act(VoidCallback action) {
      if (canContinue()) action();
    }

    return WingmanPage(
      title: 'Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GroupLabel(title: 'Make it yours'),
          _SettingsLink(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Light, dark or device setting',
            onTap: () =>
                open(AppearanceScreen(state: state, canContinue: canContinue)),
          ),
          _SettingsLink(
            icon: Icons.dashboard_outlined,
            title: 'Home & Spaces',
            subtitle: 'Choose what appears on Home',
            onTap: () => act(actions.onHomeCustomization),
          ),
          _SettingsLink(
            icon: Icons.search,
            title: 'Search',
            subtitle: 'Approved resources and local suggestions',
            onTap: () => open(
              SearchSettingsScreen(state: state, canContinue: canContinue),
            ),
          ),
          const _GroupLabel(title: 'Protection & privacy'),
          _SettingsLink(
            icon: Icons.shield_outlined,
            title: 'Protection',
            subtitle: 'Core policy and additional boundaries',
            onTap: () => act(actions.onProtection),
          ),
          _SettingsLink(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & data',
            subtitle: isPrivate
                ? 'This private session'
                : 'Local storage, retention and clearing',
            onTap: () => open(
              PrivacyDataScreen(
                state: state,
                isPrivate: isPrivate,
                canContinue: canContinue,
                actions: actions,
              ),
            ),
          ),
          _SettingsLink(
            icon: Icons.tune,
            title: 'Website permissions',
            subtitle: 'Current platform capability',
            onTap: () => open(const PermissionsScreen()),
          ),
          const _GroupLabel(title: 'Your experience'),
          _SettingsLink(
            icon: Icons.accessibility_new,
            title: 'Accessibility',
            subtitle: 'Text, motion and keyboard support',
            onTap: () => open(
              AppearanceScreen(
                state: state,
                canContinue: canContinue,
                accessibility: true,
              ),
            ),
          ),
          _SettingsLink(
            icon: Icons.help_outline,
            title: 'Help & About',
            subtitle: 'Version, licenses and capabilities',
            onTap: () => open(
              AboutScreen(
                buildInfo: buildInfo,
                policy: policy,
                canContinue: canContinue,
                actions: actions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
    final tokens = WingmanTokens.of(context);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 12,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.raised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tokens.action, size: 24),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 14, height: 20 / 14),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
