import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/branding.dart';

Map<String, Object?> reviewedBranding() => {
  'approved': true,
  'asset': 'assets/publisher_logos/fixture.png',
  'darkAsset': 'assets/publisher_logos/fixture_dark.webp',
  'sourceUrl': 'https://publisher.example/brand',
  'termsUrl': 'https://publisher.example/brand/terms',
  'usageBasis': 'Synthetic test permission for publisher identification',
  'credit': 'Fixture publisher',
  'reviewedAt': '2026-09-01T00:00:00Z',
  'expiresAt': '2026-10-01T00:00:00Z',
};

void main() {
  test(
    'branding requires explicit independent approval and bounded local raster assets',
    () {
      for (final change in <Map<String, Object?>>[
        {'approved': false},
        {'approved': 'true'},
        {'asset': 'https://publisher.example/logo.png'},
        {'asset': 'assets/publisher_logos/logo.svg'},
        {'asset': 'assets/publisher_logos/../story_images/photo.jpg'},
        {'darkAsset': 'assets/brand/wingman-mark.png'},
        {'termsUrl': 'https://owner:secret@publisher.example/terms'},
        {'sourceUrl': 'javascript:alert(1)'},
        {'reviewedAt': '2026-09-01'},
        {'expiresAt': '2026-08-01T00:00:00Z'},
        {'usageBasis': '<script>not permission</script>'},
      ]) {
        expect(
          PublisherBranding.tryFromJson({...reviewedBranding(), ...change}),
          isNull,
          reason: change.keys.single,
        );
      }
      expect(PublisherBranding.tryFromJson(null), isNull);
      expect(
        PublisherBranding.tryFromJson({
          'url': 'https://publisher.example/favicon.ico',
        }),
        isNull,
      );
    },
  );

  test(
    'review dates, expiry and approved dark variants survive round trip',
    () {
      final brand = PublisherBranding.tryFromJson(reviewedBranding())!;
      expect(brand.isCurrent(DateTime.utc(2026, 9, 15)), isTrue);
      expect(brand.isCurrent(DateTime.utc(2026, 8, 31)), isFalse);
      expect(brand.isCurrent(DateTime.utc(2026, 10, 1)), isFalse);
      expect(brand.assetFor(), 'assets/publisher_logos/fixture.png');
      expect(
        brand.assetFor(dark: true),
        'assets/publisher_logos/fixture_dark.webp',
      );
      expect(
        PublisherBranding.tryFromJson(brand.toJson())!.toJson(),
        brand.toJson(),
      );
    },
  );
}
