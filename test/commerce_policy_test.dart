import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/config/product_edition.dart';
import 'package:wingman_browser/monetization/commerce_policy.dart';
import 'package:wingman_browser/monetization/sponsorship_catalog.dart';

void main() {
  const policy = CommercePolicy();
  const catalog = EmptySponsorshipCatalog();

  test(
    'built edition matches the independently specified packaging target',
    () {
      const expected = String.fromEnvironment(
        'EXPECTED_EDITION',
        defaultValue: 'consumer',
      );
      expect(productEdition.name, expected);
    },
  );

  CommerceContext context({
    ProductEdition edition = ProductEdition.consumer,
    CommerceSurface surface = CommerceSurface.home,
    bool isPrivate = false,
    bool current = true,
    bool foreground = true,
  }) => CommerceContext(
    edition: edition,
    surface: surface,
    isPrivate: isPrivate,
    isCurrentRoute: current,
    isForeground: foreground,
  );

  test(
    'every audience, surface and private state has no display capability',
    () {
      for (final edition in ProductEdition.values) {
        for (final surface in CommerceSurface.values) {
          for (final isPrivate in [false, true]) {
            expect(
              policy.canDisplay(
                context(
                  edition: edition,
                  surface: surface,
                  isPrivate: isPrivate,
                ),
              ),
              isFalse,
            );
          }
        }
      }
    },
  );

  test('student and unknown editions deny even eligible consumer Home', () {
    expect(
      policy.evaluate(context(edition: ProductEdition.student)),
      CommerceDecision.studentEdition,
    );
    expect(
      policy.evaluate(context(edition: ProductEdition.unknown)),
      CommerceDecision.unknownEdition,
    );
  });

  test('private mode and all non-Home surfaces deny commercial placement', () {
    expect(
      policy.evaluate(context(isPrivate: true)),
      CommerceDecision.privateSession,
    );
    for (final surface in CommerceSurface.values) {
      if (surface == CommerceSurface.home) continue;
      expect(
        policy.evaluate(context(surface: surface)),
        CommerceDecision.prohibitedSurface,
      );
    }
  });

  test('background and covered Home remain ineligible', () {
    expect(
      policy.evaluate(context(current: false)),
      CommerceDecision.inactiveSurface,
    );
    expect(
      policy.evaluate(context(foreground: false)),
      CommerceDecision.inactiveSurface,
    );
  });

  test('consumer Home cannot activate inventory through legacy ad defines', () {
    // Run this suite with WINGMAN_TEST_ADS=true and former banner-ID defines.
    // The policy has no environment-reading or SDK initialization path.
    expect(policy.evaluate(context()), CommerceDecision.inventoryDisabled);
    expect(policy.canDisplay(context()), isFalse);
  });

  test('default catalog is empty for every edition and surface', () async {
    for (final edition in ProductEdition.values) {
      for (final surface in CommerceSurface.values) {
        expect(
          await catalog.forContext(context(edition: edition, surface: surface)),
          isEmpty,
        );
      }
    }
  });

  test(
    'default policy context uses the compile-time edition and fails closed',
    () {
      expect(const CommerceContext().edition, productEdition);
      expect(policy.canDisplay(const CommerceContext()), isFalse);
    },
  );
}
