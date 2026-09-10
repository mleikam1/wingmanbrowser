import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/domain/bookmark_transfer.dart';
import 'package:wingman_browser/presentation/bookmark_files.dart';

class _GrowingSelection extends XFile {
  _GrowingSelection(this.bytes, {this.reportedLength = 1})
    : super('synthetic-only');
  final Uint8List bytes;
  final int reportedLength;
  int? requestedEnd;
  @override
  Future<int> length() async => reportedLength;
  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('Unbounded read forbidden');
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    requestedEnd = end;
    return Stream.value(bytes);
  }
}

void main() {
  test(
    'oversized actual selection is rejected even with stale small metadata',
    () async {
      final file = _GrowingSelection(
        Uint8List(BookmarkTransferCodec.maximumFileBytes + 1),
      );
      await expectLater(readBookmarkSelection(file), throwsFormatException);
      expect(file.requestedEnd, BookmarkTransferCodec.maximumFileBytes + 1);
    },
  );
  test('oversized metadata is rejected before opening a stream', () async {
    final file = _GrowingSelection(
      Uint8List(0),
      reportedLength: BookmarkTransferCodec.maximumFileBytes + 1,
    );
    await expectLater(readBookmarkSelection(file), throwsFormatException);
    expect(file.requestedEnd, isNull);
  });
  test('small selection is returned through the bounded stream', () async {
    final file = _GrowingSelection(Uint8List.fromList([1, 2, 3]));
    expect(await readBookmarkSelection(file), [1, 2, 3]);
  });
}
