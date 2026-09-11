import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../guard/guard_models.dart';
import 'reader_article.dart';
export 'reader_article.dart' show ReaderArticle;

const _nativeChannel = MethodChannel('wingman/browser');
typedef BrowserGuardRequest = GuardRequest;

/// Only local cleanup, incoming-address rejection and capture protection remain.
/// There is no website JavaScript bridge or content WebView plugin.
class NativeBrowserService {
  Future<void> setSensitiveContent(bool sensitive) async {
    if (!kIsWeb) {
      await _nativeChannel.invokeMethod<void>('setSensitiveContent', {
        'sensitive': sensitive,
      });
    }
  }

  /// Must complete before the new catalog is shown after a native upgrade.
  /// Android cancels only this app's unfinished OS downloads. Completed files
  /// are preserved. No view is created. Android deregisters old private
  /// profiles; the OS may finish their physical file deletion asynchronously.
  Future<void> quarantineLegacyContent() async {
    if (!kIsWeb) {
      await _nativeChannel
          .invokeMethod<void>('quarantineLegacyContent')
          .timeout(const Duration(seconds: 15));
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
    void rejectAddress(Object? value) {
      final uri = Uri.tryParse(value is String ? value : '');
      if (uri != null &&
          const ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          uri.toString().length <= 16384) {
        // The receiver may explain why this address is unavailable. This
        // callback cannot allocate a view or grant eligibility.
        onIncomingUri(uri);
      }
    }

    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'incomingUri') rejectAddress(call.arguments);
      if (call.method == 'message' && call.arguments is String) {
        onMessage?.call(call.arguments as String);
      }
      // Old renderer/download/Guard events cannot resurrect legacy content.
    });
    rejectAddress(await _nativeChannel.invokeMethod<String>('initialize'));
  }

  Future<bool> privateBrowsingAvailable() async => false;
  Future<bool> requestDefaultBrowser() async => false;

  void dispose() {
    if (!kIsWeb) _nativeChannel.setMethodCallHandler(null);
  }
}

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

/// Compatibility boundary for retired browser UI and stale navigation intents.
///
/// This class deliberately imports no WebView, URL launcher or network API.
/// No preference, policy payload, role, private flag, build mode or test callback
/// can enable a content renderer. The reviewed catalog uses Flutter plain text.
class BrowserEnginePool extends ChangeNotifier {
  BrowserEnginePool({
    required this.confirm,
    required this.prompt,
    required this.onPageChanged,
    required this.onMessage,
    this.navigationPolicy,
    this.onGuardBlock,
    this.onTrackersBlocked,
    this.beforeLoadForTesting,
  });

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

  static const supportsLiveBrowsing = false;
  static const maxLiveEngines = 0;
  static const unavailableMessage =
      'Live browsing is unavailable. Open a reviewed item in the bundled library.';
  final Map<String, BrowserPageStatus> _blocked = {};
  bool _disposed = false;
  Future<void>? _pendingSiteDataClear;

  bool get supportsReader => false;
  bool get isClearingSiteData => _pendingSiteDataClear != null;
  List<String> get liveTabIds => const [];
  int get liveEngineCount => 0;
  Widget? view(String tabId) => null;
  BrowserPageStatus status(String tabId) =>
      _blocked[tabId] ?? BrowserPageStatus();

  Future<void> open({
    required String tabId,
    required String url,
    required bool isPrivate,
    bool desktopMode = false,
  }) async {
    if (_disposed) return;
    // Do not evaluate a legacy allow/exception callback. Do not retain the
    // address or title: even metadata may contain unreviewed content.
    final decision = GuardDecision(
      action: GuardAction.blockUnsupported,
      host: '',
      ruleId: 'bundled-content-only',
    );
    _blocked[tabId] = BrowserPageStatus()
      ..progress = 100
      ..error = unavailableMessage
      ..guardDecision = decision;
    onGuardBlock?.call(decision, isPrivate);
    onMessage(
      isClearingSiteData
          ? 'Legacy site data is still being cleared. Live browsing is unavailable.'
          : unavailableMessage,
    );
    notifyListeners();
  }

  // Retired policy and lifecycle calls cannot change this capability boundary.
  Future<void> updateGuardPolicy(Map<String, Object?> policy) async {}
  Future<void> recheckGuard() async {}
  Future<void> retryGuard(String tabId) async {}
  void guardBlocked(Map<String, dynamic> event) {}
  void trackersBlocked(int nativeId, int count) {}
  void rendererGone(int nativeId) {}
  void activate(String tabId) {}
  Future<void> navigationSettled(int nativeId, String attemptedUrl) async {}
  Future<void> back(String tabId) async {}
  Future<void> forward(String tabId) async {}
  Future<void> reload(String tabId) async {}
  Future<void> stop(String tabId) async {}
  Future<void> find(String tabId, String query) async {}
  Future<void> findNext(String tabId, {bool forward = true}) async {}
  Future<void> setPageScale(int percentage) async {}
  Future<void> setDesktopMode(
    String tabId,
    bool enabled, {
    bool reload = true,
  }) async {}
  Future<ReaderArticle?> readArticle(String tabId) async => null;

  Future<void> close(String tabId) async {
    _blocked.remove(tabId);
    if (!_disposed) notifyListeners();
  }

  Future<void> clearData({
    bool cookies = true,
    bool cache = true,
    bool storage = true,
  }) async {
    if (_pendingSiteDataClear != null) {
      throw StateError('A previous site-data deletion is still pending.');
    }
    final operation = _pendingSiteDataClear =
        (() async {
          if (!kIsWeb) {
            await _nativeChannel.invokeMethod<void>('clearData', {
              'cookies': cookies,
              'cache': cache,
              'storage': storage,
            });
          }
        })().whenComplete(() {
          _pendingSiteDataClear = null;
          if (!_disposed) notifyListeners();
        });
    await operation.timeout(const Duration(seconds: 15));
  }

  /// The former annotation-only JavaScript hook is unconditionally disabled,
  /// including debug/test builds. No executable script crosses a native channel.
  @visibleForTesting
  Future<Object> evaluateForTesting(String tabId, String script) async =>
      throw UnsupportedError(unavailableMessage);

  @visibleForTesting
  Future<bool> terminateRendererForTesting(String tabId) async => false;

  @visibleForTesting
  Future<Map<String, dynamic>> platformStateForTesting(
    String tabId, {
    bool? shieldVisible,
  }) async => Map<String, dynamic>.from(
    await _nativeChannel.invokeMethod<Map>('capabilityState') ?? const {},
  );

  @override
  void dispose() {
    _disposed = true;
    _blocked.clear();
    super.dispose();
  }
}
