import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../domain/bookmark_transfer.dart';

typedef BookmarkImportDecoder =
    Future<BookmarkImportPreview> Function(
      Uint8List bytes,
      Iterable<String> existingUrls,
    );

Future<BookmarkImportPreview> decodeBookmarkFile(
  Uint8List bytes,
  Iterable<String> existingUrls,
) => compute(_decode, (bytes: bytes, urls: existingUrls.toList()));

BookmarkImportPreview _decode(({Uint8List bytes, List<String> urls}) input) =>
    BookmarkTransferCodec.parse(input.bytes, existingUrls: input.urls);

/// Bound the actual read even if a provider's file grows after its size check.
Future<Uint8List> readBookmarkSelection(XFile file) async {
  if (await file.length() > BookmarkTransferCodec.maximumFileBytes) {
    throw const FormatException('Choose a bookmark file smaller than 2 MiB.');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(
    0,
    BookmarkTransferCodec.maximumFileBytes + 1,
  )) {
    if (bytes.length + chunk.length > BookmarkTransferCodec.maximumFileBytes) {
      throw const FormatException('Choose a bookmark file smaller than 2 MiB.');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

/// Reads only an explicit OS picker selection, never other browser profiles.
abstract interface class BookmarkFiles {
  Future<Uint8List?> selectImport();
  Future<void> export(Uint8List bytes, Rect? origin);
}

class DeviceBookmarkFiles implements BookmarkFiles {
  const DeviceBookmarkFiles();
  @override
  Future<Uint8List?> selectImport() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Bookmark exports',
          extensions: ['html', 'htm'],
          mimeTypes: ['text/html'],
          uniformTypeIdentifiers: ['public.html'],
        ),
      ],
    );
    if (file == null) return null;
    return readBookmarkSelection(file);
  }

  @override
  Future<void> export(Uint8List bytes, Rect? origin) async {
    final file = XFile.fromData(
      bytes,
      mimeType: 'text/html',
      name: 'wingman-bookmarks.html',
    );
    if (kIsWeb) {
      await file.saveTo('wingman-bookmarks.html');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: ['wingman-bookmarks.html'],
        title: 'Wingman bookmarks',
        sharePositionOrigin: origin,
        downloadFallbackEnabled: true,
        mailToFallbackEnabled: false,
      ),
    );
  }
}
