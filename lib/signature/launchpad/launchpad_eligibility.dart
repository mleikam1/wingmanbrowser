import '../../policy/policy_runtime.dart';
import 'launchpad_models.dart';

class LaunchpadEligibility {
  const LaunchpadEligibility({
    required this.canOpen,
    required this.message,
    this.canRetainInactive = false,
    this.policyCode,
  });
  final bool canOpen, canRetainInactive;
  final String message;
  final PolicyDecisionCode? policyCode;
}

/// Presentation records never carry a permission. Call for every render/open/save.
class LaunchpadEligibilityService {
  LaunchpadEligibilityService({
    required this.resourceEligible,
    this.evaluateWebsite,
    this.toolAvailable,
    this.resourceLookup,
    this.websiteAvailable,
  });
  final bool Function(String) resourceEligible;
  final PolicyDecision Function(Uri)? evaluateWebsite;
  final bool Function(LaunchpadTool)? toolAvailable;
  final ApprovedResource? Function(String)? resourceLookup;
  final bool Function()? websiteAvailable;
  LaunchpadEligibility assess(LaunchpadTarget target) {
    try {
      LaunchpadTarget.fromJson(target.toJson());
      switch (target.kind) {
        case LaunchpadKind.resource:
          return resourceEligible(target.value)
              ? const LaunchpadEligibility(
                  canOpen: true,
                  message: 'Reviewed article · Available offline',
                )
              : const LaunchpadEligibility(
                  canOpen: false,
                  message: 'This reviewed resource is currently unavailable.',
                  policyCode: PolicyDecisionCode.blockUnreviewed,
                );
        case LaunchpadKind.tool:
          final tool = target.tool!;
          final allowed =
              toolAvailable?.call(tool) ?? tool != LaunchpadTool.helpNow;
          return LaunchpadEligibility(
            canOpen: allowed,
            message: allowed
                ? 'Wingman tool · On this device'
                : 'This tool is unavailable in this session.',
          );
        case LaunchpadKind.website:
          final uri = Uri.parse(target.value);
          // Search terms must not become persistent shortcuts, including an
          // inactive review record or a caller-forged allow decision.
          if (uri.host == 'duckduckgo.com' ||
              uri.host.endsWith('.duckduckgo.com') ||
              const {'duck.com', 'www.duck.com', 'ddg.gg'}.contains(uri.host)) {
            return const LaunchpadEligibility(
              canOpen: false,
              message:
                  'Search pages cannot be saved. Pin a reviewed result page instead.',
              policyCode: PolicyDecisionCode.blockUnsupportedCapability,
            );
          }
          final decision =
              evaluateWebsite?.call(uri) ??
              const PolicyDecision(
                PolicyDecisionCode.blockUnsupportedCapability,
              );
          // A decision alone cannot provide a native renderer or companion
          // transport. The application also supplies current capability.
          final capable = websiteAvailable?.call() ?? false;
          final code = capable
              ? decision.code
              : decision.isAllowed
              ? PolicyDecisionCode.blockUnsupportedCapability
              : decision.code;
          final retained = {
            PolicyDecisionCode.blockUnsupportedCapability,
            PolicyDecisionCode.blockUnreviewed,
            PolicyDecisionCode.blockPolicyUnavailable,
          }.contains(code);
          return LaunchpadEligibility(
            canOpen: capable && decision.isAllowed,
            canRetainInactive: retained,
            policyCode: code,
            message: capable && decision.isAllowed
                ? 'Website shortcut · Current destination rules apply'
                : retained
                ? 'Inactive local review record. This destination is outside the supported website scope for this session; nothing is submitted.'
                : 'This destination cannot be saved as an active shortcut.',
          );
      }
    } catch (_) {
      return const LaunchpadEligibility(
        canOpen: false,
        message: 'This destination could not be checked.',
        policyCode: PolicyDecisionCode.blockPolicyUnavailable,
      );
    }
  }

  String presentedTitle(LaunchpadShortcut shortcut) =>
      targetTitle(shortcut.target, shortcut.title);
  String targetTitle(LaunchpadTarget target, String title) =>
      target.kind == LaunchpadKind.resource && !assess(target).canOpen
      ? 'Unavailable resource'
      : title;
  String destinationLabel(LaunchpadTarget target) => switch (target.kind) {
    LaunchpadKind.website => target.value,
    LaunchpadKind.tool => target.tool?.label ?? 'Unavailable tool',
    LaunchpadKind.resource =>
      assess(target).canOpen
          ? resourceLookup?.call(target.value)?.title ??
                'Reviewed offline article'
          : 'Reviewed resource unavailable',
  };
}
