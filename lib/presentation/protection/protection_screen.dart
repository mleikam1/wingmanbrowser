import 'package:flutter/material.dart';
import '../../config/product_edition.dart';
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
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final VoidCallback onReceipt, onRequestReview, onHome;
  final ValueChanged<String> onOpenApprovedResource;
  void _open(BuildContext context, Widget page) {
    if (canContinue()) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, policy]),
    builder: (context, _) => WingmanPage(
      title: 'Protection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [WingmanTokens.navy, WingmanTokens.light.action],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 32,
                  color: WingmanTokens.cyan,
                ),
                const SizedBox(height: 20),
                Text(
                  'Built-in boundaries.\nMore peace of mind.',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  productEdition == ProductEdition.consumer &&
                          !policy.consumerProtection.isUsable
                      ? 'Browsing is closed until mandatory protection data is recovered.'
                      : policy.status.usable
                      ? 'Mandatory category and security rules have no off switch.'
                      : 'Core rules remain active. Reviewed content is currently unavailable.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 14,
                    height: 20 / 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WingmanStatus(
            title: 'Coverage is limited',
            message:
                '${policy.status.resourceCount} reviewed offline articles. ${policy.liveAvailable(isPrivate: isPrivate) ? 'Consumer pages use local category and threat filtering. Unknown destinations may be permitted, not verified safe. Live content can change; there is no per-image or automatic text classifier.' : 'Live website support is unavailable in this session.'}',
            tone: WingmanTone.caution,
          ),
          const Text(
            'Filters can miss prohibited material or block legitimate pages. Alcohol, drug promotion and tobacco coverage is limited; dynamic ads and recommendations may not be classified.',
          ),
          WingmanStatus(
            title: 'Web search has a separate filtering scope',
            message:
                '${policy.searchAvailable(isPrivate: isPrivate, additional: state.protectedPreferences.additional) ? 'DuckDuckGo search is available with required Strict adult filtering.' : 'Web search is unavailable or disabled in this session.'} Search snippets and ads are not classified against all six Wingman rules. Clicked destinations are evaluated separately.',
            tone: WingmanTone.caution,
          ),
          const WingmanSection(title: 'Mandatory content policy'),
          for (final category in MandatoryCategory.values.where(
            (value) => value != MandatoryCategory.securityThreat,
          )) ...[
            ListTile(
              minTileHeight: 48,
              contentPadding: EdgeInsets.zero,
              title: Text(switch (category) {
                MandatoryCategory.sexualExplicit => 'Explicit entertainment',
                MandatoryCategory.gambling => 'Gambling & wagering',
                MandatoryCategory.alcoholPromotion => 'Alcohol promotion',
                MandatoryCategory.recreationalDrugPromotion =>
                  'Recreational-drug promotion',
                MandatoryCategory.tobaccoNicotine =>
                  'Tobacco & vaping promotion',
                MandatoryCategory.securityThreat => category.label,
              }),
              trailing: const Icon(Icons.lock_outline, size: 18),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 12),
          WingmanSettingsRow(
            icon: Icons.lock_outline,
            title: 'Always-on protections',
            subtitle: 'Read-only core rules and review status',
            onTap: () =>
                _open(context, AlwaysOnProtectionsScreen(policy: policy)),
          ),
          WingmanSettingsRow(
            icon: Icons.tune,
            title: 'Additional boundaries',
            subtitle: 'Disable web search or hide reviewed content',
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
            icon: Icons.security,
            title: 'Website request controls',
            subtitle: policy.liveAvailable(isPrivate: isPrivate)
                ? 'Native category, threat and tracker controls apply to supported requests. JavaScript, normal sign-in and user-initiated media use platform browser controls.'
                : 'Live website support is unavailable in this session.',
          ),
          WingmanSettingsRow(
            icon: Icons.receipt_long_outlined,
            title: 'Trust Receipt',
            subtitle: 'What Wingman observed, configured and cannot observe',
            onTap: () {
              if (canContinue()) onReceipt();
            },
          ),
          WingmanSettingsRow(
            icon: Icons.favorite_border,
            title: 'Help Now',
            subtitle: 'A quiet local pause and reviewed support',
            onTap: () => _open(
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
          ),
          WingmanSettingsRow(
            icon: Icons.fact_check_outlined,
            title: 'Request content review',
            subtitle: 'Review never grants temporary access',
            onTap: () {
              if (canContinue()) onRequestReview();
            },
          ),
        ],
      ),
    ),
  );
}

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
                  ? policy.consumerProtection.isStale(DateTime.now())
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
            'DuckDuckGo adult filtering stays Strict where native web search is supported. The provider can miss adult content, and its results and advertisements are not a six-category Wingman classification. An additional boundary can disable web search; private tabs inherit it.',
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
