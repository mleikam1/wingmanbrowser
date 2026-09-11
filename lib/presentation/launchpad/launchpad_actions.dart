import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';

/// The shell supplies captured session ownership and all navigation. Widgets
/// never load websites or infer approval from shortcut metadata.
class LaunchpadActions {
  const LaunchpadActions({
    required this.canContinue,
    required this.push,
    required this.onOpen,
    required this.bookmarks,
    this.changes,
    this.catalog,
    this.onAddToSpace,
    this.onManageSpaces,
    this.onHomeSections,
  });
  final bool Function() canContinue;
  final Future<void> Function(Widget page) push;
  final Future<void> Function(LaunchpadTarget target, {bool newTab}) onOpen;
  final List<LaunchpadPinDraft> Function() bookmarks;
  final Listenable? changes;
  final LaunchpadCatalog? catalog;
  final Future<void> Function(LaunchpadTarget target)? onAddToSpace;
  final VoidCallback? onManageSpaces, onHomeSections;
}

/// An explicit page/bookmark pin preview, never a persisted permission.
class LaunchpadPinDraft {
  const LaunchpadPinDraft({
    required this.title,
    required this.target,
    this.localIconKey = 'link',
    this.fromBookmark = false,
    this.fromCurrentPage = false,
  });
  final String title, localIconKey;
  final LaunchpadTarget target;
  final bool fromBookmark, fromCurrentPage;
}
