import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../guard/guard_models.dart';
import '../guard/safe_search_policy.dart';
import 'reader_article.dart';
export 'reader_article.dart' show ReaderArticle;

const _nativeChannel = MethodChannel('wingman/browser');
typedef BrowserGuardRequest = GuardRequest;

/// App-only channel for OS integration. No website JavaScript channel is installed.
class NativeBrowserService {
  /// Native protection covers all routes; false cannot weaken that baseline.
  Future<void> setSensitiveContent(bool sensitive) async {
    if (!kIsWeb) {
      await _nativeChannel.invokeMethod<void>('setSensitiveContent', {
        'sensitive': sensitive,
      });
    }
  }

  Future<void> initialize({
    required void Function(Uri) onIncomingUri,
    void Function(String)? onMessage,
    void Function(int)? onRendererGone,
    void Function(int, String)? onNavigationSettled,
    void Function(Map<String, dynamic>)? onGuardBlocked,
    void Function(int, int)? onTrackersBlocked,
  }) async {
    if (kIsWeb) return;
    void accept(Object? value) {
      final uri = Uri.tryParse(value?.toString() ?? '');
      if (_isWebUri(uri)) onIncomingUri(uri!);
    }

    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'incomingUri') accept(call.arguments);
      if (call.method == 'rendererGone') {
        onRendererGone?.call((call.arguments as num).toInt());
      }
      if (call.method == 'message') onMessage?.call(call.arguments as String);
      if (call.method == 'navigationSettled') {
        final arguments = call.arguments as Map;
        onNavigationSettled?.call(
          (arguments['id'] as num).toInt(),
          arguments['attemptedUrl'] as String,
        );
      }
      if (call.method == 'guardBlocked') {
        onGuardBlocked?.call(Map<String, dynamic>.from(call.arguments as Map));
      }
      if (call.method == 'trackersBlocked') {
        final arguments = call.arguments as Map;
        onTrackersBlocked?.call(
          (arguments['id'] as num).toInt(),
          (arguments['count'] as num).toInt(),
        );
      }
    });
    try {
      accept(await _nativeChannel.invokeMethod<String>('initialize'));
    } on MissingPluginException {
      /* Desktop companion has no browser engine. */
    }
  }

  Future<bool> privateBrowsingAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _nativeChannel.invokeMethod<bool>('privateAvailable') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestDefaultBrowser() async {
    if (kIsWeb) return false;
    try {
      return await _nativeChannel.invokeMethod<bool>('defaultBrowser') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  void dispose() {
    if (!kIsWeb) _nativeChannel.setMethodCallHandler(null);
  }
}

bool _isWebUri(Uri? uri) =>
    uri != null &&
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.toString().length <= 16384;

class BrowserPageStatus {
  String url = '';
  String title = '';
  int progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  bool isLoading = false;
  String? error;
  GuardDecision? guardDecision;
}

class _GuardBlockedTab {
  _GuardBlockedTab(
    this.status,
    this.isPrivate,
    this.desktopMode,
    this.previousUrl,
  );
  final BrowserPageStatus status;
  final bool isPrivate;
  final bool desktopMode;
  final String? previousUrl;
}

class _EngineEntry {
  _EngineEntry(this.id, this.controller, this.isPrivate);
  final String id;
  final WebViewController controller;
  final bool isPrivate;
  final BrowserPageStatus status = BrowserPageStatus();
  String requestedUrl = '';
  String? lastCommittedUrl;
  int navigationRevision = 0;
  bool needsLoad = false;
  bool closed = false;
  bool crashed = false;
  bool desktopMode = false;
  int refreshRevision = 0;
  int? nativeId;
  String? mobileUserAgent;
  late final Widget widget;
}

/// Metadata lives in BrowserStore. This bounded pool owns at most three engines.
/// Evicted normal tabs reload their last URL. An evicted private tab ends its
/// native session; it cannot leak cookies into a later session or normal tabs.
class BrowserEnginePool extends ChangeNotifier with WidgetsBindingObserver {
  BrowserEnginePool({
    required this.confirm,
    required this.prompt,
    required this.onPageChanged,
    required this.onMessage,
    this.navigationPolicy,
    this.onGuardBlock,
    this.onTrackersBlocked,
    this.beforeLoadForTesting,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<bool> Function(String title, String message) confirm;
  final Future<String?> Function(String title, String message, String initial)
  prompt;
  final void Function(String tabId, String url, String title, bool completed)
  onPageChanged;
  final void Function(String message) onMessage;
  final Future<GuardDecision> Function(BrowserGuardRequest request)?
  navigationPolicy;
  final void Function(GuardDecision decision, bool isPrivate)? onGuardBlock;
  final void Function(int count, bool isPrivate)? onTrackersBlocked;
  @visibleForTesting
  final Future<void> Function(String url)? beforeLoadForTesting;
  final Map<String, _GuardBlockedTab> _guardBlocks = {};
  Map<String, Object?> _guardPolicy = {};
  bool _guardSyncFailed = false;
  int _policyRevision = 0;
  int _appliedPolicyRevision = 0;
  Future<void> _policyQueue = Future<void>.value();
  final Map<String, _EngineEntry> _entries = {};
  final List<String> _recency = [];
  final Map<String, int> _generations = {};
  final Map<String, int> _requests = {};
  final Map<String, int> _pendingPublicRequests = {};
  int _nextRequest = 0;
  Future<void> _queue = Future<void>.value();
  String? _activeId;
  bool _disposed = false;
  int _pageScale = 100;
  Future<void>? _pendingSiteDataClear;
  bool get isClearingSiteData => _pendingSiteDataClear != null;
  bool get supportsReader =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static const maxLiveEngines = 3;
  List<String> get liveTabIds => List.unmodifiable(_entries.keys);
  int get liveEngineCount => _entries.length;
  BrowserPageStatus status(String tabId) =>
      _guardBlocks[tabId]?.status ??
      _entries[tabId]?.status ??
      BrowserPageStatus();
  Widget? view(String tabId) => _entries[tabId]?.widget;

  Future<void> setPageScale(int percentage) async {
    _pageScale = percentage.clamp(75, 200);
    for (final entry in _entries.values.toList()) {
      if (!entry.closed && !entry.crashed) {
        await _native('pageScale', entry, {'percentage': _pageScale});
      }
    }
  }

  /// User-triggered, local extraction from the current rendered main document.
  /// Unavailable for forms, hidden articles, unsupported layouts or stale tabs.
  Future<ReaderArticle?> readArticle(String tabId) async {
    // The installed Android binding cannot evaluate in an isolated world;
    // website-overridable helpers are not a safe extraction fallback.
    if (!supportsReader) return null;
    final entry = _entries[tabId];
    if (entry == null || !_canPrompt(entry) || entry.status.isLoading) {
      return null;
    }
    final request = _requests[tabId];
    final url = entry.status.url;
    try {
      Object? value = await _nativeChannel
          .invokeMethod<Object?>('readArticle', {
            'id': entry.nativeId,
            'script': readerExtractionScript,
          })
          .timeout(const Duration(seconds: 5));
      // Platform bindings differ in whether a JavaScript string is unquoted.
      for (var i = 0; i < 2 && value is String; i++) {
        value = jsonDecode(value);
      }
      final current = await entry.controller.currentUrl();
      if (!_canPrompt(entry) ||
          _requests[tabId] != request ||
          entry.status.url != url ||
          current != url ||
          value is! Map ||
          value['url'] != url ||
          value['text'] is! String) {
        return null;
      }
      final text = value['text'] as String;
      if (text.length < 120 || text.length > 60000) return null;
      final title = entry.status.title;
      return ReaderArticle(
        title: title.length > 300 ? title.substring(0, 300) : title,
        text: text,
        sourceUrl: url,
      );
    } catch (_) {
      return null;
    }
  }

  int _beginRequest(String tabId, {bool pending = false}) {
    final request = ++_nextRequest;
    _requests[tabId] = request;
    if (pending) {
      _pendingPublicRequests[tabId] = request;
    } else {
      _pendingPublicRequests.remove(tabId);
    }
    return request;
  }

  Future<void> open({
    required String tabId,
    required String url,
    required bool isPrivate,
    bool desktopMode = false,
  }) {
    final old = _entries[tabId];
    // Selecting an existing page is not a new navigation intent. In particular,
    // it must not cancel an in-flight delegate for that same issued load.
    if (old != null &&
        !old.closed &&
        !old.crashed &&
        !old.needsLoad &&
        old.isPrivate == isPrivate &&
        old.status.error == null &&
        !_guardBlocks.containsKey(tabId) &&
        !_pendingPublicRequests.containsKey(tabId) &&
        (old.requestedUrl == url || old.status.url == url)) {
      return _enqueue(() async {
        activate(tabId);
      });
    }
    final request = _beginRequest(tabId, pending: true);
    if (old != null && old.status.isLoading) unawaited(_native('stop', old));
    return _enqueue(
      () => _open(tabId, url, isPrivate, desktopMode, request: request),
    );
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final future = _queue.then((_) => operation());
    _queue = future.catchError((Object _) {});
    return future;
  }

  Future<GuardDecision> _decision(String tabId, Uri uri, bool isPrivate) async {
    try {
      return await navigationPolicy?.call(
            GuardRequest(uri: uri, tabId: tabId, isPrivate: isPrivate),
          ) ??
          GuardDecision(action: GuardAction.allow, host: uri.host);
    } catch (_) {
      // Pack updates preserve the last verified generation. A transient policy
      // error cannot become an invented threat classification.
      return GuardDecision(action: GuardAction.errorAllow, host: uri.host);
    }
  }

  Uri _safeSearch(Uri uri) => const SafeSearchPolicy().apply(
    uri,
    adultFilteringEnabled:
        _guardPolicy['guardEnabled'] == true &&
        (_guardPolicy['enabledCategories'] as List? ?? const []).contains(
          'adult',
        ),
  );

  Future<void> updateGuardPolicy(Map<String, Object?> policy) {
    // Publish the revision immediately. Policy writes have their own ordered
    // queue so a slow controller creation cannot delay a requested lock.
    final revision = ++_policyRevision;
    final future = _policyQueue.then((_) async {
      if (_disposed) return;
      try {
        if (!kIsWeb) {
          await _nativeChannel.invokeMethod<void>('updateGuardPolicy', policy);
        }
        _guardPolicy = Map.unmodifiable(policy);
        _guardSyncFailed = false;
        _appliedPolicyRevision = revision;
      } catch (_) {
        _guardSyncFailed = true;
        for (final entry in _entries.values.toList()) {
          await _native('hideForGuard', entry);
          _setPageError(
            entry,
            'Local protection could not be updated. Retry the Guard setting before browsing.',
          );
        }
        rethrow;
      }
    });
    _policyQueue = future.catchError((Object _) {});
    return future;
  }

  Future<int> _waitForPolicy() async {
    while (true) {
      final revision = _policyRevision;
      await _policyQueue;
      if (revision == _policyRevision) return revision;
    }
  }

  bool _canPrompt(_EngineEntry entry) =>
      !entry.closed &&
      !entry.crashed &&
      entry.id == _activeId &&
      entry.status.guardDecision == null &&
      entry.status.error == null &&
      !_guardSyncFailed &&
      _appliedPolicyRevision == _policyRevision;

  void _retryAfterPolicy(
    String tabId,
    String url,
    bool isPrivate,
    bool desktopMode,
    int generation,
    int request,
  ) {
    if (_requests[tabId] != request) return;
    _entries[tabId]?.needsLoad = true;
    unawaited(
      _enqueue(() async {
        if (!_disposed &&
            generation == (_generations[tabId] ?? 0) &&
            _requests[tabId] == request) {
          await _open(
            tabId,
            url,
            isPrivate,
            desktopMode,
            activateTab: false,
            request: request,
          );
        }
      }),
    );
  }

  void _blockGuard(
    String tabId,
    String url,
    bool isPrivate,
    bool desktopMode,
    GuardDecision decision,
  ) {
    if (_disposed) return;
    final entry = _entries[tabId];
    final old = _guardBlocks[tabId];
    final previous = old?.previousUrl ?? entry?.lastCommittedUrl;
    final blocked = BrowserPageStatus()
      ..url = url
      ..progress = 100
      ..canGoBack = previous != null && previous != url
      ..guardDecision = decision;
    _guardBlocks[tabId] = _GuardBlockedTab(
      blocked,
      isPrivate,
      desktopMode,
      previous,
    );
    if (entry != null) {
      entry.navigationRevision++;
      entry.refreshRevision++;
      entry.status.guardDecision = decision;
      entry.status.isLoading = false;
      unawaited(_native('hideForGuard', entry));
    }
    onPageChanged(tabId, url, '', false);
    if (old?.status.url != url ||
        old?.status.guardDecision?.action != decision.action) {
      onGuardBlock?.call(decision, isPrivate);
    }
    _notify();
  }

  void guardBlocked(Map<String, dynamic> event) {
    final entries = _entries.values.where(
      (entry) => entry.nativeId == event['id'],
    );
    if (entries.isEmpty || event['decision'] is! Map) return;
    final entry = entries.first;
    final url = event['url'] as String? ?? '';
    if (entry.closed ||
        entry.crashed ||
        event['request'] != _requests[entry.id] ||
        _pendingPublicRequests.containsKey(entry.id) ||
        !_isWebUri(Uri.tryParse(url))) {
      return;
    }
    final decision = GuardDecision.fromJson(
      Map<String, Object?>.from(event['decision'] as Map),
    );
    if (decision.isBlocked) {
      _blockGuard(entry.id, url, entry.isPrivate, entry.desktopMode, decision);
    }
  }

  void trackersBlocked(int nativeId, int count) {
    if (count <= 0) return;
    final entries = _entries.values.where(
      (entry) => entry.nativeId == nativeId,
    );
    if (entries.isEmpty || entries.first.closed) return;
    onTrackersBlocked?.call(count, entries.first.isPrivate);
  }

  Future<void> retryGuard(String tabId) {
    final request = _beginRequest(tabId);
    final blocked = _guardBlocks[tabId];
    return _enqueue(() async {
      if (blocked == null || _requests[tabId] != request) return;
      await _open(
        tabId,
        blocked.status.url,
        blocked.isPrivate,
        blocked.desktopMode,
        request: request,
      );
    });
  }

  Future<void> recheckGuard() => _enqueue(() async {
    final ids = {..._entries.keys, ..._guardBlocks.keys};
    for (final id in ids) {
      final entry = _entries[id];
      final blocked = _guardBlocks[id];
      final url = blocked?.status.url ?? entry?.status.url ?? '';
      final uri = Uri.tryParse(url);
      if (!_isWebUri(uri)) continue;
      final isPrivate = blocked?.isPrivate ?? entry!.isPrivate;
      final desktopMode = blocked?.desktopMode ?? entry!.desktopMode;
      final request = _requests[id];
      final revision = await _waitForPolicy();
      final decision = await _decision(id, uri!, isPrivate);
      if (_disposed) return;
      if (_requests[id] != request ||
          revision != _policyRevision ||
          status(id).url != url) {
        continue;
      }
      if (decision.isBlocked) {
        _blockGuard(id, url, isPrivate, desktopMode, decision);
      } else if (blocked != null && id == _activeId) {
        await _open(
          id,
          url,
          isPrivate,
          desktopMode,
          activateTab: false,
          request: request,
        );
      }
    }
  });

  Future<void> _open(
    String tabId,
    String url,
    bool isPrivate,
    bool desktopMode, {
    bool activateTab = true,
    int? request,
  }) async {
    request ??= _requests[tabId] ??= ++_nextRequest;
    if (_disposed || kIsWeb || _requests[tabId] != request) return;
    if (isClearingSiteData) {
      onMessage(
        'Site data is still being cleared. Wait before loading another page.',
      );
      return;
    }
    final policyRevision = await _waitForPolicy();
    if (_guardSyncFailed) {
      onMessage(
        'Local protection is unavailable. Retry the Guard setting before browsing.',
      );
      return;
    }
    final generation = _generations[tabId] ?? 0;
    var uri = Uri.tryParse(url);
    if (!_isWebUri(uri)) {
      onMessage('Enter a valid HTTP or HTTPS address.');
      return;
    }
    uri = _safeSearch(uri!);
    url = uri.toString();
    final decision = await _decision(tabId, uri, isPrivate);
    if (_disposed ||
        generation != (_generations[tabId] ?? 0) ||
        _requests[tabId] != request) {
      return;
    }
    if (policyRevision != _policyRevision) {
      _retryAfterPolicy(
        tabId,
        url,
        isPrivate,
        desktopMode,
        generation,
        request,
      );
      return;
    }
    if (decision.isBlocked) {
      _pendingPublicRequests.remove(tabId);
      _blockGuard(tabId, url, isPrivate, desktopMode, decision);
      if (activateTab) activate(tabId);
      return;
    }
    final wasBlocked = _guardBlocks.remove(tabId) != null;
    var entry = _entries[tabId];
    if (entry != null) entry.status.guardDecision = null;
    if (entry?.crashed == true) {
      await _closeNow(tabId);
      entry = null;
    }
    if (entry == null) {
      if (isPrivate &&
          !await NativeBrowserService().privateBrowsingAvailable()) {
        onMessage(
          'Private browsing requires a newer Android System WebView. Update it and try again.',
        );
        return;
      }
      while (_entries.length >= maxLiveEngines) {
        final oldest = _recency.first;
        final wasPrivate = _entries[oldest]?.isPrivate == true;
        await _closeNow(oldest);
        if (wasPrivate) {
          onMessage('An inactive private session was cleared to free memory.');
        }
      }
      PlatformWebViewControllerCreationParams params =
          const PlatformWebViewControllerCreationParams();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final wk = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          javaScriptCanOpenWindowsAutomatically: false,
        );
        if (isPrivate) {
          final configured = await _nativeChannel.invokeMethod<bool>(
            'privateConfiguration',
            {'id': wk.wingmanConfigurationIdentifier},
          );
          if (configured != true) {
            throw StateError('Private storage unavailable');
          }
        }
        params = wk;
      }
      late final _EngineEntry created;
      final controller = WebViewController.fromPlatformCreationParams(
        params,
        onPermissionRequest: (request) => _permission(created, request),
      );
      created = _EngineEntry(tabId, controller, isPrivate);
      entry = created;
      try {
        await _configure(created);
        await _native('pageScale', created, {'percentage': _pageScale});
        if (_disposed ||
            generation != (_generations[tabId] ?? 0) ||
            _requests[tabId] != request) {
          created.closed = true;
          await _native('close', created);
          return;
        }
        created.widget = WebViewWidget(
          key: ValueKey('engine-$tabId'),
          controller: controller,
        );
        _entries[tabId] = created;
        await setDesktopMode(tabId, desktopMode, reload: false);
      } catch (_) {
        created.closed = true;
        if (created.nativeId != null) {
          try {
            await _nativeChannel.invokeMethod<void>('close', {
              'id': created.nativeId,
            });
          } catch (_) {}
        }
        onMessage(
          isPrivate
              ? 'Private browsing could not be isolated. The page was not loaded.'
              : 'The browser could not start. Please try again.',
        );
        return;
      }
    }
    if (_requests[tabId] != request) return;
    if (policyRevision != _policyRevision) {
      _retryAfterPolicy(
        tabId,
        url,
        isPrivate,
        desktopMode,
        generation,
        request,
      );
      return;
    }
    if (activateTab) activate(tabId);
    if (!wasBlocked &&
        !entry.needsLoad &&
        (entry.requestedUrl == url || entry.status.url == url)) {
      _pendingPublicRequests.remove(tabId);
      return;
    }
    entry.needsLoad = true;
    entry.requestedUrl = url;
    entry.status.url = url;
    entry.status.error = null;
    entry.status.isLoading = true;
    _notify();
    if (kDebugMode) await beforeLoadForTesting?.call(url);
    await _native('prepareGuardNavigation', entry, {'url': url});
    if (entry.closed ||
        generation != (_generations[tabId] ?? 0) ||
        _requests[tabId] != request) {
      return;
    }
    if (policyRevision != _policyRevision || _guardSyncFailed) {
      _retryAfterPolicy(
        tabId,
        url,
        isPrivate,
        desktopMode,
        generation,
        request,
      );
      return;
    }
    entry.needsLoad = false;
    _pendingPublicRequests.remove(tabId);
    await entry.controller.loadRequest(uri);
  }

  Future<void> _configure(_EngineEntry entry) async {
    final c = entry.controller;
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Console output deliberately discarded: sites frequently log credentials.
    await c.setOnConsoleMessage((_) {});
    await c.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) async {
          final requestedUrl = entry.status.url;
          final uri = Uri.tryParse(request.url);
          if (_isWebUri(uri)) {
            if (request.isMainFrame) {
              if (_pendingPublicRequests.containsKey(entry.id)) {
                return NavigationDecision.prevent;
              }
              final navigationRequest = _beginRequest(entry.id);
              final policyRevision = await _waitForPolicy();
              if (_guardSyncFailed) return NavigationDecision.prevent;
              final revision = ++entry.navigationRevision;
              final safeUri = _safeSearch(uri!);
              final decision = await _decision(
                entry.id,
                safeUri,
                entry.isPrivate,
              );
              if (entry.closed ||
                  entry.crashed ||
                  revision != entry.navigationRevision ||
                  _requests[entry.id] != navigationRequest) {
                return NavigationDecision.prevent;
              }
              if (policyRevision != _policyRevision) {
                _retryAfterPolicy(
                  entry.id,
                  request.url,
                  entry.isPrivate,
                  entry.desktopMode,
                  _generations[entry.id] ?? 0,
                  navigationRequest,
                );
                return NavigationDecision.prevent;
              }
              if (decision.isBlocked) {
                _blockGuard(
                  entry.id,
                  safeUri.toString(),
                  entry.isPrivate,
                  entry.desktopMode,
                  decision,
                );
                return NavigationDecision.prevent;
              }
              _guardBlocks.remove(entry.id);
              entry.status.guardDecision = null;
              if (safeUri != uri) {
                unawaited(
                  open(
                    tabId: entry.id,
                    url: safeUri.toString(),
                    isPrivate: entry.isPrivate,
                    desktopMode: entry.desktopMode,
                  ),
                );
                return NavigationDecision.prevent;
              }
              entry.requestedUrl = request.url;
              entry.status.error = null;
              await _native('prepareGuardNavigation', entry, {
                'url': request.url,
              });
              if (entry.closed ||
                  entry.crashed ||
                  _requests[entry.id] != navigationRequest ||
                  policyRevision != _policyRevision) {
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          }
          if (request.url == 'about:blank') return NavigationDecision.navigate;
          if (request.isMainFrame &&
              uri != null &&
              {'mailto', 'tel', 'sms'}.contains(uri.scheme)) {
            if (_canPrompt(entry) &&
                await confirm(
                  'Open another app?',
                  'This page wants to open your ${uri.scheme == 'mailto' ? 'email' : 'phone or messaging'} app.',
                ) &&
                _canPrompt(entry) &&
                entry.status.url == requestedUrl) {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                onMessage('No app is available for this link.');
              }
            }
          } else if (request.isMainFrame) {
            onMessage('This link type is blocked or unsupported.');
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          if (entry.closed ||
              entry.crashed ||
              entry.status.guardDecision != null ||
              entry.status.error != null) {
            return;
          }
          entry.status.url = url;
          entry.status.isLoading = entry.status.error == null;
          entry.status.progress = 0;
          _updatePage(entry, false);
        },
        onPageFinished: (url) async {
          if (entry.closed ||
              entry.crashed ||
              entry.status.guardDecision != null ||
              entry.status.error != null) {
            return;
          }
          entry.status.url = url;
          entry.status.progress = 100;
          await _updatePage(entry, entry.status.error == null);
          if (!entry.closed && !entry.crashed && entry.status.url == url) {
            entry.status.isLoading = false;
            entry.lastCommittedUrl = url;
            _notify();
          }
        },
        onUrlChange: (change) {
          if (entry.closed ||
              entry.crashed ||
              entry.status.error != null ||
              entry.status.guardDecision != null ||
              change.url == null ||
              !_isWebUri(Uri.tryParse(change.url!))) {
            return;
          }
          entry.status.url = change.url!;
          _updatePage(entry, false);
          _scheduleMetadataRefresh(entry);
        },
        onProgress: (progress) {
          if (entry.closed ||
              entry.crashed ||
              entry.status.guardDecision != null) {
            return;
          }
          entry.status.progress = progress;
          _notify();
        },
        onWebResourceError: (error) {
          // WebKit reports ordinary stopped/superseded navigations as cancelled.
          if (defaultTargetPlatform == TargetPlatform.iOS &&
              error.errorCode == -999) {
            return;
          }
          if (entry.closed ||
              entry.crashed ||
              entry.status.guardDecision != null ||
              error.isForMainFrame == false) {
            return;
          }
          if (error.errorType == WebResourceErrorType.unsupportedScheme) return;
          final message = switch (error.errorType) {
            WebResourceErrorType.failedSslHandshake =>
              'A secure connection could not be verified. Wingman blocked this page.',
            WebResourceErrorType.hostLookup =>
              'This website could not be found. Check the address and your connection.',
            WebResourceErrorType.connect || WebResourceErrorType.timeout =>
              'This website is not responding. Check your connection and try again.',
            _ => 'This page could not be loaded. Try again or return home.',
          };
          _setPageError(entry, message, failedUrl: error.url);
        },
        onHttpError: (error) {
          if (entry.closed ||
              entry.crashed ||
              (error.request != null &&
                  error.request!.uri.toString() != entry.status.url &&
                  error.request!.uri.toString() != entry.requestedUrl)) {
            return;
          }
          final code = error.response?.statusCode;
          if (code != null && code >= 400) {
            _setPageError(
              entry,
              'The website returned an error ($code). Try again later.',
              failedUrl: error.request?.uri.toString(),
            );
          }
        },
        onSslAuthError: (error) {
          error.cancel();
          if (entry.closed || entry.crashed) return;
          _setPageError(
            entry,
            'A secure connection could not be verified. Wingman blocked this page.',
          );
        },
        onHttpAuthRequest: (request) async {
          final requestedUrl = entry.status.url;
          final requestIdentity = _requests[entry.id];
          if (!_canPrompt(entry) ||
              !entry.status.url.startsWith('https:') ||
              request.host != _host(entry)) {
            request.onCancel();
            return;
          }
          final name = await prompt(
            'Website sign-in',
            'Username for ${request.host}',
            '',
          );
          if (name == null ||
              !_canPrompt(entry) ||
              _requests[entry.id] != requestIdentity ||
              entry.status.url != requestedUrl) {
            request.onCancel();
            if (name == null &&
                _canPrompt(entry) &&
                _requests[entry.id] == requestIdentity &&
                entry.status.url == requestedUrl) {
              _setPageError(
                entry,
                'Website sign-in was cancelled.',
                failedUrl: requestedUrl,
              );
            }
            return;
          }
          final password = await prompt(
            'Website password',
            'Password for ${request.host}',
            '',
          );
          if (password == null ||
              !_canPrompt(entry) ||
              _requests[entry.id] != requestIdentity ||
              entry.status.url != requestedUrl) {
            request.onCancel();
            if (password == null &&
                _canPrompt(entry) &&
                _requests[entry.id] == requestIdentity &&
                entry.status.url == requestedUrl) {
              _setPageError(
                entry,
                'Website sign-in was cancelled.',
                failedUrl: requestedUrl,
              );
            }
            return;
          }
          request.onProceed(WebViewCredential(user: name, password: password));
        },
      ),
    );
    await c.setOnJavaScriptAlertDialog((request) async {
      if (_canPrompt(entry)) {
        await confirm('Message from ${_host(entry)}', request.message);
      }
    });
    await c.setOnJavaScriptConfirmDialog((request) async {
      final url = entry.status.url;
      if (!_canPrompt(entry)) return false;
      final answer = await confirm(
        'Confirm for ${_host(entry)}',
        request.message,
      );
      return answer && _canPrompt(entry) && entry.status.url == url;
    });
    await c.setOnJavaScriptTextInputDialog((request) async {
      final url = entry.status.url;
      if (!_canPrompt(entry)) return '';
      final answer = await prompt(
        'Input for ${_host(entry)}',
        request.message,
        request.defaultText ?? '',
      );
      return _canPrompt(entry) && entry.status.url == url ? answer ?? '' : '';
    });
    if (c.platform is AndroidWebViewController) {
      final android = c.platform as AndroidWebViewController;
      await android.setAllowFileAccess(false);
      await android.setMixedContentMode(MixedContentMode.neverAllow);
      await android.setMediaPlaybackRequiresUserGesture(true);
      await android.setOnShowFileSelector((params) async {
        final requestedUrl = entry.status.url;
        if (!_canPrompt(entry)) return [];
        final files =
            await _nativeChannel.invokeListMethod<String>('chooseFiles', {
              'types': params.acceptTypes,
              'multiple': params.mode == FileSelectorMode.openMultiple,
            }) ??
            <String>[];
        return _canPrompt(entry) && entry.status.url == requestedUrl
            ? files
            : <String>[];
      });
      await android.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          final requestedUrl = entry.status.url;
          final uri = Uri.tryParse(request.origin);
          final allowed =
              _canPrompt(entry) &&
              uri?.scheme == 'https' &&
              await confirm(
                'Location access',
                '${uri!.host} wants your approximate location for this session.',
              ) &&
              _canPrompt(entry) &&
              entry.status.url == requestedUrl &&
              await _nativeChannel.invokeMethod<bool>('requestPermissions', {
                    'types': ['location'],
                  }) ==
                  true;
          return GeolocationPermissionsResponse(
            allow:
                allowed &&
                _canPrompt(entry) &&
                entry.status.url == requestedUrl,
            retain: false,
          );
        },
      );
      entry.nativeId = android.webViewIdentifier;
    } else if (c.platform is WebKitWebViewController) {
      final wk = c.platform as WebKitWebViewController;
      await wk.setAllowsBackForwardNavigationGestures(true);
      await wk.setAllowsLinkPreview(false);
      entry.nativeId = wk.webViewIdentifier;
    }
    await c
        .currentUrl(); // Await native creation before touching native settings.
    final configured = await _nativeChannel.invokeMethod<bool>('configure', {
      'id': entry.nativeId,
      'private': entry.isPrivate,
      'tabId': entry.id,
    });
    if (configured != true) throw StateError('Browser configuration failed');
  }

  String _host(_EngineEntry entry) =>
      Uri.tryParse(entry.status.url)?.host ?? 'this website';
  Future<void> _permission(
    _EngineEntry entry,
    WebViewPermissionRequest request,
  ) async {
    final requestedUrl = entry.status.url;
    final types = request.types
        .map(
          (type) => type == WebViewPermissionResourceType.camera
              ? 'camera'
              : type == WebViewPermissionResourceType.microphone
              ? 'microphone'
              : 'unsupported',
        )
        .toList();
    if (!_canPrompt(entry) ||
        !entry.status.url.startsWith('https:') ||
        types.contains('unsupported')) {
      await request.deny();
      return;
    }
    final allowed = await confirm(
      'Website permission',
      'The page at ${_host(entry)} (including embedded content) wants to use your ${types.join(' and ')}. Allow for this request?',
    );
    if (!allowed || !_canPrompt(entry) || entry.status.url != requestedUrl) {
      await request.deny();
      return;
    }
    try {
      if (await _nativeChannel.invokeMethod<bool>('requestPermissions', {
                'types': types,
              }) ==
              true &&
          _canPrompt(entry) &&
          entry.status.url == requestedUrl) {
        await request.grant();
      } else {
        await request.deny();
      }
    } catch (_) {
      await request.deny();
    }
  }

  void _setPageError(_EngineEntry entry, String message, {String? failedUrl}) {
    if (entry.closed || entry.status.guardDecision != null) return;
    final url = _isWebUri(Uri.tryParse(failedUrl ?? ''))
        ? failedUrl!
        : entry.requestedUrl;
    if (_isWebUri(Uri.tryParse(url))) {
      entry.requestedUrl = url;
      entry.status.url = url;
      entry.status.title = '';
      onPageChanged(entry.id, url, '', false);
    }
    entry.refreshRevision++;
    entry.status.error = message;
    entry.status.isLoading = false;
    _notify();
  }

  Future<void> _updatePage(_EngineEntry entry, bool completed) async {
    if (entry.status.error != null || entry.status.guardDecision != null) {
      return;
    }
    final requestedUrl = entry.status.url;
    try {
      final values = await Future.wait<Object?>([
        entry.controller.getTitle(),
        entry.controller.canGoBack(),
        entry.controller.canGoForward(),
      ]);
      if (entry.closed ||
          entry.crashed ||
          entry.status.error != null ||
          entry.status.guardDecision != null ||
          entry.status.url != requestedUrl) {
        return;
      }
      entry.status.title = values[0] as String? ?? '';
      entry.status.canGoBack = values[1] as bool;
      entry.status.canGoForward = values[2] as bool;
      if (_isWebUri(Uri.tryParse(entry.status.url))) {
        onPageChanged(
          entry.id,
          entry.status.url,
          entry.status.title,
          completed,
        );
      }
      _notify();
    } catch (_) {
      /* A closed view must not emit stale state or diagnostic URLs. */
    }
  }

  void activate(String tabId) {
    final old = _entries[_activeId];
    if (old != null && old.id != tabId) _native('pause', old);
    _activeId = tabId;
    _recency.remove(tabId);
    if (_entries.containsKey(tabId)) {
      _recency.add(tabId);
      _native('resume', _entries[tabId]!);
    }
    _notify();
  }

  /// A native download keeps the displayed page while ending its navigation.
  Future<void> navigationSettled(int nativeId, String attemptedUrl) async {
    final entries = _entries.values.where(
      (entry) => entry.nativeId == nativeId,
    );
    if (entries.isEmpty) return;
    final entry = entries.first;
    if (entry.closed ||
        entry.crashed ||
        entry.status.error != null ||
        entry.status.guardDecision != null ||
        (entry.requestedUrl != attemptedUrl &&
            entry.status.url != attemptedUrl)) {
      return;
    }
    final pendingUrl = entry.requestedUrl;
    try {
      final currentUrl = await entry.controller.currentUrl();
      if (entry.closed ||
          entry.crashed ||
          entry.status.error != null ||
          entry.status.guardDecision != null ||
          entry.requestedUrl != pendingUrl ||
          !_isWebUri(Uri.tryParse(currentUrl ?? ''))) {
        return;
      }
      entry.requestedUrl = currentUrl!;
      entry.status.url = currentUrl;
      entry.status.isLoading = false;
      entry.status.progress = 100;
      await _updatePage(entry, false);
      _notify();
    } catch (_) {
      /* A closed view cannot settle an earlier download navigation. */
    }
  }

  Future<void> back(String tabId) async {
    final request = _beginRequest(tabId);
    await _waitForPolicy();
    if (_guardSyncFailed || _requests[tabId] != request) return;
    final blocked = _guardBlocks[tabId];
    if (blocked != null) {
      if (blocked.previousUrl != null) {
        await open(
          tabId: tabId,
          url: blocked.previousUrl!,
          isPrivate: blocked.isPrivate,
          desktopMode: blocked.desktopMode,
        );
      }
      return;
    }
    final entry = _entries[tabId];
    if (entry == null || entry.closed || entry.crashed) return;
    entry.status.error = null;
    await _native('prepareGuardNavigation', entry, {'url': entry.status.url});
    if (entry.closed || _requests[tabId] != request) return;
    await entry.controller.goBack();
    _scheduleMetadataRefresh(entry);
  }

  Future<void> forward(String tabId) async {
    final request = _beginRequest(tabId);
    await _waitForPolicy();
    if (_guardSyncFailed || _requests[tabId] != request) return;
    final entry = _entries[tabId];
    if (entry == null || entry.closed || entry.crashed) return;
    entry.status.error = null;
    await _native('prepareGuardNavigation', entry, {'url': entry.status.url});
    if (entry.closed || _requests[tabId] != request) return;
    await entry.controller.goForward();
    _scheduleMetadataRefresh(entry);
  }

  void _scheduleMetadataRefresh(_EngineEntry entry) {
    final revision = ++entry.refreshRevision;
    // SPA/popstate and back-forward-cache transitions can finish without a
    // page-finished event. Two bounded refreshes let URL/title/history settle.
    for (final delay in [100, 500]) {
      unawaited(
        Future<void>.delayed(Duration(milliseconds: delay), () async {
          if (entry.closed ||
              entry.crashed ||
              entry.status.error != null ||
              entry.status.guardDecision != null ||
              revision != entry.refreshRevision) {
            return;
          }
          try {
            final url = await entry.controller.currentUrl();
            if (entry.closed ||
                entry.crashed ||
                entry.status.error != null ||
                entry.status.guardDecision != null ||
                revision != entry.refreshRevision ||
                !_isWebUri(Uri.tryParse(url ?? ''))) {
              return;
            }
            entry.status.url = url!;
            await _updatePage(entry, false);
          } catch (_) {
            /* A closed renderer cannot update browser chrome. */
          }
        }),
      );
    }
  }

  Future<void> reload(String tabId) async {
    final request = _beginRequest(tabId);
    final policyRevision = await _waitForPolicy();
    if (_guardSyncFailed || _requests[tabId] != request) return;
    if (_guardBlocks.containsKey(tabId)) return retryGuard(tabId);
    final entry = _entries[tabId];
    if (entry == null) return;
    if (entry.crashed) {
      final url = entry.status.url;
      final wasActive = _activeId == tabId;
      return _enqueue(() async {
        if (_requests[tabId] != request) return;
        await _closeNow(tabId);
        if (_requests[tabId] != request) return;
        await _open(
          tabId,
          url,
          entry.isPrivate,
          entry.desktopMode,
          activateTab: false,
          request: request,
        );
        if (_requests[tabId] == request && wasActive && _activeId == null) {
          activate(tabId);
        }
      });
    }
    final requestedUrl = entry.status.url;
    final uri = Uri.tryParse(requestedUrl);
    if (!_isWebUri(uri)) return;
    final decision = await _decision(tabId, uri!, entry.isPrivate);
    if (entry.closed ||
        entry.crashed ||
        _requests[tabId] != request ||
        entry.status.url != requestedUrl) {
      return;
    }
    if (policyRevision != _policyRevision) {
      _retryAfterPolicy(
        tabId,
        requestedUrl,
        entry.isPrivate,
        entry.desktopMode,
        _generations[tabId] ?? 0,
        request,
      );
      return;
    }
    if (decision.isBlocked) {
      _blockGuard(
        tabId,
        requestedUrl,
        entry.isPrivate,
        entry.desktopMode,
        decision,
      );
      return;
    }
    final failedUrl = entry.status.error == null ? null : entry.status.url;
    await _native('prepareGuardNavigation', entry, {'url': requestedUrl});
    if (_requests[tabId] != request || entry.status.url != requestedUrl) return;
    if (policyRevision != _policyRevision || _guardSyncFailed) {
      _retryAfterPolicy(
        tabId,
        requestedUrl,
        entry.isPrivate,
        entry.desktopMode,
        _generations[tabId] ?? 0,
        request,
      );
      return;
    }
    entry.status.error = null;
    entry.status.isLoading = true;
    entry.status.progress = 0;
    _notify();
    if (failedUrl != null && _isWebUri(Uri.tryParse(failedUrl))) {
      await entry.controller.loadRequest(Uri.parse(failedUrl));
    } else {
      await entry.controller.reload();
    }
  }

  Future<void> stop(String tabId) async {
    final request = _beginRequest(tabId);
    final entry = _entries[tabId];
    if (entry == null) return;
    await _native('stop', entry);
    if (_requests[tabId] != request) return;
    entry.status.isLoading = false;
    _notify();
  }

  Future<void> find(String tabId, String query) async {
    final entry = _entries[tabId];
    if (entry != null) await _native('find', entry, {'query': query});
  }

  Future<void> findNext(String tabId, {bool forward = true}) async {
    final entry = _entries[tabId];
    if (entry != null) await _native('findNext', entry, {'forward': forward});
  }

  Future<void> setDesktopMode(
    String tabId,
    bool enabled, {
    bool reload = true,
  }) async {
    final entry = _entries[tabId];
    if (entry == null) return;
    entry.desktopMode = enabled;
    if (entry.crashed) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _native('desktop', entry, {'enabled': enabled});
    } else {
      entry.mobileUserAgent ??= await entry.controller.getUserAgent();
      final desktopAgent = entry.mobileUserAgent
          ?.replaceFirst(
            RegExp(r'\(Linux; Android[^)]*\)'),
            '(X11; Linux x86_64)',
          )
          .replaceAll('Version/4.0 ', '')
          .replaceAll(' Mobile', '');
      await entry.controller.setUserAgent(
        enabled ? desktopAgent : entry.mobileUserAgent,
      );
    }
    if (reload) await this.reload(tabId);
  }

  Future<void> close(String tabId) {
    // Invalidate an in-flight construction immediately, then release in order.
    _generations[tabId] = (_generations[tabId] ?? 0) + 1;
    _requests.remove(tabId);
    _pendingPublicRequests.remove(tabId);
    return _enqueue(() => _closeNow(tabId));
  }

  Future<void> _closeNow(String tabId) async {
    _guardBlocks.remove(tabId);
    final entry = _entries.remove(tabId);
    _recency.remove(tabId);
    if (entry == null) {
      _notify();
      return;
    }
    entry.closed = true;
    if (_activeId == tabId) _activeId = null;
    _notify();
    // Let Flutter unmount its platform view before releasing the native view.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    await _native('close', entry);
    final platform = entry.controller.platform;
    if (platform is WebKitWebViewController) {
      await platform.wingmanDispose();
      // Pigeon releases its native strong reference asynchronously. Observe
      // completion instead of letting shared deletion wait on old web processes.
      for (var attempt = 0; attempt < 100; attempt++) {
        if (await _nativeChannel.invokeMethod<bool>('closedViewReleased', {
              'id': entry.nativeId,
            }) ==
            true) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      throw StateError('The browser could not finish releasing a closed page.');
    }
  }

  Future<void> clearData({
    bool cookies = true,
    bool cache = true,
    bool storage = true,
  }) {
    for (final id in _requests.keys.toList()) {
      _beginRequest(id);
      _generations[id] = (_generations[id] ?? 0) + 1;
    }
    return _enqueue(
      () => _clearDataNow(cookies: cookies, cache: cache, storage: storage),
    );
  }

  Future<void> _clearDataNow({
    required bool cookies,
    required bool cache,
    required bool storage,
  }) async {
    if (_pendingSiteDataClear != null) {
      throw StateError(
        'A previous site-data deletion is still pending. Wait for it to finish before choosing another deletion.',
      );
    }
    final operation = _pendingSiteDataClear =
        _performSiteDataClear(
          cookies: cookies,
          cache: cache,
          storage: storage,
        ).whenComplete(() {
          _pendingSiteDataClear = null;
          _notify();
        });
    // WebKit may leave a deletion completion pending. Release the operation
    // queue with an honest failure, keeping navigation paused until completion.
    await operation.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException(
          'Site-data clearing has not finished. Browsing is paused until it completes. Restart Wingman and retry clearing if it remains unavailable.',
        );
      },
    );
  }

  Future<void> _performSiteDataClear({
    required bool cookies,
    required bool cache,
    required bool storage,
  }) async {
    for (final entry in _entries.values.toList()) {
      // Stop every renderer before one native-store deletion. Clearing the
      // shared WK store repeatedly while other views remain live can stall.
      await _closeNow(entry.id);
    }
    if (!kIsWeb) {
      await _nativeChannel.invokeMethod<void>('clearData', {
        'cookies': cookies,
        'cache': cache,
        'storage': storage,
      });
    }
  }

  Future<void> _native(
    String method,
    _EngineEntry entry, [
    Map<String, Object?> extra = const {},
  ]) async {
    if (entry.nativeId == null || (entry.crashed && method != 'close')) return;
    try {
      await _nativeChannel.invokeMethod<void>(method, {
        'id': entry.nativeId,
        if (method == 'prepareGuardNavigation')
          'request': _requests[entry.id] ?? 0,
        ...extra,
      });
    } on PlatformException {
      if (!_disposed && method != 'close') {
        onMessage('The browser action could not be completed.');
      }
    } on MissingPluginException {
      /* Companion platform. */
    }
  }

  void rendererGone(int nativeId) {
    for (final entry in _entries.values) {
      if (entry.nativeId == nativeId) {
        entry.crashed = true;
        entry.status.isLoading = false;
        entry.status.error =
            'This page stopped responding. Reload to start a fresh browser session.';
      }
    }
    _notify();
  }

  @visibleForTesting
  Future<bool> terminateRendererForTesting(String tabId) async =>
      await _nativeChannel.invokeMethod<bool>('terminateRendererForTesting', {
        'id': _entries[tabId]!.nativeId,
      }) ??
      false;

  @visibleForTesting
  Future<Object> evaluateForTesting(String tabId, String script) =>
      _entries[tabId]!.controller.runJavaScriptReturningResult(script);

  @visibleForTesting
  Future<Map<String, dynamic>> platformStateForTesting(
    String tabId, {
    bool? shieldVisible,
  }) async => Map<String, dynamic>.from(
    await _nativeChannel.invokeMethod<Map>('privacyStateForTesting', {
          'id': _entries[tabId]?.nativeId,
          'visible': ?shieldVisible,
        }) ??
        const {},
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    for (final entry in _entries.values) {
      _native(
        state == AppLifecycleState.resumed && entry.id == _activeId
            ? 'resume'
            : 'pause',
        entry,
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _guardBlocks.clear();
    for (final id in _entries.keys.toList()) {
      unawaited(close(id));
    }
    super.dispose();
  }
}
