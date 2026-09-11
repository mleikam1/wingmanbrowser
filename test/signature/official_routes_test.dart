import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/official_routes/official_route.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import '../support/protected_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Object?> source;
  late OfficialRouteCatalog catalog;
  setUp(() {
    source = Map<String, Object?>.from(
      jsonDecode(
            File('assets/signature/official_routes.json').readAsStringSync(),
          )
          as Map,
    );
    catalog = OfficialRouteCatalog.decode(jsonEncode(source));
  });
  test('18 real identities have bounded exact scopes and review evidence', () {
    expect(catalog.routes, hasLength(18));
    for (final route in catalog.routes) {
      expect(route.evidence.length, greaterThanOrEqualTo(2));
      expect(route.policyCategoryIds, hasLength(6));
      expect(
        route.identityStatus(DateTime.utc(2026, 9, 11, 12)),
        RouteIdentityStatus.reviewed,
      );
      expect(route.matchesDestination(route.destination.toString()), isTrue);
      expect(
        route.matchesDestination('${route.destination}/another-page'),
        isFalse,
      );
      expect(route.destination.host.endsWith('.test'), isFalse);
    }
    expect(
      catalog.search('passport', region: 'United Kingdom').single.id,
      'uk-passport',
    );
    expect(catalog.search('not-in-this-catalog'), isEmpty);
    expect(catalog.search('x' * 201), isEmpty);
  });
  test(
    'lookalikes, unknown subdomains, altered paths and query changes never match',
    () {
      final apple = catalog.routes.firstWhere((r) => r.id == 'apple-support');
      for (final candidate in [
        'https://support.apple.com.attacker.test/contact',
        'https://fake.support.apple.com/contact',
        'https://support.apple.com/contact?return=https://attacker.test',
        'https://support.apple.com/contact#another',
        'http://support.apple.com/contact',
        'https://user:secret@support.apple.com/contact',
        'https://support.apple.com:443/contact',
        'https://support.apple.com./contact',
        'https://support.apple.com/%63ontact',
        'https://support.apple.com/a/../contact',
        'https://suppоrt.apple.com/contact', // Cyrillic o.
        'https://xn--pple-43d.com/contact',
        'https://support.apple.com\\@attacker.test/contact',
      ]) {
        expect(apple.matchesDestination(candidate), isFalse, reason: candidate);
      }
    },
  );
  test(
    'review cannot grant live eligibility in either session or context',
    () async {
      final policy = await loadTestPolicy(
        clock: () => DateTime.utc(2026, 9, 11, 12),
      );
      addTearDown(policy.dispose);
      for (final route in catalog.routes) {
        for (final private in [true, false]) {
          for (final context in ContentContext.values) {
            final assessment = route.assess(
              policy,
              now: DateTime.utc(2026, 9, 11, 12),
              isPrivate: private,
              context: context,
            );
            expect(assessment.canOpen, isFalse);
            expect(assessment.showsActiveVerificationBadge, isFalse);
            expect(
              assessment.policyDecision.code,
              PolicyDecisionCode.blockUnsupportedCapability,
            );
          }
        }
      }
    },
  );
  test('expiry and revocation are distinct and cannot leave active review', () {
    final row = Map<String, Object?>.from(
      (source['routes'] as List).first as Map,
    );
    final route = OfficialRoute.fromJson(row);
    expect(route.identityStatus(route.expiresAt), RouteIdentityStatus.expired);
    expect(
      route.identityStatus(
        route.reviewedAt.subtract(const Duration(seconds: 1)),
      ),
      RouteIdentityStatus.notYetReviewed,
    );
    row['status'] = 'revoked';
    expect(
      OfficialRoute.fromJson(row).identityStatus(route.reviewedAt),
      RouteIdentityStatus.revoked,
    );
  });
  test(
    'forged, oversized and ambiguous catalog records reject the whole catalog',
    () {
      final pristine = jsonEncode(source);
      for (final mutation in <void Function(Map<String, Object?>)>[
        (j) => j['identityHost'] = 'attacker.test',
        (j) => j['navigationScope'] = 'all-subdomains',
        (j) => j['policyVersion'] = 0,
        (j) => j['policyCategoryIds'] = ['security-threat'],
        (j) => j['evidence'] = [],
        (j) => j['expiresAt'] = '2028-09-11T00:00:00Z',
        (j) => j['destination'] = 'https://127.0.0.1/',
      ]) {
        final next = Map<String, Object?>.from(jsonDecode(pristine) as Map);
        final rows = next['routes'] as List;
        final row = Map<String, Object?>.from(rows.first as Map);
        mutation(row);
        rows[0] = row;
        expect(
          () => OfficialRouteCatalog.decode(jsonEncode(next)),
          throwsFormatException,
        );
      }
      (source['routes'] as List).add((source['routes'] as List).first);
      expect(
        () => OfficialRouteCatalog.decode(jsonEncode(source)),
        throwsFormatException,
      );
      expect(
        () => OfficialRouteCatalog.decode(
          ' ' * (OfficialRouteCatalog.maximumBytes + 1),
        ),
        throwsFormatException,
      );
    },
  );
}
