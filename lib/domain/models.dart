import 'package:flutter/material.dart' show ThemeMode;

/// Metadata only. Live web engines belong to the platform/presentation layer.
/// Stable IDs leave room for tab groups, pinned tabs and optional future sync.
class BrowserTab {
  const BrowserTab({
    required this.id,
    this.url = '',
    this.title = 'New tab',
    this.isPrivate = false,
    this.desktopMode = false,
  });

  final String id;
  final String url;
  final String title;
  final bool isPrivate;
  final bool desktopMode;

  bool get isHome => url.isEmpty;
  bool get isSecure => Uri.tryParse(url)?.scheme == 'https';

  BrowserTab copyWith({String? url, String? title, bool? desktopMode}) =>
      BrowserTab(
        id: id,
        url: url ?? this.url,
        title: title ?? this.title,
        isPrivate: isPrivate,
        desktopMode: desktopMode ?? this.desktopMode,
      );
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
  });
  final String id;
  final String url;
  final String title;
  final DateTime visitedAt;
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.url,
    required this.title,
    required this.createdAt,
  });
  final String id;
  final String url;
  final String title;
  final DateTime createdAt;
}

class BrowserSettings {
  const BrowserSettings({
    this.themeMode = ThemeMode.system,
    this.searchProviderId = 'duckduckgo',
    this.onboardingComplete = false,
  });

  final ThemeMode themeMode;
  final String searchProviderId;
  final bool onboardingComplete;

  BrowserSettings copyWith({
    ThemeMode? themeMode,
    String? searchProviderId,
    bool? onboardingComplete,
  }) => BrowserSettings(
    themeMode: themeMode ?? this.themeMode,
    searchProviderId: searchProviderId ?? this.searchProviderId,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
  );
}
