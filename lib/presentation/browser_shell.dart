import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../browser/browser_engine.dart';
import '../domain/search.dart';
import '../domain/local_suggestions.dart';
import '../guard_ui/guard_controller.dart';
import '../guard_ui/guard_settings_screen.dart';
import '../guard_ui/guard_surfaces.dart';
import '../monetization/ad_policy_service.dart';
import '../monetization/ad_route_observer.dart';
import '../state/browser_state.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tab_switcher.dart';
import 'widgets/omnibox.dart';
import 'widgets/browser_toolbar.dart';
import 'widgets/browser_page_error.dart';
import 'widgets/clear_browsing_data_dialog.dart';

class BrowserShell extends StatefulWidget {
  const BrowserShell({
    super.key,
    required this.state,
    this.guard,
    this.readerForTesting,
  });
  final BrowserState state;
  final GuardController? guard;
  @visibleForTesting
  final Future<ReaderArticle?> Function(String)? readerForTesting;
  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell>
    with WidgetsBindingObserver, RouteAware {
  BrowserState get data => widget.state;
  GuardController? get guard => widget.guard;
  late final BrowserEnginePool engine;
  late Listenable _adEligibilityChanges;
  late Listenable _shellChanges;
  final native = NativeBrowserService();
  bool _isForeground = true;
  bool _reading = false;
  int _readerGeneration = 0;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (_route != next) {
      adRouteObserver.unsubscribe(this);
      _route = next;
      if (next != null) adRouteObserver.subscribe(this, next);
      _readerGeneration++;
    }
  }

  @override
  void didPushNext() {
    _readerGeneration++;
  }

  @override
  void didPop() {
    _readerGeneration++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    engine = BrowserEnginePool(
      confirm: confirm,
      prompt: prompt,
      navigationPolicy: guard?.evaluate,
      onGuardBlock: guard?.recordBlock,
      onTrackersBlocked: guard?.recordTrackers,
      onPageChanged: (id, url, title, completed) {
        if (completed) guard?.navigationCompleted(id);
        return data.pageChanged(
          tabId: id,
          url: url,
          title: title,
          completed: completed,
        );
      },
      onMessage: message,
    );
    _adEligibilityChanges = Listenable.merge([data, guard]);
    _shellChanges = Listenable.merge([data, engine, guard]);
    guard?.applyNative = (policy, recheck) async {
      if (kIsWeb) return;
      await engine.updateGuardPolicy(policy);
      if (recheck) await engine.recheckGuard();
    };
    if (!kIsWeb) unawaited(initializeNative());
    if (guard?.requestSetup ?? false) {
      guard!.requestSetup = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) guardSettings();
      });
    }
  }

  Future<void> initializeNative() async {
    try {
      // Install policy before initialize can deliver a cold-start external URL.
      await guard?.sync();
      await engine.setPageScale(data.settings.pageScale);
      await native.initialize(
        onMessage: message,
        onRendererGone: engine.rendererGone,
        onNavigationSettled: engine.navigationSettled,
        onGuardBlocked: engine.guardBlocked,
        onTrackersBlocked: engine.trackersBlocked,
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
  void didUpdateWidget(covariant BrowserShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state || oldWidget.guard != widget.guard) {
      _adEligibilityChanges = Listenable.merge([data, guard]);
      _shellChanges = Listenable.merge([data, engine, guard]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _readerGeneration++;
    if (mounted) {
      setState(() => _isForeground = state == AppLifecycleState.resumed);
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(data.flush());
      guard?.pin.lock();
    }
  }

  @override
  void dispose() {
    _readerGeneration++;
    adRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    native.dispose();
    guard?.applyNative = null;
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
      final parsed = const OmniboxParser().parse(
        input,
        provider: SearchProvider.byId(data.settings.searchProviderId),
      );
      final normalized = guard?.safeSearch(parsed.uri) ?? parsed.uri;
      final target = kIsWeb ? parsed : data.navigate(normalized.toString());
      if (kIsWeb || target.isExternal) {
        if (target.isExternal &&
            !await confirm(
              'Open another app?',
              'This link will leave Wingman and open an app for ${target.uri.scheme} links.',
            )) {
          return;
        }
        final opened = await launchUrl(
          normalized,
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
      if (data.activeId == tab.id &&
          engine.view(tab.id) == null &&
          engine.status(tab.id).guardDecision == null) {
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
    guard?.forgetTab(id);
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
    guard?.forgetTab(id);
    data.goHome();
    await engine.close(id);
  }

  void library(LibraryKind kind) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          LibraryScreen(state: data, kind: kind, onNavigate: navigate),
    ),
  );
  void settings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        state: data,
        onClear: clearData,
        onPageScale: (value) async {
          data.saveSettings(data.settings.copyWith(pageScale: value));
          try {
            await engine.setPageScale(value);
          } catch (_) {
            message(
              'This website could not apply the new size. Try reloading it.',
            );
          }
        },
        onGuard: guard == null ? null : guardSettings,
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
  void guardSettings() {
    if (guard == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GuardSettingsScreen(guard: guard!),
      ),
    );
  }

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
      guard?.runtime.repository.clearCache();
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
        engine.isClearingSiteData
            ? 'Website data is still clearing. New pages are paused until it finishes. Please wait before trying again.'
            : 'Some data could not be cleared. Please close your tabs and try again.',
      );
    }
  }

  Future<void> menu(String value) async {
    final tab = data.activeTab;
    switch (value) {
      case 'bookmark':
        await data.toggleBookmark();
      case 'bookmarks':
        library(LibraryKind.bookmarks);
      case 'history':
        library(LibraryKind.history);
      case 'readingList':
        library(LibraryKind.readingList);
      case 'saveReading':
        final saved = await data.addToReadingList();
        message(
          saved
              ? 'Saved to your reading list.'
              : 'Already saved, or this page cannot be added to the reading list.',
        );
      case 'reader':
        await openReader();
      case 'settings':
        settings();
      case 'guard':
        guardSettings();
      case 'reportGuard':
        await showGuardReport(context, url: tab.url, missed: true);
      case 'tracking':
        await guard?.pauseTracking(tab.url);
        message(
          'Temporary tracking exception updated. Reload the page to apply it to existing resources.',
        );
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

  Future<void> openReader() async {
    if (kIsWeb || _reading || !_isForeground || _route?.isCurrent != true) {
      return;
    }
    final tab = data.activeTab;
    if (tab.isHome) return;
    _reading = true;
    final generation = _readerGeneration;
    try {
      final article = await (widget.readerForTesting ?? engine.readArticle)(
        tab.id,
      );
      if (!mounted ||
          generation != _readerGeneration ||
          !_isForeground ||
          _route?.isCurrent != true ||
          data.activeId != tab.id ||
          data.activeTab.url != tab.url) {
        return;
      }
      if (article == null) {
        message(
          'This page does not have readable article text. Finish loading it or try another page.',
        );
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ReaderScreen(article: article)),
      );
    } finally {
      _reading = false;
    }
  }

  AdProtectionRequirements get adProtectionRequirements {
    final controller = guard;
    if (controller == null ||
        controller.problem != null ||
        !controller.pack.integrityVerified) {
      return AdProtectionRequirements.unknown;
    }
    final policy = controller.configuration;
    if (controller.pin.hasPin ||
        controller.locked ||
        controller.focusActive ||
        policy.customBlock.isNotEmpty ||
        (policy.guardEnabled && policy.enabledCategories.isNotEmpty)) {
      return AdProtectionRequirements.strict;
    }
    return AdProtectionRequirements.standard;
  }

  AdEligibilityContext readAdEligibility() => AdEligibilityContext(
    currentSurface: data.activeTab.isHome || kIsWeb
        ? AdHostSurface.home
        : AdHostSurface.browserPage,
    isCurrentRoute: mounted && _route?.isCurrent == true,
    isForeground: _isForeground,
    protectionRequirements: adProtectionRequirements,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _shellChanges,
    builder: (context, _) {
      final isCurrentRoute = ModalRoute.isCurrentOf(context) ?? false;
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
                          localSuggestions: (input) =>
                              const LocalSuggestionService().suggest(
                                input,
                                bookmarks: data.bookmarks,
                                history: data.history,
                                isPrivate: tab.isPrivate,
                                enabled: data.settings.localSuggestions,
                              ),
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
                                onBookmarks: () =>
                                    library(LibraryKind.bookmarks),
                                onReadingList: () =>
                                    library(LibraryKind.readingList),
                                adEligibility: AdEligibilityContext(
                                  currentSurface: AdHostSurface.home,
                                  isCurrentRoute: isCurrentRoute,
                                  isForeground: _isForeground,
                                  protectionRequirements:
                                      adProtectionRequirements,
                                ),
                                adEligibilityChanges: _adEligibilityChanges,
                                readAdEligibility: readAdEligibility,
                                readAdIsPrivate: () => data.activeTab.isPrivate,
                                onPrivate: () => newTab(true),
                                guardCard: guard == null
                                    ? null
                                    : GuardHomeCard(
                                        enabled:
                                            guard!.configuration.guardEnabled,
                                        focusActive: guard!.focusActive,
                                        ready:
                                            guard!.pack.integrityVerified &&
                                            guard!.problem == null,
                                        locked: guard!.locked,
                                        blocks:
                                            guard!.guardToday +
                                            guard!.riskyToday,
                                        onOpen: guardSettings,
                                      ),
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
                            securityWarning: page.error.toString().contains(
                              'secure connection could not be verified',
                            ),
                            onRetry: () => engine.reload(tab.id),
                            onHome: home,
                            onBack: page.canGoBack
                                ? () => engine.back(tab.id)
                                : null,
                          ),
                        ),
                      if (!tab.isHome &&
                          page.guardDecision != null &&
                          guard != null)
                        Positioned.fill(
                          child: GuardBlockedPage(
                            decision: page.guardDecision!,
                            isPrivate: tab.isPrivate,
                            onBack: () {
                              if (page.canGoBack) {
                                engine.back(tab.id);
                              } else {
                                home();
                              }
                            },
                            onSettings: guardSettings,
                            onReport: () => showGuardReport(
                              context,
                              url: page.url.isEmpty ? tab.url : page.url,
                              decision: page.guardDecision,
                            ),
                            onAllowOnce: guard!.locked
                                ? null
                                : () async {
                                    try {
                                      await guard!.allowOnce(
                                        tab.id,
                                        page.guardDecision!,
                                      );
                                      await engine.retryGuard(tab.id);
                                    } catch (_) {
                                      message(
                                        'This exception could not be applied.',
                                      );
                                    }
                                  },
                            onAlwaysAllow: guard!.locked
                                ? null
                                : () async {
                                    try {
                                      await guard!.alwaysAllow(
                                        page.guardDecision!,
                                      );
                                      await engine.retryGuard(tab.id);
                                    } catch (_) {
                                      message(
                                        'This exception could not be applied.',
                                      );
                                    }
                                  },
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
                  guardAvailable: guard != null,
                  readerAvailable:
                      engine.supportsReader &&
                      !tab.isHome &&
                      !page.isLoading &&
                      page.error == null &&
                      page.guardDecision == null &&
                      engine.view(tab.id) != null,
                  readerSupported: engine.supportsReader,
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
                    } on LibraryOperationException catch (error) {
                      message(error.message);
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
