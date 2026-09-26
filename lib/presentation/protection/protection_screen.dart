import 'package:flutter/material.dart';
import '../../config/product_edition.dart';
import '../../live_content/controller.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';
import 'additional_boundaries_screen.dart';
import 'help_now_screen.dart';

class ProtectionScreen extends StatelessWidget {
  const ProtectionScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
    required this.onReceipt,
    required this.onRequestReview,
    required this.onOpenApprovedResource,
    required this.onHome,
    this.liveContent,
    this.observedBlockedRequests,
    this.observationScope,
    this.requestCountersObservable = false,
    this.observedCounterSaturated = false,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final VoidCallback onReceipt, onRequestReview, onHome;
  final ValueChanged<String> onOpenApprovedResource;
  final LiveContentController? liveContent;
  final int? observedBlockedRequests;
  final String? observationScope;
  final bool requestCountersObservable, observedCounterSaturated;

  void _open(BuildContext context, Widget page) {
    if (canContinue()) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, policy, liveContent]),
    builder: (context, _) {
      final tokens = WingmanTokens.of(context);
      final consumer = productEdition == ProductEdition.consumer;
      final usable = consumer
          ? policy.consumerProtection.isUsable
          : policy.status.usable;
      final stale =
          consumer &&
          usable &&
          policy.consumerProtection.isStale(policy.clock.now());
      final live = policy.liveAvailable(isPrivate: isPrivate);
      final status = !usable
          ? 'Protection unavailable · browsing closed'
          : stale
          ? 'Usable rules · update recommended'
          : 'Validated rules installed';
      final configured = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.raised, tokens.action.withValues(alpha: .14)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: tokens.divider),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONFIGURED / INSTALLED',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.action,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Always part\nof Wingman.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Content and threat boundaries stay mandatory, including in private sessions.',
                ),
                const SizedBox(height: 22),
                WingmanStatus(
                  title: status,
                  message: !usable
                      ? 'No usable mandatory baseline is installed. Local tools remain available while browsing stays closed.'
                      : stale
                      ? 'The last validated baseline is older than 24 hours. It remains usable during outages; coverage may be outdated.'
                      : 'This describes installed rules. It does not verify every page or request.',
                  tone: !usable || stale
                      ? WingmanTone.caution
                      : WingmanTone.info,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _ProtectionPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Actually observed',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                Text(
                  'Supported requests blocked',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  observedBlockedRequests == null
                      ? requestCountersObservable
                            ? 'No observation available yet'
                            : 'Not observable on this platform'
                      : '$observedBlockedRequests${observedCounterSaturated ? '+' : ''}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  observedBlockedRequests == null
                      ? 'No request count is available for this view. An absent count is not zero traffic.'
                      : 'Observed when this view opened. ${observationScope ?? 'This tab’s page engine'}. Resets when this page engine is released or recreated. Repeated blocked requests are separate outcomes, not unique trackers.',
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 10),
                const Text(
                  'Local Wingman tools',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'No cloud assistant is configured. Websites, search, and enabled Updates have their own network activity.',
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {
                    if (canContinue()) onReceipt();
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Open Trust Receipt'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _informationFlow(context),
        ],
      );
      final rules = _ProtectionPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Built-in boundaries',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Read-only core rules. Filtering coverage varies.'),
            const SizedBox(height: 18),
            for (final category in MandatoryCategory.values) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: tokens.action, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _categoryName(category),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _categoryScope(category),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Required · no off switch',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: tokens.action),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 20),
            const WingmanStatus(
              title: 'Coverage is limited',
              message:
                  'Filters can miss prohibited content or block legitimate pages. Dynamic images, ads, and recommendations are not reliably classified.',
              tone: WingmanTone.caution,
            ),
            const SizedBox(height: 12),
            WingmanSettingsRow(
              icon: Icons.tune,
              title: 'Additional boundaries',
              subtitle: 'Narrow access without lowering the core rules',
              onTap: () => _open(
                context,
                AdditionalBoundariesScreen(
                  state: state,
                  policy: policy,
                  isPrivate: isPrivate,
                  canContinue: canContinue,
                ),
              ),
            ),
            WingmanSettingsRow(
              icon: Icons.shield_outlined,
              title: 'Always-on protections',
              subtitle: 'Installed versions, rule dates, and review scope',
              onTap: () =>
                  _open(context, AlwaysOnProtectionsScreen(policy: policy)),
            ),
          ],
        ),
      );
      return WingmanPage(
        title: 'Privacy & protection',
        maxWidth: 1440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PRIVACY & PROTECTION',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.action,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Protection you can inspect.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'See what is installed, what was observed, and what we cannot verify.',
            ),
            const SizedBox(height: 28),
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= 860 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: configured),
                        const SizedBox(width: 24),
                        Expanded(flex: 10, child: rules),
                      ],
                    )
                  : Column(
                      children: [configured, const SizedBox(height: 20), rules],
                    ),
            ),
            const SizedBox(height: 24),
            _ProtectionPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Limits and current availability',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    live
                        ? 'Live pages use local category and threat filtering on supported navigation and request paths. Permitted is not the same as verified safe.'
                        : 'Live website support is unavailable in this session. The web companion does not control the host browser.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${policy.status.resourceCount} reviewed offline articles. Offline catalog availability is separate from consumer browsing protection.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${policy.brandedSearchAvailable(additional: state.protectedPreferences.additional) ? 'Wingman Search is allowed with required Strict filtering; its gateway must be configured.' : 'Web search is unavailable or disabled in this session.'} Query, result and destination checks apply. Filtering can miss content; listed results are not verified safe.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    policy.consumerUpdatesConfigured
                        ? 'Online rule updates are configured. Startup checks retain the last validated rules during outages.'
                        : 'Online rule updates are not configured in this build. Verified app updates refresh bundled rules.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (canContinue()) onRequestReview();
                  },
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Prepare review details'),
                ),
                TextButton.icon(
                  onPressed: () => _open(
                    context,
                    HelpNowScreen(
                      policy: policy,
                      additional: () => state.protectedPreferences.additional,
                      isPrivate: isPrivate,
                      canContinue: canContinue,
                      onHome: onHome,
                      onOpenApprovedResource: onOpenApprovedResource,
                    ),
                  ),
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Take a quiet pause'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _informationFlow(BuildContext context) {
    final feed = liveContent;
    final suppressed = isPrivate || feed?.context == LiveContentContext.handoff;
    return _ProtectionPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where information goes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const _InformationRoute(
            icon: Icons.language,
            title: 'Websites from your device',
            detail:
                'Sites receive page requests and your connection’s IP address. Cookies and sign-ins follow the current session’s engine storage.',
          ),
          const _InformationRoute(
            icon: Icons.search,
            title: 'Submitted search through Wingman to Brave',
            detail:
                'The Wingman gateway receives the submitted query and sends it to Brave without consumer IP, cookie or account forwarding. The standard Brave notice permits retention up to 90 days. Typing stays local.',
          ),
          _InformationRoute(
            icon: Icons.newspaper_outlined,
            title: 'Updates and associated images',
            detail: suppressed
                ? 'Suppressed in this private or handoff session. Normal selections and caches are not shown here.'
                : feed?.configured != true
                ? 'No feed provider is configured for this view.'
                : !feed!.preferences.enabled
                ? 'Updates are off. No feed or associated image requests are started by the disabled feature.'
                : 'Enabled Updates use the configured feed service and approved publishers; associated images use their approved image origins. These services receive network requests and your IP address. Local topics organize the common feed.',
          ),
          _InformationRoute(
            icon: Icons.system_update_alt,
            title: 'Protection updates',
            detail: policy.consumerUpdatesConfigured
                ? 'The configured rule service receives update checks. Installed rules remain available if that service fails.'
                : 'No online rule-update service is configured in this build.',
          ),
          const _InformationRoute(
            icon: Icons.devices_outlined,
            title: 'Local tools on this device',
            detail:
                'Spaces, notes, and supplied-text analysis use local state. Clipboard and file exports leave that boundary only when you explicitly choose them.',
          ),
        ],
      ),
    );
  }
}

class _ProtectionPanel extends StatelessWidget {
  const _ProtectionPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: WingmanTokens.of(context).surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: WingmanTokens.of(context).divider),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

class _InformationRoute extends StatelessWidget {
  const _InformationRoute({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: WingmanTokens.of(context).action, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

String _categoryName(MandatoryCategory category) => switch (category) {
  MandatoryCategory.sexualExplicit => 'Explicit entertainment',
  MandatoryCategory.gambling => 'Gambling & wagering',
  MandatoryCategory.alcoholPromotion => 'Alcohol promotion',
  MandatoryCategory.recreationalDrugPromotion => 'Recreational-drug promotion',
  MandatoryCategory.tobaccoNicotine => 'Tobacco & vaping promotion',
  MandatoryCategory.securityThreat => 'Malware & phishing',
};

String _categoryScope(MandatoryCategory category) => switch (category) {
  MandatoryCategory.sexualExplicit ||
  MandatoryCategory.gambling => 'Domain and supported-request rules',
  MandatoryCategory.alcoholPromotion || MandatoryCategory.tobaccoNicotine =>
    'Coverage is limited for dynamic content',
  MandatoryCategory.recreationalDrugPromotion =>
    'Legitimate information has a separate context',
  MandatoryCategory.securityThreat => 'Known-threat rules',
};

class AlwaysOnProtectionsScreen extends StatelessWidget {
  const AlwaysOnProtectionsScreen({super.key, required this.policy});
  final PolicyRuntime policy;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: policy,
    builder: (context, _) => WingmanPage(
      title: 'Always-on protections',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mandatory category and security boundaries are built into the application. Private sessions, optional settings, review requests and compatibility corrections cannot turn them off. Live search previews use a separate provider filter; they are not classified against all six rules.',
          ),
          const SizedBox(height: 20),
          for (final category in MandatoryCategory.values)
            WingmanSettingsRow(
              icon: Icons.lock_outline,
              title: category.label,
              subtitle: 'Mandatory policy; filtering coverage varies',
            ),
          const SizedBox(height: 24),
          const WingmanSection(title: 'Policy & review data'),
          Text('Core policy version ${MandatorySafetyPolicy.version}'),
          Text(
            'Offline catalog version: ${policy.status.version ?? 'Unavailable'}',
          ),
          Text(
            'Offline catalog sequence: ${policy.status.sequence?.toString() ?? 'Unavailable'}',
          ),
          Text(
            'Offline article review expires: ${_reviewExpiry(policy.status.expiresAt)}',
          ),
          const SizedBox(height: 12),
          Text(
            'Reviewed Home website catalog expires: ${_reviewExpiry(policy.policy.livePolicy?.expiresAt)}',
          ),
          if (productEdition == ProductEdition.consumer) ...[
            Text(
              policy.consumerUpdatesConfigured
                  ? 'Online rule updates are configured. Wingman checks during startup; outages retain the last validated rules.'
                  : 'Online rule updates are not configured in this build. Install verified app updates to refresh the bundled rules.',
            ),
            Text(
              'Browsing protection: ${policy.consumerProtection.version ?? 'Recovery required'}',
            ),
            Text(
              'Protection data date: ${_reviewExpiry(policy.consumerProtection.generatedAt)}',
            ),
            Text(
              policy.consumerProtection.isUsable
                  ? policy.consumerProtection.isStale(policy.clock.now())
                        ? 'Protection data is older than 24 hours. The last validated rules remain active; coverage may be outdated.'
                        : 'Validated local protection data is installed.'
                  : 'No usable mandatory baseline is available. Browsing stays closed.',
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Installed articles and reviewed Home content use separate approval records. Consumer browsing permits ordinary destinations under local category and threat rules; the reviewed catalog does not grant browsing permission. School allowlisting remains separate. Filters can miss prohibited content or block legitimate pages. Dynamic ads, images and recommendations are not reliably classified. Browsing uses the last validated baseline during update outages and closes when no usable baseline exists.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Wingman Search always requires Strict provider filtering and separate query, preview and destination checks. These checks can miss content. An additional boundary can disable web search; private tabs inherit it.',
          ),
        ],
      ),
    ),
  );
}

String _reviewExpiry(DateTime? expiry) {
  if (expiry == null) return 'Unavailable';
  final utc = expiry.toUtc();
  final date = utc.toIso8601String().split('T').first;
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  return '$date at $hour:$minute UTC';
}
