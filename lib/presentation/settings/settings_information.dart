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
          title: 'Website permissions are origin scoped',
          message:
              'Supported native pages can request camera or microphone access for their own origin. Wingman asks before granting supported permissions. File uploads and downloads use system pickers. Account sessions use normal cookies; private website storage is separate.',
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
            subtitle: name == 'Website notifications'
                ? 'Unavailable in this build'
                : 'Subject to native platform support and your permission',
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
            'Native consumer Wingman uses System WebView or WKWebView for ordinary pages, forms, JavaScript and sign-in continuity. DuckDuckGo Strict adult filtering is required. Local category and threat rules check destinations separately. Unknown destinations may be permitted; they are not verified safe.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Web search sends submitted queries and the connection’s IP address directly to DuckDuckGo, with no remote suggestions while typing and no paid search service. Native desktop apps are not available. The web companion has local tools and submits search by leaving for the strict provider. It cannot enforce native protection in the host browser.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Filtering can miss prohibited content and block legitimate pages. Dynamic recommendations, images and ads are not comprehensively classified. Alcohol, recreational-drug promotion and tobacco data have limited coverage. Cloud sync and report submission remain unavailable.',
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
