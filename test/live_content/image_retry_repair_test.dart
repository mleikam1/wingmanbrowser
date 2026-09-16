import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';

import 'article_images_test.dart' as photos;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'extreme publisher image hold never becomes an immediate retry',
    () async {
      final transport = photos.Images()
        ..failure = const RssFailure(
          'image-status',
          status: 429,
          headers: {'retry-after': '9999999999'},
        );
      var now = photos.now;
      final loader = ArticleImageLoader(
        eligibility: photos.gate(),
        transport: transport,
        clock: () => now,
      );
      addTearDown(() => loader.cancel(clear: true));
      final item = photos.item(1);
      await loader.load([item], onChanged: () {});
      expect(loader.statusFor(item)['outcome'], 'publisher-hold');
      expect(loader.nextRetryAt, isNull);
      for (var n = 0; n < 4; n++) {
        now = now.add(const Duration(hours: 1));
        await loader.load([item], onChanged: () {});
      }
      expect(transport.calls, hasLength(1));
      expect(loader.bytesFor(item), isNull);
    },
  );

  testWidgets(
    'batch timeout leaves a paced availability outcome instead of eternal loading',
    (tester) async {
      final pending = Completer<RssFetchResponse>();
      final transport = photos.Images()..pending = pending;
      var now = photos.now;
      final loader = ArticleImageLoader(
        eligibility: photos.gate(),
        transport: transport,
        clock: () => now,
      );
      addTearDown(() => loader.cancel(clear: true));
      final item = photos.item(1);
      var changes = 0;
      final loading = loader.load([item], onChanged: () => changes++);
      await tester.pump();
      expect(loader.statusFor(item)['outcome'], 'loading');
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      await loading;
      expect(loader.statusFor(item)['outcome'], isNot('loading'));
      expect(loader.nextRetryAt, isNotNull);
      expect(loader.nextRetryAt!.isAfter(now), isTrue);
      expect(changes, 0);
      await loader.load([item], onChanged: () => changes++);
      expect(transport.calls, hasLength(1));
      pending.complete(
        RssFetchResponse(200, photos.png, const {'content-type': 'image/png'}),
      );
      await tester.pump();
      expect(loader.bytesFor(item), isNull);
      expect(changes, 0);
    },
  );
}
