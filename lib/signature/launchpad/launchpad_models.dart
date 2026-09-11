import 'dart:convert';
import '../../domain/search.dart';
import '../../policy/policy_models.dart';

enum LaunchpadKind { resource, tool, website }

enum LaunchpadSource { user, catalog, bookmark, currentPage, legacy }

enum LaunchpadDensity { compact, comfortable }

enum LaunchpadSetup { notStarted, completed, dismissed }

enum LaunchpadTool {
  explore('Learn'),
  officialRoutes('Official Routes'),
  library('Library'),
  spaces('Your Spaces'),
  finishMode('Finish Mode'),
  beforeYouCommit('Before You Commit'),
  trustReceipt('Trust Receipt'),
  compatibility('Something isn’t working'),
  helpNow('Help Now');

  const LaunchpadTool(this.label);
  final String label;
}

const launchpadIconKeys = {
  'link',
  'book',
  'science',
  'sports',
  'shopping',
  'tools',
  'home',
  'star',
  'folder',
  'globe',
  'school',
  'receipt',
  'checklist',
};
bool validLaunchpadIcon(String value) =>
    launchpadIconKeys.contains(value) ||
    RegExp(r'^initials:[A-Z0-9]{1,2}$').hasMatch(value);

/// No fetch, DNS, icon or title request. URI paths/query/fragment stay meaningful.
String normalizeLaunchpadWebsite(String input) {
  final parsed = const OmniboxParser().parse(
    input,
    provider: SearchProvider.available.first,
  );
  if (parsed.isSearch) {
    throw const FormatException('Enter a website address, not a search.');
  }
  final uri = requireWebUri(parsed.url);
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  // This local review record accepts explicit public ASCII/A-label identities.
  // IDNs require their visible ASCII form; ambiguous host transformations fail.
  if (host.length > 253 ||
      host.contains('%') ||
      !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) ||
      !host.contains('.') ||
      RegExp(r'^[0-9.]+$').hasMatch(host) ||
      RegExp(r'^[0-9]+$').hasMatch(host.split('.').last) ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.split('.').any((p) => p.length > 63)) {
    throw const FormatException(
      'Use a public website hostname in its ASCII form.',
    );
  }
  return uri
      .replace(host: host, path: uri.path.isEmpty ? '/' : uri.path)
      .toString();
}

Never invalidLaunchpad() => throw const FormatException(
  'Saved Launchpad data is invalid or exceeds its limits.',
);
void _keys(Map<String, Object?> row, Set<String> keys) {
  if (row.length != keys.length || !row.keys.every(keys.contains)) {
    invalidLaunchpad();
  }
}

String _text(Object? value, int maximum, {bool empty = false}) {
  if (value is! String ||
      value.length > maximum ||
      (!empty && value.trim().isEmpty) ||
      RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(value)) {
    invalidLaunchpad();
  }
  return value;
}

String _id(Object? value) {
  if (value is! String || !validResourceId(value)) invalidLaunchpad();
  return value;
}

String _catalogId(Object? value) {
  if (value is! String ||
      !RegExp(r'^[a-z0-9][a-z0-9-]{0,127}$').hasMatch(value)) {
    invalidLaunchpad();
  }
  return value;
}

int _order(Object? value) {
  if (value is! int ||
      value < 0 ||
      value >
          LaunchpadSnapshot.maximumShortcuts +
              LaunchpadSnapshot.maximumFolders) {
    invalidLaunchpad();
  }
  return value;
}

String _icon(Object? value) {
  if (value is! String || !validLaunchpadIcon(value)) invalidLaunchpad();
  return value;
}

T _enum<T extends Enum>(Iterable<T> choices, Object? value) =>
    choices.where((e) => e.name == value).firstOrNull ?? invalidLaunchpad();
Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((k) => k is! String)) invalidLaunchpad();
  return Map<String, Object?>.from(value);
}

List<T> _rows<T>(
  Object? value,
  int maximum,
  T Function(Map<String, Object?>) parse,
) {
  if (value is! List || value.length > maximum) invalidLaunchpad();
  return value.map((e) => parse(_map(e))).toList();
}

DateTime _date(Object? value) {
  if (value is! int || value < 0 || value > 4102444800000) invalidLaunchpad();
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

class LaunchpadTarget {
  const LaunchpadTarget.resource(String id)
    : kind = LaunchpadKind.resource,
      value = id;
  LaunchpadTarget.tool(LaunchpadTool tool)
    : kind = LaunchpadKind.tool,
      value = tool.name;
  const LaunchpadTarget.website(String url)
    : kind = LaunchpadKind.website,
      value = url;
  const LaunchpadTarget._(this.kind, this.value);
  final LaunchpadKind kind;
  final String value;
  LaunchpadTool? get tool =>
      LaunchpadTool.values.where((t) => t.name == value).firstOrNull;
  String get identity => '${kind.name}:$value';
  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};
  factory LaunchpadTarget.fromJson(Map<String, Object?> row) {
    _keys(row, {'kind', 'value'});
    final kind = _enum(LaunchpadKind.values, row['kind']);
    final value = _text(row['value'], 8192);
    switch (kind) {
      case LaunchpadKind.resource:
        _id(value);
      case LaunchpadKind.tool:
        _enum(LaunchpadTool.values, value);
      case LaunchpadKind.website:
        if (normalizeLaunchpadWebsite(value) != value) invalidLaunchpad();
    }
    return LaunchpadTarget._(kind, value);
  }
  @override
  bool operator ==(Object other) =>
      other is LaunchpadTarget && kind == other.kind && value == other.value;
  @override
  int get hashCode => Object.hash(kind, value);
}

class LaunchpadDraft {
  const LaunchpadDraft({
    required this.title,
    required this.target,
    this.localIconKey = 'link',
    this.folderId,
    this.source = LaunchpadSource.user,
    this.catalogEntryId,
  });
  final String title, localIconKey;
  final LaunchpadTarget target;
  final String? folderId, catalogEntryId;
  final LaunchpadSource source;
}

sealed class LaunchpadItem {
  String get id;
  String get title;
  String get localIconKey;
  int get order;
}

class LaunchpadShortcut implements LaunchpadItem {
  const LaunchpadShortcut({
    required this.id,
    required this.title,
    required this.target,
    required this.localIconKey,
    required this.order,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.catalogEntryId,
  });
  @override
  final String id, title, localIconKey;
  @override
  final int order;
  final LaunchpadTarget target;
  final String? folderId, catalogEntryId;
  final LaunchpadSource source;
  final DateTime createdAt, updatedAt;
  LaunchpadShortcut placed(String? folder, int position) => LaunchpadShortcut(
    id: id,
    title: title,
    target: target,
    localIconKey: localIconKey,
    order: position,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt,
    folderId: folder,
    catalogEntryId: catalogEntryId,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'target': target.toJson(),
    'localIconKey': localIconKey,
    'order': order,
    'folderId': folderId,
    'source': source.name,
    'catalogEntryId': catalogEntryId,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
  factory LaunchpadShortcut.fromJson(Map<String, Object?> row) {
    _keys(row, {
      'id',
      'title',
      'target',
      'localIconKey',
      'order',
      'folderId',
      'source',
      'catalogEntryId',
      'createdAt',
      'updatedAt',
    });
    final created = _date(row['createdAt']), updated = _date(row['updatedAt']);
    if (updated.isBefore(created)) invalidLaunchpad();
    return LaunchpadShortcut(
      id: _id(row['id']),
      title: _text(row['title'], 80),
      target: LaunchpadTarget.fromJson(_map(row['target'])),
      localIconKey: _icon(row['localIconKey']),
      order: _order(row['order']),
      folderId: row['folderId'] == null ? null : _id(row['folderId']),
      source: _enum(LaunchpadSource.values, row['source']),
      catalogEntryId: row['catalogEntryId'] == null
          ? null
          : _catalogId(row['catalogEntryId']),
      createdAt: created,
      updatedAt: updated,
    );
  }
}

class LaunchpadFolder implements LaunchpadItem {
  const LaunchpadFolder({
    required this.id,
    required this.title,
    this.localIconKey = 'folder',
    required this.order,
  });
  @override
  final String id, title, localIconKey;
  @override
  final int order;
  LaunchpadFolder placed(int position) => LaunchpadFolder(
    id: id,
    title: title,
    localIconKey: localIconKey,
    order: position,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'localIconKey': localIconKey,
    'order': order,
  };
  factory LaunchpadFolder.fromJson(Map<String, Object?> row) {
    _keys(row, {'id', 'title', 'localIconKey', 'order'});
    return LaunchpadFolder(
      id: _id(row['id']),
      title: _text(row['title'], 80),
      localIconKey: _icon(row['localIconKey']),
      order: _order(row['order']),
    );
  }
}

enum LaunchpadCollection {
  sports('Sports'),
  shopping('Shopping'),
  learning('Learning');

  const LaunchpadCollection(this.label);
  final String label;
}

/// Sources own typed targets, not shortcut IDs. Removing a tile leaves these intact.
class LaunchpadCollectionSource {
  const LaunchpadCollectionSource({
    required this.title,
    required this.target,
    this.localIconKey = 'link',
  });
  final String title, localIconKey;
  final LaunchpadTarget target;
  Map<String, Object?> toJson() => {
    'title': title,
    'target': target.toJson(),
    'localIconKey': localIconKey,
  };
  factory LaunchpadCollectionSource.fromJson(Map<String, Object?> row) {
    _keys(row, {'title', 'target', 'localIconKey'});
    return LaunchpadCollectionSource(
      title: _text(row['title'], 80),
      target: LaunchpadTarget.fromJson(_map(row['target'])),
      localIconKey: _icon(row['localIconKey']),
    );
  }
}

class HomeCollectionPreference {
  HomeCollectionPreference({
    required this.kind,
    this.visible = true,
    required this.order,
    Iterable<LaunchpadCollectionSource> sources = const [],
  }) : sources = List.unmodifiable(sources);
  final LaunchpadCollection kind;
  final bool visible;
  final int order;
  final List<LaunchpadCollectionSource> sources;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'visible': visible,
    'order': order,
    'sources': sources.map((s) => s.toJson()).toList(),
  };
  factory HomeCollectionPreference.fromJson(Map<String, Object?> row) {
    _keys(row, {'kind', 'visible', 'order', 'sources'});
    if (row['visible'] is! bool) invalidLaunchpad();
    final sources = _rows(
      row['sources'],
      24,
      LaunchpadCollectionSource.fromJson,
    );
    if (sources.map((e) => e.target.identity).toSet().length !=
        sources.length) {
      invalidLaunchpad();
    }
    return HomeCollectionPreference(
      kind: _enum(LaunchpadCollection.values, row['kind']),
      visible: row['visible'] as bool,
      order: _order(row['order']),
      sources: sources,
    );
  }
}

class LaunchpadSnapshot {
  LaunchpadSnapshot({
    Iterable<LaunchpadShortcut> shortcuts = const [],
    Iterable<LaunchpadFolder> folders = const [],
    Iterable<HomeCollectionPreference> collections = const [],
    this.showShortcuts = true,
    this.showCollections = true,
    this.density = LaunchpadDensity.compact,
    this.setup = LaunchpadSetup.notStarted,
    this.legacyMigrated = true,
  }) : shortcuts = List.unmodifiable(shortcuts),
       folders = List.unmodifiable(folders),
       collections = List.unmodifiable(collections);
  static const maximumShortcuts = 64, maximumFolders = 12;
  final List<LaunchpadShortcut> shortcuts;
  final List<LaunchpadFolder> folders;
  final List<HomeCollectionPreference> collections;
  final bool showShortcuts, showCollections, legacyMigrated;
  final LaunchpadDensity density;
  final LaunchpadSetup setup;
  List<LaunchpadItem> get rootItems =>
      [...shortcuts.where((s) => s.folderId == null), ...folders]
        ..sort((a, b) => a.order.compareTo(b.order));
  List<LaunchpadShortcut> folderItems(String id) =>
      shortcuts.where((s) => s.folderId == id).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  LaunchpadSnapshot copyWith({
    Iterable<LaunchpadShortcut>? shortcuts,
    Iterable<LaunchpadFolder>? folders,
    Iterable<HomeCollectionPreference>? collections,
    bool? showShortcuts,
    bool? showCollections,
    LaunchpadDensity? density,
    LaunchpadSetup? setup,
  }) => LaunchpadSnapshot(
    shortcuts: shortcuts ?? this.shortcuts,
    folders: folders ?? this.folders,
    collections: collections ?? this.collections,
    showShortcuts: showShortcuts ?? this.showShortcuts,
    showCollections: showCollections ?? this.showCollections,
    density: density ?? this.density,
    setup: setup ?? this.setup,
    legacyMigrated: legacyMigrated,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'legacyMigrated': legacyMigrated,
    'setup': setup.name,
    'showShortcuts': showShortcuts,
    'showCollections': showCollections,
    'density': density.name,
    'shortcuts': shortcuts.map((s) => s.toJson()).toList(),
    'folders': folders.map((f) => f.toJson()).toList(),
    'collections': collections.map((c) => c.toJson()).toList(),
  };
  factory LaunchpadSnapshot.fromJson(Map<String, Object?> row) {
    _keys(row, {
      'version',
      'legacyMigrated',
      'setup',
      'showShortcuts',
      'showCollections',
      'density',
      'shortcuts',
      'folders',
      'collections',
    });
    if (row['version'] != 1 ||
        row['legacyMigrated'] != true ||
        row['showShortcuts'] is! bool ||
        row['showCollections'] is! bool ||
        utf8.encode(jsonEncode(row)).length > 512 * 1024) {
      invalidLaunchpad();
    }
    final shortcuts = _rows(
      row['shortcuts'],
      maximumShortcuts,
      LaunchpadShortcut.fromJson,
    );
    final folders = _rows(
      row['folders'],
      maximumFolders,
      LaunchpadFolder.fromJson,
    );
    final collections = _rows(
      row['collections'],
      3,
      HomeCollectionPreference.fromJson,
    );
    final ids = [...shortcuts.map((s) => s.id), ...folders.map((f) => f.id)];
    if (ids.toSet().length != ids.length ||
        shortcuts.map((s) => s.target.identity).toSet().length !=
            shortcuts.length ||
        collections.map((c) => c.kind).toSet().length != collections.length ||
        shortcuts.any(
          (s) => s.folderId != null && !folders.any((f) => f.id == s.folderId),
        )) {
      invalidLaunchpad();
    }
    void positions(Iterable<int> values) {
      final sorted = values.toList()..sort();
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i] != i) invalidLaunchpad();
      }
    }

    positions([
      ...shortcuts.where((s) => s.folderId == null).map((s) => s.order),
      ...folders.map((f) => f.order),
    ]);
    for (final folder in folders) {
      positions(
        shortcuts.where((s) => s.folderId == folder.id).map((s) => s.order),
      );
    }
    positions(collections.map((c) => c.order));
    return LaunchpadSnapshot(
      shortcuts: shortcuts,
      folders: folders,
      collections: collections,
      showShortcuts: row['showShortcuts'] as bool,
      showCollections: row['showCollections'] as bool,
      density: _enum(LaunchpadDensity.values, row['density']),
      setup: _enum(LaunchpadSetup.values, row['setup']),
    );
  }
}
