import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'wingman_components.dart';

/// Native navigation owns Wingman's reviewed-page trail. Web companion controls
/// navigate this app only and never impersonate the host browser's toolbar.
class BrowserDock extends StatelessWidget {
  const BrowserDock({
    super.key,
    required this.onHome,
    required this.onTabs,
    required this.onMenu,
    required this.onLibrary,
    required this.onSpaces,
    this.onBack,
    this.onForward,
    this.tabCount = 1,
    this.resourceTitle,
    this.onAddress,
    this.onPageInfo,
    this.isPrivate = false,
  });
  final VoidCallback onHome, onTabs, onMenu, onLibrary, onSpaces;
  final VoidCallback? onBack, onForward, onAddress, onPageInfo;
  final int tabCount;
  final String? resourceTitle;
  final bool isPrivate;
  @override
  Widget build(BuildContext context) => Material(
    color: WingmanTokens.of(context).surface,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          if (resourceTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Page information',
                    onPressed: onPageInfo,
                    icon: const Icon(Icons.info_outline),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: onAddress,
                      child: Text(resourceTitle!, textAlign: TextAlign.start),
                    ),
                  ),
                  const Tooltip(
                    message: 'Installed text · no live page to reload',
                    child: Icon(Icons.offline_pin_outlined),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: kIsWeb
                  ? [
                      IconButton(
                        tooltip: 'Home',
                        onPressed: onHome,
                        icon: const Icon(Icons.home_outlined),
                      ),
                      IconButton(
                        tooltip: 'Library',
                        onPressed: onLibrary,
                        icon: const Icon(Icons.bookmark_border),
                      ),
                      IconButton(
                        tooltip: 'Your Spaces',
                        onPressed: onSpaces,
                        icon: const Icon(Icons.dashboard_outlined),
                      ),
                      IconButton(
                        tooltip: 'App sessions ($tabCount)',
                        onPressed: onTabs,
                        icon: const Icon(Icons.view_agenda_outlined),
                      ),
                      IconButton(
                        tooltip: 'Menu',
                        onPressed: onMenu,
                        icon: const Icon(Icons.menu),
                      ),
                    ]
                  : [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Forward',
                        onPressed: onForward,
                        icon: const Icon(Icons.arrow_forward_ios, size: 20),
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
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: WingmanTokens.of(context).text,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$tabCount',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Menu',
                        onPressed: onMenu,
                        icon: const Icon(Icons.menu),
                      ),
                    ],
            ),
          ),
        ],
      ),
    ),
  );
}

class MenuAction {
  const MenuAction(this.label, this.icon, this.onTap, {this.subtitle});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? subtitle;
}

Future<void> showBrowserMenu(
  BuildContext context,
  Map<String, List<MenuAction>> groups,
) => showWingmanSheet<void>(
  context: context,
  builder: (sheet) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Menu',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Close menu',
              onPressed: () => Navigator.pop(sheet),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        for (final group in groups.entries) ...[
          const SizedBox(height: 16),
          WingmanSection(title: group.key),
          for (final action in group.value)
            WingmanSettingsRow(
              icon: action.icon,
              title: action.label,
              subtitle: action.subtitle,
              onTap: action.onTap == null
                  ? null
                  : () {
                      Navigator.pop(sheet);
                      action.onTap!();
                    },
            ),
        ],
      ],
    ),
  ),
);
