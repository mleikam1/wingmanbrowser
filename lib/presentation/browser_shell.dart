import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../browser/browser_engine.dart';
import '../domain/search.dart';
import '../state/browser_state.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tab_switcher.dart';
import 'widgets/omnibox.dart';
import 'widgets/browser_toolbar.dart';
import 'widgets/browser_page_error.dart';
import 'widgets/clear_browsing_data_dialog.dart';

class BrowserShell extends StatefulWidget {
  const BrowserShell({super.key, required this.state});
  final BrowserState state;
  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell>
    with WidgetsBindingObserver {
  BrowserState get data => widget.state;
  late final BrowserEnginePool engine;
  final native = NativeBrowserService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    engine = BrowserEnginePool(
      confirm: confirm,
      prompt: prompt,
      onPageChanged: (id, url, title, completed) => data.pageChanged(
        tabId: id,
        url: url,
        title: title,
        completed: completed,
      ),
      onMessage: message,
    );
    if (!kIsWeb) unawaited(initializeNative());
  }

  Future<void> initializeNative() async {
    try {
      await native.initialize(
        onMessage: message,
        onRendererGone: engine.rendererGone,
        onNavigationSettled: engine.navigationSettled,
        onIncomingUri: (uri) {
          if (!mounted) return;
          try {
            data.newTab(url: uri.toString());
            unawaited(openActive());
          } on StateError {
            message('Close a tab before opening another (50 tab limit).');
          } on FormatException {
            message('This incoming address could not be opened.');
          }
        },
      );
      if (!data.activeTab.isHome) await openActive();
    } catch (_) {
      message(
        'Some device features are unavailable. You can still use Wingman Home.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(data.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    native.dispose();
    engine.dispose();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> confirm(String title, String text) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(text)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> prompt(String title, String text, String initial) async {
    if (!mounted) return null;
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty) Text(text),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                autofocus: true,
                obscureText: title == 'Website password',
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: !data.activeTab.isPrivate,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    // The route may still animate with its field attached after pop.
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    return result;
  }

  Future<void> navigate(String input) async {
    try {
      final target = kIsWeb
          ? const OmniboxParser().parse(
              input,
              provider: SearchProvider.byId(data.settings.searchProviderId),
            )
          : data.navigate(input);
      if (kIsWeb || target.isExternal) {
        if (target.isExternal &&
            !await confirm(
              'Open another app?',
              'This link will leave Wingman and open an app for ${target.uri.scheme} links.',
            )) {
          return;
        }
        final opened = await launchUrl(
          target.uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        if (!opened) message('No app could open this link.');
      } else {
        await openActive();
      }
    } on FormatException catch (error) {
      message(error.message);
    } catch (_) {
      message('That page could not be opened. Please try again.');
    }
  }

  Future<void> openActive() async {
    if (kIsWeb) return;
    final tab = data.activeTab;
    if (tab.isHome) return;
    try {
      await engine.open(
        tabId: tab.id,
        url: tab.url,
        isPrivate: tab.isPrivate,
        desktopMode: tab.desktopMode,
      );
      if (!mounted) return;
      engine.activate(data.activeId);
      if (data.activeId == tab.id && engine.view(tab.id) == null) {
        message('The browser could not start this tab. Please try again.');
        data.goHome();
      }
    } catch (_) {
      if (!mounted) return;
      message(
        'The browser engine could not open this tab. Return home and try again.',
      );
      if (data.activeId == tab.id && engine.view(tab.id) == null) data.goHome();
    }
  }

  Future<void> newTab(bool private) async {
    if (private) {
      try {
        if (!await native.privateBrowsingAvailable()) {
          message(
            'Private browsing requires an updated WebView provider with isolated profile cleanup.',
          );
          return;
        }
      } catch (_) {
        message('Private browsing is unavailable on this device.');
        return;
      }
    }
    try {
      data.newTab(isPrivate: private);
      engine.activate(data.activeId);
    } on StateError {
      message('Close a tab before opening another (50 tab limit).');
    }
  }

  Future<void> closeTab(String id) async {
    await engine.close(id);
    data.closeTab(id);
    await openActive();
  }

  void selectTab(String id) {
    data.selectTab(id);
    unawaited(openActive());
  }

  Future<void> home() async {
    final id = data.activeId;
    data.goHome();
    await engine.close(id);
  }

  void library(bool bookmarks) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => LibraryScreen(
        state: data,
        bookmarks: bookmarks,
        onNavigate: navigate,
      ),
    ),
  );
  void settings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        state: data,
        onClear: clearData,
        onDefaultBrowser: () async {
          try {
            if (!await native.requestDefaultBrowser()) {
              message(
                'Default-browser settings are unavailable on this device.',
              );
            }
          } catch (_) {
            message('Default-browser settings are unavailable on this device.');
          }
        },
      ),
    ),
  );
  void tabs() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => TabSwitcher(
        state: data,
        onSelect: selectTab,
        onClose: closeTab,
        onNew: newTab,
      ),
    ),
  );
  Future<void> clearData() async {
    final choice = await showDialog<Set<String>>(
      context: context,
      builder: (_) => const ClearBrowsingDataDialog(),
    );
    if (choice == null || choice.isEmpty) return;
    try {
      if (!kIsWeb && choice.any((e) => e != 'history')) {
        await engine.clearData(
          cookies: choice.contains('cookies'),
          cache: choice.contains('cache'),
          storage: choice.contains('storage'),
        );
      }
      if (choice.contains('history')) await data.clearHistory();
      message('Selected browsing data cleared.');
      await openActive();
    } catch (_) {
      message(
        'Some data could not be cleared. Please close your tabs and try again.',
      );
    }
  }

  Future<void> menu(String value) async {
    final tab = data.activeTab;
    switch (value) {
      case 'bookmark':
        data.toggleBookmark();
      case 'bookmarks':
        library(true);
      case 'history':
        library(false);
      case 'settings':
        settings();
      case 'private':
        await newTab(true);
      case 'new':
        await newTab(false);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: tab.url));
        message('Address copied.');
      case 'share':
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            uri: Uri.parse(tab.url),
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      case 'external':
        if (await confirm(
          'Open outside Wingman?',
          'Your device’s external browser will receive this address.',
        )) {
          if (!await launchUrl(
            Uri.parse(tab.url),
            mode: LaunchMode.externalApplication,
          )) {
            message('No external browser could open this page.');
          }
        }
      case 'desktop':
        data.setDesktopMode(!tab.desktopMode);
        await engine.setDesktopMode(tab.id, !tab.desktopMode);
      case 'find':
        final query = await prompt('Find in page', '', '');
        if (query != null) await engine.find(tab.id, query);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([data, engine]),
    builder: (context, _) {
      final tab = data.activeTab;
      final page = engine.status(tab.id);
      final scheme = Theme.of(context).colorScheme;
      final liveIds = engine.liveTabIds;
      final visibleIndex = tab.isHome || kIsWeb
          ? 0
          : liveIds.indexOf(tab.id) + 1;
      return PopScope(
        canPop: tab.isHome,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (page.canGoBack) {
              engine.back(tab.id);
            } else {
              home();
            }
          }
        },
        child: Scaffold(
          backgroundColor: tab.isPrivate ? scheme.tertiaryContainer : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (data.storageError != null)
                  MaterialBanner(
                    content: const Text(
                      'Local storage is unavailable. Changes may not be saved.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => confirm(
                          'Local storage unavailable',
                          'This session can continue in memory. Restart Wingman to retry local storage. Existing stored data has not been overwritten.',
                        ),
                        child: const Text('Details'),
                      ),
                    ],
                  ),
                if (tab.isPrivate)
                  Container(
                    width: double.infinity,
                    color: scheme.tertiaryContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 16,
                          color: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Private tab · not saved in history',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!tab.isHome && !kIsWeb)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      children: [
                        Omnibox(
                          key: ValueKey(tab.id),
                          compact: true,
                          hasPageError: page.error != null,
                          url: tab.url,
                          isPrivate: tab.isPrivate,
                          onSubmit: navigate,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            page.error != null
                                ? 'Page unavailable · ${Uri.tryParse(tab.url)?.host ?? ''}'
                                : '${tab.isSecure ? 'HTTPS address' : 'Not encrypted · HTTP'} · ${page.title.isEmpty ? tab.title : page.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!tab.isHome && page.isLoading)
                  LinearProgressIndicator(
                    value: page.progress / 100,
                    minHeight: 2,
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(
                          index: visibleIndex,
                          children: [
                            if (tab.isHome || kIsWeb)
                              HomeScreen(
                                key: ValueKey('home-${tab.id}'),
                                state: data,
                                onNavigate: navigate,
                                onSettings: settings,
                                onBookmarks: () => library(true),
                                onPrivate: () => newTab(true),
                              )
                            else
                              const SizedBox.shrink(),
                            for (final id in liveIds)
                              KeyedSubtree(
                                key: ValueKey('engine-$id'),
                                child:
                                    engine.view(id) ??
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                              ),
                          ],
                        ),
                      ),
                      if (!tab.isHome && !kIsWeb && !liveIds.contains(tab.id))
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Colors.white,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      if (!tab.isHome && page.error != null)
                        Positioned.fill(
                          child: BrowserPageError(
                            message: page.error.toString(),
                            onRetry: () => engine.reload(tab.id),
                            onHome: home,
                            onBack: page.canGoBack
                                ? () => engine.back(tab.id)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: kIsWeb
              ? null
              : BrowserToolbar(
                  isHome: tab.isHome,
                  isPrivate: tab.isPrivate,
                  isLoading: page.isLoading,
                  isBookmarked: data.isBookmarked,
                  desktopMode: tab.desktopMode,
                  tabCount: data.tabs.length,
                  onBack: !tab.isHome && page.canGoBack
                      ? () => engine.back(tab.id)
                      : null,
                  onForward: !tab.isHome && page.canGoForward
                      ? () => engine.forward(tab.id)
                      : null,
                  onPrimaryAction: tab.isHome
                      ? () => newTab(false)
                      : page.isLoading
                      ? () => engine.stop(tab.id)
                      : () => engine.reload(tab.id),
                  onHome: home,
                  onTabs: tabs,
                  onMenuSelected: (value) async {
                    try {
                      await menu(value);
                    } catch (_) {
                      message('This action could not be completed.');
                    }
                  },
                ),
        ),
      );
    },
  );
}
