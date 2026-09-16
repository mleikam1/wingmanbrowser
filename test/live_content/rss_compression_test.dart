import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/rss_transport.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';

void main() {
  Future<List<int>> decode(
    List<int> body, {
    String encoding = 'gzip',
    int wire = 1024,
    int expanded = 4096,
    void Function()? validate,
  }) => readBoundedRssBody(
    Stream<List<int>>.fromIterable([body]),
    encoding: encoding,
    maximumWireBytes: wire,
    maximumDecodedBytes: expanded,
    validateDeadline: validate ?? () {},
  );
  test('standard gzip and deflate decode original feed bytes', () async {
    final body = utf8.encode(
      '<rss><channel><title>News</title></channel></rss>',
    );
    expect(await decode(gzip.encode(body)), body);
    expect(await decode(zlib.encode(body), encoding: 'deflate'), body);
    expect(await decode(body, encoding: 'identity'), body);
  });
  test('wire and expanded bounds apply independently', () async {
    final body = gzip.encode(utf8.encode('x' * 10000));
    expect(body.length, lessThan(1024));
    await expectLater(
      decode(body, wire: 8),
      throwsA(
        isA<RssFailure>().having((e) => e.code, 'reason', 'body-too-large'),
      ),
    );
    await expectLater(
      decode(body),
      throwsA(
        isA<RssFailure>().having(
          (e) => e.code,
          'reason',
          'decoded-body-too-large',
        ),
      ),
    );
  });
  test(
    'unknown stacking and invalid compressed payload are rejected',
    () async {
      for (final encoding in ['br', 'gzip, deflate']) {
        await expectLater(
          decode([1, 2, 3], encoding: encoding),
          throwsA(
            isA<RssFailure>().having(
              (e) => e.code,
              'reason',
              'unsupported-encoding',
            ),
          ),
        );
      }
      await expectLater(
        decode([1, 2, 3, 4]),
        throwsA(
          isA<RssFailure>().having(
            (e) => e.code,
            'reason',
            'invalid-compression',
          ),
        ),
      );
    },
  );
  test(
    'decode observes deadline and private cancellation during expansion',
    () async {
      var checks = 0;
      final body = gzip.encode(utf8.encode('x' * 1000));
      await expectLater(
        decode(
          body,
          validate: () {
            if (++checks > 2) throw const RssFailure('cancelled');
          },
        ),
        throwsA(isA<RssFailure>().having((e) => e.code, 'reason', 'cancelled')),
      );
      expect(checks, greaterThan(2));
    },
  );
}
