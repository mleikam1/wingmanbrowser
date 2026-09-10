import 'package:flutter/material.dart';
import '../../state/browser_state.dart';
import '../widgets/brand.dart';

class TabSwitcher extends StatelessWidget {
  const TabSwitcher({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
  });
  final BrowserState state;
  final ValueChanged<String> onSelect, onClose;
  final ValueChanged<bool> onNew;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          '${state.tabs.length} open ${state.tabs.length == 1 ? 'tab' : 'tabs'}',
        ),
        actions: [
          IconButton(
            tooltip: 'Done',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(190),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: state.tabs.length,
        itemBuilder: (context, index) {
          final tab = state.tabs[index];
          final selected = state.activeId == tab.id;
          final scheme = Theme.of(context).colorScheme;
          return Card(
            color: tab.isPrivate
                ? scheme.tertiaryContainer
                : scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.pop(context);
                onSelect(tab.id);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          tab.isPrivate
                              ? Icons.visibility_off_outlined
                              : Icons.public,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tab.isPrivate
                                ? 'Private tab'
                                : selected
                                ? 'Current tab'
                                : 'Tab',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        IconButton(
                          tooltip:
                              'Close ${tab.isHome ? 'new tab' : tab.title}',
                          onPressed: () => onClose(tab.id),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    const Spacer(),
                    WingmanMark(size: 32, isPrivate: tab.isPrivate),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        tab.isHome
                            ? 'New tab'
                            : tab.title.isEmpty
                            ? Uri.tryParse(tab.url)?.host ?? 'Website'
                            : tab.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!tab.isHome)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Text(
                          Uri.tryParse(tab.url)?.host ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onNew(false);
                },
                icon: const Icon(Icons.add),
                label: const Text('New tab'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onNew(true);
                },
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('Private tab'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
