import 'package:flutter/material.dart';

/// Stateless browser controls. Navigation and platform actions stay in the shell.
class BrowserToolbar extends StatelessWidget {
  const BrowserToolbar({
    super.key,
    required this.isHome,
    required this.isPrivate,
    required this.isLoading,
    required this.isBookmarked,
    required this.desktopMode,
    required this.tabCount,
    required this.onBack,
    required this.onForward,
    required this.onPrimaryAction,
    required this.onHome,
    required this.onTabs,
    required this.onMenuSelected,
  });

  final bool isHome, isPrivate, isLoading, isBookmarked, desktopMode;
  final int tabCount;
  final VoidCallback? onBack, onForward;
  final VoidCallback onPrimaryAction, onHome, onTabs;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isPrivate ? scheme.tertiaryContainer : scheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                tooltip: 'Forward',
                onPressed: onForward,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              IconButton(
                tooltip: isHome
                    ? 'New tab'
                    : isLoading
                    ? 'Stop loading'
                    : 'Reload',
                onPressed: onPrimaryAction,
                icon: Icon(
                  isHome
                      ? Icons.add_rounded
                      : isLoading
                      ? Icons.close
                      : Icons.refresh_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Home',
                onPressed: onHome,
                icon: const Icon(Icons.home_outlined),
              ),
              IconButton(
                tooltip: 'Tabs ($tabCount)',
                onPressed: onTabs,
                icon: Container(
                  width: 23,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.onSurface, width: 1.7),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$tabCount',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Browser menu',
                onSelected: onMenuSelected,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'new', child: Text('New tab')),
                  const PopupMenuItem(
                    value: 'private',
                    child: Text('New private tab'),
                  ),
                  if (!isHome && !isPrivate)
                    PopupMenuItem(
                      value: 'bookmark',
                      child: Text(
                        isBookmarked ? 'Remove bookmark' : 'Bookmark page',
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'bookmarks',
                    child: Text('Bookmarks'),
                  ),
                  const PopupMenuItem(value: 'history', child: Text('History')),
                  if (!isHome) ...[
                    const PopupMenuItem(value: 'copy', child: Text('Copy URL')),
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('Share page'),
                    ),
                    const PopupMenuItem(
                      value: 'find',
                      child: Text('Find in page'),
                    ),
                    PopupMenuItem(
                      value: 'desktop',
                      child: Text(
                        desktopMode ? 'Use mobile site' : 'Use desktop site',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'external',
                      child: Text('Open externally'),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings & privacy'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
