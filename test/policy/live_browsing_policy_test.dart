import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/live_browsing_policy.dart';
import 'package:wingman_browser/policy/policy_models.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.bytes);
  final Uint8List bytes;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveBrowsingPolicy policy;
  final now = DateTime.utc(2026, 9, 11, 12);
  final moon = Uri.parse('https://science.nasa.gov/moon/facts/');

  setUpAll(() async {
    policy = await LiveBrowsingPolicy.load(
      bundle: _Bundle(await File(LiveBrowsingPolicy.assetPath).readAsBytes()),
    );
  });

  test(
    'build-pinned manifest loads reviewed scopes and maintained privacy data',
    () {
      expect(policy.errorCode, isNull);
      expect(policy.isUsable(now: now), isTrue);
      expect(policy.sites.map((s) => s.id), [
        'nasa-moon',
        'wikipedia-bulls',
        'adafruit-breadboard',
        'espn-bulls',
        'walmart-notebooks',
      ]);
      expect(policy.blockedThirdPartyDomains, hasLength(2501));
      expect(policy.privacyVersion, '2026.09.11.1');
      expect(policy.siteForUri(moon)!.resources.length, greaterThan(100));
    },
  );

  test('only the reviewed complete document URL grants navigation', () {
    expect(policy.assessNavigation(moon, now: now).isAllowed, isTrue);
    expect(policy.assessNavigation(moon, now: now).resourceId, 'nasa-moon');
    for (final address in [
      'https://science.nasa.gov/',
      'https://science.nasa.gov/moon/image-galleries/',
      'https://science.nasa.gov/moon/facts',
      'https://science.nasa.gov/moon/facts/more',
      'https://science.nasa.gov/moon/facts/?search=anything',
      'https://science.nasa.gov/moon/facts/?url=https://example.com/',
      'https://science.nasa.gov.evil.example/moon/facts/',
      'https://other.science.nasa.gov/moon/facts/',
    ]) {
      expect(
        policy.assessNavigation(Uri.parse(address), now: now).isAllowed,
        isFalse,
        reason: address,
      );
    }
  });

  test(
    'local anchors preserve eligibility without granting query authority',
    () {
      final anchor = moon.replace(fragment: 'surface');
      expect(policy.assessNavigation(anchor, now: now).isAllowed, isTrue);
      expect(policy.siteForUri(anchor)!.id, 'nasa-moon');
      expect(
        policy
            .assessNavigation(anchor.replace(query: 'w=1'), now: now)
            .isAllowed,
        isFalse,
      );
    },
  );

  test(
    'schemes credentials local targets ports and malformed scopes are denied',
    () {
      for (final address in [
        'http://science.nasa.gov/moon/facts/',
        'https://person:password@science.nasa.gov/moon/facts/',
        'https://science.nasa.gov:444/moon/facts/',
        'https://science.nasa.gov./moon/facts/',
        'https://127.0.0.1/moon/facts/',
        'https://[::1]/moon/facts/',
        'https://localhost/moon/facts/',
        'file:///moon/facts/',
        'data:text/html,<h1>not reviewed</h1>',
        'javascript:alert(1)',
        'https://science.nasa.gov/moon%2Ffacts/',
        'https://science.nasa.gov/moon/facts/%00',
      ]) {
        expect(
          policy.assessNavigation(Uri.parse(address), now: now).isAllowed,
          isFalse,
          reason: address,
        );
      }
    },
  );

  test(
    'a familiar sports or retail brand does not enable a disabled candidate',
    () {
      for (final site in policy.sites.where((s) => !s.enabled)) {
        final uri = Uri.parse(site.entryUrl);
        expect(policy.siteForUri(uri), site);
        expect(
          policy.assessNavigation(uri, now: now).code,
          PolicyDecisionCode.blockUnsupportedCapability,
        );
        expect(site.limitations, isNotEmpty);
      }
    },
  );

  test('manifest expiry and a clock before review fail closed', () {
    expect(policy.isUsable(now: DateTime.utc(2026, 9, 10, 23, 59)), isFalse);
    expect(policy.isUsable(now: DateTime.utc(2026, 10, 10, 23, 59)), isTrue);
    expect(policy.isUsable(now: DateTime.utc(2026, 10, 11)), isFalse);
    expect(
      policy.assessNavigation(moon, now: DateTime.utc(2026, 10, 11)).code,
      PolicyDecisionCode.blockPolicyUnavailable,
    );
  });

  test('additional restrictions subtract by stable site or collection', () {
    for (final restriction in [
      AdditionalRestrictions(blockedResourceIds: ['nasa-moon']),
      AdditionalRestrictions(blockedCollections: ['learning']),
    ]) {
      expect(
        policy.assessNavigation(moon, now: now, additional: restriction).code,
        PolicyDecisionCode.blockAdditionalRestriction,
      );
    }
    expect(
      policy
          .assessNavigation(
            moon,
            now: now,
            additional: AdditionalRestrictions(
              blockedResourceIds: ['unrelated'],
            ),
          )
          .isAllowed,
      isTrue,
    );
  });

  test(
    'student and normal contexts share the same supported document rules',
    () {
      for (final context in ContentContext.values) {
        expect(
          policy.assessNavigation(moon, context: context, now: now).isAllowed,
          isTrue,
        );
        expect(
          policy
              .assessNavigation(
                Uri.parse('https://www.espn.com/'),
                context: context,
                now: now,
              )
              .isAllowed,
          isFalse,
        );
      }
    },
  );

  test('passive image can load only under its eligible top-level document', () {
    final image = policy
        .siteForUri(moon)!
        .resources
        .firstWhere((r) => r.type == LiveResourceType.image);
    final uri = Uri.parse(image.url);
    expect(
      policy
          .assessResource(
            uri,
            topDocument: moon,
            type: LiveResourceType.image,
            now: now,
          )
          .isAllowed,
      isTrue,
    );
    expect(policy.assessNavigation(uri, now: now).isAllowed, isFalse);
    expect(
      policy
          .assessResource(
            uri,
            topDocument: Uri.parse('https://example.com/'),
            type: LiveResourceType.image,
            now: now,
          )
          .isAllowed,
      isFalse,
    );
    expect(
      policy
          .assessResource(
            uri,
            topDocument: moon,
            type: LiveResourceType.styleSheet,
            now: now,
          )
          .isAllowed,
      isFalse,
    );
    expect(
      policy
          .assessResource(
            uri.replace(query: 'unreviewed=1'),
            topDocument: moon,
            type: LiveResourceType.image,
            now: now,
          )
          .isAllowed,
      isFalse,
    );
  });

  test(
    'POST nested documents and unlisted resource redirects are rejected',
    () {
      final image = Uri.parse(
        policy
            .siteForUri(moon)!
            .resources
            .firstWhere((r) => r.type == LiveResourceType.image)
            .url,
      );
      for (final method in ['POST', 'PUT', 'HEAD', 'get']) {
        expect(
          policy
              .assessResource(
                image,
                topDocument: moon,
                type: LiveResourceType.image,
                method: method,
                now: now,
              )
              .isAllowed,
          isFalse,
        );
      }
      expect(
        policy
            .assessResource(
              moon,
              topDocument: moon,
              type: LiveResourceType.document,
              now: now,
            )
            .isAllowed,
        isFalse,
      );
      expect(
        policy
            .assessResource(
              Uri.parse('https://assets.science.nasa.gov/new.jpg'),
              topDocument: moon,
              type: LiveResourceType.image,
              now: now,
            )
            .isAllowed,
        isFalse,
      );
    },
  );

  test('resource evaluation immediately follows revocation and expiry', () {
    final image = Uri.parse(
      policy
          .siteForUri(moon)!
          .resources
          .firstWhere((r) => r.type == LiveResourceType.image)
          .url,
    );
    expect(
      policy
          .assessResource(
            image,
            topDocument: moon,
            type: LiveResourceType.image,
            now: now,
            additional: AdditionalRestrictions(
              blockedCollections: ['learning'],
            ),
          )
          .code,
      PolicyDecisionCode.blockAdditionalRestriction,
    );
    expect(
      policy
          .assessResource(
            image,
            topDocument: moon,
            type: LiveResourceType.image,
            now: DateTime.utc(2026, 10, 11),
          )
          .code,
      PolicyDecisionCode.blockPolicyUnavailable,
    );
  });

  test(
    'privacy adaptation uses suffix boundaries without broad substring matches',
    () {
      expect(
        policy.isKnownThirdPartyTracker(
          Uri.parse('https://metrics.hotjar.com/a'),
          moon,
        ),
        isTrue,
      );
      expect(
        policy.isKnownThirdPartyTracker(
          Uri.parse('https://not-hotjar.com/a'),
          moon,
        ),
        isFalse,
      );
      expect(
        policy.isKnownThirdPartyTracker(
          Uri.parse('https://hotjar.com.evil.example/a'),
          moon,
        ),
        isFalse,
      );
      expect(
        policy.isKnownThirdPartyTracker(
          Uri.parse('https://hotjar.com/a'),
          Uri.parse('https://hotjar.com/'),
        ),
        isFalse,
      );
      expect(
        policy
            .assessResource(
              Uri.parse('https://metrics.hotjar.com/a'),
              topDocument: moon,
              type: LiveResourceType.image,
              now: now,
            )
            .isAllowed,
        isFalse,
      );
    },
  );

  test(
    'tampering with enabled sites or relaxing resource scope invalidates entire manifest',
    () async {
      final original = await File(LiveBrowsingPolicy.assetPath).readAsString();
      final data = jsonDecode(original) as Map<String, dynamic>;
      (data['sites'] as List).firstWhere(
        (s) => s['id'] == 'espn-bulls',
      )['enabled'] = true;
      data['allowAllHosts'] = true;
      final tampered = await LiveBrowsingPolicy.load(
        bundle: _Bundle(Uint8List.fromList(utf8.encode(jsonEncode(data)))),
      );
      expect(tampered.errorCode, 'manifest-integrity');
      expect(tampered.sites, isEmpty);
      expect(tampered.assessNavigation(moon, now: now).isAllowed, isFalse);
    },
  );

  test('missing oversized and unrelated assets fail closed', () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List(LiveBrowsingPolicy.maxManifestBytes + 1),
      Uint8List.fromList(utf8.encode('{"allow":true}')),
    ]) {
      final invalid = await LiveBrowsingPolicy.load(bundle: _Bundle(bytes));
      expect(invalid.isUsable(now: now), isFalse);
      expect(
        invalid.assessNavigation(moon, now: now).code,
        PolicyDecisionCode.blockPolicyUnavailable,
      );
    }
  });

  test(
    'three distinct visual journeys include only their exact reviewed pages',
    () {
      final enabled = policy.sites.where((s) => s.enabled).toList();
      expect(enabled.map((s) => s.id), [
        'nasa-moon',
        'wikipedia-bulls',
        'adafruit-breadboard',
      ]);
      expect(enabled.fold<int>(0, (n, s) => n + s.documents.length), 6);
      for (final site in enabled) {
        for (final document in site.documents) {
          expect(
            policy
                .assessNavigation(Uri.parse(document.url), now: now)
                .resourceId,
            site.id,
          );
        }
        final image = site.resources.firstWhere(
          (r) => r.type == LiveResourceType.image,
        );
        expect(
          policy
              .assessResource(
                Uri.parse(image.url),
                topDocument: Uri.parse(site.entryUrl),
                type: LiveResourceType.image,
                now: now,
              )
              .isAllowed,
          isTrue,
        );
        expect(
          policy
              .assessNavigation(
                Uri.parse(site.entryUrl).replace(path: '/'),
                now: now,
              )
              .isAllowed,
          isFalse,
        );
        expect(
          policy
              .assessNavigation(
                Uri.parse(site.entryUrl),
                now: now,
                additional: AdditionalRestrictions(
                  blockedResourceIds: [site.id],
                ),
              )
              .isAllowed,
          isFalse,
        );
        expect(
          policy
              .assessNavigation(Uri.parse(site.entryUrl), now: policy.expiresAt)
              .isAllowed,
          isFalse,
        );
      }
    },
  );

  test('a product resource cannot load inside a different approved source', () {
    final shop = policy.sites.firstWhere((s) => s.id == 'adafruit-breadboard');
    final image = shop.resources.firstWhere(
      (r) => r.type == LiveResourceType.image,
    );
    expect(
      policy
          .assessResource(
            Uri.parse(image.url),
            topDocument: moon,
            type: LiveResourceType.image,
            now: now,
          )
          .isAllowed,
      isFalse,
    );
    expect(
      policy
          .assessNavigation(
            Uri.parse('https://www.adafruit.com/product/153'),
            now: now,
          )
          .isAllowed,
      isFalse,
    );
    expect(
      policy
          .assessNavigation(
            Uri.parse('https://en.wikipedia.org/wiki/Basketball'),
            now: now,
          )
          .isAllowed,
      isFalse,
    );
  });

  test('published policy collections are immutable', () {
    final site = policy.siteForUri(moon)!;
    expect(() => policy.sites.clear(), throwsUnsupportedError);
    expect(() => site.resources.clear(), throwsUnsupportedError);
    expect(() => site.contexts.clear(), throwsUnsupportedError);
    expect(
      () => policy.blockedThirdPartyDomains.clear(),
      throwsUnsupportedError,
    );
  });
}
