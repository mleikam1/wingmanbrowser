import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_profiles.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report.dart';

import '../policy/policy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'minimal report has no domain by default and reports nothing submitted',
    () {
      final report = CompatibilityReport(
        issue: CompatibilityIssue.layoutInteraction,
        diagnostics: CompatibilityDiagnostics(
          appVersion: '0.5.0+5',
          policyVersion: 1,
          capability: CompatibilityCapability.bundledReader,
        ),
      );
      expect(report.toJson().keys, isNot(contains('reviewedDomain')));
      expect(report.toText(), contains('Nothing submitted'));
      expect(report.toJson()['status'], 'local-only-not-submitted');
      expect(
        () => CompatibilityDiagnostics(
          appVersion: 'https://private.test',
          policyVersion: 1,
          capability: CompatibilityCapability.unknown,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'domain opt-in accepts a bare name and rejects sensitive URL material',
    () {
      expect(DiagnosticDomain.parse(' Example.COM ').value, 'example.com');
      for (final input in [
        'https://example.com',
        'user:password@example.com',
        'example.com/account?token=secret',
        'example.com#secret',
        '127.0.0.1',
        'example.com/',
        'example.com:443',
        'example.com\nsecret',
        'evil..com',
        'éxample.com',
        '-example.com',
      ]) {
        expect(
          () => DiagnosticDomain.parse(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );

  Future<(PolicyRuntime, CompatibilityProfileRegistry)> setup({
    bool fixtures = true,
    DateTime Function()? clock,
  }) async {
    final fixture = await PolicyFixture.create();
    final runtime = await PolicyRuntime.initialize(
      repository: SignedPolicyRepository(
        bundle: await fixture.bundle(),
        verifier: await fixture.verifier(),
        clock: PolicyClock(wallClock: () => policyTestTime),
      ),
      checkpointStore: MemoryPolicyCheckpointStore(),
    );
    final registry = CompatibilityProfileRegistry(
      policy: runtime,
      clock: clock ?? () => policyTestTime,
      allowControlledFixtures: fixtures,
    );
    addTearDown(() {
      registry.dispose();
      runtime.dispose();
    });
    return (runtime, registry);
  }

  Map<String, Object?> profile(PolicyRuntime runtime) => {
    'id': 'fixture-wrap',
    'resourceId': 'seed-science',
    'resourceSha256': runtime.resource('seed-science')!.sha256,
    'policyVersion': 1,
    'correction': 'wrapLongLines',
    'evidence': 'controlledFixture',
    'evidenceId': 'fixture-narrow-viewport',
    'reviewedAt': DateTime.utc(2026, 9, 10).toIso8601String(),
    'expiresAt': DateTime.utc(2026, 10, 10).toIso8601String(),
  };
  CompatibilityProfilePack pack(
    List<Map<String, Object?>> profiles, {
    int sequence = 1,
    List<String> revoked = const [],
  }) => CompatibilityProfilePack.parse(
    jsonEncode({
      'schema': 1,
      'sequence': sequence,
      'profiles': profiles,
      'revokedIds': revoked,
    }),
  );

  test(
    'empty production registry rejects controlled evidence and weakening schema',
    () async {
      final (runtime, registry) = await setup(fixtures: false);
      expect(registry.activeProfileCount, 0);
      expect(
        () => registry.activateReviewedPack(pack([profile(runtime)])),
        throwsFormatException,
      );
      for (final key in [
        'disableGuard',
        'ignoreTls',
        'javascript',
        'allowHost',
        'grantPermissions',
        'externalBrowser',
        'trackingExemption',
      ]) {
        expect(
          () => pack([
            {...profile(runtime), key: true},
          ]),
          throwsFormatException,
        );
      }
      expect(
        () => pack([
          {...profile(runtime), 'correction': 'executeScript'},
        ]),
        throwsFormatException,
      );
    },
  );

  test(
    'exact digest and resource scope; policy denial always precedes correction',
    () async {
      final (runtime, registry) = await setup();
      registry.activateReviewedPack(pack([profile(runtime)]));
      expect(
        registry.resolve('seed-science', baselineSoftWrap: false).softWrap,
        true,
      );
      for (final sibling in [
        'seed-science-gambling',
        'seed-science-alcohol',
        'unreviewed',
      ]) {
        expect(registry.resolve(sibling).allowed, false);
      }
      expect(
        registry
            .resolve(
              'seed-science',
              additional: AdditionalRestrictions(
                blockedResourceIds: ['seed-science'],
              ),
            )
            .allowed,
        false,
      );
      expect(
        runtime.policy
            .evaluate(
              PolicyRequest.navigation(
                Uri.parse('https://science.example.test'),
              ),
            )
            .isAllowed,
        false,
      );
      registry.activateReviewedPack(
        pack([
          {...profile(runtime), 'resourceSha256': List.filled(64, '0').join()},
        ], sequence: 2),
      );
      final mismatch = registry.resolve(
        'seed-science',
        baselineSoftWrap: false,
      );
      expect(mismatch.allowed, true);
      expect(mismatch.softWrap, false);
      expect(mismatch.profileId, isNull);
    },
  );

  test(
    'revocation and replay cannot restore correction or weaken content policy',
    () async {
      final (runtime, registry) = await setup();
      registry.activateReviewedPack(pack([profile(runtime)]));
      registry.activateReviewedPack(
        pack([], sequence: 2, revoked: ['fixture-wrap']),
      );
      expect(
        registry.resolve('seed-science', baselineSoftWrap: false).softWrap,
        false,
      );
      expect(
        () => registry.activateReviewedPack(pack([profile(runtime)])),
        throwsFormatException,
      );
      registry.activateReviewedPack(pack([profile(runtime)], sequence: 3));
      expect(registry.resolve('seed-science').profileId, isNull);
      expect(registry.resolve('seed-science-gambling').allowed, false);
    },
  );

  test(
    'expiry removes a correction and a backward clock cannot revive it',
    () async {
      var now = policyTestTime;
      final (runtime, registry) = await setup(clock: () => now);
      registry.activateReviewedPack(
        pack([
          {
            ...profile(runtime),
            'expiresAt': policyTestTime
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        ]),
      );
      expect(
        registry.resolve('seed-science', baselineSoftWrap: false).softWrap,
        true,
      );
      now = now.add(const Duration(hours: 2));
      expect(
        registry.resolve('seed-science', baselineSoftWrap: false).softWrap,
        false,
      );
      now = policyTestTime;
      expect(
        registry.resolve('seed-science', baselineSoftWrap: false).softWrap,
        false,
      );
      expect(registry.resolve('seed-science-gambling').allowed, false);
    },
  );

  testWidgets(
    'controlled eligible clipped reader is repaired at narrow width; sibling stays closed',
    (tester) async {
      final (runtime, registry) = (await tester.runAsync(() => setup()))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 140,
                child: CompatibleReaderText(
                  resourceId: 'seed-science',
                  registry: registry,
                  baselineSoftWrap: false,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester
          .getSize(find.byKey(const ValueKey('compatible-reader-body')))
          .height;
      registry.activateReviewedPack(pack([profile(runtime)]));
      await tester.pump();
      final after = tester
          .getSize(find.byKey(const ValueKey('compatible-reader-body')))
          .height;
      expect(after, greaterThan(before * 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: CompatibleReaderText(
            resourceId: 'seed-science-gambling',
            registry: registry,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('compatible-reader-body')),
        findsNothing,
      );
      expect(
        find.text('This resource is not currently eligible.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    },
  );
}
