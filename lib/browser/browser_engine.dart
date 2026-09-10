import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const _nativeChannel = MethodChannel('wingman/browser');

/// App-only channel for OS integration. No website JavaScript channel is installed.
class NativeBrowserService {
  Future<void> initialize({
    required void Function(Uri) onIncomingUri,
    void Function(String)? onMessage,
    void Function(int)? onRendererGone,
    void Function(int, String)? onNavigationSettled,
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
}

class _EngineEntry {
  _EngineEntry(this.id, this.controller, this.isPrivate);
  final String id;
  final WebViewController controller;
  final bool isPrivate;
  final BrowserPageStatus status = BrowserPageStatus();
  String requestedUrl = '';
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
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<bool> Function(String title, String message) confirm;
  final Future<String?> Function(String title, String message, String initial)
  prompt;
  final void Function(String tabId, String url, String title, bool completed)
  onPageChanged;
  final void Function(String message) onMessage;
  final Map<String, _EngineEntry> _entries = {};
  final List<String> _recency = [];
  final Map<String, int> _generations = {};
  Future<void> _queue = Future<void>.value();
  String? _activeId;
  bool _disposed = false;
  static const maxLiveEngines = 3;
  List<String> get liveTabIds => List.unmodifiable(_entries.keys);
  int get liveEngineCount => _entries.length;
  BrowserPageStatus status(String tabId) =>
      _entries[tabId]?.status ?? BrowserPageStatus();
  Widget? view(String tabId) => _entries[tabId]?.widget;

  Future<void> open({
    required String tabId,
    required String url,
    required bool isPrivate,
    bool desktopMode = false,
  }) {
    return _enqueue(() => _open(tabId, url, isPrivate, desktopMode));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final future = _queue.then((_) => operation());
    _queue = future.catchError((Object _) {});
    return future;
  }

  Future<void> _open(
    String tabId,
    String url,
    bool isPrivate,
    bool desktopMode,
  ) async {
    if (_disposed || kIsWeb) return;
    final generation = _generations[tabId] ?? 0;
    final uri = Uri.tryParse(url);
    if (!_isWebUri(uri)) {
      onMessage('Enter a valid HTTP or HTTPS address.');
      return;
    }
    var entry = _entries[tabId];
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
        if (_disposed || generation != (_generations[tabId] ?? 0)) {
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
    activate(tabId);
    if (entry.requestedUrl == url || entry.status.url == url) return;
    entry.requestedUrl = url;
    entry.status.url = url;
    entry.status.error = null;
    entry.status.isLoading = true;
    _notify();
    await entry.controller.loadRequest(uri!);
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
              entry.requestedUrl = request.url;
              entry.status.error = null;
            }
            return NavigationDecision.navigate;
          }
          if (request.url == 'about:blank') return NavigationDecision.navigate;
          if (request.isMainFrame &&
              uri != null &&
              {'mailto', 'tel', 'sms'}.contains(uri.scheme)) {
            if (entry.id == _activeId &&
                await confirm(
                  'Open another app?',
                  'This page wants to open your ${uri.scheme == 'mailto' ? 'email' : 'phone or messaging'} app.',
                ) &&
                !entry.closed &&
                !entry.crashed &&
                entry.id == _activeId &&
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
          if (entry.closed || entry.crashed || entry.status.error != null) {
            return;
          }
          entry.status.url = url;
          entry.status.isLoading = entry.status.error == null;
          entry.status.progress = 0;
          _updatePage(entry, false);
        },
        onPageFinished: (url) async {
          if (entry.closed || entry.crashed || entry.status.error != null) {
            return;
          }
          entry.status.url = url;
          entry.status.progress = 100;
          await _updatePage(entry, entry.status.error == null);
          if (!entry.closed && !entry.crashed && entry.status.url == url) {
            entry.status.isLoading = false;
            _notify();
          }
        },
        onUrlChange: (change) {
          if (entry.closed ||
              entry.crashed ||
              entry.status.error != null ||
              change.url == null ||
              !_isWebUri(Uri.tryParse(change.url!))) {
            return;
          }
          entry.status.url = change.url!;
          _updatePage(entry, false);
          _scheduleMetadataRefresh(entry);
        },
        onProgress: (progress) {
          if (entry.closed || entry.crashed) return;
          entry.status.progress = progress;
          _notify();
        },
        onWebResourceError: (error) {
          // WebKit reports ordinary stopped/superseded navigations as cancelled.
          if (defaultTargetPlatform == TargetPlatform.iOS &&
              error.errorCode == -999) {
            return;
          }
          if (entry.closed || entry.crashed || error.isForMainFrame == false) {
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
          if (entry.closed ||
              entry.crashed ||
              entry.id != _activeId ||
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
              entry.closed ||
              entry.crashed ||
              entry.id != _activeId ||
              entry.status.url != requestedUrl) {
            request.onCancel();
            return;
          }
          final password = await prompt(
            'Website password',
            'Password for ${request.host}',
            '',
          );
          if (password == null ||
              entry.closed ||
              entry.crashed ||
              entry.id != _activeId ||
              entry.status.url != requestedUrl) {
            request.onCancel();
            return;
          }
          request.onProceed(WebViewCredential(user: name, password: password));
        },
      ),
    );
    await c.setOnJavaScriptAlertDialog((request) async {
      if (entry.id == _activeId) {
        await confirm('Message from ${_host(entry)}', request.message);
      }
    });
    await c.setOnJavaScriptConfirmDialog((request) async {
      final url = entry.status.url;
      if (entry.closed || entry.crashed || entry.id != _activeId) return false;
      final answer = await confirm(
        'Confirm for ${_host(entry)}',
        request.message,
      );
      return answer &&
          !entry.closed &&
          !entry.crashed &&
          entry.id == _activeId &&
          entry.status.url == url;
    });
    await c.setOnJavaScriptTextInputDialog((request) async {
      final url = entry.status.url;
      if (entry.closed || entry.crashed || entry.id != _activeId) return '';
      final answer = await prompt(
        'Input for ${_host(entry)}',
        request.message,
        request.defaultText ?? '',
      );
      return !entry.closed &&
              !entry.crashed &&
              entry.id == _activeId &&
              entry.status.url == url
          ? answer ?? ''
          : '';
    });
    if (c.platform is AndroidWebViewController) {
      final android = c.platform as AndroidWebViewController;
      await android.setAllowFileAccess(false);
      await android.setMixedContentMode(MixedContentMode.neverAllow);
      await android.setMediaPlaybackRequiresUserGesture(true);
      await android.setOnShowFileSelector((params) async {
        final requestedUrl = entry.status.url;
        if (entry.closed || entry.crashed || entry.id != _activeId) return [];
        final files =
            await _nativeChannel.invokeListMethod<String>('chooseFiles', {
              'types': params.acceptTypes,
              'multiple': params.mode == FileSelectorMode.openMultiple,
            }) ??
            <String>[];
        return !entry.closed &&
                !entry.crashed &&
                entry.id == _activeId &&
                entry.status.url == requestedUrl
            ? files
            : <String>[];
      });
      await android.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          final requestedUrl = entry.status.url;
          final uri = Uri.tryParse(request.origin);
          final allowed =
              entry.id == _activeId &&
              uri?.scheme == 'https' &&
              await confirm(
                'Location access',
                '${uri!.host} wants your approximate location for this session.',
              ) &&
              !entry.closed &&
              !entry.crashed &&
              entry.id == _activeId &&
              entry.status.url == requestedUrl &&
              await _nativeChannel.invokeMethod<bool>('requestPermissions', {
                    'types': ['location'],
                  }) ==
                  true;
          return GeolocationPermissionsResponse(
            allow:
                allowed &&
                !entry.closed &&
                !entry.crashed &&
                entry.id == _activeId &&
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
    if (entry.closed ||
        entry.crashed ||
        entry.id != _activeId ||
        !entry.status.url.startsWith('https:') ||
        types.contains('unsupported')) {
      await request.deny();
      return;
    }
    final allowed = await confirm(
      'Website permission',
      'The page at ${_host(entry)} (including embedded content) wants to use your ${types.join(' and ')}. Allow for this request?',
    );
    if (!allowed ||
        entry.closed ||
        entry.crashed ||
        entry.id != _activeId ||
        entry.status.url != requestedUrl) {
      await request.deny();
      return;
    }
    try {
      if (await _nativeChannel.invokeMethod<bool>('requestPermissions', {
                'types': types,
              }) ==
              true &&
          !entry.closed &&
          !entry.crashed &&
          entry.id == _activeId &&
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
    if (entry.status.error != null) return;
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
    final entry = _entries[tabId];
    if (entry == null || entry.closed || entry.crashed) return;
    entry.status.error = null;
    await entry.controller.goBack();
    _scheduleMetadataRefresh(entry);
  }

  Future<void> forward(String tabId) async {
    final entry = _entries[tabId];
    if (entry == null || entry.closed || entry.crashed) return;
    entry.status.error = null;
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
              revision != entry.refreshRevision) {
            return;
          }
          try {
            final url = await entry.controller.currentUrl();
            if (entry.closed ||
                entry.crashed ||
                entry.status.error != null ||
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
    final entry = _entries[tabId];
    if (entry == null) return;
    if (entry.crashed) {
      final url = entry.status.url;
      await close(tabId);
      await open(
        tabId: tabId,
        url: url,
        isPrivate: entry.isPrivate,
        desktopMode: entry.desktopMode,
      );
      return;
    }
    final failedUrl = entry.status.error == null ? null : entry.status.url;
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
    final entry = _entries[tabId];
    if (entry == null) return;
    await _native('stop', entry);
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
    if (reload) await entry.controller.reload();
  }

  Future<void> close(String tabId) {
    // Invalidate an in-flight construction immediately, then release in order.
    _generations[tabId] = (_generations[tabId] ?? 0) + 1;
    return _enqueue(() => _closeNow(tabId));
  }

  Future<void> _closeNow(String tabId) async {
    final entry = _entries.remove(tabId);
    _recency.remove(tabId);
    if (entry == null) return;
    entry.closed = true;
    if (_activeId == tabId) _activeId = null;
    _notify();
    // Let Flutter unmount its platform view before releasing the native view.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    await _native('close', entry);
  }

  Future<void> clearData({
    bool cookies = true,
    bool cache = true,
    bool storage = true,
  }) => _enqueue(
    () => _clearDataNow(cookies: cookies, cache: cache, storage: storage),
  );

  Future<void> _clearDataNow({
    required bool cookies,
    required bool cache,
    required bool storage,
  }) async {
    for (final entry in _entries.values.toList()) {
      if (cache) {
        try {
          await entry.controller.clearCache();
        } catch (_) {}
      }
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
    for (final id in _entries.keys.toList()) {
      unawaited(close(id));
    }
    super.dispose();
  }
}
