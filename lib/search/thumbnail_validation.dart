import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../live_content/image_headers.dart';

const maximumThumbnailBytes = 128 * 1024;

/// Gateway thumbnails are re-encoded PNGs. Check allocation bounds before
/// decoding, then verify a single actual frame before retaining any pixels.
Future<void> validateSearchThumbnail(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > maximumThumbnailBytes) {
    throw const FormatException('Invalid thumbnail.');
  }
  final size = articleImageDimensions(bytes, 'image/png');
  bool matches(int width, int height) =>
      width == size.width &&
      height == size.height &&
      width >= 16 &&
      height >= 16 &&
      width <= 384 &&
      height <= 216;
  if (!matches(size.width, size.height)) {
    throw const FormatException('Invalid thumbnail.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (!kIsWeb && !matches(descriptor.width, descriptor.height)) {
      throw const FormatException('Invalid thumbnail.');
    }
    codec = await descriptor.instantiateCodec();
    if (codec.frameCount != 1) {
      throw const FormatException('Invalid thumbnail.');
    }
    final frame = await codec.getNextFrame();
    try {
      if (!matches(frame.image.width, frame.image.height)) {
        throw const FormatException('Invalid thumbnail.');
      }
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
