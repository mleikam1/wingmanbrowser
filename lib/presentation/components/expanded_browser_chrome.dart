import 'package:flutter/material.dart';
import 'wingman_components.dart';

class BrowserTabChip {
  const BrowserTabChip({
    required this.id,
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    this.isPrivate = false,
  });
  final String id, label;
  final bool selected, isPrivate;
  final VoidCallback onSelect, onClose;
}

/// Shown only for a real native engine. Width never creates engine authority.
class ExpandedBrowserChrome extends StatelessWidget {
  const ExpandedBrowserChrome({
    super.key,
    required this.tabs,
    required this.address,
    required this.onAddress,
    required this.onNewTab,
    required this.onTabs,
    required this.onMenu,
    required this.onCompanion,
    required this.onProtection,
    this.onBack,
    this.onForward,
    this.onReload,
    this.loading = false,
    this.isPrivate = false,
  });
  final List<BrowserTabChip> tabs;
  final String address;
  final VoidCallback onAddress,
      onNewTab,
      onTabs,
      onMenu,
      onCompanion,
      onProtection;
  final VoidCallback? onBack, onForward, onReload;
  final bool loading, isPrivate;
  @override
  Widget build(BuildContext context) {
    final t = WingmanTokens.of(context);
    return Material(
      color: t.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: t.raised,
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final tab in tabs)
                        Container(
                          width: 210,
                          margin: const EdgeInsets.only(top: 4, right: 4),
                          decoration: BoxDecoration(
                            color: tab.selected ? t.surface : t.raised,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: tab.onSelect,
                                  child: Row(
                                    children: [
                                      Icon(
                                        tab.isPrivate
                                            ? Icons.visibility_off_outlined
                                            : Icons.language,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          tab.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close ${tab.label}',
                                onPressed: tab.onClose,
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'New tab',
                  onPressed: onNewTab,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Tabs (${tabs.length})',
                  onPressed: onTabs,
                  icon: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: onForward,
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: loading ? 'Stop loading' : 'Reload protected page',
                  onPressed: onReload,
                  icon: Icon(loading ? Icons.close : Icons.refresh),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: t.canvas,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: onAddress,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              isPrivate
                                  ? Icons.visibility_off_outlined
                                  : Icons.search,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Protection overview',
                  onPressed: onProtection,
                  icon: const Icon(Icons.shield_outlined),
                ),
                IconButton(
                  tooltip: 'Your Wingman',
                  onPressed: onCompanion,
                  icon: const Icon(Icons.auto_awesome_outlined),
                ),
                IconButton(
                  tooltip: 'Menu',
                  onPressed: onMenu,
                  icon: const Icon(Icons.menu),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
