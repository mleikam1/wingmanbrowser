import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/image_headers.dart';
import 'package:wingman_browser/live_content/image_loader.dart';
import 'package:wingman_browser/live_content/models.dart';

// Generated 90px solid-color fixtures. No publisher images or network required.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAFoAAABaCAIAAAC3ytZVAAAAwUlEQVR4nO3QMRGAMADAwLYisFMh+PfRCY6g4X/KnHnte/BYb2HHnx1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gRdoQdYUfYEXaEHWFH2BF2hB1hR9gxvg5iKgFkbdVUZgAAAABJRU5ErkJggg==',
);
final jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCABaAFoDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDzWiiivTPLCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//9k=',
);
final webp = base64Decode(
  'UklGRlYAAABXRUJQVlA4IEoAAADQBACdASpaAFoAPm02mUmkIyKhIOgAgA2JaQB2AAAO7Kr5e4095N9OnTp06dOm+AD+9Vi//i2KQ3M/+6DLOGfw6PbNHAAAAAAAAA==',
);
final webpLossless = base64Decode(
  'UklGRiQAAABXRUJQVlA4TBcAAAAvWUAWAAfQn1p0q/9hABLC//1SRP9TGwA=',
);

LiveArticleImage image({int width = 90, int height = 90}) => LiveArticleImage(
  url: Uri.parse('https://images.example/photo.png'),
  articleUrl: Uri.parse('https://publisher.example/story'),
  sourceId: 'fixture',
  credit: 'Synthetic test fixture',
  caption: 'Solid color',
  licenseUrl: Uri.parse('https://publisher.example/terms'),
  licenseLabel: 'Fixture',
  basis: 'syndicated-feed-thumbnail',
  width: width,
  height: height,
);

Uint8List copy(Uint8List value) => Uint8List.fromList(value);
void be32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value);
void le32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
Uint8List chunk(String name, List<int> data) {
  final result = Uint8List(8 + data.length + (data.length & 1));
  result.setRange(0, 4, name.codeUnits);
  le32(result, 4, data.length);
  result.setRange(8, 8 + data.length, data);
  return result;
}

Uint8List riff(List<int> chunks) {
  final result = Uint8List(12 + chunks.length);
  result.setRange(0, 4, 'RIFF'.codeUnits);
  le32(result, 4, result.length - 8);
  result.setRange(8, 12, 'WEBP'.codeUnits);
  result.setRange(12, result.length, chunks);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = {'image/png': png, 'image/jpeg': jpeg, 'image/webp': webp};
  test('PNG JPEG and both WebP encodings expose bounded dimensions', () {
    for (final entry in fixtures.entries) {
      final size = articleImageDimensions(entry.value, entry.key);
      expect([size.width, size.height], [90, 90]);
    }
    final lossless = articleImageDimensions(webpLossless, 'image/webp');
    expect([lossless.width, lossless.height], [90, 90]);
  });
  test('truncated headers fail without range errors or pixel allocation', () {
    for (final entry in fixtures.entries) {
      for (var length = 0; length < 32; length++) {
        expect(
          () => articleImageDimensions(
            Uint8List.sublistView(entry.value, 0, length),
            entry.key,
          ),
          throwsFormatException,
        );
      }
    }
    for (final entry in {'image/png': png, 'image/webp': webp}.entries) {
      expect(
        () => articleImageDimensions(
          Uint8List.sublistView(entry.value, 0, entry.value.length - 1),
          entry.key,
        ),
        throwsFormatException,
      );
    }
  });
  test('declared pixel bombs are rejected before platform decoding', () {
    final giantPng = copy(png);
    be32(giantPng, 16, 0xffffffff);
    expect(
      () => articleImageDimensions(giantPng, 'image/png'),
      throwsFormatException,
    );
    final giantJpeg = copy(jpeg);
    final start = List.generate(
      jpeg.length - 1,
      (i) => i,
    ).firstWhere((i) => jpeg[i] == 255 && jpeg[i + 1] == 192);
    giantJpeg[start + 7] = 255;
    giantJpeg[start + 8] = 255;
    expect(
      () => articleImageDimensions(giantJpeg, 'image/jpeg'),
      throwsFormatException,
    );
    final giantWebp = riff([
      ...chunk('VP8X', [0, 0, 0, 0, 255, 255, 255, 255, 255, 255]),
      ...webpLossless.sublist(12),
    ]);
    expect(
      () => articleImageDimensions(giantWebp, 'image/webp'),
      throwsFormatException,
    );
  });
  test('oversized chunks and malformed marker lengths fail closed', () {
    final badPng = copy(png);
    be32(badPng, 33, 0xffffffff);
    final badWebp = copy(webp);
    le32(badWebp, 16, 0xffffffff);
    expect(
      () => articleImageDimensions(badPng, 'image/png'),
      throwsFormatException,
    );
    expect(
      () => articleImageDimensions(badWebp, 'image/webp'),
      throwsFormatException,
    );
    expect(
      () => articleImageDimensions(
        Uint8List.fromList([255, 216, 255, 224, 255, 255]),
        'image/jpeg',
      ),
      throwsFormatException,
    );
  });
  test('animation containers are not accepted as static images', () {
    final apng = Uint8List.fromList([
      ...png.sublist(0, 33),
      0,
      0,
      0,
      8,
      ...'acTL'.codeUnits,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...png.sublist(33),
    ]);
    final animated = riff([
      ...chunk('VP8X', [2, 0, 0, 0, 89, 0, 0, 89, 0, 0]),
      ...webpLossless.sublist(12),
    ]);
    expect(
      () => articleImageDimensions(apng, 'image/png'),
      throwsFormatException,
    );
    expect(
      () => articleImageDimensions(animated, 'image/webp'),
      throwsFormatException,
    );
  });
  test('mismatched MIME and unsupported data are rejected', () {
    expect(
      () => articleImageDimensions(png, 'image/jpeg'),
      throwsFormatException,
    );
    expect(
      () => articleImageDimensions(png, 'image/svg+xml'),
      throwsFormatException,
    );
    expect(
      () => articleImageDimensions(Uint8List(1024 * 1024 + 1), 'image/png'),
      throwsFormatException,
    );
  });
  test(
    'real platform decode succeeds without web descriptor dimension getters',
    () async {
      for (final entry in fixtures.entries) {
        await validateArticleImage(entry.value, image(), entry.key);
      }
      await validateArticleImage(webpLossless, image(), 'image/webp');
    },
  );
  test('declared rendition and policy dimensions remain enforced', () async {
    await expectLater(
      validateArticleImage(png, image(width: 89), 'image/png'),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      validateArticleImage(png, image(), 'image/png', maximumWidth: 89),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      validateArticleImage(png, image(width: 1, height: 1), 'image/png'),
      throwsA(isA<Exception>()),
    );
  });
}
