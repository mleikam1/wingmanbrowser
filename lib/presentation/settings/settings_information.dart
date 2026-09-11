import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../design_system/app_build_info.dart';
import '../components/wingman_components.dart';
import 'settings_actions.dart';

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});
  @override
  Widget build(BuildContext context) => WingmanPage(
    title: 'Website permissions',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WingmanEmptyState(
          icon: Icons.lock_outline,
          title: 'Website permissions stay restricted',
          message:
              'Reviewed native pages can display HTML, styles and listed images. Camera, microphone, location, uploads, notifications and account sign-in remain unavailable for websites.',
        ),
        const SizedBox(height: 24),
        for (final name in [
          'Camera & microphone',
          'Location',
          'Uploads & downloads',
          'Website notifications',
        ])
          WingmanSettingsRow(
            icon: Icons.block,
            title: name,
            subtitle: 'Unavailable for websites in this build',
          ),
        const SizedBox(height: 20),
        const Text(
          'These are capability limits, not a list of OS permissions granted to other apps. Wingman cannot reset another browser’s site permissions.',
        ),
      ],
    ),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.buildInfo,
    required this.policy,
    required this.canContinue,
    required this.actions,
  });
  final AppBuildInfo buildInfo;
  final PolicyRuntime policy;
  final bool Function() canContinue;
  final SettingsActions actions;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: policy,
    builder: (context, _) => WingmanPage(
      title: 'Help & About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wingman Browser',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('Version ${buildInfo.version} · Build ${buildInfo.build}'),
          const SizedBox(height: 12),
          const Text("We've got your back, not your data."),
          const SizedBox(height: 24),
          const WingmanSection(title: 'Current capabilities'),
          WingmanStatus(
            title: policy.status.usable
                ? 'Reviewed library available'
                : 'Library policy unavailable',
            message: policy.status.usable
                ? '${policy.status.resourceCount} signed local articles. Review freshness and exact-content eligibility are checked before display.'
                : 'Content remains closed. Settings and local-tool explanations remain available.',
            tone: policy.status.usable ? WingmanTone.info : WingmanTone.caution,
          ),
          const Text(
            'Local tools: Spaces, Finish Mode, Official Routes evidence, Before You Commit, Trust Receipt and previewed compatibility export. Native Hand It Over shares only selected static text with an owner-return gate.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Eligible Android and iOS 18.4+ builds include a limited reviewed website pilot with images and styles. Scripts, external search, account sign-in, site permissions, remote Reader, downloads, cloud sync and report submission remain unavailable. Web is a local-tools companion and does not control other browser tabs.',
          ),
          const SizedBox(height: 20),
          WingmanSettingsRow(
            icon: Icons.receipt_long_outlined,
            title: 'Trust Receipt',
            subtitle: 'Configured, observed and unknown behavior',
            onTap: () {
              if (canContinue()) actions.onReceipt();
            },
          ),
          WingmanSettingsRow(
            icon: Icons.build_outlined,
            title: 'Something isn’t working',
            subtitle: 'Prepare a minimal report; nothing is submitted',
            onTap: () {
              if (canContinue()) actions.onCompatibility();
            },
          ),
          if (actions.onHelpNow != null)
            WingmanSettingsRow(
              icon: Icons.favorite_border,
              title: 'Help Now',
              subtitle: 'A quiet local starting point',
              onTap: () {
                if (canContinue()) actions.onHelpNow!();
              },
            ),
          WingmanSettingsRow(
            icon: Icons.description_outlined,
            title: 'Open-source licenses',
            onTap: () {
              if (canContinue()) {
                showLicensePage(
                  context: context,
                  applicationName: 'Wingman Browser',
                  applicationVersion:
                      '${buildInfo.version} (${buildInfo.build})',
                );
              }
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'No report endpoint, support case number or response-time promise is configured. Clipboard exports may be accessible to other apps and OS clipboard services. Device backups, completed files and other applications are outside Wingman’s clearing guarantee.',
          ),
          const SizedBox(height: 16),
          const Text(
            'The reviewed library is limited coverage, not a guarantee about the internet. No clinical, legal, compliance or independent security certification is claimed.',
          ),
        ],
      ),
    ),
  );
}
