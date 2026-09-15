import 'models.dart';

class LiveContentPreferences {
  const LiveContentPreferences({
    this.enabled = true,
    this.selectedTopics = const {},
    this.selectedSourceIds = const {},
    this.hiddenSourceIds = const {},
    this.fewerTopics = const {},
    this.dismissedItemIds = const {},
    this.language = 'en',
    this.region,
  });
  factory LiveContentPreferences.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 || json['enabled'] is! bool) {
      throw const FormatException('Invalid feed preferences.');
    }
    return LiveContentPreferences(
      enabled: json['enabled'] as bool,
      selectedTopics: feedIds(json['selectedTopics'] ?? [], max: 30),
      selectedSourceIds: feedIds(json['selectedSourceIds'] ?? [], max: 256),
      hiddenSourceIds: feedIds(json['hiddenSourceIds'] ?? [], max: 256),
      fewerTopics: feedIds(json['fewerTopics'] ?? [], max: 30),
      dismissedItemIds: feedIds(json['dismissedItemIds'] ?? [], max: 2000),
      language: feedId(json['language'] ?? 'en'),
      region: json['region'] == null ? null : feedId(json['region']),
    );
  }
  final bool enabled;

  /// Empty selection means all approved, available topics/sources.
  final Set<String> selectedTopics,
      selectedSourceIds,
      hiddenSourceIds,
      fewerTopics,
      dismissedItemIds;
  Set<String> get selectedSources => selectedSourceIds;
  final String language;
  final String? region;
  bool follows(String id) =>
      !hiddenSourceIds.contains(id) &&
      (selectedSourceIds.isEmpty || selectedSourceIds.contains(id));
  LiveContentPreferences copyWith({
    bool? enabled,
    Set<String>? selectedTopics,
    Set<String>? selectedSourceIds,
    Set<String>? hiddenSourceIds,
    Set<String>? fewerTopics,
    Set<String>? dismissedItemIds,
    String? language,
    String? region,
    bool clearRegion = false,
  }) => LiveContentPreferences(
    enabled: enabled ?? this.enabled,
    selectedTopics: selectedTopics ?? this.selectedTopics,
    selectedSourceIds: selectedSourceIds ?? this.selectedSourceIds,
    hiddenSourceIds: hiddenSourceIds ?? this.hiddenSourceIds,
    fewerTopics: fewerTopics ?? this.fewerTopics,
    dismissedItemIds: dismissedItemIds ?? this.dismissedItemIds,
    language: language ?? this.language,
    region: clearRegion ? null : region ?? this.region,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'enabled': enabled,
    'selectedTopics': selectedTopics.toList(),
    'selectedSourceIds': selectedSourceIds.toList(),
    'hiddenSourceIds': hiddenSourceIds.toList(),
    'fewerTopics': fewerTopics.toList(),
    'dismissedItemIds': dismissedItemIds.toList(),
    'language': language,
    'region': region,
  };
}

class LiveSavedItem {
  const LiveSavedItem({
    required this.id,
    required this.sourceId,
    required this.savedAt,
    required this.item,
    this.unavailableReason,
  });
  factory LiveSavedItem.fromJson(Map<String, dynamic> json) => LiveSavedItem(
    id: feedId(json['id']),
    sourceId: feedId(json['sourceId']),
    savedAt: feedDate(json['savedAt']),
    item: json['item'] == null
        ? null
        : LiveContentItem.fromJson(feedMap(json['item'])),
    unavailableReason: json['unavailableReason'] == null
        ? null
        : feedText(json['unavailableReason'], max: 160),
  );
  final String id, sourceId;
  final DateTime savedAt;
  final LiveContentItem? item;
  final String? unavailableReason;
  bool get available => item != null;
  LiveSavedItem unavailable(String reason) => LiveSavedItem(
    id: id,
    sourceId: sourceId,
    savedAt: savedAt,
    item: null,
    unavailableReason: reason,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'savedAt': savedAt.toIso8601String(),
    'item': item?.toJson(),
    'unavailableReason': unavailableReason,
  };
}
