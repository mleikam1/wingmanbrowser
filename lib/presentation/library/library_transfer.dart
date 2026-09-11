import 'dart:convert';
import '../../policy/policy_runtime.dart';

class ReviewedTransferPreview {
  ReviewedTransferPreview({
    required Iterable<String> acceptedIds,
    required this.duplicates,
    required this.rejected,
  }) : acceptedIds = List.unmodifiable(acceptedIds);
  final List<String> acceptedIds;
  final int duplicates, rejected;
}

abstract final class ReviewedLibraryTransfer {
  static const maximumBytes = 512 * 1024;
  static const maximumItems = 5000;
  static const kind = 'wingman-reviewed-bookmarks';

  static ReviewedTransferPreview preview(
    String text, {
    required bool Function(String) eligible,
    required Set<String> existing,
  }) {
    try {
      if (utf8.encode(text).length > maximumBytes) {
        throw const FormatException();
      }
      final document = jsonDecode(text);
      if (document is! Map ||
          document.length != 3 ||
          document['schema'] != 1 ||
          document['kind'] != kind ||
          document['resourceIds'] is! List) {
        throw const FormatException();
      }
      final rows = document['resourceIds'] as List;
      if (rows.length > maximumItems) throw const FormatException();
      final accepted = <String>[], seen = <String>{};
      var duplicates = 0, rejected = 0;
      for (final row in rows) {
        if (row is! String || !validResourceId(row) || !eligible(row)) {
          rejected++;
          continue;
        }
        if (!seen.add(row) || existing.contains(row)) {
          duplicates++;
          continue;
        }
        accepted.add(row);
      }
      if (existing.length + accepted.length > maximumItems) {
        throw const FormatException('The bookmark limit would be exceeded.');
      }
      return ReviewedTransferPreview(
        acceptedIds: accepted,
        duplicates: duplicates,
        rejected: rejected,
      );
    } catch (_) {
      throw const FormatException(
        'Use a Wingman reviewed-bookmark document within the 512 KiB and 5,000-item limits. No data was imported.',
      );
    }
  }

  static String export(
    Iterable<String> ids, {
    required bool Function(String) eligible,
  }) {
    final approved =
        ids.where((id) => validResourceId(id) && eligible(id)).toSet().toList()
          ..sort();
    if (approved.length > maximumItems) {
      throw const FormatException('The export limit was exceeded.');
    }
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert({'schema': 1, 'kind': kind, 'resourceIds': approved});
    if (utf8.encode(text).length > maximumBytes) {
      throw const FormatException('The export limit was exceeded.');
    }
    return text;
  }
}
