import 'dart:typed_data';

/// Bounded metadata inspection before allocating pixels. This is not a decoder;
/// the platform decoder must still validate the image and its final dimensions.
class ArticleImageDimensions {
  const ArticleImageDimensions(this.width, this.height);
  final int width, height;
}

ArticleImageDimensions articleImageDimensions(Uint8List bytes, String mime) {
  if (bytes.isEmpty || bytes.length > 1024 * 1024) {
    throw const FormatException('Image byte limit.');
  }
  final reader = _ImageHeader(bytes);
  final size = switch (mime) {
    'image/png' => reader.png(),
    'image/jpeg' => reader.jpeg(),
    'image/webp' => reader.webp(),
    _ => throw const FormatException('Unsupported image type.'),
  };
  if (size.width < 16 ||
      size.height < 16 ||
      size.width > 2048 ||
      size.height > 2048 ||
      size.width * size.height > 4 * 1024 * 1024) {
    throw const FormatException('Image pixel limit.');
  }
  return size;
}

class _ImageHeader {
  _ImageHeader(this.bytes);
  final Uint8List bytes;
  Never invalid() => throw const FormatException('Invalid image header.');
  void need(int offset, int length) {
    if (offset < 0 || length < 0 || offset > bytes.length - length) invalid();
  }

  int byte(int p) {
    need(p, 1);
    return bytes[p];
  }

  int be16(int p) => byte(p) * 256 + byte(p + 1);
  int le16(int p) => byte(p) + byte(p + 1) * 256;
  int be32(int p) => be16(p) * 65536 + be16(p + 2);
  int le24(int p) => le16(p) + byte(p + 2) * 65536;
  int le32(int p) => le16(p) + le16(p + 2) * 65536;
  bool text(int p, String value) {
    need(p, value.length);
    for (var i = 0; i < value.length; i++) {
      if (bytes[p + i] != value.codeUnitAt(i)) return false;
    }
    return true;
  }

  ArticleImageDimensions png() {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    need(0, 33);
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) invalid();
    }
    if (be32(8) != 13 || !text(12, 'IHDR')) invalid();
    final size = ArticleImageDimensions(be32(16), be32(20));
    var p = 8, chunks = 0;
    var imageData = false;
    while (p < bytes.length) {
      if (++chunks > 20000) invalid();
      need(p, 12);
      final length = be32(p);
      need(p + 8, length + 4);
      if (p != 8 && text(p + 4, 'IHDR')) invalid();
      if (text(p + 4, 'acTL') || text(p + 4, 'fcTL') || text(p + 4, 'fdAT')) {
        invalid(); // APNG cannot be disguised as a single-frame PNG.
      }
      if (text(p + 4, 'IDAT')) imageData = true;
      if (text(p + 4, 'IEND')) {
        if (length != 0 || !imageData || p + 12 != bytes.length) invalid();
        return size;
      }
      p += length + 12;
    }
    return invalid();
  }

  ArticleImageDimensions jpeg() {
    if (be16(0) != 0xffd8) invalid();
    var p = 2, segments = 0;
    ArticleImageDimensions? size;
    const starts = {
      0xc0,
      0xc1,
      0xc2,
      0xc3,
      0xc5,
      0xc6,
      0xc7,
      0xc9,
      0xca,
      0xcb,
      0xcd,
      0xce,
      0xcf,
    };
    while (p < bytes.length) {
      if (++segments > 20000 || byte(p++) != 0xff) invalid();
      while (byte(p) == 0xff) {
        p++;
      }
      final marker = byte(p++);
      if (marker == 0 ||
          marker == 0xd8 ||
          marker == 0xd9 ||
          marker == 1 ||
          (marker >= 0xd0 && marker <= 0xd7)) {
        invalid();
      }
      final length = be16(p);
      if (length < 2) invalid();
      need(p, length);
      if (starts.contains(marker)) {
        if (size != null || length < 8) invalid();
        final components = byte(p + 7);
        if (components < 1 || components > 4 || length != 8 + 3 * components) {
          invalid();
        }
        size = ArticleImageDimensions(be16(p + 5), be16(p + 3));
      }
      if (marker == 0xda) {
        if (size == null || length < 6 || p + length >= bytes.length) invalid();
        return size;
      }
      p += length;
    }
    return invalid();
  }

  ArticleImageDimensions webp() {
    need(0, 20);
    if (!text(0, 'RIFF') || !text(8, 'WEBP') || le32(4) != bytes.length - 8) {
      invalid();
    }
    var p = 12, chunks = 0;
    ArticleImageDimensions? canvas, size;
    while (p < bytes.length) {
      if (++chunks > 20000) invalid();
      need(p, 8);
      final length = le32(p + 4), data = p + 8;
      need(data, length + (length & 1));
      if (text(p, 'ANIM') || text(p, 'ANMF')) invalid();
      if (text(p, 'VP8X')) {
        if (p != 12 ||
            length != 10 ||
            canvas != null ||
            (byte(data) & 0xc3) != 0 ||
            le24(data + 1) != 0) {
          invalid();
        }
        canvas = ArticleImageDimensions(le24(data + 4) + 1, le24(data + 7) + 1);
      } else if (text(p, 'VP8 ')) {
        if (size != null ||
            length < 10 ||
            (byte(data) & 1) != 0 ||
            byte(data + 3) != 0x9d ||
            byte(data + 4) != 1 ||
            byte(data + 5) != 0x2a) {
          invalid();
        }
        size = ArticleImageDimensions(
          le16(data + 6) & 0x3fff,
          le16(data + 8) & 0x3fff,
        );
      } else if (text(p, 'VP8L')) {
        if (size != null ||
            length < 5 ||
            byte(data) != 0x2f ||
            (byte(data + 4) & 0xe0) != 0) {
          invalid();
        }
        final bits = le32(data + 1);
        size = ArticleImageDimensions(
          (bits & 0x3fff) + 1,
          ((bits >> 14) & 0x3fff) + 1,
        );
      }
      p = data + length + (length & 1);
    }
    if (size == null ||
        p != bytes.length ||
        (canvas != null &&
            (canvas.width != size.width || canvas.height != size.height))) {
      invalid();
    }
    return size;
  }
}
