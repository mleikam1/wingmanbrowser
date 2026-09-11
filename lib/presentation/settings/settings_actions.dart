import 'package:flutter/foundation.dart';

/// The parent retains session and native-operation ownership across routes.
enum PrivacyDataCategory {
  reviewedBookmarks,
  readingList,
  launchpad,
  legacyHistory,
  websiteStorage,
  trustReceipt,
  session,
}

class DataClearOutcome {
  DataClearOutcome({
    Iterable<PrivacyDataCategory> completed = const [],
    Iterable<PrivacyDataCategory> failed = const [],
    this.pending = false,
  }) : completed = Set.unmodifiable(completed),
       failed = Set.unmodifiable(failed);
  final Set<PrivacyDataCategory> completed, failed;
  final bool pending;
}

class SettingsActions {
  const SettingsActions({
    required this.onHomeCustomization,
    required this.onSpaces,
    required this.onProtection,
    required this.onReceipt,
    required this.onCompatibility,
    required this.onClearData,
    required this.clearableCategories,
    this.onHelpNow,
    this.pendingDataClear,
    this.onClearDataScoped,
  });
  final VoidCallback onHomeCustomization,
      onSpaces,
      onProtection,
      onReceipt,
      onCompatibility;
  final VoidCallback? onHelpNow;
  final Future<DataClearOutcome>? Function()? pendingDataClear;
  final Future<DataClearOutcome> Function(
    Set<PrivacyDataCategory>,
    bool Function() canReconcile,
  )?
  onClearDataScoped;
  final Set<PrivacyDataCategory> clearableCategories;
  final Future<DataClearOutcome> Function(Set<PrivacyDataCategory>) onClearData;
}

extension PrivacyDataLabel on PrivacyDataCategory {
  String get label => switch (this) {
    PrivacyDataCategory.reviewedBookmarks => 'Reviewed bookmarks',
    PrivacyDataCategory.readingList => 'Reading list and read status',
    PrivacyDataCategory.launchpad => 'Your Launchpad and sources',
    PrivacyDataCategory.legacyHistory => 'Quarantined earlier history',
    PrivacyDataCategory.websiteStorage => 'Legacy website data',
    PrivacyDataCategory.trustReceipt => 'This Trust Receipt journal',
    PrivacyDataCategory.session => 'This discovery session',
  };
  String explanation({required bool isPrivate}) => switch (this) {
    PrivacyDataCategory.reviewedBookmarks =>
      'Removes saved reviewed-resource IDs. Other library items and notes stay.',
    PrivacyDataCategory.readingList =>
      'Removes reading-list IDs and their read marks. Article bundles stay installed.',
    PrivacyDataCategory.launchpad =>
      'Removes saved shortcuts, addresses, folder names, collection sources and Launchpad display choices. Keeps bookmarks, Spaces and protection. Earlier shortcuts will not return automatically.',
    PrivacyDataCategory.legacyHistory =>
      'Deletes earlier history records without displaying their titles or addresses. Other quarantined records stay.',
    PrivacyDataCategory.websiteStorage =>
      'Removes legacy site cookies, cache and storage together. Completed download files are not deleted.',
    PrivacyDataCategory.trustReceipt =>
      'Clears this journal only. Copies already exported to the clipboard or files remain outside Wingman.',
    PrivacyDataCategory.session =>
      isPrivate
          ? 'Closes private tabs and clears their transient tools. Normal saved items stay.'
          : 'Closes normal discovery tabs and clears their searches. Keeps Launchpad, bookmarks, reading saves, restrictions, Spaces, tasks, findings, receipt and quarantine.',
  };
}
