import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/policy/policy_models.dart';

void main() {
  test(
    'native denial vocabulary never infers sensitive category from unknown reason',
    () {
      for (final event in [
        <String, Object?>{},
        {
          'reasonCode': 'allowPermitted',
          'url': 'https://private.example/secret',
        },
        {'reasonCode': 'blockMandatoryCategory', 'category': 'invented'},
        {'reason': 'explicit wording in arbitrary text'},
      ]) {
        final decision = nativeBoundaryDecision(event);
        expect(decision.code, PolicyDecisionCode.blockUnsupportedCapability);
        expect(decision.category, isNull);
        expect(decision.safeTitle, isNull);
        expect(decision.resourceId, isNull);
      }
    },
  );
  test(
    'known enforcement category, threat, and unavailable reasons remain distinct',
    () {
      for (final category in MandatoryCategory.values) {
        final decision = nativeBoundaryDecision({
          'reasonCode': 'blockMandatoryCategory',
          'category': category.id,
        });
        expect(decision.category, category);
        expect(
          decision.code,
          category == MandatoryCategory.securityThreat
              ? PolicyDecisionCode.blockSecurityThreat
              : PolicyDecisionCode.blockMandatoryCategory,
        );
      }
      for (final code in [
        PolicyDecisionCode.blockAdditionalRestriction,
        PolicyDecisionCode.blockPolicyUnavailable,
        PolicyDecisionCode.blockSecurityThreat,
        PolicyDecisionCode.blockUnsupportedCapability,
      ]) {
        expect(nativeBoundaryDecision({'reasonCode': code.name}).code, code);
      }
    },
  );
}
